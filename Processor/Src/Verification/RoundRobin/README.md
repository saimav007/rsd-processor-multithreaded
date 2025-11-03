# Round-Robin SMT Testbench Environment

## Overview
This testbench environment verifies the round-robin multiplexing between 2 threads in the RSD processor's fetch stage for Simultaneous Multi-Threading (SMT) support.

## Components

### 1. `TestRoundRobin_Top.sv`
Top-level testbench module that instantiates all components and runs test scenarios.

### 2. `RoundRobinMonitor.sv`
Monitors the NextPCStage signals and verifies correct round-robin behavior:
- Tracks which thread is selected each cycle
- Verifies thread alternation when conditions are met
- Detects protocol violations

### 3. `RoundRobinStimulus.sv`
Generates stimulus signals for various test scenarios:
- Normal operation (no stalls, no recovery)
- Stall conditions
- Recovery/flush scenarios
- Interrupt handling
- Mixed scenarios

### 4. `RoundRobinScoreboard.sv`
Tracks expected vs actual behavior:
- Maintains expected thread selection
- Compares with actual thread selection
- Reports mismatches

### 5. `RoundRobinChecker.sv`
Assertion-based checker for key properties:
- Thread alternation in normal operation
- Proper handling of stalls
- Recovery behavior
- PC management per thread

## Test Scenarios

1. **Basic Round-Robin**: Verify alternation between threads in normal operation
2. **Stall Handling**: Verify thread selection during stalls
3. **Recovery Testing**: Verify thread selection during pipeline recovery
4. **Priority Testing**: Verify recovery thread gets priority
5. **PC Independence**: Verify each thread maintains independent PC

## Running Tests

```bash
cd Verification/RoundRobin
make clean
make run
```

## Expected Behavior

### Normal Operation
- Thread 0 fetches, then Thread 1 fetches, then Thread 0, etc.
- Each thread maintains independent PC
- PC increments by FETCH_WIDTH*INSN_BYTE_WIDTH per fetch

### During Stall
- Selected thread remains unchanged
- No thread switching occurs

### During Recovery
- Recovery thread gets selected immediately
- Normal round-robin resumes after recovery

## Outputs

- **round_robin_test.log**: Detailed cycle-by-cycle log
- **round_robin_results.txt**: Summary of test results
- **waveform.vcd**: VCD waveform for debugging
