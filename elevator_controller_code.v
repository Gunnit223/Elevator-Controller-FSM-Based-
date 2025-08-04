module elevator_controller (
    input clk,
    input rst_n,
    input [3:0] floor,
    input [15:0] up,
    input [15:0] down,
    input open,
    input close,
    
    output reg dir,
    output reg move,
    output reg door_open,
    output reg door_close
);

localparam IDLE         = 2'b00;
localparam MOVING_UP    = 2'b01;
localparam MOVING_DOWN  = 2'b10;
localparam DOOR_STOP    = 2'b11;

reg [1:0] state;
reg [3:0] current_floor;
reg current_direction;
reg [4:0] nearest;
reg [15:0] internal_requests;
reg [15:0] external_up_requests;
reg [15:0] external_down_requests;

always @(posedge clk) begin
    if (!rst_n) begin
        internal_requests <= 16'b0;
        external_up_requests <= 16'b0;
        external_down_requests <= 16'b0;
    end
    else begin
        if (floor <= 4'd15) begin  
            internal_requests[floor] <= 1'b1;
        end
        //Masked Up and Down Requests
        external_up_requests <= {1'b0, external_up_requests[14:0] | up[14:0]};
        external_down_requests <= {external_down_requests[15:1] | down[15:1], 1'b0};
    end
end
//Store all Requests
wire [15:0] all_requests = internal_requests | external_up_requests | external_down_requests;
wire has_any_request = |all_requests; //Flag to check for any active requests

function has_requests_above;
    input [3:0] from_floor;
    begin
        if (from_floor >= 4'd15)
            has_requests_above = 0;
        else
            has_requests_above = |(all_requests & (16'hFFFF << (from_floor + 1)));
    end
endfunction

function has_requests_below;
    input [3:0] from_floor;
    begin
        if (from_floor == 4'd0)
            has_requests_below = 0;
        else
            has_requests_below = |(all_requests & ~(16'hFFFF << from_floor));
    end
endfunction
  
//Function to check if Lift should stop at the present floor
function should_stop_at_floor;
    input [3:0] check_floor;
    input check_direction;//Direction-> Up:1 and Down:0
    begin
        should_stop_at_floor = 
            internal_requests[check_floor] |
            (external_up_requests[check_floor] & check_direction) |
            (external_down_requests[check_floor] & ~check_direction);
    end
endfunction
//Function to find the nearest Request
function [4:0] find_nearest_request;
    input [3:0] curr_floor;
    reg [4:0] i;
    reg found_up, found_down;
    reg [3:0] up_dist, down_dist;
    begin
        found_up = 0;
        found_down = 0;
        up_dist = 4'hF;
        down_dist = 4'hF;
        //Check Up
        for (i = 0; i <= 15; i = i + 1) begin
            if (!found_up && i >= curr_floor + 1) begin
                if (all_requests[i]) begin
                    up_dist = i - curr_floor;
                    found_up = 1;
                end
            end
        end
        //Check Down
      for (i = 15; i >= 0; i = i - 1) begin
            if (!found_down && i <= curr_floor - 1) begin
                if (all_requests[i]) begin
                    down_dist = curr_floor - i;
                    found_down = 1;
                end
            end
        end
        //Then compare both distances
        if (!found_up && !found_down)
            find_nearest_request = 5'b00000;
        else if (!found_up)
            find_nearest_request = {1'b1, 1'b0, down_dist[2:0]};
        else if (!found_down)
            find_nearest_request = {1'b1, 1'b1, up_dist[2:0]};
        else
            find_nearest_request = (up_dist <= down_dist) ? 
                {1'b1, 1'b1, up_dist[2:0]} : {1'b1, 1'b0, down_dist[2:0]};
      //Format: {found something, found up/ found down, distance}
    end
endfunction

always @(posedge clk) begin
    if (!rst_n) begin
        state <= IDLE;
        current_floor <= 4'd0;
        current_direction <= 1'b1;//Default Inital Direction: Up
    end
    else begin
        case (state)
            IDLE: begin
                if (has_any_request) begin
                    if (should_stop_at_floor(current_floor, current_direction)) begin
                        state <= DOOR_STOP;
                    end
                    else begin
                        nearest = find_nearest_request(current_floor);
                        if (nearest[4]) begin
                            current_direction <= nearest[3];
                            state <= nearest[3] ? MOVING_UP : MOVING_DOWN;
                        end
                    end
                end
            end
            
            MOVING_UP: begin
              	//If At MAX-1 Floor: Check if it should STOP or Keep Going Up
                if (current_floor < 4'd15) begin
                    if (should_stop_at_floor(current_floor, 1'b1)) begin
                        state <= DOOR_STOP;
                    end
                    else begin
                        current_floor <= current_floor + 1;
                    end
                end
              	//When reached Max Floor, it should move to door_stop
                else begin
                    if (should_stop_at_floor(current_floor, 1'b1)) begin
                        state <= DOOR_STOP;
                    end
                    else if (!has_requests_above(current_floor)) begin
                        state <= DOOR_STOP;
                    end
                end
            end
            
            MOVING_DOWN: begin
                if (current_floor > 4'd0) begin
                    if (should_stop_at_floor(current_floor, 1'b0)) begin
                        state <= DOOR_STOP;
                    end
                    else begin
                        current_floor <= current_floor - 1;
                    end
                end
              	//If at Lowest Floor: Check for destination and STOP
                else begin
                    if (should_stop_at_floor(current_floor, 1'b0)) begin
                        state <= DOOR_STOP;
                    end
                    else if (!has_requests_below(current_floor)) begin
                        state <= DOOR_STOP;
                    end
                end
            end
            
            DOOR_STOP: begin
                internal_requests[current_floor] <= 1'b0;
                //Deassert the request for that floor on reaching
                if (current_direction)
                    external_up_requests[current_floor] <= 1'b0;
                else
                    external_down_requests[current_floor] <= 1'b0;
                //Handling Open and Close inputs
                if (open && !close) begin
                    state <= DOOR_STOP;
                end
                else begin
                    if (current_direction && has_requests_above(current_floor)) begin
                        state <= MOVING_UP;
                    end
                    else if (!current_direction && has_requests_below(current_floor)) begin
                        state <= MOVING_DOWN;
                    end
                    else if (has_requests_below(current_floor)) begin
                        current_direction <= 1'b0;
                        state <= MOVING_DOWN;
                    end
                    else if (has_requests_above(current_floor)) begin
                        current_direction <= 1'b1;
                        state <= MOVING_UP;
                    end
                    else begin
                        state <= IDLE;
                    end
                end
            end
        endcase
    end
end

always_comb begin
    move = 1'b0;
    dir = current_direction;
    door_open = 1'b0;
    door_close = 1'b0;
    
    case (state)
        MOVING_UP, MOVING_DOWN: begin
            move = 1'b1;
            dir = (state == MOVING_UP);
            door_close = 1'b1;
        end
        
        DOOR_STOP: begin
            door_open = 1'b1;
        end
        
        IDLE: begin
            door_close = 1'b1;
        end
    endcase
end

endmodule
