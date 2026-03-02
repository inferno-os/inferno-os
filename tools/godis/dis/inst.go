package dis

import "fmt"

// Operand represents a single instruction operand.
type Operand struct {
	Mode byte  // AFP, AMP, AIMM, AXXX, AFP|AIND, AMP|AIND
	Val  int32 // Offset or immediate value
	Ind  int32 // Second indirection offset (only for AIND modes)
}

// NoOperand is a sentinel for unused operand slots.
var NoOperand = Operand{Mode: AXXX}

// FP creates a frame-pointer-relative operand.
func FP(offset int32) Operand {
	return Operand{Mode: AFP, Val: offset}
}

// MP creates a module-pointer-relative operand.
func MP(offset int32) Operand {
	return Operand{Mode: AMP, Val: offset}
}

// Imm creates an immediate-value operand.
func Imm(val int32) Operand {
	return Operand{Mode: AIMM, Val: val}
}

// FPInd creates an indirect frame-pointer operand: val(offset(fp)).
func FPInd(fpOff, indOff int32) Operand {
	return Operand{Mode: AFP | AIND, Val: fpOff, Ind: indOff}
}

// MPInd creates an indirect module-pointer operand: val(offset(mp)).
func MPInd(mpOff, indOff int32) Operand {
	return Operand{Mode: AMP | AIND, Val: mpOff, Ind: indOff}
}

// SrcDstMode returns the addressing mode bits for use in the src or dst
// position of the address byte.
func (o Operand) SrcDstMode() byte {
	switch o.Mode {
	case AMP:
		return AMP
	case AFP:
		return AFP
	case AIMM:
		return AIMM
	case AXXX:
		return AXXX
	case AMP | AIND:
		return AMP | AIND
	case AFP | AIND:
		return AFP | AIND
	default:
		return AXXX
	}
}

// MidMode returns the addressing mode bits for use in the middle
// operand position of the address byte.
func (o Operand) MidMode() byte {
	switch o.Mode {
	case AIMM:
		return AXIMM
	case AFP:
		return AXINF
	case AMP:
		return AXINM
	default:
		return AXNON
	}
}

// IsNone returns true if this operand is unused.
func (o Operand) IsNone() bool {
	return o.Mode == AXXX
}

// IsIndirect returns true if this operand uses indirect addressing.
func (o Operand) IsIndirect() bool {
	return o.Mode&AIND != 0
}

func (o Operand) String() string {
	switch o.Mode {
	case AXXX:
		return "-"
	case AFP:
		return fmt.Sprintf("%d(fp)", o.Val)
	case AMP:
		return fmt.Sprintf("%d(mp)", o.Val)
	case AIMM:
		return fmt.Sprintf("$%d", o.Val)
	case AFP | AIND:
		return fmt.Sprintf("%d(%d(fp))", o.Ind, o.Val)
	case AMP | AIND:
		return fmt.Sprintf("%d(%d(mp))", o.Ind, o.Val)
	default:
		return "???"
	}
}

// Inst represents a single Dis VM instruction.
type Inst struct {
	Op  Op
	Src Operand
	Mid Operand
	Dst Operand
}

// NewInst creates an instruction with source, middle, and destination operands.
func NewInst(op Op, src, mid, dst Operand) Inst {
	return Inst{Op: op, Src: src, Mid: mid, Dst: dst}
}

// Inst2 creates an instruction with source and destination (no middle operand).
func Inst2(op Op, src, dst Operand) Inst {
	return Inst{Op: op, Src: src, Mid: NoOperand, Dst: dst}
}

// Inst1 creates an instruction with only a destination operand.
func Inst1(op Op, dst Operand) Inst {
	return Inst{Op: op, Src: NoOperand, Mid: NoOperand, Dst: dst}
}

// Inst0 creates an instruction with no operands (e.g., IRET, IEXIT).
func Inst0(op Op) Inst {
	return Inst{Op: op, Src: NoOperand, Mid: NoOperand, Dst: NoOperand}
}

// AddressByte computes the encoded address byte for this instruction.
func (inst Inst) AddressByte() byte {
	src := inst.Src.SrcDstMode()
	dst := inst.Dst.SrcDstMode()
	mid := inst.Mid.MidMode()
	return (src << 3) | dst | mid
}

func (inst Inst) String() string {
	s := inst.Op.String()
	if !inst.Src.IsNone() {
		s += " " + inst.Src.String()
	}
	if !inst.Mid.IsNone() {
		s += ", " + inst.Mid.String()
	}
	if !inst.Dst.IsNone() {
		s += ", " + inst.Dst.String()
	}
	return s
}
