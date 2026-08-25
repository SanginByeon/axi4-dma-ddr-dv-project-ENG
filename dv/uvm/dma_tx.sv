// ============================================================================
// dma_tx.sv - DMA Transaction
//
// - Defines DMA source/destination addresses, transfer size, CTRL, and DDR-model verification settings.
// - Generates a source-memory preload payload pattern matching the transfer size.
// - Constrains 4-byte address alignment, the 4 KB memory range, and source/destination non-overlap.
// - Provides factory registration, normal-transfer defaults, and transaction formatting.
// ============================================================================

class dma_tx extends uvm_sequence_item;
    rand bit [31:0] src_addr;      // Source address
    rand bit [31:0] dst_addr;      // Destination address
    rand bit [31:0] size;          // Transfer size
    rand byte data_payload[];      // Data used for integrity verification

    // Low three bits of the CTRL register
    rand bit enable;
    rand bit start;
    rand bit irq;

    // Probability of AXI4 W-channel backpressure in the DDR memory model
    rand bit [7:0] backpressure_prob;

    // DDR memory-model BRESP error-injection setting
    rand bit error_inject;

    // Test-scenario name for each Sequence
    string scenario_name;

    function new(input string name = "dma_tx");
        super.new(name);
    endfunction

    // [Factory registration]
    `uvm_object_utils_begin(dma_tx)
        `uvm_field_int(src_addr, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(dst_addr, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(size, UVM_DEFAULT | UVM_DEC)
        `uvm_field_int(enable, UVM_DEFAULT | UVM_BIN)
        `uvm_field_int(start, UVM_DEFAULT | UVM_BIN)
        `uvm_field_int(irq, UVM_DEFAULT | UVM_BIN)
        `uvm_field_int(backpressure_prob, UVM_DEFAULT | UVM_DEC)
        `uvm_field_int(error_inject, UVM_DEFAULT | UVM_BIN)
        `uvm_field_array_int(data_payload, UVM_DEFAULT)
        `uvm_field_string(scenario_name, UVM_DEFAULT)
    `uvm_object_utils_end

    // [Address constraint] : Restrict addresses to the 4-byte alignment supported by the DUT
    constraint c_addr_alignment {
        src_addr[1:0] == 2'b00;
        dst_addr[1:0] == 2'b00;
    }

    // [Default constraint] : Generate 4–1024-byte normal transfers by default
    constraint c_default_transfer {
        soft size inside {[4:1024]};
        soft size[1:0] == 2'b00;

        soft enable == 1'b1;
        soft start  == 1'b1;
        soft irq    == 1'b1;
    }

    // [Backpressure constraint] : Default to no stall and limit the maximum to 99%
    constraint c_backpressure {
        backpressure_prob inside {[0:99]};
        soft backpressure_prob == 0;
    }

    // [Error-injection constraint] : Do not inject BRESP errors in normal transfers
    constraint c_error_injection {
        soft error_inject == 1'b0;
    }

    // [Memory constraint] : Keep source/destination transfer regions within the 4 KB memory
    constraint c_memory_range {
        size inside {[1:2048]};

        src_addr <= 32'd4096 - size;
        dst_addr <= 32'd4096 - size;
    }

    // [Overlap constraint] : Prevent source and destination transfer regions from overlapping
    constraint c_no_overlap {
        (src_addr + size <= dst_addr) ||
        (dst_addr + size <= src_addr);
    }

    // [Payload constraint] : Set the source-preload array size to match the transfer size
    constraint c_data_size {
        data_payload.size() == size;
    }

    // [Transaction formatting] : Print scenario and transaction information separately
    virtual function string convert2string();
        string s = super.convert2string();

        // Display the scenario name available only in the original Sequence/Driver transaction
        if (scenario_name != "")
            s = {s, $sformatf("[Scenario: %s] ", scenario_name)};

        s = {s, "[Transaction: "};
        s = {s, $sformatf("src_addr:0x%0h, ", src_addr)};
        s = {s, $sformatf("dst_addr:0x%0h, ", dst_addr)};
        s = {s, $sformatf("size:%0d, ", size)};
        s = {s, $sformatf("enable:%0b, ", enable)};
        s = {s, $sformatf("start:%0b, ", start)};
        s = {s, $sformatf("irq:%0b, ", irq)};
        s = {s, $sformatf("backpressure_prob:%0d%%, ", backpressure_prob)};
        s = {s, $sformatf("error_inject:%0b]", error_inject)};

        return s;
    endfunction

    // [Payload generation] : Generate the payload from the word index
    // The Sequence calls utility_pkg::preload_src_mem() to write the payload starting at src_addr
    function void post_randomize();
        for (int i = 0; i < data_payload.size(); i += 4) begin
            int word = 32'hCAFE_0000 + (i / 4);

            if (i < data_payload.size())
                data_payload[i] = word[7:0];
            if (i + 1 < data_payload.size())
                data_payload[i + 1] = word[15:8];
            if (i + 2 < data_payload.size())
                data_payload[i + 2] = word[23:16];
            if (i + 3 < data_payload.size())
                data_payload[i + 3] = word[31:24];
        end
    endfunction
endclass
