// ============================================================================
// axi_checker.sv - AXI4 W Channel Protocol Checker
//
// - Uses SVA to verify WVALID persistence under W-channel backpressure.
// - Uses SVA to verify WDATA/WSTRB/WLAST stability under W-channel backpressure.
// - At each W-channel handshake, checks that WLAST is high if and only if the current beat is the
//   final beat of the burst.
// - Provides per-assertion violation counters for result checking in the UVM report phase.
// ============================================================================

module axi_checker (
    axi4_if axi,
    input logic [7:0] w_beats_sent
);

    // Violation count for each assertion
    int unsigned vio_total = 0;
    int unsigned vio_w_payload_stable_on_stall = 0;
    int unsigned vio_wvalid_hold = 0;
    int unsigned vio_wlast_timing = 0;

    // [A-01] : Hold the W-channel payload while a stall persists
    property p_w_payload_stable_on_stall;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        (axi.wvalid && !axi.wready)
        |=> $stable({axi.wdata, axi.wstrb, axi.wlast});
    endproperty

    // [A-02] : Hold WVALID while a stall persists
    property p_wvalid_hold;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        (axi.wvalid && !axi.wready)
        |=> axi.wvalid;
    endproperty

    // [A-03] : At each W handshake, check that WLAST matches the final-beat condition from AWLEN
    property p_wlast_timing;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        (axi.wvalid && axi.wready)
        |-> (axi.wlast == (w_beats_sent == axi.awlen));
    endproperty

    ap_w_payload_stable_on_stall:
        assert property (p_w_payload_stable_on_stall)
        else begin
            $error("[A-01][AXI_W] Payload changed while stalled");
            vio_total++;
            vio_w_payload_stable_on_stall++;
        end

    ap_wvalid_hold:
        assert property (p_wvalid_hold)
        else begin
            $error("[A-02][AXI_W] WVALID deasserted while stalled");
            vio_total++;
            vio_wvalid_hold++;
        end

    ap_wlast_timing:
        assert property (p_wlast_timing)
        else begin
            $error(
                "[A-03][AXI_W] WLAST timing mismatch: WLAST=%0b, beat=%0d, AWLEN=%0d",
                axi.wlast, w_beats_sent, axi.awlen
            );
            vio_total++;
            vio_wlast_timing++;
        end

endmodule
