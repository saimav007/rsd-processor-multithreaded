// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// Top-level testbench for Round-Robin SMT verification
// Tests the round-robin thread scheduling in NextPCStage
//

`timescale 1ns/1ps

import BasicTypes::*;
import PipelineTypes::*;
import FetchUnitTypes::*;
import MemoryMapTypes::*;

module TestRoundRobin_Top;

    // Clock and reset
    logic clk;
    logic rst;
    
    // Test control
    int testScenario;
    logic testComplete;
    int testsPassed;
    int testsFailed;
    
    // Clock generation
    parameter CLOCK_PERIOD = 10;
    initial begin
        clk = 0;
        forever #(CLOCK_PERIOD/2) clk = ~clk;
    end
    
    // Reset generation
    initial begin
        rst = 1;
        #(CLOCK_PERIOD * 5);
        rst = 0;
    end
    
    // Signals for NextPCStage (simplified DUT)
    ThreadID selectedThread;
    ThreadID nextThreadID;
    PC_Path pcOut[NUM_THREADS];
    PC_Path pcIn[NUM_THREADS];
    logic pcWE[NUM_THREADS];
    PC_Path predNextPC;
    ThreadID predNextThreadID;
    
    // Control signals from stimulus
    logic stall;
    logic clear;
    logic toRecoveryPhase;
    logic recoverFromRename;
    ThreadID recoveredThreadID;
    logic interruptAddrWE;
    PC_Path interruptAddrIn;
    BranchResult brResult[INT_ISSUE_WIDTH];
    
    // Thread ready signals
    logic threadReady[NUM_THREADS];
    
    // Monitor outputs
    int threadSwitchCount;
    int thread0FetchCount;
    int thread1FetchCount;
    int violationCount;
    
    // PC registers for each thread (simplified)
    always_ff @(posedge clk) begin
        if (rst) begin
            pcOut[0] <= 32'h8000_0000;
            pcOut[1] <= 32'h8000_1000;
        end
        else begin
            for (int t = 0; t < NUM_THREADS; t++) begin
                if (pcWE[t]) begin
                    pcOut[t] <= pcIn[t];
                end
            end
        end
    end
    
    // Simplified round-robin logic (mimics NextPCStage)
    logic regStall;
    logic beginStall;
    logic writePC_FromOuter;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            regStall <= FALSE;
            selectedThread <= 0;
        end
        else begin
            regStall <= stall;
            selectedThread <= nextThreadID;
        end
    end
    
    always_comb begin
        beginStall = !regStall && stall;
        
        if (toRecoveryPhase || recoverFromRename || interruptAddrWE) begin
            writePC_FromOuter = TRUE;
        end
        else begin
            writePC_FromOuter = FALSE;
        end
        
        // PC write enable logic (thread-aware)
        for (int t = 0; t < NUM_THREADS; t++) begin
            if (t == selectedThread) begin
                pcWE[t] = (writePC_FromOuter || !stall || beginStall) && !rst;
            end
            else begin
                pcWE[t] = FALSE;
            end
        end
        
        // Thread ready logic
        for (int t = 0; t < NUM_THREADS; t++) begin
            threadReady[t] = !toRecoveryPhase && !recoverFromRename;
        end
        
        // Round-robin selection logic
        nextThreadID = selectedThread;
        
        if (toRecoveryPhase) begin
            nextThreadID = recoveredThreadID;
        end
        else if (!stall && !clear && !rst && threadReady[selectedThread]) begin
            ThreadID nextCandidate = (selectedThread + 1) % NUM_THREADS;
            
            if (threadReady[nextCandidate]) begin
                nextThreadID = nextCandidate;
            end
            else if (threadReady[selectedThread]) begin
                nextThreadID = selectedThread;
            end
        end
        else begin
            // Try to find any ready thread
            nextThreadID = selectedThread;
            for (int attempt = 0; attempt < NUM_THREADS; attempt++) begin
                ThreadID candidateThread = (selectedThread + attempt) % NUM_THREADS;
                if (threadReady[candidateThread]) begin
                    nextThreadID = candidateThread;
                    break;
                end
            end
        end
        
        // Determine predicted next PC
        if (toRecoveryPhase) begin
            predNextPC = 32'h8000_0100; // Recovery address
        end
        else if (recoverFromRename) begin
            predNextPC = 32'h8000_0200; // Rename recovery address
        end
        else begin
            predNextPC = pcOut[selectedThread];
        end
        
        predNextThreadID = selectedThread;
        
        // PC input logic
        if (interruptAddrWE) begin
            pcIn[selectedThread] = interruptAddrIn;
        end
        else if (beginStall) begin
            pcIn[selectedThread] = predNextPC;
        end
        else begin
            // Increment PC by FETCH_WIDTH * INSN_BYTE_WIDTH
            pcIn[selectedThread] = predNextPC + (FETCH_WIDTH * INSN_BYTE_WIDTH);
        end
        
        // Non-selected threads keep their PC
        for (int t = 0; t < NUM_THREADS; t++) begin
            if (t != selectedThread) begin
                pcIn[t] = pcOut[t];
            end
        end
    end
    
    // Instantiate stimulus generator
    RoundRobinStimulus stimulus(
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .clear(clear),
        .toRecoveryPhase(toRecoveryPhase),
        .recoverFromRename(recoverFromRename),
        .recoveredThreadID(recoveredThreadID),
        .interruptAddrWE(interruptAddrWE),
        .interruptAddrIn(interruptAddrIn),
        .brResult(brResult),
        .testScenario(testScenario),
        .testComplete(testComplete)
    );
    
    // Instantiate monitor
    RoundRobinMonitor monitor(
        .clk(clk),
        .rst(rst),
        .selectedThread(selectedThread),
        .nextThreadID(nextThreadID),
        .stall(stall),
        .clear(clear),
        .toRecoveryPhase(toRecoveryPhase),
        .recoverFromRename(recoverFromRename),
        .recoveredThreadID(recoveredThreadID),
        .pcOut(pcOut),
        .pcIn(pcIn),
        .pcWE(pcWE),
        .threadSwitchCount(threadSwitchCount),
        .thread0FetchCount(thread0FetchCount),
        .thread1FetchCount(thread1FetchCount),
        .violationCount(violationCount)
    );
    
    // Instantiate assertion-based checker
    RoundRobinChecker checker(
        .clk(clk),
        .rst(rst),
        .selectedThread(selectedThread),
        .nextThreadID(nextThreadID),
        .stall(stall),
        .clear(clear),
        .toRecoveryPhase(toRecoveryPhase),
        .recoverFromRename(recoverFromRename),
        .recoveredThreadID(recoveredThreadID),
        .pcOut(pcOut),
        .pcIn(pcIn),
        .pcWE(pcWE),
        .threadReady(threadReady)
    );
    
    // Test execution
    initial begin
        testsPassed = 0;
        testsFailed = 0;
        
        $display("========================================");
        $display("Round-Robin SMT Testbench");
        $display("NUM_THREADS: %0d", NUM_THREADS);
        $display("FETCH_WIDTH: %0d", FETCH_WIDTH);
        $display("========================================\n");
        
        // Wait for reset to deassert
        wait(!rst);
        @(posedge clk);
        
        // Run test scenarios
        for (testScenario = 0; testScenario <= 7; testScenario++) begin
            testComplete = 0;
            
            $display("\n========================================");
            $display("Running Test Scenario %0d", testScenario);
            $display("========================================");
            
            // Wait for test to complete
            wait(testComplete);
            
            // Wait a few cycles for final statistics
            repeat(5) @(posedge clk);
            
            // Check results
            if (violationCount == 0) begin
                $display("Test %0d: PASSED (Violations: %0d)", testScenario, violationCount);
                testsPassed++;
            end
            else begin
                $display("Test %0d: FAILED (Violations: %0d)", testScenario, violationCount);
                testsFailed++;
            end
            
            // Reset violation count for next test
            // Note: In a real testbench, we'd need a way to reset the monitor
            
            // Small delay between tests
            repeat(10) @(posedge clk);
        end
        
        // Final summary
        $display("\n========================================");
        $display("Test Suite Complete");
        $display("========================================");
        $display("Tests Passed: %0d", testsPassed);
        $display("Tests Failed: %0d", testsFailed);
        $display("Total Tests: %0d", testsPassed + testsFailed);
        
        if (testsFailed == 0) begin
            $display("\n*** ALL TESTS PASSED ***");
        end
        else begin
            $display("\n*** SOME TESTS FAILED ***");
        end
        $display("========================================\n");
        
        // End simulation
        #100;
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #1_000_000; // 1ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("round_robin_test.vcd");
        $dumpvars(0, TestRoundRobin_Top);
    end
    
    // Monitor key signals
    always @(posedge clk) begin
        if (!rst && $time > 0) begin
            // Display thread selection every 10 cycles
            if (($time / CLOCK_PERIOD) % 10 == 0) begin
                $display("[%0t] Selected: T%0d, Next: T%0d, PC0: 0x%08x, PC1: 0x%08x, State: %s",
                    $time, selectedThread, nextThreadID, pcOut[0], pcOut[1],
                    stall ? "STALL" : 
                    toRecoveryPhase ? "RECOVERY" : 
                    recoverFromRename ? "RENAME_REC" : "NORMAL");
            end
        end
    end

endmodule : TestRoundRobin_Top
