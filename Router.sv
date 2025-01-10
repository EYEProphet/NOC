`default_nettype none
`include "Router.svh"
`include "RouterPkg.pkg"

//////
////// Network on Chip (NoC) 18-341
////// Router module
//////
module Router #(parameter ROUTERID = 0) (
    input logic             clock, reset_n,

    input logic [3:0]       free_outbound,     // Node is free
    input logic [3:0]       put_inbound,       // Node is transferring to router
    input logic [3:0][7:0]  payload_inbound,   // Data sent from node to router

    output logic [3:0]      free_inbound,      // Router is free
    output logic [3:0]      put_outbound,      // Router is transferring to node
    output logic [3:0][7:0] payload_outbound); // Data sent from router to node

    logic [3:0] emptyQueue, fullQueue, wrToQ, reFromQ, doneIn, regFull, doneOut,
                checkEqual0, checkEqual1, checkEqual2, loadOut, updatedTook, 
                regHolderLoad, clrPktHolder, regBusy;
    pkt_t [3:0] inputRegOut, qOut, pktHolder, regOutToNode;
    logic [3:0][5:0] positionIn;
    logic [3:0][2:0] dataValidIn, dataValidOut, convertedDest, outLoad;
    logic [3:0][3:0] took;
    logic [3:0][1:0] startNode, tookNode, previousNode, checkNode0, checkNode1, 
                     checkNode2;

    genvar inReg;
    genvar outReg;

    generate 
      for (inReg = 0; inReg < 4; inReg = inReg + 1) begin: inputSequence
        // Checks to see if packet has been fully received
        assign doneIn[inReg] = (dataValidIn[inReg] == 3'd4) ? 1 : 0;

        // Writes to FIFO once packet is fully recieved
        assign wrToQ[inReg] = (~put_inbound[inReg] && doneIn[inReg] && 
                               ~fullQueue[inReg]) ? 1 : 0;
        
        // Reads from FIFO when queue register outside queue are empty
        assign reFromQ[inReg] = (~emptyQueue[inReg] && ~regFull[inReg]) ? 1 : 0;

        // Creates input buffers for router nodes
        always_ff @(posedge clock, negedge reset_n) begin
            if (~reset_n) begin
                inputRegOut[inReg] <= '0;
                positionIn[inReg] <= 24;
                free_inbound[inReg] <= 1;
                dataValidIn[inReg] <= '0;
            end
            else if (put_inbound[inReg]) begin
                inputRegOut[inReg] <= (inputRegOut[inReg] | 
                                       (payload_inbound[inReg] << 
                                        positionIn[inReg]));
                positionIn[inReg] <= positionIn[inReg] - 8;
                free_inbound[inReg] <= 0;
                dataValidIn[inReg] <= dataValidIn[inReg] + 1;
            end
            else if (~put_inbound[inReg] && doneIn[inReg] && fullQueue[inReg]) 
            begin
                free_inbound[inReg] <= 0;
            end
            else if (~put_inbound[inReg] && doneIn[inReg] && ~fullQueue[inReg]) 
            begin
                dataValidIn[inReg] <= '0;
                free_inbound[inReg] <= 0;
            end
            else begin
                free_inbound[inReg] <= 1;
                positionIn[inReg] <= 24;
                inputRegOut[inReg] <= '0;
            end   
        end

        // Stores packets read in from the input buffer
        biggerFIFO Q(.clock, .reset_n, .data_in(inputRegOut[inReg]), 
                     .we(wrToQ[inReg]), .re(reFromQ[inReg]), 
                     .data_out(qOut[inReg]), .full(fullQueue[inReg]), 
                     .empty(emptyQueue[inReg]));

        // Creates register to hold packet after reading from queue
        regHolderFSM holder(.clock, .reset_n, .emptyQueue(emptyQueue[inReg]), 
                            .took(updatedTook[inReg]), .full(regFull[inReg]), 
                            .load(regHolderLoad[inReg]), 
                            .clear(clrPktHolder[inReg]));
        always_ff @(posedge clock, negedge reset_n) begin
          if (~reset_n) begin
            pktHolder[inReg] <= '1;
          end
          else if (clrPktHolder[inReg]) begin
            pktHolder[inReg] <= '1;
          end
          else if (regHolderLoad[inReg]) begin
            pktHolder[inReg] <= qOut[inReg];
          end
        end
      end


      for (outReg = 2'd0; outReg < 3'd4; outReg = outReg + 1) 
      begin: outputSequence
        // Checks to see if packet has been fully received
        assign doneOut[outReg] = (dataValidOut[outReg] == 3'd4) ? 1 : 0;

        // Checks where each node is sending a packet to
        if (ROUTERID == 0)
          convertDest #(0) (.dest(pktHolder[outReg].dest), 
                                .newDest(convertedDest[outReg]));
        else
          convertDest #(1) (.dest(pktHolder[outReg].dest), 
                                .newDest(convertedDest[outReg]));

        always_comb begin 
          /* Ensures each output port in the router looks at the other input 
          ports without looking at themselves */
          checkNode0[outReg] = (outReg + 2'd1) % 4;
          if (((checkNode0[outReg] + 2'd1) % 4) == outReg) begin
            checkNode1[outReg] = checkNode0[outReg] + 2'd2;
            checkNode2[outReg] = checkNode0[outReg] + 2'd3;
          end
          else if (((checkNode0[outReg] + 2'd2) % 4) == outReg) begin
            checkNode1[outReg] = checkNode0[outReg] + 2'd1;
            checkNode2[outReg] = checkNode0[outReg] + 2'd3;
          end
          else begin
            checkNode1[outReg] = checkNode0[outReg] + 2'd1;
            checkNode2[outReg] = checkNode0[outReg] + 2'd2;
          end
          
          // Checks which ports out of the 3 are going to their output
          checkEqual0[outReg] = convertedDest[checkNode0[outReg]] == outReg;
          checkEqual1[outReg] = convertedDest[checkNode1[outReg]] == outReg;
          checkEqual2[outReg] = convertedDest[checkNode2[outReg]] == outReg;
        end
        
        /* Implements fairness and helps keep track of when output registers 
        should load*/
        outputArbiter access(.clock, .reset_n, .ready({checkEqual2[outReg], 
                                                         checkEqual1[outReg], 
                                                         checkEqual0[outReg]}),
                                               .busy(regBusy[outReg]), 
                                               .load(outLoad[outReg]));

        /* Depending on which port the out register is loading from this helps 
        to send that packet out*/ 
        outputDeciderFSM decide(.clock, .reset_n, .check(outLoad[outReg]),
                                .fullReg0(regFull[checkNode0[outReg]]), 
                                .fullReg1(regFull[checkNode1[outReg]]), 
                                .fullReg2(regFull[checkNode2[outReg]]), 
                                .free_outbound(free_outbound[outReg]),
                                .loadOut(loadOut[outReg]),
                                .dataValidOut(dataValidOut[outReg]),
                                .checkNode0(checkNode0[outReg]), 
                                .checkNode1(checkNode1[outReg]), 
                                .checkNode2(checkNode2[outReg]),
                                .regBusy(regBusy[outReg]), 
                                .tookNode(tookNode[outReg]));

        /* Uses the output decider fsm to properly load the packets, increment
        the packet counters, and output any communication signals needed to the 
        nodes/router ports*/
        always_ff @(posedge clock, negedge reset_n) begin
          if (~reset_n) begin
            regOutToNode[outReg] <= '0;
            took[outReg] <= '0;
            previousNode[outReg] <= 0;
            dataValidOut[outReg] <= 0;
            put_outbound[outReg] <= 0;
          end
          else if (loadOut[outReg]) begin
            regOutToNode[outReg] <= pktHolder[tookNode[outReg]];
            took[outReg][tookNode[outReg]] <= 1;
            previousNode[outReg] <= tookNode[outReg];
            dataValidOut[outReg] <= dataValidOut[outReg] + 1;
            put_outbound[outReg] <= 0;
          end
          else if (free_outbound[outReg] && dataValidOut[outReg] == 1) begin
            took[outReg][previousNode[outReg]] <= 0;
            put_outbound[outReg] <= 1;
            dataValidOut[outReg] <= dataValidOut[outReg] + 1;
            payload_outbound[outReg] <= {regOutToNode[outReg].src, 
                                          regOutToNode[outReg].dest};
          end
          else if (dataValidOut[outReg] == 2) begin
            put_outbound[outReg] <= 1; 
            dataValidOut[outReg] <= dataValidOut[outReg] + 1;
            payload_outbound[outReg] <= regOutToNode[outReg][23:16];
          end
          else if (dataValidOut[outReg] == 3) begin
            put_outbound[outReg] <= 1; 
            dataValidOut[outReg] <= dataValidOut[outReg] + 1;
            payload_outbound[outReg] <= regOutToNode[outReg][15:8];
          end
          else if (dataValidOut[outReg] == 4) begin
            payload_outbound[outReg] <= regOutToNode[outReg][7:0];
            dataValidOut[outReg] <= '0;
            put_outbound[outReg] <= 1; 
          end
          else begin
            put_outbound[outReg] <= 0;
            took[outReg][previousNode[outReg]] <= 0;
          end
        end
      end

    endgenerate
 
    /* Keeps a global took signal so that every register holding a value from 
    the queue knows if they are empty or not*/
    assign updatedTook = took[0] | took[1] | took[2] | took[3];

endmodule : Router

// Created a FIFO with a depth of 7 so that more packets can go into the router
module biggerFIFO #(parameter WIDTH=32) (
    input logic              clock, reset_n,
    input logic [WIDTH-1:0]  data_in,
    input logic              we, re,
    output logic [WIDTH-1:0] data_out,
    output logic             full, empty);

    logic [6:0][WIDTH-1:0] Q;
    logic [2:0] getPtr, putPtr;
    logic [2:0] lengthQ;

    always_comb begin
      empty = (lengthQ == 0);
      full = (lengthQ == 3'd7);

      if (re & ~empty) 
        data_out = Q[getPtr];
    end

    always_ff @(posedge clock, negedge reset_n) begin
      if (~reset_n) begin
        getPtr <= '0;
        putPtr <= '0;
        lengthQ <= '0;
        Q <= '0;
      end
      else if ((we && ~re && ~full) || (we && re && ~full && empty)) begin
        Q[putPtr] <= data_in;
        putPtr <= (putPtr == 3'd6) ? 3'd0 : putPtr + 1;
        lengthQ <= lengthQ + 1;
      end
      else if ((~we && re && ~empty) || (we && re && full && ~empty)) begin
        getPtr <= (getPtr == 3'd6) ? 3'd0 : getPtr + 1;
        lengthQ <= lengthQ - 1;
      end
      else if (we && re && ~full && ~empty) begin
        Q[putPtr] <= data_in;
        putPtr <= (putPtr == 3'd6) ? 3'd0 : putPtr + 1;
        getPtr <= (getPtr == 3'd6) ? 3'd0 : getPtr + 1;
      end
    end
endmodule : biggerFIFO

/* Converts the destination given from the node into a destination that 
correlates with the router ports*/
module convertDest #(parameter ROUTERID = 0) (
    input logic [3:0] dest,
    output logic [2:0] newDest);

    always_comb begin
      if (ROUTERID == 0) begin
        if (dest == 0) 
          newDest = 0;
        else if (dest == 1)
          newDest = 2;
        else if (dest == 2)
          newDest = 3;
        else if (dest == 3 || dest == 4 || dest == 5)
          newDest = 1;
        else
          newDest = 3'b111;
      end
      else begin
        if (dest == 0 || dest == 1 || dest == 2) 
          newDest = 3;
        else if (dest == 3)
          newDest = 0;
        else if (dest == 4)
          newDest = 1;
        else if (dest == 5)
          newDest = 2;
        else
          newDest = 3'b111;
      end
    end
endmodule: convertDest

/* FSM that controls when the register outside the queue can grab a value and
let's it know when it is full*/
module regHolderFSM
  (input logic clock, reset_n, emptyQueue, took,
  output logic full, load, clear);

  enum logic {GET, FULL} state, nextState;

  // Output logic
  assign full = ((state == FULL) && ~took) || ((state == GET) && ~emptyQueue);
  assign load = (state == GET) && ~emptyQueue;
  assign clear = (state == FULL) && took;
 
  // Next State Logic
  always_comb begin
    unique case (state)
      GET: nextState = (emptyQueue) ? GET : FULL; 
      FULL: nextState = (took) ? GET : FULL;
    endcase
  end

  // State Register
  always_ff @(posedge clock, negedge reset_n)
    if (~reset_n)
      state <= GET;
    else
      state <= nextState;

endmodule: regHolderFSM

/* FSM that helps send out the packet that is received based on the path taken
which is given by the output arbiter*/
module outputDeciderFSM
  (input logic clock, reset_n, fullReg0,
  fullReg1, fullReg2, free_outbound, 
  input logic [1:0] checkNode0, checkNode1, checkNode2,
  input logic [2:0] dataValidOut, check,
  output logic loadOut, regBusy,
  output logic [1:0] tookNode);

  enum logic [2:0] {START, HOLD1, HOLD2, HOLD3, SEND} state, nextState;

  // Next State Logic and Output Logic
  always_comb begin
    unique case (state)
      START: begin
        if (check[0] & fullReg0) begin
          loadOut = 1;
          tookNode = checkNode0;
          regBusy = 1;
          nextState = HOLD1;
        end
        else if (check[1] & fullReg1) begin
          loadOut = 1;
          tookNode = checkNode1;
          regBusy = 1;
          nextState = HOLD2;
        end
        else if (check[2] & fullReg2) begin
          loadOut = 1;
          tookNode = checkNode2;
          regBusy = 1;
          nextState = HOLD3;
        end
        else begin
          loadOut = 0;
          regBusy = 0;
          tookNode = checkNode0;
          nextState = START;
        end
      end
      HOLD1: begin
        loadOut = 0;
        regBusy = 1;
        nextState = (free_outbound) ? SEND : HOLD1;
      end
      HOLD2: begin
        loadOut = 0;
        regBusy = 1;
        nextState = (free_outbound) ? SEND : HOLD2;
      end
      HOLD3: begin
        loadOut = 0;
        regBusy = 1;
        nextState = (free_outbound) ? SEND : HOLD3;
      end
      SEND: begin
        loadOut = 0;
        regBusy = (dataValidOut == 3'd4) ? 0 : 1;
        nextState = (dataValidOut == 3'd4) ? START : SEND; 
      end

    endcase

  end

  // State Register
  always_ff @(posedge clock, negedge reset_n) begin
    if (~reset_n)
      state <= START;
    else
      state <= nextState;
  end
  
endmodule: outputDeciderFSM

/* Computes which port the output register will take and helps implements
fairness by keeping track of the path it is on and which ports were taken from
in that path*/
module outputArbiter
  (input logic clock, reset_n, busy,
  input logic [2:0] ready,
  output logic [2:0] load);

  logic [3:0][2:0] pathChecker;

  always_ff @(posedge clock, negedge reset_n) begin
    if (~reset_n) begin
      load <= '0;
      pathChecker <= '0;
    end
    else if (~busy) begin
      case (ready)
        3'b000: load <= '0;
        3'b001: load <= 3'b001;
        3'b010: load <= 3'b010;
        3'b011: begin
          if (pathChecker[0] == 2'd0)
            load <= 3'b001;
          else
            load <= 3'b010;
          pathChecker[0] <= (pathChecker[0] + 1) % 2;
        end
        3'b100: load <= 3'b100;
        3'b101: begin
          if (pathChecker[1] == 2'd0)
            load <= 3'b001;
          else
            load <= 3'b100;
          pathChecker[1] <= (pathChecker[1] + 1) % 2;
        end
        3'b110: begin
          if (pathChecker[2] == 2'd0)
            load <= 3'b010;
          else
            load <= 3'b100;
          pathChecker[2] <= (pathChecker[2] + 1) % 2;
        end
        3'b111: begin
          if (pathChecker[3] == 2'd0)
            load <= 3'b001;
          else if (pathChecker[3] == 2'd1)
            load <= 3'b010;
          else
            load <= 3'b100;
          pathChecker[3] <= (pathChecker[3] + 1) % 3;
        end
      endcase
    end
  end

endmodule: outputArbiter