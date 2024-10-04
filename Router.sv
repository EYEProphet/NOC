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
                takeNode0, takeNode1, takeNode2, takeNode3;
    pkt_t [3:0] inputRegOut, qOut, pktHolder, regOutToNode;
    logic [3:0][5:0] positionIn;
    logic [3:0][2:0] dataValidIn, dataValidOut;

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
        always_ff @(posedge clock, negedge reset_n) begin
          if (~reset_n) begin
            pktHolder[inReg] <= '0;
            regFull[inReg] <= 0;
          end
          else if (~emptyQueue[inReg] && ~regFull[inReg]) begin
            pktHolder[inReg] <= qOut[inReg];
            regFull[inReg] <= 1;
          end
        end
      end

      for (outReg = 0; outReg < 4; outReg = outReg + 1) begin: outputSequence
        // Checks to see if packet has been fully received
        assign doneOut[outReg] = (dataValidOut[outReg] == 3'd4) ? 1 : 0;

        // Checks where each node is sending a packet to
        assign takeNode0[outReg] = (pktHolder[outReg].dest == 4'd0) ? 1 : 0;
        assign takeNode1[outReg] = (pktHolder[outReg].dest == 4'd1) ? 1 : 0;
        assign takeNode2[outReg] = (pktHolder[outReg].dest == 4'd2) ? 1 : 0;
        assign takeNode3[outReg] = (pktHolder[outReg].dest == 4'd3) ? 1 : 0;
        
        always_ff @(posedge clock, negedge reset_n) begin
            if (reset_n) begin
              regOutToNode[outReg] <= '0;
              dataValidOut[outReg] <= '0;
              put_outbound[outReg] <= 0;
            end
            else if (dataValidOut[outReg] == 0) begin
              put_outbound[outReg] <= 0;
              if (takeNode0[outReg] && regFull[0]) begin
                regOutToNode[outReg] <= pktHolder[0];
                regFull[0] <= 0;
                dataValidOut[outReg] <= dataValidOut[outReg] + 1;
              end
              else if (takeNode1[outReg] && regFull[1]) begin
                regOutToNode[outReg] <= pktHolder[1];
                regFull[1] <= 0;
                dataValidOut[outReg] <= dataValidOut[outReg] + 1;
              end
              else if (takeNode2[outReg] && regFull[2]) begin
                regOutToNode[outReg] <= pktHolder[2];
                regFull[2] <= 0;
                dataValidOut[outReg] <= dataValidOut[outReg] + 1;
              end
              else if (takeNode3[outReg] && regFull[3]) begin
                regOutToNode[outReg] <= pktHolder[3];
                regFull[3] <= 0;
                dataValidOut[outReg] <= dataValidOut[outReg] + 1;
              end
            end
            else if (free_outbound[outReg] && dataValidOut[outReg] == 1) begin
              payload_outbound[outReg] <= {regOutToNode[outReg].src, 
                                           regOutToNode[outReg].dest};
              dataValidOut[outReg] <= dataValidOut[outReg] + 1;
              put_outbound[outReg] <= 1; 
            end
            else if (dataValidOut[outReg] == 2) begin
              payload_outbound[outReg] <= regOutToNode[outReg][23:16];
              dataValidOut[outReg] <= dataValidOut[outReg] + 1;
              put_outbound[outReg] <= 1; 
            end
            else if (dataValidOut[outReg] == 3) begin
              payload_outbound[outReg] <= regOutToNode[outReg][15:8];
              dataValidOut[outReg] <= dataValidOut[outReg] + 1;
              put_outbound[outReg] <= 1; 
            end
            else if (dataValidOut[outReg] == 4) begin
              payload_outbound[outReg] <= regOutToNode[outReg][7:0];
              dataValidOut[outReg] <= '0;
              put_outbound[outReg] <= 1; 
            end
        end

      end


    endgenerate

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
        putPtr <= putPtr + 1;
        lengthQ <= lengthQ + 1;
      end
      else if ((~we && re && ~empty) || (we && re && full && ~empty)) begin
        getPtr <= getPtr + 1;
        lengthQ <= lengthQ - 1;
      end
      else if (we && re && ~full && ~empty) begin
        Q[putPtr] <= data_in;
        putPtr <= putPtr + 1;
        getPtr <= getPtr + 1;
      end
    end
endmodule : biggerFIFO