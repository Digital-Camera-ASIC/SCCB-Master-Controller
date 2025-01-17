/* 
-----------------------------|----------------
     Register name           |       Adress
-----------------------------|----------------
SCCB CLK PRESCALER           |   32'h3000_0000
-----------------------------|----------------

Operator in Configuration registers region  (set AXI4_CTRL_CONF=1)
    - Write:    Write the data to the configuration registers
    - Read:     Return the data of the configuration registers 
Operator in Write-streaming region          (set AXI4_CTRL_WR_ST=1)
    - Write:    Streaming data to the slave 
    - Read:     Return number of data in the write-streaming FIFO 
Operator in Read-streaming region           (set AXI4_CTRL_RD_ST=1)
    - Write:    Can't access 
    - Read:     Return the data, which is received from the slave 
*/
module axi4_ctrl
#(
    // AXI4 Controller type
    parameter AXI4_CTRL_CONF    = 1,                // AXI4-Configuration-Register  || 0: Disable || 1: Enable
    parameter AXI4_CTRL_WR_ST   = 1,                // AXI4-Write-Data-Streaming    || 0: Disable || 1: Enable
    parameter AXI4_CTRL_RD_ST   = 1,                // AXI4-Read-Data-Streaming     || 0: Disable || 1: Enable
    // AXI4 (configuration segment) Interface
    parameter CONF_BASE_ADDR    = 32'h2000_0000,    // Memory mapping - BASE
    parameter CONF_OFFSET       = 32'h01,           // Memory mapping - OFFSET ---> Address (byte-access) = (base + offset*n)
    parameter CONF_REG_NUM      = 32'd8,            // Number of configuration registers
    // AXI4 (write-data-streaming segment) Interface
    parameter ST_WR_BASE_ADDR   = 32'h2100_0000,    // Memory mapping - BASE
    parameter ST_WR_OFFSET      = 32'h01,           // Memory mapping - OFFSET ---> Address (byte-access) = (base + offset*n)
    parameter ST_WR_FIFO_NUM    = 32'd02,           // Number of write-data-streaming FIFO
    parameter ST_WR_FIFO_DEPTH  = 4,                // Depth of each write-data-streaming FIFO
    // AXI4 (read-data-streaming segment) Interface
    parameter ST_RD_BASE_ADDR   = 32'h2200_0000,    // Memory mapping - BASE
    parameter ST_RD_OFFSET      = 32'h01,           // Memory mapping - OFFSET ---> Address (byte-access) = (base + offset*n)
    parameter ST_RD_FIFO_NUM    = 32'd02,           // Number of read-data-streaming FIFO
    parameter ST_RD_FIFO_DEPTH  = 4,                // Depth of each read-data-streaming FIFO
    // Common
    parameter DATA_W            = 8,
    parameter ADDR_W            = 32,
    parameter MST_ID_W          = 5,
    parameter TRANS_DATA_LEN_W  = 8,
    parameter TRANS_DATA_SIZE_W = 3,
    parameter TRANS_RESP_W      = 2,
    
    // IP Configuration
    // -- For Configuration Registers mode
    parameter CONF_ADDR_W       = $clog2(CONF_REG_NUM),
    parameter CONF_DATA_W       = CONF_OFFSET*8,     // Byte-access
    // -- For Write-Data-Streaming mode
    parameter ST_WR_ADDR_W      = $clog2(ST_WR_FIFO_NUM),
    // -- For Read-Data-Streaming mode
    parameter ST_RD_ADDR_W      = $clog2(ST_RD_FIFO_NUM)
)
(   
    // Input declaration
    // -- Global 
    input                                   clk,
    input                                   rst_n,

    // -- to AXI4 Master            
    // -- -- AW channel         
    input   [MST_ID_W-1:0]                  m_awid_i,
    input   [ADDR_W-1:0]                    m_awaddr_i,
    input   [TRANS_DATA_LEN_W-1:0]          m_awlen_i,
    input                                   m_awvalid_i,
    // -- -- W channel          
    input   [DATA_W-1:0]                    m_wdata_i,
    input                                   m_wlast_i,
    input                                   m_wvalid_i,
    // -- -- B channel          
    input                                   m_bready_i,
    // -- -- AR channel         
    input   [MST_ID_W-1:0]                  m_arid_i,
    input   [ADDR_W-1:0]                    m_araddr_i,
    input   [TRANS_DATA_LEN_W-1:0]          m_arlen_i,
    input                                   m_arvalid_i,
    // -- -- R channel          
    input                                   m_rready_i,
    // -- -- For Write-streaming FIFO 
    input   [ST_WR_FIFO_NUM-1:0]            wr_st_rd_vld_i,
    // -- -- For Read-streaming FIFO
    input   [DATA_W*ST_RD_FIFO_NUM-1:0]     rd_st_wr_data_i,
    input   [ST_RD_FIFO_NUM-1:0]            rd_st_wr_vld_i,
    // Output declaration           
    // -- -- AW channel         
    output                                  m_awready_o,
    // -- -- W channel          
    output                                  m_wready_o,
    // -- -- B channel          
    output  [MST_ID_W-1:0]                  m_bid_o,
    output  [TRANS_RESP_W-1:0]              m_bresp_o,
    output                                  m_bvalid_o,
    // -- -- AR channel         
    output                                  m_arready_o,
    // -- -- R channel          
    output  [DATA_W-1:0]                    m_rdata_o,
    output  [TRANS_RESP_W-1:0]              m_rresp_o,
    output                                  m_rlast_o,
    output                                  m_rvalid_o,
    // -- -- For Configuration register
    output  [CONF_DATA_W*CONF_REG_NUM-1:0]  conf_reg_o,
    // -- -- For Write-streaming FIFO 
    output  [DATA_W*ST_WR_FIFO_NUM-1:0]     wr_st_rd_data_o,
    output  [ST_WR_FIFO_NUM-1:0]            wr_st_rd_rdy_o,
    // -- -- For Read-streaming FIFO
    output  [ST_RD_FIFO_NUM-1:0]            rd_st_wr_rdy_o
);
    // Local parameters 
    localparam CONF_OFFSET_W    = $clog2(CONF_OFFSET);
    localparam ST_WR_DAT_CNT_W  = $clog2(ST_WR_FIFO_DEPTH);
    localparam AW_INFO_W        = MST_ID_W + ADDR_W;
    localparam W_INFO_W         = DATA_W + 1;                           // DATA width + W_LAST
    localparam B_INFO_W         = MST_ID_W + TRANS_RESP_W;
    localparam AR_INFO_W        = MST_ID_W + TRANS_DATA_LEN_W + ADDR_W; // MST_ID + ARLEN + ADDR
    localparam R_INFO_W         = DATA_W + 1 + TRANS_RESP_W;            // DATA + R_LAST + R_RESP
    
    // Internal variables 
    genvar conf_idx;
    genvar fifo_idx;
    // Internal signal
    // -- wire
    // -- -- Common
    wire [AW_INFO_W-1:0]        bwd_aw_info;
    
    wire [R_INFO_W-1:0]         bwd_r_info;
    wire [DATA_W-1:0]           bwd_rdata;
    wire [TRANS_RESP_W-1:0]     bwd_rresp;
    wire                        bwd_rlast;
    wire                        bwd_r_vld;
    wire                        bwd_r_rdy;
    wire [R_INFO_W-1:0]         fwd_r_info;
    
    wire [B_INFO_W-1:0]         bwd_b_info;
    wire [MST_ID_W-1:0]         bwd_b_bid;
    wire [TRANS_RESP_W-1:0]     bwd_b_bresp;
    wire                        bwd_b_vld;
    wire                        bwd_b_rdy;
    
    wire [AR_INFO_W-1:0]        bwd_ar_info;
    wire [AR_INFO_W-1:0]        fwd_ar_info;
    wire [MST_ID_W-1:0]         fwd_arid;
    wire [TRANS_DATA_LEN_W-1:0] fwd_arlen;
    wire [ADDR_W-1:0]           fwd_araddr;
    wire                        fwd_ar_vld;
    wire                        fwd_ar_rdy;
    
    wire [AW_INFO_W-1:0]        fwd_aw_info;
    wire [MST_ID_W-1:0]         fwd_awid;
    wire [ADDR_W-1:0]           fwd_awaddr;
    wire                        fwd_aw_vld;
    wire                        fwd_aw_rdy;
    
    wire [DATA_W-1:0]           fwd_wdata;
    wire                        fwd_wlast;
    wire                        fwd_w_vld;
    wire                        fwd_w_rdy;
    // -- -- For configuration registers mode
    wire [CONF_REG_NUM-1:0]     conf_aw_map_vld;
    wire [CONF_REG_NUM-1:0]     conf_ar_map_vld;
    wire                        mem_wr_en;
    // -- -- For write-data-streaming mode
    wire [ST_WR_FIFO_NUM-1:0]   wr_st_fifo_wr_rdy;
    wire [ST_WR_FIFO_NUM-1:0]   wr_st_fifo_wr_vld;
    wire [ST_WR_FIFO_NUM-1:0]   wr_st_aw_map_vld;
    wire [ST_WR_ADDR_W-1:0]     wr_st_aw_map_idx;
    wire [DATA_W-1:0]           wr_st_rd_data       [0:ST_WR_FIFO_NUM-1];
    wire                        wr_st_wr_rdy;
    wire [ST_WR_ADDR_W-1:0]     wr_st_ar_map_idx;
    wire [ST_WR_FIFO_NUM-1:0]   wr_st_ar_map_vld;
    wire [ST_WR_DAT_CNT_W:0]    wr_st_data_cnt      [0:ST_WR_FIFO_NUM-1];
    // -- -- For read-data-streaming mode
    wire [ST_RD_FIFO_NUM-1:0]   rd_st_fifo_rd_rdy;
    wire [ST_RD_FIFO_NUM-1:0]   rd_st_fifo_rd_vld;
    wire [ST_RD_FIFO_NUM-1:0]   rd_st_ar_map_vld;
    wire [ST_RD_ADDR_W-1:0]     rd_st_ar_map_idx;
    wire [DATA_W-1:0]           rd_st_wr_data       [0:ST_RD_FIFO_NUM-1];
    wire [DATA_W-1:0]           rd_st_rd_data       [0:ST_RD_FIFO_NUM-1];
    wire                        rd_st_rd_rdy;   // The mapped read-streaming FIFO is ready (mapped -> mapped_fifo_ready)
    // -- reg
    // -- -- Common
    reg  [TRANS_DATA_LEN_W-1:0] wdata_cnt;
    reg  [TRANS_DATA_LEN_W-1:0] rdata_cnt;
    // -- -- For configuration registers mode
    reg  [DATA_W-1:0]           ip_config_reg       [0:CONF_REG_NUM-1];
    
    // Module instantiation
    // -- AW channel buffer 
    skid_buffer #(
        .SBUF_TYPE(2),          // Light-weight
        .DATA_WIDTH(AW_INFO_W)
    ) aw_chn_buf (
        .clk        (clk),
        .rst_n      (rst_n),
        .bwd_data_i (bwd_aw_info),
        .bwd_valid_i(m_awvalid_i), 
        .fwd_ready_i(fwd_aw_rdy), 
        .fwd_data_o (fwd_aw_info),
        .bwd_ready_o(m_awready_o), 
        .fwd_valid_o(fwd_aw_vld)
    );
    // -- W channel buffer 
    skid_buffer #(
        .SBUF_TYPE(5),          // Half-registered (full bandwidth)
        .DATA_WIDTH(W_INFO_W)
    ) w_chn_buf (
        .clk        (clk),
        .rst_n      (rst_n),
        .bwd_data_i ({m_wdata_i, m_wlast_i}),
        .bwd_valid_i(m_wvalid_i), 
        .fwd_ready_i(fwd_w_rdy), 
        .fwd_data_o ({fwd_wdata, fwd_wlast}),
        .bwd_ready_o(m_wready_o), 
        .fwd_valid_o(fwd_w_vld)
    );
    // -- B channel buffer 
    skid_buffer #(
        .SBUF_TYPE(2),          // Light-weight
        .DATA_WIDTH(B_INFO_W)
    ) b_chn_buf (
        .clk        (clk),
        .rst_n      (rst_n),
        .bwd_data_i (bwd_b_info),
        .bwd_valid_i(bwd_b_vld), 
        .fwd_ready_i(m_bready_i), 
        .fwd_data_o ({m_bid_o, m_bresp_o}),
        .bwd_ready_o(bwd_b_rdy), 
        .fwd_valid_o(m_bvalid_o)
    );
    // -- AR channel buffer 
    skid_buffer #(
        .SBUF_TYPE(2),          // Light-weight
        .DATA_WIDTH(AR_INFO_W)
    ) ar_chn_buf (
        .clk        (clk),
        .rst_n      (rst_n),
        .bwd_data_i (bwd_ar_info),
        .bwd_valid_i(m_arvalid_i),
        .fwd_ready_i(fwd_ar_rdy), 
        .fwd_data_o (fwd_ar_info),
        .bwd_ready_o(m_arready_o), 
        .fwd_valid_o(fwd_ar_vld)
    );
    // -- R channel buffer 
    skid_buffer #(
        .SBUF_TYPE(5),          // Half-registered (full bandwidth)
        .DATA_WIDTH(R_INFO_W)
    ) r_chn_buf (
        .clk        (clk),
        .rst_n      (rst_n),
        .bwd_data_i (bwd_r_info),
        .bwd_valid_i(bwd_r_vld), 
        .fwd_ready_i(m_rready_i), 
        .fwd_data_o (fwd_r_info),
        .bwd_ready_o(bwd_r_rdy), 
        .fwd_valid_o(m_rvalid_o)
    );
    
generate
if(AXI4_CTRL_CONF == 1) begin : AXI4_CONF
    // Combination logic
    for(conf_idx = 0; conf_idx < CONF_REG_NUM; conf_idx = conf_idx + 1) begin
        assign conf_reg_o[(conf_idx+1)*CONF_DATA_W-1 -: CONF_DATA_W] = ip_config_reg[conf_idx];
    end
    for(conf_idx = 0; conf_idx < CONF_REG_NUM; conf_idx = conf_idx + 1) begin
        assign conf_aw_map_vld[conf_idx] = ~|((fwd_awaddr + wdata_cnt<<(CONF_OFFSET-1)) ^ (CONF_BASE_ADDR+conf_idx*CONF_OFFSET));    // Check if the address is in the configuration region
        assign conf_ar_map_vld[conf_idx] = ~|((fwd_araddr + rdata_cnt<<(CONF_OFFSET-1)) ^ (CONF_BASE_ADDR+conf_idx*CONF_OFFSET));    // Check if the address is in the configuration region
    end
    
    // Flip-flop
    for(conf_idx = 0; conf_idx < CONF_REG_NUM; conf_idx = conf_idx + 1) begin
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            ip_config_reg[conf_idx] <= {DATA_W{1'b0}};
        end
        else if(conf_aw_map_vld[conf_idx] & mem_wr_en) begin
            ip_config_reg[conf_idx] <= fwd_wdata;
        end
    end
    end
end
else begin
    assign conf_aw_map_vld = {CONF_REG_NUM{1'b0}};
    assign conf_ar_map_vld = {CONF_REG_NUM{1'b0}};
end

if(AXI4_CTRL_WR_ST == 1) begin : AXI4_WR_ST
    /* 
    Operator in write-streaming region
        - Write:    streaming data to the slave 
        - Read:     return number of data in the write-streaming FIFO 
    */
    // Module instantiation
    for(fifo_idx = 0; fifo_idx < ST_WR_FIFO_NUM; fifo_idx = fifo_idx + 1) begin
        // -- Write streaming FIFO
        sync_fifo #(
            .FIFO_TYPE      (1),    // Normal FIFO  
            .DATA_WIDTH     (DATA_W),      
            .FIFO_DEPTH     (ST_WR_FIFO_DEPTH)
        ) wr_st_fifo (
            .clk            (clk),
            .data_i         (fwd_wdata),
            .data_o         (wr_st_rd_data[fifo_idx]),
            .wr_valid_i     (wr_st_fifo_wr_vld[fifo_idx]),
            .rd_valid_i     (wr_st_rd_vld_i[fifo_idx]),
            .empty_o        (),
            .full_o         (),
            .wr_ready_o     (wr_st_fifo_wr_rdy[fifo_idx]),
            .rd_ready_o     (wr_st_rd_rdy_o[fifo_idx]),
            .almost_empty_o (),
            .almost_full_o  (),
            .counter        (wr_st_data_cnt[fifo_idx]),
            .rst_n          (rst_n)
        );
    end
    if(ST_WR_FIFO_NUM > 1) begin
        // -- One-hot encoder for AW channel
        onehot_encoder #(
            .INPUT_W    (ST_WR_FIFO_NUM),
            .OUTPUT_W   (ST_WR_ADDR_W)
        ) wr_st_aw_fifo_map (
            .i          (wr_st_aw_map_vld),
            .o          (wr_st_aw_map_idx)
        );
        // -- One-hot encoder for AR channel
        onehot_encoder #(
            .INPUT_W    (ST_WR_FIFO_NUM),
            .OUTPUT_W   (ST_WR_ADDR_W)
        ) wr_st_ar_fifo_map (
            .i          (wr_st_ar_map_vld),
            .o          (wr_st_ar_map_idx)
        );
    end
    else begin
        assign wr_st_aw_map_idx = 1'd0;
        assign wr_st_ar_map_idx = 1'd0;
    end
    // Comninational logic
    assign wr_st_wr_rdy = wr_st_fifo_wr_rdy[wr_st_aw_map_idx];
    for(fifo_idx = 0; fifo_idx < ST_WR_FIFO_NUM; fifo_idx = fifo_idx + 1) begin
        assign wr_st_rd_data_o[(fifo_idx+1)*DATA_W-1 -: DATA_W] = wr_st_rd_data[fifo_idx];
        assign wr_st_aw_map_vld[fifo_idx] = ~|(fwd_awaddr ^ (ST_WR_BASE_ADDR+fifo_idx*ST_WR_OFFSET));    // Check if the address is in the write-stream FIFO region
        assign wr_st_fifo_wr_vld[fifo_idx] = mem_wr_en & wr_st_aw_map_vld[fifo_idx];
        assign wr_st_ar_map_vld[fifo_idx] = ~|(fwd_araddr ^ (ST_WR_BASE_ADDR+fifo_idx*ST_WR_OFFSET));    // Check if the address is in the write-stream FIFO region
    end
end
else begin
    assign wr_st_wr_rdy     = 1'b1;
    assign wr_st_aw_map_vld = {ST_WR_FIFO_NUM{1'b0}};
end

if(AXI4_CTRL_RD_ST == 1) begin : AXI4_RD_ST
    /* 
    Operator in read-streaming region
        - Write:    Can't access 
        - Read:     return the data, which is received from the slave 
    */
    // Module instantiation
    // -- Read streaming FIFO
    for(fifo_idx = 0; fifo_idx < ST_RD_FIFO_NUM; fifo_idx = fifo_idx + 1) begin
        sync_fifo #(
            .FIFO_TYPE      (1),    // Normal FIFO  
            .DATA_WIDTH     (DATA_W),      
            .FIFO_DEPTH     (ST_RD_FIFO_DEPTH)
        ) rd_st_fifo (
            .clk            (clk),
            .data_i         (rd_st_wr_data[fifo_idx]),
            .data_o         (rd_st_rd_data[fifo_idx]),
            .wr_valid_i     (rd_st_wr_vld_i[fifo_idx]),
            .rd_valid_i     (rd_st_fifo_rd_vld[fifo_idx]),
            .empty_o        (),
            .full_o         (),
            .wr_ready_o     (rd_st_wr_rdy_o[fifo_idx]),
            .rd_ready_o     (rd_st_fifo_rd_rdy[fifo_idx]),
            .almost_empty_o (),
            .almost_full_o  (),
            .counter        (),
            .rst_n          (rst_n)
        );
    end
    if(ST_RD_FIFO_NUM > 1) begin
        // -- One-hot encoder
        onehot_encoder #(
            .INPUT_W    (ST_RD_FIFO_NUM),
            .OUTPUT_W   (ST_RD_ADDR_W)
        ) rd_st_fifo_map (
            .i          (rd_st_ar_map_vld),
            .o          (rd_st_ar_map_idx)
        );
    end
    else begin
        assign rd_st_ar_map_idx = 1'd0;
    end
    // Combination logic
    assign rd_st_rd_rdy = ~(|rd_st_ar_map_vld) | rd_st_fifo_rd_rdy[rd_st_ar_map_idx];   // If the address is in the read-streaming FIFO region, then return the read-streaming FIFO ready signal
    for(fifo_idx = 0; fifo_idx < ST_RD_FIFO_NUM; fifo_idx = fifo_idx + 1) begin
        assign rd_st_wr_data[fifo_idx] = rd_st_wr_data_i[(fifo_idx+1)*DATA_W-1 -: DATA_W];
        assign rd_st_ar_map_vld[fifo_idx] = ~|(fwd_araddr ^ (ST_RD_BASE_ADDR+fifo_idx*ST_RD_OFFSET));    // Check if the address is in the read-stream FIFO region
        assign rd_st_fifo_rd_vld[fifo_idx] = (bwd_r_vld & bwd_r_rdy) & rd_st_ar_map_vld[fifo_idx];
    end
    // Flip-flop
end
else begin
    // DO SOMETHING: set all flags to ...
    assign rd_st_ar_map_vld = {ST_RD_FIFO_NUM{1'b0}};
end
endgenerate
    
    // COMMON LOGIC
    // Combination logic
    assign {m_rresp_o, m_rlast_o, m_rdata_o} = fwd_r_info;
    assign fwd_aw_rdy   = mem_wr_en & bwd_b_rdy & fwd_wlast;
    assign fwd_w_rdy    = mem_wr_en & (~fwd_wlast | bwd_b_rdy); // When last data is received, wait for B channel to be ready
    assign bwd_b_info   = {bwd_b_bid, bwd_b_bresp};
    assign bwd_b_bid    = fwd_awid;
    assign bwd_b_vld    = mem_wr_en & fwd_wlast;
    assign {fwd_arid, fwd_arlen, fwd_araddr} = fwd_ar_info;
    assign {fwd_awid, fwd_awaddr} = fwd_aw_info;
    assign bwd_aw_info  = {m_awid_i, m_awaddr_i};
    assign bwd_ar_info  = {m_arid_i, m_arlen_i, m_araddr_i};
    assign fwd_ar_rdy   = bwd_r_rdy & bwd_rlast & rd_st_rd_rdy; // "bwd_rlast" - When last data is received, wait for R channel to be ready -> Pop data from AR channel || "rd_st_rd_rdy" - If the address is in the read-streaming FIFO region, then read-streaming FIFO must be ready
    assign bwd_r_info   = {bwd_rresp, bwd_rlast, bwd_rdata};
    assign bwd_rlast    = ~|(rdata_cnt ^ fwd_arlen);
    assign bwd_r_vld    = fwd_ar_vld & rd_st_rd_rdy;

    assign bwd_b_bresp  = ((|conf_aw_map_vld) | (|wr_st_aw_map_vld)) ? 2'b00 : 2'b11;    // 2'b00: SUCCESS || 2'b11: Wrong mapping
    assign bwd_rdata    = (|conf_ar_map_vld)  ? ip_config_reg[fwd_araddr[CONF_ADDR_W+CONF_OFFSET_W-1-:CONF_ADDR_W] + rdata_cnt<<(CONF_OFFSET-1)] :  // Map to configuration registers   -> return configuration data
                          (|rd_st_ar_map_vld) ? rd_st_rd_data[rd_st_ar_map_idx] :                                                                   // Map to read-streaming FIFO       -> return RX data from the slave
                                                wr_st_data_cnt[wr_st_ar_map_idx];                                                                   // Map to write-streaming FIFO      -> return number of data in the write-streaming FIFO
    assign bwd_rresp    = ((|conf_ar_map_vld) | (|rd_st_ar_map_vld) | (|wr_st_ar_map_vld)) ? 2'b00 : 2'b11;
    assign mem_wr_en    = fwd_w_vld & fwd_aw_vld & (~(|wr_st_aw_map_vld) | wr_st_wr_rdy); // "(~(|wr_st_aw_map_vld) | wr_st_wr_rdy)" - If the address is in the write-streaming FIFO region, then the write-streaming FIFO must be ready 
    
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            wdata_cnt <= {TRANS_DATA_LEN_W{1'b0}};
        end
        else if(fwd_w_vld & fwd_w_rdy) begin
            if(fwd_wlast) begin
                wdata_cnt <= {TRANS_DATA_LEN_W{1'b0}};
            end
            else begin
                wdata_cnt <= wdata_cnt + 1'b1;
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            rdata_cnt <= {TRANS_DATA_LEN_W{1'b0}};
        end
        else if(bwd_r_vld & bwd_r_rdy) begin
            if(bwd_rlast) begin
                rdata_cnt <= {TRANS_DATA_LEN_W{1'b0}};
            end
            else begin
                rdata_cnt <= rdata_cnt + 1'b1;
            end
        end
    end

    

endmodule

/*          De-flattern configuration registers - start          */
// genvar i;
// for (i = 0; i < CONF_REG_NUM; i++) begin
//     assign conf_reg[i] = conf_reg_o[CONF_DATA_W*(i+1)-1:CONF_DATA_W*i];
// end
/*          De-flattern configuration registers - end            */


/*          De-flattern Write-Streaming Data - start          */
// genvar i;
// logic  [DATA_W-1:0]  wr_st_data [0:ST_WR_FIFO_NUM-1];
// for(i = 0; i < ST_WR_FIFO_NUM; i++) begin
//     assign wr_st_data[i] = wr_st_rd_data_o[DATA_W*(i+1)-1:DATA_W*i];
// end
/*          De-flattern Write-Streaming Data - end            */