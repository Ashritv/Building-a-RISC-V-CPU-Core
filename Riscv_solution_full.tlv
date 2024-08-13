\m4_TLV_version 1d: tl-x.org
\SV
   // This code can be found in: https://github.com/stevehoover/LF-Building-a-RISC-V-CPU-Core/risc-v_shell.tlv
   
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/LF-Building-a-RISC-V-CPU-Core/main/lib/risc-v_shell_lib.tlv'])


   //---------------------------------------------------------------------------------
   // /====================\
   // | Sum 1 to 9 Program |
   // \====================/
   //
   // Program to test RV32I
   // Add 1,2,3,...,9 (in that order).
   //
   // Regs:
   //  x12 (a2): 10
   //  x13 (a3): 1..10
   //  x14 (a4): Sum
   // 
  // m4_asm(ADDI, x14, x0, 0)             // Initialize sum register a4 with 0
  // m4_asm(ADDI, x12, x0, 1010)          // Store count of 10 in register a2.
  // m4_asm(ADDI, x13, x0, 1)             // Initialize loop count register a3 with 0
   // Loop:
  // m4_asm(ADD, x14, x13, x14)           // Incremental summation
  // m4_asm(ADDI, x13, x13, 1)            // Increment loop count by 1
  // m4_asm(BLT, x13, x12, 1111111111000) // If a3 is less than a2, branch to label named <loop>
   // Test result value in x14, and set x31 to reflect pass/fail.
   //m4_asm(ADDI, x30, x14, 111111010100) // Subtract expected value of 44 to set x30 to 1 if and only iff the result is 45 (1 + 2 + ... + 9).
  // m4_asm(BGE, x0, x0, 0) // Done. Jump to itself (infinite loop). (Up to 20-bit signed immediate plus implicit 0 bit (unlike JALR) provides byte address; last immediate bit should also be 0)
   //m4_asm(ADD, x0, x7, x8) //added instruction to reflect change in value of register 0                
   //m4_asm_end()
   //m4_define(['M4_MAX_CYC'], 50)
   //---------------------------------------------------------------------------------
   m4_test_prog()


\SV
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)
   /* verilator lint_on WIDTH */
\TLV
   //Program Counter
   $reset = *reset;
   $pc[31:0] = >>1$next_pc;
   $next_pc[31:0] = $reset ? 0 :
                    $taken_br ? $br_tgt_pc :// added this during constructing branch stage 
                    $is_jal ? $br_tgt_pc ://  added both Jump and link , jump and link register during final phase 
                    $is_jalr ? $jalr_tgt_pc :
                    ($pc + 32'd4);
   
   
   //Instruction Memory access
   `READONLY_MEM($pc/*address*/, $$instr[31:0]/*Instruction to be stored here*/);
   
   //Decode logic
   //Instruction type - immediate,register,jump,branch,store,upper immediate
   $is_i_instr = $instr[6:2] ==?5'b0000x || // it says whether 5bits in opcde match with given combination
                 $instr[6:2] ==?5'b001x0 ||
                 $instr[6:2] ==?5'b11001;
   
   $is_r_instr = $instr[6:2] ==?5'b011x0 ||
                 $instr[6:2] ==?5'b01011 ||
                 $instr[6:2] ==?5'b10100;
   
   $is_s_instr = $instr[6:2] ==?5'b0100x;
   $is_u_instr = $instr[6:2] ==?5'b0x101;
   $is_b_instr = $instr[6:2] ==?5'b11000;
   $is_j_instr = $instr[6:2] ==?5'b11011;
   
   //Instruction Fileds ($funct3, $rs1, $rs2, $rd, $opcode)
   $opcode[6:0] = $instr[6:0];
   $rd[4:0] = $instr[11:7];
   $funct3[2:0] = $instr[14:12];
   $rs1[4:0] = $instr[19:15];
   $rs2[4:0] = $instr[24:20];
   
   //Load instruction using only opcode 
   $is_load = ($opcode ==? 7'b0x00011);
   
   //Determining validity i.e in which all instr are valid(look at the base instructions format table)
   $rs2_valid = $is_r_instr || $is_s_instr || $is_b_instr;
   $rs1_valid = $is_r_instr || $is_s_instr || $is_b_instr || $is_i_instr;
   $rd_valid = $is_r_instr || $is_u_instr || $is_j_instr || $is_i_instr;
   $funct3_valid = $is_r_instr || $is_s_instr || $is_b_instr || $is_i_instr;
   $imm_valid = $is_s_instr || $is_b_instr || $is_i_instr || $is_u_instr || $is_j_instr;
   
   //produces no logic,but looks like a signal consumption,so warnings are suppressed --line could be removed after signals are used
   `BOGUS_USE($rd $rd_valid $rs1 $rs1_valid $rs2 $rs2_valid $opcode $imm_valid $funct3 $funct3_valid) 
   
   //Immediate field logic
   $imm[31:0] = $is_i_instr ? {  {21{$instr[31]}},  $instr[30:20]  } :
                $is_s_instr ? { {21{$instr[31]}}, $instr[11:7], $instr[30:25] } :
                $is_j_instr ? { {12{$instr[31]}}, $instr[19:12], $instr[20], $instr[30:21], 1'b0 } :
                $is_b_instr ? { {20{$instr[31]}}, $instr[7], $instr[30:25], $instr[11:8], 1'b0 } :
                $is_u_instr ? { $instr[31:12], 12'b0 } :
                              32'b0;  // Default
   
   //Determining specific operation using (opcode,funct3,funct7)
   $dec_bits[10:0] = {$instr[30], $funct3, $opcode};
   
   $is_beq = $dec_bits ==? 11'bx_000_1100011;
   $is_bne = $dec_bits ==? 11'bx_001_1100011;
   $is_blt = $dec_bits ==? 11'bx_100_1100011;
   $is_bge = $dec_bits ==? 11'bx_101_1100011;
   $is_bltu = $dec_bits ==? 11'bx_110_1100011;
   $is_bgeu = $dec_bits ==? 11'bx_111_1100011;
   $is_add = $dec_bits ==? 11'b0_000_0110011;
   $is_addi = $dec_bits ==? 11'bx_000_0010011;
   $is_slti = $dec_bits ==? 11'bx0100010011;
   $is_sltiu = $dec_bits ==? 11'bx0110010011;
   $is_xori = $dec_bits ==? 11'bx1000010011;
   $is_ori = $dec_bits ==? 11'bx1100010011;
   $is_andi = $dec_bits ==? 11'bx1110010011;
   $is_slli = $dec_bits ==? 11'b00010010011;
   $is_srli = $dec_bits ==? 11'b01010010011;
   $is_srai = $dec_bits ==? 11'b11010010011;
   $is_sub = $dec_bits ==? 11'b10000110011;
   $is_sll = $dec_bits ==? 11'b00010110011;
   $is_slt = $dec_bits ==? 11'b00100110011;
   $is_sltu = $dec_bits ==? 11'b00110110011;
   $is_xor = $dec_bits ==? 11'b01000110011;
   $is_srl = $dec_bits ==? 11'b01010110011;
   $is_sra = $dec_bits ==? 11'b11010110011;
   $is_or = $dec_bits ==? 11'b01100110011;
   $is_and = $dec_bits ==? 11'b01110110011;
   $is_lui = $dec_bits ==? 11'bxxxx0110111;
   $is_auipc = $dec_bits ==? 11'bxxxx0010111;
   $is_jal = $dec_bits ==? 11'bxxxx1101111;
   $is_jalr = $dec_bits ==? 11'bx0001100111;
   
   //there will be many warnings for these unused signals so use this to keep log clean
   `BOGUS_USE($imm $ $is_beq $is_bne $is_blt $is_bge $is_bltu $is_bgeu $is_add $is_addi)
   
   // Checking if rs1 and rs2 are valid for instruction to enable read and read data outputed to src1_value and 2
   $rd_en1 = $rs1_valid;
   $rd_en2 = $rs2_valid;
   $rd_index1[4:0] = $rd_en1 ? $rs1 : 0;// condition ? value_if_true : value_if_false;
   $rd_index2[4:0] = $rd_en2 ? $rs2 : 0;
   $src1_value[31:0] = $rd_data1;   // I made a mistake of not specifying 32 bit in src1_value due to which i was getting 0 and 1
   $src2_value[31:0] = $rd_data2;  // i.e $src1_value = $rd_data1-- which stores single bit result in src1_value
   
   //----> Full ALU unit code 
   
   // SLTU and SLTI (set if less than,unsigned) results:
   $sltu_rslt[31:0] = {31'b0, $src1_value < $src2_value};
   $sltiu_rslt[31:0] = {31'b0, $src1_value < $imm};
   
   // SRA and SRAI (shift right,arithmetic) results:
   // sign-extended src1
   $sext_src1[63:0] = {{32{$src1_value[31]}}, $src1_value};
   // 64-bit sign-extended results to be truncated
   $sra_rslt[63:0] = $sext_src1 >> $src2_value[4:0];
   $srai_rslt[63:0] = $sext_src1 >> $imm[4:0];
   
   //ALU support for all instructions --Started with add and addi instruction now extended for all 
   $result[31:0] = $is_andi ? $src1_value & $imm:
                   $is_ori ? $src1_value | $imm:
                   $is_xori ? $src1_value ^ $imm:
                   $is_addi ? $src1_value + $imm:
                   $is_slli ? $src1_value << $imm[5:0]:
                   $is_srli ? $src1_value >> $imm[5:0]:
                   $is_and ? $src1_value & $src2_value:
                   $is_or ? $src1_value | $src2_value:
                   $is_xor ? $src1_value ^ $src2_value:
                   $is_add ? $src1_value + $src2_value:
                   $is_sub ? $src1_value - $src2_value:
                   $is_sll ? $src1_value << $src2_value:
                   $is_srl ? $src1_value >> $src2_value:
                   $is_sltu ? $sltu_rslt:
                   $is_sltiu ? $sltiu_rslt:
                   $is_lui ? {$imm[31:12], 12'b0}:
                   $is_auipc ? $pc + {$imm[31:12], 12'b0}:
                   $is_jal ? $pc + 32'd4:
                   $is_jalr ? $pc + 32'd4:
                   $is_slt ? (($src1_value[31] == $src2_value[31]) ? $sltu_rslt : {31'b0, $src1_value[31]}):
                   $is_slti ? (($src1_value[31] == $imm[31]) ? $sltu_rslt : {31'b0, $src1_value[31]}):
                   $is_sra ? $sra_rslt[31:0]:
                   $is_srai ? $srai_rslt[31:0]:
                   ($is_load || $is_s_instr) ? $src1_value + $imm: // Calculation of effective address in AlU stage for load and store 
                   32'b0;
                   
   //Adding a MUX to select either result or $ld_data depending on instruction                 
   $result_write_rf[31:0] = $is_load ? $ld_data[31:0] : $result;
   
   
   //Register File write
   $wr_en = $rd_valid && $rd != 0;
   $wr_index[4:0] = $wr_en ? $rd : 0;
   $wr_data[31:0] = $result;
   
   //Branch Taken or not 
   $taken_br = $is_beq ? ($src1_value == $src2_value ? 1'b1 : 1'b0) : // 1'b1 and 1'b0 is taken so that it acts as select line for mux in program counter 
               $is_bne ? ($src1_value != $src2_value ? 1'b1 : 1'b0) :  // where if $taken_br = 1'b1 means branch is taken and next_pc = pc + immediate value otherwise pc = pc +32d4
               $is_blt ? (($src1_value < $src2_value) ^ ($src1_value[31] != $src2_value[31]) ? 1'b1 : 1'b0) :
               $is_bge ? (($src1_value >= $src2_value) ^ ($src1_value[31] != $src2_value[31]) ? 1'b1 : 1'b0) :
               $is_bltu ? ($src1_value < $src2_value ? 1'b1 : 1'b0) :
               $is_bgeu ? ($src1_value >= $src2_value ? 1'b1 : 1'b0) :
               1'b0 ;
   
   // Branch target pc 
   $br_tgt_pc[31:0] = $pc[31:0] + $imm;
   $jalr_tgt_pc[31:0] = $src1_value + $imm;
   
   
   // Assert these to end simulation (before Makerchip cycle limit).
   m4+tb()
   *failed = *cyc_cnt > M4_MAX_CYC;
   
   m4+rf(32, 32, $reset, $wr_en, $wr_index[4:0], $wr_data[31:0], $rd_en1, $rd_index1[4:0], $rd_data1, $rd_en2, $rd_index2[4:0], $rd_data2)
   m4+dmem(32, 32, $reset, $result[6:2], $is_s_instr, $src2_value, $is_load, $ld_data) //($addr[4:0], $wr_en, $wr_data[31:0], $rd_en, $rd_data)
   m4+cpu_viz()
\SV
   endmodule
