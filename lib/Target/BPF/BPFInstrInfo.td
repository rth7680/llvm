//===-- BPFInstrInfo.td - Target Description for BPF Target ---------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file describes the BPF instructions in TableGen format.
//
//===----------------------------------------------------------------------===//

include "BPFInstrFormats.td"

// Instruction Operands and Patterns

// These are target-independent nodes, but have target-specific formats.
def SDT_BPFCallSeqStart : SDCallSeqStart<[SDTCisVT<0, iPTR>]>;
def SDT_BPFCallSeqEnd   : SDCallSeqEnd<[SDTCisVT<0, iPTR>, SDTCisVT<1, iPTR>]>;
def SDT_BPFCall         : SDTypeProfile<0, -1, [SDTCisVT<0, iPTR>]>;
def SDT_BPFSetFlag      : SDTypeProfile<0, 3, [SDTCisSameAs<0, 1>]>;
def SDT_BPFSelectCC     : SDTypeProfile<1, 5, [SDTCisSameAs<1, 2>,
                                               SDTCisSameAs<0, 4>,
                                               SDTCisSameAs<4, 5>]>;
def SDT_BPFBrCC         : SDTypeProfile<0, 4, [SDTCisSameAs<0, 1>,
                                               SDTCisVT<3, OtherVT>]>;
def SDT_BPFWrapper      : SDTypeProfile<1, 1, [SDTCisSameAs<0, 1>,
                                               SDTCisPtrTy<0>]>;

def BPFcall         : SDNode<"BPFISD::CALL", SDT_BPFCall,
                             [SDNPHasChain, SDNPOptInGlue, SDNPOutGlue,
                              SDNPVariadic]>;
def BPFretflag      : SDNode<"BPFISD::RET_FLAG", SDTNone,
                             [SDNPHasChain, SDNPOptInGlue, SDNPVariadic]>;
def BPFcallseq_start: SDNode<"ISD::CALLSEQ_START", SDT_BPFCallSeqStart,
                             [SDNPHasChain, SDNPOutGlue]>;
def BPFcallseq_end  : SDNode<"ISD::CALLSEQ_END",   SDT_BPFCallSeqEnd,
                             [SDNPHasChain, SDNPOptInGlue, SDNPOutGlue]>;
def BPFbrcc         : SDNode<"BPFISD::BR_CC", SDT_BPFBrCC,
                             [SDNPHasChain, SDNPOutGlue, SDNPInGlue]>;

def BPFselectcc     : SDNode<"BPFISD::SELECT_CC", SDT_BPFSelectCC, [SDNPInGlue]>;
def BPFWrapper      : SDNode<"BPFISD::Wrapper", SDT_BPFWrapper>;

def brtarget : Operand<OtherVT>;
def calltarget : Operand<i64>;

def u64imm   : Operand<i64> {
  let PrintMethod = "printImm64Operand";
}

def i64immSExt32 : PatLeaf<(imm),
                [{return isInt<32>(N->getSExtValue()); }]>;

// Addressing modes.
def ADDRri : ComplexPattern<i64, 2, "SelectAddr", [], []>;
def FIri : ComplexPattern<i64, 2, "SelectFIAddr", [add, or], []>;

// Address operands
def MEMri : Operand<i64> {
  let PrintMethod = "printMemOperand";
  let EncoderMethod = "getMemoryOpValue";
  let MIOperandInfo = (ops GPR, i16imm);
}

// Conditional code predicates - used for pattern matching for jump instructions
def BPF_CC_EQ  : PatLeaf<(imm),
                         [{return (N->getZExtValue() == ISD::SETEQ);}]>;
def BPF_CC_NE  : PatLeaf<(imm),
                         [{return (N->getZExtValue() == ISD::SETNE);}]>;
def BPF_CC_GE  : PatLeaf<(imm),
                         [{return (N->getZExtValue() == ISD::SETGE);}]>;
def BPF_CC_GT  : PatLeaf<(imm),
                         [{return (N->getZExtValue() == ISD::SETGT);}]>;
def BPF_CC_GTU : PatLeaf<(imm),
                         [{return (N->getZExtValue() == ISD::SETUGT);}]>;
def BPF_CC_GEU : PatLeaf<(imm),
                         [{return (N->getZExtValue() == ISD::SETUGE);}]>;

// jump instructions
class JMP_RR<bits<4> Opc, string OpcodeStr, PatLeaf Cond>
    : F_COF<5 /* BPF_JMP */, Opc, 1 /* BPF_X */,
            (outs), (ins GPR:$dst, GPR:$src, brtarget:$BrDst),
            !strconcat(OpcodeStr, "\t$dst, $src goto $BrDst"),
            [(BPFbrcc GPR:$dst, GPR:$src, Cond, bb:$BrDst)]> {
  bits<4> dst;
  bits<4> src;
  bits<16> BrDst;
  let BPFDst = dst;
  let BPFSrc = src;
  let BPFOff = BrDst;
  let BPFImm = 0;
}

class JMP_RI<bits<4> Opc, string OpcodeStr, PatLeaf Cond>
    : F_COF<5 /* BPF_JMP */, Opc, 0 /* BPF_K */,
            (outs), (ins GPR:$dst, i64imm:$imm, brtarget:$BrDst),
            !strconcat(OpcodeStr, "i\t$dst, $imm goto $BrDst"),
            [(BPFbrcc GPR:$dst, i64immSExt32:$imm, Cond, bb:$BrDst)]> {
  bits<4> dst;
  bits<32> imm;
  bits<16> BrDst;
  let BPFDst = dst;
  let BPFSrc = 0;
  let BPFImm = imm;
  let BPFOff = BrDst;
}

multiclass J<bits<4> Opc, string OpcodeStr, PatLeaf Cond> {
  def _rr : JMP_RR<Opc, OpcodeStr, Cond>;
  def _ri : JMP_RI<Opc, OpcodeStr, Cond>;
}

let isBranch = 1, isTerminator = 1, hasDelaySlot=0 in {
// cmp+goto instructions
  defm JEQ  : J<0x1, "jeq",  BPF_CC_EQ>;
  defm JNE  : J<0x5, "jne",  BPF_CC_NE>;
  defm JUGT : J<0x2, "jgt", BPF_CC_GTU>;
  defm JUGE : J<0x3, "jge", BPF_CC_GEU>;
  defm JSGT : J<0x6, "jsgt", BPF_CC_GT>;
  defm JSGE : J<0x7, "jsge", BPF_CC_GE>;
}

// ALU instructions
class ALU_RI<bits<4> Opc, string OpcodeStr, SDNode OpNode>
    : F_COF<7 /* BPF_ALU64 */, Opc, 0 /* BPF_K */,
           (outs GPR:$dst), (ins GPR:$srcd, i64imm:$imm),
	   !strconcat(OpcodeStr, "i\t$dst, $imm"),
           [(set GPR:$dst, (OpNode GPR:$srcd, i64immSExt32:$imm))]> {
  bits<4> dst;
  bits<32> imm;
  let BPFDst = dst;
  let BPFSrc = 0;
  let BPFOff = 0;
  let BPFImm = imm;
}

class ALU_RR<bits<4> Opc, string OpcodeStr, SDNode OpNode>
    : F_COF<7 /* BPF_ALU64 */, Opc, 1 /* BPF_X */,
            (outs GPR:$dst), (ins GPR:$srcd, GPR:$src),
            !strconcat(OpcodeStr, "\t$dst, $src"),
            [(set GPR:$dst, (OpNode GPR:$srcd, GPR:$src))]> {
  bits<4> dst;
  bits<4> src;
  let BPFDst = dst;
  let BPFSrc = src;
  let BPFOff = 0;
  let BPFImm = 0;
}

multiclass ALU<bits<4> Opc, string OpcodeStr, SDNode OpNode> {
  def _rr : ALU_RR<Opc, OpcodeStr, OpNode>;
  def _ri : ALU_RI<Opc, OpcodeStr, OpNode>;
}

let Constraints = "$dst = $srcd" in {
  let isAsCheapAsAMove = 1 in {
    let isCommutable = 1 in {
      defm ADD : ALU<0x0, "add", add>;
      defm OR  : ALU<0x4, "or", or>;
      defm AND : ALU<0x5, "and", and>;
      defm XOR : ALU<0xa, "xor", xor>;
    }
    defm SUB : ALU<0x1, "sub", sub>;
    defm SLL : ALU<0x6, "sll", shl>;
    defm SRL : ALU<0x7, "srl", srl>;
    defm SRA : ALU<0xc, "sra", sra>;

    def NEG_r
      : F_COF<7 /* BPF_ALU64 */, 8 /* BPF_NEG */, 0,
              (outs GPR:$dst), (ins GPR:$srcd),
              "neg\t$dst",
              [(set GPR:$dst, (ineg GPR:$srcd))]> {
      bits<4> dst;
      let BPFDst = dst;
      let BPFSrc = 0;
      let BPFOff = 0;
      let BPFImm = 0;
    }
  }
  let isCommutable = 1 in {
    defm MUL : ALU<0x2, "mul", mul>;
  }
  defm DIV : ALU<0x3, "div", udiv>;
  defm MOD : ALU<0x9, "mod", urem>;
}

let isReMaterializable = 1, isAsCheapAsAMove = 1 in {

  def MOV_rr
    : F_COF<7 /* BPF_ALU64 */, 0xb /* BPF_MOV */, 1 /* BPF_X */,
            (outs GPR:$dst), (ins GPR:$src),
            "mov\t$dst, $src", []> {
    bits<4> dst;
    bits<4> src;
    let BPFDst = dst;
    let BPFSrc = src;
    let BPFOff = 0;
    let BPFImm = 0;
  }

  let isMoveImm = 1 in {
  def MOV_ri
    : F_COF<7 /* BPF_ALU64 */, 0xb /* BPF_MOV */, 0 /* BPF_K */,
           (outs GPR:$dst), (ins i64imm:$imm),
           "mov\t$dst, $imm",
           [(set GPR:$dst, (i64 i64immSExt32:$imm))]> {
    bits<4> dst;
    bits<32> imm;
    let BPFDst = dst;
    let BPFSrc = 0;
    let BPFOff = 0;
    let BPFImm = imm;
  }

  def LD_imm64
    : F_CMS<0 /* BPF_LD */, 0 /* BPF_IMM */, 3 /* BPF_DW */,
            (outs GPR:$dst), (ins u64imm:$imm),
            "ld_64\t$dst, $imm", []> {
    bits<4> dst;
    bits<64> imm;
    let BPFDst = dst;
    let BPFSrc = 0;
    let BPFOff = 0;
    let BPFImm = imm{31-0};
  }

  def LD_pseudo
    : F_CMS<0 /* BPF_LD */, 0 /* BPF_IMM */, 3 /* BPF_DW */,
            (outs GPR:$dst), (ins i64imm:$pseudo, u64imm:$imm),
            "ld_pseudo\t$dst, $pseudo, $imm",
            [(set GPR:$dst, (int_bpf_pseudo imm:$pseudo, imm:$imm))]> {
    bits<4> dst;
    bits<4> pseudo;
    bits<64> imm;
    let BPFDst = dst;
    let BPFSrc = pseudo;
    let BPFOff = 0;
    let BPFImm = imm{31-0};
  }
  } // isMoveImm
}

def FI_ri
    : InstBPF<(outs GPR:$dst), (ins MEMri:$addr),
               "lea\t$dst, $addr",
               [(set GPR:$dst, FIri:$addr)]> {
  // This is a tentative instruction, and will be replaced
  // with MOV_rr and ADD_ri in PEI phase
}

let hasSideEffects = 0 in {
  def NOP
    : F_COF<7 /* BPF_ALU64 */, 0xb /* BPF_MOV */, 1 /* BPF_X */,
            (outs), (ins), "nop", []> {
    // mov r0, r0 == nop
    let BPFDst = 0;
    let BPFSrc = 0;
    let BPFOff = 0;
    let BPFImm = 0;
  }
}

// STORE instructions
class STORE<bits<2> SizeOp, string OpcodeStr, list<dag> Pattern>
    : F_CMS<3 /* BPF_STX */, 3 /* BPF_MEM */, SizeOp,
           (outs), (ins GPR:$src, MEMri:$addr),
           !strconcat(OpcodeStr, "\t$addr, $src"), Pattern> {
  bits<4> src;
  bits<20> addr;
  let BPFSrc = src;
  let BPFDst = addr{19-16}; // base reg
  let BPFOff = addr{15-0};  // offset
  let BPFImm = 0;
}

class STOREi64<bits<2> Opc, string OpcodeStr, PatFrag OpNode>
    : STORE<Opc, OpcodeStr, [(OpNode GPR:$src, ADDRri:$addr)]>;

def STW : STOREi64<0x0, "stw", truncstorei32>;
def STH : STOREi64<0x1, "sth", truncstorei16>;
def STB : STOREi64<0x2, "stb", truncstorei8>;
def STD : STOREi64<0x3, "std", store>;

// LOAD instructions
class LOAD<bits<2> SizeOp, string OpcodeStr, list<dag> Pattern>
    : F_CMS<1 /* BPF_LDX */, 3 /* BPF_MEM */, SizeOp,
            (outs GPR:$dst), (ins MEMri:$addr),
            !strconcat(OpcodeStr, "\t$dst, $addr"), Pattern> {
  bits<4> dst;
  bits<20> addr;
  let BPFDst = dst;
  let BPFSrc = addr{19-16}; // base reg
  let BPFOff = addr{15-0};  // offset
  let BPFImm = 0;
}

class LOADi64<bits<2> SizeOp, string OpcodeStr, PatFrag OpNode>
    : LOAD<SizeOp, OpcodeStr, [(set GPR:$dst, (OpNode ADDRri:$addr))]>;

def LDW : LOADi64<0x0, "ldw", zextloadi32>;
def LDH : LOADi64<0x1, "ldh", zextloadi16>;
def LDB : LOADi64<0x2, "ldb", zextloadi8>;
def LDD : LOADi64<0x3, "ldd", load>;

// Jump always
let isBranch = 1, isTerminator = 1, hasDelaySlot=0, isBarrier = 1 in {
  def JMP
    : F_COF<5 /* BPF_JMP */, 0 /* BPF_JA */, 0 /* BPF_K */,
            (outs), (ins brtarget:$BrDst),
            "jmp\t$BrDst", [(br bb:$BrDst)]> {
    bits<16> BrDst;
    let BPFDst = 0;
    let BPFSrc = 0;
    let BPFOff = BrDst;
    let BPFImm = 0;
  }
}

// Jump and link
let isCall=1, hasDelaySlot=0, Uses = [R11],
    // Potentially clobbered registers
    Defs = [R0, R1, R2, R3, R4, R5] in {
  def JAL
    : F_COF<5 /* BPF_JMP */, 8 /* BPF_CALL */, 0 /* BPF_K */,
            (outs), (ins calltarget:$BrDst),
            "call\t$BrDst", []> {
    bits<32> BrDst;
    let BPFDst = 0;
    let BPFSrc = 0;
    let BPFOff = 0;
    let BPFImm = BrDst;
  }
}

let isReturn = 1, isTerminator = 1, hasDelaySlot=0, isBarrier = 1,
    isNotDuplicable = 1 in {
  def RET
    : F_COF<5 /* BPF_JMP */, 9 /* BPF_EXIT */, 0 /* BPF_K */,
            (outs), (ins), "ret", [(BPFretflag)]> {
    let BPFDst = 0;
    let BPFSrc = 0;
    let BPFOff = 0;
    let BPFImm = 0;
  }
}

// ADJCALLSTACKDOWN/UP pseudo insns
let Defs = [R11], Uses = [R11] in {
def ADJCALLSTACKDOWN : Pseudo<(outs), (ins i64imm:$amt),
                              "#ADJCALLSTACKDOWN $amt",
                              [(BPFcallseq_start timm:$amt)]>;
def ADJCALLSTACKUP   : Pseudo<(outs), (ins i64imm:$amt1, i64imm:$amt2),
                              "#ADJCALLSTACKUP $amt1 $amt2",
                              [(BPFcallseq_end timm:$amt1, timm:$amt2)]>;
}

let usesCustomInserter = 1 in {
  def Select : Pseudo<(outs GPR:$dst),
                      (ins GPR:$lhs, GPR:$rhs, i64imm:$imm, GPR:$src, GPR:$src2),
                      "# Select PSEUDO $dst = $lhs $imm $rhs ? $src : $src2",
                      [(set i64:$dst,
                       (BPFselectcc i64:$lhs, i64:$rhs, (i64 imm:$imm), i64:$src, i64:$src2))]>;
}

// load 64-bit global addr into register
def : Pat<(BPFWrapper tglobaladdr:$in), (LD_imm64 tglobaladdr:$in)>;

// 0xffffFFFF doesn't fit into simm32, optimize common case
def : Pat<(i64 (and (i64 GPR:$src), 0xffffFFFF)),
          (SRL_ri (SLL_ri (i64 GPR:$src), 32), 32)>;

// Calls
def : Pat<(BPFcall tglobaladdr:$dst), (JAL tglobaladdr:$dst)>;
def : Pat<(BPFcall imm:$dst), (JAL imm:$dst)>;

// Loads
def : Pat<(extloadi8  ADDRri:$src), (i64 (LDB ADDRri:$src))>;
def : Pat<(extloadi16 ADDRri:$src), (i64 (LDH ADDRri:$src))>;
def : Pat<(extloadi32 ADDRri:$src), (i64 (LDW ADDRri:$src))>;

// Atomics
class XADD<bits<2> SizeOp, string OpcodeStr, PatFrag OpNode>
    : F_CMS<3 /* BPF_STX */, 6 /* BPF_XADD */, SizeOp,
            (outs GPR:$dst), (ins MEMri:$addr, GPR:$srcd),
            !strconcat(OpcodeStr, "\t$dst, $addr, $srcd"),
            [(set GPR:$dst, (OpNode ADDRri:$addr, GPR:$srcd))]> {
  bits<4> srcd;
  bits<20> addr;
  let BPFSrc = srcd;
  let BPFDst = addr{19-16}; // base reg
  let BPFOff = addr{15-0};  // offset
  let BPFImm = 0;
}

let Constraints = "$dst = $srcd" in {
  def XADD32 : XADD<0, "xadd32", atomic_load_add_32>;
  def XADD64 : XADD<3, "xadd64", atomic_load_add_64>;
  // undefined def XADD16 : XADD<1, "xadd16", atomic_load_add_16>;
  // undefined def XADD8  : XADD<2, "xadd8", atomic_load_add_8>;
}

// bswap16, bswap32, bswap64
// (TODO: use BPF_TO_LE for big-endian target)
class BSWAP<bits<32> SizeOp, string OpcodeStr, list<dag> Pattern>
    : F_COF<4 /* BPF_ALU */, 0xd /* BPF_END */, 1 /* BPF_TO_BE */,
            (outs GPR:$dst), (ins GPR:$src),
            !strconcat(OpcodeStr, "\t$dst"), Pattern> {
  bits<4> dst;
  let BPFDst = dst;
  let BPFSrc = 0;
  let BPFOff = 0;
  let BPFImm = SizeOp;
}

let Constraints = "$dst = $src" in {
  def BSWAP16 : BSWAP<16, "bswap16",
                      [(set GPR:$dst, (srl (bswap GPR:$src), (i64 48)))]>;
  def BSWAP32 : BSWAP<32, "bswap32",
                      [(set GPR:$dst, (srl (bswap GPR:$src), (i64 32)))]>;
  def BSWAP64 : BSWAP<64, "bswap64",
                      [(set GPR:$dst, (bswap GPR:$src))]>;
}

let Defs = [R0, R1, R2, R3, R4, R5], Uses = [R6], hasSideEffects = 1,
    hasExtraDefRegAllocReq = 1, hasExtraSrcRegAllocReq = 1, mayLoad = 1 in {

class LOAD_ABS<bits<2> SizeOp, string OpcodeStr, Intrinsic OpNode>
    : F_CMS<0 /* BPF_LD */, 1 /* BPF_ABS */, SizeOp,
            (outs), (ins GPR:$skb, i64imm:$imm),
            !strconcat(OpcodeStr, "\tr0, $skb.data + $imm"),
            [(set R0, (OpNode GPR:$skb, i64immSExt32:$imm))]> {
  bits<32> imm;
  let BPFDst = 0;
  let BPFSrc = 0;
  let BPFOff = 0;
  let BPFImm = imm;
}

class LOAD_IND<bits<2> SizeOp, string OpcodeStr, Intrinsic OpNode>
    : F_CMS<0 /* BPF_LD */, 2 /* BPF_IND */, SizeOp,
            (outs), (ins GPR:$skb, GPR:$val),
            !strconcat(OpcodeStr, "\tr0, $skb.data + $val"),
            [(set R0, (OpNode GPR:$skb, GPR:$val))]> {
  bits<4> val;
  let BPFDst = 0;
  let BPFSrc = val;
  let BPFOff = 0;
  let BPFImm = 0;
}
}

def LD_ABS_B : LOAD_ABS<2, "ldabs_b", int_bpf_load_byte>;
def LD_ABS_H : LOAD_ABS<1, "ldabs_h", int_bpf_load_half>;
def LD_ABS_W : LOAD_ABS<0, "ldabs_w", int_bpf_load_word>;

def LD_IND_B : LOAD_IND<2, "ldind_b", int_bpf_load_byte>;
def LD_IND_H : LOAD_IND<1, "ldind_h", int_bpf_load_half>;
def LD_IND_W : LOAD_IND<0, "ldind_w", int_bpf_load_word>;
