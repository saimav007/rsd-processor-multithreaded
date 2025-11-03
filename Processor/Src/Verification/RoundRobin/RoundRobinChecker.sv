// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// Round-Robin Assertion-Based Checker
// Contains SVA properties for round-robin verification
//

`timescale 1ns/1ps

import BasicTypes::*;
import PipelineTypes::*;

module RoundRobinChecker(
    input logic clk,
    input logic rst,
    
    // Signals to check
    input ThreadID selectedThread,
    input ThreadID nextThreadID,
    input logic stall,
    input logic clear,
    input logic toRecoveryPhase,
    input logic recoverFromRename,
    input ThreadID recoveredThreadID,
    input PC_Path pcOut[NUM_THREADS],
    input PC_Path pcIn[NUM_THREADS],
    input logic pcWE[NUM_THREADS],
    input logic threadReady[NUM_THREADS]
);

    // Helper signals
    logic normalOperation;
    logic isRecovering;
    
    assign normalOperation = !stall && !clear && !toRecoveryPhase && !recoverFromRename && !rst;
    assign isRecovering = toRecoveryPhase || recoverFromRename;
    
    //
    // Assertion Properties
    //
    
    // Property 1: Only selected thread should have PC write enabled in normal operation
    property p_pc_write_only_selected_thread;
        @(posedge clk) disable iff (rst)
        normalOperation |-> 
            foreach(pcWE[i]) (pcWE[i] == (i == selectedThread));
    endproperty
    
    assert_pc_write_only_selected: 
        assert property (p_pc_write_only_selected_thread)
        else $error("Assertion Failed: PC written for non-selected thread at time %0t", $time);
    
    // Property 2: During recovery, recovered thread should be selected next
    property p_recovery_thread_selected;
        @(posedge clk) disable iff (rst)
        isRecovering |-> (nextThreadID == recoveredThreadID);
    endproperty
    
    assert_recovery_thread_selected:
        assert property (p_recovery_thread_selected)
        else $error("Assertion Failed: Recovery thread not selected at time %0t", $time);
    
    // Property 3: During stall, selected thread should not change
    property p_thread_unchanged_during_stall;
        @(posedge clk) disable iff (rst)
        stall && !isRecovering |=> (selectedThread == $past(selectedThread));
    endproperty
    
    assert_thread_unchanged_during_stall:
        assert property (p_thread_unchanged_during_stall)
        else $error("Assertion Failed: Thread changed during stall at time %0t", $time);
    
    // Property 4: In normal operation, nextThreadID should be either current or next in round-robin
    property p_valid_next_thread;
        @(posedge clk) disable iff (rst)
        normalOperation |-> 
            (nextThreadID == selectedThread) || 
            (nextThreadID == ((selectedThread + 1) % NUM_THREADS));
    endproperty
    
    assert_valid_next_thread:
        assert property (p_valid_next_thread)
        else $error("Assertion Failed: Invalid next thread selection at time %0t", $time);
    
    // Property 5: PC should advance for selected thread when not stalled
    property p_pc_advances_when_not_stalled;
        @(posedge clk) disable iff (rst)
        normalOperation && !isRecovering && pcWE[selectedThread] |->
            (pcIn[selectedThread] != pcOut[selectedThread]);
    endproperty
    
    assert_pc_advances:
        assert property (p_pc_advances_when_not_stalled)
        else $error("Assertion Failed: PC not advancing for selected thread at time %0t", $time);
    
    // Property 6: Non-selected thread PC should remain unchanged
    property p_non_selected_pc_unchanged;
        @(posedge clk) disable iff (rst)
        normalOperation |->
            foreach(pcIn[i]) 
                (i != selectedThread) |-> (pcIn[i] == pcOut[i]);
    endproperty
    
    assert_non_selected_pc_unchanged:
        assert property (p_non_selected_pc_unchanged)
        else $error("Assertion Failed: Non-selected thread PC changed at time %0t", $time);
    
    // Property 7: Thread alternation in sustained normal operation
    // If we run for several cycles without stall/recovery, threads should alternate
    property p_thread_alternation;
        @(posedge clk) disable iff (rst)
        (normalOperation throughout (##1 normalOperation ##1 normalOperation)) |->
            ((selectedThread == 0 ##1 selectedThread == 1) or
             (selectedThread == 1 ##1 selectedThread == 0));
    endproperty
    
    assert_thread_alternation:
        assert property (p_thread_alternation)
        else $warning("Warning: Thread not alternating in normal operation at time %0t", $time);
    
    // Property 8: selectedThread must be a valid thread ID
    property p_valid_thread_id;
        @(posedge clk) disable iff (rst)
        selectedThread < NUM_THREADS;
    endproperty
    
    assert_valid_thread_id:
        assert property (p_valid_thread_id)
        else $error("Assertion Failed: Invalid thread ID at time %0t", $time);
    
    // Property 9: nextThreadID must be a valid thread ID
    property p_valid_next_thread_id;
        @(posedge clk) disable iff (rst)
        nextThreadID < NUM_THREADS;
    endproperty
    
    assert_valid_next_thread_id:
        assert property (p_valid_next_thread_id)
        else $error("Assertion Failed: Invalid next thread ID at time %0t", $time);
    
    // Property 10: Recovery should clear after one cycle
    property p_recovery_clears;
        @(posedge clk) disable iff (rst)
        toRecoveryPhase |=> !toRecoveryPhase;
    endproperty
    
    assert_recovery_clears:
        assert property (p_recovery_clears)
        else $warning("Warning: Recovery did not clear after one cycle at time %0t", $time);
    
    //
    // Coverage Points
    //
    
    // Cover thread switches
    covergroup cg_thread_switches @(posedge clk);
        option.per_instance = 1;
        
        cp_thread0_to_thread1: coverpoint selectedThread {
            bins t0_to_t1 = (0 => 1);
        }
        
        cp_thread1_to_thread0: coverpoint selectedThread {
            bins t1_to_t0 = (1 => 0);
        }
        
        cp_thread_stays_same: coverpoint selectedThread {
            bins stays_0 = (0 => 0);
            bins stays_1 = (1 => 1);
        }
    endgroup
    
    cg_thread_switches cg_switches = new();
    
    // Cover recovery scenarios
    covergroup cg_recovery @(posedge clk);
        option.per_instance = 1;
        
        cp_recovery_phase: coverpoint toRecoveryPhase {
            bins recovery_active = {1};
        }
        
        cp_recovery_thread: coverpoint recoveredThreadID {
            bins thread0 = {0};
            bins thread1 = {1};
        }
        
        cp_recovery_cross: cross cp_recovery_phase, cp_recovery_thread;
    endgroup
    
    cg_recovery cg_recov = new();
    
    // Cover stall scenarios
    covergroup cg_stalls @(posedge clk);
        option.per_instance = 1;
        
        cp_stall: coverpoint stall {
            bins no_stall = {0};
            bins stalled = {1};
        }
        
        cp_stall_with_thread: cross cp_stall, selectedThread;
    endgroup
    
    cg_stalls cg_st = new();
    
    // Cover normal operation patterns
    covergroup cg_normal_ops @(posedge clk);
        option.per_instance = 1;
        
        cp_normal_op: coverpoint normalOperation {
            bins normal = {1};
        }
        
        cp_pc_write: coverpoint pcWE[selectedThread] iff (normalOperation) {
            bins write_enabled = {1};
        }
        
        cp_thread_in_normal: coverpoint selectedThread iff (normalOperation) {
            bins thread0 = {0};
            bins thread1 = {1};
        }
    endgroup
    
    cg_normal_ops cg_norm = new();

endmodule : RoundRobinChecker
