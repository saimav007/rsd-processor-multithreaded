// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// A pipeline stage for updating PC
//

import BasicTypes::*;
import PipelineTypes::*;
import MemoryMapTypes::*;
import CacheSystemTypes::*;
import FetchUnitTypes::*;

//`define RSD_STOP_FETCH_ON_PRED_MISS

// Detect the cache line boundary in sequential access
function automatic logic StepOverCacheLine (PC_Path pc1, PC_Path pc2);
    return pc1[ICACHE_LINE_BYTE_NUM_BIT_WIDTH] != pc2[ICACHE_LINE_BYTE_NUM_BIT_WIDTH];
endfunction

module NextPCStage(
    NextPCStageIF.ThisStage port,
    FetchStageIF.NextPCStage next,
    RecoveryManagerIF.NextPCStage recovery,
    ControllerIF.NextPCStage ctrl,
    DebugIF.NextPCStage debug
);

`ifdef RSD_STOP_FETCH_ON_PRED_MISS
    typedef enum logic {
        PHASE_FETCH,
        PHASE_WAIT
    } Phase;

    parameter PHASE_DELAY = 2;
    Phase phase[PHASE_DELAY];
    Phase nextPhase;
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            for (int i = 0; i < PHASE_DELAY; i++) begin
                phase[i] <= PHASE_FETCH;
            end
        end
        else if (recovery.toRecoveryPhase || recovery.toCommitPhase) begin
            for (int i = 0; i < PHASE_DELAY; i++) begin
                phase[i] <= PHASE_FETCH;
            end
        end
        else begin
            for (int i = 0; i < PHASE_DELAY - 1; i++) begin
                phase[i+1] <= phase[i];
            end
            phase[0] <= nextPhase;
        end
    end

    always_comb begin
        if (recovery.toRecoveryPhase) begin
            nextPhase = PHASE_FETCH;
        end
        else begin

            nextPhase = phase[0];
            for (int i = 0; i < INT_ISSUE_WIDTH; i++) begin
                if (port.brResult[i].valid && port.brResult[i].mispred) begin
                    nextPhase = PHASE_WAIT;
                end
            end
        end
    end
`endif

    // デバッグ用SID
    // 内部事情により，1 からはじめる
`ifndef RSD_DISABLE_DEBUG_REGISTER
    OpSerial curSID, nextSID;
    FlipFlop#( .FF_WIDTH(OP_SERIAL_WIDTH), .RESET_VALUE(1) )
        sidFF(
            .out( curSID ),
            .in ( nextSID ),
            .clk( port.clk ),
            .rst( port.rst )
        );
`endif

    PC_Path predNextPC;
    FetchStageRegPath nextStage[ FETCH_WIDTH ];

    // Pipeline Control
    logic stall, clear;
    logic regStall, beginStall;
    logic writePC_FromOuter;

    // Round-robin thread scheduler
    ThreadID nextThreadID;
    ThreadID selectedThread;
    logic threadReady[NUM_THREADS];
    logic threadSelected;
    FlipFlop#(.FF_WIDTH($clog2(NUM_THREADS)), .RESET_VALUE(0)) 
        roundRobinFF(
            .out(selectedThread),
            .in(nextThreadID),
            .clk(port.clk),
            .rst(port.rst)
        );
    always_ff @(posedge port.clk) begin
        if (port.rst) begin
            regStall <= FALSE;
        end
        else begin
            regStall <= stall;
        end
    end

    always_comb begin
        // Control
        stall = ctrl.npStage.stall;
        clear = ctrl.npStage.clear;
`ifdef RSD_STOP_FETCH_ON_PRED_MISS
        ctrl.npStageSendBubbleLower =
            (!recovery.toRecoveryPhase && phase[PHASE_DELAY - 1] == PHASE_WAIT);
`else
        ctrl.npStageSendBubbleLower = FALSE;
`endif

        beginStall = !regStall && stall;

        // Whether PC is written from outside
        if (recovery.toRecoveryPhase || recovery.recoverFromRename
                                     || port.interruptAddrWE) begin
            writePC_FromOuter = TRUE;
        end
        else begin
            writePC_FromOuter = FALSE;
        end
        
        // Update PC if not stalled.
        // NOTE: Update even during stall in the next cases:
        //   1) if PC is written from outside
        //   2) if it is beginning of stall
        //   (see the comment of regBrPred in FetchStage.sv)
        // pcWE is thread-aware - only enable for selected thread
        for (int t = 0; t < NUM_THREADS; t++) begin
            if (t == selectedThread) begin
                port.pcWE[t] = 
                    (writePC_FromOuter || !stall || beginStall) && !port.rst;
            end
            else begin
                port.pcWE[t] = FALSE;
            end
        end
    end


    //
    // Round-robin thread selection logic
    //
    always_comb begin
        // Check which threads are ready (have valid PC and are not in recovery)
        // A thread is ready if:
        //  1. Not in recovery phase
        //  2. Not recovering from rename stage
        //  3. Not stalled or beginning of stall
        for (int t = 0; t < NUM_THREADS; t++) begin
            threadReady[t] = !recovery.toRecoveryPhase && !recovery.recoverFromRename;
        end

        // Round-robin selection: alternate between threads
        // Advance to next thread when we successfully fetch (not stalled)
        nextThreadID = selectedThread;
        threadSelected = FALSE;

        // If not stalled and successfully fetching, advance to next thread in round-robin
        if (!stall && !clear && !port.rst && threadReady[selectedThread]) begin
            // Advance to next thread in round-robin order
            ThreadID nextCandidate = (selectedThread + 1) % NUM_THREADS;
            
            // Try next thread first
            if (threadReady[nextCandidate]) begin
                nextThreadID = nextCandidate;
                threadSelected = TRUE;
            end
            // If next thread not ready, try current thread
            else if (threadReady[selectedThread]) begin
                nextThreadID = selectedThread;
                threadSelected = TRUE;
            end
        end
        // If stalled or clearing, keep current thread selection
        else begin
            // Try to find any ready thread
            for (int attempt = 0; attempt < NUM_THREADS; attempt++) begin
                ThreadID candidateThread = (selectedThread + attempt) % NUM_THREADS;
                if (threadReady[candidateThread] && !threadSelected) begin
                    nextThreadID = candidateThread;
                    threadSelected = TRUE;
                end
            end
            
            // If no thread is ready, keep current thread
            if (!threadSelected) begin
                nextThreadID = selectedThread;
            end
        end
    end

    //
    // Branch Prediction
    //
    always_comb begin

        // Decide the address to input to the branch predictor
        // Use PC of the selected thread
        if (recovery.toRecoveryPhase) begin
            // Branch misprediction or an exception etc. is detected
            // Refetch instruction specified by Rw, Cm stage
            predNextPC = recovery.recoveredPC_FromRwCommit;
        end
        else if (recovery.recoverFromRename) begin
            // Detect branch misprediction in decode stage
            predNextPC = recovery.recoveredPC_FromRename;
        end
        else begin
            // Use current PC of selected thread
            predNextPC = port.pcOut[selectedThread];

            for (int i = 0; i < FETCH_WIDTH; i++) begin
                // Process of branch prediction:
                // If BTB is hit, the instruction is predicted to be a branch. 
                // In addition, if the branch is predicted as Taken, 
                // the address read from BTB is used as next PC.
                if (!regStall && next.fetchStageIsValid[i] && 
                        next.btbHit[i] && next.brPredTaken[i]) begin
                    // Use PC from BTB
                    predNextPC = next.btbOut[i];
                    break;
                end
            end
        end
        // To Branch predictor
        port.predNextPC = predNextPC;
    end


    //
    //  Updating PC
    //
    always_comb begin

        // --- PC Update for selected thread
        if (port.interruptAddrWE) begin
            // When an interrupt occurs, use interrupt address.
            // NOTE: This input can be a critical path.
            // Hence, interrupt address is input to PC first rather than 
            // input to the branch predictor directly.
            port.pcIn[selectedThread] = port.interruptAddrIn;
        end
        else if (beginStall) begin
            // Update PC based on the branch prediction result accessed
            // immediately before the stall if it is beginning of stall.
            // (see the comment of regBrPred in FetchStage.sv)
            port.pcIn[selectedThread] = predNextPC;
        end
        else begin
            // Increment PC
            port.pcIn[selectedThread] = predNextPC + FETCH_WIDTH*INSN_BYTE_WIDTH;
            for (int i = 1; i < FETCH_WIDTH; i++) begin
                if (StepOverCacheLine(predNextPC, 
                                     predNextPC+i*INSN_BYTE_WIDTH)) begin
                    // When PC stepped over the border of cache line, stop there
                    port.pcIn[selectedThread] = predNextPC+i*INSN_BYTE_WIDTH;
                    break;
                end
            end
        end

        // For other threads, keep PC unchanged when not selected
        for (int t = 0; t < NUM_THREADS; t++) begin
            if (t != selectedThread) begin
                port.pcIn[t] = port.pcOut[t];
            end
        end

        // Assign threadID and other fields for each fetch lane
        for (int i = 0; i < FETCH_WIDTH; i++) begin
`ifndef RSD_DISABLE_DEBUG_REGISTER
            // Generate serial id for dumping
            nextStage[i].sid = curSID + i;
`endif
            nextStage[i].threadID = selectedThread;
            nextStage[i].pc = predNextPC + i * INSN_BYTE_WIDTH;
            if (port.interruptAddrWE || clear ||
                StepOverCacheLine(predNextPC, nextStage[i].pc)) begin
                nextStage[i].valid = FALSE;
            end
            else begin
                nextStage[i].valid = TRUE;
            end
        end

        port.nextStage = nextStage;
    end


    //
    // I-cache Access
    //
    AddrPath fetchAddr;
    always_comb begin
        // Decide input address of I-cache
        if (next.fetchStageIsValid[0] && stall) begin
            // Use the PC of the IF stage
            fetchAddr = ToAddrFromPC(next.fetchStagePC[0]);
        end
        else begin
            // Use the PC of this stage
            fetchAddr = ToAddrFromPC(predNextPC);
        end
        
        // To I-cache
        port.icNextReadAddrIn = ToPhyAddrFromLogical(fetchAddr);
    end


`ifndef RSD_DISABLE_DEBUG_REGISTER
    logic [FETCH_WIDTH : 0] numValidInsns;
    always_comb begin
        numValidInsns = 0; // Count valid instructions in this stage
        for (int i = 0; i < FETCH_WIDTH; i++) begin
            if (!nextStage[i].valid) begin
                break;
            end
            else begin
                numValidInsns++;
            end
        end

        // Update serial ID.
        nextSID = ( stall || clear) ? 
            curSID : (curSID + numValidInsns);

        // --- Debug Register
        for ( int i = 0; i < FETCH_WIDTH; i++ ) begin
            debug.npReg[i].valid = stall ? FALSE : nextStage[i].valid;
            debug.npReg[i].sid = nextStage[i].sid;
        end
    end
`endif

endmodule : NextPCStage
