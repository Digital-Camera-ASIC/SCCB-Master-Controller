module sccb_fsm #(
    parameter DATA_W = 8
) (
    // Input declaration
    // -- Global
    input                   clk,
    input                   rst_n,
    // -- Configuration registers
    input   [DATA_W-2:0]    slv_dvc_addr_i,
    // -- Control registers
    input                   trans_type_i,   // 0: Read      ||  1: Write
    input   [1:0]           phase_amt_i,    // 0-1: ERROR   ||  2: 2 ph  || 3: 3 ph
    input                   ctrl_vld_i,
    // -- Streaming TX
    input   [DATA_W-1:0]    tx_data_i,
    input                   tx_data_vld_i,
    input   [DATA_W-1:0]    tx_sub_adr_i,
    input                   tx_sub_adr_vld_i,
    // -- Streaming RX
    input                   rx_rdy_i,
    // -- SCCB Timing generator
    input                   tick_en_i,
    input                   sio_c_tgl_en_i,

    // Output declaration
    // -- Control registers
    output                  ctrl_rdy_o,
    // -- Streaming TX
    output                  tx_data_rdy_o,
    output                  tx_sub_adr_rdy_o,
    // -- Streaming RX
    output  [DATA_W-1:0]    rx_data_o,
    output                  rx_vld_o,
    // -- SCCB Timing generator
    output                  cntr_en_o,
    // -- SCCB Master Interface
    output                  sio_c,
    inout                   sio_d
);
    // Local parameters declaration
    localparam IDLE_ST          = 3'd0;
    localparam START_TRANS_ST   = 3'd1;
    localparam TX_DATA_ST       = 3'd2;
    localparam TX_DATA_ACK_ST   = 3'd3;
    localparam RX_DATA_ST       = 3'd4;
    localparam RX_DATA_ACK_ST   = 3'd5;
    localparam STOP_TRANS_ST    = 3'd6;
    localparam BUF_RX_DATA_ST   = 3'd7;

    localparam DATA_CNT_W       = $clog2(DATA_W);
    // Internal signals declaration
    // -- wire
    reg     [2:0]           st_d;
    wire    [DATA_W-1:0]    slv_dvc_addr;
    reg                     ctrl_rdy;
    reg                     tx_data_rdy;
    reg                     tx_sub_adr_rdy;
    reg     [1:0]           phase_cnt_d;
    reg                     sio_oe_m_d;
    reg                     sio_d_intl_d;
    reg                     sio_c_d;
    reg     [DATA_CNT_W-1:0]sio_d_cnt_d;
    reg     [DATA_W-1:0]    rx_data_d;
    // -- reg
    reg     [2:0]           st_q;
    reg     [DATA_W-1:0]    tx_data_q1;
    reg     [DATA_W-1:0]    tx_sub_adr_q1;
    reg     [1:0]           phase_cnt_q;
    reg     [1:0]           phase_amt_q1;
    reg                     trans_type_q1;
    reg                     sio_oe_m_q;     // SIO_D output enable (tri-state control)
    reg                     sio_d_intl_q;   // Internal SIO_D
    reg                     sio_c_q;   // Internal SIO_D
    reg     [DATA_CNT_W-1:0]sio_d_cnt_q;
    reg     [DATA_W-1:0]    rx_data_q;

    // Combinational logic
    assign sio_d = sio_oe_m_q ? 1'bz : sio_d_intl_q;
    assign sio_c = sio_c_q;
    assign ctrl_rdy_o = ctrl_rdy & ~|(st_q ^ IDLE_ST);
    assign tx_sub_adr_rdy_o = tx_sub_adr_rdy;
    assign tx_data_rdy_o = tx_data_rdy;
    assign rx_data_o = rx_data_q;
    assign slv_dvc_addr = {slv_dvc_addr_i, ~trans_type_q1}; // Slave device address + R/W bit
    assign cntr_en_o = |(st_q ^ IDLE_ST);  // start counting when the state is not IDLE
    always @(*) begin
        ctrl_rdy    = 1'b0;
        tx_data_rdy = 1'b0;
        tx_sub_adr_rdy = 1'b0;
        
        case({phase_amt_i, trans_type_i})
            {2'd2, 1'b0}: begin     // 2-Phase Read transmission
                ctrl_rdy    = 1'b1; // Always accept
            end
            {2'd2, 1'b1}: begin     // 2-Phase Write transmission
                ctrl_rdy    = tx_sub_adr_vld_i; // Need sub-address
                tx_sub_adr_rdy = ctrl_rdy_o;
            end
            {2'd3, 1'b1}: begin     // 3-Phase Write transmission 
                ctrl_rdy    = tx_sub_adr_vld_i & tx_data_vld_i; // Need both sub-address and data
                tx_sub_adr_rdy = ctrl_rdy_o;
                tx_data_rdy = ctrl_rdy_o;
            end
        endcase
    end
    always @(*) begin
        st_d        = st_q;
        sio_oe_m_d  = sio_oe_m_q;
        sio_d_intl_d= sio_d_intl_q;
        sio_c_d     = sio_c_q;
        phase_cnt_d = phase_cnt_q;
        sio_d_cnt_d = sio_d_cnt_q;
        rx_data_d   = rx_data_q;
        case (st_q)
            IDLE_ST: begin
                if (ctrl_vld_i & ctrl_rdy_o) begin
                    st_d = START_TRANS_ST;
                    // IO
                    sio_oe_m_d = 1'b0;
                    // Internal
                    sio_d_intl_d = 1'b1;
                end
                phase_cnt_d = 2'd0;
            end
            START_TRANS_ST: begin
                if(tick_en_i) begin
                    if(sio_d_intl_d) begin  // Start transmission
                        st_d = TX_DATA_ST;
                        sio_d_intl_d = 1'b0;
                        sio_d_cnt_q = DATA_W - 1'b1; // 3'd7
                    end
                end
            end
            TX_DATA_ST: begin
                if(tick_en_i & (~sio_c_q)) begin    // Active on LOW level of SIO_C
                    if(~|sio_d_cnt_q) begin // == 0
                        st_d = TX_DATA_ACK_ST;
                        // I/O
                        sio_oe_m_d = 1'b1;  // Float SIO_D
                        // Internal
                        phase_cnt_d = phase_cnt_q + 1'b1;
                    end
                    else begin
                        if(~|(phase_cnt_q^2'd0)) begin  // The current phase is slave device address phase (phase 1)
                            sio_d_intl_d = slv_dvc_addr[sio_d_cnt_q];
                        end
                        else if(~|(phase_cnt_q^2'd1)) begin // The current phase is sub-address phase (phase 2)
                            sio_d_intl_d = tx_sub_adr_q1[sio_d_cnt_q];
                        end
                        else begin  // The current phase is data phase (phase 3)
                            sio_d_intl_d = tx_data_q1[sio_d_cnt_q];
                        end
                    end
                    sio_d_cnt_d = sio_d_cnt_q - 1'b1;   // 7 -> 0
                end
            end
            TX_DATA_ACK_ST: begin
                if(tick_en_i & (~sio_c_q)) begin    // Active on LOW level of SIO_C
                    if(~trans_type_q1) begin    // Read transmission
                        st_d = RX_DATA_ST;
                        sio_oe_m_d = 1'b0;      // Float SIO_D
                        sio_d_intl_d = 1'b1;
                    end
                    else begin    // Write transmission
                        if(~|(phase_cnt_q^(phase_amt_q1-1'b1))) begin    // Last phase
                            st_d = STOP_TRANS_ST;
                            // Setup SCCB stop transmission
                            sio_d_intl_d = 1'b0;
                        end
                    end
                end
            end
            RX_DATA_ST: begin
                if(tick_en_i & (~sio_c_q)) begin    // Active on LOW level of SIO_C
                    if(~|sio_d_cnt_q) begin // == 0
                        st_d = RX_DATA_ACK_ST;
                        // I/O
                        sio_oe_m_d = 1'b0;  // Drive the SIO_D pin
                        // Internal
                        sio_d_intl_d = 1'b1;
                    end
                    sio_d_cnt_d = sio_d_cnt_q - 1'b1;   // 7 -> 0
                end
                if(sio_c_tgl_en_i & (~sio_c_q)) begin   // Sample SIO_D on rising edge of SIO_C
                    rx_data_d = {rx_data_q[DATA_W-2:0], sio_d};
                end
            end
            RX_DATA_ACK_ST: begin
                if(tick_en_i & (~sio_c_q)) begin
                    st_d = STOP_TRANS_ST;
                    // Setup SCCB stop transmission
                    sio_d_intl_d = 1'b0;
                end
            end
            STOP_TRANS_ST: begin
                if(tick_en_i) begin
                    if(sio_d_intl_q) begin
                        st_d = IDLE_ST;
                        // IO
                        sio_oe_m_d = 1'b1;  // Float SIO_D
                    end
                    else begin
                        sio_d_intl_d = 1'b1;
                    end
                end
            end
        endcase
    end

    // Flip-flop
    always @(posedge clk) begin
        if (tx_data_vld_i & tx_data_rdy_o) begin
            tx_data_q1 <= tx_data_i;
        end
    end
    always @(posedge clk) begin
        if(tx_sub_adr_vld_i & tx_sub_adr_rdy_o) begin
            tx_sub_adr_q1 <= tx_sub_adr_i;
        end
    end
    always @(posedge clk) begin
        if(ctrl_vld_i & ctrl_rdy_o) begin
            phase_amt_q1 <= phase_amt_i;
        end
    end
    always @(posedge clk) begin
        if(ctrl_vld_i & ctrl_rdy_o) begin
            trans_type_q1 <= trans_type_i;
        end
    end
    always @(posedge clk) begin
        if(st_d != st_q) begin
            st_q <= st_d;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            sio_c_q <= 1'b1;
        end
        else if(sio_c_tgl_en_i) begin
            sio_c_q <= (~|(st_q^START_TRANS_ST) | ~|(st_q^START_TRANS_ST)) | (~sio_c_q); // When current state is START transmission or STOP transmission, then SIO_C is HIGH. Otherwise, toggle SIO_C
        end
    end
endmodule