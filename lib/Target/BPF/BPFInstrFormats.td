//===-- BPFInstrFormats.td - BPF Instruction Formats -------*- tablegen -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

class InstBPF<dag outs, dag ins, string asmstr, list<dag> pattern>
  : Instruction {
  field bits<64> Inst;
  field bits<64> SoftFail = 0;
  let Size = 8;

  let Namespace = "BPF";
  let DecoderNamespace = "BPF";

  dag OutOperandList = outs;
  dag InOperandList = ins;
  let AsmString = asmstr;
  let Pattern = pattern;
}

// Pseudo instructions
class Pseudo<dag outs, dag ins, string asmstr, list<dag> pattern>
  : InstBPF<outs, ins, asmstr, pattern> {
  let Inst{63-0} = 0;
  let isPseudo = 1;
}

// Format "Code, Mode, Size", used by load/store insns.
class F_CMS<bits<3> cls, bits<3> mode, bits<2> sz,
            dag outs, dag ins, string asmstr, list<dag> pattern>
  : InstBPF<outs, ins, asmstr, pattern> {
  bits<4> BPFDst;
  bits<4> BPFSrc;
  bits<16> BPFOff;
  bits<32> BPFImm;

  let Inst{63-61} = mode;
  let Inst{60-59} = sz;
  let Inst{58-56} = cls;
  let Inst{55-52} = BPFSrc;
  let Inst{51-48} = BPFDst;
  let Inst{47-32} = BPFOff;
  let Inst{31-0} = BPFImm;
}

// Format "Code, Op, source Flag", used by ALU and misc insns.
class F_COF<bits<3> cls, bits<4> op, bits<1> srcf,
            dag outs, dag ins, string asmstr, list<dag> pattern>
  : InstBPF<outs, ins, asmstr, pattern> {
  bits<4> BPFDst;
  bits<4> BPFSrc;
  bits<16> BPFOff;
  bits<32> BPFImm;

  let Inst{63-60} = op;
  let Inst{59} = srcf;
  let Inst{58-56} = cls;
  let Inst{55-52} = BPFSrc;
  let Inst{51-48} = BPFDst;
  let Inst{47-32} = BPFOff;
  let Inst{31-0} = BPFImm;
}
