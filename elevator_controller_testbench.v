`timescale 1ns / 1ps
// Elevator Controller Testbench

`timescale 1ns/1ps

module elevator_tb;
    // Inputs
    reg clk;
    reg rst_n;
    reg [3:0] floor;
    reg [15:0] up;
	reg [15:0] down;
    reg open;
    reg close;
    
    // Outputs
    wire dir;
    wire move;
    wire door_open;
    wire door_close;
    
    // DUT
    elevator_controller dut (
        .clk(clk),
        .rst_n(rst_n),
        .floor(floor),
        .up(up),
        .down(down),
        .open(open),
        .close(close),
        .dir(dir),
        .move(move),
        .door_open(door_open),
        .door_close(door_close)
    );
    
    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;
    
    // Display current floor (1-16 for readability)
    wire [4:0] current_floor_display = dut.current_floor + 1;
    
    // Monitor all state changes
    always @(posedge clk) begin
        $display("%6t: Floor=%2d State=%s Move=%b Dir=%s Door=%s | I_Req=%h", 
                $time, 
                current_floor_display,
                (dut.state == 2'b00) ? "IDLE" :
                (dut.state == 2'b01) ? "MVUP" :
                (dut.state == 2'b10) ? "MVDN" : "STOP",
                move,
                dir ? "UP" : "DN",
                door_open ? "OPEN " : "CLOSE",
                dut.internal_requests);
    end
    
    // Test sequence
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, elevator_tb);
        
        // Initialize
        $display("\n=== Elevator Test Starting ===");
        rst_n = 0;
      
      	up=16'h0001;
      	{down, open, close} = 0;
        #15 rst_n = 1;
        
        //=====================================
      	// TEST 0: Basic Movement Test
        //=====================================
      
        // Setup: Move to floors 5, 8, 12
      	$display("\n=== TEST 0: Basic Movement Test ===");
      	$display("    Setup: Request floors 5, 8, 12 ");
        
        floor = 4'd4;  // Floor 5
        #10 floor=4'd7; //Floor 8
        #10 floor = 4'd11; // Floor 12
        #10 floor = 4'd0;
        up=16'h0000;
        // Wait for floor 5
        while (current_floor_display != 5) @(posedge clk);
        $display(" --> Reached floor 5");
      	$display(" TEST 0 PASSED: Basic Movement Test");
        while (door_open) @(posedge clk);
        
        //=====================================
        // TEST 1: Direction Persistence
        //=====================================
        $display("\n=== TEST 1: Direction Persistence ===");
        $display("At floor 8, will request floors 14 and 3");
        
        // When we reach floor 8, add requests for 14 and 3
        while (current_floor_display != 8) @(posedge clk);
        $display("  --> At floor 8, adding requests");
        
        //@(posedge clk);
        floor = 4'd13; // Floor 14
        @(posedge clk);
        floor = 4'd2;  // Floor 3
        
        // Should go to 12 next
        while (current_floor_display != 12 ) @(posedge clk);
        $display("  --> Reached floor 12 (continued UP)");
        while (door_open) @(posedge clk);
        
        // Should go to 14 next
        while (current_floor_display != 14 ) @(posedge clk);
        $display("  --> Reached floor 14 (persisted UP)");
        while (door_open) @(posedge clk);
      	@(posedge clk);
        // Finally should go down to 3
        $display("  Now reversing to go to floor 3");
        while (current_floor_display != 3 ) @(posedge clk);
        $display("  --> Reached floor 3");
        
        $display("TEST 1 PASSED: Direction persistence works");
        
        //=====================================
        // TEST 2: Last Minute Request
        //=====================================
        $display("\n=== TEST 2: Last Minute Request ===");
        $display("Will request floor 11 when at floor 10");
      	$display("   --> Requesting Floors 12, 16 and later Floor 3");
      	// Going back up (To Floor 12, 16)
        @(posedge clk);
        floor = 4'd11; // Floor 12
        @(posedge clk);
        floor = 4'd15; //Floor 16
        
      	while (!(dut.current_floor == 4'd8 && dut.state == 2'b01)) @(posedge clk);
        floor <= 4'd10; // Floor 11
        @(posedge clk);
      	floor = 4'd2;	//Floor 3
        // Should stop at floor 11
      	repeat(2) @(posedge clk); // Checking after few cycles
        
        if (current_floor_display == 11 && door_open) begin
            $display("TEST 2 PASSED: Caught last-minute request");
        end else if (current_floor_display > 11) begin
            $display("TEST 2 FAILED: Missed the request, went past floor 11");
        end else begin
            $display("TEST 2 Status: Floor=%d State=%b", current_floor_display, dut.state);
        end
      	#100;
      	//=====================================
        // TEST 3: DOWNWARDS MOVEMENT TEST
        //=====================================
      	$display("\n=== TEST 3: DOWNWARDS MOVEMENT TEST ===");
      	$display("	--> Request for Floors 10,7");
        @(posedge clk);
        floor = 4'd9;//Floor 10
        @(posedge clk);
        floor = 4'd6;//Floor 7
      	while (current_floor_display != 10 ) @(posedge clk);
      	$display("  --> Reached floor 10 ");
      	
        while (!(dut.current_floor == 4'd6))@(posedge clk);
      	$display("  --> Reached floor 7 ");
      	$display("TEST 3 PASSED: Downwards Movement Test");
      
      	//=================================================
      	// TEST 4: DIRECTION PERSISTENCE TEST (DOWNWARDS)
        //=================================================
      	$display("\n=== TEST 4: DIRECTION PERSISTENCE TEST (DOWNWARDS) ===");
      	$display("  ---> Will request for Floor 11 at Floor 7");
        floor = 4'd10;//Floor 11
      	while (current_floor_display != 3 ) @(posedge clk);
      	$display("  --> Reached floor 3 (persisted DOWN)");
      	@(posedge clk);
      	$display("  Now reversing to go to floor 11");
      	while (current_floor_display != 11 ) @(posedge clk);
      	$display("  --> Reached floor 11");
        
      	$display("TEST 4 PASSED: Direction persistence works");
      
      	//=================================================
      	// TEST 5: SIMULTANEOUS INPUT TEST
        //=================================================
      	$display("\n=== TEST 5: SIMULTANEOUS INPUT TEST ===");
      $display("  ---> Will simultaneously request(external & internal) for Floor 13,8 at Floor 11 (When IDLE)");
      	$display("		To Check whether it caters to nearest input first or not");
      	#20;
      	up=16'h1000; floor=4'd7;
      	#10;
		up = 16'h0000;
      	while (current_floor_display != 13 ) @(posedge clk);
      	$display("  --> Reached floor 13 (Nearest) ");
      	@(posedge clk);
      	$display("  Now reversing to go to floor 8");
      	while (current_floor_display != 8 ) @(posedge clk);
      	$display("  --> Reached floor 8");
      
      	$display("TEST 5 PASSED: Serves Nearest Input First before reversing to next");
        //=====================================
        // End of tests
        //=====================================
        #40;
        $display("\n=== All Tests Completed ===");
        $finish;
    end
     
    // Timeout Check
    initial begin
        #5000;
        $display("\nERROR: Simulation timeout!");
        $finish;
    end
    
endmodule
