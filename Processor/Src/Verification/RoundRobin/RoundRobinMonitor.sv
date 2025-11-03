// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// Round-Robin Monitor for SMT verification
// Monitors thread selection behavior and verifies round-robin scheduling
//

`timescale 1ns/1ps

import BasicTypes::*;
import PipelineTypes::*;

module RoundRobinMonitor(
    input logic clk,
    input logic rst,
    
    // Signals from NextPCStage
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
    
    // Statistics outputs
    output int threadSwitchCount,
    output int thread0FetchCount,
    output int thread1FetchCount,
    output int violationCount
);

    // Internal tracking variables
    ThreadID lastSelectedThread;
    ThreadID expectedNextThread;
    int cycleCount;
    int stallCycles;
    int recoveryCycles;
    
    // Flags for different states
    logic isStalled;
    logic isRecovering;
    logic normalOperation;
    
    // File handle for logging
    integer logFile;
    
    // Initialize
    initial begin
        threadSwitchCount = 0;
        thread0FetchCount = 0;
        thread1FetchCount = 0;
        violationCount = 0;
        cycleCount = 0;
        stallCycles = 0;
        recoveryCycles = 0;
        lastSelectedThread = 0;
        
        logFile = $fopen("round_robin_monitor.log", "w");
        if (logFile == 0) begin
            $display("ERROR: Could not open log file");
            $finish;
        end
        
        $fdisplay(logFile, "=== Round-Robin Monitor Log ===");
        $fdisplay(logFile, "Time: %0t", $time);
        $fdisplay(logFile, "NUM_THREADS: %0d", NUM_THREADS);
        $fdisplay(logFile, "FETCH_WIDTH: %0d", FETCH_WIDTH);
        $fdisplay(logFile, "================================\n");
    end
    
    // Monitor state
    always_comb begin
        isStalled = stall;
        isRecovering = toRecoveryPhase || recoverFromRename;
        normalOperation = !isStalled && !isRecovering && !clear && !rst;
    end
    
    // Main monitoring logic
    always_ff @(posedge clk) begin
        if (rst) begin
            lastSelectedThread <= 0;
            cycleCount <= 0;
            stallCycles <= 0;
            recoveryCycles <= 0;
        end
        else begin
            cycleCount <= cycleCount + 1;
            
            // Log current cycle state
            $fdisplay(logFile, "Cycle %0d (Time %0t):", cycleCount, $time);
            $fdisplay(logFile, "  Selected Thread: %0d", selectedThread);
            $fdisplay(logFile, "  Next Thread ID: %0d", nextThreadID);
            $fdisplay(logFile, "  State: %s", 
                isRecovering ? "RECOVERY" : 
                isStalled ? "STALLED" : 
                clear ? "CLEAR" : "NORMAL");
            
            // Track per-thread PC values
            for (int t = 0; t < NUM_THREADS; t++) begin
                $fdisplay(logFile, "  Thread %0d PC: 0x%08x -> 0x%08x (WE=%0b)", 
                    t, pcOut[t], pcIn[t], pcWE[t]);
            end
            
            // Check thread switching behavior
            if (normalOperation) begin
                // In normal operation, count fetches per thread
                if (selectedThread == 0) begin
                    thread0FetchCount <= thread0FetchCount + 1;
                end
                else if (selectedThread == 1) begin
                    thread1FetchCount <= thread1FetchCount + 1;
                end
                
                // Check if thread switched
                if (selectedThread != lastSelectedThread) begin
                    threadSwitchCount <= threadSwitchCount + 1;
                    $fdisplay(logFile, "  >>> Thread switch detected: %0d -> %0d", 
                        lastSelectedThread, selectedThread);
                end
                
                // Verify expected round-robin behavior
                // Expected: threads should alternate (0->1->0->1...)
                expectedNextThread = (selectedThread + 1) % NUM_THREADS;
                
                // nextThreadID should be the next thread in round-robin order
                // unless we're staying on the same thread
                if (nextThreadID != expectedNextThread && 
                    nextThreadID != selectedThread) begin
                    $fdisplay(logFile, "  !!! VIOLATION: Unexpected next thread");
                    $fdisplay(logFile, "      Current: %0d, Expected next: %0d, Actual next: %0d",
                        selectedThread, expectedNextThread, nextThreadID);
                    violationCount <= violationCount + 1;
                end
                
                // Verify PC write enable is only for selected thread
                for (int t = 0; t < NUM_THREADS; t++) begin
                    if (t == selectedThread) begin
                        if (!pcWE[t]) begin
                            $fdisplay(logFile, "  !!! VIOLATION: PC not written for selected thread %0d", t);
                            violationCount <= violationCount + 1;
                        end
                    end
                    else begin
                        if (pcWE[t]) begin
                            $fdisplay(logFile, "  !!! VIOLATION: PC written for non-selected thread %0d", t);
                            violationCount <= violationCount + 1;
                        end
                    end
                end
            end
            else if (isStalled) begin
                stallCycles <= stallCycles + 1;
                $fdisplay(logFile, "  Stall cycle count: %0d", stallCycles);
                
                // During stall, selected thread should remain the same
                if (selectedThread != lastSelectedThread) begin
                    $fdisplay(logFile, "  !!! VIOLATION: Thread changed during stall");
                    violationCount <= violationCount + 1;
                end
            end
            else if (isRecovering) begin
                recoveryCycles <= recoveryCycles + 1;
                $fdisplay(logFile, "  Recovery cycle count: %0d", recoveryCycles);
                $fdisplay(logFile, "  Recovery thread ID: %0d", recoveredThreadID);
                
                // During recovery, the recovered thread should be selected
                if (nextThreadID != recoveredThreadID) begin
                    $fdisplay(logFile, "  !!! VIOLATION: Recovery thread not selected");
                    $fdisplay(logFile, "      Expected: %0d, Actual: %0d", 
                        recoveredThreadID, nextThreadID);
                    violationCount <= violationCount + 1;
                end
            end
            
            $fdisplay(logFile, "");  // Blank line for readability
            lastSelectedThread <= selectedThread;
        end
    end
    
    // Report statistics periodically
    always @(posedge clk) begin
        if (!rst && (cycleCount % 100 == 0) && cycleCount > 0) begin
            $display("=== Round-Robin Monitor Statistics (Cycle %0d) ===", cycleCount);
            $display("  Thread 0 fetches: %0d", thread0FetchCount);
            $display("  Thread 1 fetches: %0d", thread1FetchCount);
            $display("  Thread switches: %0d", threadSwitchCount);
            $display("  Violations: %0d", violationCount);
            $display("  Stall cycles: %0d", stallCycles);
            $display("  Recovery cycles: %0d", recoveryCycles);
            
            // Check for fairness (should be roughly equal)
            if (thread0FetchCount > 0 && thread1FetchCount > 0) begin
                real ratio = real'(thread0FetchCount) / real'(thread1FetchCount);
                $display("  Thread fairness ratio (T0/T1): %0f", ratio);
                if (ratio < 0.8 || ratio > 1.2) begin
                    $display("  WARNING: Unfair thread scheduling detected!");
                end
            end
            $display("================================================");
        end
    end
    
    // Final report
    final begin
        $fdisplay(logFile, "\n=== Final Statistics ===");
        $fdisplay(logFile, "Total cycles: %0d", cycleCount);
        $fdisplay(logFile, "Thread 0 fetches: %0d", thread0FetchCount);
        $fdisplay(logFile, "Thread 1 fetches: %0d", thread1FetchCount);
        $fdisplay(logFile, "Thread switches: %0d", threadSwitchCount);
        $fdisplay(logFile, "Stall cycles: %0d", stallCycles);
        $fdisplay(logFile, "Recovery cycles: %0d", recoveryCycles);
        $fdisplay(logFile, "Total violations: %0d", violationCount);
        
        if (thread0FetchCount > 0 && thread1FetchCount > 0) begin
            real ratio = real'(thread0FetchCount) / real'(thread1FetchCount);
            $fdisplay(logFile, "Fairness ratio (T0/T1): %0f", ratio);
        end
        
        if (violationCount == 0) begin
            $fdisplay(logFile, "\n*** TEST PASSED: No violations detected ***");
        end
        else begin
            $fdisplay(logFile, "\n*** TEST FAILED: %0d violations detected ***", violationCount);
        end
        
        $fclose(logFile);
        
        // Console output
        $display("\n=== Round-Robin Monitor Final Report ===");
        $display("Total cycles: %0d", cycleCount);
        $display("Thread 0 fetches: %0d", thread0FetchCount);
        $display("Thread 1 fetches: %0d", thread1FetchCount);
        $display("Thread switches: %0d", threadSwitchCount);
        $display("Violations: %0d", violationCount);
        if (violationCount == 0) begin
            $display("*** TEST PASSED ***");
        end
        else begin
            $display("*** TEST FAILED ***");
        end
        $display("========================================");
    end

endmodule : RoundRobinMonitor
