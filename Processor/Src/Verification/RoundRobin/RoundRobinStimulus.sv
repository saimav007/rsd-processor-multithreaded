// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.

//
// Round-Robin Stimulus Generator
// Generates various test scenarios for round-robin verification
//

`timescale 1ns/1ps

import BasicTypes::*;
import PipelineTypes::*;

module RoundRobinStimulus(
    input logic clk,
    input logic rst,
    
    // Control signals to drive
    output logic stall,
    output logic clear,
    output logic toRecoveryPhase,
    output logic recoverFromRename,
    output ThreadID recoveredThreadID,
    output logic interruptAddrWE,
    output PC_Path interruptAddrIn,
    output BranchResult brResult[INT_ISSUE_WIDTH],
    
    // Test control
    input int testScenario,
    output logic testComplete
);

    // Test scenario definitions
    typedef enum int {
        TEST_NORMAL_OPERATION = 0,
        TEST_STALL_BEHAVIOR = 1,
        TEST_RECOVERY_THREAD0 = 2,
        TEST_RECOVERY_THREAD1 = 3,
        TEST_RENAME_RECOVERY = 4,
        TEST_INTERRUPT = 5,
        TEST_MIXED_SCENARIOS = 6,
        TEST_STRESS = 7
    } TestScenarioType;
    
    int cycleInTest;
    logic testStarted;
    
    // Initialize
    initial begin
        stall = FALSE;
        clear = FALSE;
        toRecoveryPhase = FALSE;
        recoverFromRename = FALSE;
        recoveredThreadID = 0;
        interruptAddrWE = FALSE;
        interruptAddrIn = 32'h0;
        testComplete = FALSE;
        cycleInTest = 0;
        testStarted = FALSE;
        
        // Initialize branch results
        for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
            brResult[i].valid = FALSE;
            brResult[i].mispred = FALSE;
            brResult[i].threadID = 0;
            brResult[i].pc = 32'h0;
            brResult[i].nextPC = 32'h0;
        end
    end
    
    // Main stimulus generation
    always_ff @(posedge clk) begin
        if (rst) begin
            stall <= FALSE;
            clear <= FALSE;
            toRecoveryPhase <= FALSE;
            recoverFromRename <= FALSE;
            recoveredThreadID <= 0;
            interruptAddrWE <= FALSE;
            testComplete <= FALSE;
            cycleInTest <= 0;
            testStarted <= FALSE;
            
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                brResult[i].valid <= FALSE;
                brResult[i].mispred <= FALSE;
            end
        end
        else begin
            if (!testStarted) begin
                testStarted <= TRUE;
                $display("Starting test scenario: %0d", testScenario);
            end
            
            cycleInTest <= cycleInTest + 1;
            
            // Default values
            stall <= FALSE;
            clear <= FALSE;
            toRecoveryPhase <= FALSE;
            recoverFromRename <= FALSE;
            interruptAddrWE <= FALSE;
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                brResult[i].valid <= FALSE;
                brResult[i].mispred <= FALSE;
            end
            
            // Generate stimulus based on test scenario
            case (testScenario)
                TEST_NORMAL_OPERATION: begin
                    // Simple test: no stalls, no recovery
                    // Let threads alternate naturally
                    if (cycleInTest >= 50) begin
                        testComplete <= TRUE;
                        $display("Test NORMAL_OPERATION completed at cycle %0d", cycleInTest);
                    end
                end
                
                TEST_STALL_BEHAVIOR: begin
                    // Test stall behavior
                    // Stall for a few cycles, then resume
                    if (cycleInTest >= 10 && cycleInTest < 20) begin
                        stall <= TRUE;
                    end
                    else if (cycleInTest >= 30 && cycleInTest < 35) begin
                        stall <= TRUE;
                    end
                    
                    if (cycleInTest >= 60) begin
                        testComplete <= TRUE;
                        $display("Test STALL_BEHAVIOR completed at cycle %0d", cycleInTest);
                    end
                end
                
                TEST_RECOVERY_THREAD0: begin
                    // Test recovery from thread 0
                    if (cycleInTest == 15) begin
                        toRecoveryPhase <= TRUE;
                        recoveredThreadID <= 0;
                        $display("Triggering recovery to Thread 0 at cycle %0d", cycleInTest);
                    end
                    else if (cycleInTest == 40) begin
                        toRecoveryPhase <= TRUE;
                        recoveredThreadID <= 0;
                        $display("Triggering recovery to Thread 0 at cycle %0d", cycleInTest);
                    end
                    
                    if (cycleInTest >= 70) begin
                        testComplete <= TRUE;
                        $display("Test RECOVERY_THREAD0 completed at cycle %0d", cycleInTest);
                    end
                end
                
                TEST_RECOVERY_THREAD1: begin
                    // Test recovery from thread 1
                    if (cycleInTest == 15) begin
                        toRecoveryPhase <= TRUE;
                        recoveredThreadID <= 1;
                        $display("Triggering recovery to Thread 1 at cycle %0d", cycleInTest);
                    end
                    else if (cycleInTest == 40) begin
                        toRecoveryPhase <= TRUE;
                        recoveredThreadID <= 1;
                        $display("Triggering recovery to Thread 1 at cycle %0d", cycleInTest);
                    end
                    
                    if (cycleInTest >= 70) begin
                        testComplete <= TRUE;
                        $display("Test RECOVERY_THREAD1 completed at cycle %0d", cycleInTest);
                    end
                end
                
                TEST_RENAME_RECOVERY: begin
                    // Test recovery from rename stage
                    if (cycleInTest == 20) begin
                        recoverFromRename <= TRUE;
                        recoveredThreadID <= 0;
                        $display("Triggering rename recovery at cycle %0d", cycleInTest);
                    end
                    else if (cycleInTest == 45) begin
                        recoverFromRename <= TRUE;
                        recoveredThreadID <= 1;
                        $display("Triggering rename recovery at cycle %0d", cycleInTest);
                    end
                    
                    if (cycleInTest >= 70) begin
                        testComplete <= TRUE;
                        $display("Test RENAME_RECOVERY completed at cycle %0d", cycleInTest);
                    end
                end
                
                TEST_INTERRUPT: begin
                    // Test interrupt behavior
                    if (cycleInTest == 25) begin
                        interruptAddrWE <= TRUE;
                        interruptAddrIn <= 32'h8000_0100;
                        $display("Triggering interrupt at cycle %0d", cycleInTest);
                    end
                    
                    if (cycleInTest >= 60) begin
                        testComplete <= TRUE;
                        $display("Test INTERRUPT completed at cycle %0d", cycleInTest);
                    end
                end
                
                TEST_MIXED_SCENARIOS: begin
                    // Mix of stalls, recovery, and normal operation
                    if (cycleInTest >= 10 && cycleInTest < 15) begin
                        stall <= TRUE;
                    end
                    else if (cycleInTest == 25) begin
                        toRecoveryPhase <= TRUE;
                        recoveredThreadID <= 1;
                    end
                    else if (cycleInTest >= 40 && cycleInTest < 43) begin
                        stall <= TRUE;
                    end
                    else if (cycleInTest == 50) begin
                        recoverFromRename <= TRUE;
                        recoveredThreadID <= 0;
                    end
                    else if (cycleInTest == 70) begin
                        toRecoveryPhase <= TRUE;
                        recoveredThreadID <= 1;
                    end
                    
                    if (cycleInTest >= 100) begin
                        testComplete <= TRUE;
                        $display("Test MIXED_SCENARIOS completed at cycle %0d", cycleInTest);
                    end
                end
                
                TEST_STRESS: begin
                    // Stress test with frequent events
                    // Stall every 5 cycles for 2 cycles
                    if (cycleInTest % 5 == 0 && cycleInTest % 10 != 0) begin
                        stall <= TRUE;
                    end
                    
                    // Recovery every 20 cycles
                    if (cycleInTest % 20 == 0 && cycleInTest > 0) begin
                        toRecoveryPhase <= TRUE;
                        recoveredThreadID <= ThreadID'(cycleInTest / 20) % NUM_THREADS;
                        $display("Stress test recovery at cycle %0d", cycleInTest);
                    end
                    
                    if (cycleInTest >= 150) begin
                        testComplete <= TRUE;
                        $display("Test STRESS completed at cycle %0d", cycleInTest);
                    end
                end
                
                default: begin
                    // Unknown test
                    if (cycleInTest >= 10) begin
                        testComplete <= TRUE;
                        $display("ERROR: Unknown test scenario %0d", testScenario);
                    end
                end
            endcase
        end
    end
    
    // Generate branch misprediction events for testing
    always_ff @(posedge clk) begin
        if (!rst && testScenario == TEST_RECOVERY_THREAD0) begin
            // Simulate branch misprediction for thread 0
            if (cycleInTest == 14) begin
                brResult[0].valid <= TRUE;
                brResult[0].mispred <= TRUE;
                brResult[0].threadID <= 0;
                brResult[0].pc <= 32'h8000_0040;
                brResult[0].nextPC <= 32'h8000_0100;
            end
        end
        else if (!rst && testScenario == TEST_RECOVERY_THREAD1) begin
            // Simulate branch misprediction for thread 1
            if (cycleInTest == 14) begin
                brResult[0].valid <= TRUE;
                brResult[0].mispred <= TRUE;
                brResult[0].threadID <= 1;
                brResult[0].pc <= 32'h8000_0044;
                brResult[0].nextPC <= 32'h8000_0200;
            end
        end
    end

endmodule : RoundRobinStimulus
