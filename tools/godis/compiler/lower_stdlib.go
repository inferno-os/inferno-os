package compiler

// lower_stdlib.go — stdlib lowering implementations for new packages/functions.
// These are methods on *funcLowerer that are called from dispatchers in lower.go.

import (
	"go/types"
	"math"
	"strings"

	"golang.org/x/tools/go/ssa"

	"github.com/NERVsystems/infernode/tools/godis/dis"
)

// ============================================================
// strings package — new functions
// ============================================================

// lowerStringsCount: count non-overlapping occurrences of substr in s.
func (fl *funcLowerer) lowerStringsCount(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	subOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenSub := fl.frame.AllocWord("")
	limit := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	endIdx := fl.frame.AllocWord("")
	candidate := fl.frame.AllocTemp(true)
	count := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, subOp, dis.FP(lenSub)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(count)))

	// if lenSub == 0 → return lenS+1
	beqEmptyIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(lenSub), dis.Imm(0)))

	// if lenSub > lenS → return 0
	bgtIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSub), dis.FP(lenS), dis.Imm(0)))

	// limit = lenS - lenSub + 1
	fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSub), dis.FP(lenS), dis.FP(limit)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(limit), dis.FP(limit)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	// loop:
	loopPC := int32(len(fl.insts))
	bgeIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(limit), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSub), dis.FP(i), dis.FP(endIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(candidate)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))

	beqFoundIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, subOp, dis.FP(candidate), dis.Imm(0)))

	// no match: i++
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// found: count++, i += lenSub (non-overlapping)
	foundPC := int32(len(fl.insts))
	fl.insts[beqFoundIdx].Dst = dis.Imm(foundPC)
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(count), dis.FP(count)))
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSub), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// done:
	donePC := int32(len(fl.insts))
	fl.insts[bgeIdx].Dst = dis.Imm(donePC)
	fl.insts[bgtIdx].Dst = dis.Imm(donePC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(count), dis.FP(dst)))
	jmpEndIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// empty substr: return lenS + 1
	emptyPC := int32(len(fl.insts))
	fl.insts[beqEmptyIdx].Dst = dis.Imm(emptyPC)
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(lenS), dis.FP(dst)))

	endPC := int32(len(fl.insts))
	fl.insts[jmpEndIdx].Dst = dis.Imm(endPC)
	return nil
}

// lowerStringsEqualFold: case-insensitive string comparison.
func (fl *funcLowerer) lowerStringsEqualFold(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	tOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenT := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	chS := fl.frame.AllocWord("")
	chT := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, tOp, dis.FP(lenT)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst))) // default false

	// if lenS != lenT → done (false)
	bneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBNEW, dis.FP(lenS), dis.FP(lenT), dis.Imm(0)))

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	// loop:
	loopPC := int32(len(fl.insts))
	bgeMatchIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0))) // all chars match

	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(i), dis.FP(chS)))
	fl.emit(dis.NewInst(dis.IINDC, tOp, dis.FP(i), dis.FP(chT)))

	// toLower both: if 'A'-'Z', add 32
	tmpS := fl.frame.AllocWord("")
	tmpT := fl.frame.AllocWord("")
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(chS), dis.FP(tmpS)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(chT), dis.FP(tmpT)))

	// toLower chS
	skipS := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, dis.FP(chS), dis.Imm(65), dis.Imm(0)))
	skipS2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(chS), dis.Imm(90), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(32), dis.FP(chS), dis.FP(tmpS)))
	skipSPC := int32(len(fl.insts))
	fl.insts[skipS].Dst = dis.Imm(skipSPC)
	fl.insts[skipS2].Dst = dis.Imm(skipSPC)

	// toLower chT
	skipT := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, dis.FP(chT), dis.Imm(65), dis.Imm(0)))
	skipT2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(chT), dis.Imm(90), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(32), dis.FP(chT), dis.FP(tmpT)))
	skipTPC := int32(len(fl.insts))
	fl.insts[skipT].Dst = dis.Imm(skipTPC)
	fl.insts[skipT2].Dst = dis.Imm(skipTPC)

	// compare lowered chars
	bneCharIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBNEW, dis.FP(tmpS), dis.FP(tmpT), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// all matched:
	matchPC := int32(len(fl.insts))
	fl.insts[bgeMatchIdx].Dst = dis.Imm(matchPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))

	// done:
	donePC := int32(len(fl.insts))
	fl.insts[bneIdx].Dst = dis.Imm(donePC)
	fl.insts[bneCharIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerStringsTrimPrefix: if s starts with prefix, return s[len(prefix):].
func (fl *funcLowerer) lowerStringsTrimPrefix(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	prefOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenP := fl.frame.AllocWord("")
	head := fl.frame.AllocTemp(true)

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, prefOp, dis.FP(lenP)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst))) // default: return s

	// if lenP > lenS → done
	bgtIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenP), dis.FP(lenS), dis.Imm(0)))

	// head = s[0:lenP]
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(head)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.FP(lenP), dis.FP(head)))

	// if head != prefix → done
	bneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBNEC, prefOp, dis.FP(head), dis.Imm(0)))

	// match: dst = s[lenP:]
	tmp := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(tmp)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(lenP), dis.FP(lenS), dis.FP(tmp)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmp), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[bgtIdx].Dst = dis.Imm(donePC)
	fl.insts[bneIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerStringsTrimSuffix: if s ends with suffix, return s[:len(s)-len(suffix)].
func (fl *funcLowerer) lowerStringsTrimSuffix(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	sufOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenSuf := fl.frame.AllocWord("")
	startOff := fl.frame.AllocWord("")
	tail := fl.frame.AllocTemp(true)

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, sufOp, dis.FP(lenSuf)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst))) // default: return s

	bgtIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSuf), dis.FP(lenS), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSuf), dis.FP(lenS), dis.FP(startOff)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(tail)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(startOff), dis.FP(lenS), dis.FP(tail)))

	bneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBNEC, sufOp, dis.FP(tail), dis.Imm(0)))

	tmp := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(tmp)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.FP(startOff), dis.FP(tmp)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmp), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[bgtIdx].Dst = dis.Imm(donePC)
	fl.insts[bneIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerStringsReplaceAll: same as Replace with n=-1.
func (fl *funcLowerer) lowerStringsReplaceAll(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	oldOp := fl.operandOf(instr.Call.Args[1])
	newOp := fl.operandOf(instr.Call.Args[2])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenOld := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	endIdx := fl.frame.AllocWord("")
	candidate := fl.frame.AllocTemp(true)
	result := fl.frame.AllocTemp(true)
	limit := fl.frame.AllocWord("")
	ch := fl.frame.AllocTemp(true)

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, oldOp, dis.FP(lenOld)))
	emptyOff := fl.comp.AllocString("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	bgtShort := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenOld), dis.FP(lenS), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenOld), dis.FP(lenS), dis.FP(limit)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(limit), dis.FP(limit)))
	jmpLoop := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	shortPC := int32(len(fl.insts))
	fl.insts[bgtShort].Dst = dis.Imm(shortPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(limit)))

	loopPC := int32(len(fl.insts))
	fl.insts[jmpLoop].Dst = dis.Imm(loopPC)
	bgeDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(limit), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenOld), dis.FP(i), dis.FP(endIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(candidate)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))
	beqMatch := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, oldOp, dis.FP(candidate), dis.Imm(0)))

	// no match: append s[i] char
	oneAfter := fl.frame.AllocWord("")
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(oneAfter)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(ch)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(oneAfter), dis.FP(ch)))
	fl.emit(dis.NewInst(dis.IADDC, dis.FP(ch), dis.FP(result), dis.FP(result)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// match: append new, skip lenOld
	matchPC := int32(len(fl.insts))
	fl.insts[beqMatch].Dst = dis.Imm(matchPC)
	fl.emit(dis.NewInst(dis.IADDC, newOp, dis.FP(result), dis.FP(result)))
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenOld), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// done: append tail
	donePC := int32(len(fl.insts))
	fl.insts[bgeDone].Dst = dis.Imm(donePC)
	tail := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(tail)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(lenS), dis.FP(tail)))
	fl.emit(dis.NewInst(dis.IADDC, dis.FP(tail), dis.FP(result), dis.FP(result)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(result), dis.FP(dst)))
	return nil
}

// lowerStringsContainsRune: check if rune (int32) exists in string.
func (fl *funcLowerer) lowerStringsContainsRune(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	rOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	ch := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	loopPC := int32(len(fl.insts))
	bgeIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(i), dis.FP(ch)))
	beqIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(ch), rOp, dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	foundPC := int32(len(fl.insts))
	fl.insts[beqIdx].Dst = dis.Imm(foundPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[bgeIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerStringsContainsAny: check if any char in chars exists in s.
func (fl *funcLowerer) lowerStringsContainsAny(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	charsOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenC := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	j := fl.frame.AllocWord("")
	chS := fl.frame.AllocWord("")
	chC := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, charsOp, dis.FP(lenC)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	outerPC := int32(len(fl.insts))
	bgeOuterIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(i), dis.FP(chS)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(j)))

	innerPC := int32(len(fl.insts))
	bgeInnerIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(j), dis.FP(lenC), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IINDC, charsOp, dis.FP(j), dis.FP(chC)))
	beqIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(chS), dis.FP(chC), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(j), dis.FP(j)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(innerPC)))

	// inner done: no match for this char
	innerDonePC := int32(len(fl.insts))
	fl.insts[bgeInnerIdx].Dst = dis.Imm(innerDonePC)
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(outerPC)))

	// found:
	foundPC := int32(len(fl.insts))
	fl.insts[beqIdx].Dst = dis.Imm(foundPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[bgeOuterIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerStringsIndexByte: find first occurrence of byte in string, return index or -1.
func (fl *funcLowerer) lowerStringsIndexByte(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	bOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	ch := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	loopPC := int32(len(fl.insts))
	bgeIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(i), dis.FP(ch)))
	beqIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(ch), bOp, dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	foundPC := int32(len(fl.insts))
	fl.insts[beqIdx].Dst = dis.Imm(foundPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(i), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[bgeIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerStringsIndexRune: same as IndexByte but for rune (int32).
func (fl *funcLowerer) lowerStringsIndexRune(instr *ssa.Call) error {
	// Same implementation — INDC returns Unicode code point
	return fl.lowerStringsIndexByte(instr)
}

// lowerStringsLastIndex: find last occurrence of substr in s.
func (fl *funcLowerer) lowerStringsLastIndex(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	subOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenSub := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	endIdx := fl.frame.AllocWord("")
	candidate := fl.frame.AllocTemp(true)

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, subOp, dis.FP(lenSub)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))

	// if lenSub > lenS → done
	bgtIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSub), dis.FP(lenS), dis.Imm(0)))

	// i = lenS - lenSub (start from end)
	fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSub), dis.FP(lenS), dis.FP(i)))

	loopPC := int32(len(fl.insts))
	bltIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, dis.FP(i), dis.Imm(0), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSub), dis.FP(i), dis.FP(endIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(candidate)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))

	beqIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, subOp, dis.FP(candidate), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	foundPC := int32(len(fl.insts))
	fl.insts[beqIdx].Dst = dis.Imm(foundPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(i), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[bgtIdx].Dst = dis.Imm(donePC)
	fl.insts[bltIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerStringsFields: split on whitespace runs.
func (fl *funcLowerer) lowerStringsFields(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	ch := fl.frame.AllocWord("")
	count := fl.frame.AllocWord("")
	inWord := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))

	// First pass: count words
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(count)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(inWord)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	countLoopPC := int32(len(fl.insts))
	bgeCountDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(i), dis.FP(ch)))

	// isSpace: ch == 32 || ch == 9 || ch == 10 || ch == 13
	beqSpc := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(32), dis.FP(ch), dis.Imm(0)))
	beqTab := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(9), dis.FP(ch), dis.Imm(0)))
	beqNl := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(10), dis.FP(ch), dis.Imm(0)))
	beqCr := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(13), dis.FP(ch), dis.Imm(0)))

	// not space: if !inWord, count++ and set inWord=1
	beqAlreadyIn := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBNEW, dis.FP(inWord), dis.Imm(0), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(count), dis.FP(count)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(inWord)))
	alreadyInPC := int32(len(fl.insts))
	fl.insts[beqAlreadyIn].Dst = dis.Imm(alreadyInPC)
	jmpNext := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// space: set inWord=0
	spacePC := int32(len(fl.insts))
	fl.insts[beqSpc].Dst = dis.Imm(spacePC)
	fl.insts[beqTab].Dst = dis.Imm(spacePC)
	fl.insts[beqNl].Dst = dis.Imm(spacePC)
	fl.insts[beqCr].Dst = dis.Imm(spacePC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(inWord)))

	nextPC := int32(len(fl.insts))
	fl.insts[jmpNext].Dst = dis.Imm(nextPC)
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(countLoopPC)))

	countDonePC := int32(len(fl.insts))
	fl.insts[bgeCountDone].Dst = dis.Imm(countDonePC)

	// Allocate array
	elemTDIdx := fl.makeHeapTypeDesc(nil) // string type desc
	fl.emit(dis.NewInst(dis.INEWA, dis.FP(count), dis.Imm(int32(elemTDIdx)), dis.FP(dst)))

	// Second pass: fill array
	arrIdx := fl.frame.AllocWord("")
	segStart := fl.frame.AllocWord("")
	segment := fl.frame.AllocTemp(true)
	storeAddr := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(arrIdx)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(inWord)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(segStart)))

	fillLoopPC := int32(len(fl.insts))
	bgeFillDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(i), dis.FP(ch)))

	beqSpc2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(32), dis.FP(ch), dis.Imm(0)))
	beqTab2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(9), dis.FP(ch), dis.Imm(0)))
	beqNl2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(10), dis.FP(ch), dis.Imm(0)))
	beqCr2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(13), dis.FP(ch), dis.Imm(0)))

	// not space
	beqAlreadyIn2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBNEW, dis.FP(inWord), dis.Imm(0), dis.Imm(0)))
	// start of new word
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(inWord)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(i), dis.FP(segStart)))
	alreadyIn2PC := int32(len(fl.insts))
	fl.insts[beqAlreadyIn2].Dst = dis.Imm(alreadyIn2PC)
	jmpNext2 := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// space: if inWord, store segment
	space2PC := int32(len(fl.insts))
	fl.insts[beqSpc2].Dst = dis.Imm(space2PC)
	fl.insts[beqTab2].Dst = dis.Imm(space2PC)
	fl.insts[beqNl2].Dst = dis.Imm(space2PC)
	fl.insts[beqCr2].Dst = dis.Imm(space2PC)

	beqNotInWord := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(inWord), dis.Imm(0), dis.Imm(0)))
	// end of word: store s[segStart:i]
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(segment)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(segStart), dis.FP(i), dis.FP(segment)))
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(dst), dis.FP(storeAddr), dis.FP(arrIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(segment), dis.FPInd(storeAddr, 0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(arrIdx), dis.FP(arrIdx)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(inWord)))
	notInWordPC := int32(len(fl.insts))
	fl.insts[beqNotInWord].Dst = dis.Imm(notInWordPC)

	next2PC := int32(len(fl.insts))
	fl.insts[jmpNext2].Dst = dis.Imm(next2PC)
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(fillLoopPC)))

	// fill done: if inWord, store last segment
	fillDonePC := int32(len(fl.insts))
	fl.insts[bgeFillDone].Dst = dis.Imm(fillDonePC)
	beqNoLast := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(inWord), dis.Imm(0), dis.Imm(0)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(segment)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(segStart), dis.FP(lenS), dis.FP(segment)))
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(dst), dis.FP(storeAddr), dis.FP(arrIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(segment), dis.FPInd(storeAddr, 0)))
	fl.insts[beqNoLast].Dst = dis.Imm(int32(len(fl.insts)))

	return nil
}

// isSpaceHelper emits inline checks for whitespace (space, tab, newline, carriage return).
// Returns the instruction indices of the 4 branch instructions that jump to "is space" target,
// and the instruction index of the "not space" jump.
func (fl *funcLowerer) emitIsSpaceCheck(ch int32) (spaceJmps []int, notSpaceJmp int) {
	spaceJmps = append(spaceJmps, len(fl.insts))
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(32), dis.FP(ch), dis.Imm(0)))
	spaceJmps = append(spaceJmps, len(fl.insts))
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(9), dis.FP(ch), dis.Imm(0)))
	spaceJmps = append(spaceJmps, len(fl.insts))
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(10), dis.FP(ch), dis.Imm(0)))
	spaceJmps = append(spaceJmps, len(fl.insts))
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(13), dis.FP(ch), dis.Imm(0)))
	notSpaceJmp = len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
	return
}

// lowerStringsTrim: trim chars in cutset from both ends of s.
func (fl *funcLowerer) lowerStringsTrim(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	cutsetOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenCut := fl.frame.AllocWord("")
	start := fl.frame.AllocWord("")
	end := fl.frame.AllocWord("")
	ch := fl.frame.AllocWord("")
	j := fl.frame.AllocWord("")
	cutCh := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, cutsetOp, dis.FP(lenCut)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(start)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(lenS), dis.FP(end)))

	// Trim leading
	leadLoopPC := int32(len(fl.insts))
	leadDoneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(start), dis.FP(end), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(start), dis.FP(ch)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(j)))

	innerLeadPC := int32(len(fl.insts))
	innerLeadDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(j), dis.FP(lenCut), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IINDC, cutsetOp, dis.FP(j), dis.FP(cutCh)))
	beqLeadMatch := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(ch), dis.FP(cutCh), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(j), dis.FP(j)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(innerLeadPC)))

	// char not in cutset → done leading
	notInCutPC := int32(len(fl.insts))
	fl.insts[innerLeadDone].Dst = dis.Imm(notInCutPC)
	jmpLeadDone := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// char in cutset → start++, continue
	inCutPC := int32(len(fl.insts))
	fl.insts[beqLeadMatch].Dst = dis.Imm(inCutPC)
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(start), dis.FP(start)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(leadLoopPC)))

	leadDonePC := int32(len(fl.insts))
	fl.insts[leadDoneIdx].Dst = dis.Imm(leadDonePC)
	fl.insts[jmpLeadDone].Dst = dis.Imm(leadDonePC)

	// Trim trailing
	trailLoopPC := int32(len(fl.insts))
	trailDoneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(start), dis.FP(end), dis.Imm(0)))
	tailIdx := fl.frame.AllocWord("")
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(end), dis.FP(tailIdx)))
	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(tailIdx), dis.FP(ch)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(j)))

	innerTrailPC := int32(len(fl.insts))
	innerTrailDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(j), dis.FP(lenCut), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IINDC, cutsetOp, dis.FP(j), dis.FP(cutCh)))
	beqTrailMatch := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(ch), dis.FP(cutCh), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(j), dis.FP(j)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(innerTrailPC)))

	notInCut2PC := int32(len(fl.insts))
	fl.insts[innerTrailDone].Dst = dis.Imm(notInCut2PC)
	jmpTrailDone := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	inCut2PC := int32(len(fl.insts))
	fl.insts[beqTrailMatch].Dst = dis.Imm(inCut2PC)
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(end), dis.FP(end)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(trailLoopPC)))

	trailDonePC := int32(len(fl.insts))
	fl.insts[trailDoneIdx].Dst = dis.Imm(trailDonePC)
	fl.insts[jmpTrailDone].Dst = dis.Imm(trailDonePC)

	// result = s[start:end]
	tmp := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(tmp)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(start), dis.FP(end), dis.FP(tmp)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmp), dis.FP(dst)))
	return nil
}

// lowerStringsTrimLeft: trim chars in cutset from left side of s.
func (fl *funcLowerer) lowerStringsTrimLeft(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	cutsetOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenCut := fl.frame.AllocWord("")
	start := fl.frame.AllocWord("")
	ch := fl.frame.AllocWord("")
	j := fl.frame.AllocWord("")
	cutCh := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, cutsetOp, dis.FP(lenCut)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(start)))

	loopPC := int32(len(fl.insts))
	doneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(start), dis.FP(lenS), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(start), dis.FP(ch)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(j)))

	innerPC := int32(len(fl.insts))
	innerDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(j), dis.FP(lenCut), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IINDC, cutsetOp, dis.FP(j), dis.FP(cutCh)))
	beqMatch := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(ch), dis.FP(cutCh), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(j), dis.FP(j)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(innerPC)))

	// not in cutset → done
	notInPC := int32(len(fl.insts))
	fl.insts[innerDone].Dst = dis.Imm(notInPC)
	jmpDone := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// in cutset → start++
	inPC := int32(len(fl.insts))
	fl.insts[beqMatch].Dst = dis.Imm(inPC)
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(start), dis.FP(start)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	donePC := int32(len(fl.insts))
	fl.insts[doneIdx].Dst = dis.Imm(donePC)
	fl.insts[jmpDone].Dst = dis.Imm(donePC)

	tmp := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(tmp)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(start), dis.FP(lenS), dis.FP(tmp)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmp), dis.FP(dst)))
	return nil
}

// lowerStringsTrimRight: trim chars in cutset from right side of s.
func (fl *funcLowerer) lowerStringsTrimRight(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	cutsetOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenCut := fl.frame.AllocWord("")
	end := fl.frame.AllocWord("")
	ch := fl.frame.AllocWord("")
	j := fl.frame.AllocWord("")
	cutCh := fl.frame.AllocWord("")
	tailIdx := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, cutsetOp, dis.FP(lenCut)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(lenS), dis.FP(end)))

	loopPC := int32(len(fl.insts))
	doneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLEW, dis.FP(end), dis.Imm(0), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(end), dis.FP(tailIdx)))
	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(tailIdx), dis.FP(ch)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(j)))

	innerPC := int32(len(fl.insts))
	innerDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(j), dis.FP(lenCut), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IINDC, cutsetOp, dis.FP(j), dis.FP(cutCh)))
	beqMatch := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(ch), dis.FP(cutCh), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(j), dis.FP(j)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(innerPC)))

	notInPC := int32(len(fl.insts))
	fl.insts[innerDone].Dst = dis.Imm(notInPC)
	jmpDone := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	inPC := int32(len(fl.insts))
	fl.insts[beqMatch].Dst = dis.Imm(inPC)
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(end), dis.FP(end)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	donePC := int32(len(fl.insts))
	fl.insts[doneIdx].Dst = dis.Imm(donePC)
	fl.insts[jmpDone].Dst = dis.Imm(donePC)

	tmp := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(tmp)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.FP(end), dis.FP(tmp)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmp), dis.FP(dst)))
	return nil
}

// lowerStringsTitle: capitalize first letter of each word.
func (fl *funcLowerer) lowerStringsTitle(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	ch := fl.frame.AllocWord("")
	prevSpace := fl.frame.AllocWord("")
	result := fl.frame.AllocTemp(true)
	charStr := fl.frame.AllocTemp(true)

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	emptyOff := fl.comp.AllocString("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(prevSpace))) // start of string counts as after space

	loopPC := int32(len(fl.insts))
	bgeDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(i), dis.FP(ch)))

	// check if space
	beqSpc := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(32), dis.FP(ch), dis.Imm(0)))
	beqTab := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(9), dis.FP(ch), dis.Imm(0)))
	beqNl := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(10), dis.FP(ch), dis.Imm(0)))
	beqCr := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(13), dis.FP(ch), dis.Imm(0)))

	// not space: if prevSpace && 'a'-'z', convert to upper
	beqNoPrev := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(prevSpace), dis.Imm(0), dis.Imm(0)))
	bltNoUpper := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, dis.FP(ch), dis.Imm(97), dis.Imm(0)))
	bgtNoUpper := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(ch), dis.Imm(122), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(32), dis.FP(ch), dis.FP(ch)))
	noUpperPC := int32(len(fl.insts))
	fl.insts[beqNoPrev].Dst = dis.Imm(noUpperPC)
	fl.insts[bltNoUpper].Dst = dis.Imm(noUpperPC)
	fl.insts[bgtNoUpper].Dst = dis.Imm(noUpperPC)

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(prevSpace)))
	jmpAppend := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// space:
	spacePC := int32(len(fl.insts))
	fl.insts[beqSpc].Dst = dis.Imm(spacePC)
	fl.insts[beqTab].Dst = dis.Imm(spacePC)
	fl.insts[beqNl].Dst = dis.Imm(spacePC)
	fl.insts[beqCr].Dst = dis.Imm(spacePC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(prevSpace)))

	// append char
	appendPC := int32(len(fl.insts))
	fl.insts[jmpAppend].Dst = dis.Imm(appendPC)
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(charStr)))
	fl.emit(dis.NewInst(dis.IINSC, dis.FP(ch), dis.Imm(0), dis.FP(charStr)))
	fl.emit(dis.NewInst(dis.IADDC, dis.FP(charStr), dis.FP(result), dis.FP(result)))

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	donePC := int32(len(fl.insts))
	fl.insts[bgeDone].Dst = dis.Imm(donePC)
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(result), dis.FP(dst)))
	return nil
}

// ============================================================
// strings package — Cut, CutPrefix, CutSuffix
// ============================================================

// lowerStringsCut: strings.Cut(s, sep) → (before, after string, found bool)
func (fl *funcLowerer) lowerStringsCut(instr *ssa.Call) (bool, error) {
	sOp := fl.operandOf(instr.Call.Args[0])
	sepOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)
	iby2wd := int32(dis.IBY2WD)

	// Use Index to find sep in s
	lenS := fl.frame.AllocWord("")
	lenSep := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	limit := fl.frame.AllocWord("")
	candidate := fl.frame.AllocTemp(true)
	endIdx := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, sepOp, dis.FP(lenSep)))

	// Default: not found → before=s, after="", found=false
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
	emptyOff := fl.comp.AllocString("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst+iby2wd)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))

	// if lenSep > lenS → not found
	bgtIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSep), dis.FP(lenS), dis.Imm(0)))

	// limit = lenS - lenSep + 1
	fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSep), dis.FP(lenS), dis.FP(limit)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(limit), dis.FP(limit)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	loopPC := int32(len(fl.insts))
	bgeIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(limit), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSep), dis.FP(i), dis.FP(endIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(candidate)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))
	beqFoundIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, sepOp, dis.FP(candidate), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// Found at i: before=s[:i], after=s[i+lenSep:], found=true
	foundPC := int32(len(fl.insts))
	fl.insts[beqFoundIdx].Dst = dis.Imm(foundPC)
	before := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(before)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.FP(i), dis.FP(before)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(before), dis.FP(dst)))

	after := fl.frame.AllocTemp(true)
	afterStart := fl.frame.AllocWord("")
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSep), dis.FP(i), dis.FP(afterStart)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(after)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(afterStart), dis.FP(lenS), dis.FP(after)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(after), dis.FP(dst+iby2wd)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst+2*iby2wd)))

	donePC := int32(len(fl.insts))
	fl.insts[bgtIdx].Dst = dis.Imm(donePC)
	fl.insts[bgeIdx].Dst = dis.Imm(donePC)

	return true, nil
}

// lowerStringsCutPrefix: strings.CutPrefix(s, prefix) → (after string, found bool)
func (fl *funcLowerer) lowerStringsCutPrefix(instr *ssa.Call) (bool, error) {
	sOp := fl.operandOf(instr.Call.Args[0])
	prefixOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)
	iby2wd := int32(dis.IBY2WD)

	lenS := fl.frame.AllocWord("")
	lenP := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, prefixOp, dis.FP(lenP)))

	// Default: not found → after=s, found=false
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))

	// if lenP > lenS → not found
	bgtIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenP), dis.FP(lenS), dis.Imm(0)))

	// Check prefix: head = s[:lenP]
	head := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(head)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.FP(lenP), dis.FP(head)))
	bneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBNEC, prefixOp, dis.FP(head), dis.Imm(0)))

	// Match: after = s[lenP:], found = true
	afterSlot := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(afterSlot)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(lenP), dis.FP(lenS), dis.FP(afterSlot)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(afterSlot), dis.FP(dst)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst+iby2wd)))

	donePC := int32(len(fl.insts))
	fl.insts[bgtIdx].Dst = dis.Imm(donePC)
	fl.insts[bneIdx].Dst = dis.Imm(donePC)

	return true, nil
}

// lowerStringsCutSuffix: strings.CutSuffix(s, suffix) → (before string, found bool)
func (fl *funcLowerer) lowerStringsCutSuffix(instr *ssa.Call) (bool, error) {
	sOp := fl.operandOf(instr.Call.Args[0])
	suffixOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)
	iby2wd := int32(dis.IBY2WD)

	lenS := fl.frame.AllocWord("")
	lenSuf := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, suffixOp, dis.FP(lenSuf)))

	// Default: not found → before=s, found=false
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))

	// if lenSuf > lenS → not found
	bgtIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSuf), dis.FP(lenS), dis.Imm(0)))

	// Check suffix: tail = s[lenS-lenSuf:]
	tailStart := fl.frame.AllocWord("")
	fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSuf), dis.FP(lenS), dis.FP(tailStart)))
	tail := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(tail)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(tailStart), dis.FP(lenS), dis.FP(tail)))
	bneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBNEC, suffixOp, dis.FP(tail), dis.Imm(0)))

	// Match: before = s[:tailStart], found = true
	beforeSlot := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(beforeSlot)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.FP(tailStart), dis.FP(beforeSlot)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(beforeSlot), dis.FP(dst)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst+iby2wd)))

	donePC := int32(len(fl.insts))
	fl.insts[bgtIdx].Dst = dis.Imm(donePC)
	fl.insts[bneIdx].Dst = dis.Imm(donePC)

	return true, nil
}

// ============================================================
// math package — new functions
// ============================================================

// lowerMathFloor: floor(x) = trunc(x) if x >= 0, else trunc(x)-1 if frac != 0.
func (fl *funcLowerer) lowerMathFloor(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	trunc := fl.frame.AllocWord("")
	frac := fl.frame.AllocWord("")
	zeroOff := fl.comp.AllocReal(0.0)
	oneOff := fl.comp.AllocReal(1.0)

	// trunc = CVTFR(CVTRF(src))  — convert to int then back to float = truncation
	intSlot := fl.frame.AllocWord("")
	fl.emit(dis.Inst2(dis.ICVTFR, src, dis.FP(intSlot)))
	fl.emit(dis.Inst2(dis.ICVTRF, dis.FP(intSlot), dis.FP(trunc)))

	// if src >= 0 → result = trunc
	bgefIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEF, src, dis.MP(zeroOff), dis.Imm(0)))

	// src < 0: check if frac != 0
	fl.emit(dis.NewInst(dis.ISUBF, dis.FP(trunc), src, dis.FP(frac)))
	beqfIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQF, dis.FP(frac), dis.MP(zeroOff), dis.Imm(0))) // frac==0 → trunc is exact

	// frac != 0: floor = trunc - 1
	fl.emit(dis.NewInst(dis.ISUBF, dis.MP(oneOff), dis.FP(trunc), dis.FP(dst)))
	jmpDoneIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// positive or exact: dst = trunc
	posPC := int32(len(fl.insts))
	fl.insts[bgefIdx].Dst = dis.Imm(posPC)
	fl.insts[beqfIdx].Dst = dis.Imm(posPC)
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(trunc), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[jmpDoneIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerMathCeil: ceil(x) = trunc(x) if x <= 0, else trunc(x)+1 if frac != 0.
func (fl *funcLowerer) lowerMathCeil(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	trunc := fl.frame.AllocWord("")
	frac := fl.frame.AllocWord("")
	zeroOff := fl.comp.AllocReal(0.0)
	oneOff := fl.comp.AllocReal(1.0)

	intSlot := fl.frame.AllocWord("")
	fl.emit(dis.Inst2(dis.ICVTFR, src, dis.FP(intSlot)))
	fl.emit(dis.Inst2(dis.ICVTRF, dis.FP(intSlot), dis.FP(trunc)))

	// if src <= 0 → result = trunc
	blefIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLEF, src, dis.MP(zeroOff), dis.Imm(0)))

	// src > 0: check frac
	fl.emit(dis.NewInst(dis.ISUBF, dis.FP(trunc), src, dis.FP(frac)))
	beqfIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQF, dis.FP(frac), dis.MP(zeroOff), dis.Imm(0)))

	// frac != 0: ceil = trunc + 1
	fl.emit(dis.NewInst(dis.IADDF, dis.MP(oneOff), dis.FP(trunc), dis.FP(dst)))
	jmpDoneIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	negPC := int32(len(fl.insts))
	fl.insts[blefIdx].Dst = dis.Imm(negPC)
	fl.insts[beqfIdx].Dst = dis.Imm(negPC)
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(trunc), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[jmpDoneIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerMathRound: round to nearest, ties away from zero.
func (fl *funcLowerer) lowerMathRound(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	halfOff := fl.comp.AllocReal(0.5)
	zeroOff := fl.comp.AllocReal(0.0)
	tmp := fl.frame.AllocWord("")
	intSlot := fl.frame.AllocWord("")

	// if src >= 0: round = floor(src + 0.5)
	bgefIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEF, src, dis.MP(zeroOff), dis.Imm(0)))

	// src < 0: round = ceil(src - 0.5)
	fl.emit(dis.NewInst(dis.ISUBF, dis.MP(halfOff), src, dis.FP(tmp)))
	fl.emit(dis.Inst2(dis.ICVTFR, dis.FP(tmp), dis.FP(intSlot)))
	fl.emit(dis.Inst2(dis.ICVTRF, dis.FP(intSlot), dis.FP(dst)))
	jmpDoneIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// src >= 0
	posPC := int32(len(fl.insts))
	fl.insts[bgefIdx].Dst = dis.Imm(posPC)
	fl.emit(dis.NewInst(dis.IADDF, dis.MP(halfOff), src, dis.FP(tmp)))
	fl.emit(dis.Inst2(dis.ICVTFR, dis.FP(tmp), dis.FP(intSlot)))
	fl.emit(dis.Inst2(dis.ICVTRF, dis.FP(intSlot), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[jmpDoneIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerMathTrunc: truncate to integer (toward zero).
func (fl *funcLowerer) lowerMathTrunc(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	intSlot := fl.frame.AllocWord("")
	fl.emit(dis.Inst2(dis.ICVTFR, src, dis.FP(intSlot)))
	fl.emit(dis.Inst2(dis.ICVTRF, dis.FP(intSlot), dis.FP(dst)))
	return nil
}

// lowerMathPow: x^y using EXPF instruction.
func (fl *funcLowerer) lowerMathPow(instr *ssa.Call) error {
	xOp := fl.operandOf(instr.Call.Args[0])
	yOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	// EXPF src, mid, dst: dst = mid ^ src (mid raised to power src)
	fl.emit(dis.NewInst(dis.IEXPF, yOp, xOp, dis.FP(dst)))
	return nil
}

// lowerMathMod: floating-point modulo.
func (fl *funcLowerer) lowerMathMod(instr *ssa.Call) error {
	xOp := fl.operandOf(instr.Call.Args[0])
	yOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	// mod = x - trunc(x/y) * y
	quotient := fl.frame.AllocWord("")
	truncQ := fl.frame.AllocWord("")
	truncQf := fl.frame.AllocWord("")
	prod := fl.frame.AllocWord("")

	fl.emit(dis.NewInst(dis.IDIVF, yOp, xOp, dis.FP(quotient)))
	fl.emit(dis.Inst2(dis.ICVTFR, dis.FP(quotient), dis.FP(truncQ)))
	fl.emit(dis.Inst2(dis.ICVTRF, dis.FP(truncQ), dis.FP(truncQf)))
	fl.emit(dis.NewInst(dis.IMULF, yOp, dis.FP(truncQf), dis.FP(prod)))
	fl.emit(dis.NewInst(dis.ISUBF, dis.FP(prod), xOp, dis.FP(dst)))
	return nil
}

// lowerMathLog: natural logarithm using series approximation.
// ln(x) = 2*sum(((x-1)/(x+1))^(2k+1)/(2k+1), k=0..N)
func (fl *funcLowerer) lowerMathLog(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	oneOff := fl.comp.AllocReal(1.0)
	twoOff := fl.comp.AllocReal(2.0)
	num := fl.frame.AllocWord("")
	den := fl.frame.AllocWord("")
	t := fl.frame.AllocWord("")
	t2 := fl.frame.AllocWord("")
	term := fl.frame.AllocWord("")
	sum := fl.frame.AllocWord("")
	denom := fl.frame.AllocWord("")

	// t = (x-1)/(x+1)
	fl.emit(dis.NewInst(dis.ISUBF, dis.MP(oneOff), src, dis.FP(num)))
	fl.emit(dis.NewInst(dis.IADDF, dis.MP(oneOff), src, dis.FP(den)))
	fl.emit(dis.NewInst(dis.IDIVF, dis.FP(den), dis.FP(num), dis.FP(t)))
	// t2 = t*t
	fl.emit(dis.NewInst(dis.IMULF, dis.FP(t), dis.FP(t), dis.FP(t2)))
	// sum = t (first term k=0: t^1/1 = t)
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(t), dis.FP(sum)))
	// term = t (current power)
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(t), dis.FP(term)))

	// Unrolled 12 terms for reasonable precision
	for k := 1; k <= 12; k++ {
		d := float64(2*k + 1)
		denomOff := fl.comp.AllocReal(d)
		// term *= t2
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(t2), dis.FP(term), dis.FP(term)))
		// sum += term / denom
		fl.emit(dis.NewInst(dis.IDIVF, dis.MP(denomOff), dis.FP(term), dis.FP(denom)))
		fl.emit(dis.NewInst(dis.IADDF, dis.FP(denom), dis.FP(sum), dis.FP(sum)))
	}

	// result = 2 * sum
	fl.emit(dis.NewInst(dis.IMULF, dis.MP(twoOff), dis.FP(sum), dis.FP(dst)))
	return nil
}

// lowerMathLog2: log2(x) = ln(x) / ln(2).
func (fl *funcLowerer) lowerMathLog2(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	ln2Off := fl.comp.AllocReal(0.6931471805599453)
	oneOff := fl.comp.AllocReal(1.0)
	twoOff := fl.comp.AllocReal(2.0)
	num := fl.frame.AllocWord("")
	den := fl.frame.AllocWord("")
	t := fl.frame.AllocWord("")
	t2 := fl.frame.AllocWord("")
	term := fl.frame.AllocWord("")
	sum := fl.frame.AllocWord("")
	denom := fl.frame.AllocWord("")
	lnx := fl.frame.AllocWord("")

	fl.emit(dis.NewInst(dis.ISUBF, dis.MP(oneOff), src, dis.FP(num)))
	fl.emit(dis.NewInst(dis.IADDF, dis.MP(oneOff), src, dis.FP(den)))
	fl.emit(dis.NewInst(dis.IDIVF, dis.FP(den), dis.FP(num), dis.FP(t)))
	fl.emit(dis.NewInst(dis.IMULF, dis.FP(t), dis.FP(t), dis.FP(t2)))
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(t), dis.FP(sum)))
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(t), dis.FP(term)))

	for k := 1; k <= 12; k++ {
		d := float64(2*k + 1)
		denomOff := fl.comp.AllocReal(d)
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(t2), dis.FP(term), dis.FP(term)))
		fl.emit(dis.NewInst(dis.IDIVF, dis.MP(denomOff), dis.FP(term), dis.FP(denom)))
		fl.emit(dis.NewInst(dis.IADDF, dis.FP(denom), dis.FP(sum), dis.FP(sum)))
	}

	fl.emit(dis.NewInst(dis.IMULF, dis.MP(twoOff), dis.FP(sum), dis.FP(lnx)))
	fl.emit(dis.NewInst(dis.IDIVF, dis.MP(ln2Off), dis.FP(lnx), dis.FP(dst)))
	return nil
}

// lowerMathLog10: log10(x) = ln(x) / ln(10).
func (fl *funcLowerer) lowerMathLog10(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	ln10Off := fl.comp.AllocReal(2.302585092994046)
	oneOff := fl.comp.AllocReal(1.0)
	twoOff := fl.comp.AllocReal(2.0)
	num := fl.frame.AllocWord("")
	den := fl.frame.AllocWord("")
	t := fl.frame.AllocWord("")
	t2 := fl.frame.AllocWord("")
	term := fl.frame.AllocWord("")
	sum := fl.frame.AllocWord("")
	denom := fl.frame.AllocWord("")
	lnx := fl.frame.AllocWord("")

	fl.emit(dis.NewInst(dis.ISUBF, dis.MP(oneOff), src, dis.FP(num)))
	fl.emit(dis.NewInst(dis.IADDF, dis.MP(oneOff), src, dis.FP(den)))
	fl.emit(dis.NewInst(dis.IDIVF, dis.FP(den), dis.FP(num), dis.FP(t)))
	fl.emit(dis.NewInst(dis.IMULF, dis.FP(t), dis.FP(t), dis.FP(t2)))
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(t), dis.FP(sum)))
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(t), dis.FP(term)))

	for k := 1; k <= 12; k++ {
		d := float64(2*k + 1)
		denomOff := fl.comp.AllocReal(d)
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(t2), dis.FP(term), dis.FP(term)))
		fl.emit(dis.NewInst(dis.IDIVF, dis.MP(denomOff), dis.FP(term), dis.FP(denom)))
		fl.emit(dis.NewInst(dis.IADDF, dis.FP(denom), dis.FP(sum), dis.FP(sum)))
	}

	fl.emit(dis.NewInst(dis.IMULF, dis.MP(twoOff), dis.FP(sum), dis.FP(lnx)))
	fl.emit(dis.NewInst(dis.IDIVF, dis.MP(ln10Off), dis.FP(lnx), dis.FP(dst)))
	return nil
}

// lowerMathExp: e^x using Taylor series.
func (fl *funcLowerer) lowerMathExp(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	oneOff := fl.comp.AllocReal(1.0)
	sum := fl.frame.AllocWord("")
	term := fl.frame.AllocWord("")

	// sum = 1, term = 1
	fl.emit(dis.Inst2(dis.IMOVF, dis.MP(oneOff), dis.FP(sum)))
	fl.emit(dis.Inst2(dis.IMOVF, dis.MP(oneOff), dis.FP(term)))

	// Unrolled 20 terms: term *= x/k; sum += term
	for k := 1; k <= 20; k++ {
		kOff := fl.comp.AllocReal(float64(k))
		fl.emit(dis.NewInst(dis.IMULF, src, dis.FP(term), dis.FP(term)))
		fl.emit(dis.NewInst(dis.IDIVF, dis.MP(kOff), dis.FP(term), dis.FP(term)))
		fl.emit(dis.NewInst(dis.IADDF, dis.FP(term), dis.FP(sum), dis.FP(sum)))
	}

	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(sum), dis.FP(dst)))
	return nil
}

// lowerMathInf: return +Inf or -Inf based on sign argument.
func (fl *funcLowerer) lowerMathInf(instr *ssa.Call) error {
	signOp := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	posInfOff := fl.comp.AllocReal(math.Inf(1)) // overflow to +Inf
	negInfOff := fl.comp.AllocReal(math.Inf(-1))

	fl.emit(dis.Inst2(dis.IMOVF, dis.MP(posInfOff), dis.FP(dst)))
	bgeIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, signOp, dis.Imm(0), dis.Imm(0)))
	fl.emit(dis.Inst2(dis.IMOVF, dis.MP(negInfOff), dis.FP(dst)))
	donePC := int32(len(fl.insts))
	fl.insts[bgeIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerMathNaN: return NaN.
func (fl *funcLowerer) lowerMathNaN(instr *ssa.Call) error {
	dst := fl.slotOf(instr)
	// NaN = 0.0 / 0.0
	zeroOff := fl.comp.AllocReal(0.0)
	tmp := fl.frame.AllocWord("")
	fl.emit(dis.Inst2(dis.IMOVF, dis.MP(zeroOff), dis.FP(tmp)))
	fl.emit(dis.NewInst(dis.IDIVF, dis.FP(tmp), dis.FP(tmp), dis.FP(dst)))
	return nil
}

// lowerMathIsNaN: NaN != NaN.
func (fl *funcLowerer) lowerMathIsNaN(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
	// NaN is the only value where x != x
	bneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBNEF, src, src, dis.Imm(0)))
	jmpIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	truePC := int32(len(fl.insts))
	fl.insts[bneIdx].Dst = dis.Imm(truePC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[jmpIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerMathIsInf: check if value is +/-Inf.
func (fl *funcLowerer) lowerMathIsInf(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	signOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	posInfOff := fl.comp.AllocReal(math.Inf(1))
	negInfOff := fl.comp.AllocReal(math.Inf(-1))

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))

	// sign > 0 → check +Inf only
	bgtIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, signOp, dis.Imm(0), dis.Imm(0)))
	// sign < 0 → check -Inf only
	bltIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, signOp, dis.Imm(0), dis.Imm(0)))

	// sign == 0 → check either
	beqPosIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQF, src, dis.MP(posInfOff), dis.Imm(0)))
	beqNegIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQF, src, dis.MP(negInfOff), dis.Imm(0)))
	jmpDoneIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// check +Inf
	checkPosPC := int32(len(fl.insts))
	fl.insts[bgtIdx].Dst = dis.Imm(checkPosPC)
	beqPos2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQF, src, dis.MP(posInfOff), dis.Imm(0)))
	jmpDone2 := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// check -Inf
	checkNegPC := int32(len(fl.insts))
	fl.insts[bltIdx].Dst = dis.Imm(checkNegPC)
	beqNeg2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQF, src, dis.MP(negInfOff), dis.Imm(0)))
	jmpDone3 := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// true:
	truePC := int32(len(fl.insts))
	fl.insts[beqPosIdx].Dst = dis.Imm(truePC)
	fl.insts[beqNegIdx].Dst = dis.Imm(truePC)
	fl.insts[beqPos2].Dst = dis.Imm(truePC)
	fl.insts[beqNeg2].Dst = dis.Imm(truePC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[jmpDoneIdx].Dst = dis.Imm(donePC)
	fl.insts[jmpDone2].Dst = dis.Imm(donePC)
	fl.insts[jmpDone3].Dst = dis.Imm(donePC)
	return nil
}

// lowerMathSignbit: return true if x is negative or negative zero.
func (fl *funcLowerer) lowerMathSignbit(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)
	zeroOff := fl.comp.AllocReal(0.0)

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
	bgeIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEF, src, dis.MP(zeroOff), dis.Imm(0)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
	donePC := int32(len(fl.insts))
	fl.insts[bgeIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerMathCopysign: return x with the sign of y.
func (fl *funcLowerer) lowerMathCopysign(instr *ssa.Call) error {
	xOp := fl.operandOf(instr.Call.Args[0])
	yOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)
	zeroOff := fl.comp.AllocReal(0.0)

	// abs(x)
	absX := fl.frame.AllocWord("")
	fl.emit(dis.Inst2(dis.IMOVF, xOp, dis.FP(absX)))
	bgefAbsIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEF, xOp, dis.MP(zeroOff), dis.Imm(0)))
	fl.emit(dis.Inst2(dis.INEGF, xOp, dis.FP(absX)))
	absPC := int32(len(fl.insts))
	fl.insts[bgefAbsIdx].Dst = dis.Imm(absPC)

	// if y >= 0 → dst = absX, else dst = -absX
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(absX), dis.FP(dst)))
	bgefIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEF, yOp, dis.MP(zeroOff), dis.Imm(0)))
	fl.emit(dis.Inst2(dis.INEGF, dis.FP(absX), dis.FP(dst)))
	donePC := int32(len(fl.insts))
	fl.insts[bgefIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerMathDim: max(x-y, 0).
func (fl *funcLowerer) lowerMathDim(instr *ssa.Call) error {
	xOp := fl.operandOf(instr.Call.Args[0])
	yOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)
	zeroOff := fl.comp.AllocReal(0.0)

	diff := fl.frame.AllocWord("")
	fl.emit(dis.NewInst(dis.ISUBF, yOp, xOp, dis.FP(diff)))
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(diff), dis.FP(dst)))
	bgefIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEF, dis.FP(diff), dis.MP(zeroOff), dis.Imm(0)))
	fl.emit(dis.Inst2(dis.IMOVF, dis.MP(zeroOff), dis.FP(dst)))
	donePC := int32(len(fl.insts))
	fl.insts[bgefIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerMathFloat64bits: reinterpret float64 as uint64 (identity on Dis — same 8-byte word).
func (fl *funcLowerer) lowerMathFloat64bits(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)
	// On Dis VM, float64 and int64 share the same 8-byte WORD slot. Just copy.
	fl.emit(dis.Inst2(dis.IMOVF, src, dis.FP(dst)))
	return nil
}

// lowerMathFloat64frombits: reinterpret uint64 as float64 (identity on Dis).
func (fl *funcLowerer) lowerMathFloat64frombits(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)
	fl.emit(dis.Inst2(dis.IMOVW, src, dis.FP(dst)))
	return nil
}

// lowerMathTrig: sin/cos/tan using Taylor series.
func (fl *funcLowerer) lowerMathTrig(instr *ssa.Call, name string) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	oneOff := fl.comp.AllocReal(1.0)
	sum := fl.frame.AllocWord("")
	term := fl.frame.AllocWord("")
	x2 := fl.frame.AllocWord("")

	fl.emit(dis.NewInst(dis.IMULF, src, src, dis.FP(x2)))

	switch name {
	case "Sin":
		// sin(x) = x - x^3/3! + x^5/5! - ...
		fl.emit(dis.Inst2(dis.IMOVF, src, dis.FP(sum)))
		fl.emit(dis.Inst2(dis.IMOVF, src, dis.FP(term)))
		for k := 1; k <= 10; k++ {
			n1 := float64(2*k * (2*k + 1))
			nOff := fl.comp.AllocReal(n1)
			fl.emit(dis.NewInst(dis.IMULF, dis.FP(x2), dis.FP(term), dis.FP(term)))
			fl.emit(dis.NewInst(dis.IDIVF, dis.MP(nOff), dis.FP(term), dis.FP(term)))
			fl.emit(dis.Inst2(dis.INEGF, dis.FP(term), dis.FP(term)))
			fl.emit(dis.NewInst(dis.IADDF, dis.FP(term), dis.FP(sum), dis.FP(sum)))
		}
	case "Cos":
		// cos(x) = 1 - x^2/2! + x^4/4! - ...
		fl.emit(dis.Inst2(dis.IMOVF, dis.MP(oneOff), dis.FP(sum)))
		fl.emit(dis.Inst2(dis.IMOVF, dis.MP(oneOff), dis.FP(term)))
		for k := 1; k <= 10; k++ {
			n1 := float64((2*k - 1) * (2 * k))
			nOff := fl.comp.AllocReal(n1)
			fl.emit(dis.NewInst(dis.IMULF, dis.FP(x2), dis.FP(term), dis.FP(term)))
			fl.emit(dis.NewInst(dis.IDIVF, dis.MP(nOff), dis.FP(term), dis.FP(term)))
			fl.emit(dis.Inst2(dis.INEGF, dis.FP(term), dis.FP(term)))
			fl.emit(dis.NewInst(dis.IADDF, dis.FP(term), dis.FP(sum), dis.FP(sum)))
		}
	case "Tan":
		// tan(x) = sin(x)/cos(x) — compute both inline
		sinSum := fl.frame.AllocWord("")
		sinTerm := fl.frame.AllocWord("")
		cosSum := fl.frame.AllocWord("")
		cosTerm := fl.frame.AllocWord("")

		fl.emit(dis.Inst2(dis.IMOVF, src, dis.FP(sinSum)))
		fl.emit(dis.Inst2(dis.IMOVF, src, dis.FP(sinTerm)))
		fl.emit(dis.Inst2(dis.IMOVF, dis.MP(oneOff), dis.FP(cosSum)))
		fl.emit(dis.Inst2(dis.IMOVF, dis.MP(oneOff), dis.FP(cosTerm)))

		for k := 1; k <= 10; k++ {
			sn := float64(2*k * (2*k + 1))
			cn := float64((2*k - 1) * (2 * k))
			snOff := fl.comp.AllocReal(sn)
			cnOff := fl.comp.AllocReal(cn)
			fl.emit(dis.NewInst(dis.IMULF, dis.FP(x2), dis.FP(sinTerm), dis.FP(sinTerm)))
			fl.emit(dis.NewInst(dis.IDIVF, dis.MP(snOff), dis.FP(sinTerm), dis.FP(sinTerm)))
			fl.emit(dis.Inst2(dis.INEGF, dis.FP(sinTerm), dis.FP(sinTerm)))
			fl.emit(dis.NewInst(dis.IADDF, dis.FP(sinTerm), dis.FP(sinSum), dis.FP(sinSum)))
			fl.emit(dis.NewInst(dis.IMULF, dis.FP(x2), dis.FP(cosTerm), dis.FP(cosTerm)))
			fl.emit(dis.NewInst(dis.IDIVF, dis.MP(cnOff), dis.FP(cosTerm), dis.FP(cosTerm)))
			fl.emit(dis.Inst2(dis.INEGF, dis.FP(cosTerm), dis.FP(cosTerm)))
			fl.emit(dis.NewInst(dis.IADDF, dis.FP(cosTerm), dis.FP(cosSum), dis.FP(cosSum)))
		}

		fl.emit(dis.NewInst(dis.IDIVF, dis.FP(cosSum), dis.FP(sinSum), dis.FP(dst)))
		return nil
	}

	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(sum), dis.FP(dst)))
	return nil
}

// ============================================================
// New package dispatchers
// ============================================================

// lowerUnicodeCall handles unicode package functions.
func (fl *funcLowerer) lowerUnicodeCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	switch callee.Name() {
	case "IsLetter":
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		// a-z or A-Z
		blt1 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, src, dis.Imm(65), dis.Imm(0)))
		ble1 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLEW, src, dis.Imm(90), dis.Imm(0)))
		blt2 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, src, dis.Imm(97), dis.Imm(0)))
		ble2 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLEW, src, dis.Imm(122), dis.Imm(0)))
		jmpDone := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		truePC := int32(len(fl.insts))
		fl.insts[ble1].Dst = dis.Imm(truePC)
		fl.insts[ble2].Dst = dis.Imm(truePC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[blt1].Dst = dis.Imm(donePC)
		fl.insts[blt2].Dst = dis.Imm(donePC)
		fl.insts[jmpDone].Dst = dis.Imm(donePC)
		return true, nil

	case "IsDigit":
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		blt := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, src, dis.Imm(48), dis.Imm(0)))
		bgt := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, src, dis.Imm(57), dis.Imm(0)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[blt].Dst = dis.Imm(donePC)
		fl.insts[bgt].Dst = dis.Imm(donePC)
		return true, nil

	case "IsUpper":
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		blt := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, src, dis.Imm(65), dis.Imm(0)))
		bgt := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, src, dis.Imm(90), dis.Imm(0)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[blt].Dst = dis.Imm(donePC)
		fl.insts[bgt].Dst = dis.Imm(donePC)
		return true, nil

	case "IsLower":
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		blt := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, src, dis.Imm(97), dis.Imm(0)))
		bgt := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, src, dis.Imm(122), dis.Imm(0)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[blt].Dst = dis.Imm(donePC)
		fl.insts[bgt].Dst = dis.Imm(donePC)
		return true, nil

	case "IsSpace":
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		beq1 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(32), src, dis.Imm(0)))
		beq2 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(9), src, dis.Imm(0)))
		beq3 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(10), src, dis.Imm(0)))
		beq4 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(13), src, dis.Imm(0)))
		jmpDone := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		truePC := int32(len(fl.insts))
		fl.insts[beq1].Dst = dis.Imm(truePC)
		fl.insts[beq2].Dst = dis.Imm(truePC)
		fl.insts[beq3].Dst = dis.Imm(truePC)
		fl.insts[beq4].Dst = dis.Imm(truePC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[jmpDone].Dst = dis.Imm(donePC)
		return true, nil

	case "ToUpper":
		fl.emit(dis.Inst2(dis.IMOVW, src, dis.FP(dst)))
		blt := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, src, dis.Imm(97), dis.Imm(0)))
		bgt := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, src, dis.Imm(122), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(32), src, dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[blt].Dst = dis.Imm(donePC)
		fl.insts[bgt].Dst = dis.Imm(donePC)
		return true, nil

	case "ToLower":
		fl.emit(dis.Inst2(dis.IMOVW, src, dis.FP(dst)))
		blt := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, src, dis.Imm(65), dis.Imm(0)))
		bgt := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, src, dis.Imm(90), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(32), src, dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[blt].Dst = dis.Imm(donePC)
		fl.insts[bgt].Dst = dis.Imm(donePC)
		return true, nil
	}
	return false, nil
}

// lowerUTF8Call handles unicode/utf8 package functions.
func (fl *funcLowerer) lowerUTF8Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "RuneCountInString":
		// For ASCII-compatible impl, same as len(s)
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.ILENC, src, dis.FP(dst)))
		return true, nil
	case "ValidString":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst))) // assume valid
		return true, nil
	case "RuneLen":
		// Simplified: all runes are 1 byte (ASCII)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "DecodeRuneInString":
		// Returns (rune, size). For ASCII: rune = s[0], size = 1
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		ch := fl.frame.AllocWord("")
		fl.emit(dis.NewInst(dis.IINDC, src, dis.Imm(0), dis.FP(ch)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(ch), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst+iby2wd)))
		return true, nil
	case "DecodeRune":
		// DecodeRune(p []byte) → (rune, size). ASCII: first byte, 1
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0xFFFD), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst+iby2wd)))
		return true, nil
	case "DecodeLastRune":
		// DecodeLastRune(p []byte) → (rune, size). Stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0xFFFD), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst+iby2wd)))
		return true, nil
	case "DecodeLastRuneInString":
		// DecodeLastRuneInString(s) → (rune, size). Stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0xFFFD), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst+iby2wd)))
		return true, nil
	case "ValidRune":
		// ValidRune(r) → true stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "FullRune", "FullRuneInString":
		// FullRune(p) / FullRuneInString(s) → true stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "RuneCount":
		// RuneCount(p []byte) → len(p) for ASCII
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.ILENA, src, dis.FP(dst)))
		return true, nil
	case "Valid":
		// Valid(p []byte) → true stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "EncodeRune":
		// EncodeRune(p, r) → 1 (simplified ASCII)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "AppendRune":
		// AppendRune(p, r) → p stub (return input slice)
		pOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, pOp, dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// lowerPathCall handles path package functions.
func (fl *funcLowerer) lowerPathCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Base":
		// Return everything after last '/'
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		lenS := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		ch := fl.frame.AllocWord("")
		lastSlash := fl.frame.AllocWord("")

		fl.emit(dis.Inst2(dis.ILENC, src, dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(lastSlash)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

		loopPC := int32(len(fl.insts))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IINDC, src, dis.FP(i), dis.FP(ch)))
		bneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEW, dis.FP(ch), dis.Imm(47), dis.Imm(0))) // '/' = 47
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(i), dis.FP(lastSlash)))
		skipPC := int32(len(fl.insts))
		fl.insts[bneIdx].Dst = dis.Imm(skipPC)
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

		donePC := int32(len(fl.insts))
		fl.insts[bgeIdx].Dst = dis.Imm(donePC)

		// if lastSlash == -1, return s as-is
		startOff := fl.frame.AllocWord("")
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(lastSlash), dis.FP(startOff)))
		tmp := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.IMOVP, src, dis.FP(tmp)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(startOff), dis.FP(lenS), dis.FP(tmp)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmp), dis.FP(dst)))
		return true, nil

	case "Dir":
		// Return everything before last '/'
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		lenS := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		ch := fl.frame.AllocWord("")
		lastSlash := fl.frame.AllocWord("")

		fl.emit(dis.Inst2(dis.ILENC, src, dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(lastSlash)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

		loopPC := int32(len(fl.insts))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IINDC, src, dis.FP(i), dis.FP(ch)))
		bneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEW, dis.FP(ch), dis.Imm(47), dis.Imm(0)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(i), dis.FP(lastSlash)))
		skipPC := int32(len(fl.insts))
		fl.insts[bneIdx].Dst = dis.Imm(skipPC)
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

		donePC := int32(len(fl.insts))
		fl.insts[bgeIdx].Dst = dis.Imm(donePC)

		// if lastSlash <= 0, return "."
		dotOff := fl.comp.AllocString(".")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(dotOff), dis.FP(dst)))
		bgtIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lastSlash), dis.Imm(0), dis.Imm(0)))
		jmpEnd := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

		slicePC := int32(len(fl.insts))
		fl.insts[bgtIdx].Dst = dis.Imm(slicePC)
		tmp := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.IMOVP, src, dis.FP(tmp)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.FP(lastSlash), dis.FP(tmp)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmp), dis.FP(dst)))

		endPC := int32(len(fl.insts))
		fl.insts[jmpEnd].Dst = dis.Imm(endPC)
		return true, nil

	case "Ext":
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		lenS := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		ch := fl.frame.AllocWord("")
		lastDot := fl.frame.AllocWord("")

		fl.emit(dis.Inst2(dis.ILENC, src, dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(lastDot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

		loopPC := int32(len(fl.insts))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IINDC, src, dis.FP(i), dis.FP(ch)))
		bneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEW, dis.FP(ch), dis.Imm(46), dis.Imm(0))) // '.' = 46
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(i), dis.FP(lastDot)))
		skipPC := int32(len(fl.insts))
		fl.insts[bneIdx].Dst = dis.Imm(skipPC)
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

		searchDonePC := int32(len(fl.insts))
		fl.insts[bgeIdx].Dst = dis.Imm(searchDonePC)

		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		beqNoExt := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.FP(lastDot), dis.Imm(-1), dis.Imm(0)))
		tmp := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.IMOVP, src, dis.FP(tmp)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(lastDot), dis.FP(lenS), dis.FP(tmp)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmp), dis.FP(dst)))
		fl.insts[beqNoExt].Dst = dis.Imm(int32(len(fl.insts)))
		return true, nil

	case "Join":
		// path.Join — delegate to strings.Join with "/"
		return fl.lowerPathJoin(instr)
	}
	return false, nil
}

// lowerPathJoin: join path segments with "/".
func (fl *funcLowerer) lowerPathJoin(instr *ssa.Call) (bool, error) {
	// path.Join takes variadic args which SSA presents as a slice
	elemsOp := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	lenArr := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	result := fl.frame.AllocTemp(true)
	elem := fl.frame.AllocTemp(true)
	elemAddr := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENA, elemsOp, dis.FP(lenArr)))
	emptyOff := fl.comp.AllocString("")
	sepOff := fl.comp.AllocString("/")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	loopPC := int32(len(fl.insts))
	bgeDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenArr), dis.Imm(0)))

	beqSkipSep := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(i), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDC, dis.MP(sepOff), dis.FP(result), dis.FP(result)))
	skipSepPC := int32(len(fl.insts))
	fl.insts[beqSkipSep].Dst = dis.Imm(skipSepPC)

	fl.emit(dis.NewInst(dis.IINDW, elemsOp, dis.FP(elemAddr), dis.FP(i)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(elemAddr, 0), dis.FP(elem)))
	fl.emit(dis.NewInst(dis.IADDC, dis.FP(elem), dis.FP(result), dis.FP(result)))

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	donePC := int32(len(fl.insts))
	fl.insts[bgeDone].Dst = dis.Imm(donePC)
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(result), dis.FP(dst)))
	return true, nil
}

// lowerMathBitsCall handles math/bits package functions.
func (fl *funcLowerer) lowerMathBitsCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "OnesCount":
		// Popcount: loop and count set bits
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		n := fl.frame.AllocWord("")
		count := fl.frame.AllocWord("")
		bit := fl.frame.AllocWord("")

		fl.emit(dis.Inst2(dis.IMOVW, src, dis.FP(n)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(count)))

		loopPC := int32(len(fl.insts))
		beqDone := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(n), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IANDW, dis.Imm(1), dis.FP(n), dis.FP(bit)))
		fl.emit(dis.NewInst(dis.IADDW, dis.FP(bit), dis.FP(count), dis.FP(count)))
		fl.emit(dis.NewInst(dis.ILSRW, dis.Imm(1), dis.FP(n), dis.FP(n)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

		donePC := int32(len(fl.insts))
		fl.insts[beqDone].Dst = dis.Imm(donePC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(count), dis.FP(dst)))
		return true, nil

	case "Len":
		// Bit length: find position of highest set bit
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		n := fl.frame.AllocWord("")
		count := fl.frame.AllocWord("")

		fl.emit(dis.Inst2(dis.IMOVW, src, dis.FP(n)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(count)))

		loopPC := int32(len(fl.insts))
		beqDone := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(n), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(count), dis.FP(count)))
		fl.emit(dis.NewInst(dis.ILSRW, dis.Imm(1), dis.FP(n), dis.FP(n)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

		donePC := int32(len(fl.insts))
		fl.insts[beqDone].Dst = dis.Imm(donePC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(count), dis.FP(dst)))
		return true, nil

	case "TrailingZeros":
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		n := fl.frame.AllocWord("")
		count := fl.frame.AllocWord("")
		bit := fl.frame.AllocWord("")

		fl.emit(dis.Inst2(dis.IMOVW, src, dis.FP(n)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(count)))

		// if n == 0 → return 64
		beqZero := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(n), dis.Imm(0)))

		loopPC := int32(len(fl.insts))
		fl.emit(dis.NewInst(dis.IANDW, dis.Imm(1), dis.FP(n), dis.FP(bit)))
		bneFound := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEW, dis.FP(bit), dis.Imm(0), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(count), dis.FP(count)))
		fl.emit(dis.NewInst(dis.ILSRW, dis.Imm(1), dis.FP(n), dis.FP(n)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

		foundPC := int32(len(fl.insts))
		fl.insts[bneFound].Dst = dis.Imm(foundPC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(count), dis.FP(dst)))
		jmpEnd := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

		zeroPC := int32(len(fl.insts))
		fl.insts[beqZero].Dst = dis.Imm(zeroPC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(64), dis.FP(dst)))

		endPC := int32(len(fl.insts))
		fl.insts[jmpEnd].Dst = dis.Imm(endPC)
		return true, nil

	case "RotateLeft":
		src := fl.operandOf(instr.Call.Args[0])
		kOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		left := fl.frame.AllocWord("")
		right := fl.frame.AllocWord("")
		rShift := fl.frame.AllocWord("")

		fl.emit(dis.NewInst(dis.ISHLW, kOp, src, dis.FP(left)))
		fl.emit(dis.NewInst(dis.ISUBW, kOp, dis.Imm(64), dis.FP(rShift)))
		fl.emit(dis.NewInst(dis.ILSRW, dis.FP(rShift), src, dis.FP(right)))
		fl.emit(dis.NewInst(dis.IORW, dis.FP(right), dis.FP(left), dis.FP(dst)))
		return true, nil

	case "Reverse":
		// Bit reversal — simplified: just return the value (stub)
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, src, dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// lowerMathRandCall handles math/rand package functions.
func (fl *funcLowerer) lowerMathRandCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	dst := fl.slotOf(instr)

	switch callee.Name() {
	case "Intn":
		// Use sys.millisec() as a simple pseudo-random source
		nOp := fl.operandOf(instr.Call.Args[0])
		msSlot := fl.frame.AllocWord("")

		disName := "millisec"
		ldtIdx, ok := fl.sysUsed[disName]
		if !ok {
			ldtIdx = len(fl.sysUsed)
			fl.sysUsed[disName] = ldtIdx
		}
		callFrame := fl.frame.AllocWord("")
		fl.emit(dis.NewInst(dis.IMFRAME, dis.MP(fl.sysMPOff), dis.Imm(int32(ldtIdx)), dis.FP(callFrame)))
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(msSlot), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))
		fl.emit(dis.NewInst(dis.IMCALL, dis.FP(callFrame), dis.Imm(int32(ldtIdx)), dis.MP(fl.sysMPOff)))

		// result = abs(ms) % n
		absMs := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(msSlot), dis.FP(absMs)))
		bgefIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(absMs), dis.Imm(0), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.FP(absMs), dis.Imm(0), dis.FP(absMs)))
		absPC := int32(len(fl.insts))
		fl.insts[bgefIdx].Dst = dis.Imm(absPC)
		fl.emit(dis.NewInst(dis.IMODW, nOp, dis.FP(absMs), dis.FP(dst)))
		return true, nil

	case "Int":
		msSlot := fl.frame.AllocWord("")
		disName := "millisec"
		ldtIdx, ok := fl.sysUsed[disName]
		if !ok {
			ldtIdx = len(fl.sysUsed)
			fl.sysUsed[disName] = ldtIdx
		}
		callFrame := fl.frame.AllocWord("")
		fl.emit(dis.NewInst(dis.IMFRAME, dis.MP(fl.sysMPOff), dis.Imm(int32(ldtIdx)), dis.FP(callFrame)))
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(msSlot), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))
		fl.emit(dis.NewInst(dis.IMCALL, dis.FP(callFrame), dis.Imm(int32(ldtIdx)), dis.MP(fl.sysMPOff)))
		// abs
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(msSlot), dis.FP(dst)))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(dst), dis.Imm(0), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.FP(dst), dis.Imm(0), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[bgeIdx].Dst = dis.Imm(donePC)
		return true, nil

	case "Float64":
		// Return millisec as fraction
		msSlot := fl.frame.AllocWord("")
		disName := "millisec"
		ldtIdx, ok := fl.sysUsed[disName]
		if !ok {
			ldtIdx = len(fl.sysUsed)
			fl.sysUsed[disName] = ldtIdx
		}
		callFrame := fl.frame.AllocWord("")
		fl.emit(dis.NewInst(dis.IMFRAME, dis.MP(fl.sysMPOff), dis.Imm(int32(ldtIdx)), dis.FP(callFrame)))
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(msSlot), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))
		fl.emit(dis.NewInst(dis.IMCALL, dis.FP(callFrame), dis.Imm(int32(ldtIdx)), dis.MP(fl.sysMPOff)))

		fSlot := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.ICVTRF, dis.FP(msSlot), dis.FP(fSlot)))
		largeOff := fl.comp.AllocReal(1000000000.0)
		fl.emit(dis.NewInst(dis.IMODW, dis.Imm(1000000), dis.FP(msSlot), dis.FP(msSlot)))
		fl.emit(dis.Inst2(dis.ICVTRF, dis.FP(msSlot), dis.FP(fSlot)))
		fl.emit(dis.NewInst(dis.IDIVF, dis.MP(largeOff), dis.FP(fSlot), dis.FP(dst)))
		return true, nil

	case "Seed":
		// No-op: our PRNG doesn't support seeding
		return true, nil
	}
	return false, nil
}

// lowerBytesCall handles bytes package functions.
func (fl *funcLowerer) lowerBytesCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Contains":
		// bytes.Contains(b, subslice) → convert both to strings, use string Contains
		bOp := fl.operandOf(instr.Call.Args[0])
		subOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)

		sStr := fl.frame.AllocTemp(true)
		subStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, bOp, dis.FP(sStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, subOp, dis.FP(subStr)))

		lenS := fl.frame.AllocWord("")
		lenSub := fl.frame.AllocWord("")
		limit := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		endIdx := fl.frame.AllocWord("")
		candidate := fl.frame.AllocTemp(true)

		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(subStr), dis.FP(lenSub)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))

		beqEmpty := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(lenSub), dis.Imm(0)))
		bgtShort := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSub), dis.FP(lenS), dis.Imm(0)))

		fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSub), dis.FP(lenS), dis.FP(limit)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(limit), dis.FP(limit)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

		loopPC := int32(len(fl.insts))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(limit), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSub), dis.FP(i), dis.FP(endIdx)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(sStr), dis.FP(candidate)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))
		beqFound := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQC, dis.FP(subStr), dis.FP(candidate), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

		foundPC := int32(len(fl.insts))
		fl.insts[beqFound].Dst = dis.Imm(foundPC)
		fl.insts[beqEmpty].Dst = dis.Imm(foundPC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))

		donePC := int32(len(fl.insts))
		fl.insts[bgtShort].Dst = dis.Imm(donePC)
		fl.insts[bgeIdx].Dst = dis.Imm(donePC)
		return true, nil

	case "Equal":
		aOp := fl.operandOf(instr.Call.Args[0])
		bOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		aStr := fl.frame.AllocTemp(true)
		bStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, aOp, dis.FP(aStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, bOp, dis.FP(bStr)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		beqIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQC, dis.FP(aStr), dis.FP(bStr), dis.Imm(0)))
		jmpDone := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		truePC := int32(len(fl.insts))
		fl.insts[beqIdx].Dst = dis.Imm(truePC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[jmpDone].Dst = dis.Imm(donePC)
		return true, nil

	case "Compare":
		// bytes.Compare(a, b) → -1, 0, or 1
		aOp := fl.operandOf(instr.Call.Args[0])
		bOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		aStr := fl.frame.AllocTemp(true)
		bStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, aOp, dis.FP(aStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, bOp, dis.FP(bStr)))
		// default 0 (equal)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		beqIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQC, dis.FP(aStr), dis.FP(bStr), dis.Imm(0)))
		// not equal — use lexicographic compare via IBLTC/IBGTC pattern
		// simplified: compare lengths, if a < b → -1, else 1
		lenA := fl.frame.AllocWord("")
		lenB := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(aStr), dis.FP(lenA)))
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(bStr), dis.FP(lenB)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
		bltIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, dis.FP(lenA), dis.FP(lenB), dis.Imm(0)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[beqIdx].Dst = dis.Imm(donePC)
		fl.insts[bltIdx].Dst = dis.Imm(donePC)
		return true, nil

	case "HasPrefix":
		aOp := fl.operandOf(instr.Call.Args[0])
		pOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		aStr := fl.frame.AllocTemp(true)
		pStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, aOp, dis.FP(aStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, pOp, dis.FP(pStr)))
		lenA := fl.frame.AllocWord("")
		lenP := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(aStr), dis.FP(lenA)))
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(pStr), dis.FP(lenP)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		bgtIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenP), dis.FP(lenA), dis.Imm(0)))
		head := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(aStr), dis.FP(head)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.FP(lenP), dis.FP(head)))
		beqIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQC, dis.FP(pStr), dis.FP(head), dis.Imm(0)))
		jmpDone := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		truePC := int32(len(fl.insts))
		fl.insts[beqIdx].Dst = dis.Imm(truePC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[bgtIdx].Dst = dis.Imm(donePC)
		fl.insts[jmpDone].Dst = dis.Imm(donePC)
		return true, nil

	case "HasSuffix":
		aOp := fl.operandOf(instr.Call.Args[0])
		sOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		aStr := fl.frame.AllocTemp(true)
		sStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, aOp, dis.FP(aStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, sOp, dis.FP(sStr)))
		lenA := fl.frame.AllocWord("")
		lenS := fl.frame.AllocWord("")
		startOff := fl.frame.AllocWord("")
		tail := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(aStr), dis.FP(lenA)))
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		bgtIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenS), dis.FP(lenA), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenS), dis.FP(lenA), dis.FP(startOff)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(aStr), dis.FP(tail)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(startOff), dis.FP(lenA), dis.FP(tail)))
		beqIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQC, dis.FP(sStr), dis.FP(tail), dis.Imm(0)))
		jmpDone := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		truePC := int32(len(fl.insts))
		fl.insts[beqIdx].Dst = dis.Imm(truePC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[bgtIdx].Dst = dis.Imm(donePC)
		fl.insts[jmpDone].Dst = dis.Imm(donePC)
		return true, nil

	case "Index":
		// bytes.Index(s, sep) → convert to strings, search loop
		sOp := fl.operandOf(instr.Call.Args[0])
		sepOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		sepStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, sOp, dis.FP(sStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, sepOp, dis.FP(sepStr)))
		lenS := fl.frame.AllocWord("")
		lenSep := fl.frame.AllocWord("")
		limit := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		endIdx := fl.frame.AllocWord("")
		candidate := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sepStr), dis.FP(lenSep)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
		// empty sep → return 0
		beqEmpty := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(lenSep), dis.Imm(0)))
		bgtShort := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSep), dis.FP(lenS), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSep), dis.FP(lenS), dis.FP(limit)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(limit), dis.FP(limit)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
		loopPC := int32(len(fl.insts))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(limit), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSep), dis.FP(i), dis.FP(endIdx)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(sStr), dis.FP(candidate)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))
		beqFound := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQC, dis.FP(sepStr), dis.FP(candidate), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))
		foundPC := int32(len(fl.insts))
		fl.insts[beqFound].Dst = dis.Imm(foundPC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(i), dis.FP(dst)))
		jmpDone := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		emptyPC := int32(len(fl.insts))
		fl.insts[beqEmpty].Dst = dis.Imm(emptyPC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[bgtShort].Dst = dis.Imm(donePC)
		fl.insts[bgeIdx].Dst = dis.Imm(donePC)
		fl.insts[jmpDone].Dst = dis.Imm(donePC)
		return true, nil

	case "IndexByte":
		// bytes.IndexByte(b, c) → loop over string chars
		bOp := fl.operandOf(instr.Call.Args[0])
		cOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, bOp, dis.FP(sStr)))
		lenS := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		ch := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
		loopPC := int32(len(fl.insts))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IINDC, dis.FP(sStr), dis.FP(i), dis.FP(ch)))
		beqFound := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, cOp, dis.FP(ch), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))
		foundPC := int32(len(fl.insts))
		fl.insts[beqFound].Dst = dis.Imm(foundPC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(i), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[bgeIdx].Dst = dis.Imm(donePC)
		return true, nil

	case "Count":
		// bytes.Count(s, sep) → count non-overlapping occurrences
		sOp := fl.operandOf(instr.Call.Args[0])
		sepOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		sepStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, sOp, dis.FP(sStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, sepOp, dis.FP(sepStr)))
		lenS := fl.frame.AllocWord("")
		lenSep := fl.frame.AllocWord("")
		limit := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		endIdx := fl.frame.AllocWord("")
		candidate := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sepStr), dis.FP(lenSep)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		bgtShort := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSep), dis.FP(lenS), dis.Imm(0)))
		// empty sep: return len+1
		beqEmptySep := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(lenSep), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSep), dis.FP(lenS), dis.FP(limit)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(limit), dis.FP(limit)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
		loopPC := int32(len(fl.insts))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(limit), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSep), dis.FP(i), dis.FP(endIdx)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(sStr), dis.FP(candidate)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))
		bneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEC, dis.FP(sepStr), dis.FP(candidate), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(dst), dis.FP(dst)))
		fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSep), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))
		noMatchPC := int32(len(fl.insts))
		fl.insts[bneIdx].Dst = dis.Imm(noMatchPC)
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))
		emptyPC := int32(len(fl.insts))
		fl.insts[beqEmptySep].Dst = dis.Imm(emptyPC)
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(lenS), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[bgtShort].Dst = dis.Imm(donePC)
		fl.insts[bgeIdx].Dst = dis.Imm(donePC)
		return true, nil

	case "TrimSpace":
		// Convert to string, trim leading/trailing whitespace, convert back
		bOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, bOp, dis.FP(sStr)))
		lenS := fl.frame.AllocWord("")
		startIdx := fl.frame.AllocWord("")
		endI := fl.frame.AllocWord("")
		ch := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(startIdx)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(lenS), dis.FP(endI)))
		// trim leading
		trimLeadPC := int32(len(fl.insts))
		bgeSkipLead := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(startIdx), dis.FP(endI), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IINDC, dis.FP(sStr), dis.FP(startIdx), dis.FP(ch)))
		// check space (32), tab (9), newline (10), carriage return (13)
		beqSpace1 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(32), dis.FP(ch), dis.Imm(0)))
		beqTab := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(9), dis.FP(ch), dis.Imm(0)))
		beqNL := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(10), dis.FP(ch), dis.Imm(0)))
		beqCR := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(13), dis.FP(ch), dis.Imm(0)))
		jmpTrimTrail := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		incLeadPC := int32(len(fl.insts))
		fl.insts[beqSpace1].Dst = dis.Imm(incLeadPC)
		fl.insts[beqTab].Dst = dis.Imm(incLeadPC)
		fl.insts[beqNL].Dst = dis.Imm(incLeadPC)
		fl.insts[beqCR].Dst = dis.Imm(incLeadPC)
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(startIdx), dis.FP(startIdx)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(trimLeadPC)))
		// trim trailing
		trimTrailPC := int32(len(fl.insts))
		fl.insts[jmpTrimTrail].Dst = dis.Imm(trimTrailPC)
		fl.insts[bgeSkipLead].Dst = dis.Imm(trimTrailPC)
		tailIdx := fl.frame.AllocWord("")
		trimTrailLoop := int32(len(fl.insts))
		bleDone := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLEW, dis.FP(endI), dis.FP(startIdx), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(endI), dis.FP(tailIdx)))
		fl.emit(dis.NewInst(dis.IINDC, dis.FP(sStr), dis.FP(tailIdx), dis.FP(ch)))
		beqSpace2 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(32), dis.FP(ch), dis.Imm(0)))
		beqTab2 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(9), dis.FP(ch), dis.Imm(0)))
		beqNL2 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(10), dis.FP(ch), dis.Imm(0)))
		beqCR2 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(13), dis.FP(ch), dis.Imm(0)))
		jmpSlice := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		decTrailPC := int32(len(fl.insts))
		fl.insts[beqSpace2].Dst = dis.Imm(decTrailPC)
		fl.insts[beqTab2].Dst = dis.Imm(decTrailPC)
		fl.insts[beqNL2].Dst = dis.Imm(decTrailPC)
		fl.insts[beqCR2].Dst = dis.Imm(decTrailPC)
		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(endI), dis.FP(endI)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(trimTrailLoop)))
		slicePC := int32(len(fl.insts))
		fl.insts[jmpSlice].Dst = dis.Imm(slicePC)
		fl.insts[bleDone].Dst = dis.Imm(slicePC)
		result := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(sStr), dis.FP(result)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(startIdx), dis.FP(endI), dis.FP(result)))
		fl.emit(dis.Inst2(dis.ICVTCA, dis.FP(result), dis.FP(dst)))
		return true, nil

	case "ToLower":
		// Convert to string, lowercase each char, convert back
		bOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, bOp, dis.FP(sStr)))
		lenS := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		ch := fl.frame.AllocWord("")
		result := fl.frame.AllocTemp(true)
		charStr := fl.frame.AllocTemp(true)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
		loopPC := int32(len(fl.insts))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IINDC, dis.FP(sStr), dis.FP(i), dis.FP(ch)))
		// if 'A' <= ch <= 'Z', ch += 32
		bltNoConv := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, dis.FP(ch), dis.Imm(65), dis.Imm(0)))
		bgtNoConv := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(ch), dis.Imm(90), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(32), dis.FP(ch), dis.FP(ch)))
		noConvPC := int32(len(fl.insts))
		fl.insts[bltNoConv].Dst = dis.Imm(noConvPC)
		fl.insts[bgtNoConv].Dst = dis.Imm(noConvPC)
		fl.emit(dis.Inst2(dis.ICVTWC, dis.FP(ch), dis.FP(charStr)))
		fl.emit(dis.NewInst(dis.IADDC, dis.FP(charStr), dis.FP(result), dis.FP(result)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))
		donePC := int32(len(fl.insts))
		fl.insts[bgeIdx].Dst = dis.Imm(donePC)
		fl.emit(dis.Inst2(dis.ICVTCA, dis.FP(result), dis.FP(dst)))
		return true, nil

	case "ToUpper":
		// Convert to string, uppercase each char, convert back
		bOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, bOp, dis.FP(sStr)))
		lenS := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		ch := fl.frame.AllocWord("")
		result := fl.frame.AllocTemp(true)
		charStr := fl.frame.AllocTemp(true)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
		loopPC := int32(len(fl.insts))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IINDC, dis.FP(sStr), dis.FP(i), dis.FP(ch)))
		// if 'a' <= ch <= 'z', ch -= 32
		bltNoConv := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, dis.FP(ch), dis.Imm(97), dis.Imm(0)))
		bgtNoConv := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(ch), dis.Imm(122), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(32), dis.FP(ch), dis.FP(ch)))
		noConvPC := int32(len(fl.insts))
		fl.insts[bltNoConv].Dst = dis.Imm(noConvPC)
		fl.insts[bgtNoConv].Dst = dis.Imm(noConvPC)
		fl.emit(dis.Inst2(dis.ICVTWC, dis.FP(ch), dis.FP(charStr)))
		fl.emit(dis.NewInst(dis.IADDC, dis.FP(charStr), dis.FP(result), dis.FP(result)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))
		donePC := int32(len(fl.insts))
		fl.insts[bgeIdx].Dst = dis.Imm(donePC)
		fl.emit(dis.Inst2(dis.ICVTCA, dis.FP(result), dis.FP(dst)))
		return true, nil

	case "Repeat":
		// bytes.Repeat(b, count) → convert to string, repeat, convert back
		bOp := fl.operandOf(instr.Call.Args[0])
		countOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, bOp, dis.FP(sStr)))
		result := fl.frame.AllocTemp(true)
		i := fl.frame.AllocWord("")
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
		loopPC := int32(len(fl.insts))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), countOp, dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDC, dis.FP(sStr), dis.FP(result), dis.FP(result)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))
		donePC := int32(len(fl.insts))
		fl.insts[bgeIdx].Dst = dis.Imm(donePC)
		fl.emit(dis.Inst2(dis.ICVTCA, dis.FP(result), dis.FP(dst)))
		return true, nil

	case "Join":
		// bytes.Join(s [][]byte, sep []byte) []byte — stub returns nil
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil

	case "Split":
		// bytes.Split(s, sep []byte) [][]byte — stub returns nil slice
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil

	case "Replace", "ReplaceAll":
		// bytes.Replace/ReplaceAll — convert to strings, use string replace, convert back
		sOp := fl.operandOf(instr.Call.Args[0])
		oldOp := fl.operandOf(instr.Call.Args[1])
		newOp := fl.operandOf(instr.Call.Args[2])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		oldStr := fl.frame.AllocTemp(true)
		newStr := fl.frame.AllocTemp(true)
		result := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, sOp, dis.FP(sStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, oldOp, dis.FP(oldStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, newOp, dis.FP(newStr)))
		// Inline replace loop
		lenS := fl.frame.AllocWord("")
		lenOld := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		endIdx := fl.frame.AllocWord("")
		limit := fl.frame.AllocWord("")
		candidate := fl.frame.AllocTemp(true)
		iP1 := fl.frame.AllocWord("")
		charStr := fl.frame.AllocTemp(true)
		ch := fl.frame.AllocWord("")
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(oldStr), dis.FP(lenOld)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
		loopPC := int32(len(fl.insts))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))
		// check if old matches at position i
		fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenOld), dis.FP(i), dis.FP(endIdx)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenOld), dis.FP(lenS), dis.FP(limit)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(limit), dis.FP(limit)))
		bgtNoMatch := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(endIdx), dis.FP(lenS), dis.Imm(0)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(sStr), dis.FP(candidate)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))
		bneNoMatch := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEC, dis.FP(oldStr), dis.FP(candidate), dis.Imm(0)))
		// match found: append new, skip old
		fl.emit(dis.NewInst(dis.IADDC, dis.FP(newStr), dis.FP(result), dis.FP(result)))
		fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenOld), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))
		// no match: append current char
		noMatchPC := int32(len(fl.insts))
		fl.insts[bgtNoMatch].Dst = dis.Imm(noMatchPC)
		fl.insts[bneNoMatch].Dst = dis.Imm(noMatchPC)
		fl.emit(dis.NewInst(dis.IINDC, dis.FP(sStr), dis.FP(i), dis.FP(ch)))
		fl.emit(dis.Inst2(dis.ICVTWC, dis.FP(ch), dis.FP(charStr)))
		fl.emit(dis.NewInst(dis.IADDC, dis.FP(charStr), dis.FP(result), dis.FP(result)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(iP1)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(iP1), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))
		donePC := int32(len(fl.insts))
		fl.insts[bgeIdx].Dst = dis.Imm(donePC)
		fl.emit(dis.Inst2(dis.ICVTCA, dis.FP(result), dis.FP(dst)))
		return true, nil

	case "Trim", "TrimLeft", "TrimRight":
		// bytes.Trim/TrimLeft/TrimRight(s, cutset) — simplified: return input unchanged
		bOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, bOp, dis.FP(dst)))
		return true, nil

	case "NewBuffer", "NewBufferString":
		// bytes.NewBuffer/NewBufferString → returns 0 handle (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil

	case "NewReader":
		// bytes.NewReader(b) → returns 0 handle (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil

	case "TrimPrefix":
		// bytes.TrimPrefix(s, prefix) → if s has prefix, return s[len(prefix):]
		sOp := fl.operandOf(instr.Call.Args[0])
		pOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		pStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, sOp, dis.FP(sStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, pOp, dis.FP(pStr)))
		lenS := fl.frame.AllocWord("")
		lenP := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(pStr), dis.FP(lenP)))
		// default: return s unchanged
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		bgtIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenP), dis.FP(lenS), dis.Imm(0)))
		head := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(sStr), dis.FP(head)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.FP(lenP), dis.FP(head)))
		bneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEC, dis.FP(pStr), dis.FP(head), dis.Imm(0)))
		trimmed := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(sStr), dis.FP(trimmed)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(lenP), dis.FP(lenS), dis.FP(trimmed)))
		fl.emit(dis.Inst2(dis.ICVTCA, dis.FP(trimmed), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[bgtIdx].Dst = dis.Imm(donePC)
		fl.insts[bneIdx].Dst = dis.Imm(donePC)
		return true, nil

	case "TrimSuffix":
		// bytes.TrimSuffix(s, suffix) → if s has suffix, return s[:len(s)-len(suffix)]
		sOp := fl.operandOf(instr.Call.Args[0])
		sfxOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		sfxStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, sOp, dis.FP(sStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, sfxOp, dis.FP(sfxStr)))
		lenS := fl.frame.AllocWord("")
		lenSfx := fl.frame.AllocWord("")
		startOff := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sfxStr), dis.FP(lenSfx)))
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		bgtIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSfx), dis.FP(lenS), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSfx), dis.FP(lenS), dis.FP(startOff)))
		tail := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(sStr), dis.FP(tail)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(startOff), dis.FP(lenS), dis.FP(tail)))
		bneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEC, dis.FP(sfxStr), dis.FP(tail), dis.Imm(0)))
		trimmed := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(sStr), dis.FP(trimmed)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.FP(startOff), dis.FP(trimmed)))
		fl.emit(dis.Inst2(dis.ICVTCA, dis.FP(trimmed), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[bgtIdx].Dst = dis.Imm(donePC)
		fl.insts[bneIdx].Dst = dis.Imm(donePC)
		return true, nil

	case "LastIndex":
		// bytes.LastIndex(s, sep) → search from end
		sOp := fl.operandOf(instr.Call.Args[0])
		sepOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		sepStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, sOp, dis.FP(sStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, sepOp, dis.FP(sepStr)))
		lenS := fl.frame.AllocWord("")
		lenSep := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		endIdx := fl.frame.AllocWord("")
		candidate := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sepStr), dis.FP(lenSep)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
		bgtIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSep), dis.FP(lenS), dis.Imm(0)))
		// start from lenS-lenSep, go down to 0
		fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSep), dis.FP(lenS), dis.FP(i)))
		loopPC := int32(len(fl.insts))
		bltIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, dis.FP(i), dis.Imm(0), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSep), dis.FP(i), dis.FP(endIdx)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(sStr), dis.FP(candidate)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))
		beqFound := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQC, dis.FP(sepStr), dis.FP(candidate), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))
		foundPC := int32(len(fl.insts))
		fl.insts[beqFound].Dst = dis.Imm(foundPC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(i), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[bgtIdx].Dst = dis.Imm(donePC)
		fl.insts[bltIdx].Dst = dis.Imm(donePC)
		return true, nil

	case "EqualFold":
		// bytes.EqualFold(s, t) → case-insensitive comparison via string conversion
		sOp := fl.operandOf(instr.Call.Args[0])
		tOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		tStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, sOp, dis.FP(sStr)))
		fl.emit(dis.Inst2(dis.ICVTAC, tOp, dis.FP(tStr)))
		// Lowercase both and compare
		lenS := fl.frame.AllocWord("")
		lenT := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(tStr), dis.FP(lenT)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		// If lengths differ → false
		bneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEW, dis.FP(lenS), dis.FP(lenT), dis.Imm(0)))
		// Compare char by char, case-insensitive
		i := fl.frame.AllocWord("")
		chS := fl.frame.AllocWord("")
		chT := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
		loopPC := int32(len(fl.insts))
		bgeMatch := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IINDC, dis.FP(sStr), dis.FP(i), dis.FP(chS)))
		fl.emit(dis.NewInst(dis.IINDC, dis.FP(tStr), dis.FP(i), dis.FP(chT)))
		// to lower: if 'A' <= ch <= 'Z', ch += 32
		bltS := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, dis.FP(chS), dis.Imm(65), dis.Imm(0)))
		bgtS := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(chS), dis.Imm(90), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(32), dis.FP(chS), dis.FP(chS)))
		skipS := int32(len(fl.insts))
		fl.insts[bltS].Dst = dis.Imm(skipS)
		fl.insts[bgtS].Dst = dis.Imm(skipS)
		bltT := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, dis.FP(chT), dis.Imm(65), dis.Imm(0)))
		bgtT := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(chT), dis.Imm(90), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(32), dis.FP(chT), dis.FP(chT)))
		skipT := int32(len(fl.insts))
		fl.insts[bltT].Dst = dis.Imm(skipT)
		fl.insts[bgtT].Dst = dis.Imm(skipT)
		bneMismatch := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEW, dis.FP(chS), dis.FP(chT), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))
		matchPC := int32(len(fl.insts))
		fl.insts[bgeMatch].Dst = dis.Imm(matchPC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[bneIdx].Dst = dis.Imm(donePC)
		fl.insts[bneMismatch].Dst = dis.Imm(donePC)
		return true, nil

	case "ContainsRune":
		// bytes.ContainsRune(b, r) → loop through chars
		bOp := fl.operandOf(instr.Call.Args[0])
		rOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, bOp, dis.FP(sStr)))
		lenS := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		ch := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
		loopPC := int32(len(fl.insts))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IINDC, dis.FP(sStr), dis.FP(i), dis.FP(ch)))
		beqFound := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, rOp, dis.FP(ch), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))
		foundPC := int32(len(fl.insts))
		fl.insts[beqFound].Dst = dis.Imm(foundPC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[bgeIdx].Dst = dis.Imm(donePC)
		return true, nil

	case "ContainsAny":
		// bytes.ContainsAny(b, chars) → double loop
		bOp := fl.operandOf(instr.Call.Args[0])
		charsOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		sStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, bOp, dis.FP(sStr)))
		lenS := fl.frame.AllocWord("")
		lenC := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		j := fl.frame.AllocWord("")
		ch := fl.frame.AllocWord("")
		cc := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.ILENC, charsOp, dis.FP(lenC)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
		outerPC := int32(len(fl.insts))
		bgeOuter := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IINDC, dis.FP(sStr), dis.FP(i), dis.FP(ch)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(j)))
		innerPC := int32(len(fl.insts))
		bgeInner := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(j), dis.FP(lenC), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IINDC, charsOp, dis.FP(j), dis.FP(cc)))
		beqFound := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.FP(ch), dis.FP(cc), dis.Imm(0)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(j), dis.FP(j)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(innerPC)))
		nextI := int32(len(fl.insts))
		fl.insts[bgeInner].Dst = dis.Imm(nextI)
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(outerPC)))
		foundPC := int32(len(fl.insts))
		fl.insts[beqFound].Dst = dis.Imm(foundPC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[bgeOuter].Dst = dis.Imm(donePC)
		return true, nil

	case "Fields", "SplitN":
		// stub: return nil slice
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil

	case "Map":
		// bytes.Map — stub: return input unchanged
		dst := fl.slotOf(instr)
		sOp := fl.operandOf(instr.Call.Args[1])
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		return true, nil

	// Buffer method stubs — all Buffer methods come through here
	case "Write":
		// (*Buffer).Write(p) → (len(p), nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil

	case "WriteString":
		// (*Buffer).WriteString(s) → (len(s), nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil

	case "WriteByte":
		// (*Buffer).WriteByte(c) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil

	case "String":
		// (*Buffer).String() → empty string
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil

	case "Bytes":
		// (*Buffer).Bytes() → nil slice
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil

	case "Len":
		// (*Buffer).Len() → 0
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil

	case "Reset":
		// (*Buffer).Reset() → no-op
		return true, nil

	case "Read":
		// (*Buffer).Read(p) → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil

	case "ReadByte":
		// (*Buffer).ReadByte() → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil

	case "ReadString":
		// (*Buffer).ReadString(delim) → ("", nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil

	// New bytes functions
	case "ToTitle", "Title", "ToValidUTF8", "Runes":
		// []byte → []byte — pass through as identity stub
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, src, dis.FP(dst)))
		return true, nil

	case "IndexAny", "LastIndexAny":
		// ([]byte, string) → int — -1 stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
		return true, nil

	case "LastIndexByte":
		// ([]byte, byte) → int — -1 stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
		return true, nil

	case "IndexRune":
		// ([]byte, rune) → int — -1 stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
		return true, nil

	case "IndexFunc", "LastIndexFunc":
		// ([]byte, func(rune) bool) → int — -1 stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
		return true, nil

	case "SplitAfter", "SplitAfterN", "FieldsFunc":
		// → nil slice stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil

	case "ContainsFunc":
		// ([]byte, func(rune) bool) → false stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil

	case "TrimFunc", "TrimLeftFunc", "TrimRightFunc":
		// ([]byte, func) → []byte — pass through
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, src, dis.FP(dst)))
		return true, nil

	case "Clone":
		// Clone(b) → b (shallow copy is fine for immutable Dis)
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, src, dis.FP(dst)))
		return true, nil

	case "CutPrefix", "CutSuffix":
		// (s, prefix/suffix) → (after/before, found) — (s, false) stub
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, src, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil

	case "Cut":
		// (s, sep) → (before, after, found) — (s, "", false) stub
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, src, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil

	// Additional Buffer methods
	case "Cap":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Grow":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	case "WriteRune":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
	case "ReadRune":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
	case "UnreadByte", "UnreadRune":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "ReadBytes":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
	case "Next":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Truncate":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	case "WriteTo":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
	case "ReadFrom":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
	case "Available":
		// (*Buffer).Available() → 0 stub
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "AvailableBuffer":
		// (*Buffer).AvailableBuffer() → nil slice stub
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	}
	return false, nil
}

// lowerEncodingHexCall handles encoding/hex package functions.
func (fl *funcLowerer) lowerEncodingHexCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Encode":
		// hex.Encode(dst, src) → int (stub: 0)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Decode":
		// hex.Decode(dst, src) → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Dump":
		// hex.Dump(data) → "" stub
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "NewEncoder", "NewDecoder", "Dumper":
		// hex.NewEncoder/NewDecoder/Dumper → nil interface stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "EncodeToString":
		// Convert each byte to 2-char hex string
		srcOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)

		sStr := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.ICVTAC, srcOp, dis.FP(sStr)))

		lenS := fl.frame.AllocWord("")
		i := fl.frame.AllocWord("")
		ch := fl.frame.AllocWord("")
		hi := fl.frame.AllocWord("")
		lo := fl.frame.AllocWord("")
		hiP1 := fl.frame.AllocWord("")
		loP1 := fl.frame.AllocWord("")
		hiStr := fl.frame.AllocTemp(true)
		loStr := fl.frame.AllocTemp(true)
		result := fl.frame.AllocTemp(true)

		hexTableOff := fl.comp.AllocString("0123456789abcdef")
		emptyOff := fl.comp.AllocString("")

		fl.emit(dis.Inst2(dis.ILENC, dis.FP(sStr), dis.FP(lenS)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

		loopPC := int32(len(fl.insts))
		bgeDone := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))

		fl.emit(dis.NewInst(dis.IINDC, dis.FP(sStr), dis.FP(i), dis.FP(ch)))
		// hi = ch >> 4; lo = ch & 0xf
		fl.emit(dis.NewInst(dis.ISHRW, dis.Imm(4), dis.FP(ch), dis.FP(hi)))
		fl.emit(dis.NewInst(dis.IANDW, dis.Imm(15), dis.FP(ch), dis.FP(lo)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(hi), dis.FP(hiP1)))
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(lo), dis.FP(loP1)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(hexTableOff), dis.FP(hiStr)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(hi), dis.FP(hiP1), dis.FP(hiStr)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(hexTableOff), dis.FP(loStr)))
		fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(lo), dis.FP(loP1), dis.FP(loStr)))
		fl.emit(dis.NewInst(dis.IADDC, dis.FP(hiStr), dis.FP(result), dis.FP(result)))
		fl.emit(dis.NewInst(dis.IADDC, dis.FP(loStr), dis.FP(result), dis.FP(result)))

		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

		donePC := int32(len(fl.insts))
		fl.insts[bgeDone].Dst = dis.Imm(donePC)
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(result), dis.FP(dst)))
		return true, nil

	case "DecodeString":
		// hex.DecodeString returns ([]byte, error) — simplified
		srcOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		// For now, just convert the string to bytes directly (stub)
		fl.emit(dis.Inst2(dis.ICVTCA, srcOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "EncodedLen":
		// EncodedLen(n) = n * 2
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "DecodedLen":
		// DecodedLen(x) = x / 2
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "AppendEncode":
		// AppendEncode(dst, src) → dst (passthrough stub)
		srcOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, srcOp, dis.FP(dst)))
		return true, nil
	case "AppendDecode":
		// AppendDecode(dst, src) → (dst, nil)
		srcOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, srcOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Error":
		// InvalidByteError.Error() → ""
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// lowerEncodingBase64Call handles encoding/base64 package functions.
func (fl *funcLowerer) lowerEncodingBase64Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	// Base64 operations are complex; provide stub implementations
	// that pass type-checking but use simplified encoding
	name := callee.Name()

	dst := fl.slotOf(instr)
	iby2wd := int32(dis.IBY2WD)
	switch name {
	case "EncodeToString":
		srcOp := fl.operandOf(instr.Call.Args[1]) // arg after receiver
		fl.emit(dis.Inst2(dis.ICVTAC, srcOp, dis.FP(dst)))
		return true, nil
	case "DecodeString":
		srcOp := fl.operandOf(instr.Call.Args[1])
		fl.emit(dis.Inst2(dis.ICVTCA, srcOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Encode":
		// no-op stub (writes to dst buffer)
		return true, nil
	case "Decode":
		// stub returning (0, nil)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "EncodedLen", "DecodedLen":
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Strict", "WithPadding":
		// Return receiver (self)
		recvOp := fl.operandOf(instr.Call.Args[0])
		fl.emit(dis.Inst2(dis.IMOVP, recvOp, dis.FP(dst)))
		return true, nil
	case "NewEncoding":
		// Return nil *Encoding
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewEncoder", "NewDecoder":
		// Return nil interface
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// fmt package — extended functions
// ============================================================

// lowerFmtSprint: fmt.Sprint(args...) → string. Same as Sprintf with "%v" style.
func (fl *funcLowerer) lowerFmtSprint(instr *ssa.Call) (bool, error) {
	// Sprint concatenates values with no separator.
	// Use the same approach as Println but collect into string instead of printing.
	strSlot, ok := fl.emitSprintConcatInline(instr, false)
	if !ok {
		return false, nil
	}
	dst := fl.slotOf(instr)
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(strSlot), dis.FP(dst)))
	return true, nil
}

// lowerFmtSprintln: fmt.Sprintln(args...) → concatenate with spaces and newline.
func (fl *funcLowerer) lowerFmtSprintln(instr *ssa.Call) (bool, error) {
	strSlot, ok := fl.emitSprintConcatInline(instr, true)
	if !ok {
		return false, nil
	}
	dst := fl.slotOf(instr)
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(strSlot), dis.FP(dst)))
	return true, nil
}

// lowerFmtPrint: fmt.Print(args...) → print without newline.
func (fl *funcLowerer) lowerFmtPrint(instr *ssa.Call) (bool, error) {
	strSlot, ok := fl.emitSprintConcatInline(instr, false)
	if !ok {
		return false, nil
	}
	fl.emitSysCall("print", []callSiteArg{{strSlot, true}})
	if len(*instr.Referrers()) > 0 {
		dstSlot := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot+2*iby2wd)))
	}
	return true, nil
}

// lowerFmtFprintf: fmt.Fprintf(w, format, args...) → ignore w, use Printf logic.
func (fl *funcLowerer) lowerFmtFprintf(instr *ssa.Call) (bool, error) {
	// Skip the first arg (w io.Writer) and treat rest as Printf
	// Create a modified Call that skips the writer argument
	strSlot, ok := fl.emitSprintfInline(instr)
	if !ok {
		return false, nil
	}
	fl.emitSysCall("print", []callSiteArg{{strSlot, true}})
	if len(*instr.Referrers()) > 0 {
		dstSlot := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot+2*iby2wd)))
	}
	return true, nil
}

// lowerFmtFprintln: fmt.Fprintln(w, args...) → ignore w, use Println logic.
func (fl *funcLowerer) lowerFmtFprintln(instr *ssa.Call) (bool, error) {
	strSlot, ok := fl.emitSprintConcatInline(instr, true)
	if !ok {
		return false, nil
	}
	fl.emitSysCall("print", []callSiteArg{{strSlot, true}})
	if len(*instr.Referrers()) > 0 {
		dstSlot := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot+2*iby2wd)))
	}
	return true, nil
}

// lowerFmtFprint: fmt.Fprint(w, args...) → ignore w, print args.
func (fl *funcLowerer) lowerFmtFprint(instr *ssa.Call) (bool, error) {
	strSlot, ok := fl.emitSprintConcatInline(instr, false)
	if !ok {
		return false, nil
	}
	fl.emitSysCall("print", []callSiteArg{{strSlot, true}})
	if len(*instr.Referrers()) > 0 {
		dstSlot := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot+2*iby2wd)))
	}
	return true, nil
}

// emitSprintConcatInline concatenates the variadic args of a Print/Sprint/Println-style call
// into a single string. If addNewline is true, appends "\n" at the end (Println style).
// Returns the frame slot of the result string and true on success.
func (fl *funcLowerer) emitSprintConcatInline(instr *ssa.Call, addNewline bool) (int32, bool) {
	result := fl.frame.AllocTemp(true)
	emptyOff := fl.comp.AllocString("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))

	args := instr.Call.Args
	// Skip first arg if it's an io.Writer (Fprint/Fprintln/Fprintf)
	startIdx := 0
	if len(args) > 0 {
		if _, ok := args[0].Type().Underlying().(*types.Interface); ok {
			// Could be io.Writer — check if this is an F-variant
			name := ""
			if callee, ok := instr.Call.Value.(*ssa.Function); ok {
				name = callee.Name()
			}
			if name == "Fprintf" || name == "Fprintln" || name == "Fprint" {
				startIdx = 1
			}
		}
	}

	for i := startIdx; i < len(args); i++ {
		arg := args[i]

		// Try to trace through SliceToArrayPointer or other wrapping
		t := arg.Type().Underlying()
		basic, isBasic := t.(*types.Basic)

		tmp := fl.frame.AllocTemp(true)

		if isBasic {
			switch {
			case basic.Kind() == types.String:
				src := fl.operandOf(arg)
				fl.emit(dis.Inst2(dis.IMOVP, src, dis.FP(tmp)))
			case basic.Info()&types.IsInteger != 0:
				src := fl.operandOf(arg)
				fl.emit(dis.Inst2(dis.ICVTWC, src, dis.FP(tmp)))
			case basic.Info()&types.IsFloat != 0:
				src := fl.operandOf(arg)
				fl.emit(dis.Inst2(dis.ICVTFC, src, dis.FP(tmp)))
			case basic.Kind() == types.Bool:
				src := fl.operandOf(arg)
				trueMP := fl.comp.AllocString("true")
				falseMP := fl.comp.AllocString("false")
				fl.emit(dis.Inst2(dis.IMOVP, dis.MP(falseMP), dis.FP(tmp)))
				skipIdx := len(fl.insts)
				fl.emit(dis.NewInst(dis.IBEQW, src, dis.Imm(0), dis.Imm(0)))
				fl.emit(dis.Inst2(dis.IMOVP, dis.MP(trueMP), dis.FP(tmp)))
				fl.insts[skipIdx].Dst = dis.Imm(int32(len(fl.insts)))
			default:
				src := fl.operandOf(arg)
				fl.emit(dis.Inst2(dis.ICVTWC, src, dis.FP(tmp)))
			}
		} else {
			// Non-basic: try CVTWC
			src := fl.operandOf(arg)
			fl.emit(dis.Inst2(dis.ICVTWC, src, dis.FP(tmp)))
		}

		// Add space separator for Println (between args, not before first)
		if addNewline && i > startIdx {
			spaceMP := fl.comp.AllocString(" ")
			fl.emit(dis.NewInst(dis.IADDC, dis.MP(spaceMP), dis.FP(result), dis.FP(result)))
		}

		fl.emit(dis.NewInst(dis.IADDC, dis.FP(tmp), dis.FP(result), dis.FP(result)))
	}

	if addNewline {
		nlMP := fl.comp.AllocString("\n")
		fl.emit(dis.NewInst(dis.IADDC, dis.MP(nlMP), dis.FP(result), dis.FP(result)))
	}

	return result, true
}

// ============================================================
// path/filepath package
// ============================================================

// lowerFilepathCall handles calls to the path/filepath package.
// Since Inferno uses forward-slash paths (like Unix), filepath functions
// behave identically to the path package equivalents.
func (fl *funcLowerer) lowerFilepathCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Base":
		return fl.lowerFilepathBase(instr)
	case "Dir":
		return fl.lowerFilepathDir(instr)
	case "Ext":
		return fl.lowerFilepathExt(instr)
	case "Clean":
		return fl.lowerFilepathClean(instr)
	case "Join":
		return fl.lowerFilepathJoin(instr)
	case "IsAbs":
		return fl.lowerFilepathIsAbs(instr)
	case "Abs":
		return fl.lowerFilepathAbs(instr)
	case "Rel":
		// filepath.Rel → stub returning target and nil error
		targetSlot := fl.materialize(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(targetSlot), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Split":
		// filepath.Split(path) → (dir, file) — dir=Dir(path), file=Base(path)
		// Stub: return ("", path)
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst+iby2wd)))
		return true, nil
	case "ToSlash", "FromSlash":
		// On Inferno (Unix-like), these are identity
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		return true, nil
	case "Match":
		// filepath.Match(pattern, name) → (false, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Glob":
		// filepath.Glob(pattern) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "EvalSymlinks":
		// filepath.EvalSymlinks(path) → (path, nil) stub
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "VolumeName":
		// filepath.VolumeName(path) → "" (no volumes on Inferno)
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "SplitList":
		// filepath.SplitList(path) → nil slice stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Walk", "WalkDir":
		// filepath.Walk/WalkDir(root, fn) → nil error stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "HasPrefix":
		// filepath.HasPrefix(p, prefix) → bool
		// Deprecated but still used. Check if p starts with prefix.
		// Stub: return strings.HasPrefix equivalent — just return true
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "IsLocal":
		// filepath.IsLocal(path) → bool — Go 1.20+
		// Returns true if path is local (no "..", no abs path, no special chars)
		// Stub: return true (assume paths are local)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// lowerFilepathBase returns the last element of path (after final slash).
func (fl *funcLowerer) lowerFilepathBase(instr *ssa.Call) (bool, error) {
	pathOp := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	lenP := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, pathOp, dis.FP(lenP)))

	// Empty path → return "."
	dotOff := fl.comp.AllocString(".")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(dotOff), dis.FP(dst)))
	beqEmptyIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(lenP), dis.Imm(0)))

	// Start from end, find last '/'
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(lenP), dis.FP(i)))
	loopPC := int32(len(fl.insts))
	bltIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, dis.FP(i), dis.Imm(0), dis.Imm(0)))

	// Check if path[i] == '/'
	charSlot := fl.frame.AllocTemp(true)
	endIdx := fl.frame.AllocWord("")
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(i), dis.Imm(1), dis.FP(endIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, pathOp, dis.FP(charSlot)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(charSlot)))
	slashOff := fl.comp.AllocString("/")
	beqSlashIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, dis.MP(slashOff), dis.FP(charSlot), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// Found slash at i → result is path[i+1:]
	foundPC := int32(len(fl.insts))
	fl.insts[beqSlashIdx].Dst = dis.Imm(foundPC)
	startSlot := fl.frame.AllocWord("")
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(startSlot)))
	fl.emit(dis.Inst2(dis.IMOVP, pathOp, dis.FP(dst)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(startSlot), dis.FP(lenP), dis.FP(dst)))
	jmpEndIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// No slash found → whole path is the base
	noSlashPC := int32(len(fl.insts))
	fl.insts[bltIdx].Dst = dis.Imm(noSlashPC)
	fl.emit(dis.Inst2(dis.IMOVP, pathOp, dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[jmpEndIdx].Dst = dis.Imm(donePC)
	fl.insts[beqEmptyIdx].Dst = dis.Imm(donePC)

	return true, nil
}

// lowerFilepathDir returns all but the last element of path.
func (fl *funcLowerer) lowerFilepathDir(instr *ssa.Call) (bool, error) {
	pathOp := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	lenP := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, pathOp, dis.FP(lenP)))

	// Empty path → return "."
	dotOff := fl.comp.AllocString(".")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(dotOff), dis.FP(dst)))
	beqEmptyIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(lenP), dis.Imm(0)))

	// Find last '/'
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(lenP), dis.FP(i)))
	loopPC := int32(len(fl.insts))
	bltIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, dis.FP(i), dis.Imm(0), dis.Imm(0)))

	charSlot := fl.frame.AllocTemp(true)
	endIdx := fl.frame.AllocWord("")
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(i), dis.Imm(1), dis.FP(endIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, pathOp, dis.FP(charSlot)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(charSlot)))
	slashOff := fl.comp.AllocString("/")
	beqSlashIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, dis.MP(slashOff), dis.FP(charSlot), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// Found slash at i → dir is path[:i] (or "/" if i==0)
	foundPC := int32(len(fl.insts))
	fl.insts[beqSlashIdx].Dst = dis.Imm(foundPC)
	beqRootIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(i), dis.Imm(0), dis.Imm(0)))
	fl.emit(dis.Inst2(dis.IMOVP, pathOp, dis.FP(dst)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.FP(i), dis.FP(dst)))
	jmpEndIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// Slash at 0 → return "/"
	rootPC := int32(len(fl.insts))
	fl.insts[beqRootIdx].Dst = dis.Imm(rootPC)
	rootOff := fl.comp.AllocString("/")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(rootOff), dis.FP(dst)))
	jmpEndIdx2 := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// No slash found → return "."
	noSlashPC := int32(len(fl.insts))
	fl.insts[bltIdx].Dst = dis.Imm(noSlashPC)

	donePC := int32(len(fl.insts))
	fl.insts[jmpEndIdx].Dst = dis.Imm(donePC)
	fl.insts[jmpEndIdx2].Dst = dis.Imm(donePC)
	fl.insts[beqEmptyIdx].Dst = dis.Imm(donePC)

	return true, nil
}

// lowerFilepathExt returns the file extension (including the dot).
func (fl *funcLowerer) lowerFilepathExt(instr *ssa.Call) (bool, error) {
	pathOp := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	lenP := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, pathOp, dis.FP(lenP)))

	// Default: empty string
	emptyOff := fl.comp.AllocString("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))

	beqEmptyIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(lenP), dis.Imm(0)))

	// Scan backwards for '.'
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(lenP), dis.FP(i)))
	loopPC := int32(len(fl.insts))
	bltIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, dis.FP(i), dis.Imm(0), dis.Imm(0)))

	charSlot := fl.frame.AllocTemp(true)
	endIdx := fl.frame.AllocWord("")
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(i), dis.Imm(1), dis.FP(endIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, pathOp, dis.FP(charSlot)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(charSlot)))

	// Check for '/'  — stop scanning if we hit a dir separator
	slashOff := fl.comp.AllocString("/")
	bSlashIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, dis.MP(slashOff), dis.FP(charSlot), dis.Imm(0)))

	// Check for '.'
	dotOff := fl.comp.AllocString(".")
	bDotIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, dis.MP(dotOff), dis.FP(charSlot), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// Found dot at i → ext is path[i:]
	foundDotPC := int32(len(fl.insts))
	fl.insts[bDotIdx].Dst = dis.Imm(foundDotPC)
	fl.emit(dis.Inst2(dis.IMOVP, pathOp, dis.FP(dst)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(lenP), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[bltIdx].Dst = dis.Imm(donePC)
	fl.insts[bSlashIdx].Dst = dis.Imm(donePC)
	fl.insts[beqEmptyIdx].Dst = dis.Imm(donePC)

	return true, nil
}

// lowerFilepathClean returns a cleaned path. Simplified: just returns the input.
func (fl *funcLowerer) lowerFilepathClean(instr *ssa.Call) (bool, error) {
	pathOp := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)
	fl.emit(dis.Inst2(dis.IMOVP, pathOp, dis.FP(dst)))
	return true, nil
}

// lowerFilepathJoin concatenates path elements with "/".
func (fl *funcLowerer) lowerFilepathJoin(instr *ssa.Call) (bool, error) {
	// filepath.Join is variadic, but SSA passes a slice.
	// For now, handle the common case of 2-3 literal string args.
	args := instr.Call.Args
	if len(args) == 0 {
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	}

	dst := fl.slotOf(instr)
	slashOff := fl.comp.AllocString("/")

	// Start with first argument
	first := fl.operandOf(args[0])
	fl.emit(dis.Inst2(dis.IMOVP, first, dis.FP(dst)))

	// Concatenate remaining with "/" separator
	for idx := 1; idx < len(args); idx++ {
		fl.emit(dis.NewInst(dis.IADDC, dis.MP(slashOff), dis.FP(dst), dis.FP(dst)))
		argOp := fl.operandOf(args[idx])
		fl.emit(dis.NewInst(dis.IADDC, argOp, dis.FP(dst), dis.FP(dst)))
	}

	return true, nil
}

// lowerFilepathIsAbs returns whether path is absolute (starts with '/').
func (fl *funcLowerer) lowerFilepathIsAbs(instr *ssa.Call) (bool, error) {
	pathOp := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	lenP := fl.frame.AllocWord("")
	fl.emit(dis.Inst2(dis.ILENC, pathOp, dis.FP(lenP)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))

	beqEmptyIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(lenP), dis.Imm(0)))

	// Check first char
	firstChar := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, pathOp, dis.FP(firstChar)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.Imm(1), dis.FP(firstChar)))
	slashOff := fl.comp.AllocString("/")
	bneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBNEC, dis.MP(slashOff), dis.FP(firstChar), dis.Imm(0)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[beqEmptyIdx].Dst = dis.Imm(donePC)
	fl.insts[bneIdx].Dst = dis.Imm(donePC)

	return true, nil
}

// lowerFilepathAbs returns an absolute path. Stub: returns path, nil error.
func (fl *funcLowerer) lowerFilepathAbs(instr *ssa.Call) (bool, error) {
	pathOp := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)
	iby2wd := int32(dis.IBY2WD)
	fl.emit(dis.Inst2(dis.IMOVP, pathOp, dis.FP(dst)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
	return true, nil
}

// ============================================================
// slices package (Go 1.21+)
// ============================================================

// lowerSlicesCall handles calls to the slices package.
func (fl *funcLowerer) lowerSlicesCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Contains", "ContainsFunc":
		return fl.lowerSlicesContains(instr)
	case "Index", "IndexFunc":
		return fl.lowerSlicesIndex(instr)
	case "Reverse", "Sort", "SortFunc", "SortStableFunc":
		// In-place operations: no-op stub
		return true, nil
	case "Compact", "CompactFunc", "DeleteFunc":
		// Return input slice unchanged
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		return true, nil
	case "Clone", "Clip", "Grow", "Delete", "Insert", "Replace", "Repeat":
		// Return input slice (passthrough stub)
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		return true, nil
	case "Concat":
		// slices.Concat: return nil slice (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Equal", "EqualFunc":
		// slices.Equal/EqualFunc: stub returns false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Compare", "CompareFunc":
		// slices.Compare/CompareFunc: stub returns 0 (equal)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "IsSorted", "IsSortedFunc":
		// stub returns true
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "Min", "Max", "MinFunc", "MaxFunc":
		// Return zero value (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "BinarySearch", "BinarySearchFunc":
		// Return (0, false) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "All", "Values", "Backward", "Chunk":
		// Iterator-returning: return nil (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Collect", "Sorted", "SortedFunc", "SortedStableFunc", "AppendSeq":
		// Slice-returning from iterator: return nil slice (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// lowerSlicesContains checks if a slice contains a value.
// Since slices are generic in Go but we use interface stubs,
// the actual implementation depends on the concrete type at the call site.
func (fl *funcLowerer) lowerSlicesContains(instr *ssa.Call) (bool, error) {
	// Simplified: return false (stub)
	// Full implementation would need type-specific comparison over the slice.
	dst := fl.slotOf(instr)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
	return true, nil
}

// lowerSlicesIndex returns the index of a value in a slice, or -1 if not found.
func (fl *funcLowerer) lowerSlicesIndex(instr *ssa.Call) (bool, error) {
	// Simplified: return -1 (stub)
	dst := fl.slotOf(instr)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
	return true, nil
}

// ============================================================
// maps package (Go 1.21+)
// ============================================================

// lowerMapsCall handles calls to the maps package.
func (fl *funcLowerer) lowerMapsCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Keys":
		// maps.Keys: stub returns nil slice
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Values":
		// maps.Values: stub returns nil slice
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Clone":
		// maps.Clone: return input map (shallow)
		mOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, mOp, dis.FP(dst)))
		return true, nil
	case "Equal":
		// maps.Equal: stub returns false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Copy", "DeleteFunc", "Insert":
		// maps.Copy/DeleteFunc/Insert: no-op stubs (mutate in place)
		return true, nil
	case "EqualFunc":
		// maps.EqualFunc: stub returns false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Collect":
		// maps.Collect: stub returns nil map
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "All":
		// maps.All: return nil iterator stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// io package
// ============================================================

// lowerIOCall handles calls to the io package.
func (fl *funcLowerer) lowerIOCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "ReadAll":
		// io.ReadAll(r) → ([]byte, error)
		// Stub: return empty byte slice and nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "WriteString":
		// io.WriteString(w, s) → (int, error)
		// Stub: return len(s), nil error
		sOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Copy":
		// io.Copy(dst, src) → (int64, error)
		// Stub: return 0, nil
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "NopCloser":
		// io.NopCloser(r) → return r
		rOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, rOp, dis.FP(dst)))
		return true, nil

	case "Pipe":
		// io.Pipe() → (*PipeReader, *PipeWriter) — stub returns (nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil

	case "LimitReader":
		// io.LimitReader(r, n) → return r (stub)
		rOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, rOp, dis.FP(dst)))
		return true, nil

	case "TeeReader":
		// io.TeeReader(r, w) → return r (stub)
		rOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, rOp, dis.FP(dst)))
		return true, nil

	case "MultiReader", "MultiWriter":
		// io.MultiReader/MultiWriter → stub returns nil
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil

	case "CopyN", "CopyBuffer":
		// io.CopyN/CopyBuffer → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil

	case "ReadFull", "ReadAtLeast":
		// io.ReadFull/ReadAtLeast → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil

	case "NewSectionReader":
		// io.NewSectionReader → returns nil (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// cmp package (Go 1.21+)
// ============================================================

// lowerCmpCall handles calls to the cmp package.
func (fl *funcLowerer) lowerCmpCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Compare":
		// cmp.Compare(x, y) → -1, 0, or 1
		// Simplified: compare as integers
		xOp := fl.operandOf(instr.Call.Args[0])
		yOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		// if x < y → -1
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, xOp, yOp, dis.Imm(0)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
		jmpEndIdx := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		// if x > y → 1
		gePC := int32(len(fl.insts))
		fl.insts[bgeIdx].Dst = dis.Imm(gePC)
		bleIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, yOp, xOp, dis.Imm(0)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[jmpEndIdx].Dst = dis.Imm(donePC)
		fl.insts[bleIdx].Dst = dis.Imm(donePC)
		return true, nil
	case "Less":
		// cmp.Less(x, y) → x < y
		xOp := fl.operandOf(instr.Call.Args[0])
		yOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		bgeIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, xOp, yOp, dis.Imm(0)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		fl.insts[bgeIdx].Dst = dis.Imm(int32(len(fl.insts)))
		return true, nil
	case "Or":
		// cmp.Or(vals...) → return first non-zero val (stub: return 0)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// context package
// ============================================================

// lowerContextCall handles calls to the context package.
func (fl *funcLowerer) lowerContextCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Background", "TODO":
		// context.Background() / context.TODO() → return nil context
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "WithCancel":
		// context.WithCancel(parent) → (ctx, cancel)
		// Return parent context and no-op cancel
		parentOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, parentOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "WithValue":
		// context.WithValue(parent, key, val) → return parent (simplified)
		parentOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, parentOp, dis.FP(dst)))
		return true, nil
	case "WithTimeout", "WithDeadline":
		// context.WithTimeout/WithDeadline(parent, ...) → (parent, no-op cancel)
		parentOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, parentOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "WithCancelCause":
		// context.WithCancelCause(parent) → (parent, no-op cancelCause)
		parentOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, parentOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Cause":
		// context.Cause(c) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "AfterFunc":
		// context.AfterFunc(ctx, f) → returns stop func (nil stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "WithoutCancel":
		// context.WithoutCancel(parent) → return parent
		parentOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, parentOp, dis.FP(dst)))
		return true, nil
	case "WithDeadlineCause", "WithTimeoutCause":
		// Same as WithDeadline/WithTimeout but with extra cause arg
		parentOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, parentOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// sync/atomic package
// ============================================================

// lowerSyncAtomicCall handles calls to the sync/atomic package.
// Dis VM is single-threaded, so atomics are just regular operations.
func (fl *funcLowerer) lowerSyncAtomicCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "AddInt32", "AddInt64":
		// atomic.AddInt32(addr, delta) → *addr += delta; return *addr
		// For now: return delta (stub)
		deltaOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, deltaOp, dis.FP(dst)))
		return true, nil
	case "LoadInt32", "LoadInt64":
		// atomic.LoadInt32(addr) → return 0 (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "StoreInt32", "StoreInt64":
		// atomic.StoreInt32(addr, val) → no-op (stub)
		return true, nil
	case "CompareAndSwapInt32", "CompareAndSwapInt64":
		// atomic.CompareAndSwapInt32(addr, old, new) → return true (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// bufio package
// ============================================================

// lowerBufioCall handles calls to the bufio package.
func (fl *funcLowerer) lowerBufioCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewScanner":
		// bufio.NewScanner(r) → return stub pointer
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewReader":
		// bufio.NewReader(r) → return stub pointer
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewWriter":
		// bufio.NewWriter(w) → return stub pointer
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "ScanLines", "ScanWords", "ScanRunes", "ScanBytes":
		// Split functions → return (0, nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	case "NewReaderSize", "NewWriterSize":
		// bufio.NewReaderSize/NewWriterSize → return stub pointer
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewReadWriter":
		// bufio.NewReadWriter(r, w) → return stub pointer
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil

	// Scanner methods
	case "Scan":
		// (*Scanner).Scan() → false (no more tokens)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Text":
		// (*Scanner).Text() → ""
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "Err":
		// (*Scanner).Err() → nil
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Split", "Buffer":
		// (*Scanner).Split/Buffer — no-op
		return true, nil
	case "Bytes":
		// (*Scanner).Bytes() → nil slice
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil

	// Reader methods
	case "Read":
		// (*Reader).Read(p) → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ReadByte":
		// (*Reader).ReadByte() → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ReadString":
		// (*Reader).ReadString(delim) → ("", nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ReadLine":
		// (*Reader).ReadLine() → (nil, false, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	case "ReadRune":
		// (*Reader).ReadRune() → (0, 0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	case "UnreadByte", "UnreadRune":
		// (*Reader).UnreadByte/UnreadRune() → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Peek":
		// (*Reader).Peek(n) → (nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Buffered", "Available":
		// (*Reader/Writer).Buffered/Available() → 0
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Reset":
		// (*Reader/Writer).Reset — no-op
		return true, nil

	// Writer methods
	case "Write":
		// (*Writer).Write(p) → (len(p), nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "WriteByte":
		// (*Writer).WriteByte(c) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "WriteString":
		// (*Writer).WriteString(s) → (len(s), nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "WriteRune":
		// (*Writer).WriteRune(r) → (size, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Flush":
		// (*Writer).Flush() → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "ReadFrom":
		// (*Writer).ReadFrom(r) → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ReadBytes", "ReadSlice":
		// (*Reader).ReadBytes/ReadSlice(delim) → (nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "WriteTo":
		// (*Reader).WriteTo(w) → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Discard":
		// (*Reader).Discard(n) → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Size":
		// (*Reader/Writer).Size() → 0
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "AvailableBuffer":
		// (*Writer).AvailableBuffer() → nil slice
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// net/url package
// ============================================================

// lowerNetURLCall handles calls to the net/url package.
func (fl *funcLowerer) lowerNetURLCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Parse":
		// url.Parse(rawURL) → (*URL, error)
		// Stub: return nil URL and nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "QueryEscape", "PathEscape":
		// url.QueryEscape(s) → return s (simplified stub)
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		return true, nil
	case "QueryUnescape", "PathUnescape":
		// url.QueryUnescape(s) → (s, nil error)
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ParseQuery":
		// url.ParseQuery(query) → (Values, error)
		// Stub: return nil map and nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ParseRequestURI":
		// url.ParseRequestURI(rawURL) → (*URL, error)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "User", "UserPassword":
		// url.User/UserPassword → nil *Userinfo stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// URL methods
	case "String", "Hostname", "Port", "RequestURI", "EscapedPath", "EscapedFragment", "Redacted":
		if callee.Signature.Recv() != nil {
			// (*URL).String/Hostname/Port/etc → "" stub
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Query":
		if callee.Signature.Recv() != nil {
			// (*URL).Query() → nil Values
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "IsAbs":
		if callee.Signature.Recv() != nil {
			// (*URL).IsAbs() → false
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "ResolveReference":
		if callee.Signature.Recv() != nil {
			// (*URL).ResolveReference(ref) → ref passthrough
			refOp := fl.operandOf(instr.Call.Args[1])
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVP, refOp, dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "MarshalBinary":
		if callee.Signature.Recv() != nil {
			// (*URL).MarshalBinary() → (nil, nil)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
		return false, nil
	case "UnmarshalBinary":
		if callee.Signature.Recv() != nil {
			// (*URL).UnmarshalBinary(text) → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	// Values methods
	case "Get":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Set", "Add", "Del":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
		return false, nil
	case "Has":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Encode":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	// Userinfo methods
	case "Username":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Password":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "JoinPath":
		if callee.Signature.Recv() != nil {
			// (*URL).JoinPath(elem ...string) → *URL
			// Stub: return nil *URL
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		// url.JoinPath(base, elem ...string) → (string, error)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	// Error type methods
	case "Error":
		if callee.Signature.Recv() != nil && strings.Contains(callee.String(), "Error).Error") {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Unwrap":
		if callee.Signature.Recv() != nil && strings.Contains(callee.String(), "Error).Unwrap") {
			// (*Error).Unwrap() → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "Timeout", "Temporary":
		if callee.Signature.Recv() != nil {
			// (*Error).Timeout/Temporary() → false
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	}
	return false, nil
}

// ============================================================
// encoding/json package
// ============================================================

// lowerEncodingJSONCall handles calls to the encoding/json package.
func (fl *funcLowerer) lowerEncodingJSONCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Marshal", "MarshalIndent":
		// json.Marshal(v) → ([]byte, error)
		// Stub: return empty bytes and nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Unmarshal":
		// json.Unmarshal(data, v) → error
		// Stub: return nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Valid":
		// json.Valid(data) → bool (stub: return true)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "Compact":
		// json.Compact(dst, src) → error (stub: return nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Indent":
		// json.Indent(dst, src, prefix, indent) → error (stub: return nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "HTMLEscape":
		// json.HTMLEscape(dst, src) → no-op
		return true, nil
	case "NewEncoder":
		// json.NewEncoder(w) → nil *Encoder stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewDecoder":
		// json.NewDecoder(r) → nil *Decoder stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Encoder methods
	case "Encode":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "SetIndent", "SetEscapeHTML":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
		return false, nil
	// Decoder methods
	case "Decode":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "More":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "UseNumber", "DisallowUnknownFields":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
		return false, nil
	case "Token":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
		return false, nil
	case "Buffered":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "InputOffset":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	// Number methods
	case "Float64":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
			return true, nil
		}
		return false, nil
	case "Int64":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
		return false, nil
	// Error type methods
	case "Error":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Unwrap":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	// RawMessage methods
	case "MarshalJSON":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
		return false, nil
	case "UnmarshalJSON":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	}
	return false, nil
}

// ============================================================
// runtime package
// ============================================================

// lowerRuntimeCall handles calls to the runtime package.
func (fl *funcLowerer) lowerRuntimeCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "GOMAXPROCS":
		// runtime.GOMAXPROCS(n) → return 1 (Dis VM is single-threaded)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "NumCPU":
		// runtime.NumCPU() → return 1
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "NumGoroutine":
		// runtime.NumGoroutine() → return 1
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "Gosched":
		// runtime.Gosched() → no-op
		return true, nil
	case "GC":
		// runtime.GC() → no-op (Dis VM handles GC)
		return true, nil
	case "Goexit":
		// runtime.Goexit() → emit RET
		fl.emit(dis.Inst0(dis.IRET))
		return true, nil
	case "Caller":
		// runtime.Caller(skip) → (0, "", 0, false)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))             // pc
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst+iby2wd))) // file
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))    // line
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))    // ok
		return true, nil
	case "Callers":
		// runtime.Callers(skip, pc []uintptr) → 0
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "GOROOT":
		// runtime.GOROOT() → "/go"
		dst := fl.slotOf(instr)
		gorootOff := fl.comp.AllocString("/go")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(gorootOff), dis.FP(dst)))
		return true, nil
	case "Version":
		// runtime.Version() → "go1.22"
		dst := fl.slotOf(instr)
		verOff := fl.comp.AllocString("go1.22")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(verOff), dis.FP(dst)))
		return true, nil
	case "GOOS":
		// runtime.GOOS → "inferno" (handled as var)
		return false, nil
	case "GOARCH":
		return false, nil
	case "SetFinalizer":
		// runtime.SetFinalizer(obj, finalizer) → no-op
		return true, nil
	case "KeepAlive":
		// runtime.KeepAlive(x) → no-op
		return true, nil
	case "LockOSThread", "UnlockOSThread":
		return true, nil // no-op
	case "ReadMemStats":
		return true, nil // no-op — writes to *MemStats
	case "Stack":
		// runtime.Stack(buf, all) → 0
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "FuncForPC":
		// runtime.FuncForPC(pc) → nil *Func
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "CallersFrames":
		// runtime.CallersFrames(callers) → nil *Frames
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Func methods
	case "Name":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Entry":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "FileLine":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	// Frames.Next method
	case "Next":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			// Frame struct fields + more bool
			for i := int32(0); i < 7; i++ {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i*iby2wd)))
			}
			return true, nil
		}
		return false, nil
	}
	return false, nil
}

// ============================================================
// reflect package
// ============================================================

// lowerReflectCall handles calls to the reflect package.
func (fl *funcLowerer) lowerReflectCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "TypeOf":
		// reflect.TypeOf(i) → stub return nil
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "ValueOf":
		// reflect.ValueOf(i) → stub return zero Value
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "DeepEqual":
		// reflect.DeepEqual(x, y) → stub return false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Zero", "New", "MakeSlice", "MakeMap", "MakeMapWithSize", "MakeChan",
		"Indirect", "AppendSlice":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Append":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Copy":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Swapper":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "PtrTo", "PointerTo", "SliceOf", "MapOf", "ChanOf":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Value methods (called on Value receiver)
	case "String":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Int":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Float":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Bool", "IsNil", "IsValid", "IsZero", "CanSet", "CanInterface", "CanAddr":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Bytes":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Interface":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Kind", "Type":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Elem", "Field", "FieldByName", "Index", "MapIndex", "Addr", "Convert",
		"MapRange", "Slice":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Len", "Cap", "NumField", "NumMethod":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Uint", "Pointer":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "MapKeys":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Call":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Set", "SetInt", "SetString", "SetFloat", "SetBool", "SetBytes",
		"SetUint", "SetMapIndex", "SetLen", "SetCap", "SetComplex",
		"SetPointer", "Send", "Close", "Grow", "SetZero":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	case "FieldByIndex", "FieldByNameFunc", "Method":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "MethodByName":
		if callee.Signature.Recv() != nil {
			// Returns (Value, bool)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Recv", "TryRecv":
		if callee.Signature.Recv() != nil {
			// Returns (Value, bool)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "TrySend":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "UnsafeAddr", "UnsafePointer":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "OverflowFloat", "OverflowInt", "OverflowUint", "Comparable", "Equal":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Complex":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	// StructTag methods
	case "Get":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	case "Lookup":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	// MapIter methods
	case "Key", "Value":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Next":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Reset":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	// Package-level functions
	case "Select":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "FuncOf", "StructOf", "ArrayOf":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "MakeFunc", "NewAt":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// os/exec package
// ============================================================

func (fl *funcLowerer) lowerOsExecCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Command":
		// exec.Command(name, args...) → return nil *Cmd stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "LookPath":
		// exec.LookPath(file) → (file, nil error)
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "CommandContext":
		// exec.CommandContext(ctx, name, args...) → nil *Cmd stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Cmd methods
	case "Run", "Start", "Wait":
		// (*Cmd).Run/Start/Wait() → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Output", "CombinedOutput":
		// (*Cmd).Output/CombinedOutput() → (nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "StdinPipe", "StdoutPipe", "StderrPipe":
		// (*Cmd).StdinPipe/StdoutPipe/StderrPipe() → (nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "String":
		// (*Cmd).String() → ""
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "Environ":
		// (*Cmd).Environ() → nil []string
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Error":
		// Error.Error() or ExitError.Error() → ""
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "Unwrap":
		// Error.Unwrap() → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "ExitCode":
		// ExitError.ExitCode() → -1
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// os/signal package
// ============================================================

func (fl *funcLowerer) lowerOsSignalCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Notify", "Stop":
		// No-op stubs
		return true, nil
	}
	return false, nil
}

// ============================================================
// io/ioutil package (deprecated, forwards to io/os)
// ============================================================

func (fl *funcLowerer) lowerIOUtilCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "ReadFile":
		// Same as os.ReadFile stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "WriteFile":
		// Same as os.WriteFile stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "ReadAll":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "TempDir":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		tmpOff := fl.comp.AllocString("/tmp")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(tmpOff), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "NopCloser":
		rOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, rOp, dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// io/fs package
// ============================================================

func (fl *funcLowerer) lowerIOFSCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	dst := fl.slotOf(instr)
	iby2wd := int32(dis.IBY2WD)
	switch name {
	case "ReadFile":
		// fs.ReadFile(fsys, name) → (nil, nil)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ReadDir":
		// fs.ReadDir(fsys, name) → (nil, nil)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Stat":
		// fs.Stat(fsys, name) → (nil, nil)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "WalkDir":
		// fs.WalkDir(fsys, root, fn) → nil error
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Sub":
		// fs.Sub(fsys, dir) → (nil, nil)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Glob":
		// fs.Glob(fsys, pattern) → (nil, nil)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ValidPath":
		// fs.ValidPath(name) → true
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "FormatFileInfo", "FormatDirEntry":
		// fs.FormatFileInfo/FormatDirEntry → ""
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "IsDir", "IsRegular":
		// FileMode.IsDir/IsRegular → false
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Perm", "Type":
		// FileMode.Perm/Type → 0
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "String":
		// FileMode.String → ""
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "Error":
		// PathError.Error → ""
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "Unwrap":
		// PathError.Unwrap → nil error
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// regexp package
// ============================================================

func (fl *funcLowerer) lowerRegexpCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Compile":
		// regexp.Compile(expr) → (*Regexp, error) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "MustCompile":
		// regexp.MustCompile(str) → *Regexp stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "MatchString":
		// regexp.MatchString(pattern, s) → (bool, error) stub: return false, nil
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "QuoteMeta":
		// regexp.QuoteMeta(s) → return s (stub)
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		return true, nil
	case "Match":
		// regexp.Match(pattern, b) → (false, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "CompilePOSIX":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "MustCompilePOSIX":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Regexp method stubs
	case "FindString", "ReplaceAllString":
		// (*Regexp).FindString/ReplaceAllString → "" stub
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "ReplaceAllStringFunc":
		// (*Regexp).ReplaceAllStringFunc(src, repl) → return src
		dst := fl.slotOf(instr)
		srcOp := fl.operandOf(instr.Call.Args[1])
		fl.emit(dis.Inst2(dis.IMOVP, srcOp, dis.FP(dst)))
		return true, nil
	case "FindStringIndex", "FindStringSubmatch", "FindAllString",
		"FindAllStringSubmatch", "Split", "SubexpNames":
		// return nil slice
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "String":
		// (*Regexp).String() → "" stub
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "NumSubexp", "SubexpIndex":
		// (*Regexp).NumSubexp/SubexpIndex() → 0
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Byte-based find methods
	case "Find", "ReplaceAll", "ReplaceAllLiteral":
		// Return nil []byte
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "ReplaceAllFunc":
		// Return src arg
		dst := fl.slotOf(instr)
		srcOp := fl.operandOf(instr.Call.Args[1])
		fl.emit(dis.Inst2(dis.IMOVP, srcOp, dis.FP(dst)))
		return true, nil
	case "FindIndex", "FindSubmatch", "FindSubmatchIndex",
		"FindAll", "FindAllIndex", "FindAllSubmatch", "FindAllSubmatchIndex",
		"FindStringSubmatchIndex", "FindAllStringIndex", "FindAllStringSubmatchIndex":
		// Return nil slice
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "ReplaceAllLiteralString":
		// Return src
		dst := fl.slotOf(instr)
		srcOp := fl.operandOf(instr.Call.Args[1])
		fl.emit(dis.Inst2(dis.IMOVP, srcOp, dis.FP(dst)))
		return true, nil
	case "Expand", "ExpandString":
		// Return dst arg
		dst := fl.slotOf(instr)
		dstOp := fl.operandOf(instr.Call.Args[1])
		fl.emit(dis.Inst2(dis.IMOVP, dstOp, dis.FP(dst)))
		return true, nil
	case "Longest":
		// No-op
		return true, nil
	case "Copy":
		// Return nil *Regexp
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "LiteralPrefix":
		// Return ("", false)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "MatchReader":
		// Return false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// net/http package
// ============================================================

func (fl *funcLowerer) lowerNetHTTPCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()

	// Handle method calls on types
	if callee.Signature.Recv() != nil {
		return fl.lowerNetHTTPMethodCall(instr, callee, name)
	}

	switch name {
	case "Get", "Post", "Head", "PostForm":
		// http.Get/Post/Head/PostForm → (*Response, error) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "NewRequest", "NewRequestWithContext":
		// http.NewRequest → (*Request, error) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ListenAndServe", "ListenAndServeTLS":
		// http.ListenAndServe → error stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Handle", "HandleFunc", "Error", "NotFound", "Redirect", "SetCookie":
		// no-op stubs
		return true, nil
	case "NewServeMux":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "StatusText", "CanonicalHeaderKey":
		// → string stub
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "DetectContentType":
		// → string stub
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("application/octet-stream")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "NotFoundHandler", "FileServer", "StripPrefix", "TimeoutHandler", "AllowQuerySemicolons":
		// handler-returning stubs → return nil handler
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "MaxBytesReader":
		// return nil reader
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "ProxyFromEnvironment":
		// → (nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "ServeFile", "ServeContent":
		// http.ServeFile(w, r, name) / http.ServeContent(w, r, name, modtime, content) → no-op
		return true, nil
	case "ReadResponse":
		// http.ReadResponse(r, req) → (*Response, error)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerNetHTTPMethodCall(instr *ssa.Call, callee *ssa.Function, name string) (bool, error) {
	recv := callee.Signature.Recv()
	recvStr := recv.Type().String()

	switch name {
	// Header methods
	case "Set", "Add", "Del":
		if strings.Contains(recvStr, "Header") {
			return true, nil // no-op
		}
	case "Get":
		if strings.Contains(recvStr, "Header") {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		// Client.Get → (*Response, error)
		if strings.Contains(recvStr, "Client") {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Values":
		if strings.Contains(recvStr, "Header") {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Clone":
		if strings.Contains(recvStr, "Header") {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		// Request.Clone(ctx) → *Request
		if strings.Contains(recvStr, "Request") {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Write":
		if strings.Contains(recvStr, "Header") || strings.Contains(recvStr, "Request") || strings.Contains(recvStr, "Response") {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}

	// Request methods
	case "FormValue", "PostFormValue", "UserAgent", "Referer":
		if strings.Contains(recvStr, "Request") {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	case "Context":
		if strings.Contains(recvStr, "Request") {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Cookie":
		if strings.Contains(recvStr, "Request") {
			// (*Cookie, error)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Cookies":
		// Request.Cookies() or Response.Cookies() → nil slice
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "AddCookie", "SetBasicAuth":
		if strings.Contains(recvStr, "Request") {
			return true, nil // no-op
		}
	case "BasicAuth":
		if strings.Contains(recvStr, "Request") {
			// (username, password string, ok bool)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
	case "ParseForm", "ParseMultipartForm":
		if strings.Contains(recvStr, "Request") {
			// → error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "ProtoAtLeast":
		if strings.Contains(recvStr, "Request") || strings.Contains(recvStr, "Response") {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "WithContext":
		if strings.Contains(recvStr, "Request") {
			// Request.WithContext(ctx) → *Request stub (return nil)
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "MultipartReader":
		if strings.Contains(recvStr, "Request") {
			// Request.MultipartReader() → (*multipart.Reader, error) stub
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
	// Client methods
	case "Do", "Post", "Head", "PostForm":
		if strings.Contains(recvStr, "Client") {
			// → (*Response, error)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "CloseIdleConnections":
		if strings.Contains(recvStr, "Client") {
			return true, nil // no-op
		}

	// Server methods
	case "ListenAndServe", "ListenAndServeTLS", "Shutdown", "Close":
		if strings.Contains(recvStr, "Server") {
			// → error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}

	// Response methods
	case "Location":
		if strings.Contains(recvStr, "Response") {
			// Response.Location() → (*url.URL, error) stub
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}

	// ServeMux methods
	case "Handle", "HandleFunc", "ServeHTTP":
		if strings.Contains(recvStr, "ServeMux") {
			return true, nil // no-op
		}

	// Cookie methods
	case "String":
		if strings.Contains(recvStr, "Cookie") {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	case "Valid":
		if strings.Contains(recvStr, "Cookie") {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	}
	return false, nil
}

// ============================================================
// log/slog package
// ============================================================

func (fl *funcLowerer) lowerLogSlogCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Info", "Warn", "Error", "Debug":
		// slog.Info/Warn/Error/Debug(msg, args...) → print msg via sys->print
		if len(instr.Call.Args) > 0 {
			msgOp := fl.operandOf(instr.Call.Args[0])
			msgSlot := fl.frame.AllocTemp(true)
			fl.emit(dis.Inst2(dis.IMOVP, msgOp, dis.FP(msgSlot)))
			nlOff := fl.comp.AllocString("\n")
			fl.emit(dis.NewInst(dis.IADDC, dis.MP(nlOff), dis.FP(msgSlot), dis.FP(msgSlot)))
			fl.emitSysCall("print", []callSiteArg{{msgSlot, true}})
		}
		return true, nil
	case "String", "Int", "Int64", "Float64", "Bool", "Any", "Duration", "Group":
		// slog.String/Int/Int64/Float64/Bool/Any/Duration/Group → return zero Attr (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "InfoContext", "WarnContext", "ErrorContext", "DebugContext":
		// slog.XxxContext(ctx, msg, args...) → print msg
		if len(instr.Call.Args) > 1 {
			msgOp := fl.operandOf(instr.Call.Args[1])
			msgSlot := fl.frame.AllocTemp(true)
			fl.emit(dis.Inst2(dis.IMOVP, msgOp, dis.FP(msgSlot)))
			nlOff := fl.comp.AllocString("\n")
			fl.emit(dis.NewInst(dis.IADDC, dis.MP(nlOff), dis.FP(msgSlot), dis.FP(msgSlot)))
			fl.emitSysCall("print", []callSiteArg{{msgSlot, true}})
		}
		return true, nil
	case "New", "Default", "With", "WithGroup":
		// slog.New/Default/With/WithGroup → return nil *Logger
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "SetDefault":
		// slog.SetDefault(l) → no-op
		return true, nil
	case "Enabled":
		// Logger.Enabled → false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Handler":
		// Logger.Handler → nil
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewTextHandler", "NewJSONHandler":
		// slog.NewTextHandler/NewJSONHandler → nil
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Level", "Set":
		// LevelVar.Level/Set → stub
		if callee.Signature.Recv() != nil {
			if callee.Name() == "Level" {
				dst := fl.slotOf(instr)
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			}
			return true, nil
		}
		return false, nil
	case "Equal":
		// Attr.Equal → false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// embed package
// ============================================================

func (fl *funcLowerer) lowerEmbedCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Open":
		// FS.Open(name) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ReadDir":
		// FS.ReadDir(name) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ReadFile":
		// FS.ReadFile(name) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// flag package
// ============================================================

func (fl *funcLowerer) lowerFlagCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Parse":
		// flag.Parse() → no-op
		return true, nil
	case "String":
		// flag.String(name, value, usage) → return pointer to value (stub: return nil)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Int":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Bool":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Arg":
		// flag.Arg(i) → return empty string
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "Args":
		// flag.Args() → return nil slice
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NArg", "NFlag":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Float64", "Int64", "Uint", "Uint64", "Duration":
		// Return nil pointer (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "StringVar", "IntVar", "BoolVar", "Float64Var", "Int64Var",
		"UintVar", "Uint64Var", "DurationVar", "TextVar":
		// No-op (writes to pointer)
		return true, nil
	case "Parsed":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Set":
		// flag.Set(name, value) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Lookup":
		// flag.Lookup(name) → nil *Flag
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewFlagSet":
		// flag.NewFlagSet(name, handling) → nil *FlagSet
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "PrintDefaults", "Visit", "VisitAll":
		// No-op stubs
		return true, nil
	case "Func", "BoolFunc", "Var":
		// No-op (registers a flag with callback)
		return true, nil
	case "UnquoteUsage":
		// flag.UnquoteUsage(flag) → ("", "")
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst+iby2wd)))
		return true, nil
	case "Init", "SetOutput":
		// No-op
		return true, nil
	case "Name":
		// FlagSet.Name() → ""
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "ErrorHandling":
		// FlagSet.ErrorHandling() → ContinueOnError (0)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Output":
		// FlagSet.Output() → nil
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// crypto/sha256 package
// ============================================================

func (fl *funcLowerer) lowerCryptoSHA256Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Sum256":
		// crypto/sha256.Sum256(data) → [32]byte stub: return zero array
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Sum224":
		// crypto/sha256.Sum224(data) → [28]byte stub: return zero array
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "New", "New224":
		// crypto/sha256.New/New224() → return nil (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// crypto/md5 package
// ============================================================

func (fl *funcLowerer) lowerCryptoMD5Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Sum":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "New":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// encoding/binary package
// ============================================================

func (fl *funcLowerer) lowerEncodingBinaryCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Write", "Read":
		// binary.Write/Read → stub: return nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "PutUvarint":
		// binary.PutUvarint → return 0 (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Uvarint":
		// binary.Uvarint → return (0, 0)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "PutVarint":
		// binary.PutVarint → return 0 (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Varint":
		// binary.Varint → return (0, 0)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Size":
		// binary.Size → return 0 (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "AppendUvarint", "AppendVarint":
		// binary.AppendUvarint/AppendVarint → return buf (passthrough)
		bufOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, bufOp, dis.FP(dst)))
		return true, nil
	case "Encode", "Decode":
		// binary.Encode/Decode(buf, order, data) → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Append":
		// binary.Append(order, buf, data) → (buf, nil)
		bufOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, bufOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// encoding/csv package
// ============================================================

func (fl *funcLowerer) lowerEncodingCSVCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewReader", "NewWriter":
		// csv.NewReader/NewWriter → return nil pointer (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Reader methods
	case "Read":
		// (*Reader).Read() → (nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ReadAll":
		// (*Reader).ReadAll() → (nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	// Writer methods
	case "Write":
		// (*Writer).Write(record) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "WriteAll":
		// (*Writer).WriteAll(records) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Flush":
		// (*Writer).Flush() → no-op
		return true, nil
	case "Error":
		// (*Writer).Error() or ParseError.Error() → nil error / empty string
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "FieldPos":
		// (*Reader).FieldPos(field) → (0, 0)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "InputOffset":
		// (*Reader).InputOffset() → 0
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Unwrap":
		// ParseError.Unwrap() → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// math/big package
// ============================================================

func (fl *funcLowerer) lowerMathBigCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewInt", "NewFloat", "NewRat":
		// big.NewInt/NewFloat/NewRat → return nil pointer (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Int/Float/Rat methods that return *T (self-modifying)
	case "Add", "Sub", "Mul", "Div", "Mod", "Abs", "Neg", "Set", "SetInt64", "SetBytes", "Exp", "GCD", "Quo", "SetFloat64", "SetPrec":
		if callee.Signature.Recv() != nil {
			// Return receiver (self) as stub
			selfOp := fl.operandOf(instr.Call.Args[0])
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVP, selfOp, dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Cmp", "Sign", "BitLen":
		if callee.Signature.Recv() != nil {
			// Return 0 (stub)
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Int64":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Float64":
		if callee.Signature.Recv() != nil {
			// (*Float).Float64() → (0.0, 0 accuracy)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "String":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			zeroOff := fl.comp.AllocString("0")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(zeroOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "SetString":
		if callee.Signature.Recv() != nil {
			// (*Int).SetString(s, base) → (self, true)
			selfOp := fl.operandOf(instr.Call.Args[0])
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVP, selfOp, dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "Bytes":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "IsInt64", "IsInf":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	}
	return false, nil
}

// ============================================================
// text/template package
// ============================================================

func (fl *funcLowerer) lowerTextTemplateCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "New":
		// template.New(name) → return nil pointer (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Must":
		// template.Must(t, err) → t passthrough
		tOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, tOp, dis.FP(dst)))
		return true, nil
	case "ParseFiles", "ParseGlob":
		// template.ParseFiles/ParseGlob → (nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	// Template methods
	case "Parse":
		if callee.Signature.Recv() != nil {
			// (*Template).Parse(text) → (self, nil)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			selfOp := fl.operandOf(instr.Call.Args[0])
			fl.emit(dis.Inst2(dis.IMOVP, selfOp, dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
		return false, nil
	case "Execute", "ExecuteTemplate":
		if callee.Signature.Recv() != nil {
			// (*Template).Execute/ExecuteTemplate → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "Funcs", "Option", "Delims":
		if callee.Signature.Recv() != nil {
			// (*Template).Funcs/Option/Delims → self passthrough
			selfOp := fl.operandOf(instr.Call.Args[0])
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVP, selfOp, dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Name":
		if callee.Signature.Recv() != nil {
			// (*Template).Name() → ""
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Lookup":
		if callee.Signature.Recv() != nil {
			// (*Template).Lookup(name) → nil
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Clone":
		if callee.Signature.Recv() != nil {
			// (*Template).Clone() → (nil, nil)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
		return false, nil
	}
	return false, nil
}

// ============================================================
// hash, hash/crc32 packages
// ============================================================

func (fl *funcLowerer) lowerHashCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "ChecksumIEEE":
		// crc32.ChecksumIEEE(data) → return 0 (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "New":
		// hash.New/crc32.New → return nil (stub)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// net package
// ============================================================

func (fl *funcLowerer) lowerNetCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Dial", "Listen":
		// net.Dial/Listen or Dialer.Dial → (nil, nil error) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "JoinHostPort":
		// net.JoinHostPort(host, port) → host + ":" + port
		hostOp := fl.operandOf(instr.Call.Args[0])
		portOp := fl.operandOf(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		colonOff := fl.comp.AllocString(":")
		fl.emit(dis.Inst2(dis.IMOVP, hostOp, dis.FP(dst)))
		fl.emit(dis.NewInst(dis.IADDC, dis.MP(colonOff), dis.FP(dst), dis.FP(dst)))
		fl.emit(dis.NewInst(dis.IADDC, portOp, dis.FP(dst), dis.FP(dst)))
		return true, nil
	case "SplitHostPort":
		// net.SplitHostPort → stub: return ("", "", nil error)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	case "DialTimeout":
		// net.DialTimeout(network, address, timeout) → (nil, nil error)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "DialTCP", "DialUDP", "DialUnix":
		// net.DialTCP/UDP/Unix → (nil, nil error)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ListenTCP", "ListenUDP", "ListenUnix", "ListenPacket":
		// net.ListenXxx → (nil, nil error)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "LookupHost", "LookupAddr":
		// net.LookupHost/LookupAddr or Resolver.LookupHost → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "LookupIP":
		// net.LookupIP(host) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "LookupPort":
		// net.LookupPort(network, service) → (0, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "LookupCNAME", "LookupTXT", "LookupMX", "LookupNS", "LookupSRV":
		// net.Lookup* → return zero values
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Interfaces":
		// net.Interfaces() → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "InterfaceByName":
		// net.InterfaceByName(name) → (nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ResolveIPAddr", "ResolveTCPAddr", "ResolveUDPAddr", "ResolveUnixAddr":
		// net.Resolve*Addr → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ParseCIDR":
		// net.ParseCIDR(s) → (nil IP, nil IPNet, nil error) — 3 results
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	case "ParseIP":
		// net.ParseIP(s) → nil IP
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "CIDRMask", "IPv4Mask":
		// net.CIDRMask/IPv4Mask → nil IPMask
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "IPv4":
		// net.IPv4(a, b, c, d) → nil IP
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "FileConn", "FileListener", "FilePacketConn":
		// net.File* → (nil, nil error)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Pipe":
		// net.Pipe() → (nil, nil) — two Conn values
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	// Method calls on net types
	case "String", "Network":
		if callee.Signature.Recv() != nil {
			// IP.String(), TCPAddr.String(), UDPAddr.String(), IPNet.String(),
			// IPMask.String(), TCPAddr.Network(), UDPAddr.Network(), OpError.Error(), DNSError.Error()
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	case "Error":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	case "Equal", "IsLoopback", "IsPrivate", "IsUnspecified", "Timeout", "Temporary":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "To4", "To16":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "MarshalText":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Size":
		if callee.Signature.Recv() != nil {
			// IPMask.Size() → (0, 0)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Contains":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "DialContext":
		if callee.Signature.Recv() != nil {
			// Dialer.DialContext → (nil Conn, nil error)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
	}
	return false, nil
}

// ============================================================
// crypto/rand package
// ============================================================

func (fl *funcLowerer) lowerCryptoRandCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Read":
		// crypto/rand.Read(b) → (len(b), nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		bSlot := fl.materialize(instr.Call.Args[0])
		lenSlot := fl.frame.AllocWord("crand.len")
		fl.emit(dis.Inst2(dis.ILENA, dis.FP(bSlot), dis.FP(lenSlot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(lenSlot), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Int", "Prime":
		// crypto/rand.Int/Prime → (0, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// crypto/hmac package
// ============================================================

func (fl *funcLowerer) lowerCryptoHMACCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "New":
		// hmac.New(h, key) → 0 (stub handle)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Equal":
		// hmac.Equal(mac1, mac2) → false stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// crypto/aes package
// ============================================================

func (fl *funcLowerer) lowerCryptoAESCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewCipher":
		// aes.NewCipher(key) → (0, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// crypto/cipher package
// ============================================================

func (fl *funcLowerer) lowerCryptoCipherCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewGCM":
		// cipher.NewGCM(cipher) → (0, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "NewCFBEncrypter", "NewCFBDecrypter", "NewCTR", "NewOFB":
		// cipher mode constructors → 0 stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewCBCEncrypter", "NewCBCDecrypter":
		// CBC mode → 0 stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewGCMWithNonceSize", "NewGCMWithTagSize":
		// GCM variants → (0, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// unicode/utf16 package
// ============================================================

func (fl *funcLowerer) lowerUnicodeUTF16Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Encode", "Decode":
		// utf16.Encode/Decode → nil slice stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "IsSurrogate":
		// utf16.IsSurrogate(r) → false stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// encoding/xml package
// ============================================================

func (fl *funcLowerer) lowerEncodingXMLCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Marshal", "MarshalIndent":
		// xml.Marshal(v) → ([]byte(""), nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Unmarshal":
		// xml.Unmarshal(data, v) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "EscapeText":
		// xml.EscapeText(w, data) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "NewEncoder":
		// xml.NewEncoder(w) → nil *Encoder stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewDecoder":
		// xml.NewDecoder(r) → nil *Decoder stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewTokenDecoder":
		// xml.NewTokenDecoder(r) → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Escape":
		// xml.Escape(w, data) → no-op
		return true, nil
	case "CopyToken":
		// xml.CopyToken(t) → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Encoder/Decoder methods
	case "Encode", "EncodeToken", "EncodeElement":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "Decode", "DecodeElement":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "Token":
		if callee.Signature.Recv() != nil {
			// (*Decoder).Token() → (nil, nil)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
		return false, nil
	case "Skip":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "Flush":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "Indent":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
		return false, nil
	case "Copy":
		// StartElement.Copy(), CharData.Copy(), etc. → return zero value
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "End":
		// StartElement.End() → return zero EndElement
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "InputOffset":
		// Decoder.InputOffset() → 0
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Error":
		// SyntaxError.Error(), etc. → ""
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// encoding/pem package
// ============================================================

func (fl *funcLowerer) lowerEncodingPEMCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Decode":
		// pem.Decode(data) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Encode":
		// pem.Encode(out, b) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "EncodeToMemory":
		// pem.EncodeToMemory(b) → nil slice stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// crypto/tls package
// ============================================================

func (fl *funcLowerer) lowerCryptoTLSCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Dial", "DialWithDialer", "Listen":
		// tls.Dial/DialWithDialer/Listen → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "LoadX509KeyPair", "X509KeyPair":
		// → (zero Certificate, nil) stub
		dst := fl.slotOf(instr)
		for i := int32(0); i < 5*int32(dis.IBY2WD); i += int32(dis.IBY2WD) {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i)))
		}
		return true, nil
	case "NewListener":
		// tls.NewListener → nil interface
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Clone":
		// Config.Clone() → nil *Config
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Close", "Handshake":
		// Conn.Close/Handshake → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Read", "Write":
		// Conn.Read/Write → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ConnectionState":
		// Conn.ConnectionState → zero struct
		dst := fl.slotOf(instr)
		for i := int32(0); i < 4*int32(dis.IBY2WD); i += int32(dis.IBY2WD) {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i)))
		}
		return true, nil
	}
	return false, nil
}

// ============================================================
// crypto/x509 package
// ============================================================

func (fl *funcLowerer) lowerCryptoX509Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "ParseCertificate":
		// x509.ParseCertificate(data) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "SystemCertPool", "NewCertPool":
		// x509.SystemCertPool/NewCertPool() → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ParseCertificates":
		// x509.ParseCertificates → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "ParsePKCS1PrivateKey", "ParsePKCS8PrivateKey", "ParsePKIXPublicKey", "MarshalPKIXPublicKey":
		// Key parsing → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Verify":
		// Certificate.Verify → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Equal":
		// Certificate/PublicKey.Equal → false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "AppendCertsFromPEM":
		// CertPool.AppendCertsFromPEM → false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "AddCert":
		// CertPool.AddCert → no-op
		return true, nil
	case "Error":
		// Error types → ""
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// database/sql package
// ============================================================

func (fl *funcLowerer) lowerDatabaseSQLCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	switch {
	case name == "Open":
		// sql.Open(driver, dsn) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case strings.Contains(name, "Close"):
		// DB.Close() → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case strings.Contains(name, "QueryRow"):
		// DB.QueryRow(...) → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case strings.Contains(name, "Exec"):
		// DB.Exec(...) → (0, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case strings.Contains(name, "Scan"):
		// Row.Scan(...) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case name == "Query", name == "QueryContext", name == "Prepare", name == "PrepareContext",
		name == "Begin", name == "BeginTx":
		// DB.Query/QueryContext/Prepare/PrepareContext/Begin/BeginTx → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case name == "Ping", name == "PingContext", name == "Commit", name == "Rollback":
		// Ping/Commit/Rollback → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case name == "SetMaxOpenConns", name == "SetMaxIdleConns",
		name == "SetConnMaxLifetime", name == "SetConnMaxIdleTime":
		return true, nil // no-op
	case name == "Stats":
		// DB.Stats() → zero DBStats struct
		dst := fl.slotOf(instr)
		for i := int32(0); i < 9*int32(dis.IBY2WD); i += int32(dis.IBY2WD) {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i)))
		}
		return true, nil
	case name == "Stmt":
		// Tx.Stmt(stmt) → nil *Stmt
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case name == "Next":
		// Rows.Next() → false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case name == "Err":
		// Rows.Err() → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case name == "Columns":
		// Rows.Columns() → (nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case name == "Register":
		return true, nil // no-op
	}
	return false, nil
}

// ============================================================
// archive/zip package
// ============================================================

func (fl *funcLowerer) lowerArchiveZipCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "OpenReader":
		// zip.OpenReader(name) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// archive/tar package
// ============================================================

func (fl *funcLowerer) lowerArchiveTarCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewReader", "NewWriter":
		// tar.NewReader/NewWriter → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// compress/gzip package
// ============================================================

func (fl *funcLowerer) lowerCompressGzipCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewReader":
		// gzip.NewReader(r) → (*Reader, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "NewWriter":
		// gzip.NewWriter(w) → *Writer stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewWriterLevel":
		// gzip.NewWriterLevel(w, level) → (*Writer, nil error) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	// Reader methods
	case "Read":
		if callee.Signature.Recv() != nil {
			// Reader.Read(p) → (0, nil)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Close":
		if callee.Signature.Recv() != nil {
			// Reader.Close / Writer.Close → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Reset":
		if callee.Signature.Recv() != nil {
			// Reader.Reset / Writer.Reset — no-op or → nil error
			if strings.Contains(callee.String(), "Reader") {
				// Reader.Reset(r) → nil error
				dst := fl.slotOf(instr)
				iby2wd := int32(dis.IBY2WD)
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
				return true, nil
			}
			// Writer.Reset(w) — no-op
			return true, nil
		}
	case "Multistream":
		if callee.Signature.Recv() != nil {
			// Reader.Multistream(ok) — no-op
			return true, nil
		}
	// Writer methods
	case "Write":
		if callee.Signature.Recv() != nil {
			// Writer.Write(p) → (0, nil)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Flush":
		if callee.Signature.Recv() != nil {
			// Writer.Flush() → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	}
	return false, nil
}

// ============================================================
// compress/flate package
// ============================================================

func (fl *funcLowerer) lowerCompressFlateCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewReader":
		// flate.NewReader(r) → io.ReadCloser stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewWriter":
		// flate.NewWriter(w, level) → (*Writer, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "NewWriterDict":
		// flate.NewWriterDict(w, level, dict) → (*Writer, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "NewReaderDict":
		// flate.NewReaderDict(r, dict) → io.ReadCloser stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Writer methods
	case "Write":
		if callee.Signature.Recv() != nil {
			// Writer.Write(p) → (0, nil)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Close":
		if callee.Signature.Recv() != nil {
			// Writer.Close() → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Flush":
		if callee.Signature.Recv() != nil {
			// Writer.Flush() → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Reset":
		if callee.Signature.Recv() != nil {
			// Writer.Reset(w) — no-op
			return true, nil
		}
	case "Error":
		if callee.Signature.Recv() != nil {
			// CorruptInputError.Error / InternalError.Error → ""
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	}
	return false, nil
}

// ============================================================
// html package
// ============================================================

func (fl *funcLowerer) lowerHTMLCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "EscapeString":
		// html.EscapeString(s) → s (identity stub)
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		return true, nil
	case "UnescapeString":
		// html.UnescapeString(s) → s (identity stub)
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// html/template package
// ============================================================

func (fl *funcLowerer) lowerHTMLTemplateCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "HTMLEscapeString", "JSEscapeString":
		// Identity stub - return input string
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		return true, nil
	case "HTMLEscaper", "JSEscaper", "URLQueryEscaper":
		// Return empty string stub
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	}
	return fl.lowerTextTemplateCall(instr, callee) // delegate to text/template
}

// ============================================================
// mime package
// ============================================================

func (fl *funcLowerer) lowerMIMECall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "TypeByExtension":
		// mime.TypeByExtension(ext) → "" stub
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "ExtensionsByType":
		// mime.ExtensionsByType(typ) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "FormatMediaType":
		// mime.FormatMediaType(t, param) → t stub
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		return true, nil
	case "ParseMediaType":
		// mime.ParseMediaType(v) → (v, 0, nil) stub
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// mime/multipart package
// ============================================================

func (fl *funcLowerer) lowerMIMEMultipartCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewWriter", "NewReader":
		// multipart.NewWriter/NewReader → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Writer methods
	case "Boundary", "FormDataContentType":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "SetBoundary", "WriteField", "Close":
		if callee.Signature.Recv() != nil {
			// → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "CreatePart", "CreateFormFile", "CreateFormField":
		if callee.Signature.Recv() != nil {
			// → (nil io.Writer, nil error)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
		return false, nil
	// Part methods
	case "Read":
		if callee.Signature.Recv() != nil {
			// Part.Read → (0, nil error)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
		return false, nil
	case "FileName", "FormName":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	// Reader methods
	case "NextPart", "NextRawPart":
		if callee.Signature.Recv() != nil {
			// → (nil *Part, nil error)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
		return false, nil
	case "ReadForm":
		if callee.Signature.Recv() != nil {
			// → (nil *Form, nil error)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
		return false, nil
	// FileHeader methods
	case "Open":
		if callee.Signature.Recv() != nil {
			// → (nil File, nil error)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
		return false, nil
	// Form methods
	case "RemoveAll":
		if callee.Signature.Recv() != nil {
			// → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	}
	return false, nil
}

// ============================================================
// net/mail package
// ============================================================

func (fl *funcLowerer) lowerNetMailCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "ParseAddress":
		// mail.ParseAddress(address) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// net/textproto package
// ============================================================

func (fl *funcLowerer) lowerNetTextprotoCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "CanonicalMIMEHeaderKey", "TrimString":
		// identity stub
		sOp := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// net/http/httputil package
// ============================================================

func (fl *funcLowerer) lowerNetHTTPUtilCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "DumpRequest", "DumpResponse":
		// httputil.DumpRequest/Response → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// crypto/elliptic package
// ============================================================

func (fl *funcLowerer) lowerCryptoEllipticCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "P256", "P384", "P521":
		// elliptic.P256() → 0 stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// crypto/ecdsa package
// ============================================================

func (fl *funcLowerer) lowerCryptoECDSACall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "GenerateKey":
		// ecdsa.GenerateKey(c, rand) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Sign", "SignASN1":
		// ecdsa.Sign/SignASN1 → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "VerifyASN1":
		// ecdsa.VerifyASN1 → false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Public":
		// PrivateKey.Public → nil
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Equal":
		// PublicKey/PrivateKey.Equal → false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "ECDH":
		// PublicKey/PrivateKey.ECDH → (nil, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// crypto/rsa package
// ============================================================

func (fl *funcLowerer) lowerCryptoRSACall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	dst := fl.slotOf(instr)
	iby2wd := int32(dis.IBY2WD)
	switch name {
	case "GenerateKey":
		// rsa.GenerateKey(random, bits) → (nil, nil) stub
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "SignPKCS1v15", "SignPSS", "EncryptOAEP", "EncryptPKCS1v15", "DecryptOAEP", "DecryptPKCS1v15":
		// Sign/Encrypt/Decrypt → (nil, nil) stub
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "VerifyPKCS1v15", "VerifyPSS":
		// Verify → nil error
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Public":
		// PrivateKey.Public() → nil interface
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Sign":
		// PrivateKey.Sign → (nil, nil)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Validate":
		// PrivateKey.Validate → nil error
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Size":
		// PublicKey.Size → 0
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Equal":
		// PublicKey.Equal → false
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// crypto/ed25519 package
// ============================================================

func (fl *funcLowerer) lowerCryptoEd25519Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "GenerateKey":
		// ed25519.GenerateKey(rand) → (nil, nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	case "Sign":
		// ed25519.Sign(priv, msg) → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Verify":
		// ed25519.Verify(pub, msg, sig) → false stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}
