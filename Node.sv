`default_nettype none
`include "Router.svh"
`include "RouterPkg.pkg"

//////
////// Network on Chip (NoC) 18-341
////// Node module
//////
module Node #(parameter NODEID = 0) (
  input logic clock, reset_n,

  //Interface to testbench: the blue arrows
  input  pkt_t pkt_in,        // Data packet from the TB
  input  logic pkt_in_avail,  // The packet from TB is available
  output logic cQ_full,       // The queue is full

  output pkt_t pkt_out,       // Outbound packet from node to TB
  output logic pkt_out_avail, // The outbound packet is available

  //Interface with the router: black arrows
  input  logic       free_outbound,    // Router is free
  output logic       put_outbound,     // Node is transferring to router
  output logic [7:0] payload_outbound, // Data sent from node to router

  output logic       free_inbound,     // Node is free
  input  logic       put_inbound,      // Router is transferring to node
  input  logic [7:0] payload_inbound); // Data sent from router to node

  logic takeFromBuf, emptyQueue;
  logic [31:0] dataReadToReg;
  pkt_t regOutToRouter;
  pkt_t regOutToTB;
  logic [2:0] dataValid;
  

  // Queue structure to store packets
  FIFO buffer(.clock, .reset_n, .data_in(pkt_in), .we(pkt_in_avail), 
              .re(takeFromBuf), .data_out(dataReadToReg), .full(cQ_full), 
              .empty(emptyQueue));

  assign takeFromBuf = (emptyQueue) ? 0 : 1;
  
  // Shift register for Node to Router
  always_ff @(posedge clock) begin
    if (~reset_n)
      regOutToRouter <= '0;
    else if (takeFromBuf && dataValid == 0)
      /* CHECK COMBINATIONAL READ FROM QUEUE CURRENTLY THE QUEUE HAS THE READ
      OUTPUT AVAILABLE ON THE NEXT CLOCK CYCLE */
      regOutToRouter <= dataReadToReg;
    else if (dataValid == 1)
      payload_outbound <= {regOutToRouter.src, regOutToRouter.desc};
    else if (dataValid == 2)
      payload_outbound <= regOutToRouter.data[23:16];
    else if (dataValid == 3)
      payload_outbound <= regOutToRouter.data[15:8];
    else if (dataValid == 4)
      payload_outbound <= regOutToRouter.data[7:0];
      dataValid <= '0;

  end

  // Shift register for Router to TB
  always_ff @(posedge clock) begin
    if (~reset_n)
      regOutToTB <= '0;
    else if ()
    

  end

endmodule : Node

/*
 *  Create a FIFO (First In First Out) buffer with depth 4 using the given
 *  interface and constraints
 *    - The buffer is initally empty
 *    - Reads are combinational, so data_out is valid unless empty is asserted
 *    - Removal from the queue is processed on the clock edge.
 *    - Writes are processed on the clock edge
 *    - If a write is pending while the buffer is full, do nothing
 *    - If a read is pending while the buffer is empty, do nothing
 */
module FIFO #(parameter WIDTH=32) (
    input logic              clock, reset_n,
    input logic [WIDTH-1:0]  data_in,
    input logic              we, re,
    output logic [WIDTH-1:0] data_out,
    output logic             full, empty);

    logic [WIDTH-1:0][3:0] Q;
    logic [1:0] getPtr, putPtr;
    logic [2:0] lengthQ;

    always_comb begin
      empty = (lengthQ == 0);
      full = (lengthQ == 3'd4);
      if ((~we && re && ~empty) || (we && re && full && ~empty) || 
          (we && re && ~full && ~empty)) 
        data_out = Q[getPtr];

    end

    always_ff @(posedge clock) begin
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
endmodule : FIFO
