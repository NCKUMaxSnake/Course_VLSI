`include "AXI_define.svh"
// `include "../include/AXI_define.svh"
module ROM_wrapper (
    input clk,
    input rst,

    // WRITE ADDRESS
    input [`AXI_IDS_BITS-1:0] AWID,
    input [`AXI_ADDR_BITS-1:0] AWADDR,
    input [`AXI_LEN_BITS-1:0] AWLEN,
    input [`AXI_SIZE_BITS-1:0] AWSIZE,
    input [1:0] AWBURST,
    input AWVALID,
    output logic AWREADY,
    // WRITE DATA
    input [`AXI_DATA_BITS-1:0] WDATA,
    input [`AXI_STRB_BITS-1:0] WSTRB,
    input WLAST,
    input WVALID,
    output logic WREADY,
    // WRITE RESPONSE
    output logic [`AXI_IDS_BITS-1:0] BID,
    output logic [1:0] BRESP,
    output logic BVALID,
    input BREADY,

    // READ ADDRESS
    input [`AXI_IDS_BITS-1:0] ARID,
    input [`AXI_ADDR_BITS-1:0] ARADDR,
    input [`AXI_LEN_BITS-1:0] ARLEN,
    input [`AXI_SIZE_BITS-1:0] ARSIZE,
    input [1:0] ARBURST,
    input ARVALID,
    output logic ARREADY,
    // READ DATA
    output logic [`AXI_IDS_BITS-1:0] RID,
    output logic [`AXI_DATA_BITS-1:0] RDATA,
    output logic [1:0] RRESP,
    output logic RLAST,
    output logic RVALID,
    input RREADY,

    output logic ROM_enable,
    output logic ROM_read,
    output logic [`AXI_ADDR_BITS-1:0] ROM_address,
    input [`AXI_DATA_BITS-1:0] ROM_out

);
    logic [13:0] A;
    logic [`AXI_DATA_BITS-1:0] DI;
    logic [`AXI_DATA_BITS-1:0] DO;
    logic [`AXI_STRB_BITS-1:0] WEB;
    logic CS;
    logic OE;

    //assign ROM inoutput
    assign ROM_enable = CS;
    assign ROM_read = OE;
    assign ROM_address = {18'b0,A};
    assign DO = ROM_out;

    logic AR_done, R_done, AW_done, W_done, B_done;
    assign AR_done = ARVALID & ARREADY;
    assign R_done  = RVALID & RREADY;
    assign AW_done = AWVALID & AWREADY;
    assign W_done  = WVALID & WREADY;
    assign B_done  = BVALID & BREADY;

    logic R_done_last, W_done_last;
    assign R_done_last = RLAST & R_done;
    assign W_done_last = WLAST & W_done;

    logic [1:0] slave_status, next_status;
    parameter [1:0] S_address    = 2'b00,
                    S_read_data  = 2'b01,
                    S_write_data = 2'b10,
                    S_response   = 2'b11;

    always_ff @(posedge clk or negedge rst) begin
        if(~rst) begin
            slave_status <= S_address;
        end else begin
             slave_status <= next_status;
        end
    end

    always_comb begin
        case(slave_status)
            S_address: begin
                if(AW_done & W_done)
                    next_status = S_response;
                else if(AW_done)
                    next_status = S_write_data;
                else if(AR_done)
                    next_status = S_read_data;
                else
                    next_status = S_address;
            end
            S_read_data: begin
                if(R_done_last & AW_done)
                    next_status = S_write_data;
                else if(R_done_last & AR_done)
                    next_status = S_read_data;
                else if(R_done_last)
                    next_status = S_address;
                else
                    next_status = S_read_data;
            end
            S_write_data: begin
                if(W_done_last)
                    next_status = S_response;
                else
                    next_status = S_write_data;
            end
            default/*S_response*/: begin
                if(B_done & AW_done)
                    next_status = S_write_data;
                else if(B_done & AR_done)
                    next_status = S_read_data;
                else if(B_done)
                    next_status = S_address;
                else
                    next_status = S_response;
            end
        endcase // slave_status
    end

    // assign AWREADY = (slave_status == S_address)? 1'b1:1'b0;
    // assign ARREADY = ((slave_status == S_address) & ~AWVALID)? 1'b1:1'b0;
    always_comb begin
        case (slave_status)
            S_address:
                AWREADY = 1'b1;
            S_response:
                AWREADY = B_done;
            S_read_data:
                AWREADY = R_done;
            default : /* default */
                AWREADY = 1'b0;
        endcase
    end

    logic delay;
    always_ff @(posedge clk or negedge rst) begin
        if(~rst) begin
            delay <= 1'b0;
        end else begin
            delay <= ARVALID;
        end
    end

    always_comb begin
        case (slave_status)
            S_address:
                ARREADY = ~AWVALID & delay;
            S_response:
                ARREADY = 1'b0;
            S_read_data:
                ARREADY = 1'b0;
            default:/* default */
                ARREADY = 1'b0;
        endcase
    end
    assign WREADY = (slave_status == S_write_data)? 1'b1:1'b0;
    assign BVALID = (slave_status == S_response)? 1'b1:1'b0;
    assign RVALID = (slave_status == S_read_data)? 1'b1:1'b0;

    assign RRESP = `AXI_RESP_OKAY;
    assign BRESP = `AXI_RESP_OKAY;

    logic [`AXI_IDS_BITS-1:0] reg_ARID, reg_AWID;
    always_ff @(posedge clk or negedge rst) begin
        if(~rst) begin
            reg_ARID <= `AXI_IDS_BITS'b0;
            reg_AWID <= `AXI_IDS_BITS'b0;
        end else begin
            reg_ARID <= (AR_done)? ARID:reg_ARID;
            reg_AWID <= (AW_done)? AWID:reg_AWID;
        end
    end

    assign RID = reg_ARID;
    assign BID = reg_AWID;

    logic [`AXI_LEN_BITS-1:0] reg_ARLEN, reg_AWLEN;
    always_ff @(posedge clk or negedge rst) begin
        if(~rst) begin
            reg_ARLEN <= `AXI_LEN_BITS'b0;
            reg_AWLEN <= `AXI_LEN_BITS'b0;
        end else begin
            reg_ARLEN <= (AR_done)? ARLEN:reg_ARLEN;
            reg_AWLEN <= (AW_done)? AWLEN:reg_AWLEN;
        end
    end

    logic [`AXI_LEN_BITS-1:0] cnt;

    always_ff @(posedge clk or negedge rst) begin
        if (~rst) begin
            cnt <= `AXI_LEN_BITS'h0;
        end
        else begin
            case (slave_status)
                S_read_data: cnt <= (R_done_last)? `AXI_LEN_BITS'b0:((R_done)? cnt+`AXI_LEN_BITS'b1:cnt);
                S_write_data:cnt <= (W_done_last)? `AXI_LEN_BITS'b0:((W_done)? cnt+`AXI_LEN_BITS'b1:cnt);
            endcase
        end
    end
    assign RLAST = (reg_ARLEN == cnt);

    // logic reg_RVALID;
    // always_ff @(posedge clk or negedge rst) begin
    //     if(~rst) begin
    //         reg_RVALID <= 1'b0;
    //     end else begin
    //         reg_RVALID <= RVALID;
    //     end
    // end

    // logic [`AXI_DATA_BITS-1:0] reg_RDATA;
    // always_ff @(posedge clk or negedge rst) begin
    //     if (~rst)begin
    //         reg_RDATA <= `AXI_DATA_BITS'b0;
    //     end
    //     else begin
    //         reg_RDATA <= (RVALID & ~reg_RVALID)? DO : reg_RDATA;
    //     end
    // end

    // Max 1125 modify
    assign RDATA = DO; // (RVALID & reg_RVALID)? reg_RDATA:DO;

    assign WEB = WSTRB;
    assign DI = WDATA;
    // assign OE = (slave_status == S_read_data)? 1'b1:1'b0; // f
    always_comb begin
        case (slave_status)
            S_address:
                OE = ~AWVALID & AR_done | delay;
            S_read_data:
                OE = 1'b1;
            default : /* default */
                OE = 1'b0;
        endcase
    end

    always_comb begin
        case (slave_status)
            S_address:
                CS = AWVALID | ARVALID;
            default : /* default */
                CS = 1'b1;
        endcase
    end

    // assign CS = ((slave_status == S_address) & ~(AWVALID | ARVALID))? 1'b0: 1'b1;
    // assign A = (AW_done)? AWADDR[15:2]:ARADDR[15:2];

    // logic [1:0] cnt;
    // always_ff @(posedge clk or negedge rst) begin
    //     if(~rst) begin
    //         cnt <= 2'b0;
    //     end else begin
    //         if((slave_status == S_read_data) & R_done) begin
    //             if(R_done_last)
    //                 cnt <= 2'b0;
    //             else
    //                 cnt <= cnt + 2'b1;
    //         end
    //     end
    // end

    logic [13:0] reg_RADDR, reg_WADDR;
    logic [1:0] A_offset;
    assign A_offset = (cnt[1:0] == 2'b0)? ((R_done)? cnt[1:0] + 2'b1: cnt[1:0]):cnt[1:0] + 2'b1;

    always_ff @(posedge clk or negedge rst) begin
        if (~rst) begin
            reg_RADDR  <= 14'b0;
            reg_WADDR  <= 14'b0;
        end
        else begin
            reg_RADDR  <= AR_done? ARADDR[15:2] : reg_RADDR;
            reg_WADDR  <= AW_done? AWADDR[15:2] : reg_WADDR;
        end
    end

    always_comb begin
        case(slave_status)
            S_address   :
                A = (AW_done)? AWADDR[15:2]:ARADDR[15:2] + delay;
            S_read_data :
                A = reg_RADDR + A_offset + 1'b1;
            S_write_data:
                A = reg_WADDR;
            default:
                /*S_response*/
                A = ~B_done? reg_WADDR:(AW_done ? AWADDR[15:2]:ARADDR[15:2]);
        endcase
    end

endmodule