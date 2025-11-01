// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// PC
// PC has INSN_RESET_VECTOR and cannot use AddrReg.
//

import BasicTypes::*;
import MemoryMapTypes::*;

// module PC( NextPCStageIF.PC port );
    
//     FlipFlopWE#( PC_WIDTH, INSN_RESET_VECTOR ) 
//         body( 
//             .out( port.pcOut ), 
//             .in ( port.pcIn ),
//             .we ( port.pcWE ), 
//             .clk( port.clk ),
//             .rst( port.rst )
//         );
        
// endmodule : PC

        // In PC.sv - thread aware 
        module PC( NextPCStageIF.PC port );

            genvar i;
            generate
                for (i = 0; i < NUM_THREADS; i++) begin : gen_pc_ff
                    FlipFlopWE#( PC_WIDTH, INSN_RESET_VECTOR )
                        body(
                            .out( port.pcOut[i] ),
                            .in ( port.pcIn[i] ),
                            .we ( port.pcWE[i] ),
                            .clk( port.clk ),
                            .rst( port.rst )
                        );
                end
            endgenerate

        endmodule : PC
