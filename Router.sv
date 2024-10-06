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
                regHolderLoad, clrPktHolder;
    pkt_t [3:0] inputRegOut, qOut, pktHolder, regOutToNode;
    logic [3:0][5:0] positionIn;
    logic [3:0][2:0] dataValidIn, dataValidOut, leastUsed, convertedDest;
    logic [3:0][3:0] took;
    logic [3:0][1:0] startNode, tookNode, previousNode;

    genvar inReg;
    genvar outReg;

    generate 
      for (inReg = 0; inReg < 4; inReg = inReg + 1) begin: inputSequence
        // Checks to see if packet has been fully received
        assign doneIn[inReg] = (dataValidIn[inReg] == 3'd4) ? 1 : 0;

        // Writes to FIFO once packet is fully recieved
        assign wrToQ[inReg] = (~put_inbound[inReg] && doneIn[inReg] && 
                               ~fullQueue[inReg]) ? 1 : 0;
        
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
          // if (leastUsed[outReg][0] == 0)
          //   startNode[outReg] = outReg + 2'd1;
          // else if (leastUsed[outReg][1] == 0)
          //   startNode[outReg] = outReg + 2'd2;
          // else if (leastUsed[outReg][2] == 0)
          //   startNode[outReg] = outReg + 2'd3;
          // else begin
          //   startNode[outReg] = outReg + 2'd1;
          // end
          
          startNode[outReg] = outReg + 2'd1;
          checkEqual0[outReg] = convertedDest[startNode[outReg]] == outReg;
          checkEqual1[outReg] = (convertedDest[(startNode[outReg] + 2'd1)] == 
                                  outReg);
          checkEqual2[outReg] = (convertedDest[(startNode[outReg] + 2'd2)] == 
                                  outReg);
        end

        outputDeciderFSM decide(.clock, .reset_n, 
                                .checkEqual0(checkEqual0[outReg]), 
                                .checkEqual1(checkEqual1[outReg]), 
                                .checkEqual2(checkEqual2[outReg]), 
                                .fullReg0(regFull[startNode[outReg]]), 
                                .fullReg1(regFull[startNode[outReg] + 2'd1]), 
                                .fullReg2(regFull[startNode[outReg] + 2'd2]), 
                                .free_outbound(free_outbound[outReg]),
                                .loadOut(loadOut[outReg]),
                                .dataValidOut(dataValidOut[outReg]),
                                .startNode(startNode[outReg]), 
                                .tookNode(tookNode[outReg]));

        always_ff @(posedge clock, negedge reset_n) begin
          if (~reset_n) begin
            regOutToNode[outReg] <= '0;
            took[outReg] <= '0;
            previousNode[outReg] <= 0;
            dataValidOut[outReg] <= 0;
            put_outbound[outReg] <= 0;
            leastUsed[outReg] <= '0;
          end
          else if (loadOut[outReg]) begin
            regOutToNode[outReg] <= pktHolder[tookNode[outReg]];
            took[outReg][tookNode[outReg]] <= 1;
            leastUsed[outReg][(((2'd3-outReg)+tookNode[outReg]) % 4)] <= 1;
            previousNode[outReg] <= tookNode[outReg];
            dataValidOut[outReg] <= dataValidOut[outReg] + 1;
            put_outbound[outReg] <= 0;
          end
          else if (free_outbound[outReg] && dataValidOut[outReg] == 1) begin
            took[outReg][previousNode[outReg]] <= 0;
            if (leastUsed[outReg] == 3'b111) begin
              leastUsed[outReg] <= '0;
            end
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
            if (leastUsed[outReg] == 3'b111)
              leastUsed[outReg] <= '0;
          end
        end
      end

    endgenerate

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

module outputDeciderFSM
  (input logic clock, reset_n, checkEqual0, checkEqual1, checkEqual2, fullReg0,
  fullReg1, fullReg2, free_outbound, 
  input logic [1:0] startNode,
  input logic [2:0] dataValidOut,
  output logic loadOut,
  output logic [1:0] tookNode);

  enum logic [2:0] {START, HOLD1, HOLD2, HOLD3, SEND} state, nextState;

  // Next State Logic and Output Logic
  always_comb begin
    unique case (state)
      START: begin
        if (checkEqual0 & fullReg0) begin
          loadOut = 1;
          tookNode = startNode;
          nextState = HOLD1;
        end
        else if (checkEqual1 & fullReg1) begin
          loadOut = 1;
          tookNode = startNode + 1;
          nextState = HOLD2;
        end
        else if (checkEqual2 & fullReg2) begin
          loadOut = 1;
          tookNode = startNode + 2;
          nextState = HOLD3;
        end
        else begin
          loadOut = 0;
          tookNode = startNode;
          nextState = START;
        end
      end
      HOLD1: begin
        loadOut = 0;
        nextState = (free_outbound) ? SEND : HOLD1;
      end
      HOLD2: begin
        loadOut = 0;
        nextState = (free_outbound) ? SEND : HOLD2;
      end
      HOLD3: begin
        loadOut = 0;
        nextState = (free_outbound) ? SEND : HOLD3;
      end
      SEND: begin
        loadOut = 0;
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