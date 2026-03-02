package compiler

import (
	"fmt"
	"go/constant"
	"go/token"
	"go/types"
	"sort"
	"strings"

	"github.com/NERVsystems/infernode/tools/godis/dis"
	"golang.org/x/tools/go/ssa"
)

// funcLowerer lowers a single SSA function to Dis instructions.
type funcLowerer struct {
	fn              *ssa.Function
	frame           *Frame
	comp            *Compiler  // parent compiler (for string allocation, etc.)
	insts           []dis.Inst
	valueMap        map[ssa.Value]int32 // SSA value → frame offset
	allocBase       map[ssa.Value]int32 // *ssa.Alloc → base frame offset of data
	blockPC         map[*ssa.BasicBlock]int32
	patches         []branchPatch // deferred branch target patches
	sysMPOff        int32         // offset of Sys module ref in MP
	sysUsed         map[string]int // function name → LDT index
	callTypeDescs   []dis.TypeDesc // type descriptors for call-site frames
	funcCallPatches []funcCallPatch // deferred patches for local function calls
	closurePtrSlot  int32           // frame offset of hidden closure pointer (for inner functions)
	deferStack      []ssa.CallCommon // LIFO stack of deferred calls
	hasRecover      bool             // true if a deferred closure calls recover()
	excSlotFP       int32            // frame pointer slot for exception data (pointer, for VM storage)
	handlers        []handlerInfo    // exception handler table entries
}

// handlerInfo records an exception handler for the current function.
type handlerInfo struct {
	eoff   int32 // frame offset for exception data
	pc1    int32 // start PC of protected range (function-local)
	pc2    int32 // end PC of protected range (exclusive, function-local)
	wildPC int32 // wildcard handler PC (function-local)
}

type branchPatch struct {
	instIdx int
	target  *ssa.BasicBlock
}

// funcCallPatch records an instruction that needs patching for a local function call.
const (
	patchIFRAME = iota // IFRAME src = callee's type descriptor ID
	patchICALL         // ICALL dst = callee's start PC
)

type funcCallPatch struct {
	instIdx   int
	callee    *ssa.Function
	patchKind int
}

func newFuncLowerer(fn *ssa.Function, comp *Compiler, sysMPOff int32, sysUsed map[string]int) *funcLowerer {
	return &funcLowerer{
		fn:        fn,
		frame:     NewFrame(),
		comp:      comp,
		valueMap:  make(map[ssa.Value]int32),
		allocBase: make(map[ssa.Value]int32),
		blockPC:   make(map[*ssa.BasicBlock]int32),
		sysMPOff:  sysMPOff,
		sysUsed:   sysUsed,
	}
}

// lowerResult contains the compilation output of a function.
type lowerResult struct {
	insts           []dis.Inst
	frame           *Frame
	callTypeDescs   []dis.TypeDesc  // extra type descriptors for call-site frames
	funcCallPatches []funcCallPatch // patches for local function calls
	handlers        []handlerInfo   // exception handler table entries
}

// lower compiles the function to Dis instructions.
func (fl *funcLowerer) lower() (*lowerResult, error) {
	if len(fl.fn.Blocks) == 0 {
		return nil, fmt.Errorf("function %s has no blocks", fl.fn.Name())
	}

	// Scan for recover() in deferred closures
	fl.scanForRecover()

	// Pre-allocate frame slots for all SSA values that need them
	fl.allocateSlots()

	// If this function has recover, allocate the exception frame slot
	if fl.hasRecover {
		fl.excSlotFP = fl.frame.AllocPointer("excdata")
	}

	// Emit preamble to load free vars from closure struct
	if len(fl.fn.FreeVars) > 0 {
		fl.emitFreeVarLoads()
	}

	// If this is main, emit go:embed initializations (before init funcs)
	if fl.fn.Name() == "main" && len(fl.comp.embedInits) > 0 {
		for _, ei := range fl.comp.embedInits {
			globalOff, ok := fl.comp.GlobalOffset(ei.globalName)
			if !ok {
				continue
			}
			strOff := fl.comp.AllocString(ei.content) // already allocated, returns existing offset
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(strOff), dis.MP(globalOff)))
		}
	}

	// If this is main, emit calls to user-defined init functions
	if fl.fn.Name() == "main" && len(fl.comp.initFuncs) > 0 {
		for _, initFn := range fl.comp.initFuncs {
			callFrame := fl.frame.AllocWord("init.frame")
			iframeIdx := len(fl.insts)
			fl.emit(dis.Inst2(dis.IFRAME, dis.Imm(0), dis.FP(callFrame)))
			icallIdx := len(fl.insts)
			fl.emit(dis.Inst2(dis.ICALL, dis.FP(callFrame), dis.Imm(0)))
			fl.funcCallPatches = append(fl.funcCallPatches,
				funcCallPatch{instIdx: iframeIdx, callee: initFn, patchKind: patchIFRAME},
				funcCallPatch{instIdx: icallIdx, callee: initFn, patchKind: patchICALL},
			)
		}
	}

	// Record body start PC (after preamble, before user code)
	bodyStartPC := int32(len(fl.insts))

	// First pass: emit instructions for each basic block
	for _, block := range fl.fn.Blocks {
		fl.blockPC[block] = int32(len(fl.insts))
		if err := fl.lowerBlock(block); err != nil {
			return nil, fmt.Errorf("block %s: %w", block.Comment, err)
		}
	}

	// If this function has recover, append the exception handler epilogue
	if fl.hasRecover {
		fl.emitExceptionHandler(bodyStartPC)
	}

	// Second pass: patch branch targets
	for _, p := range fl.patches {
		targetPC := fl.blockPC[p.target]
		inst := &fl.insts[p.instIdx]
		inst.Dst = dis.Imm(targetPC)
	}

	return &lowerResult{
		insts:           fl.insts,
		frame:           fl.frame,
		callTypeDescs:   fl.callTypeDescs,
		funcCallPatches: fl.funcCallPatches,
		handlers:        fl.handlers,
	}, nil
}

// scanForRecover checks if any deferred closure in this function calls recover().
func (fl *funcLowerer) scanForRecover() {
	for _, anon := range fl.fn.AnonFuncs {
		if anonHasRecover(anon) {
			fl.hasRecover = true
			return
		}
	}
}

// anonHasRecover checks if a function (closure) calls the recover() builtin.
func anonHasRecover(fn *ssa.Function) bool {
	for _, block := range fn.Blocks {
		for _, instr := range block.Instrs {
			call, ok := instr.(*ssa.Call)
			if !ok {
				continue
			}
			builtin, ok := call.Call.Value.(*ssa.Builtin)
			if ok && builtin.Name() == "recover" {
				return true
			}
		}
	}
	return false
}

// emitExceptionHandler appends exception handler code after the normal function body.
// Layout:
//
//	[handlerPC]   MOVW excSlotFP(fp) → excGlobal(mp)  // bridge exception
//	              ... deferred calls (LIFO) ...
//	              RET
//
// The handler table entry covers [bodyStartPC, handlerPC).
func (fl *funcLowerer) emitExceptionHandler(bodyStartPC int32) {
	handlerPC := int32(len(fl.insts))
	excGlobalMP := fl.comp.AllocExcGlobal()

	// Copy exception string from frame slot to module-data bridge
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(fl.excSlotFP), dis.MP(excGlobalMP)))

	// Emit deferred calls in LIFO order (same as normal RunDefers)
	for i := len(fl.deferStack) - 1; i >= 0; i-- {
		call := fl.deferStack[i]
		fl.emitDeferredCall(call) //nolint: ignore error for handler path
	}

	// Zero return values (Go returns zero values when recovering from panic)
	regretOff := int32(dis.REGRET * dis.IBY2WD)
	results := fl.fn.Signature.Results()
	retOff := int32(0)
	for i := 0; i < results.Len(); i++ {
		dt := GoTypeToDis(results.At(i).Type())
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FPInd(regretOff, retOff)))
		retOff += dt.Size
	}

	fl.emit(dis.Inst0(dis.IRET))

	// Record the handler table entry
	fl.handlers = append(fl.handlers, handlerInfo{
		eoff:   fl.excSlotFP,
		pc1:    bodyStartPC,
		pc2:    handlerPC, // exclusive: [pc1, pc2)
		wildPC: handlerPC,
	})
}

// allocateSlots pre-allocates frame slots for parameters and all SSA values.
func (fl *funcLowerer) allocateSlots() {
	// For the init function, reserve space for Inferno's command parameters:
	//   offset 64 (MaxTemp+0): ctxt (ref Draw->Context) - pointer
	//   offset 72 (MaxTemp+8): args (list of string) - pointer
	// These are set by the command launcher before calling init.
	if fl.fn.Name() == "main" {
		fl.frame.AllocPointer("ctxt") // offset 64
		fl.frame.AllocPointer("args") // offset 72
	}

	// Free variables (closures): allocate hidden closure pointer param BEFORE regular params
	// The caller stores the closure pointer at MaxTemp+0, then regular args follow.
	if len(fl.fn.FreeVars) > 0 {
		fl.closurePtrSlot = fl.frame.AllocPointer("$closure")
	}

	// Parameters (after closure pointer if present)
	for _, p := range fl.fn.Params {
		if _, ok := p.Type().Underlying().(*types.Interface); ok {
			// Interface parameter: 2 consecutive WORDs (tag + value)
			base := fl.frame.AllocWord(p.Name() + ".tag")
			fl.frame.AllocWord(p.Name() + ".val")
			fl.valueMap[p] = base
		} else if st, ok := p.Type().Underlying().(*types.Struct); ok {
			// Struct parameter: allocate consecutive slots for each field
			base := fl.allocStructFields(st, p.Name())
			fl.valueMap[p] = base
		} else {
			dt := GoTypeToDis(p.Type())
			if dt.IsPtr {
				fl.valueMap[p] = fl.frame.AllocPointer(p.Name())
			} else {
				fl.valueMap[p] = fl.frame.AllocWord(p.Name())
			}
		}
	}

	// Allocate slots for free variable values (loaded from closure struct at entry)
	if len(fl.fn.FreeVars) > 0 {
		for _, fv := range fl.fn.FreeVars {
			if _, ok := fv.Type().Underlying().(*types.Interface); ok {
				base := fl.frame.AllocWord(fv.Name() + ".tag")
				fl.frame.AllocWord(fv.Name() + ".val")
				fl.valueMap[fv] = base
			} else {
				dt := GoTypeToDis(fv.Type())
				if dt.IsPtr {
					fl.valueMap[fv] = fl.frame.AllocPointer(fv.Name())
				} else {
					fl.valueMap[fv] = fl.frame.AllocWord(fv.Name())
				}
			}
		}
	}

	// All instructions that produce values
	for _, block := range fl.fn.Blocks {
		for _, instr := range block.Instrs {
			if v, ok := instr.(ssa.Value); ok {
				if _, exists := fl.valueMap[v]; exists {
					continue
				}
				if v.Name() == "" {
					continue // instructions that don't produce named values
				}
				// Skip instructions that allocate their own slots:
				// - Alloc, FieldAddr: LEA produces stack/MP address, not heap pointer
				// - IndexAddr: interior pointer into array, not GC-traced
				switch instr.(type) {
				case *ssa.Alloc, *ssa.FieldAddr, *ssa.IndexAddr:
					continue
				}
				// Tuple values (multi-return) need consecutive slots per element
				if tup, ok := v.Type().(*types.Tuple); ok {
					fl.valueMap[v] = fl.allocTupleSlots(tup, v.Name())
				} else if _, ok := v.Type().Underlying().(*types.Interface); ok {
					// Interface values: 2 consecutive WORDs (tag + value)
					base := fl.frame.AllocWord(v.Name() + ".tag")
					fl.frame.AllocWord(v.Name() + ".val")
					fl.valueMap[v] = base
				} else if IsComplexType(v.Type()) {
					// Complex values: 2 consecutive float64 slots (real + imag)
					base := fl.frame.AllocWord(v.Name() + ".re")
					fl.frame.AllocWord(v.Name() + ".im")
					fl.valueMap[v] = base
				} else if st, ok := v.Type().Underlying().(*types.Struct); ok {
					// Struct values need consecutive slots for each field
					fl.valueMap[v] = fl.allocStructFields(st, v.Name())
				} else {
					dt := GoTypeToDis(v.Type())
					if dt.IsPtr {
						fl.valueMap[v] = fl.frame.AllocPointer(v.Name())
					} else {
						fl.valueMap[v] = fl.frame.AllocWord(v.Name())
					}
				}
			}
		}
	}
}

func (fl *funcLowerer) lowerBlock(block *ssa.BasicBlock) error {
	for _, instr := range block.Instrs {
		if err := fl.lowerInstr(instr); err != nil {
			return fmt.Errorf("instruction %v: %w", instr, err)
		}
	}
	return nil
}

func (fl *funcLowerer) lowerInstr(instr ssa.Instruction) error {
	switch instr := instr.(type) {
	case *ssa.Alloc:
		return fl.lowerAlloc(instr)
	case *ssa.BinOp:
		return fl.lowerBinOp(instr)
	case *ssa.UnOp:
		return fl.lowerUnOp(instr)
	case *ssa.Call:
		return fl.lowerCall(instr)
	case *ssa.Return:
		return fl.lowerReturn(instr)
	case *ssa.If:
		return fl.lowerIf(instr)
	case *ssa.Jump:
		return fl.lowerJump(instr)
	case *ssa.Phi:
		return fl.lowerPhi(instr)
	case *ssa.Store:
		return fl.lowerStore(instr)
	case *ssa.FieldAddr:
		return fl.lowerFieldAddr(instr)
	case *ssa.IndexAddr:
		return fl.lowerIndexAddr(instr)
	case *ssa.Extract:
		return fl.lowerExtract(instr)
	case *ssa.Slice:
		return fl.lowerSlice(instr)
	case *ssa.Go:
		return fl.lowerGo(instr)
	case *ssa.MakeChan:
		return fl.lowerMakeChan(instr)
	case *ssa.Send:
		return fl.lowerSend(instr)
	case *ssa.Select:
		return fl.lowerSelect(instr)
	case *ssa.MakeClosure:
		return fl.lowerMakeClosure(instr)
	case *ssa.MakeSlice:
		return fl.lowerMakeSlice(instr)
	case *ssa.MakeMap:
		return fl.lowerMakeMap(instr)
	case *ssa.MapUpdate:
		return fl.lowerMapUpdate(instr)
	case *ssa.Lookup:
		return fl.lowerLookup(instr)
	case *ssa.Index:
		return fl.lowerIndex(instr)
	case *ssa.Range:
		return fl.lowerRange(instr)
	case *ssa.Next:
		return fl.lowerNext(instr)
	case *ssa.Convert:
		return fl.lowerConvert(instr)
	case *ssa.ChangeType:
		return fl.lowerChangeType(instr)
	case *ssa.Defer:
		return fl.lowerDefer(instr)
	case *ssa.RunDefers:
		return fl.lowerRunDefers(instr)
	case *ssa.Panic:
		return fl.lowerPanic(instr)
	case *ssa.MakeInterface:
		return fl.lowerMakeInterface(instr)
	case *ssa.TypeAssert:
		return fl.lowerTypeAssert(instr)
	case *ssa.ChangeInterface:
		return fl.lowerChangeInterface(instr)
	case *ssa.Field:
		return fl.lowerField(instr)
	case *ssa.SliceToArrayPointer:
		return fl.lowerSliceToArrayPointer(instr)
	case *ssa.DebugRef:
		return nil // ignore debug info
	default:
		return fmt.Errorf("unsupported instruction: %T (%v)", instr, instr)
	}
}

func (fl *funcLowerer) lowerAlloc(instr *ssa.Alloc) error {
	if instr.Heap {
		elemType := instr.Type().(*types.Pointer).Elem()
		if _, ok := elemType.Underlying().(*types.Array); ok {
			return fl.lowerHeapArrayAlloc(instr)
		}
		return fl.lowerHeapAlloc(instr)
	}
	// Stack allocation: the SSA value is a pointer (*T).
	// We allocate frame slots for the pointed-to value(s) and use LEA
	// to make the pointer slot point to the base.
	// The pointer slot is NOT a GC pointer because it points to a stack frame,
	// not the heap. The GC manages stack frames separately.
	elemType := instr.Type().(*types.Pointer).Elem()

	var baseSlot int32
	if _, ok := elemType.Underlying().(*types.Interface); ok {
		// Interface: 2 consecutive WORDs (tag + value)
		baseSlot = fl.frame.AllocWord("alloc:" + instr.Name() + ".tag")
		fl.frame.AllocWord("alloc:" + instr.Name() + ".val")
	} else if st, ok := elemType.Underlying().(*types.Struct); ok {
		// Struct: allocate one slot per field
		baseSlot = fl.allocStructFields(st, instr.Name())
	} else if at, ok := elemType.Underlying().(*types.Array); ok {
		// Fixed-size array: allocate N consecutive element slots
		baseSlot = fl.allocArrayElements(at, instr.Name())
	} else {
		dt := GoTypeToDis(elemType)
		if dt.IsPtr {
			baseSlot = fl.frame.AllocPointer("alloc:" + instr.Name())
		} else {
			baseSlot = fl.frame.AllocWord("alloc:" + instr.Name())
		}
	}

	// Track the base offset for FieldAddr
	fl.allocBase[instr] = baseSlot

	// Allocate the pointer slot as non-pointer (stack address, not heap pointer)
	ptrSlot := fl.frame.AllocWord("ptr:" + instr.Name())
	fl.valueMap[instr] = ptrSlot
	fl.emit(dis.Inst2(dis.ILEA, dis.FP(baseSlot), dis.FP(ptrSlot)))
	return nil
}

// lowerHeapAlloc emits INEW to heap-allocate a value.
// The result is a GC-traced pointer slot (unlike stack alloc which uses AllocWord).
func (fl *funcLowerer) lowerHeapAlloc(instr *ssa.Alloc) error {
	elemType := instr.Type().(*types.Pointer).Elem()

	// Create a type descriptor for the heap object
	tdLocalIdx := fl.makeHeapTypeDesc(elemType)

	// Allocate a GC-traced pointer slot for the result (this IS a heap pointer)
	ptrSlot := fl.frame.AllocPointer("heap:" + instr.Name())
	fl.valueMap[instr] = ptrSlot

	// Emit INEW $tdLocalIdx, dst(fp)
	// The local index is patched by Phase 4 to a global TD ID
	fl.emit(dis.Inst2(dis.INEW, dis.Imm(int32(tdLocalIdx)), dis.FP(ptrSlot)))

	return nil
}

// lowerHeapArrayAlloc emits NEWA to create a Dis Array for a heap-allocated [N]T.
// This creates a proper Dis Array (with length header) instead of a raw heap object,
// so Slice can just copy the pointer and INDW works for indexing.
func (fl *funcLowerer) lowerHeapArrayAlloc(instr *ssa.Alloc) error {
	arrType := instr.Type().(*types.Pointer).Elem().Underlying().(*types.Array)
	elemType := arrType.Elem()
	n := int(arrType.Len())

	// Create element type descriptor for NEWA
	elemTDIdx := fl.makeHeapTypeDesc(elemType)

	// Result: GC-traced Dis Array pointer
	ptrSlot := fl.frame.AllocPointer("harr:" + instr.Name())
	fl.valueMap[instr] = ptrSlot

	// NEWA length, $elemTD, dst
	fl.emit(dis.NewInst(dis.INEWA, dis.Imm(int32(n)), dis.Imm(int32(elemTDIdx)), dis.FP(ptrSlot)))

	// Zero-init non-pointer elements. NEWA/initarray skips types with np==0,
	// leaving non-pointer elements (int, bool, float64) uninitialized.
	elemDT := GoTypeToDis(elemType)
	if !elemDT.IsPtr && n > 0 {
		if st, ok := elemType.Underlying().(*types.Struct); ok && elemDT.Size > int32(dis.IBY2WD) {
			fl.emitStructArrayZeroInit(ptrSlot, int32(n), st)
		} else {
			fl.emitArrayZeroInit(ptrSlot, int32(n))
		}
	}

	return nil
}

// lowerMakeSlice handles make([]T, len, cap) → NEWA with dynamic size.
func (fl *funcLowerer) lowerMakeSlice(instr *ssa.MakeSlice) error {
	sliceType := instr.Type().Underlying().(*types.Slice)
	elemType := sliceType.Elem()

	elemTDIdx := fl.makeHeapTypeDesc(elemType)

	ptrSlot := fl.frame.AllocPointer("mkslice:" + instr.Name())
	fl.valueMap[instr] = ptrSlot

	lenOp := fl.operandOf(instr.Len)
	lenSlot := fl.materialize(instr.Len)

	// NEWA length, $elemTD, dst
	fl.emit(dis.NewInst(dis.INEWA, lenOp, dis.Imm(int32(elemTDIdx)), dis.FP(ptrSlot)))

	// Zero-init non-pointer elements. NEWA/initarray skips types with np==0,
	// leaving non-pointer elements (int, bool, float64) uninitialized.
	elemDT := GoTypeToDis(elemType)
	if !elemDT.IsPtr {
		if st, ok := elemType.Underlying().(*types.Struct); ok && elemDT.Size > int32(dis.IBY2WD) {
			fl.emitStructArrayZeroInitDynamic(ptrSlot, lenSlot, st)
		} else {
			fl.emitArrayZeroInitDynamic(ptrSlot, lenSlot)
		}
	}

	return nil
}

// emitArrayZeroInit emits a loop to zero-initialize all elements of a WORD-element
// array with a known constant length. Used by lowerHeapArrayAlloc.
func (fl *funcLowerer) emitArrayZeroInit(arrSlot int32, n int32) {
	idx := fl.frame.AllocWord("zinit_i")
	addr := fl.frame.AllocWord("zinit_addr")

	// idx = 0
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(idx)))

	// loopPC: if idx >= n, jump to donePC
	loopPC := int32(len(fl.insts))
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(idx), dis.Imm(n), dis.Imm(0))) // patched below
	bgePatchIdx := len(fl.insts) - 1

	// addr = &arr[idx]
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(arrSlot), dis.FP(addr), dis.FP(idx)))

	// *addr = 0
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FPInd(addr, 0)))

	// idx++
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(idx), dis.FP(idx)))

	// jump back to loopPC
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// donePC: patch the branch
	donePC := int32(len(fl.insts))
	fl.insts[bgePatchIdx].Dst = dis.Imm(donePC)
}

// emitArrayZeroInitDynamic emits a loop to zero-initialize all elements of a
// WORD-element array with a runtime-determined length. Used by lowerMakeSlice.
func (fl *funcLowerer) emitArrayZeroInitDynamic(arrSlot int32, lenSlot int32) {
	idx := fl.frame.AllocWord("zinit_i")
	addr := fl.frame.AllocWord("zinit_addr")

	// idx = 0
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(idx)))

	// loopPC: if idx >= len, jump to donePC
	loopPC := int32(len(fl.insts))
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(idx), dis.FP(lenSlot), dis.Imm(0))) // patched below
	bgePatchIdx := len(fl.insts) - 1

	// addr = &arr[idx]
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(arrSlot), dis.FP(addr), dis.FP(idx)))

	// *addr = 0
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FPInd(addr, 0)))

	// idx++
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(idx), dis.FP(idx)))

	// jump back to loopPC
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// donePC: patch the branch
	donePC := int32(len(fl.insts))
	fl.insts[bgePatchIdx].Dst = dis.Imm(donePC)
}

// emitStructArrayZeroInit emits a loop to zero-initialize all fields of each
// struct element in an array with a known constant length. Uses INDX for
// multi-word element stride.
func (fl *funcLowerer) emitStructArrayZeroInit(arrSlot int32, n int32, st *types.Struct) {
	idx := fl.frame.AllocWord("zinit_i")
	addr := fl.frame.AllocWord("zinit_addr")

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(idx)))

	loopPC := int32(len(fl.insts))
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(idx), dis.Imm(n), dis.Imm(0)))
	bgePatchIdx := len(fl.insts) - 1

	// addr = &arr[idx] using INDX (element-size stride)
	fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(addr), dis.FP(idx)))

	// Zero each field
	fieldOff := int32(0)
	for i := 0; i < st.NumFields(); i++ {
		fdt := GoTypeToDis(st.Field(i).Type())
		if fdt.IsPtr {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FPInd(addr, fieldOff))) // H
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FPInd(addr, fieldOff)))
		}
		fieldOff += fdt.Size
	}

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(idx), dis.FP(idx)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	donePC := int32(len(fl.insts))
	fl.insts[bgePatchIdx].Dst = dis.Imm(donePC)
}

// emitStructArrayZeroInitDynamic emits a loop to zero-initialize all fields of
// each struct element in an array with a runtime-determined length.
func (fl *funcLowerer) emitStructArrayZeroInitDynamic(arrSlot int32, lenSlot int32, st *types.Struct) {
	idx := fl.frame.AllocWord("zinit_i")
	addr := fl.frame.AllocWord("zinit_addr")

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(idx)))

	loopPC := int32(len(fl.insts))
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(idx), dis.FP(lenSlot), dis.Imm(0)))
	bgePatchIdx := len(fl.insts) - 1

	// addr = &arr[idx] using INDX (element-size stride)
	fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(addr), dis.FP(idx)))

	// Zero each field
	fieldOff := int32(0)
	for i := 0; i < st.NumFields(); i++ {
		fdt := GoTypeToDis(st.Field(i).Type())
		if fdt.IsPtr {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FPInd(addr, fieldOff))) // H
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FPInd(addr, fieldOff)))
		}
		fieldOff += fdt.Size
	}

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(idx), dis.FP(idx)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	donePC := int32(len(fl.insts))
	fl.insts[bgePatchIdx].Dst = dis.Imm(donePC)
}

// makeHeapTypeDesc creates a type descriptor for a heap-allocated object.
// Unlike call-site TDs which include the MaxTemp frame header, heap TDs
// describe the raw object layout starting at offset 0.
func (fl *funcLowerer) makeHeapTypeDesc(elemType types.Type) int {
	var size int
	var ptrOffsets []int

	if st, ok := elemType.Underlying().(*types.Struct); ok {
		off := 0
		for i := 0; i < st.NumFields(); i++ {
			fdt := GoTypeToDis(st.Field(i).Type())
			if fdt.IsPtr {
				ptrOffsets = append(ptrOffsets, off)
			}
			off += int(fdt.Size)
		}
		size = off
	} else {
		// For byte/uint8, use 1-byte element size (not word-sized frame slot)
		size = DisElementSize(elemType)
		dt := GoTypeToDis(elemType)
		if dt.IsPtr {
			ptrOffsets = append(ptrOffsets, 0)
		}
	}

	// Only align to word boundary for word-sized or larger types
	if size > 1 && size%dis.IBY2WD != 0 {
		size = (size + dis.IBY2WD - 1) &^ (dis.IBY2WD - 1)
	}

	td := dis.NewTypeDesc(0, size) // ID assigned by Phase 4
	for _, off := range ptrOffsets {
		td.SetPointer(off)
	}

	fl.callTypeDescs = append(fl.callTypeDescs, td)
	return len(fl.callTypeDescs) - 1
}

// allocStructFields allocates consecutive frame slots for each struct field.
// Returns the base offset (first field's offset).
// For embedded structs, recursively allocates sub-fields so that the total
// size matches GoTypeToDis().Size and field offsets align with lowerFieldAddr.
func (fl *funcLowerer) allocStructFields(st *types.Struct, baseName string) int32 {
	if st.NumFields() == 0 {
		// Empty struct: allocate a dummy slot to get a valid frame offset.
		// Without this, baseSlot defaults to 0 which is REGLINK — writing to
		// offset 0 corrupts the return address and causes nil dereferences.
		return fl.frame.AllocWord(baseName + ".empty")
	}
	var baseSlot int32
	for i := 0; i < st.NumFields(); i++ {
		field := st.Field(i)
		fieldType := field.Type().Underlying()
		var slot int32

		switch ft := fieldType.(type) {
		case *types.Struct:
			// Embedded or nested struct: recursively allocate sub-fields
			slot = fl.allocStructFields(ft, baseName+"."+field.Name())
		case *types.Interface:
			// Interface field: 2 WORDs (tag + value)
			slot = fl.frame.AllocWord(baseName + "." + field.Name() + ".tag")
			fl.frame.AllocWord(baseName + "." + field.Name() + ".val")
		default:
			dt := GoTypeToDis(field.Type())
			if dt.IsPtr {
				slot = fl.frame.AllocPointer(baseName + "." + field.Name())
			} else {
				slot = fl.frame.AllocWord(baseName + "." + field.Name())
			}
		}
		if i == 0 {
			baseSlot = slot
		}
	}
	return baseSlot
}

// allocArrayElements allocates N consecutive frame slots for a fixed-size array.
// Returns the base offset (first element's offset).
func (fl *funcLowerer) allocArrayElements(at *types.Array, baseName string) int32 {
	elemDT := GoTypeToDis(at.Elem())
	n := int(at.Len())
	var baseSlot int32
	for i := 0; i < n; i++ {
		name := fmt.Sprintf("%s[%d]", baseName, i)
		var slot int32
		if elemDT.IsPtr {
			slot = fl.frame.AllocPointer(name)
		} else {
			slot = fl.frame.AllocWord(name)
		}
		if i == 0 {
			baseSlot = slot
		}
	}
	return baseSlot
}

// allocTupleSlots allocates consecutive frame slots for each element of a tuple
// (multi-return value). Returns the base offset (first element's offset).
func (fl *funcLowerer) allocTupleSlots(tup *types.Tuple, baseName string) int32 {
	var baseSlot int32
	for i := 0; i < tup.Len(); i++ {
		name := fmt.Sprintf("%s#%d", baseName, i)
		var slot int32
		if _, ok := tup.At(i).Type().Underlying().(*types.Interface); ok {
			// Interface element: 2 WORDs (tag + value)
			slot = fl.frame.AllocWord(name + ".tag")
			fl.frame.AllocWord(name + ".val")
		} else {
			dt := GoTypeToDis(tup.At(i).Type())
			if dt.IsPtr {
				slot = fl.frame.AllocPointer(name)
			} else {
				slot = fl.frame.AllocWord(name)
			}
		}
		if i == 0 {
			baseSlot = slot
		}
	}
	return baseSlot
}

func (fl *funcLowerer) lowerBinOp(instr *ssa.BinOp) error {
	// Complex arithmetic requires special multi-instruction sequences
	if IsComplexType(instr.X.Type()) {
		return fl.lowerComplexBinOp(instr)
	}

	dst := fl.slotOf(instr)
	src := fl.operandOf(instr.X)
	mid := fl.operandOf(instr.Y)

	t := instr.X.Type().Underlying()
	basic, _ := t.(*types.Basic)

	// Dis three-operand arithmetic: dst = mid OP src
	// For Go's X OP Y:
	//   Commutative ops (ADD, MUL, AND, OR, XOR): order doesn't matter
	//   Non-commutative ops (SUB, DIV, MOD, SHL, SHR): need mid=X, src=Y
	// We have src=operandOf(X), mid=operandOf(Y), so swap for non-commutative ops.
	switch instr.Op {
	case token.ADD:
		op := fl.arithOp(dis.IADDW, dis.IADDF, dis.IADDC, basic)
		if op == dis.IADDC {
			// String concatenation is non-commutative: dst = mid + src
			// We have src=X, mid=Y, want X+Y, so swap: mid=X, src=Y
			fl.emit(dis.NewInst(op, mid, src, dis.FP(dst)))
		} else {
			fl.emit(dis.NewInst(op, src, mid, dis.FP(dst)))
		}
	case token.SUB:
		fl.emit(dis.NewInst(fl.arithOp(dis.ISUBW, dis.ISUBF, 0, basic), mid, src, dis.FP(dst)))
	case token.MUL:
		fl.emit(dis.NewInst(fl.arithOp(dis.IMULW, dis.IMULF, 0, basic), src, mid, dis.FP(dst)))
	case token.QUO:
		op := fl.arithOp(dis.IDIVW, dis.IDIVF, 0, basic)
		if op == dis.IDIVW {
			fl.emitZeroDivCheck(mid) // ARM64 sdiv returns 0 on div-by-zero instead of trapping
		}
		fl.emit(dis.NewInst(op, mid, src, dis.FP(dst)))
	case token.REM:
		fl.emitZeroDivCheck(mid)
		fl.emit(dis.NewInst(dis.IMODW, mid, src, dis.FP(dst)))
	case token.AND:
		fl.emit(dis.NewInst(dis.IANDW, src, mid, dis.FP(dst)))
	case token.OR:
		fl.emit(dis.NewInst(dis.IORW, src, mid, dis.FP(dst)))
	case token.XOR:
		fl.emit(dis.NewInst(dis.IXORW, src, mid, dis.FP(dst)))
	case token.SHL:
		fl.emit(dis.NewInst(dis.ISHLW, mid, src, dis.FP(dst)))
	case token.SHR:
		fl.emit(dis.NewInst(dis.ISHRW, mid, src, dis.FP(dst)))
	case token.AND_NOT: // &^ (bit clear): x &^ y = x AND (NOT y)
		// NOT y: XOR y, $-1 → temp
		temp := fl.frame.AllocWord("andnot.tmp")
		fl.emit(dis.NewInst(dis.IXORW, dis.Imm(-1), mid, dis.FP(temp)))
		// AND x, temp → dst
		fl.emit(dis.NewInst(dis.IANDW, dis.FP(temp), src, dis.FP(dst)))

	// Comparisons: produce a boolean (0 or 1) in the destination
	case token.EQL, token.NEQ, token.LSS, token.LEQ, token.GTR, token.GEQ:
		return fl.lowerComparison(instr, basic, src, mid, dst)

	default:
		return fmt.Errorf("unsupported binary op: %v", instr.Op)
	}

	// Sub-word integer truncation: mask result to correct width
	fl.emitSubWordTruncate(dst, instr.Type())

	return nil
}

// lowerComplexBinOp handles arithmetic and comparison on complex numbers.
// Complex values are stored as 2 consecutive float64 slots: [real, imag].
//
// Addition:       (a+bi) + (c+di) = (a+c) + (b+d)i
// Subtraction:    (a+bi) - (c+di) = (a-c) + (b-d)i
// Multiplication: (a+bi) * (c+di) = (ac-bd) + (ad+bc)i
// Division:       (a+bi) / (c+di) = ((ac+bd) + (bc-ad)i) / (c²+d²)
// Equality:       (a+bi) == (c+di) iff a==c && b==d
func (fl *funcLowerer) lowerComplexBinOp(instr *ssa.BinOp) error {
	xSlot := fl.materialize(instr.X)
	ySlot := fl.materialize(instr.Y)
	iby2wd := int32(dis.IBY2WD)

	// Extract parts: a=X.re, b=X.im, c=Y.re, d=Y.im
	aSlot := xSlot
	bSlot := xSlot + iby2wd
	cSlot := ySlot
	dSlot := ySlot + iby2wd

	switch instr.Op {
	case token.ADD:
		// Result is complex: dst.re = a+c, dst.im = b+d
		dst := fl.slotOf(instr)
		fl.emit(dis.NewInst(dis.IADDF, dis.FP(aSlot), dis.FP(cSlot), dis.FP(dst)))
		fl.emit(dis.NewInst(dis.IADDF, dis.FP(bSlot), dis.FP(dSlot), dis.FP(dst+iby2wd)))
		return nil

	case token.SUB:
		// dst.re = a-c, dst.im = b-d (SUB: dst = mid OP src → dst = src - mid)
		dst := fl.slotOf(instr)
		fl.emit(dis.NewInst(dis.ISUBF, dis.FP(cSlot), dis.FP(aSlot), dis.FP(dst)))
		fl.emit(dis.NewInst(dis.ISUBF, dis.FP(dSlot), dis.FP(bSlot), dis.FP(dst+iby2wd)))
		return nil

	case token.MUL:
		// dst.re = ac - bd, dst.im = ad + bc
		dst := fl.slotOf(instr)
		ac := fl.frame.AllocWord("cmul.ac")
		bd := fl.frame.AllocWord("cmul.bd")
		ad := fl.frame.AllocWord("cmul.ad")
		bc := fl.frame.AllocWord("cmul.bc")
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(aSlot), dis.FP(cSlot), dis.FP(ac)))
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(bSlot), dis.FP(dSlot), dis.FP(bd)))
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(aSlot), dis.FP(dSlot), dis.FP(ad)))
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(bSlot), dis.FP(cSlot), dis.FP(bc)))
		fl.emit(dis.NewInst(dis.ISUBF, dis.FP(bd), dis.FP(ac), dis.FP(dst)))        // re = ac - bd
		fl.emit(dis.NewInst(dis.IADDF, dis.FP(ad), dis.FP(bc), dis.FP(dst+iby2wd))) // im = ad + bc
		return nil

	case token.QUO:
		// dst.re = (ac+bd)/(c²+d²), dst.im = (bc-ad)/(c²+d²)
		dst := fl.slotOf(instr)
		ac := fl.frame.AllocWord("cdiv.ac")
		bd := fl.frame.AllocWord("cdiv.bd")
		ad := fl.frame.AllocWord("cdiv.ad")
		bc := fl.frame.AllocWord("cdiv.bc")
		cc := fl.frame.AllocWord("cdiv.cc")
		dd := fl.frame.AllocWord("cdiv.dd")
		denom := fl.frame.AllocWord("cdiv.denom")
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(aSlot), dis.FP(cSlot), dis.FP(ac)))
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(bSlot), dis.FP(dSlot), dis.FP(bd)))
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(aSlot), dis.FP(dSlot), dis.FP(ad)))
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(bSlot), dis.FP(cSlot), dis.FP(bc)))
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(cSlot), dis.FP(cSlot), dis.FP(cc)))
		fl.emit(dis.NewInst(dis.IMULF, dis.FP(dSlot), dis.FP(dSlot), dis.FP(dd)))
		fl.emit(dis.NewInst(dis.IADDF, dis.FP(cc), dis.FP(dd), dis.FP(denom)))
		// numerator real = ac + bd
		numRe := fl.frame.AllocWord("cdiv.numre")
		fl.emit(dis.NewInst(dis.IADDF, dis.FP(ac), dis.FP(bd), dis.FP(numRe)))
		fl.emit(dis.NewInst(dis.IDIVF, dis.FP(denom), dis.FP(numRe), dis.FP(dst)))
		// numerator imag = bc - ad
		numIm := fl.frame.AllocWord("cdiv.numim")
		fl.emit(dis.NewInst(dis.ISUBF, dis.FP(ad), dis.FP(bc), dis.FP(numIm)))
		fl.emit(dis.NewInst(dis.IDIVF, dis.FP(denom), dis.FP(numIm), dis.FP(dst+iby2wd)))
		return nil

	case token.EQL:
		// Result is bool. (a==c) && (b==d)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst))) // default false
		// if a != c goto done
		doneIdx1 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEF, dis.FP(aSlot), dis.FP(cSlot), dis.Imm(0)))
		// if b != d goto done
		doneIdx2 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEF, dis.FP(bSlot), dis.FP(dSlot), dis.Imm(0)))
		// both match
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[doneIdx1].Dst = dis.Imm(donePC)
		fl.insts[doneIdx2].Dst = dis.Imm(donePC)
		return nil

	case token.NEQ:
		// Result is bool. (a!=c) || (b!=d)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst))) // default true
		// if a != c goto done (already true)
		doneIdx1 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEF, dis.FP(aSlot), dis.FP(cSlot), dis.Imm(0)))
		// if b != d goto done (already true)
		doneIdx2 := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEF, dis.FP(bSlot), dis.FP(dSlot), dis.Imm(0)))
		// both match → not equal is false
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		donePC := int32(len(fl.insts))
		fl.insts[doneIdx1].Dst = dis.Imm(donePC)
		fl.insts[doneIdx2].Dst = dis.Imm(donePC)
		return nil

	default:
		return fmt.Errorf("unsupported complex binary op: %v", instr.Op)
	}
}

func (fl *funcLowerer) lowerComparison(instr *ssa.BinOp, basic *types.Basic, src, mid dis.Operand, dst int32) error {
	// For unsigned 64-bit ordered comparisons (< <= > >=), Dis only has signed
	// branch opcodes. XOR both operands with 0x8000000000000000 (sign bit flip)
	// to transform unsigned ordering into signed ordering.
	// EQL/NEQ are sign-agnostic and don't need this.
	// Sub-word unsigned types (uint8/16/32) are already masked to N bits,
	// so they fit in the positive signed range — no special handling needed.
	needsUnsignedFlip := false
	if basic != nil && !isFloat(basic) && basic.Kind() != types.String {
		switch instr.Op {
		case token.LSS, token.LEQ, token.GTR, token.GEQ:
			switch basic.Kind() {
			case types.Uint, types.Uint64, types.Uintptr:
				needsUnsignedFlip = true
			}
		}
	}

	actualSrc := src
	actualMid := mid
	if needsUnsignedFlip {
		// Compute sign bit: MOVW $1, tmp; SHLW $63, tmp, tmp → 0x8000000000000000
		signSlot := fl.frame.AllocWord("ucmp.sign")
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(signSlot)))
		fl.emit(dis.NewInst(dis.ISHLW, dis.Imm(63), dis.FP(signSlot), dis.FP(signSlot)))
		// XOR each operand with sign bit to transform unsigned→signed ordering
		tmpSrc := fl.frame.AllocWord("ucmp.src")
		tmpMid := fl.frame.AllocWord("ucmp.mid")
		fl.emit(dis.NewInst(dis.IXORW, dis.FP(signSlot), src, dis.FP(tmpSrc)))
		fl.emit(dis.NewInst(dis.IXORW, dis.FP(signSlot), mid, dis.FP(tmpMid)))
		actualSrc = dis.FP(tmpSrc)
		actualMid = dis.FP(tmpMid)
	}

	// Emit: movw $1, dst; bXX src, mid, PC+3; movw $0, dst
	truePC := int32(len(fl.insts)) + 3 // after movw $1, branch, movw $0

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))

	branchOp := fl.compBranchOp(instr.Op, basic)
	fl.emit(dis.NewInst(branchOp, actualSrc, actualMid, dis.Imm(truePC)))

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))

	return nil
}

func (fl *funcLowerer) lowerUnOp(instr *ssa.UnOp) error {
	dst := fl.slotOf(instr)
	src := fl.operandOf(instr.X)

	switch instr.Op {
	case token.SUB: // negation
		t := instr.X.Type().Underlying()
		if basic, ok := t.(*types.Basic); ok && isFloat(basic) {
			fl.emit(dis.Inst2(dis.INEGF, src, dis.FP(dst)))
		} else {
			// Integer negation: 0 - x → subw x, $0, dst (Dis: dst = mid - src = 0 - x)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.NewInst(dis.ISUBW, src, dis.FP(dst), dis.FP(dst)))
			fl.emitSubWordTruncate(dst, instr.Type())
		}
	case token.NOT: // logical not
		// XOR with 1
		fl.emit(dis.Inst2(dis.IMOVW, src, dis.FP(dst)))
		fl.emit(dis.NewInst(dis.IXORW, dis.Imm(1), dis.FP(dst), dis.FP(dst)))
	case token.XOR: // bitwise complement
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
		fl.emit(dis.NewInst(dis.IXORW, src, dis.FP(dst), dis.FP(dst)))
		fl.emitSubWordTruncate(dst, instr.Type())
	case token.MUL: // pointer dereference *ptr
		addrOff := fl.slotOf(instr.X)
		// Check for interface dereference (2-word copy)
		if _, ok := instr.Type().Underlying().(*types.Interface); ok {
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(addrOff, 0), dis.FP(dst)))          // tag
			fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(addrOff, iby2wd), dis.FP(dst+iby2wd))) // value
		} else if st, ok := instr.Type().Underlying().(*types.Struct); ok {
		// Check for struct dereference (multi-word copy)
			fieldOff := int32(0)
			for i := 0; i < st.NumFields(); i++ {
				fdt := GoTypeToDis(st.Field(i).Type())
				if fdt.IsPtr {
					fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(addrOff, fieldOff), dis.FP(dst+fieldOff)))
				} else {
					fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(addrOff, fieldOff), dis.FP(dst+fieldOff)))
				}
				fieldOff += fdt.Size
			}
		} else if IsByteType(instr.Type()) {
			// Byte dereference: zero-extend byte to word via CVTBW
			fl.emit(dis.Inst2(dis.ICVTBW, dis.FPInd(addrOff, 0), dis.FP(dst)))
		} else {
			dt := GoTypeToDis(instr.Type())
			if dt.IsPtr {
				fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(addrOff, 0), dis.FP(dst)))
			} else {
				fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(addrOff, 0), dis.FP(dst)))
			}
		}
	case token.ARROW: // channel receive <-ch
		chanOff := fl.slotOf(instr.X)
		return fl.emitCloseAwareRecv(instr, chanOff, dst)
	default:
		return fmt.Errorf("unsupported unary op: %v", instr.Op)
	}
	return nil
}

func (fl *funcLowerer) lowerCall(instr *ssa.Call) error {
	call := instr.Call

	// Interface method invocation (s.Method())
	if call.IsInvoke() {
		return fl.lowerInvokeCall(instr)
	}

	// Check if this is a call to a built-in like println
	if builtin, ok := call.Value.(*ssa.Builtin); ok {
		return fl.lowerBuiltinCall(instr, builtin)
	}

	// Check if this is a call to a function
	if callee, ok := call.Value.(*ssa.Function); ok {
		// Check if it's from inferno/sys package → Sys module call
		if callee.Package() != nil && callee.Package().Pkg.Path() == "inferno/sys" {
			return fl.lowerSysModuleCall(instr, callee)
		}
		// Intercept stdlib calls that map to Dis instructions
		if callee.Package() != nil {
			pkgPath := callee.Package().Pkg.Path()
			if handled, err := fl.lowerStdlibCall(instr, callee, pkgPath); handled {
				return err
			}
		}
		return fl.lowerDirectCall(instr, callee)
	}

	// Indirect call (closure or function value)
	if _, ok := call.Value.Type().Underlying().(*types.Signature); ok {
		return fl.lowerClosureCall(instr)
	}

	return fmt.Errorf("unsupported call target: %T", call.Value)
}

func (fl *funcLowerer) lowerBuiltinCall(instr *ssa.Call, builtin *ssa.Builtin) error {
	switch builtin.Name() {
	case "println", "print":
		return fl.lowerPrintln(instr)
	case "len":
		return fl.lowerLen(instr)
	case "cap":
		return fl.lowerCap(instr)
	case "copy":
		return fl.lowerCopy(instr)
	case "close":
		return fl.lowerClose(instr)
	case "append":
		return fl.lowerAppend(instr)
	case "delete":
		return fl.lowerMapDelete(instr)
	case "recover":
		return fl.lowerRecover(instr)
	case "min":
		return fl.lowerMinMax(instr, true)
	case "max":
		return fl.lowerMinMax(instr, false)
	case "clear":
		return fl.lowerClear(instr)
	case "real":
		return fl.lowerReal(instr)
	case "imag":
		return fl.lowerImag(instr)
	case "complex":
		return fl.lowerComplex(instr)
	default:
		return fmt.Errorf("unsupported builtin: %s", builtin.Name())
	}
}

// lowerMinMax implements min(a, b, ...) and max(a, b, ...) builtins (Go 1.21+).
// For integers: conditional move via BLTW/BGTW.
// For floats: conditional move via BLTF/BGTF.
// For strings: conditional move via BLTC/BGTC.
func (fl *funcLowerer) lowerMinMax(instr *ssa.Call, isMin bool) error {
	args := instr.Call.Args
	if len(args) == 0 {
		return fmt.Errorf("min/max with no arguments")
	}

	resultType := instr.Type()
	dstSlot := fl.slotOf(instr)

	// Determine comparison opcode
	basic, _ := resultType.Underlying().(*types.Basic)
	var branchOp dis.Op
	var movOp dis.Op
	if basic != nil && isFloat(basic) {
		if isMin {
			branchOp = dis.IBLTF // branch if src < mid (src is better)
		} else {
			branchOp = dis.IBGTF
		}
		movOp = dis.IMOVF
	} else if basic != nil && basic.Kind() == types.String {
		if isMin {
			branchOp = dis.IBLTC
		} else {
			branchOp = dis.IBGTC
		}
		movOp = dis.IMOVP
	} else {
		if isMin {
			branchOp = dis.IBLTW
		} else {
			branchOp = dis.IBGTW
		}
		movOp = dis.IMOVW
	}

	// Start with first arg
	firstOp := fl.operandOf(args[0])
	fl.emit(dis.Inst2(movOp, firstOp, dis.FP(dstSlot)))

	// Compare with each subsequent arg
	for i := 1; i < len(args); i++ {
		argSlot := fl.materialize(args[i])
		// branchOp tests: if arg <|> current result, jump to update
		updatePC := int32(len(fl.insts)) + 2 // skip branch + JMP
		fl.emit(dis.NewInst(branchOp, dis.FP(argSlot), dis.FP(dstSlot), dis.Imm(updatePC)))
		// Not better — skip update
		jmpIdx := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		// Update result
		fl.emit(dis.Inst2(movOp, dis.FP(argSlot), dis.FP(dstSlot)))
		// Patch JMP to skip over the update
		fl.insts[jmpIdx].Dst = dis.Imm(int32(len(fl.insts)))
	}

	return nil
}

// lowerClear implements clear(m) for maps and clear(s) for slices (Go 1.21+).
func (fl *funcLowerer) lowerClear(instr *ssa.Call) error {
	arg := instr.Call.Args[0]
	argType := arg.Type().Underlying()

	switch argType.(type) {
	case *types.Map:
		// Clear map: set count to 0
		mapSlot := fl.slotOf(arg)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FPInd(mapSlot, 16)))
		return nil
	case *types.Slice:
		// Clear slice: zero all elements
		arrSlot := fl.materialize(arg)
		sliceType := argType.(*types.Slice)
		elemType := sliceType.Elem()
		elemDt := GoTypeToDis(elemType)

		lenSlot := fl.frame.AllocWord("clear.len")
		fl.emit(dis.Inst2(dis.ILENA, dis.FP(arrSlot), dis.FP(lenSlot)))

		idx := fl.frame.AllocWord("clear.idx")
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(idx)))

		// Loop: while idx < len
		loopPC := int32(len(fl.insts))
		doneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(idx), dis.FP(lenSlot), dis.Imm(0)))

		// Zero the element at idx
		tmpPtr := fl.frame.AllocWord("clear.ptr")
		if elemDt.Size <= int32(dis.IBY2WD) {
			fl.emit(dis.NewInst(dis.IINDW, dis.FP(arrSlot), dis.FP(tmpPtr), dis.FP(idx)))
			if elemDt.IsPtr {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FPInd(tmpPtr, 0))) // H
			} else {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FPInd(tmpPtr, 0)))
			}
		} else {
			// Multi-word element: zero each word
			fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(tmpPtr), dis.FP(idx)))
			for off := int32(0); off < elemDt.Size; off += int32(dis.IBY2WD) {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FPInd(tmpPtr, off)))
			}
		}

		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(idx), dis.FP(idx)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

		// Done
		fl.insts[doneIdx].Dst = dis.Imm(int32(len(fl.insts)))
		return nil
	default:
		return fmt.Errorf("clear: unsupported type %T", argType)
	}
}

// lowerReal extracts the real part from a complex value.
// real(z) → dst = z.re (first float64 of the 2-word complex slot)
func (fl *funcLowerer) lowerReal(instr *ssa.Call) error {
	arg := instr.Call.Args[0]
	srcSlot := fl.materialize(arg)
	dstSlot := fl.slotOf(instr)
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(srcSlot), dis.FP(dstSlot)))
	return nil
}

// lowerImag extracts the imaginary part from a complex value.
// imag(z) → dst = z.im (second float64 of the 2-word complex slot)
func (fl *funcLowerer) lowerImag(instr *ssa.Call) error {
	arg := instr.Call.Args[0]
	srcSlot := fl.materialize(arg)
	dstSlot := fl.slotOf(instr)
	iby2wd := int32(dis.IBY2WD)
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(srcSlot+iby2wd), dis.FP(dstSlot)))
	return nil
}

// lowerComplex constructs a complex value from real and imaginary parts.
// complex(re, im) → dst = {re, im}
func (fl *funcLowerer) lowerComplex(instr *ssa.Call) error {
	reArg := instr.Call.Args[0]
	imArg := instr.Call.Args[1]
	reSrc := fl.materialize(reArg)
	imSrc := fl.materialize(imArg)
	dstSlot := fl.slotOf(instr)
	iby2wd := int32(dis.IBY2WD)
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(reSrc), dis.FP(dstSlot)))
	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(imSrc), dis.FP(dstSlot+iby2wd)))
	return nil
}

// lowerRecover reads the exception bridge from module data and clears it.
// Returns a tagged interface: tag=0/value=0 for nil, or tag="string" tag/value=String* if caught.
func (fl *funcLowerer) lowerRecover(instr *ssa.Call) error {
	excMP := fl.comp.AllocExcGlobal()
	dst := fl.slotOf(instr) // interface slot: tag at dst, value at dst+8
	iby2wd := int32(dis.IBY2WD)

	// Read the exception string pointer from bridge
	tmpSlot := fl.frame.AllocWord("")
	fl.emit(dis.Inst2(dis.IMOVW, dis.MP(excMP), dis.FP(tmpSlot)))
	// Clear the bridge
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.MP(excMP)))

	// If exception is non-zero, set tag = string type tag, value = string ptr
	// If zero, set tag = 0, value = 0 (nil interface)
	stringTag := fl.comp.AllocTypeTag("string")

	// BEQW $0, tmpSlot, $nilPC → if tmpSlot == 0, skip to nil
	beqwIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(tmpSlot), dis.Imm(0)))

	// Non-nil: set tag and value
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(stringTag), dis.FP(dst)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(tmpSlot), dis.FP(dst+iby2wd)))
	jmpIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// Nil: tag=0, value=0
	nilPC := int32(len(fl.insts))
	fl.insts[beqwIdx].Dst = dis.Imm(nilPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))

	donePC := int32(len(fl.insts))
	fl.insts[jmpIdx].Dst = dis.Imm(donePC)

	return nil
}

// lowerStdlibCall intercepts calls to Go stdlib packages and lowers them
// to Dis instructions. Returns (true, err) if handled, (false, nil) if not.
func (fl *funcLowerer) lowerStdlibCall(instr *ssa.Call, callee *ssa.Function, pkgPath string) (bool, error) {
	switch pkgPath {
	case "strconv":
		return fl.lowerStrconvCall(instr, callee)
	case "fmt":
		return fl.lowerFmtCall(instr, callee)
	case "errors":
		return fl.lowerErrorsCall(instr, callee)
	case "strings":
		return fl.lowerStringsCall(instr, callee)
	case "math":
		return fl.lowerMathCall(instr, callee)
	case "os":
		return fl.lowerOsCall(instr, callee)
	case "time":
		return fl.lowerTimeCall(instr, callee)
	case "sync":
		return fl.lowerSyncCall(instr, callee)
	case "sort":
		return fl.lowerSortCall(instr, callee)
	case "log":
		return fl.lowerLogCall(instr, callee)
	}
	return false, nil
}

func (fl *funcLowerer) lowerFmtCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Sprintf":
		return fl.lowerFmtSprintf(instr)
	case "Println":
		// fmt.Println(args...) → emit println-style output for each arg + newline
		// The SSA packs args into a []any slice. We trace back to find the original values.
		return fl.lowerFmtPrintln(instr)
	case "Printf":
		return fl.lowerFmtPrintf(instr)
	case "Errorf":
		return fl.lowerFmtErrorf(instr)
	}
	return false, nil
}

// lowerFmtPrintf handles fmt.Printf(format, args...) by formatting with Sprintf
// inline machinery, then printing the result via sys->print.
func (fl *funcLowerer) lowerFmtPrintf(instr *ssa.Call) (bool, error) {
	strSlot, ok := fl.emitSprintfInline(instr)
	if !ok {
		return false, nil
	}
	// Print the formatted string via sys->print
	fl.emitSysCall("print", []callSiteArg{{strSlot, true}})

	// Printf returns (int, error). Set return values if used.
	if len(*instr.Referrers()) > 0 {
		dstSlot := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		// n = len of string (approximate)
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(strSlot), dis.FP(dstSlot)))
		// error = nil
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot+2*iby2wd)))
	}
	return true, nil
}

// lowerFmtSprintf handles fmt.Sprintf by analyzing the format string and arguments.
// Parses the format string into literal segments and %verbs, emits inline Dis
// instructions to convert each arg and concatenate all pieces.
func (fl *funcLowerer) lowerFmtSprintf(instr *ssa.Call) (bool, error) {
	strSlot, ok := fl.emitSprintfInline(instr)
	if !ok {
		return false, nil
	}
	dstSlot := fl.slotOf(instr)
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(strSlot), dis.FP(dstSlot)))
	return true, nil
}

// lowerFmtErrorf handles fmt.Errorf(format, args...) by formatting the string
// with Sprintf-style logic, then wrapping it as a tagged error interface.
func (fl *funcLowerer) lowerFmtErrorf(instr *ssa.Call) (bool, error) {
	strSlot, ok := fl.emitSprintfInline(instr)
	if !ok {
		return false, nil
	}
	dst := fl.slotOf(instr)
	tag := fl.comp.AllocTypeTag("errorString")
	iby2wd := int32(dis.IBY2WD)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(tag), dis.FP(dst)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(strSlot), dis.FP(dst+iby2wd)))
	return true, nil
}

// emitSprintfInline emits the core Sprintf format-and-concatenate logic.
// Returns the frame slot containing the resulting string and true if successful,
// or (0, false) if the format string can't be handled.
func (fl *funcLowerer) emitSprintfInline(instr *ssa.Call) (int32, bool) {
	args := instr.Call.Args
	if len(args) < 1 {
		return 0, false
	}

	// Check if format string is a constant
	fmtConst, ok := args[0].(*ssa.Const)
	if !ok {
		return 0, false
	}
	fmtStr := constant.StringVal(fmtConst.Value)

	// Parse the format string into segments: literal strings and verb indices.
	// E.g., "hello %s, you are %d" → ["hello ", %s(0), ", you are ", %d(1)]
	type segment struct {
		literal string // non-empty for literal text
		verb    byte   // 's', 'd', 'v', 'c', 'x', 't', 'q', 'p', 'b', 'o', 'e' for a verb segment
		argIdx  int    // vararg index for verb segments
		width   int    // field width (0 = unset)
		prec    int    // precision (-1 = unset)
		padZero bool   // pad with zeros instead of spaces
	}
	var segments []segment
	argIdx := 0
	i := 0
	for i < len(fmtStr) {
		pct := strings.IndexByte(fmtStr[i:], '%')
		if pct < 0 {
			// Rest is literal
			segments = append(segments, segment{literal: fmtStr[i:]})
			break
		}
		if pct > 0 {
			segments = append(segments, segment{literal: fmtStr[i : i+pct]})
		}
		i += pct + 1
		if i >= len(fmtStr) {
			return 0, false // trailing %
		}
		// Parse optional flags, width, precision
		padZero := false
		if i < len(fmtStr) && fmtStr[i] == '0' {
			padZero = true
			i++
		}
		width := 0
		for i < len(fmtStr) && fmtStr[i] >= '0' && fmtStr[i] <= '9' {
			width = width*10 + int(fmtStr[i]-'0')
			i++
		}
		prec := -1
		if i < len(fmtStr) && fmtStr[i] == '.' {
			i++
			prec = 0
			for i < len(fmtStr) && fmtStr[i] >= '0' && fmtStr[i] <= '9' {
				prec = prec*10 + int(fmtStr[i]-'0')
				i++
			}
		}
		if i >= len(fmtStr) {
			return 0, false
		}
		verb := fmtStr[i]
		switch verb {
		case 's', 'd', 'v', 'c', 'x', 'f', 'g', 'w', 't', 'q', 'p', 'b', 'o', 'e':
			segments = append(segments, segment{verb: verb, argIdx: argIdx, width: width, prec: prec, padZero: padZero})
			argIdx++
			i++
		case '%':
			// %% → literal %
			segments = append(segments, segment{literal: "%"})
			i++
		default:
			return 0, false // unsupported verb
		}
	}

	if len(segments) == 0 {
		return 0, false
	}

	// Resolve each segment to a string slot.
	// Then concatenate them all with ADDC.
	var slotParts []dis.Operand
	for _, seg := range segments {
		if seg.literal != "" {
			// Allocate a constant string
			mp := fl.comp.AllocString(seg.literal)
			tmp := fl.frame.AllocTemp(true)
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(mp), dis.FP(tmp)))
			slotParts = append(slotParts, dis.FP(tmp))
		} else {
			// Verb: trace the vararg to get the original value
			var val ssa.Value
			if len(args) == 2 {
				val = fl.traceVarargElement(args[1], seg.argIdx)
			}
			if val == nil {
				return 0, false
			}
			var partSlot dis.Operand
			switch seg.verb {
			case 'd':
				src := fl.operandOf(val)
				tmp := fl.frame.AllocTemp(true)
				fl.emit(dis.Inst2(dis.ICVTWC, src, dis.FP(tmp)))
				partSlot = dis.FP(tmp)
			case 'v':
				// %v: type-aware formatting
				if isFloatType(val.Type().Underlying()) {
					src := fl.operandOf(val)
					tmp := fl.frame.AllocTemp(true)
					fl.emit(dis.Inst2(dis.ICVTFC, src, dis.FP(tmp)))
					partSlot = dis.FP(tmp)
				} else if basic, ok := val.Type().Underlying().(*types.Basic); ok && basic.Kind() == types.Bool {
					partSlot = fl.emitBoolToString(val)
				} else if isStringType(val.Type().Underlying()) {
					partSlot = fl.operandOf(val)
				} else {
					src := fl.operandOf(val)
					tmp := fl.frame.AllocTemp(true)
					fl.emit(dis.Inst2(dis.ICVTWC, src, dis.FP(tmp)))
					partSlot = dis.FP(tmp)
				}
			case 's':
				partSlot = fl.operandOf(val)
			case 'c':
				valOp := fl.operandOf(val)
				tmp := fl.frame.AllocTemp(true)
				fl.emit(dis.NewInst(dis.IINSC, valOp, dis.Imm(0), dis.FP(tmp)))
				partSlot = dis.FP(tmp)
			case 'f', 'g', 'e':
				src := fl.operandOf(val)
				tmp := fl.frame.AllocTemp(true)
				fl.emit(dis.Inst2(dis.ICVTFC, src, dis.FP(tmp)))
				partSlot = dis.FP(tmp)
			case 'x':
				valOp := fl.operandOf(val)
				hexStr := fl.emitHexConversion(valOp)
				partSlot = dis.FP(hexStr)
			case 'o':
				valOp := fl.operandOf(val)
				octStr := fl.emitBaseConversion(valOp, 8, "01234567")
				partSlot = dis.FP(octStr)
			case 'b':
				valOp := fl.operandOf(val)
				binStr := fl.emitBaseConversion(valOp, 2, "01")
				partSlot = dis.FP(binStr)
			case 't':
				partSlot = fl.emitBoolToString(val)
			case 'q':
				// quoted string: "\"" + s + "\""
				src := fl.operandOf(val)
				quoteMP := fl.comp.AllocString("\"")
				q1 := fl.frame.AllocTemp(true)
				fl.emit(dis.Inst2(dis.IMOVP, dis.MP(quoteMP), dis.FP(q1)))
				tmp1 := fl.frame.AllocTemp(true)
				fl.emit(dis.NewInst(dis.IADDC, src, dis.FP(q1), dis.FP(tmp1)))
				tmp2 := fl.frame.AllocTemp(true)
				fl.emit(dis.NewInst(dis.IADDC, dis.FP(q1), dis.FP(tmp1), dis.FP(tmp2)))
				partSlot = dis.FP(tmp2)
			case 'p':
				// pointer → "0x" + hex
				valOp := fl.operandOf(val)
				hexStr := fl.emitHexConversion(valOp)
				prefixMP := fl.comp.AllocString("0x")
				prefix := fl.frame.AllocTemp(true)
				fl.emit(dis.Inst2(dis.IMOVP, dis.MP(prefixMP), dis.FP(prefix)))
				result := fl.frame.AllocTemp(true)
				fl.emit(dis.NewInst(dis.IADDC, dis.FP(hexStr), dis.FP(prefix), dis.FP(result)))
				partSlot = dis.FP(result)
			case 'w':
				valSlot := fl.materialize(val)
				if _, ok := val.Type().Underlying().(*types.Interface); ok {
					tmp := fl.frame.AllocTemp(true)
					fl.emit(dis.Inst2(dis.IMOVW, dis.FP(valSlot+int32(dis.IBY2WD)), dis.FP(tmp)))
					partSlot = dis.FP(tmp)
				} else {
					partSlot = fl.operandOf(val)
				}
			}
			// Apply width padding if specified
			if seg.width > 0 {
				partSlot = fl.emitPadWidth(partSlot, seg.width, seg.padZero)
			}
			slotParts = append(slotParts, partSlot)
		}
	}

	if len(slotParts) == 1 {
		// Single segment — return the slot directly
		if slotParts[0].Mode == dis.AFP {
			return slotParts[0].Val, true
		}
		// Need to move to a temp slot
		tmp := fl.frame.AllocTemp(true)
		fl.emit(dis.Inst2(dis.IMOVP, slotParts[0], dis.FP(tmp)))
		return tmp, true
	}

	// Concatenate: fold left with ADDC
	// ADDC: dst = mid + src (Dis three-operand convention)
	acc := slotParts[0]
	for i := 1; i < len(slotParts); i++ {
		tmp := fl.frame.AllocTemp(true)
		fl.emit(dis.NewInst(dis.IADDC, slotParts[i], acc, dis.FP(tmp)))
		acc = dis.FP(tmp)
	}
	return acc.Val, true
}

// lowerFmtPrintln handles fmt.Println by tracing varargs to print each value.
func (fl *funcLowerer) lowerFmtPrintln(instr *ssa.Call) (bool, error) {
	args := instr.Call.Args
	if len(args) == 0 {
		// fmt.Println() → just print newline
		fl.emitSysPrint("\n")
		return true, nil
	}

	// The single arg is the varargs []any slice.
	// Trace back through the SSA to find individual elements.
	sliceVal := args[0]
	elements := fl.traceAllVarargElements(sliceVal)
	if elements == nil {
		return false, nil
	}

	for i, elem := range elements {
		if i > 0 {
			fl.emitSysPrint(" ")
		}
		if err := fl.emitPrintArg(elem); err != nil {
			return false, nil
		}
	}
	fl.emitSysPrint("\n")

	// If the result is used (fmt.Println returns (int, error)), set it
	if instr.Name() != "" {
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))          // int = 0
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))   // error.tag = 0
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd))) // error.val = 0
	}
	return true, nil
}

// lowerErrorsCall handles calls to the errors package.
func (fl *funcLowerer) lowerErrorsCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	if callee.Name() != "New" {
		return false, nil
	}
	return true, fl.lowerErrorsNew(instr)
}

// lowerErrorsNew lowers errors.New("msg") to a tagged error interface:
// tag = errorString tag, value = string.
func (fl *funcLowerer) lowerErrorsNew(instr *ssa.Call) error {
	textArg := instr.Call.Args[0]
	textOff := fl.materialize(textArg)
	dst := fl.slotOf(instr)
	tag := fl.comp.AllocTypeTag("errorString")
	iby2wd := int32(dis.IBY2WD)

	// Store tag
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(tag), dis.FP(dst)))
	// Store value (string) — use MOVW (interface value slot is WORD, not GC-traced)
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(textOff), dis.FP(dst+iby2wd)))
	return nil
}

// traceVarargElement traces back from a []any slice to find the original value
// of element at the given index. Returns nil if it can't be resolved.
func (fl *funcLowerer) traceVarargElement(sliceVal ssa.Value, idx int) ssa.Value {
	// The SSA sequence for varargs is:
	//   t0 = new [N]any (varargs)       ← Alloc
	//   t1 = &t0[idx]                   ← IndexAddr
	//   t2 = make any <- T (val)        ← MakeInterface
	//   *t1 = t2                        ← Store
	//   t3 = slice t0[:]                ← Slice
	//   call Sprintf(fmt, t3...)
	// We need to trace t3 → t0 → find the Store at index idx → find the MakeInterface value.

	// Step 1: trace Slice → Alloc
	slice, ok := sliceVal.(*ssa.Slice)
	if !ok {
		return nil
	}
	alloc, ok := slice.X.(*ssa.Alloc)
	if !ok {
		return nil
	}

	// Step 2: find Store instructions that write to indexed positions of alloc
	for _, ref := range *alloc.Referrers() {
		idxAddr, ok := ref.(*ssa.IndexAddr)
		if !ok {
			continue
		}
		// Check if this IndexAddr is for our target index
		idxConst, ok := idxAddr.Index.(*ssa.Const)
		if !ok {
			continue
		}
		if int(idxConst.Int64()) != idx {
			continue
		}
		// Find the Store to this IndexAddr
		for _, storeRef := range *idxAddr.Referrers() {
			store, ok := storeRef.(*ssa.Store)
			if !ok {
				continue
			}
			// The stored value should be a MakeInterface
			if mi, ok := store.Val.(*ssa.MakeInterface); ok {
				return mi.X // Return the original value before interface boxing
			}
			return store.Val
		}
	}
	return nil
}

// traceAllVarargElements traces all elements from a []any varargs slice.
func (fl *funcLowerer) traceAllVarargElements(sliceVal ssa.Value) []ssa.Value {
	slice, ok := sliceVal.(*ssa.Slice)
	if !ok {
		return nil
	}
	alloc, ok := slice.X.(*ssa.Alloc)
	if !ok {
		return nil
	}
	// Determine array size
	arrType, ok := alloc.Type().(*types.Pointer)
	if !ok {
		return nil
	}
	arr, ok := arrType.Elem().(*types.Array)
	if !ok {
		return nil
	}
	n := int(arr.Len())
	elements := make([]ssa.Value, n)
	for i := 0; i < n; i++ {
		elem := fl.traceVarargElement(sliceVal, i)
		if elem == nil {
			return nil
		}
		elements[i] = elem
	}
	return elements
}

func (fl *funcLowerer) lowerStrconvCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Itoa":
		// strconv.Itoa(x int) string → CVTWC src, dst
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.ICVTWC, src, dis.FP(dst)))
		return true, nil
	case "Atoi":
		// strconv.Atoi(s string) (int, error) → CVTCW src, dst
		// We only support the value; error is always nil.
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		// Tuple result: (int, error). int at dst, error interface at dst+8..dst+16.
		fl.emit(dis.Inst2(dis.ICVTCW, src, dis.FP(dst)))
		// Set error to nil interface (tag=0, val=0)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "FormatInt":
		// strconv.FormatInt(i int64, base int) string
		src := fl.operandOf(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		if baseConst, ok := instr.Call.Args[1].(*ssa.Const); ok {
			base, _ := constant.Int64Val(baseConst.Value)
			switch base {
			case 10:
				fl.emit(dis.Inst2(dis.ICVTWC, src, dis.FP(dst)))
				return true, nil
			case 16:
				hexStr := fl.emitHexConversion(src)
				fl.emit(dis.Inst2(dis.IMOVP, dis.FP(hexStr), dis.FP(dst)))
				return true, nil
			case 8:
				octStr := fl.emitBaseConversion(src, 8, "01234567")
				fl.emit(dis.Inst2(dis.IMOVP, dis.FP(octStr), dis.FP(dst)))
				return true, nil
			case 2:
				binStr := fl.emitBaseConversion(src, 2, "01")
				fl.emit(dis.Inst2(dis.IMOVP, dis.FP(binStr), dis.FP(dst)))
				return true, nil
			}
		}
		// Non-constant or unknown base: fall back to decimal
		fl.emit(dis.Inst2(dis.ICVTWC, src, dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// lowerStringsCall handles calls to the strings package.
func (fl *funcLowerer) lowerStringsCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Contains":
		return true, fl.lowerStringsContains(instr)
	case "HasPrefix":
		return true, fl.lowerStringsHasPrefix(instr)
	case "HasSuffix":
		return true, fl.lowerStringsHasSuffix(instr)
	case "Index":
		return true, fl.lowerStringsIndex(instr)
	case "TrimSpace":
		return true, fl.lowerStringsTrimSpace(instr)
	case "Split":
		return true, fl.lowerStringsSplit(instr)
	case "Join":
		return true, fl.lowerStringsJoin(instr)
	case "Replace":
		return true, fl.lowerStringsReplace(instr)
	case "ToUpper":
		return true, fl.lowerStringsToUpper(instr)
	case "ToLower":
		return true, fl.lowerStringsToLower(instr)
	case "Repeat":
		return true, fl.lowerStringsRepeat(instr)
	}
	return false, nil
}

// lowerStringsHasPrefix: LENC prefix; if lenP > lenS → false; SLICEC s,0,lenP → head; BEQC head,prefix → true
func (fl *funcLowerer) lowerStringsHasPrefix(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	prefOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenP := fl.frame.AllocWord("")
	head := fl.frame.AllocTemp(true)

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, prefOp, dis.FP(lenP)))

	// if lenP > lenS → false
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst))) // default false
	bgtIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenP), dis.FP(lenS), dis.Imm(0))) // placeholder

	// head = s[0:lenP]
	// SLICEC src, mid, dst: dst = dst[src:mid] (src=start, mid=end)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(head)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.Imm(0), dis.FP(lenP), dis.FP(head)))

	// BEQC head, prefix → true
	beqcIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, prefOp, dis.FP(head), dis.Imm(0))) // placeholder

	// Fall through = false (already set)
	jmpIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0))) // placeholder

	// true:
	truePC := int32(len(fl.insts))
	fl.insts[beqcIdx].Dst = dis.Imm(truePC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))

	// done:
	donePC := int32(len(fl.insts))
	fl.insts[bgtIdx].Dst = dis.Imm(donePC)
	fl.insts[jmpIdx].Dst = dis.Imm(donePC)

	return nil
}

// lowerStringsHasSuffix: LENC suffix; if lenSuf > lenS → false; tail = s[lenS-lenSuf:lenS]; BEQC tail,suffix → true
func (fl *funcLowerer) lowerStringsHasSuffix(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	sufOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenSuf := fl.frame.AllocWord("")
	startOff := fl.frame.AllocWord("")
	tail := fl.frame.AllocTemp(true)

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, sufOp, dis.FP(lenSuf)))

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst))) // default false

	// if lenSuf > lenS → done (false)
	bgtIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSuf), dis.FP(lenS), dis.Imm(0)))

	// startOff = lenS - lenSuf
	fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSuf), dis.FP(lenS), dis.FP(startOff)))

	// tail = s[startOff:lenS]
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(tail)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(startOff), dis.FP(lenS), dis.FP(tail)))

	// BEQC tail, suffix → true
	beqcIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, sufOp, dis.FP(tail), dis.Imm(0)))

	jmpIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	truePC := int32(len(fl.insts))
	fl.insts[beqcIdx].Dst = dis.Imm(truePC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[bgtIdx].Dst = dis.Imm(donePC)
	fl.insts[jmpIdx].Dst = dis.Imm(donePC)

	return nil
}

// lowerStringsContains: loop i from 0 to lenS-lenSub, SLICEC s[i:i+lenSub], BEQC == substr → true
func (fl *funcLowerer) lowerStringsContains(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	subOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenSub := fl.frame.AllocWord("")
	limit := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	endIdx := fl.frame.AllocWord("")
	candidate := fl.frame.AllocTemp(true)

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, subOp, dis.FP(lenSub)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst))) // default false

	// if lenSub == 0 → true (empty string is always contained)
	beqEmptyIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(lenSub), dis.Imm(0)))

	// if lenSub > lenS → false
	bgtIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSub), dis.FP(lenS), dis.Imm(0)))

	// limit = lenS - lenSub + 1
	fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSub), dis.FP(lenS), dis.FP(limit)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(limit), dis.FP(limit)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	// loop:
	loopPC := int32(len(fl.insts))
	bgeIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(limit), dis.Imm(0))) // i >= limit → done

	// endIdx = i + lenSub
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSub), dis.FP(i), dis.FP(endIdx)))

	// candidate = s[i:endIdx]
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(candidate)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))

	// BEQC candidate, substr → found
	beqcIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, subOp, dis.FP(candidate), dis.Imm(0)))

	// i++
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// found: (from BEQC or empty string)
	foundPC := int32(len(fl.insts))
	fl.insts[beqcIdx].Dst = dis.Imm(foundPC)
	fl.insts[beqEmptyIdx].Dst = dis.Imm(foundPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))

	// done:
	donePC := int32(len(fl.insts))
	fl.insts[bgtIdx].Dst = dis.Imm(donePC)
	fl.insts[bgeIdx].Dst = dis.Imm(donePC)

	return nil
}

// lowerStringsIndex: loop like Contains but returns index i or -1.
func (fl *funcLowerer) lowerStringsIndex(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	subOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenSub := fl.frame.AllocWord("")
	limit := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	endIdx := fl.frame.AllocWord("")
	candidate := fl.frame.AllocTemp(true)

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, subOp, dis.FP(lenSub)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst))) // default -1

	// if lenSub == 0 → return 0
	beqEmptyIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(lenSub), dis.Imm(0)))

	// if lenSub > lenS → done (-1)
	bgtIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSub), dis.FP(lenS), dis.Imm(0)))

	// limit = lenS - lenSub + 1
	fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSub), dis.FP(lenS), dis.FP(limit)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(limit), dis.FP(limit)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	// loop:
	loopPC := int32(len(fl.insts))
	bgeIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(limit), dis.Imm(0))) // i >= limit → done

	// endIdx = i + lenSub
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSub), dis.FP(i), dis.FP(endIdx)))

	// candidate = s[i:endIdx]
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(candidate)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))

	// BEQC candidate, substr → found at i
	beqcIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, subOp, dis.FP(candidate), dis.Imm(0)))

	// i++
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// found:
	foundPC := int32(len(fl.insts))
	fl.insts[beqcIdx].Dst = dis.Imm(foundPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(i), dis.FP(dst)))
	jmpDoneIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// empty string → return 0
	emptyPC := int32(len(fl.insts))
	fl.insts[beqEmptyIdx].Dst = dis.Imm(emptyPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))

	// done:
	donePC := int32(len(fl.insts))
	fl.insts[bgtIdx].Dst = dis.Imm(donePC)
	fl.insts[bgeIdx].Dst = dis.Imm(donePC)
	fl.insts[jmpDoneIdx].Dst = dis.Imm(donePC)

	return nil
}

// lowerStringsTrimSpace: skip leading/trailing whitespace, SLICEC result.
func (fl *funcLowerer) lowerStringsTrimSpace(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	start := fl.frame.AllocWord("")
	end := fl.frame.AllocWord("")
	ch := fl.frame.AllocWord("")
	tmp := fl.frame.AllocTemp(true)

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(start)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(lenS), dis.FP(end)))

	// Skip leading whitespace: while start < end && isSpace(s[start])
	leadLoopPC := int32(len(fl.insts))
	leadDoneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(start), dis.FP(end), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(start), dis.FP(ch)))
	// Check ' '(32), '\t'(9), '\n'(10), '\r'(13)
	beqSpc1 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(32), dis.FP(ch), dis.Imm(0)))
	beqTab1 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(9), dis.FP(ch), dis.Imm(0)))
	beqNl1 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(10), dis.FP(ch), dis.Imm(0)))
	beqCr1 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(13), dis.FP(ch), dis.Imm(0)))
	// Not whitespace → done leading
	jmpLeadDone := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
	// Is whitespace: start++, loop
	incPC := int32(len(fl.insts))
	fl.insts[beqSpc1].Dst = dis.Imm(incPC)
	fl.insts[beqTab1].Dst = dis.Imm(incPC)
	fl.insts[beqNl1].Dst = dis.Imm(incPC)
	fl.insts[beqCr1].Dst = dis.Imm(incPC)
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(start), dis.FP(start)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(leadLoopPC)))

	leadDonePC := int32(len(fl.insts))
	fl.insts[leadDoneIdx].Dst = dis.Imm(leadDonePC)
	fl.insts[jmpLeadDone].Dst = dis.Imm(leadDonePC)

	// Skip trailing whitespace: while end > start && isSpace(s[end-1])
	trailLoopPC := int32(len(fl.insts))
	trailDoneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(start), dis.FP(end), dis.Imm(0)))
	// ch = s[end-1]
	tailIdx := fl.frame.AllocWord("")
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(end), dis.FP(tailIdx)))
	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(tailIdx), dis.FP(ch)))
	beqSpc2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(32), dis.FP(ch), dis.Imm(0)))
	beqTab2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(9), dis.FP(ch), dis.Imm(0)))
	beqNl2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(10), dis.FP(ch), dis.Imm(0)))
	beqCr2 := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(13), dis.FP(ch), dis.Imm(0)))
	jmpTrailDone := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
	// Is whitespace: end--, loop
	decPC := int32(len(fl.insts))
	fl.insts[beqSpc2].Dst = dis.Imm(decPC)
	fl.insts[beqTab2].Dst = dis.Imm(decPC)
	fl.insts[beqNl2].Dst = dis.Imm(decPC)
	fl.insts[beqCr2].Dst = dis.Imm(decPC)
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(end), dis.FP(end)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(trailLoopPC)))

	trailDonePC := int32(len(fl.insts))
	fl.insts[trailDoneIdx].Dst = dis.Imm(trailDonePC)
	fl.insts[jmpTrailDone].Dst = dis.Imm(trailDonePC)

	// result = s[start:end]
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(tmp)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(start), dis.FP(end), dis.FP(tmp)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmp), dis.FP(dst)))

	return nil
}

// lowerStringsSplit: split s on sep, return []string.
// Pre-counts occurrences to allocate exact-size array, then fills it.
func (fl *funcLowerer) lowerStringsSplit(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	sepOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenSep := fl.frame.AllocWord("")
	count := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	endIdx := fl.frame.AllocWord("")
	candidate := fl.frame.AllocTemp(true)
	limit := fl.frame.AllocWord("")
	segStart := fl.frame.AllocWord("")
	arrIdx := fl.frame.AllocWord("")
	segment := fl.frame.AllocTemp(true)
	arrPtr := fl.frame.AllocPointer("split:arr")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, sepOp, dis.FP(lenSep)))

	// Count occurrences of sep in s
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(count))) // at least 1 segment
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	// limit = lenS - lenSep + 1 (or 0 if lenSep > lenS)
	bgtNoMatchIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenSep), dis.FP(lenS), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenSep), dis.FP(lenS), dis.FP(limit)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(limit), dis.FP(limit)))
	jmpCountLoop := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	noMatchPC := int32(len(fl.insts))
	fl.insts[bgtNoMatchIdx].Dst = dis.Imm(noMatchPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(limit)))

	// Count loop
	countLoopPC := int32(len(fl.insts))
	fl.insts[jmpCountLoop].Dst = dis.Imm(countLoopPC)
	bgeCountDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(limit), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSep), dis.FP(i), dis.FP(endIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(candidate)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))
	beqCountFound := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, sepOp, dis.FP(candidate), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(countLoopPC)))
	// Found: count++, skip sep
	countFoundPC := int32(len(fl.insts))
	fl.insts[beqCountFound].Dst = dis.Imm(countFoundPC)
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(count), dis.FP(count)))
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSep), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(countLoopPC)))

	countDonePC := int32(len(fl.insts))
	fl.insts[bgeCountDone].Dst = dis.Imm(countDonePC)

	// Allocate string array with 'count' elements
	elemTDIdx := fl.makeHeapTypeDesc(types.Typ[types.String])
	fl.emit(dis.NewInst(dis.INEWA, dis.FP(count), dis.Imm(int32(elemTDIdx)), dis.FP(arrPtr)))

	// Fill array: scan again, extract segments
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(segStart)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(arrIdx)))

	fillLoopPC := int32(len(fl.insts))
	bgeFillDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(limit), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSep), dis.FP(i), dis.FP(endIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(candidate)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))
	beqFillFound := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, sepOp, dis.FP(candidate), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(fillLoopPC)))
	// Found sep: extract s[segStart:i], store to arr[arrIdx]
	fillFoundPC := int32(len(fl.insts))
	fl.insts[beqFillFound].Dst = dis.Imm(fillFoundPC)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(segment)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(segStart), dis.FP(i), dis.FP(segment)))
	// INDW arr, arrIdx → indirect ptr store (actually use MOVP through indirect)
	// For string arrays: INDW gives address, then store through it
	storeAddr := fl.frame.AllocWord("")
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(arrPtr), dis.FP(storeAddr), dis.FP(arrIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(segment), dis.FPInd(storeAddr, 0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(arrIdx), dis.FP(arrIdx)))
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenSep), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(i), dis.FP(segStart)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(fillLoopPC)))

	fillDonePC := int32(len(fl.insts))
	fl.insts[bgeFillDone].Dst = dis.Imm(fillDonePC)
	// Last segment: s[segStart:lenS]
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(segment)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(segStart), dis.FP(lenS), dis.FP(segment)))
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(arrPtr), dis.FP(storeAddr), dis.FP(arrIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(segment), dis.FPInd(storeAddr, 0)))

	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(arrPtr), dis.FP(dst)))

	return nil
}

// lowerStringsJoin: concatenate elements of []string with sep between them.
func (fl *funcLowerer) lowerStringsJoin(instr *ssa.Call) error {
	elemsOp := fl.operandOf(instr.Call.Args[0])
	sepOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	lenArr := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	result := fl.frame.AllocTemp(true)
	elem := fl.frame.AllocTemp(true)
	elemAddr := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENA, elemsOp, dis.FP(lenArr)))

	// result = ""
	emptyOff := fl.comp.AllocString("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	// Loop: for i < lenArr
	loopPC := int32(len(fl.insts))
	bgeDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenArr), dis.Imm(0)))

	// If i > 0, append sep first
	beqSkipSep := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(i), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDC, sepOp, dis.FP(result), dis.FP(result)))
	skipSepPC := int32(len(fl.insts))
	fl.insts[beqSkipSep].Dst = dis.Imm(skipSepPC)

	// elem = elems[i]
	fl.emit(dis.NewInst(dis.IINDW, elemsOp, dis.FP(elemAddr), dis.FP(i)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(elemAddr, 0), dis.FP(elem)))
	fl.emit(dis.NewInst(dis.IADDC, dis.FP(elem), dis.FP(result), dis.FP(result)))

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	donePC := int32(len(fl.insts))
	fl.insts[bgeDone].Dst = dis.Imm(donePC)

	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(result), dis.FP(dst)))

	return nil
}

// lowerStringsReplace: replace occurrences of old with new in s (n=-1 for all).
func (fl *funcLowerer) lowerStringsReplace(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	oldOp := fl.operandOf(instr.Call.Args[1])
	newOp := fl.operandOf(instr.Call.Args[2])
	nOp := fl.operandOf(instr.Call.Args[3])

	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	lenOld := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	endIdx := fl.frame.AllocWord("")
	candidate := fl.frame.AllocTemp(true)
	result := fl.frame.AllocTemp(true)
	limit := fl.frame.AllocWord("")
	replaced := fl.frame.AllocWord("")
	nLimit := fl.frame.AllocWord("")
	ch := fl.frame.AllocTemp(true)

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	fl.emit(dis.Inst2(dis.ILENC, oldOp, dis.FP(lenOld)))
	emptyOff := fl.comp.AllocString("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(replaced)))
	fl.emit(dis.Inst2(dis.IMOVW, nOp, dis.FP(nLimit)))

	// limit = lenS - lenOld + 1
	bgtShort := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(lenOld), dis.FP(lenS), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.ISUBW, dis.FP(lenOld), dis.FP(lenS), dis.FP(limit)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(limit), dis.FP(limit)))
	jmpLoop := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	shortPC := int32(len(fl.insts))
	fl.insts[bgtShort].Dst = dis.Imm(shortPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(limit)))

	// Main loop
	loopPC := int32(len(fl.insts))
	fl.insts[jmpLoop].Dst = dis.Imm(loopPC)
	bgeDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(limit), dis.Imm(0)))

	// Check replacement count: if nLimit >= 0 && replaced >= nLimit, stop replacing
	bltNoLimit := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, dis.FP(nLimit), dis.Imm(0), dis.Imm(0))) // n<0 → unlimited
	bltStillOk := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, dis.FP(replaced), dis.FP(nLimit), dis.Imm(0)))
	// Exhausted n: append single char, advance
	jmpAppendChar := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	noLimitPC := int32(len(fl.insts))
	fl.insts[bltNoLimit].Dst = dis.Imm(noLimitPC)
	stillOkPC := int32(len(fl.insts))
	fl.insts[bltStillOk].Dst = dis.Imm(stillOkPC)

	// Check if s[i:i+lenOld] == old
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenOld), dis.FP(i), dis.FP(endIdx)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(candidate)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(endIdx), dis.FP(candidate)))
	beqMatch := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQC, oldOp, dis.FP(candidate), dis.Imm(0)))

	// No match: append s[i] as 1-char string
	appendCharPC := int32(len(fl.insts))
	fl.insts[jmpAppendChar].Dst = dis.Imm(appendCharPC)
	oneAfter := fl.frame.AllocWord("")
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(oneAfter)))
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(ch)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(oneAfter), dis.FP(ch)))
	fl.emit(dis.NewInst(dis.IADDC, dis.FP(ch), dis.FP(result), dis.FP(result)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// Match: append new, skip lenOld
	matchPC := int32(len(fl.insts))
	fl.insts[beqMatch].Dst = dis.Imm(matchPC)
	fl.emit(dis.NewInst(dis.IADDC, newOp, dis.FP(result), dis.FP(result)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(replaced), dis.FP(replaced)))
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(lenOld), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// Done: append remaining s[i:lenS]
	donePC := int32(len(fl.insts))
	fl.insts[bgeDone].Dst = dis.Imm(donePC)
	tail := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, sOp, dis.FP(tail)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(i), dis.FP(lenS), dis.FP(tail)))
	fl.emit(dis.NewInst(dis.IADDC, dis.FP(tail), dis.FP(result), dis.FP(result)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(result), dis.FP(dst)))

	return nil
}

// lowerStringsToUpper: loop over chars, if 'a'-'z' subtract 32.
func (fl *funcLowerer) lowerStringsToUpper(instr *ssa.Call) error {
	return fl.lowerStringsCaseConvert(instr, 97, 122, -32) // 'a'=97, 'z'=122
}

// lowerStringsToLower: loop over chars, if 'A'-'Z' add 32.
func (fl *funcLowerer) lowerStringsToLower(instr *ssa.Call) error {
	return fl.lowerStringsCaseConvert(instr, 65, 90, 32) // 'A'=65, 'Z'=90
}

// lowerStringsCaseConvert: generic case conversion loop.
// Converts chars in range [lo,hi] by adding delta to their code point.
func (fl *funcLowerer) lowerStringsCaseConvert(instr *ssa.Call, lo, hi, delta int32) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	lenS := fl.frame.AllocWord("")
	i := fl.frame.AllocWord("")
	ch := fl.frame.AllocWord("")
	result := fl.frame.AllocTemp(true)
	charStr := fl.frame.AllocTemp(true)
	iPlus1 := fl.frame.AllocWord("")

	fl.emit(dis.Inst2(dis.ILENC, sOp, dis.FP(lenS)))
	emptyOff := fl.comp.AllocString("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))

	loopPC := int32(len(fl.insts))
	bgeDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(lenS), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IINDC, sOp, dis.FP(i), dis.FP(ch)))

	// if ch < lo || ch > hi → no conversion
	bltSkip := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, dis.FP(ch), dis.Imm(lo), dis.Imm(0)))
	bgtSkip := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTW, dis.FP(ch), dis.Imm(hi), dis.Imm(0)))

	// Convert: ch += delta
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(delta), dis.FP(ch), dis.FP(ch)))

	skipPC := int32(len(fl.insts))
	fl.insts[bltSkip].Dst = dis.Imm(skipPC)
	fl.insts[bgtSkip].Dst = dis.Imm(skipPC)

	// Build 1-char string using INSC: insert ch into empty string
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(charStr)))
	fl.emit(dis.NewInst(dis.IINSC, dis.FP(ch), dis.Imm(0), dis.FP(charStr)))
	fl.emit(dis.NewInst(dis.IADDC, dis.FP(charStr), dis.FP(result), dis.FP(result)))

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	donePC := int32(len(fl.insts))
	fl.insts[bgeDone].Dst = dis.Imm(donePC)
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(result), dis.FP(dst)))

	_ = iPlus1
	return nil
}

// lowerStringsRepeat: concatenate s count times.
func (fl *funcLowerer) lowerStringsRepeat(instr *ssa.Call) error {
	sOp := fl.operandOf(instr.Call.Args[0])
	countOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	i := fl.frame.AllocWord("")
	countSlot := fl.frame.AllocWord("")
	result := fl.frame.AllocTemp(true)

	emptyOff := fl.comp.AllocString("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(i)))
	fl.emit(dis.Inst2(dis.IMOVW, countOp, dis.FP(countSlot)))

	loopPC := int32(len(fl.insts))
	bgeDone := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(i), dis.FP(countSlot), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IADDC, sOp, dis.FP(result), dis.FP(result)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(i), dis.FP(i)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	donePC := int32(len(fl.insts))
	fl.insts[bgeDone].Dst = dis.Imm(donePC)
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(result), dis.FP(dst)))

	return nil
}

// lowerMathCall handles calls to the math package.
func (fl *funcLowerer) lowerMathCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Abs":
		return true, fl.lowerMathAbs(instr)
	case "Sqrt":
		return true, fl.lowerMathSqrt(instr)
	case "Min":
		return true, fl.lowerMathMin(instr)
	case "Max":
		return true, fl.lowerMathMax(instr)
	}
	return false, nil
}

// lowerMathAbs: if src < 0.0, dst = -src; else dst = src
func (fl *funcLowerer) lowerMathAbs(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	// Allocate 0.0 in MP
	zeroOff := fl.comp.AllocReal(0.0)

	// dst = src (assume positive)
	fl.emit(dis.Inst2(dis.IMOVF, src, dis.FP(dst)))

	// if src >= 0.0, skip negation
	bgefIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEF, src, dis.MP(zeroOff), dis.Imm(0)))

	// src < 0: dst = -src
	fl.emit(dis.Inst2(dis.INEGF, src, dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[bgefIdx].Dst = dis.Imm(donePC)

	return nil
}

// lowerMathSqrt: Newton's method — g = x/2; iterate g = (g + x/g) / 2.
func (fl *funcLowerer) lowerMathSqrt(instr *ssa.Call) error {
	src := fl.operandOf(instr.Call.Args[0])
	dst := fl.slotOf(instr)

	g := fl.frame.AllocWord("")
	xg := fl.frame.AllocWord("")
	sum := fl.frame.AllocWord("")

	twoOff := fl.comp.AllocReal(2.0)

	// g = x / 2.0
	fl.emit(dis.NewInst(dis.IDIVF, dis.MP(twoOff), src, dis.FP(g)))

	// 15 iterations of Newton's method (unrolled)
	for iter := 0; iter < 15; iter++ {
		// xg = x / g
		fl.emit(dis.NewInst(dis.IDIVF, dis.FP(g), src, dis.FP(xg)))
		// sum = g + xg
		fl.emit(dis.NewInst(dis.IADDF, dis.FP(xg), dis.FP(g), dis.FP(sum)))
		// g = sum / 2.0
		fl.emit(dis.NewInst(dis.IDIVF, dis.MP(twoOff), dis.FP(sum), dis.FP(g)))
	}

	fl.emit(dis.Inst2(dis.IMOVF, dis.FP(g), dis.FP(dst)))
	return nil
}

// lowerMathMin: dst = min(x, y) for float64.
func (fl *funcLowerer) lowerMathMin(instr *ssa.Call) error {
	xOp := fl.operandOf(instr.Call.Args[0])
	yOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	fl.emit(dis.Inst2(dis.IMOVF, xOp, dis.FP(dst)))
	bltfIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTF, xOp, yOp, dis.Imm(0))) // if x < y → done (x is min)
	fl.emit(dis.Inst2(dis.IMOVF, yOp, dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[bltfIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerMathMax: dst = max(x, y) for float64.
func (fl *funcLowerer) lowerMathMax(instr *ssa.Call) error {
	xOp := fl.operandOf(instr.Call.Args[0])
	yOp := fl.operandOf(instr.Call.Args[1])
	dst := fl.slotOf(instr)

	fl.emit(dis.Inst2(dis.IMOVF, xOp, dis.FP(dst)))
	bgtfIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGTF, xOp, yOp, dis.Imm(0))) // if x > y → done (x is max)
	fl.emit(dis.Inst2(dis.IMOVF, yOp, dis.FP(dst)))

	donePC := int32(len(fl.insts))
	fl.insts[bgtfIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerOsCall handles calls to the os package.
func (fl *funcLowerer) lowerOsCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Exit":
		// os.Exit → emit RET (program terminates)
		fl.emit(dis.Inst0(dis.IRET))
		return true, nil
	}
	return false, nil
}

// lowerTimeCall handles calls to the time package.
// time.Now() → sys.millisec() stored as Time{msec}
// time.Sleep(d Duration) → sys.sleep(d / 1000000) (ns → ms)
// time.Since(t Time) → (now.msec - t.msec) * 1000000 (ms → ns Duration)
func (fl *funcLowerer) lowerTimeCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Now":
		// time.Now() → Time{msec: sys.millisec()}
		dstSlot := fl.slotOf(instr)
		// Call sys.millisec
		msSlot := fl.frame.AllocWord("time.ms")
		fl.emitSysCall("millisec", nil)
		// REGRET is at offset 32 in the callee frame — but emitSysCall
		// sets up ILEA to dstSlot. Actually we need to do this ourselves.
		// Just use sys.millisec directly through the module call mechanism.
		// Simpler: emit IMFRAME/IMCALL for millisec and read result.
		// Actually, emitSysCall doesn't return values to us easily.
		// Let's use the same pattern as lowerSysModuleCall but with a fixed dest.
		_ = msSlot
		// Register millisec in LDT
		disName := "millisec"
		ldtIdx, ok := fl.sysUsed[disName]
		if !ok {
			ldtIdx = len(fl.sysUsed)
			fl.sysUsed[disName] = ldtIdx
		}
		callFrame := fl.frame.AllocWord("")
		fl.emit(dis.NewInst(dis.IMFRAME, dis.MP(fl.sysMPOff), dis.Imm(int32(ldtIdx)), dis.FP(callFrame)))
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(dstSlot), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))
		fl.emit(dis.NewInst(dis.IMCALL, dis.FP(callFrame), dis.Imm(int32(ldtIdx)), dis.MP(fl.sysMPOff)))
		return true, nil

	case "Sleep":
		// time.Sleep(d Duration) → sys.sleep(d / 1000000)
		dSlot := fl.materialize(instr.Call.Args[0])
		msSlot := fl.frame.AllocWord("time.sleepms")
		fl.emit(dis.NewInst(dis.IDIVW, dis.Imm(1000000), dis.FP(dSlot), dis.FP(msSlot)))

		disName := "sleep"
		ldtIdx, ok := fl.sysUsed[disName]
		if !ok {
			ldtIdx = len(fl.sysUsed)
			fl.sysUsed[disName] = ldtIdx
		}
		callFrame := fl.frame.AllocWord("")
		fl.emit(dis.NewInst(dis.IMFRAME, dis.MP(fl.sysMPOff), dis.Imm(int32(ldtIdx)), dis.FP(callFrame)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(msSlot), dis.FPInd(callFrame, int32(dis.MaxTemp))))
		retSlot := fl.frame.AllocWord("time.sleepret")
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(retSlot), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))
		fl.emit(dis.NewInst(dis.IMCALL, dis.FP(callFrame), dis.Imm(int32(ldtIdx)), dis.MP(fl.sysMPOff)))
		return true, nil

	case "Since":
		// time.Since(t Time) → Duration = (now.msec - t.msec) * 1000000
		tSlot := fl.materialize(instr.Call.Args[0])
		dstSlot := fl.slotOf(instr)

		// Get current time via millisec
		nowSlot := fl.frame.AllocWord("time.now")
		disName := "millisec"
		ldtIdx, ok := fl.sysUsed[disName]
		if !ok {
			ldtIdx = len(fl.sysUsed)
			fl.sysUsed[disName] = ldtIdx
		}
		callFrame := fl.frame.AllocWord("")
		fl.emit(dis.NewInst(dis.IMFRAME, dis.MP(fl.sysMPOff), dis.Imm(int32(ldtIdx)), dis.FP(callFrame)))
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(nowSlot), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))
		fl.emit(dis.NewInst(dis.IMCALL, dis.FP(callFrame), dis.Imm(int32(ldtIdx)), dis.MP(fl.sysMPOff)))

		// elapsed_ms = now - t.msec
		fl.emit(dis.NewInst(dis.ISUBW, dis.FP(tSlot), dis.FP(nowSlot), dis.FP(dstSlot)))
		// Convert ms to ns: elapsed_ns = elapsed_ms * 1000000
		fl.emit(dis.NewInst(dis.IMULW, dis.Imm(1000000), dis.FP(dstSlot), dis.FP(dstSlot)))
		return true, nil

	case "After":
		// time.After(d Duration) <-chan Time
		// Create a channel, spawn a goroutine that sleeps then sends
		dSlot := fl.materialize(instr.Call.Args[0])
		dstSlot := fl.slotOf(instr)

		// Create channel: NEWC 0 (unbuffered), type=Time(1 word)
		fl.emit(dis.Inst2(dis.INEWCW, dis.Imm(0), dis.FP(dstSlot)))

		// We need a helper function for spawn. Since we can't easily spawn
		// inline, use a simpler approach: treat After as sleep + send on
		// the calling goroutine. This is semantically wrong (blocks caller)
		// but correct for the common pattern: <-time.After(d)
		// For now, just create the channel and schedule sleep+send inline.
		// Actually, After must return immediately. Let's use SPAWN.
		// The spawned function needs dSlot and dstSlot. Since we can't
		// create new functions at this point, emit the sleep+send inline
		// after the spawn point. Use a helper function approach:
		// For the MVP, implement as blocking (sleep then create+return).
		// This works for `<-time.After(d)` and `select { case <-time.After(d): }`.

		// Sleep
		msSlot := fl.frame.AllocWord("after.ms")
		fl.emit(dis.NewInst(dis.IDIVW, dis.Imm(1000000), dis.FP(dSlot), dis.FP(msSlot)))
		disName := "sleep"
		ldtIdx, ok := fl.sysUsed[disName]
		if !ok {
			ldtIdx = len(fl.sysUsed)
			fl.sysUsed[disName] = ldtIdx
		}
		callFrame := fl.frame.AllocWord("")
		fl.emit(dis.NewInst(dis.IMFRAME, dis.MP(fl.sysMPOff), dis.Imm(int32(ldtIdx)), dis.FP(callFrame)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(msSlot), dis.FPInd(callFrame, int32(dis.MaxTemp))))
		retSlot := fl.frame.AllocWord("after.ret")
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(retSlot), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))
		fl.emit(dis.NewInst(dis.IMCALL, dis.FP(callFrame), dis.Imm(int32(ldtIdx)), dis.MP(fl.sysMPOff)))

		// Send current time on channel
		nowSlot := fl.frame.AllocWord("after.now")
		disName2 := "millisec"
		ldtIdx2, ok2 := fl.sysUsed[disName2]
		if !ok2 {
			ldtIdx2 = len(fl.sysUsed)
			fl.sysUsed[disName2] = ldtIdx2
		}
		callFrame2 := fl.frame.AllocWord("")
		fl.emit(dis.NewInst(dis.IMFRAME, dis.MP(fl.sysMPOff), dis.Imm(int32(ldtIdx2)), dis.FP(callFrame2)))
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(nowSlot), dis.FPInd(callFrame2, int32(dis.REGRET*dis.IBY2WD))))
		fl.emit(dis.NewInst(dis.IMCALL, dis.FP(callFrame2), dis.Imm(int32(ldtIdx2)), dis.MP(fl.sysMPOff)))

		fl.emit(dis.Inst2(dis.ISEND, dis.FP(nowSlot), dis.FP(dstSlot)))
		return true, nil
	}

	// Method calls: Duration.Milliseconds(), Time.Sub()
	// SSA names methods as "(Type).Method" — check receiver
	name := callee.Name()
	if strings.HasPrefix(name, "(") {
		// Method call: receiver is first arg
		switch {
		case strings.Contains(name, "Duration") && strings.Contains(name, "Milliseconds"):
			// Duration.Milliseconds() int64 → d / 1000000
			dSlot := fl.materialize(instr.Call.Args[0])
			dstSlot := fl.slotOf(instr)
			fl.emit(dis.NewInst(dis.IDIVW, dis.Imm(1000000), dis.FP(dSlot), dis.FP(dstSlot)))
			return true, nil
		case strings.Contains(name, "Time") && strings.Contains(name, "Sub"):
			// Time.Sub(u Time) Duration → (t.msec - u.msec) * 1000000
			tSlot := fl.materialize(instr.Call.Args[0])
			uSlot := fl.materialize(instr.Call.Args[1])
			dstSlot := fl.slotOf(instr)
			fl.emit(dis.NewInst(dis.ISUBW, dis.FP(uSlot), dis.FP(tSlot), dis.FP(dstSlot)))
			fl.emit(dis.NewInst(dis.IMULW, dis.Imm(1000000), dis.FP(dstSlot), dis.FP(dstSlot)))
			return true, nil
		}
	}
	return false, nil
}

// lowerSyncCall handles calls to sync package methods.
// Mutex.Lock/Unlock use a spin-wait on a flag (cooperative scheduling).
// WaitGroup uses counter + channel signaling.
func (fl *funcLowerer) lowerSyncCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	switch {
	case strings.Contains(name, "Lock") && !strings.Contains(name, "Unlock"):
		// Mutex.Lock: spin-wait loop on locked field
		// For cooperative scheduling, just set locked=1 (no true contention)
		rcvSlot := fl.materialize(instr.Call.Args[0]) // *Mutex
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FPInd(rcvSlot, 0)))
		return true, nil
	case strings.Contains(name, "Unlock"):
		rcvSlot := fl.materialize(instr.Call.Args[0]) // *Mutex
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FPInd(rcvSlot, 0)))
		return true, nil
	case strings.Contains(name, "Add"):
		// WaitGroup.Add(delta): count += delta
		rcvSlot := fl.materialize(instr.Call.Args[0]) // *WaitGroup
		dSlot := fl.materialize(instr.Call.Args[1])
		countSlot := fl.frame.AllocWord("wg.count")
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(rcvSlot, 0), dis.FP(countSlot)))
		fl.emit(dis.NewInst(dis.IADDW, dis.FP(dSlot), dis.FP(countSlot), dis.FP(countSlot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(countSlot), dis.FPInd(rcvSlot, 0)))
		return true, nil
	case strings.Contains(name, "Done"):
		// WaitGroup.Done: count--; if count == 0 { send on channel }
		rcvSlot := fl.materialize(instr.Call.Args[0])
		countSlot := fl.frame.AllocWord("wg.dcount")
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(rcvSlot, 0), dis.FP(countSlot)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(countSlot), dis.FP(countSlot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(countSlot), dis.FPInd(rcvSlot, 0)))
		// if count == 0, send signal on channel (offset 8 in WaitGroup)
		skipPC := int32(len(fl.insts)) + 3
		fl.emit(dis.NewInst(dis.IBNEW, dis.FP(countSlot), dis.Imm(0), dis.Imm(skipPC)))
		signalSlot := fl.frame.AllocWord("wg.signal")
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(signalSlot)))
		chanSlot := fl.allocPtrTemp("wg.ch")
		fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(rcvSlot, int32(dis.IBY2WD)), dis.FP(chanSlot)))
		// Need to check if channel exists; if not, skip send
		// Actually WaitGroup.Wait creates the channel. For simplicity, skip send if ch is nil.
		skipPC2 := int32(len(fl.insts)) + 2
		fl.emit(dis.NewInst(dis.IBEQW, dis.FP(chanSlot), dis.Imm(-1), dis.Imm(skipPC2)))
		fl.emit(dis.Inst2(dis.ISEND, dis.FP(signalSlot), dis.FP(chanSlot)))
		return true, nil
	case strings.Contains(name, "Wait") && !strings.Contains(name, "Group"):
		// WaitGroup.Wait: if count > 0, create channel and recv
		rcvSlot := fl.materialize(instr.Call.Args[0])
		countSlot := fl.frame.AllocWord("wg.wcount")
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(rcvSlot, 0), dis.FP(countSlot)))
		// if count == 0 → done
		doneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.FP(countSlot), dis.Imm(0), dis.Imm(0)))
		// Create channel and store in WaitGroup
		chanSlot := fl.allocPtrTemp("wg.wch")
		fl.emit(dis.Inst2(dis.INEWCW, dis.Imm(0), dis.FP(chanSlot)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(chanSlot), dis.FPInd(rcvSlot, int32(dis.IBY2WD))))
		// Recv (blocks until Done sends)
		recvSlot := fl.frame.AllocWord("wg.recv")
		fl.emit(dis.Inst2(dis.IRECV, dis.FP(chanSlot), dis.FP(recvSlot)))
		donePC := int32(len(fl.insts))
		fl.insts[doneIdx].Dst = dis.Imm(donePC)
		return true, nil
	case strings.Contains(name, "Do"):
		// Once.Do(f): if done == 0, call f, set done = 1
		rcvSlot := fl.materialize(instr.Call.Args[0]) // *Once
		doneFlag := fl.frame.AllocWord("once.done")
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(rcvSlot, 0), dis.FP(doneFlag)))
		// if done != 0 → skip
		skipIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEW, dis.FP(doneFlag), dis.Imm(0), dis.Imm(0)))
		// Set done = 1
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FPInd(rcvSlot, 0)))
		// Call f — it's the second arg (first is receiver)
		// For now, just call it as a closure
		fArg := instr.Call.Args[1]
		if innerFn, ok := fArg.(*ssa.Function); ok {
			callFrame := fl.frame.AllocWord("")
			iframeIdx := len(fl.insts)
			fl.emit(dis.Inst2(dis.IFRAME, dis.Imm(0), dis.FP(callFrame)))
			icallIdx := len(fl.insts)
			fl.emit(dis.Inst2(dis.ICALL, dis.FP(callFrame), dis.Imm(0)))
			fl.funcCallPatches = append(fl.funcCallPatches,
				funcCallPatch{instIdx: iframeIdx, callee: innerFn, patchKind: patchIFRAME},
				funcCallPatch{instIdx: icallIdx, callee: innerFn, patchKind: patchICALL},
			)
		}
		skipPC := int32(len(fl.insts))
		fl.insts[skipIdx].Dst = dis.Imm(skipPC)
		return true, nil
	}
	return false, nil
}

// lowerSortCall handles calls to the sort package.
// sort.Ints is implemented as inline insertion sort on the Dis array.
func (fl *funcLowerer) lowerSortCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Ints":
		// Inline insertion sort on []int
		arrSlot := fl.materialize(instr.Call.Args[0])
		lenSlot := fl.frame.AllocWord("sort.len")
		fl.emit(dis.Inst2(dis.ILENA, dis.FP(arrSlot), dis.FP(lenSlot)))

		// for i := 1; i < len; i++
		iSlot := fl.frame.AllocWord("sort.i")
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(iSlot)))

		outerPC := int32(len(fl.insts))
		outerDoneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(iSlot), dis.FP(lenSlot), dis.Imm(0))) // if i >= len → done

		// key = arr[i]
		keySlot := fl.frame.AllocWord("sort.key")
		keyAddr := fl.frame.AllocWord("sort.kaddr")
		fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(keyAddr), dis.FP(iSlot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(keyAddr, 0), dis.FP(keySlot)))

		// j = i - 1
		jSlot := fl.frame.AllocWord("sort.j")
		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(iSlot), dis.FP(jSlot)))

		// while j >= 0 && arr[j] > key
		innerPC := int32(len(fl.insts))
		innerDoneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, dis.FP(jSlot), dis.Imm(0), dis.Imm(0))) // j < 0 → done

		jAddr := fl.frame.AllocWord("sort.jaddr")
		arrJ := fl.frame.AllocWord("sort.arrj")
		fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(jAddr), dis.FP(jSlot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(jAddr, 0), dis.FP(arrJ)))

		// if arr[j] <= key → done
		innerDone2Idx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLEW, dis.FP(arrJ), dis.FP(keySlot), dis.Imm(0)))

		// arr[j+1] = arr[j]
		j1Slot := fl.frame.AllocWord("sort.j1")
		j1Addr := fl.frame.AllocWord("sort.j1addr")
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(jSlot), dis.FP(j1Slot)))
		fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(j1Addr), dis.FP(j1Slot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(arrJ), dis.FPInd(j1Addr, 0)))

		// j--
		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(jSlot), dis.FP(jSlot)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(innerPC)))

		innerDonePC := int32(len(fl.insts))
		fl.insts[innerDoneIdx].Dst = dis.Imm(innerDonePC)
		fl.insts[innerDone2Idx].Dst = dis.Imm(innerDonePC)

		// arr[j+1] = key
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(jSlot), dis.FP(j1Slot)))
		fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(j1Addr), dis.FP(j1Slot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(keySlot), dis.FPInd(j1Addr, 0)))

		// i++
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(iSlot), dis.FP(iSlot)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(outerPC)))

		outerDonePC := int32(len(fl.insts))
		fl.insts[outerDoneIdx].Dst = dis.Imm(outerDonePC)
		return true, nil

	case "Strings":
		// Inline insertion sort on []string using BGTC for comparison
		arrSlot := fl.materialize(instr.Call.Args[0])
		lenSlot := fl.frame.AllocWord("ssort.len")
		fl.emit(dis.Inst2(dis.ILENA, dis.FP(arrSlot), dis.FP(lenSlot)))

		iSlot := fl.frame.AllocWord("ssort.i")
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(iSlot)))

		outerPC := int32(len(fl.insts))
		outerDoneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(iSlot), dis.FP(lenSlot), dis.Imm(0))) // if i >= len → done

		keySlot := fl.frame.AllocTemp(true)
		keyAddr := fl.frame.AllocWord("ssort.kaddr")
		fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(keyAddr), dis.FP(iSlot)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(keyAddr, 0), dis.FP(keySlot)))

		jSlot := fl.frame.AllocWord("ssort.j")
		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(iSlot), dis.FP(jSlot)))

		innerPC := int32(len(fl.insts))
		innerDoneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLTW, dis.FP(jSlot), dis.Imm(0), dis.Imm(0))) // if j < 0 → done

		jAddr := fl.frame.AllocWord("ssort.jaddr")
		arrJ := fl.frame.AllocTemp(true)
		fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(jAddr), dis.FP(jSlot)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(jAddr, 0), dis.FP(arrJ)))

		// if arr[j] <= key (string compare)
		innerDone2Idx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBLEC, dis.FP(arrJ), dis.FP(keySlot), dis.Imm(0)))

		j1Slot := fl.frame.AllocWord("ssort.j1")
		j1Addr := fl.frame.AllocWord("ssort.j1addr")
		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(jSlot), dis.FP(j1Slot)))
		fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(j1Addr), dis.FP(j1Slot)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(arrJ), dis.FPInd(j1Addr, 0)))

		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(jSlot), dis.FP(jSlot)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(innerPC)))

		innerDonePC := int32(len(fl.insts))
		fl.insts[innerDoneIdx].Dst = dis.Imm(innerDonePC)
		fl.insts[innerDone2Idx].Dst = dis.Imm(innerDonePC)

		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(jSlot), dis.FP(j1Slot)))
		fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(j1Addr), dis.FP(j1Slot)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(keySlot), dis.FPInd(j1Addr, 0)))

		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(iSlot), dis.FP(iSlot)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(outerPC)))

		outerDonePC := int32(len(fl.insts))
		fl.insts[outerDoneIdx].Dst = dis.Imm(outerDonePC)
		return true, nil

	case "IntsAreSorted":
		// Check if []int is sorted
		arrSlot := fl.materialize(instr.Call.Args[0])
		dstSlot := fl.slotOf(instr)
		lenSlot := fl.frame.AllocWord("issrt.len")
		fl.emit(dis.Inst2(dis.ILENA, dis.FP(arrSlot), dis.FP(lenSlot)))

		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dstSlot))) // assume sorted

		iSlot := fl.frame.AllocWord("issrt.i")
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(iSlot)))

		loopPC := int32(len(fl.insts))
		doneIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(iSlot), dis.FP(lenSlot), dis.Imm(0))) // if i >= len → done

		prevSlot := fl.frame.AllocWord("issrt.prev")
		curSlot := fl.frame.AllocWord("issrt.cur")
		prevIdx := fl.frame.AllocWord("issrt.pi")
		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(iSlot), dis.FP(prevIdx)))
		pAddr := fl.frame.AllocWord("issrt.pa")
		cAddr := fl.frame.AllocWord("issrt.ca")
		fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(pAddr), dis.FP(prevIdx)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(pAddr, 0), dis.FP(prevSlot)))
		fl.emit(dis.NewInst(dis.IINDX, dis.FP(arrSlot), dis.FP(cAddr), dis.FP(iSlot)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(cAddr, 0), dis.FP(curSlot)))

		// if prev > cur → not sorted
		notSortedIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBGTW, dis.FP(prevSlot), dis.FP(curSlot), dis.Imm(0)))

		fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(iSlot), dis.FP(iSlot)))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

		notSortedPC := int32(len(fl.insts))
		fl.insts[notSortedIdx].Dst = dis.Imm(notSortedPC)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dstSlot)))

		donePC := int32(len(fl.insts))
		fl.insts[doneIdx].Dst = dis.Imm(donePC)
		return true, nil
	}
	return false, nil
}

// lowerLogCall handles log.Println, log.Printf, log.Fatal, log.Fatalf.
// Maps to sys->print (log output goes to stderr in Inferno which is also stdout).
func (fl *funcLowerer) lowerLogCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Println":
		// Same as fmt.Println
		return fl.lowerFmtPrintln(instr)
	case "Printf":
		return fl.lowerFmtPrintf(instr)
	case "Fatal":
		// Print then raise
		fl.lowerFmtPrintln(instr)
		panicMP := fl.comp.AllocString("fatal")
		fl.emit(dis.Inst{Op: dis.IRAISE, Src: dis.MP(panicMP), Mid: dis.NoOperand, Dst: dis.NoOperand})
		return true, nil
	case "Fatalf":
		fl.lowerFmtPrintf(instr)
		panicMP := fl.comp.AllocString("fatal")
		fl.emit(dis.Inst{Op: dis.IRAISE, Src: dis.MP(panicMP), Mid: dis.NoOperand, Dst: dis.NoOperand})
		return true, nil
	}
	return false, nil
}

// emitHexConversion emits inline Dis instructions to convert an integer to a hex string.
// Uses a "0123456789abcdef" lookup table with SLICEC to extract 1-char substrings,
// then ADDC to prepend each digit to the result.
// Returns the frame slot containing the result string.
func (fl *funcLowerer) emitHexConversion(valOp dis.Operand) int32 {
	n := fl.frame.AllocWord("")
	result := fl.frame.AllocTemp(true)
	digit := fl.frame.AllocWord("")
	digitP1 := fl.frame.AllocWord("")
	charStr := fl.frame.AllocTemp(true)
	newResult := fl.frame.AllocTemp(true)

	// Lookup table in MP
	hexTableOff := fl.comp.AllocString("0123456789abcdef")

	// n = val
	fl.emit(dis.Inst2(dis.IMOVW, valOp, dis.FP(n)))

	// result = "" (empty string from MP)
	emptyOff := fl.comp.AllocString("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))

	// if n == 0 → zeroCase
	beqZeroIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(n), dis.Imm(0)))

	// loop:
	loopPC := int32(len(fl.insts))

	// if n == 0 → done
	beqDoneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(n), dis.Imm(0)))

	// digit = n & 0xF
	fl.emit(dis.NewInst(dis.IANDW, dis.Imm(15), dis.FP(n), dis.FP(digit)))

	// n >>= 4
	fl.emit(dis.NewInst(dis.ISHRW, dis.Imm(4), dis.FP(n), dis.FP(n)))

	// digitP1 = digit + 1
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(digit), dis.FP(digitP1)))

	// charStr = hexTable[digit:digit+1] (1-char substring)
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(hexTableOff), dis.FP(charStr)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(digit), dis.FP(digitP1), dis.FP(charStr)))

	// result = charStr + result (prepend)
	// ADDC src, mid, dst → dst = mid + src
	fl.emit(dis.NewInst(dis.IADDC, dis.FP(result), dis.FP(charStr), dis.FP(newResult)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(newResult), dis.FP(result)))

	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// zeroCase: result = "0"
	zeroPC := int32(len(fl.insts))
	fl.insts[beqZeroIdx].Dst = dis.Imm(zeroPC)
	zeroStr := fl.comp.AllocString("0")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(zeroStr), dis.FP(result)))

	// done:
	donePC := int32(len(fl.insts))
	fl.insts[beqDoneIdx].Dst = dis.Imm(donePC)

	return result
}

// emitBaseConversion emits inline instructions to convert an integer to a string
// in the given base (2 for binary, 8 for octal). Similar to emitHexConversion
// but parameterized by base and digit table.
func (fl *funcLowerer) emitBaseConversion(valOp dis.Operand, base int, digits string) int32 {
	n := fl.frame.AllocWord("")
	result := fl.frame.AllocTemp(true)
	digit := fl.frame.AllocWord("")
	digitP1 := fl.frame.AllocWord("")
	charStr := fl.frame.AllocTemp(true)
	newResult := fl.frame.AllocTemp(true)

	tableOff := fl.comp.AllocString(digits)

	fl.emit(dis.Inst2(dis.IMOVW, valOp, dis.FP(n)))

	emptyOff := fl.comp.AllocString("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(result)))

	// if n == 0 → zeroCase
	beqZeroIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(n), dis.Imm(0)))

	loopPC := int32(len(fl.insts))
	beqDoneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(0), dis.FP(n), dis.Imm(0)))

	// digit = n % base
	fl.emit(dis.NewInst(dis.IMODW, dis.Imm(int32(base)), dis.FP(n), dis.FP(digit)))
	// n /= base
	fl.emit(dis.NewInst(dis.IDIVW, dis.Imm(int32(base)), dis.FP(n), dis.FP(n)))
	// digitP1 = digit + 1
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(digit), dis.FP(digitP1)))
	// charStr = table[digit:digit+1]
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(tableOff), dis.FP(charStr)))
	fl.emit(dis.NewInst(dis.ISLICEC, dis.FP(digit), dis.FP(digitP1), dis.FP(charStr)))
	// result = charStr + result (prepend)
	fl.emit(dis.NewInst(dis.IADDC, dis.FP(result), dis.FP(charStr), dis.FP(newResult)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(newResult), dis.FP(result)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// zeroCase: result = "0"
	zeroPC := int32(len(fl.insts))
	fl.insts[beqZeroIdx].Dst = dis.Imm(zeroPC)
	zeroStr := fl.comp.AllocString("0")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(zeroStr), dis.FP(result)))

	donePC := int32(len(fl.insts))
	fl.insts[beqDoneIdx].Dst = dis.Imm(donePC)

	return result
}

// emitBoolToString emits instructions to convert a boolean value to "true" or "false".
func (fl *funcLowerer) emitBoolToString(val ssa.Value) dis.Operand {
	src := fl.operandOf(val)
	result := fl.frame.AllocTemp(true)
	trueMP := fl.comp.AllocString("true")
	falseMP := fl.comp.AllocString("false")

	// if val != 0 → trueCase
	truePC := int32(len(fl.insts)) + 3 // skip BNEW + MOVP(false) + JMP
	fl.emit(dis.NewInst(dis.IBNEW, src, dis.Imm(0), dis.Imm(truePC)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(falseMP), dis.FP(result)))
	donePC := int32(len(fl.insts)) + 2 // skip JMP + MOVP(true)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(donePC)))
	// trueCase:
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(trueMP), dis.FP(result)))
	// done:
	return dis.FP(result)
}

// emitPadWidth pads a string to the given width with spaces (or zeros if padZero).
// Uses LENC to get current length, then prepends padding chars if shorter.
func (fl *funcLowerer) emitPadWidth(src dis.Operand, width int, padZero bool) dis.Operand {
	result := fl.frame.AllocTemp(true)
	// Always copy src to result first (so skip path is safe)
	fl.emit(dis.Inst2(dis.IMOVP, src, dis.FP(result)))

	curLen := fl.frame.AllocWord("pad.len")
	fl.emit(dis.Inst2(dis.ILENC, dis.FP(result), dis.FP(curLen)))

	// if curLen >= width → done (no padding needed)
	skipIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(curLen), dis.Imm(int32(width)), dis.Imm(0)))

	padChar := " "
	if padZero {
		padChar = "0"
	}
	padMP := fl.comp.AllocString(padChar)
	padStr := fl.frame.AllocTemp(true)
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(padMP), dis.FP(padStr)))

	// Loop: while len(result) < width, result = padChar + result
	loopPC := int32(len(fl.insts))
	loopLen := fl.frame.AllocWord("pad.looplen")
	fl.emit(dis.Inst2(dis.ILENC, dis.FP(result), dis.FP(loopLen)))
	loopDoneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(loopLen), dis.Imm(int32(width)), dis.Imm(0)))
	tmp := fl.frame.AllocTemp(true)
	fl.emit(dis.NewInst(dis.IADDC, dis.FP(result), dis.FP(padStr), dis.FP(tmp)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmp), dis.FP(result)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	donePC := int32(len(fl.insts))
	fl.insts[loopDoneIdx].Dst = dis.Imm(donePC)
	fl.insts[skipIdx].Dst = dis.Imm(donePC)
	return dis.FP(result)
}

func (fl *funcLowerer) lowerPrintln(instr *ssa.Call) error {
	// println maps to sys->print with a format string
	// For each argument, emit a sys->print call with the appropriate format
	args := instr.Call.Args

	for i, arg := range args {
		if i > 0 {
			// Print space separator
			fl.emitSysPrint(" ")
		}
		if err := fl.emitPrintArg(arg); err != nil {
			return err
		}
	}

	// Print newline
	fl.emitSysPrint("\n")

	return nil
}

func (fl *funcLowerer) emitPrintArg(arg ssa.Value) error {
	t := arg.Type().Underlying()
	basic, isBasic := t.(*types.Basic)

	if isBasic {
		switch {
		case basic.Kind() == types.String:
			return fl.emitSysPrintFmt("%s", arg)
		case basic.Info()&types.IsInteger != 0:
			return fl.emitSysPrintFmt("%d", arg)
		case basic.Info()&types.IsFloat != 0:
			return fl.emitSysPrintFmt("%g", arg)
		case basic.Kind() == types.Bool:
			// println(bool) prints "true" or "false" in Go
			valOp := fl.operandOf(arg)
			trueMP := fl.comp.AllocString("true")
			falseMP := fl.comp.AllocString("false")
			strSlot := fl.frame.AllocPointer("print.boolstr")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(falseMP), dis.FP(strSlot)))
			skipIdx := len(fl.insts)
			fl.emit(dis.NewInst(dis.IBEQW, valOp, dis.Imm(0), dis.Imm(0)))
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(trueMP), dis.FP(strSlot)))
			fl.insts[skipIdx].Dst = dis.Imm(int32(len(fl.insts)))
			return fl.emitSysPrintFmtOp("%s", dis.FP(strSlot), true)
		}
	}

	// Complex: print as (real+imagi)
	if isBasic && (basic.Kind() == types.Complex128 || basic.Kind() == types.Complex64) {
		iby2wd := int32(dis.IBY2WD)
		slot := fl.materialize(arg)
		fl.emitSysPrint("(")
		if err := fl.emitSysPrintFmtOp("%g", dis.FP(slot), false); err != nil {
			return err
		}
		fl.emitSysPrint("+")
		if err := fl.emitSysPrintFmtOp("%g", dis.FP(slot+iby2wd), false); err != nil {
			return err
		}
		fl.emitSysPrint("i)")
		return nil
	}

	// Default: try %d
	return fl.emitSysPrintFmt("%d", arg)
}

// emitSysPrint emits a sys->print(literal_string) call.
func (fl *funcLowerer) emitSysPrint(s string) {
	// Allocate a temp for the format string
	fmtOff := fl.frame.AllocPointer("")

	// Store string constant into frame
	// We use MOVP to load a string. For literal strings, we need to
	// create them in the module data section. For now, use a temporary approach:
	// we'll build the string in the data section and reference it via MP.
	// Actually, for sys->print, we need to set up the frame for the print call.

	// For sys->print, the frame layout is:
	//   MaxTemp+0: format string (pointer)
	//   MaxTemp+8: return value (int)
	// But print is varargs so frame size = 0 in sysmod.h.
	// The actual frame gets sized by the compiler based on usage.

	// Simplified approach: emit the string as an immediate load.
	// Dis doesn't have a "load string literal" instruction per se.
	// String literals are loaded from the data section via MOVP from MP.
	// We need to allocate space in MP for the string and emit MOVP mp+off, fp+off.

	mpOff := fl.comp.AllocString(s)

	// Load string from MP to frame
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(mpOff), dis.FP(fmtOff)))

	// Set up print frame and call
	fl.emitSysCall("print", []callSiteArg{{fmtOff, true}})
}

// emitSysPrintFmt emits sys->print(fmt, arg).
func (fl *funcLowerer) emitSysPrintFmt(format string, arg ssa.Value) error {
	fmtOff := fl.frame.AllocPointer("")
	mpOff := fl.comp.AllocString(format)

	// Load format string
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(mpOff), dis.FP(fmtOff)))

	// Materialize the argument into a frame slot
	argOff := fl.materialize(arg)

	// Set up print frame and call with format + arg
	fl.emitSysCall("print", []callSiteArg{
		{fmtOff, true},                          // format string (always pointer)
		{argOff, GoTypeToDis(arg.Type()).IsPtr},  // argument
	})

	return nil
}

// emitSysPrintFmtOp emits sys->print(fmt, op) where op is already a dis.Operand.
func (fl *funcLowerer) emitSysPrintFmtOp(format string, op dis.Operand, isPtr bool) error {
	fmtOff := fl.frame.AllocPointer("")
	mpOff := fl.comp.AllocString(format)
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(mpOff), dis.FP(fmtOff)))

	// Copy operand to a frame slot for the call
	argOff := fl.frame.AllocWord("print.arg")
	if isPtr {
		argOff = fl.frame.AllocPointer("print.arg")
		fl.emit(dis.Inst2(dis.IMOVP, op, dis.FP(argOff)))
	} else {
		fl.emit(dis.Inst2(dis.IMOVW, op, dis.FP(argOff)))
	}

	fl.emitSysCall("print", []callSiteArg{
		{fmtOff, true},
		{argOff, isPtr},
	})
	return nil
}

// callSiteArg describes one argument being passed to a call.
type callSiteArg struct {
	srcOff int32 // frame offset of the source value
	isPtr  bool  // whether the argument is a pointer (for GC type map)
}

// emitSysCall emits a call to a Sys module function.
// For variadic functions (like print), it uses IFRAME with a local type
// descriptor. For fixed-frame functions, it uses IMFRAME.
func (fl *funcLowerer) emitSysCall(funcName string, args []callSiteArg) {
	ldtIdx, ok := fl.sysUsed[funcName]
	if !ok {
		ldtIdx = len(fl.sysUsed)
		fl.sysUsed[funcName] = ldtIdx
	}

	sf := LookupSysFunc(funcName)

	// Allocate a temp for the callee frame pointer.
	// NOT marked as a pointer: callee frames are on the stack, not heap.
	// After MCALL returns, this slot holds a stale pointer that GC must NOT trace.
	callFrame := fl.frame.AllocWord("")

	if sf != nil && sf.FrameSize == 0 {
		// Variadic function: use IFRAME with a local type descriptor
		tdID := fl.makeCallTypeDesc(args)
		fl.emit(dis.Inst2(dis.IFRAME, dis.Imm(int32(tdID)), dis.FP(callFrame)))
	} else {
		// Fixed-frame function: use IMFRAME
		fl.emit(dis.NewInst(dis.IMFRAME, dis.MP(fl.sysMPOff), dis.Imm(int32(ldtIdx)), dis.FP(callFrame)))
	}

	// Set arguments in callee frame
	for i, arg := range args {
		calleeOff := int32(dis.MaxTemp) + int32(i)*int32(dis.IBY2WD)
		if arg.isPtr {
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(arg.srcOff), dis.FPInd(callFrame, calleeOff)))
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(arg.srcOff), dis.FPInd(callFrame, calleeOff)))
		}
	}

	// Set REGRET: point to a temp word where the return value goes.
	// REGRET is at offset REGRET*IBY2WD = 32 in the callee frame.
	retOff := fl.frame.AllocWord("")
	fl.emit(dis.Inst2(dis.ILEA, dis.FP(retOff), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))

	// IMCALL: call the function
	fl.emit(dis.NewInst(dis.IMCALL, dis.FP(callFrame), dis.Imm(int32(ldtIdx)), dis.MP(fl.sysMPOff)))
}

// makeCallTypeDesc creates a type descriptor for a call-site frame.
// Returns the type descriptor ID.
func (fl *funcLowerer) makeCallTypeDesc(args []callSiteArg) int {
	// Frame layout: MaxTemp (64) + args
	frameSize := dis.MaxTemp + len(args)*dis.IBY2WD
	// Align to IBY2WD
	if frameSize%dis.IBY2WD != 0 {
		frameSize = (frameSize + dis.IBY2WD - 1) &^ (dis.IBY2WD - 1)
	}

	// ID will be assigned later by the compiler (2 + index)
	// Use a placeholder; the compiler will fix it
	td := dis.NewTypeDesc(0, frameSize)

	// Mark pointer arguments in the type map
	for i, arg := range args {
		if arg.isPtr {
			td.SetPointer(dis.MaxTemp + i*dis.IBY2WD)
		}
	}

	fl.callTypeDescs = append(fl.callTypeDescs, td)
	// Return the index; the actual ID will be computed by the compiler
	return len(fl.callTypeDescs) - 1
}

// sysGoToDisName maps Go function names in inferno/sys to Sys module function names.
var sysGoToDisName = map[string]string{
	"Fildes":   "fildes",
	"Open":     "open",
	"Create":   "create",
	"Write":    "write",
	"Read":     "read",
	"Seek":     "seek",
	"Fprint":   "fprint",
	"Sleep":    "sleep",
	"Millisec": "millisec",
	"Bind":     "bind",
	"Chdir":    "chdir",
	"Remove":   "remove",
	"Pipe":     "pipe",
	"Dup":      "dup",
	"Pctl":     "pctl",
}

// lowerSysModuleCall emits an IMFRAME/IMCALL sequence for a call to an
// inferno/sys package function, targeting the Dis Sys module.
func (fl *funcLowerer) lowerSysModuleCall(instr *ssa.Call, callee *ssa.Function) error {
	goName := callee.Name()
	disName, ok := sysGoToDisName[goName]
	if !ok {
		return fmt.Errorf("unsupported sys function: %s", goName)
	}

	sf := LookupSysFunc(disName)
	if sf == nil {
		return fmt.Errorf("unknown Sys function: %s", disName)
	}

	// Register this Sys function in the LDT
	ldtIdx, ok := fl.sysUsed[disName]
	if !ok {
		ldtIdx = len(fl.sysUsed)
		fl.sysUsed[disName] = ldtIdx
	}

	// Materialize all arguments
	type argSlot struct {
		off   int32
		isPtr bool
	}
	var args []argSlot
	for _, arg := range instr.Call.Args {
		off := fl.materialize(arg)
		dt := GoTypeToDis(arg.Type())
		args = append(args, argSlot{off, dt.IsPtr})
	}

	// Allocate callee frame slot (not GC-traced — stack frame, stale after return)
	callFrame := fl.frame.AllocWord("")

	if sf.FrameSize == 0 {
		// Variadic function (fprint, print): use IFRAME with custom TD
		var callArgs []callSiteArg
		for _, a := range args {
			callArgs = append(callArgs, callSiteArg{a.off, a.isPtr})
		}
		tdID := fl.makeCallTypeDesc(callArgs)
		fl.emit(dis.Inst2(dis.IFRAME, dis.Imm(int32(tdID)), dis.FP(callFrame)))
	} else {
		// Fixed-frame function: use IMFRAME
		fl.emit(dis.NewInst(dis.IMFRAME, dis.MP(fl.sysMPOff), dis.Imm(int32(ldtIdx)), dis.FP(callFrame)))
	}

	// Set arguments in callee frame (args start at MaxTemp = 64)
	for i, arg := range args {
		calleeOff := int32(dis.MaxTemp) + int32(i)*int32(dis.IBY2WD)
		if arg.isPtr {
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(arg.off), dis.FPInd(callFrame, calleeOff)))
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(arg.off), dis.FPInd(callFrame, calleeOff)))
		}
	}

	// Set up REGRET if function returns a value
	sig := callee.Signature
	if sig.Results().Len() > 0 {
		retSlot := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(retSlot), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))
	}

	// IMCALL: call the Sys module function
	fl.emit(dis.NewInst(dis.IMCALL, dis.FP(callFrame), dis.Imm(int32(ldtIdx)), dis.MP(fl.sysMPOff)))

	return nil
}

func (fl *funcLowerer) lowerGo(instr *ssa.Go) error {
	call := instr.Call

	// Determine target function: direct *ssa.Function or *ssa.MakeClosure
	var callee *ssa.Function
	var closureSlot int32
	isClosure := false

	switch v := call.Value.(type) {
	case *ssa.Function:
		callee = v
	case *ssa.MakeClosure:
		// Anonymous goroutine: go func() { ... }()
		innerFn := fl.comp.resolveClosureTarget(call.Value)
		if innerFn == nil {
			return fmt.Errorf("cannot statically resolve closure target for go: %v", call.Value)
		}
		callee = innerFn
		closureSlot = fl.slotOf(call.Value)
		isClosure = true
	default:
		return fmt.Errorf("go statement with non-function target: %T", call.Value)
	}

	// Materialize all arguments
	type goArgInfo struct {
		off     int32
		isPtr   bool
		isIface bool
		st      *types.Struct
	}
	var args []goArgInfo
	for _, arg := range call.Args {
		off := fl.materialize(arg)
		dt := GoTypeToDis(arg.Type())
		var st *types.Struct
		if s, ok := arg.Type().Underlying().(*types.Struct); ok {
			st = s
		}
		_, isIface := arg.Type().Underlying().(*types.Interface)
		args = append(args, goArgInfo{off, dt.IsPtr, isIface, st})
	}

	// Allocate callee frame slot
	callFrame := fl.frame.AllocWord("")

	// IFRAME $tdID, callFrame(fp)
	iframeIdx := len(fl.insts)
	fl.emit(dis.Inst2(dis.IFRAME, dis.Imm(0), dis.FP(callFrame)))

	// Set arguments in callee frame
	iby2wd := int32(dis.IBY2WD)
	calleeOff := int32(dis.MaxTemp)

	// For closures, pass closure pointer as hidden first param at MaxTemp+0
	if isClosure {
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(closureSlot), dis.FPInd(callFrame, calleeOff)))
		calleeOff += iby2wd
	}

	for _, arg := range args {
		if arg.isIface {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(arg.off), dis.FPInd(callFrame, calleeOff)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(arg.off+iby2wd), dis.FPInd(callFrame, calleeOff+iby2wd)))
			calleeOff += 2 * iby2wd
		} else if arg.st != nil {
			fieldOff := int32(0)
			for i := 0; i < arg.st.NumFields(); i++ {
				fdt := GoTypeToDis(arg.st.Field(i).Type())
				if fdt.IsPtr {
					fl.emit(dis.Inst2(dis.IMOVP, dis.FP(arg.off+fieldOff), dis.FPInd(callFrame, calleeOff+fieldOff)))
				} else {
					fl.emit(dis.Inst2(dis.IMOVW, dis.FP(arg.off+fieldOff), dis.FPInd(callFrame, calleeOff+fieldOff)))
				}
				fieldOff += fdt.Size
			}
			calleeOff += GoTypeToDis(arg.st).Size
		} else if arg.isPtr {
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(arg.off), dis.FPInd(callFrame, calleeOff)))
			calleeOff += iby2wd
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(arg.off), dis.FPInd(callFrame, calleeOff)))
			calleeOff += iby2wd
		}
	}

	// SPAWN callFrame(fp), $targetPC (instead of CALL)
	ispawnIdx := len(fl.insts)
	fl.emit(dis.Inst2(dis.ISPAWN, dis.FP(callFrame), dis.Imm(0)))

	// Record patches
	fl.funcCallPatches = append(fl.funcCallPatches,
		funcCallPatch{instIdx: iframeIdx, callee: callee, patchKind: patchIFRAME},
		funcCallPatch{instIdx: ispawnIdx, callee: callee, patchKind: patchICALL}, // same patch kind — dst = PC
	)

	return nil
}

func (fl *funcLowerer) lowerMakeChan(instr *ssa.MakeChan) error {
	chanType := instr.Type().(*types.Chan)
	elemType := chanType.Elem()

	// Select NEWC variant based on element type
	newcOp := channelNewcOp(elemType)

	// Destination: the channel wrapper pointer slot (already allocated as pointer)
	dst := fl.slotOf(instr)

	// Allocate heap wrapper: {raw Channel* (offset 0), closed flag (offset 8)}
	wrapperTDIdx := fl.makeChanWrapperTD()
	fl.emit(dis.Inst2(dis.INEW, dis.Imm(int32(wrapperTDIdx)), dis.FP(dst)))

	// Create raw channel directly into wrapper's offset 0.
	// Determine buffer size from SSA's Size operand.
	bufSize := int32(0)
	isConst := false
	if c, ok := instr.Size.(*ssa.Const); ok {
		bufSize = int32(c.Int64())
		isConst = true
	}

	if isConst && bufSize == 0 {
		// Unbuffered: no middle operand → R.m == R.d → buffer size 0
		fl.emit(dis.Inst1(newcOp, dis.FPInd(dst, 0)))
	} else if isConst {
		// Constant buffer size: middle = immediate
		fl.emit(dis.NewInst(newcOp, dis.NoOperand, dis.Imm(bufSize), dis.FPInd(dst, 0)))
	} else {
		// Dynamic buffer size: materialize the size value
		sizeSlot := fl.materialize(instr.Size)
		fl.emit(dis.NewInst(newcOp, dis.NoOperand, dis.FP(sizeSlot), dis.FPInd(dst, 0)))
	}

	// Store buffer capacity in wrapper at offset 16 for cap()
	if isConst {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(bufSize), dis.FPInd(dst, 16)))
	} else {
		sizeSlot := fl.materialize(instr.Size)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(sizeSlot), dis.FPInd(dst, 16)))
	}

	return nil
}

// channelNewcOp selects the appropriate NEWC variant for a channel element type.
func channelNewcOp(elemType types.Type) dis.Op {
	dt := GoTypeToDis(elemType)
	if dt.IsPtr {
		return dis.INEWCP
	}
	if IsByteType(elemType) {
		return dis.INEWCB
	}
	if basic, ok := elemType.Underlying().(*types.Basic); ok {
		if basic.Info()&types.IsFloat != 0 {
			return dis.INEWCF
		}
	}
	return dis.INEWCW
}

// lowerClose handles close(ch). Sets the closed flag and sends a zero value
// via NBALT to wake any goroutine blocked in RECV on this channel.
func (fl *funcLowerer) lowerClose(instr *ssa.Call) error {
	chanArg := instr.Call.Args[0]
	chanSlot := fl.materialize(chanArg)

	// Set closed flag in channel wrapper: wrapper.closed = 1
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FPInd(chanSlot, 8)))

	// Send a zero value to wake any blocked receiver.
	// Use NBALT with nsend=1 so it doesn't block if no one is waiting.
	chanType := chanArg.Type().Underlying().(*types.Chan)
	elemType := chanType.Elem()
	elemDt := GoTypeToDis(elemType)

	// Allocate a zero-value slot
	zeroSlot := fl.frame.AllocWord("close.zero")
	if elemDt.IsPtr {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(zeroSlot))) // H for pointer types
	} else {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(zeroSlot)))
	}

	// Build 1-entry Alt struct: {nsend=1, nrecv=0, {rawCh, &zeroSlot}}
	iby2wd := int32(dis.IBY2WD)
	altBase := fl.frame.AllocWord("close.alt.nsend")
	fl.frame.AllocWord("close.alt.nrecv")
	fl.frame.AllocPointer("close.alt.ch")
	fl.frame.AllocWord("close.alt.ptr")

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(altBase)))          // nsend = 1
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(altBase+iby2wd)))   // nrecv = 0

	// Extract raw channel from wrapper
	tmpRaw := fl.allocPtrTemp("close.raw")
	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(chanSlot, 0), dis.FP(tmpRaw)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmpRaw), dis.FP(altBase+2*iby2wd))) // channel
	fl.emit(dis.Inst2(dis.ILEA, dis.FP(zeroSlot), dis.FP(altBase+3*iby2wd))) // &zeroSlot

	// NBALT: non-blocking send. If a receiver is waiting, it gets the zero value.
	// If no one is waiting and buffer is full, this is a no-op.
	nbaltResult := fl.frame.AllocWord("close.nbalt.result")
	fl.emit(dis.Inst2(dis.INBALT, dis.FP(altBase), dis.FP(nbaltResult)))

	return nil
}

func (fl *funcLowerer) lowerSend(instr *ssa.Send) error {
	// Materialize the value to send into a frame slot
	valOff := fl.materialize(instr.X)

	// Get the channel wrapper slot
	chanOff := fl.slotOf(instr.Chan)

	// Check closed flag: if wrapper.closed != 0, panic
	tmpFlag := fl.frame.AllocWord("send.flag")
	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(chanOff, 8), dis.FP(tmpFlag)))
	okPC := int32(len(fl.insts)) + 3 // skip BEQW, MOVP+RAISE
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(tmpFlag), dis.Imm(0), dis.Imm(okPC)))

	// Panic: "send on closed channel"
	panicStr := fl.comp.AllocString("send on closed channel")
	panicSlot := fl.frame.AllocPointer("send.panic")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(panicStr), dis.FP(panicSlot)))
	fl.emit(dis.Inst{Op: dis.IRAISE, Src: dis.FP(panicSlot), Mid: dis.NoOperand, Dst: dis.NoOperand})

	// Extract raw channel from wrapper and send
	tmpRaw := fl.allocPtrTemp("send.raw")
	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(chanOff, 0), dis.FP(tmpRaw)))
	fl.emit(dis.Inst2(dis.ISEND, dis.FP(valOff), dis.FP(tmpRaw)))

	// Increment buffered value count: wrapper[24]++
	tmpCnt := fl.frame.AllocWord("send.cnt")
	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(chanOff, 24), dis.FP(tmpCnt)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(tmpCnt), dis.FP(tmpCnt)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(tmpCnt), dis.FPInd(chanOff, 24)))

	return nil
}

// emitCloseAwareRecv emits a close-aware channel receive for both simple (<-ch)
// and commaOk (v, ok := <-ch / for range ch) receives.
//
// When the channel is open, performs a blocking RECV.
// When closed, drains any buffered values via NBALT; if buffer is empty,
// returns the zero value (and ok=false for commaOk).
func (fl *funcLowerer) emitCloseAwareRecv(instr *ssa.UnOp, chanOff, dst int32) error {
	iby2wd := int32(dis.IBY2WD)

	// Determine element type for zero-value emission
	chanType := instr.X.Type().Underlying().(*types.Chan)
	elemType := chanType.Elem()
	elemDt := GoTypeToDis(elemType)

	// Extract raw channel from wrapper
	tmpRaw := fl.allocPtrTemp("recv.raw")
	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(chanOff, 0), dis.FP(tmpRaw)))

	// Read closed flag
	tmpFlag := fl.frame.AllocWord("recv.flag")
	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(chanOff, 8), dis.FP(tmpFlag)))

	// BEQW flag, $0, $openPath → if not closed, do blocking recv
	beqwIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(tmpFlag), dis.Imm(0), dis.Imm(0))) // patched below

	// === Closed path: try non-blocking receive to drain buffer ===
	// Build 1-entry Alt struct: {nsend=0, nrecv=1, {rawCh, &dst}}
	altBase := fl.frame.AllocWord("recv.alt.nsend")
	fl.frame.AllocWord("recv.alt.nrecv")
	fl.frame.AllocPointer("recv.alt.ch")
	fl.frame.AllocWord("recv.alt.ptr")

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(altBase)))            // nsend = 0
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(altBase+iby2wd)))     // nrecv = 1
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmpRaw), dis.FP(altBase+2*iby2wd))) // channel
	fl.emit(dis.Inst2(dis.ILEA, dis.FP(dst), dis.FP(altBase+3*iby2wd)))   // &dst

	// NBALT returns index: 0 = got value, 1 = nothing ready
	nbaltIdx := fl.frame.AllocWord("recv.nbalt.idx")
	fl.emit(dis.Inst2(dis.INBALT, dis.FP(altBase), dis.FP(nbaltIdx)))

	// BEQW nbaltIdx, $0, $gotValue → if got value, skip to gotValue
	beqwGotIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(nbaltIdx), dis.Imm(0), dis.Imm(0))) // patched below

	// Empty + closed: return zero value
	if elemDt.IsPtr {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst))) // H for pointer types
	} else {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
	}
	if instr.CommaOk {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd))) // ok = false
	}
	emptyJmpIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0))) // → done

	// gotValue: value already written to dst by NBALT.
	// Check buffered value count to distinguish real values from phantom zeros.
	gotValuePC := int32(len(fl.insts))
	fl.insts[beqwGotIdx].Dst = dis.Imm(gotValuePC)
	if instr.CommaOk {
		// Read buffered count from wrapper[24]
		tmpCnt := fl.frame.AllocWord("recv.cnt")
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(chanOff, 24), dis.FP(tmpCnt)))
		// If count > 0: real buffered value → ok=true, decrement count
		beqwPhantomIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.FP(tmpCnt), dis.Imm(0), dis.Imm(0))) // patched: if count==0 → phantom
		// Real value: ok=true, decrement count
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst+iby2wd))) // ok = true
		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(tmpCnt), dis.FP(tmpCnt)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(tmpCnt), dis.FPInd(chanOff, 24)))
		closedRealJmpIdx := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0))) // → done
		// Phantom zero: ok=false, emit zero value
		phantomPC := int32(len(fl.insts))
		fl.insts[beqwPhantomIdx].Dst = dis.Imm(phantomPC)
		if elemDt.IsPtr {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst))) // H
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		}
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd))) // ok = false
		closedPhantomJmpIdx := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0))) // → done

		// === Open path: blocking receive ===
		openPC := int32(len(fl.insts))
		fl.insts[beqwIdx].Dst = dis.Imm(openPC)

		fl.emit(dis.Inst2(dis.IRECV, dis.FP(tmpRaw), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst+iby2wd))) // ok = true
		// Decrement buffered count
		tmpCnt2 := fl.frame.AllocWord("recv.cnt2")
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(chanOff, 24), dis.FP(tmpCnt2)))
		fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(tmpCnt2), dis.FP(tmpCnt2)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(tmpCnt2), dis.FPInd(chanOff, 24)))

		// done:
		donePC := int32(len(fl.insts))
		fl.insts[emptyJmpIdx].Dst = dis.Imm(donePC)
		fl.insts[closedRealJmpIdx].Dst = dis.Imm(donePC)
		fl.insts[closedPhantomJmpIdx].Dst = dis.Imm(donePC)
	} else {
		// Simple receive (no commaOk): don't need to check count for ok,
		// but still decrement count to keep it accurate.
		closedDoneJmpIdx := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0))) // → done (skip decrement, already consumed)

		// === Open path: blocking receive ===
		openPC := int32(len(fl.insts))
		fl.insts[beqwIdx].Dst = dis.Imm(openPC)

		fl.emit(dis.Inst2(dis.IRECV, dis.FP(tmpRaw), dis.FP(dst)))

		// done:
		donePC := int32(len(fl.insts))
		fl.insts[emptyJmpIdx].Dst = dis.Imm(donePC)
		fl.insts[closedDoneJmpIdx].Dst = dis.Imm(donePC)
	}

	return nil
}

func (fl *funcLowerer) lowerSelect(instr *ssa.Select) error {
	states := instr.States

	// Count sends and recvs
	var nsend, nrecv int
	for _, s := range states {
		if s.Dir == types.SendOnly {
			nsend++
		} else {
			nrecv++
		}
	}

	nTotal := nsend + nrecv

	// Tuple base: [index (0), recvOk (8), v0 (16), v1 (24), ...]
	tupleBase := fl.slotOf(instr)

	// Allocate contiguous Alt structure in frame:
	//   nsend (WORD), nrecv (WORD), then N × {Channel* (ptr), void* (word)}
	altBase := fl.frame.AllocWord("alt.nsend")
	fl.frame.AllocWord("alt.nrecv")
	for i := 0; i < nTotal; i++ {
		fl.frame.AllocPointer(fmt.Sprintf("alt.ac%d.c", i))
		fl.frame.AllocWord(fmt.Sprintf("alt.ac%d.ptr", i))
	}

	// Fill in header
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(int32(nsend)), dis.FP(altBase)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(int32(nrecv)), dis.FP(altBase+int32(dis.IBY2WD))))

	// Dis ALT requires sends first, then recvs. Build a mapping from Dis
	// index to Go case index so we can remap the result.
	// disToGo[disIdx] = goIdx
	disToGo := make([]int, nTotal)
	mixed := nsend > 0 && nrecv > 0

	// Fill in Alt entries: sends first, then recvs
	acOff := altBase + 2*int32(dis.IBY2WD)
	disIdx := 0

	// Pass 1: sends
	for i, s := range states {
		if s.Dir != types.SendOnly {
			continue
		}
		disToGo[disIdx] = i
		chanOff := fl.slotOf(s.Chan)
		fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(chanOff, 0), dis.FP(acOff)))
		valOff := fl.materialize(s.Send)
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(valOff), dis.FP(acOff+int32(dis.IBY2WD))))
		acOff += 2 * int32(dis.IBY2WD)
		disIdx++
	}

	// Pass 2: recvs
	for i, s := range states {
		if s.Dir == types.SendOnly {
			continue
		}
		disToGo[disIdx] = i
		chanOff := fl.slotOf(s.Chan)
		fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(chanOff, 0), dis.FP(acOff)))
		recvOff := tupleBase + int32((2+i))*int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(recvOff), dis.FP(acOff+int32(dis.IBY2WD))))
		acOff += 2 * int32(dis.IBY2WD)
		disIdx++
	}

	// Emit ALT (blocking) or NBALT (non-blocking / has default)
	if instr.Blocking {
		fl.emit(dis.Inst2(dis.IALT, dis.FP(altBase), dis.FP(tupleBase)))
	} else {
		fl.emit(dis.Inst2(dis.INBALT, dis.FP(altBase), dis.FP(tupleBase)))
	}

	// Remap Dis index to Go case index if mixed send/recv
	if mixed {
		// tupleBase+0 holds the Dis index. Remap via a BEQW chain.
		rawIdx := fl.frame.AllocWord("alt.rawIdx")
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(tupleBase), dis.FP(rawIdx)))

		// For each Dis index, check if it matches and set the Go index.
		// Only emit remapping for indices where disIdx != goIdx.
		var jmpToEndIdxs []int
		for di, gi := range disToGo {
			if di == gi {
				continue // no remapping needed
			}
			skipPC := int32(len(fl.insts)) + 3 // skip BNEW + MOVW + JMP
			fl.emit(dis.NewInst(dis.IBNEW, dis.FP(rawIdx), dis.Imm(int32(di)), dis.Imm(skipPC)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(int32(gi)), dis.FP(tupleBase)))
			jmpToEndIdxs = append(jmpToEndIdxs, len(fl.insts))
			fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0))) // → done (patched below)
		}
		donePC := int32(len(fl.insts))
		for _, idx := range jmpToEndIdxs {
			fl.insts[idx].Dst = dis.Imm(donePC)
		}
	}

	// Set recvOk = 1 (Dis channels can't be closed)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(tupleBase+int32(dis.IBY2WD))))

	return nil
}

func (fl *funcLowerer) lowerDirectCall(instr *ssa.Call, callee *ssa.Function) error {
	call := instr.Call

	// Materialize all arguments first (may emit instructions for constants)
	type argInfo struct {
		off     int32
		isPtr   bool
		isIface bool         // true if interface type (2 words)
		st      *types.Struct // non-nil if this is a struct value argument
	}
	var args []argInfo
	for _, arg := range call.Args {
		off := fl.materialize(arg)
		dt := GoTypeToDis(arg.Type())
		var st *types.Struct
		if s, ok := arg.Type().Underlying().(*types.Struct); ok {
			st = s
		}
		_, isIface := arg.Type().Underlying().(*types.Interface)
		args = append(args, argInfo{off, dt.IsPtr, isIface, st})
	}

	// Allocate callee frame slot (NOT a GC pointer - stack allocated, stale after return)
	callFrame := fl.frame.AllocWord("")

	// IFRAME $0, callFrame(fp) — TD ID is placeholder, patched by compiler
	iframeIdx := len(fl.insts)
	fl.emit(dis.Inst2(dis.IFRAME, dis.Imm(0), dis.FP(callFrame)))

	// Set arguments in callee frame (args start at MaxTemp = 64)
	iby2wd := int32(dis.IBY2WD)
	calleeOff := int32(dis.MaxTemp)
	for _, arg := range args {
		if arg.isIface {
			// Interface argument: copy 2 words (tag + value)
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(arg.off), dis.FPInd(callFrame, calleeOff)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(arg.off+iby2wd), dis.FPInd(callFrame, calleeOff+iby2wd)))
			calleeOff += 2 * iby2wd
		} else if arg.st != nil {
			// Struct argument: multi-word copy
			fieldOff := int32(0)
			for i := 0; i < arg.st.NumFields(); i++ {
				fdt := GoTypeToDis(arg.st.Field(i).Type())
				if fdt.IsPtr {
					fl.emit(dis.Inst2(dis.IMOVP, dis.FP(arg.off+fieldOff), dis.FPInd(callFrame, calleeOff+fieldOff)))
				} else {
					fl.emit(dis.Inst2(dis.IMOVW, dis.FP(arg.off+fieldOff), dis.FPInd(callFrame, calleeOff+fieldOff)))
				}
				fieldOff += fdt.Size
			}
			calleeOff += GoTypeToDis(arg.st).Size
		} else if arg.isPtr {
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(arg.off), dis.FPInd(callFrame, calleeOff)))
			calleeOff += iby2wd
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(arg.off), dis.FPInd(callFrame, calleeOff)))
			calleeOff += iby2wd
		}
	}

	// Set up REGRET if function returns a value
	sig := callee.Signature
	if sig.Results().Len() > 0 {
		retSlot := fl.slotOf(instr) // caller's slot where result lands
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(retSlot), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))
	}

	// CALL callFrame(fp), $0 — target PC is placeholder, patched by compiler
	icallIdx := len(fl.insts)
	fl.emit(dis.Inst2(dis.ICALL, dis.FP(callFrame), dis.Imm(0)))

	// Record patches for the compiler to resolve
	fl.funcCallPatches = append(fl.funcCallPatches,
		funcCallPatch{instIdx: iframeIdx, callee: callee, patchKind: patchIFRAME},
		funcCallPatch{instIdx: icallIdx, callee: callee, patchKind: patchICALL},
	)

	return nil
}

// lowerInvokeCall handles interface method calls (s.Method()).
// For single-implementation interfaces: direct call (fast path).
// For multi-implementation: BEQW dispatch chain on type tag.
func (fl *funcLowerer) lowerInvokeCall(instr *ssa.Call) error {
	call := instr.Call
	methodName := call.Method.Name()

	// Resolve all concrete implementations of this method
	impls := fl.comp.ResolveInterfaceMethods(methodName)
	if len(impls) == 0 {
		return fmt.Errorf("cannot resolve interface method %s (no implementation found)", methodName)
	}

	// The receiver is call.Value (tagged interface: tag at +0, value at +8).
	ifaceSlot := fl.materialize(call.Value) // interface base slot
	iby2wd := int32(dis.IBY2WD)

	// Materialize additional arguments
	type argInfo struct {
		off   int32
		isPtr bool
	}
	var extraArgs []argInfo
	for _, arg := range call.Args {
		off := fl.materialize(arg)
		dt := GoTypeToDis(arg.Type())
		extraArgs = append(extraArgs, argInfo{off, dt.IsPtr})
	}

	// emitCallForImpl emits IFRAME + arg copy + REGRET + ICALL for one callee,
	// using ifaceSlot+8 as the receiver value.
	emitCallForImpl := func(callee *ssa.Function) {
		callFrame := fl.frame.AllocWord("")

		iframeIdx := len(fl.insts)
		fl.emit(dis.Inst2(dis.IFRAME, dis.Imm(0), dis.FP(callFrame)))

		// Set receiver (first param at MaxTemp)
		calleeOff := int32(dis.MaxTemp)
		recvValueSlot := ifaceSlot + iby2wd // value part of interface
		if len(callee.Params) > 0 {
			recvType := callee.Params[0].Type()
			paramDT := GoTypeToDis(recvType)
			if st, ok := recvType.Underlying().(*types.Struct); ok && paramDT.Size > iby2wd {
				// Struct receiver: interface value holds a pointer to struct data.
				// Copy each field through the pointer.
				fieldOff := int32(0)
				for i := 0; i < st.NumFields(); i++ {
					fdt := GoTypeToDis(st.Field(i).Type())
					if fdt.IsPtr {
						fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(recvValueSlot, fieldOff), dis.FPInd(callFrame, calleeOff+fieldOff)))
					} else {
						fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(recvValueSlot, fieldOff), dis.FPInd(callFrame, calleeOff+fieldOff)))
					}
					fieldOff += fdt.Size
				}
				calleeOff += paramDT.Size
			} else if paramDT.IsPtr {
				fl.emit(dis.Inst2(dis.IMOVP, dis.FP(recvValueSlot), dis.FPInd(callFrame, calleeOff)))
				calleeOff += iby2wd
			} else {
				fl.emit(dis.Inst2(dis.IMOVW, dis.FP(recvValueSlot), dis.FPInd(callFrame, calleeOff)))
				calleeOff += iby2wd
			}
		}

		// Set additional arguments
		for _, arg := range extraArgs {
			if arg.isPtr {
				fl.emit(dis.Inst2(dis.IMOVP, dis.FP(arg.off), dis.FPInd(callFrame, calleeOff)))
			} else {
				fl.emit(dis.Inst2(dis.IMOVW, dis.FP(arg.off), dis.FPInd(callFrame, calleeOff)))
			}
			calleeOff += iby2wd
		}

		// Set up REGRET if function returns a value
		sig := callee.Signature
		if sig.Results().Len() > 0 && instr.Name() != "" {
			retSlot := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.ILEA, dis.FP(retSlot), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))
		}

		// CALL
		icallIdx := len(fl.insts)
		fl.emit(dis.Inst2(dis.ICALL, dis.FP(callFrame), dis.Imm(0)))

		fl.funcCallPatches = append(fl.funcCallPatches,
			funcCallPatch{instIdx: iframeIdx, callee: callee, patchKind: patchIFRAME},
			funcCallPatch{instIdx: icallIdx, callee: callee, patchKind: patchICALL},
		)
	}

	// emitSyntheticInline emits inline code for a synthetic method (fn==nil).
	// Currently handles errorString.Error() — the value IS the string.
	emitSyntheticInline := func() {
		if instr.Name() != "" {
			resultDst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(ifaceSlot+iby2wd), dis.FP(resultDst)))
		}
	}

	if len(impls) == 1 {
		// Single-implementation fast path: direct call or inline synthetic
		if impls[0].fn == nil {
			emitSyntheticInline()
		} else {
			emitCallForImpl(impls[0].fn)
		}
		return nil
	}

	// Multi-implementation dispatch: BEQW chain on type tag
	// Layout:
	//   BEQW $tag1, FP(ifaceSlot), $call1_pc
	//   BEQW $tag2, FP(ifaceSlot), $call2_pc
	//   RAISE "unknown type"
	//   call1: IFRAME/args/ICALL; JMP exit
	//   call2: IFRAME/args/ICALL; JMP exit
	//   exit:

	var beqwIdxs []int
	for _, impl := range impls {
		idx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(impl.tag), dis.FP(ifaceSlot), dis.Imm(0))) // dst patched below
		beqwIdxs = append(beqwIdxs, idx)
	}

	// Default: panic with unknown type
	panicStr := fl.comp.AllocString("unknown type in interface dispatch")
	panicSlot := fl.frame.AllocPointer("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(panicStr), dis.FP(panicSlot)))
	fl.emit(dis.Inst{Op: dis.IRAISE, Src: dis.FP(panicSlot), Mid: dis.NoOperand, Dst: dis.NoOperand})

	// Emit call sequence for each impl, patch BEQW targets
	var exitJmps []int
	for i, impl := range impls {
		// Patch BEQW to jump here
		fl.insts[beqwIdxs[i]].Dst = dis.Imm(int32(len(fl.insts)))

		if impl.fn == nil {
			emitSyntheticInline()
		} else {
			emitCallForImpl(impl.fn)
		}

		// JMP to exit (placeholder)
		exitIdx := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		exitJmps = append(exitJmps, exitIdx)
	}

	// Patch exit JMPs
	exitPC := int32(len(fl.insts))
	for _, idx := range exitJmps {
		fl.insts[idx].Dst = dis.Imm(exitPC)
	}

	return nil
}

func (fl *funcLowerer) lowerReturn(instr *ssa.Return) error {
	if len(instr.Results) > 0 {
		// Store return values through REGRET pointer.
		// REGRET is at offset REGRET*IBY2WD = 32 in the frame header.
		// Multiple results go at successive offsets from REGRET.
		regretOff := int32(dis.REGRET * dis.IBY2WD)
		iby2wd := int32(dis.IBY2WD)
		retOff := int32(0)
		for _, result := range instr.Results {
			if _, ok := result.Type().Underlying().(*types.Interface); ok {
				// Interface return: copy 2 words (tag + value)
				off := fl.materialize(result)
				fl.emit(dis.Inst2(dis.IMOVW, dis.FP(off), dis.FPInd(regretOff, retOff)))
				fl.emit(dis.Inst2(dis.IMOVW, dis.FP(off+iby2wd), dis.FPInd(regretOff, retOff+iby2wd)))
				retOff += 2 * iby2wd
			} else if st, ok := result.Type().Underlying().(*types.Struct); ok {
				// Struct return: copy all fields
				off := fl.materialize(result)
				fieldOff := int32(0)
				for i := 0; i < st.NumFields(); i++ {
					fdt := GoTypeToDis(st.Field(i).Type())
					if fdt.IsPtr {
						fl.emit(dis.Inst2(dis.IMOVP, dis.FP(off+fieldOff), dis.FPInd(regretOff, retOff+fieldOff)))
					} else {
						fl.emit(dis.Inst2(dis.IMOVW, dis.FP(off+fieldOff), dis.FPInd(regretOff, retOff+fieldOff)))
					}
					fieldOff += fdt.Size
				}
				retOff += GoTypeToDis(st).Size
			} else {
				off := fl.materialize(result)
				dt := GoTypeToDis(result.Type())
				if dt.IsPtr {
					fl.emit(dis.Inst2(dis.IMOVP, dis.FP(off), dis.FPInd(regretOff, retOff)))
				} else {
					fl.emit(dis.Inst2(dis.IMOVW, dis.FP(off), dis.FPInd(regretOff, retOff)))
				}
				retOff += dt.Size
			}
		}
	}
	fl.emit(dis.Inst0(dis.IRET))
	return nil
}

func (fl *funcLowerer) lowerIf(instr *ssa.If) error {
	// The condition is already a boolean in a frame slot
	condOff := fl.slotOf(instr.Cond)

	// If condition != 0, jump to the true block (Succs[0])
	// Otherwise fall through to false block (Succs[1])
	trueBlock := instr.Block().Succs[0]
	falseBlock := instr.Block().Succs[1]
	thisBlock := instr.Block()

	trueHasPhi := blockHasPhis(trueBlock)
	falseHasPhi := blockHasPhis(falseBlock)

	if !trueHasPhi && !falseHasPhi {
		// Simple case: no phis in either successor
		patchIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEW, dis.FP(condOff), dis.Imm(0), dis.Imm(0)))
		fl.patches = append(fl.patches, branchPatch{instIdx: patchIdx, target: trueBlock})

		patchIdx = len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		fl.patches = append(fl.patches, branchPatch{instIdx: patchIdx, target: falseBlock})
	} else {
		// Phis present: emit separate phi-move blocks for each path.
		// Layout:
		//   BNEW cond, $0, truePhiPC    (if true, skip false path)
		//   [false phi moves]
		//   JMP falseBlock
		//   [true phi moves]            (truePhiPC lands here)
		//   JMP trueBlock

		// BNEW with placeholder — patched below once we know truePhiPC
		bnewIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBNEW, dis.FP(condOff), dis.Imm(0), dis.Imm(0)))

		// False path: emit phi moves then jump
		fl.emitPhiMoves(thisBlock, falseBlock)
		falseJmpIdx := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		fl.patches = append(fl.patches, branchPatch{instIdx: falseJmpIdx, target: falseBlock})

		// True path starts here — patch the BNEW target
		truePhiPC := int32(len(fl.insts))
		fl.insts[bnewIdx].Dst = dis.Imm(truePhiPC)

		fl.emitPhiMoves(thisBlock, trueBlock)
		trueJmpIdx := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
		fl.patches = append(fl.patches, branchPatch{instIdx: trueJmpIdx, target: trueBlock})
	}

	return nil
}

func (fl *funcLowerer) lowerJump(instr *ssa.Jump) error {
	target := instr.Block().Succs[0]

	// Emit phi moves for the target block before jumping
	fl.emitPhiMoves(instr.Block(), target)

	patchIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
	fl.patches = append(fl.patches, branchPatch{instIdx: patchIdx, target: target})
	return nil
}

func (fl *funcLowerer) lowerPhi(instr *ssa.Phi) error {
	// Phi nodes are handled by emitPhiMoves in lowerIf/lowerJump.
	// The moves are inserted at the end of each predecessor block,
	// before the terminating branch/jump instruction.
	return nil
}

// emitPhiMoves emits MOV instructions for phi nodes when transitioning
// from 'from' to 'to'. For each phi in 'to', this emits a move from the
// value corresponding to the 'from' edge.
func (fl *funcLowerer) emitPhiMoves(from, to *ssa.BasicBlock) {
	// Find which edge index 'from' is in 'to's predecessor list
	edgeIdx := -1
	for i, pred := range to.Preds {
		if pred == from {
			edgeIdx = i
			break
		}
	}
	if edgeIdx < 0 {
		return
	}

	for _, instr := range to.Instrs {
		phi, ok := instr.(*ssa.Phi)
		if !ok {
			break // phis are always at the start of a block
		}
		dst := fl.slotOf(phi)
		if _, ok := phi.Type().Underlying().(*types.Interface); ok {
			// Interface phi: copy 2 words (tag + value)
			edge := phi.Edges[edgeIdx]
			if c, ok := edge.(*ssa.Const); ok && c.Value == nil {
				// nil interface: tag=0, value=0
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+int32(dis.IBY2WD))))
			} else {
				srcSlot := fl.slotOf(edge)
				fl.copyIface(srcSlot, dst)
			}
		} else {
			src := fl.operandOf(phi.Edges[edgeIdx])
			dt := GoTypeToDis(phi.Type())
			if dt.IsPtr {
				fl.emit(dis.Inst2(dis.IMOVP, src, dis.FP(dst)))
			} else {
				fl.emit(dis.Inst2(dis.IMOVW, src, dis.FP(dst)))
			}
		}
	}
}

// blockHasPhis returns true if the block starts with any Phi instructions.
func blockHasPhis(b *ssa.BasicBlock) bool {
	if len(b.Instrs) == 0 {
		return false
	}
	_, ok := b.Instrs[0].(*ssa.Phi)
	return ok
}

func (fl *funcLowerer) lowerStore(instr *ssa.Store) error {
	addrOff := fl.slotOf(instr.Addr)

	// Check if storing an interface value (2-word: tag + value)
	if _, ok := instr.Val.Type().Underlying().(*types.Interface); ok {
		valBase := fl.slotOf(instr.Val)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(valBase), dis.FPInd(addrOff, 0)))          // tag
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(valBase+iby2wd), dis.FPInd(addrOff, iby2wd))) // value
		return nil
	}

	// Check if storing a struct value (multi-word)
	if st, ok := instr.Val.Type().Underlying().(*types.Struct); ok {
		valBase := fl.slotOf(instr.Val)
		fieldOff := int32(0)
		for i := 0; i < st.NumFields(); i++ {
			fdt := GoTypeToDis(st.Field(i).Type())
			if fdt.IsPtr {
				fl.emit(dis.Inst2(dis.IMOVP, dis.FP(valBase+fieldOff), dis.FPInd(addrOff, fieldOff)))
			} else {
				fl.emit(dis.Inst2(dis.IMOVW, dis.FP(valBase+fieldOff), dis.FPInd(addrOff, fieldOff)))
			}
			fieldOff += fdt.Size
		}
		return nil
	}

	valOff := fl.materialize(instr.Val)
	dt := GoTypeToDis(instr.Val.Type())
	if dt.IsPtr {
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(valOff), dis.FPInd(addrOff, 0)))
	} else if IsByteType(instr.Val.Type()) {
		// Byte store: truncate word to byte via CVTWB
		fl.emit(dis.Inst2(dis.ICVTWB, dis.FP(valOff), dis.FPInd(addrOff, 0)))
	} else {
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(valOff), dis.FPInd(addrOff, 0)))
	}
	return nil
}

// lowerSliceToArrayPointer handles (*[N]T)(slice) — Go 1.17+ conversion.
// In Dis, slices are array pointers, so this is essentially a length check + copy.
func (fl *funcLowerer) lowerSliceToArrayPointer(instr *ssa.SliceToArrayPointer) error {
	srcSlot := fl.materialize(instr.X)
	dstSlot := fl.slotOf(instr)

	// Get the target array length
	ptrType := instr.Type().(*types.Pointer)
	arrType := ptrType.Elem().(*types.Array)
	arrLen := arrType.Len()

	if arrLen > 0 {
		// Bounds check: if len(slice) < N, panic
		lenSlot := fl.frame.AllocWord("s2a.len")
		fl.emit(dis.Inst2(dis.ILENA, dis.FP(srcSlot), dis.FP(lenSlot)))
		// BLTW $arrLen, lenSlot, $panic → if arrLen > len(slice), panic
		panicStr := fl.comp.AllocString("slice to array pointer: length check failed")
		panicSlot := fl.frame.AllocPointer("s2a.panic")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(panicStr), dis.FP(panicSlot)))
		okPC := int32(len(fl.insts)) + 3
		fl.emit(dis.NewInst(dis.IBGEW, dis.FP(lenSlot), dis.Imm(int32(arrLen)), dis.Imm(okPC)))
		fl.emit(dis.Inst{Op: dis.IRAISE, Src: dis.FP(panicSlot), Mid: dis.NoOperand, Dst: dis.NoOperand})
	}

	// In Dis, the slice (array pointer) IS the underlying array pointer.
	// Just copy the reference.
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(srcSlot), dis.FP(dstSlot)))
	return nil
}

// lowerField handles *ssa.Field — direct field extraction from a struct value.
// Unlike FieldAddr (which returns a pointer), Field copies the field value.
func (fl *funcLowerer) lowerField(instr *ssa.Field) error {
	structType := instr.X.Type().Underlying().(*types.Struct)
	fieldOff := int32(0)
	for i := 0; i < instr.Field; i++ {
		dt := GoTypeToDis(structType.Field(i).Type())
		fieldOff += dt.Size
	}

	fieldType := structType.Field(instr.Field).Type()
	fieldDt := GoTypeToDis(fieldType)
	dstSlot := fl.slotOf(instr)

	base, ok := fl.allocBase[instr.X]
	if ok {
		// Stack-allocated struct: field is at base + fieldOff
		srcOff := base + fieldOff
		if fieldDt.IsPtr {
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(srcOff), dis.FP(dstSlot)))
		} else if fieldDt.Size > int32(dis.IBY2WD) {
			// Multi-word (nested struct): copy word-by-word
			for off := int32(0); off < fieldDt.Size; off += int32(dis.IBY2WD) {
				fl.emit(dis.Inst2(dis.IMOVW, dis.FP(srcOff+off), dis.FP(dstSlot+off)))
			}
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(srcOff), dis.FP(dstSlot)))
		}
	} else {
		// Value in a single slot (e.g., tuple result, function return)
		srcSlot := fl.slotOf(instr.X)
		srcOff := srcSlot + fieldOff
		if fieldDt.IsPtr {
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(srcOff), dis.FP(dstSlot)))
		} else if fieldDt.Size > int32(dis.IBY2WD) {
			for off := int32(0); off < fieldDt.Size; off += int32(dis.IBY2WD) {
				fl.emit(dis.Inst2(dis.IMOVW, dis.FP(srcOff+off), dis.FP(dstSlot+off)))
			}
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(srcOff), dis.FP(dstSlot)))
		}
	}
	return nil
}

func (fl *funcLowerer) lowerFieldAddr(instr *ssa.FieldAddr) error {
	// FieldAddr produces a pointer to a field within a struct.
	// instr.X is the struct pointer, instr.Field is the field index.
	structType := instr.X.Type().(*types.Pointer).Elem().Underlying().(*types.Struct)
	fieldOff := int32(0)
	for i := 0; i < instr.Field; i++ {
		dt := GoTypeToDis(structType.Field(i).Type())
		fieldOff += dt.Size
	}

	// Interior pointer slots are AllocWord (not GC-traced).
	// For stack allocs: points into the frame, not the heap.
	// For heap allocs: interior pointer; the base pointer in its
	// GC-traced slot keeps the object alive.
	ptrSlot := fl.frame.AllocWord("faddr:" + instr.Name())
	fl.valueMap[instr] = ptrSlot

	base, ok := fl.allocBase[instr.X]
	if ok {
		// Stack-allocated struct: field is at base + fieldOff in the frame
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(base+fieldOff), dis.FP(ptrSlot)))
	} else {
		// Heap pointer or call result: use indirect addressing.
		// basePtrSlot holds a heap pointer; LEA FPInd computes
		// *(fp+basePtrSlot) + fieldOff = &heapObj[fieldOff]
		basePtrSlot := fl.slotOf(instr.X)
		fl.emit(dis.Inst2(dis.ILEA, dis.FPInd(basePtrSlot, fieldOff), dis.FP(ptrSlot)))
	}
	return nil
}

func (fl *funcLowerer) lowerSlice(instr *ssa.Slice) error {
	xType := instr.X.Type()

	switch xt := xType.Underlying().(type) {
	case *types.Pointer:
		// *[N]T → []T: create Dis array from fixed-size array
		arrType, ok := xt.Elem().Underlying().(*types.Array)
		if !ok {
			return fmt.Errorf("Slice on non-array pointer: %v", xt.Elem())
		}
		return fl.lowerArrayToSlice(instr, arrType)
	case *types.Slice:
		// []T → []T: sub-slicing (SLICEA)
		return fl.lowerSliceSubSlice(instr)
	case *types.Basic:
		if xt.Kind() == types.String {
			return fl.lowerStringSlice(instr)
		}
		return fmt.Errorf("Slice on unsupported basic type: %v", xt)
	default:
		return fmt.Errorf("Slice on unsupported type: %T", xType.Underlying())
	}
}

func (fl *funcLowerer) lowerArrayToSlice(instr *ssa.Slice, arrType *types.Array) error {
	_, isStack := fl.allocBase[instr.X]

	if !isStack {
		// Heap array: already a Dis Array, just copy the pointer
		srcSlot := fl.slotOf(instr.X)
		dstSlot := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(srcSlot), dis.FP(dstSlot)))
		return nil
	}

	// Stack array: create Dis Array via NEWA and copy elements
	elemType := arrType.Elem()
	elemDT := GoTypeToDis(elemType)
	n := int(arrType.Len())
	base := fl.allocBase[instr.X]

	elemTDIdx := fl.makeHeapTypeDesc(elemType)
	dstSlot := fl.slotOf(instr)

	// NEWA length, $elemTD, dst
	fl.emit(dis.NewInst(dis.INEWA, dis.Imm(int32(n)), dis.Imm(int32(elemTDIdx)), dis.FP(dstSlot)))

	for i := 0; i < n; i++ {
		// Get element address in Dis array using INDW
		tempAddr := fl.frame.AllocWord("")
		fl.emit(dis.NewInst(dis.IINDW, dis.FP(dstSlot), dis.FP(tempAddr), dis.Imm(int32(i))))

		// Copy from stack to Dis array element
		srcOff := base + int32(i)*elemDT.Size
		if elemDT.IsPtr {
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(srcOff), dis.FPInd(tempAddr, 0)))
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(srcOff), dis.FPInd(tempAddr, 0)))
		}
	}

	return nil
}

// lowerSliceSubSlice handles s[low:high] on a slice type using SLICEA.
// SLICEA: src=start, mid=end, dst=array (modifies dst in-place)
func (fl *funcLowerer) lowerSliceSubSlice(instr *ssa.Slice) error {
	srcSlot := fl.materialize(instr.X)
	dstSlot := fl.slotOf(instr)

	// Copy source to destination first (SLICEA modifies dst in-place)
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(srcSlot), dis.FP(dstSlot)))

	// Low: default 0
	var lowOp dis.Operand
	if instr.Low != nil {
		lowOp = fl.operandOf(instr.Low)
	} else {
		lowOp = dis.Imm(0)
	}

	// High: default len(src)
	var highOp dis.Operand
	if instr.High != nil {
		highOp = fl.operandOf(instr.High)
	} else {
		lenSlot := fl.frame.AllocWord("slice.len")
		fl.emit(dis.Inst2(dis.ILENA, dis.FP(srcSlot), dis.FP(lenSlot)))
		highOp = dis.FP(lenSlot)
	}

	// SLICEA low, high, dst
	fl.emit(dis.NewInst(dis.ISLICEA, lowOp, highOp, dis.FP(dstSlot)))
	return nil
}

// lowerStringSlice handles s[low:high] on a string type using SLICEC.
// SLICEC: src=start, mid=end, dst=string (modifies dst in-place)
func (fl *funcLowerer) lowerStringSlice(instr *ssa.Slice) error {
	srcSlot := fl.materialize(instr.X)
	dstSlot := fl.slotOf(instr)

	// Copy source to destination first (SLICEC modifies dst in-place)
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(srcSlot), dis.FP(dstSlot)))

	// Low: default 0
	var lowOp dis.Operand
	if instr.Low != nil {
		lowOp = fl.operandOf(instr.Low)
	} else {
		lowOp = dis.Imm(0)
	}

	// High: default len(src)
	var highOp dis.Operand
	if instr.High != nil {
		highOp = fl.operandOf(instr.High)
	} else {
		lenSlot := fl.frame.AllocWord("strslice.len")
		fl.emit(dis.Inst2(dis.ILENC, dis.FP(srcSlot), dis.FP(lenSlot)))
		highOp = dis.FP(lenSlot)
	}

	// SLICEC low, high, dst
	fl.emit(dis.NewInst(dis.ISLICEC, lowOp, highOp, dis.FP(dstSlot)))
	return nil
}

func (fl *funcLowerer) lowerIndexAddr(instr *ssa.IndexAddr) error {
	// IndexAddr produces a pointer to an element within an array or slice.
	// Result is an interior pointer (AllocWord, not GC-traced).
	ptrSlot := fl.frame.AllocWord("iaddr:" + instr.Name())
	fl.valueMap[instr] = ptrSlot

	xType := instr.X.Type()

	switch xt := xType.Underlying().(type) {
	case *types.Pointer:
		// *[N]T — pointer to fixed-size array
		if arrType, ok := xt.Elem().Underlying().(*types.Array); ok {
			return fl.lowerArrayIndexAddr(instr, arrType, ptrSlot)
		}
		return fmt.Errorf("IndexAddr on pointer to non-array: %v", xt.Elem())
	case *types.Slice:
		// []T — Dis array, use INDW for element address
		return fl.lowerSliceIndexAddr(instr, ptrSlot)
	default:
		return fmt.Errorf("IndexAddr on unsupported type: %T (%v)", xType.Underlying(), xType)
	}
}

func (fl *funcLowerer) lowerArrayIndexAddr(instr *ssa.IndexAddr, arrType *types.Array, ptrSlot int32) error {
	base, ok := fl.allocBase[instr.X]
	if ok {
		// Stack-allocated array: elements are consecutive frame slots
		elemSize := GoTypeToDis(arrType.Elem()).Size
		if c, isConst := instr.Index.(*ssa.Const); isConst {
			idx, _ := constant.Int64Val(c.Value)
			off := int32(idx) * elemSize
			fl.emit(dis.Inst2(dis.ILEA, dis.FP(base+off), dis.FP(ptrSlot)))
		} else {
			// Dynamic index: compute address = &FP[base] + index * elemSize
			baseAddr := fl.frame.AllocWord("dynidx.base")
			fl.emit(dis.Inst2(dis.ILEA, dis.FP(base), dis.FP(baseAddr)))
			idxSlot := fl.materialize(instr.Index)
			offSlot := fl.frame.AllocWord("dynidx.off")
			fl.emit(dis.NewInst(dis.IMULW, dis.Imm(elemSize), dis.FP(idxSlot), dis.FP(offSlot)))
			fl.emit(dis.NewInst(dis.IADDW, dis.FP(offSlot), dis.FP(baseAddr), dis.FP(ptrSlot)))
		}
	} else {
		// Heap Dis Array: use INDB for byte, INDX for multi-word structs, INDW otherwise
		arrSlot := fl.slotOf(instr.X)
		idxOp := fl.operandOf(instr.Index)
		indOp := fl.indOpForElem(arrType.Elem())
		fl.emit(dis.NewInst(indOp, dis.FP(arrSlot), dis.FP(ptrSlot), idxOp))
	}
	return nil
}

func (fl *funcLowerer) lowerSliceIndexAddr(instr *ssa.IndexAddr, ptrSlot int32) error {
	// IND{W,B,X}: src=array, mid=resultAddr, dst=index
	// Bounds-checked: panics if index >= len or array is nil
	arrSlot := fl.slotOf(instr.X)
	idxOp := fl.operandOf(instr.Index)

	sliceType := instr.X.Type().Underlying().(*types.Slice)
	indOp := fl.indOpForElem(sliceType.Elem())
	fl.emit(dis.NewInst(indOp, dis.FP(arrSlot), dis.FP(ptrSlot), idxOp))
	return nil
}

// lowerIndex handles *ssa.Index: element access on arrays and strings.
// For strings, uses INDC; for arrays, uses IND{W,B} + load through pointer.
func (fl *funcLowerer) lowerIndex(instr *ssa.Index) error {
	xType := instr.X.Type().Underlying()
	dstSlot := fl.slotOf(instr)

	if basic, ok := xType.(*types.Basic); ok && basic.Kind() == types.String {
		// String indexing: INDC src=string, mid=index, dst=result(WORD)
		strOp := fl.operandOf(instr.X)
		idxOp := fl.operandOf(instr.Index)
		fl.emit(dis.NewInst(dis.IINDC, strOp, idxOp, dis.FP(dstSlot)))
		return nil
	}

	return fmt.Errorf("Index on unsupported type: %T (%v)", xType, xType)
}

// emitFreeVarLoads emits preamble instructions for an inner function to load
// free variables from the closure struct into frame slots.
// Closure struct layout: {funcTag(WORD @0), freevar0(@8), freevar1, ...}
func (fl *funcLowerer) emitFreeVarLoads() {
	off := int32(dis.IBY2WD) // skip function tag at offset 0
	iby2wd := int32(dis.IBY2WD)
	for _, fv := range fl.fn.FreeVars {
		fvSlot := fl.valueMap[fv]
		if _, ok := fv.Type().Underlying().(*types.Interface); ok {
			// Interface free var: load 2 words (tag + value)
			fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(fl.closurePtrSlot, off), dis.FP(fvSlot)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(fl.closurePtrSlot, off+iby2wd), dis.FP(fvSlot+iby2wd)))
			off += 2 * iby2wd
		} else {
			dt := GoTypeToDis(fv.Type())
			if dt.IsPtr {
				fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(fl.closurePtrSlot, off), dis.FP(fvSlot)))
			} else {
				fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(fl.closurePtrSlot, off), dis.FP(fvSlot)))
			}
			off += dt.Size
		}
	}
}

// lowerMakeClosure creates a heap-allocated closure struct containing a function
// tag and captured free variables.
// Layout: {funcTag(WORD @0), freevar0(@8), freevar1, ...}
func (fl *funcLowerer) lowerMakeClosure(instr *ssa.MakeClosure) error {
	innerFn := instr.Fn.(*ssa.Function)
	bindings := instr.Bindings

	// Register this MakeClosure so call sites can resolve the inner function
	fl.comp.registerClosure(instr, innerFn)

	// Allocate a function tag for this inner function
	funcTag := fl.comp.AllocClosureTag(innerFn)

	// Build closure struct: function tag (WORD @0) + free vars starting at offset 8
	iby2wd := int32(dis.IBY2WD)
	closureSize := iby2wd // start with space for function tag
	var ptrOffsets []int
	for _, binding := range bindings {
		dt := GoTypeToDis(binding.Type())
		if dt.IsPtr {
			ptrOffsets = append(ptrOffsets, int(closureSize))
		}
		closureSize += dt.Size
	}

	// closureSize is always >= 8 (at least the function tag)
	td := dis.NewTypeDesc(0, int(closureSize))
	for _, off := range ptrOffsets {
		td.SetPointer(off)
	}
	fl.callTypeDescs = append(fl.callTypeDescs, td)
	closureTDIdx := len(fl.callTypeDescs) - 1

	// NEW closure struct
	dst := fl.slotOf(instr)
	fl.emit(dis.Inst2(dis.INEW, dis.Imm(int32(closureTDIdx)), dis.FP(dst)))

	// Store function tag at offset 0
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(funcTag), dis.FPInd(dst, 0)))

	// Store free var values starting at offset 8
	off := iby2wd
	for _, binding := range bindings {
		if _, ok := binding.Type().Underlying().(*types.Interface); ok {
			// Interface binding: store 2 words (tag + value)
			srcSlot := fl.slotOf(binding)
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(srcSlot), dis.FPInd(dst, off)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(srcSlot+iby2wd), dis.FPInd(dst, off+iby2wd)))
			off += 2 * iby2wd
		} else {
			src := fl.operandOf(binding)
			dt := GoTypeToDis(binding.Type())
			if dt.IsPtr {
				fl.emit(dis.Inst2(dis.IMOVP, src, dis.FPInd(dst, off)))
			} else {
				fl.emit(dis.Inst2(dis.IMOVW, src, dis.FPInd(dst, off)))
			}
			off += dt.Size
		}
	}

	return nil
}

// lowerClosureCall emits a call through a closure. If the target can be
// statically resolved, emits a direct call. Otherwise, uses function tags
// in the closure struct to dispatch dynamically via a BEQW chain.
func (fl *funcLowerer) lowerClosureCall(instr *ssa.Call) error {
	call := instr.Call

	// Try static resolution first
	innerFn := fl.comp.resolveClosureTarget(call.Value)
	if innerFn != nil {
		return fl.emitStaticClosureCall(instr, innerFn)
	}

	// Dynamic dispatch: read function tag from closure and dispatch
	return fl.emitDynamicClosureCall(instr)
}

// emitStaticClosureCall emits a statically-resolved call through a closure.
func (fl *funcLowerer) emitStaticClosureCall(instr *ssa.Call, innerFn *ssa.Function) error {
	call := instr.Call
	closureSlot := fl.slotOf(call.Value)

	// Set up callee frame (NOT a GC pointer)
	callFrame := fl.frame.AllocWord("")

	// IFRAME with inner function's TD (placeholder, patched later)
	iframeIdx := len(fl.insts)
	fl.emit(dis.Inst2(dis.IFRAME, dis.Imm(0), dis.FP(callFrame)))

	// Pass closure pointer as hidden first param at MaxTemp+0
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(closureSlot), dis.FPInd(callFrame, int32(dis.MaxTemp))))

	// Pass actual args starting at MaxTemp+8 (after closure pointer)
	iby2wd := int32(dis.IBY2WD)
	calleeOff := int32(dis.MaxTemp) + iby2wd
	for _, arg := range call.Args {
		argOff := fl.materialize(arg)
		if _, ok := arg.Type().Underlying().(*types.Interface); ok {
			// Interface arg: copy 2 words (tag + value)
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(argOff), dis.FPInd(callFrame, calleeOff)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(argOff+iby2wd), dis.FPInd(callFrame, calleeOff+iby2wd)))
			calleeOff += 2 * iby2wd
		} else {
			dt := GoTypeToDis(arg.Type())
			if dt.IsPtr {
				fl.emit(dis.Inst2(dis.IMOVP, dis.FP(argOff), dis.FPInd(callFrame, calleeOff)))
			} else {
				fl.emit(dis.Inst2(dis.IMOVW, dis.FP(argOff), dis.FPInd(callFrame, calleeOff)))
			}
			calleeOff += dt.Size
		}
	}

	// Set up REGRET if function returns a value
	sig := call.Value.Type().Underlying().(*types.Signature)
	if sig.Results().Len() > 0 {
		retSlot := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(retSlot), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))
	}

	// CALL with direct PC (placeholder, patched later)
	icallIdx := len(fl.insts)
	fl.emit(dis.Inst2(dis.ICALL, dis.FP(callFrame), dis.Imm(0)))

	// Record patches — same as direct calls
	fl.funcCallPatches = append(fl.funcCallPatches,
		funcCallPatch{instIdx: iframeIdx, callee: innerFn, patchKind: patchIFRAME},
		funcCallPatch{instIdx: icallIdx, callee: innerFn, patchKind: patchICALL},
	)

	return nil
}

// emitDynamicClosureCall emits a dispatch chain that reads the function tag
// from the closure struct and branches to the matching inner function.
func (fl *funcLowerer) emitDynamicClosureCall(instr *ssa.Call) error {
	call := instr.Call
	closureSlot := fl.slotOf(call.Value)

	// Read function tag from closure struct offset 0
	tagSlot := fl.frame.AllocWord("dyncall.tag")
	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(closureSlot, 0), dis.FP(tagSlot)))

	// Find all candidate inner functions matching the call signature
	callSig := call.Value.Type().Underlying().(*types.Signature)
	type candidate struct {
		tag int32
		fn  *ssa.Function
	}
	var candidates []candidate
	for fn, tag := range fl.comp.closureFuncTags {
		if closureSignaturesMatch(fn, callSig) {
			candidates = append(candidates, candidate{tag, fn})
		}
	}

	if len(candidates) == 0 {
		return fmt.Errorf("no closure candidates found for dynamic call %v (sig: %v)", call.Value, callSig)
	}

	// Sort candidates by tag for deterministic output
	sort.Slice(candidates, func(i, j int) bool {
		return candidates[i].tag < candidates[j].tag
	})

	iby2wd := int32(dis.IBY2WD)
	sig := call.Value.Type().Underlying().(*types.Signature)

	// Emit dispatch chain: for each candidate, BEQW tag → call
	var doneJmps []int // indices of JMP instructions to patch to done
	for _, cand := range candidates {
		// BEQW tagSlot, $candTag, $callTarget (next instruction after this)
		// If NOT equal, fall through to next candidate check
		beqwIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.FP(tagSlot), dis.Imm(cand.tag), dis.Imm(0)))

		// Skip to next candidate if not matched
		skipIdx := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0))) // patched to next candidate

		// Call target:
		callPC := int32(len(fl.insts))
		fl.insts[beqwIdx].Dst = dis.Imm(callPC)

		// IFRAME + marshal args + CALL
		callFrame := fl.frame.AllocWord("")
		iframeIdx := len(fl.insts)
		fl.emit(dis.Inst2(dis.IFRAME, dis.Imm(0), dis.FP(callFrame)))

		// Determine calling convention based on whether the candidate is a closure
		isClosure := len(cand.fn.FreeVars) > 0 || cand.fn.Signature.Recv() != nil
		var calleeOff int32
		if isClosure {
			// Closure: pass closure pointer as hidden first param
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(closureSlot), dis.FPInd(callFrame, int32(dis.MaxTemp))))
			calleeOff = int32(dis.MaxTemp) + iby2wd
		} else {
			// Plain function: no hidden param, args start at MaxTemp
			calleeOff = int32(dis.MaxTemp)
		}

		// Marshal args
		for _, arg := range call.Args {
			argOff := fl.materialize(arg)
			if _, ok := arg.Type().Underlying().(*types.Interface); ok {
				fl.emit(dis.Inst2(dis.IMOVW, dis.FP(argOff), dis.FPInd(callFrame, calleeOff)))
				fl.emit(dis.Inst2(dis.IMOVW, dis.FP(argOff+iby2wd), dis.FPInd(callFrame, calleeOff+iby2wd)))
				calleeOff += 2 * iby2wd
			} else {
				dt := GoTypeToDis(arg.Type())
				if dt.IsPtr {
					fl.emit(dis.Inst2(dis.IMOVP, dis.FP(argOff), dis.FPInd(callFrame, calleeOff)))
				} else {
					fl.emit(dis.Inst2(dis.IMOVW, dis.FP(argOff), dis.FPInd(callFrame, calleeOff)))
				}
				calleeOff += dt.Size
			}
		}

		// Set up REGRET if function returns a value
		if sig.Results().Len() > 0 {
			retSlot := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.ILEA, dis.FP(retSlot), dis.FPInd(callFrame, int32(dis.REGRET*dis.IBY2WD))))
		}

		// CALL
		icallIdx := len(fl.insts)
		fl.emit(dis.Inst2(dis.ICALL, dis.FP(callFrame), dis.Imm(0)))

		fl.funcCallPatches = append(fl.funcCallPatches,
			funcCallPatch{instIdx: iframeIdx, callee: cand.fn, patchKind: patchIFRAME},
			funcCallPatch{instIdx: icallIdx, callee: cand.fn, patchKind: patchICALL},
		)

		// JMP to done
		doneJmps = append(doneJmps, len(fl.insts))
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

		// Patch skip to next candidate
		fl.insts[skipIdx].Dst = dis.Imm(int32(len(fl.insts)))
	}

	// Fallthrough: raise "unknown closure tag" (unreachable in correct programs)
	panicStr := fl.comp.AllocString("unknown closure tag")
	panicSlot := fl.frame.AllocPointer("dyncall.panic")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(panicStr), dis.FP(panicSlot)))
	fl.emit(dis.Inst{Op: dis.IRAISE, Src: dis.FP(panicSlot), Mid: dis.NoOperand, Dst: dis.NoOperand})

	// Patch all done jumps
	donePC := int32(len(fl.insts))
	for _, idx := range doneJmps {
		fl.insts[idx].Dst = dis.Imm(donePC)
	}

	return nil
}

// ============================================================
// Map operations
//
// Go maps are lowered to a heap-allocated ADT with parallel arrays:
//   offset 0:  PTR  keys array
//   offset 8:  PTR  values array
//   offset 16: WORD count
//
// Operations use linear scan (O(n) per lookup/update/delete).
// ============================================================

// lowerMakeMap creates a new empty map.
func (fl *funcLowerer) lowerMakeMap(instr *ssa.MakeMap) error {
	mapTDIdx := fl.makeMapTD()
	dst := fl.slotOf(instr)
	fl.emit(dis.Inst2(dis.INEW, dis.Imm(int32(mapTDIdx)), dis.FP(dst)))
	// Initialize pointer fields to H (-1) since NEW memsets to 0.
	// SLICELA treats 0 as a valid pointer and crashes; it only skips H.
	// Use MOVW (not MOVP) to avoid destroy(0) on the freshly zeroed slots.
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FPInd(dst, 0)))  // keys = H
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FPInd(dst, 8)))  // values = H
	// count stays at 0
	return nil
}

// lowerMapUpdate inserts or updates a key-value pair in a map.
// Flow: scan for existing key → found: update value, done
//                              → not found: grow arrays, append, done
func (fl *funcLowerer) lowerMapUpdate(instr *ssa.MapUpdate) error {
	mapSlot := fl.slotOf(instr.Map)
	keySlot := fl.materialize(instr.Key)
	valSlot := fl.materialize(instr.Value)

	mapType := instr.Map.Type().Underlying().(*types.Map)
	keyType := mapType.Key()
	valType := mapType.Elem()

	// Allocate temps. Pointer temps are initialized to H via MOVW to avoid
	// destroy(0) crash on frame free if a code path doesn't write them.
	cnt := fl.frame.AllocWord("mu.cnt")
	idx := fl.frame.AllocWord("mu.idx")
	keysArr := fl.allocPtrTemp("mu.keys")
	valsArr := fl.allocPtrTemp("mu.vals")
	tmpPtr := fl.frame.AllocWord("mu.ptr") // interior pointer, non-GC
	tmpKey := fl.allocMapKeyTemp(keyType, "mu.tmpk")
	newCnt := fl.frame.AllocWord("mu.ncnt")
	newKeys := fl.allocPtrTemp("mu.nkeys")
	newVals := fl.allocPtrTemp("mu.nvals")

	// Load count
	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(mapSlot, 16), dis.FP(cnt)))

	// if cnt == 0, skip scan → goto grow
	skipScanIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(cnt), dis.Imm(0), dis.Imm(0)))

	// Load keys array for scanning
	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(mapSlot, 0), dis.FP(keysArr)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(idx)))

	// Scan loop
	loopPC := int32(len(fl.insts))
	loopEndIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(idx), dis.FP(cnt), dis.Imm(0)))

	// Load keys[idx]
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(keysArr), dis.FP(tmpPtr), dis.FP(idx)))
	fl.emitLoadThrough(tmpKey, tmpPtr, keyType)

	// Compare: if keys[idx] == target key, goto found
	foundIdx := len(fl.insts)
	fl.emit(dis.NewInst(fl.mapKeyBranchEq(keyType), dis.FP(tmpKey), dis.FP(keySlot), dis.Imm(0)))

	// idx++, loop back
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(idx), dis.FP(idx)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// === found: update value at idx ===
	foundPC := int32(len(fl.insts))
	fl.insts[foundIdx].Dst = dis.Imm(foundPC)

	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(mapSlot, 8), dis.FP(valsArr)))
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(valsArr), dis.FP(tmpPtr), dis.FP(idx)))
	fl.emitStoreThrough(valSlot, tmpPtr, valType)

	doneJmp := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// === grow: append new entry ===
	growPC := int32(len(fl.insts))
	fl.insts[skipScanIdx].Dst = dis.Imm(growPC)
	fl.insts[loopEndIdx].Dst = dis.Imm(growPC)

	// newCnt = cnt + 1
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(cnt), dis.FP(newCnt)))

	// New keys array, copy old (SLICELA skips if source is H), store new key
	keyTDIdx := fl.makeHeapTypeDesc(keyType)
	fl.emit(dis.NewInst(dis.INEWA, dis.FP(newCnt), dis.Imm(int32(keyTDIdx)), dis.FP(newKeys)))
	fl.emit(dis.NewInst(dis.ISLICELA, dis.FPInd(mapSlot, 0), dis.Imm(0), dis.FP(newKeys)))
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(newKeys), dis.FP(tmpPtr), dis.FP(cnt)))
	fl.emitStoreThrough(keySlot, tmpPtr, keyType)

	// New values array, copy old, store new value
	valTDIdx := fl.makeHeapTypeDesc(valType)
	fl.emit(dis.NewInst(dis.INEWA, dis.FP(newCnt), dis.Imm(int32(valTDIdx)), dis.FP(newVals)))
	fl.emit(dis.NewInst(dis.ISLICELA, dis.FPInd(mapSlot, 8), dis.Imm(0), dis.FP(newVals)))
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(newVals), dis.FP(tmpPtr), dis.FP(cnt)))
	fl.emitStoreThrough(valSlot, tmpPtr, valType)

	// Update map struct
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(newKeys), dis.FPInd(mapSlot, 0)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(newVals), dis.FPInd(mapSlot, 8)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(newCnt), dis.FPInd(mapSlot, 16)))

	// === done ===
	donePC := int32(len(fl.insts))
	fl.insts[doneJmp].Dst = dis.Imm(donePC)

	return nil
}

// lowerLookup handles map key lookup and string indexing.
func (fl *funcLowerer) lowerLookup(instr *ssa.Lookup) error {
	switch instr.X.Type().Underlying().(type) {
	case *types.Map:
		return fl.lowerMapLookup(instr)
	default:
		// String indexing: s[i] → byte value
		return fl.lowerStringIndex(instr)
	}
}

// lowerStringIndex handles s[i] on a string using INDC.
// INDC: src=string, mid=index(WORD), dst=result(WORD)
func (fl *funcLowerer) lowerStringIndex(instr *ssa.Lookup) error {
	strOp := fl.operandOf(instr.X)
	idxOp := fl.operandOf(instr.Index)
	dstSlot := fl.slotOf(instr)

	// INDC string, index, result
	fl.emit(dis.NewInst(dis.IINDC, strOp, idxOp, dis.FP(dstSlot)))
	return nil
}

// lowerMapLookup scans the parallel key array for a match and returns the value.
// If CommaOk, returns (value, bool) tuple; otherwise just the value (zero if missing).
func (fl *funcLowerer) lowerMapLookup(instr *ssa.Lookup) error {
	mapSlot := fl.slotOf(instr.X)
	keySlot := fl.materialize(instr.Index)

	mapType := instr.X.Type().Underlying().(*types.Map)
	keyType := mapType.Key()
	valType := mapType.Elem()

	// Result slots
	var valDst, okDst int32
	if instr.CommaOk {
		tupleBase := fl.slotOf(instr)
		valDst = tupleBase
		okDst = tupleBase + int32(dis.IBY2WD)
	} else {
		valDst = fl.slotOf(instr)
	}

	// Initialize result: value = 0, ok = false
	valDT := GoTypeToDis(valType)
	if valDT.IsPtr {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(valDst))) // H for pointer zero-val
	} else {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(valDst)))
	}
	if instr.CommaOk {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(okDst)))
	}

	// Temps
	cnt := fl.frame.AllocWord("lu.cnt")
	idx := fl.frame.AllocWord("lu.idx")
	keysArr := fl.allocPtrTemp("lu.keys")
	valsArr := fl.allocPtrTemp("lu.vals")
	tmpPtr := fl.frame.AllocWord("lu.ptr")
	tmpKey := fl.allocMapKeyTemp(keyType, "lu.tmpk")

	// Load count
	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(mapSlot, 16), dis.FP(cnt)))

	// if cnt == 0, goto done (empty map)
	skipIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(cnt), dis.Imm(0), dis.Imm(0)))

	// Load keys array
	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(mapSlot, 0), dis.FP(keysArr)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(idx)))

	// Scan loop
	loopPC := int32(len(fl.insts))
	loopEndIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(idx), dis.FP(cnt), dis.Imm(0)))

	// Load keys[idx]
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(keysArr), dis.FP(tmpPtr), dis.FP(idx)))
	fl.emitLoadThrough(tmpKey, tmpPtr, keyType)

	// Compare
	foundIdx := len(fl.insts)
	fl.emit(dis.NewInst(fl.mapKeyBranchEq(keyType), dis.FP(tmpKey), dis.FP(keySlot), dis.Imm(0)))

	// idx++, loop back
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(idx), dis.FP(idx)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// === found: load value ===
	foundPC := int32(len(fl.insts))
	fl.insts[foundIdx].Dst = dis.Imm(foundPC)

	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(mapSlot, 8), dis.FP(valsArr)))
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(valsArr), dis.FP(tmpPtr), dis.FP(idx)))
	fl.emitLoadThrough(valDst, tmpPtr, valType)

	if instr.CommaOk {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(okDst)))
	}

	// === done ===
	donePC := int32(len(fl.insts))
	fl.insts[skipIdx].Dst = dis.Imm(donePC)
	fl.insts[loopEndIdx].Dst = dis.Imm(donePC)

	return nil
}

// lowerMapDelete removes a key from a map using swap-with-last strategy.
func (fl *funcLowerer) lowerMapDelete(instr *ssa.Call) error {
	mapArg := instr.Call.Args[0]
	keyArg := instr.Call.Args[1]
	mapSlot := fl.slotOf(mapArg)
	keySlot := fl.materialize(keyArg)

	mapType := mapArg.Type().Underlying().(*types.Map)
	keyType := mapType.Key()
	valType := mapType.Elem()

	// Temps
	cnt := fl.frame.AllocWord("dl.cnt")
	idx := fl.frame.AllocWord("dl.idx")
	keysArr := fl.allocPtrTemp("dl.keys")
	valsArr := fl.allocPtrTemp("dl.vals")
	tmpPtr := fl.frame.AllocWord("dl.ptr")
	tmpPtr2 := fl.frame.AllocWord("dl.ptr2")
	tmpKey := fl.allocMapKeyTemp(keyType, "dl.tmpk")
	lastIdx := fl.frame.AllocWord("dl.last")

	// Load count
	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(mapSlot, 16), dis.FP(cnt)))

	// if cnt == 0, nothing to delete
	skipIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(cnt), dis.Imm(0), dis.Imm(0)))

	// Load arrays
	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(mapSlot, 0), dis.FP(keysArr)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(mapSlot, 8), dis.FP(valsArr)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(idx)))

	// Scan
	loopPC := int32(len(fl.insts))
	loopEndIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(idx), dis.FP(cnt), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IINDW, dis.FP(keysArr), dis.FP(tmpPtr), dis.FP(idx)))
	fl.emitLoadThrough(tmpKey, tmpPtr, keyType)

	foundIdx := len(fl.insts)
	fl.emit(dis.NewInst(fl.mapKeyBranchEq(keyType), dis.FP(tmpKey), dis.FP(keySlot), dis.Imm(0)))

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(idx), dis.FP(idx)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	// === found: swap with last, decrement count ===
	foundPC := int32(len(fl.insts))
	fl.insts[foundIdx].Dst = dis.Imm(foundPC)

	// lastIdx = cnt - 1
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(cnt), dis.FP(lastIdx)))

	// if idx == lastIdx, skip swap (already at end)
	skipSwapIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(idx), dis.FP(lastIdx), dis.Imm(0)))

	// keys[idx] = keys[lastIdx]
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(keysArr), dis.FP(tmpPtr2), dis.FP(lastIdx)))
	fl.emitLoadThrough(tmpKey, tmpPtr2, keyType)
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(keysArr), dis.FP(tmpPtr), dis.FP(idx)))
	fl.emitStoreThrough(tmpKey, tmpPtr, keyType)

	// values[idx] = values[lastIdx]
	tmpVal := fl.frame.AllocWord("dl.tmpv")
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(valsArr), dis.FP(tmpPtr2), dis.FP(lastIdx)))
	fl.emitLoadThrough(tmpVal, tmpPtr2, valType)
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(valsArr), dis.FP(tmpPtr), dis.FP(idx)))
	fl.emitStoreThrough(tmpVal, tmpPtr, valType)

	// skip swap target
	skipSwapPC := int32(len(fl.insts))
	fl.insts[skipSwapIdx].Dst = dis.Imm(skipSwapPC)

	// count--
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(lastIdx), dis.FPInd(mapSlot, 16)))

	// === done ===
	donePC := int32(len(fl.insts))
	fl.insts[skipIdx].Dst = dis.Imm(donePC)
	fl.insts[loopEndIdx].Dst = dis.Imm(donePC)

	return nil
}

// emitDeferredMapDelete handles defer delete(m, k) with raw SSA values.
func (fl *funcLowerer) emitDeferredMapDelete(mapVal, keyVal ssa.Value) error {
	mapSlot := fl.materialize(mapVal)
	keySlot := fl.materialize(keyVal)

	mapType := mapVal.Type().Underlying().(*types.Map)
	keyType := mapType.Key()
	valType := mapType.Elem()

	cnt := fl.frame.AllocWord("ddl.cnt")
	idx := fl.frame.AllocWord("ddl.idx")
	keysArr := fl.allocPtrTemp("ddl.keys")
	valsArr := fl.allocPtrTemp("ddl.vals")
	tmpPtr := fl.frame.AllocWord("ddl.ptr")
	tmpPtr2 := fl.frame.AllocWord("ddl.ptr2")
	tmpKey := fl.allocMapKeyTemp(keyType, "ddl.tmpk")
	lastIdx := fl.frame.AllocWord("ddl.last")

	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(mapSlot, 16), dis.FP(cnt)))
	skipIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(cnt), dis.Imm(0), dis.Imm(0)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(mapSlot, 0), dis.FP(keysArr)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(mapSlot, 8), dis.FP(valsArr)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(idx)))

	loopPC := int32(len(fl.insts))
	loopEndIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(idx), dis.FP(cnt), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(keysArr), dis.FP(tmpPtr), dis.FP(idx)))
	fl.emitLoadThrough(tmpKey, tmpPtr, keyType)
	foundIdx := len(fl.insts)
	fl.emit(dis.NewInst(fl.mapKeyBranchEq(keyType), dis.FP(tmpKey), dis.FP(keySlot), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(idx), dis.FP(idx)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	foundPC := int32(len(fl.insts))
	fl.insts[foundIdx].Dst = dis.Imm(foundPC)
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(cnt), dis.FP(lastIdx)))
	skipSwapIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(idx), dis.FP(lastIdx), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(keysArr), dis.FP(tmpPtr2), dis.FP(lastIdx)))
	fl.emitLoadThrough(tmpKey, tmpPtr2, keyType)
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(keysArr), dis.FP(tmpPtr), dis.FP(idx)))
	fl.emitStoreThrough(tmpKey, tmpPtr, keyType)
	tmpVal := fl.frame.AllocWord("ddl.tmpv")
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(valsArr), dis.FP(tmpPtr2), dis.FP(lastIdx)))
	fl.emitLoadThrough(tmpVal, tmpPtr2, valType)
	fl.emit(dis.NewInst(dis.IINDW, dis.FP(valsArr), dis.FP(tmpPtr), dis.FP(idx)))
	fl.emitStoreThrough(tmpVal, tmpPtr, valType)

	skipSwapPC := int32(len(fl.insts))
	fl.insts[skipSwapIdx].Dst = dis.Imm(skipSwapPC)
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(lastIdx), dis.FPInd(mapSlot, 16)))

	donePC := int32(len(fl.insts))
	fl.insts[skipIdx].Dst = dis.Imm(donePC)
	fl.insts[loopEndIdx].Dst = dis.Imm(donePC)
	return nil
}

// lowerRange initializes a map, string, or channel iterator.
// For maps/strings: the iterator is an index (WORD) starting at 0.
// For channels: the iterator holds a copy of the channel wrapper pointer (WORD).
func (fl *funcLowerer) lowerRange(instr *ssa.Range) error {
	iterSlot := fl.slotOf(instr)
	if _, ok := instr.X.Type().Underlying().(*types.Chan); ok {
		// Channel range: copy the channel wrapper pointer into the iterator slot.
		// Use MOVW (not MOVP) — the original ref keeps it alive.
		chanSlot := fl.materialize(instr.X)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(chanSlot), dis.FP(iterSlot)))
		return nil
	}
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(iterSlot)))
	return nil
}

// lowerNext advances a map/string/channel iterator and returns (ok, key, value).
func (fl *funcLowerer) lowerNext(instr *ssa.Next) error {
	if instr.IsString {
		return fl.lowerStringNext(instr)
	}

	rangeInstr := instr.Iter.(*ssa.Range)

	// Channel range: for v := range ch
	if _, ok := rangeInstr.X.Type().Underlying().(*types.Chan); ok {
		return fl.lowerChanNext(instr)
	}

	mapSlot := fl.slotOf(rangeInstr.X)
	iterSlot := fl.slotOf(rangeInstr)

	mapType := rangeInstr.X.Type().Underlying().(*types.Map)
	keyType := mapType.Key()
	valType := mapType.Elem()

	// Result tuple: (ok WORD @0, key @8, value @16+)
	tupleBase := fl.slotOf(instr)
	okSlot := tupleBase
	keyDT := GoTypeToDis(keyType)
	keySlot := tupleBase + int32(dis.IBY2WD)
	valSlot := keySlot + keyDT.Size

	// Load count from map
	cnt := fl.frame.AllocWord("next.cnt")
	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(mapSlot, 16), dis.FP(cnt)))

	// if index < count goto hasMore
	hasMoreIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, dis.FP(iterSlot), dis.FP(cnt), dis.Imm(0)))

	// exhausted: ok = false, jump to end
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(okSlot)))
	endIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// hasMore:
	fl.insts[hasMoreIdx].Dst = dis.Imm(int32(len(fl.insts)))

	tmpPtr := fl.frame.AllocWord("next.ptr")

	// Only load key if its tuple slot type is valid (not _ blank identifier).
	// When the key is unused, SSA gives it types.Invalid which allocates as WORD,
	// but the actual map key may be a pointer type. MOVP into a WORD slot
	// whose initial value is 0 (not H) crashes on destroy(0).
	tup := instr.Type().(*types.Tuple)
	if tup.At(1).Type() != types.Typ[types.Invalid] {
		keysArr := fl.frame.AllocWord("next.keys")
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(mapSlot, 0), dis.FP(keysArr)))
		fl.emit(dis.NewInst(dis.IINDW, dis.FP(keysArr), dis.FP(tmpPtr), dis.FP(iterSlot)))
		fl.emitLoadThrough(keySlot, tmpPtr, keyType)
	}

	// Only load value if its tuple slot type is valid.
	if tup.At(2).Type() != types.Typ[types.Invalid] {
		valsArr := fl.frame.AllocWord("next.vals")
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(mapSlot, 8), dis.FP(valsArr)))
		fl.emit(dis.NewInst(dis.IINDW, dis.FP(valsArr), dis.FP(tmpPtr), dis.FP(iterSlot)))
		fl.emitLoadThrough(valSlot, tmpPtr, valType)
	}

	// ok = true
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(okSlot)))

	// index++
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(iterSlot), dis.FP(iterSlot)))

	// end:
	fl.insts[endIdx].Dst = dis.Imm(int32(len(fl.insts)))
	return nil
}

// lowerStringNext advances a string iterator and returns (ok, index, rune).
func (fl *funcLowerer) lowerStringNext(instr *ssa.Next) error {
	rangeInstr := instr.Iter.(*ssa.Range)
	strSlot := fl.materialize(rangeInstr.X)
	iterSlot := fl.slotOf(rangeInstr)

	// Result tuple: (ok WORD @0, index WORD @8, rune WORD @16)
	tupleBase := fl.slotOf(instr)
	okSlot := tupleBase
	idxSlot := tupleBase + int32(dis.IBY2WD)
	runeSlot := idxSlot + int32(dis.IBY2WD)

	// Get string length
	lenSlot := fl.frame.AllocWord("strnext.len")
	fl.emit(dis.Inst2(dis.ILENC, dis.FP(strSlot), dis.FP(lenSlot)))

	// if index < length goto hasMore
	hasMoreIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBLTW, dis.FP(iterSlot), dis.FP(lenSlot), dis.Imm(0)))

	// exhausted: ok = false, jump to end
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(okSlot)))
	endIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))

	// hasMore:
	fl.insts[hasMoreIdx].Dst = dis.Imm(int32(len(fl.insts)))

	tup := instr.Type().(*types.Tuple)

	// Load index (byte position) if used
	if tup.At(1).Type() != types.Typ[types.Invalid] {
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(iterSlot), dis.FP(idxSlot)))
	}

	// Load rune at current index if used
	if tup.At(2).Type() != types.Typ[types.Invalid] {
		fl.emit(dis.NewInst(dis.IINDC, dis.FP(strSlot), dis.FP(iterSlot), dis.FP(runeSlot)))
	}

	// ok = true
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(okSlot)))

	// index++ (advance by 1 character)
	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(iterSlot), dis.FP(iterSlot)))

	// end:
	fl.insts[endIdx].Dst = dis.Imm(int32(len(fl.insts)))
	return nil
}

// lowerChanNext advances a channel range iterator.
// Channel range returns a 2-element tuple: (ok bool, value T).
// Semantics: recv from channel; if closed and empty, ok=false and loop exits.
func (fl *funcLowerer) lowerChanNext(instr *ssa.Next) error {
	iby2wd := int32(dis.IBY2WD)

	rangeInstr := instr.Iter.(*ssa.Range)
	chanSlot := fl.slotOf(rangeInstr) // iterator slot holds channel wrapper copy

	chanType := rangeInstr.X.Type().Underlying().(*types.Chan)
	elemType := chanType.Elem()
	elemDt := GoTypeToDis(elemType)

	// Result tuple: (ok WORD @0, value @8)
	tupleBase := fl.slotOf(instr)
	okSlot := tupleBase
	valSlot := tupleBase + iby2wd

	// Extract raw channel from wrapper
	tmpRaw := fl.allocPtrTemp("chanrange.raw")
	fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(chanSlot, 0), dis.FP(tmpRaw)))

	// Read closed flag
	tmpFlag := fl.frame.AllocWord("chanrange.flag")
	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(chanSlot, 8), dis.FP(tmpFlag)))

	// BEQW flag, $0, $openPath → if not closed, do blocking recv
	beqwIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(tmpFlag), dis.Imm(0), dis.Imm(0))) // patched

	// === Closed path: try non-blocking receive to drain buffer ===
	altBase := fl.frame.AllocWord("chanrange.alt.nsend")
	fl.frame.AllocWord("chanrange.alt.nrecv")
	fl.frame.AllocPointer("chanrange.alt.ch")
	fl.frame.AllocWord("chanrange.alt.ptr")

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(altBase)))              // nsend = 0
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(altBase+iby2wd)))       // nrecv = 1
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmpRaw), dis.FP(altBase+2*iby2wd))) // channel
	fl.emit(dis.Inst2(dis.ILEA, dis.FP(valSlot), dis.FP(altBase+3*iby2wd))) // &valSlot

	// NBALT returns index: 0 = got value, 1 = nothing ready
	nbaltIdx := fl.frame.AllocWord("chanrange.nbalt.idx")
	fl.emit(dis.Inst2(dis.INBALT, dis.FP(altBase), dis.FP(nbaltIdx)))

	// BEQW nbaltIdx, $0, $gotValue
	beqwGotIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(nbaltIdx), dis.Imm(0), dis.Imm(0))) // patched

	// Empty + closed: ok = false, zero value
	if elemDt.IsPtr {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(valSlot))) // H
	} else {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(valSlot)))
	}
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(okSlot))) // ok = false
	emptyJmpIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0))) // → done

	// gotValue: value already written to valSlot by NBALT.
	// Check buffered value count to distinguish real values from phantom zeros.
	gotValuePC := int32(len(fl.insts))
	fl.insts[beqwGotIdx].Dst = dis.Imm(gotValuePC)
	// Read buffered count from wrapper[24]
	tmpCnt := fl.frame.AllocWord("chanrange.cnt")
	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(chanSlot, 24), dis.FP(tmpCnt)))
	// If count == 0: phantom zero → ok=false
	beqwPhantomIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(tmpCnt), dis.Imm(0), dis.Imm(0))) // patched
	// Real value: ok=true, decrement count
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(okSlot)))
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(tmpCnt), dis.FP(tmpCnt)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(tmpCnt), dis.FPInd(chanSlot, 24)))
	closedRealJmpIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0))) // → done
	// Phantom zero: ok=false, zero value
	phantomPC := int32(len(fl.insts))
	fl.insts[beqwPhantomIdx].Dst = dis.Imm(phantomPC)
	if elemDt.IsPtr {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(valSlot))) // H
	} else {
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(valSlot)))
	}
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(okSlot)))
	closedPhantomJmpIdx := len(fl.insts)
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0))) // → done

	// === Open path: blocking receive ===
	openPC := int32(len(fl.insts))
	fl.insts[beqwIdx].Dst = dis.Imm(openPC)

	fl.emit(dis.Inst2(dis.IRECV, dis.FP(tmpRaw), dis.FP(valSlot)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(okSlot))) // ok = true
	// Decrement buffered count
	tmpCnt2 := fl.frame.AllocWord("chanrange.cnt2")
	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(chanSlot, 24), dis.FP(tmpCnt2)))
	fl.emit(dis.NewInst(dis.ISUBW, dis.Imm(1), dis.FP(tmpCnt2), dis.FP(tmpCnt2)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(tmpCnt2), dis.FPInd(chanSlot, 24)))

	// done:
	donePC := int32(len(fl.insts))
	fl.insts[emptyJmpIdx].Dst = dis.Imm(donePC)
	fl.insts[closedRealJmpIdx].Dst = dis.Imm(donePC)
	fl.insts[closedPhantomJmpIdx].Dst = dis.Imm(donePC)

	return nil
}

// makeMapTD creates a type descriptor for the map ADT: {keys PTR, values PTR, count WORD}.
func (fl *funcLowerer) makeMapTD() int {
	td := dis.NewTypeDesc(0, 24) // 3 * 8 bytes
	td.SetPointer(0)             // keys
	td.SetPointer(8)             // values
	fl.callTypeDescs = append(fl.callTypeDescs, td)
	return len(fl.callTypeDescs) - 1
}

// makeChanWrapperTD creates a type descriptor for the channel wrapper ADT:
//
//	offset 0:  PTR  raw Channel* (GC-traced)
//	offset 8:  WORD closed flag  (0=open, 1=closed)
//	offset 16: WORD buffer capacity (set at make time)
//	offset 24: WORD buffered value count (incremented on send, decremented on recv)
//
// Total size: 32 bytes. The wrapper is heap-allocated so the closed flag
// is shared across all goroutines holding a reference to the same channel.
func (fl *funcLowerer) makeChanWrapperTD() int {
	td := dis.NewTypeDesc(0, 32)
	td.SetPointer(0) // raw channel is GC-traced
	fl.callTypeDescs = append(fl.callTypeDescs, td)
	return len(fl.callTypeDescs) - 1
}

// allocPtrTemp allocates a GC-traced pointer slot and initializes it to H (-1)
// using MOVW (not MOVP) to avoid destroy(0) on the zeroed frame slot.
func (fl *funcLowerer) allocPtrTemp(name string) int32 {
	slot := fl.frame.AllocPointer(name)
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(slot)))
	return slot
}

// allocMapKeyTemp allocates a temp slot for a map key, with H init for pointer types.
func (fl *funcLowerer) allocMapKeyTemp(keyType types.Type, name string) int32 {
	dt := GoTypeToDis(keyType)
	if dt.IsPtr {
		return fl.allocPtrTemp(name)
	}
	return fl.frame.AllocWord(name)
}

// mapKeyBranchEq returns the branch-if-equal opcode for the given key type.
func (fl *funcLowerer) mapKeyBranchEq(keyType types.Type) dis.Op {
	if isStringType(keyType.Underlying()) {
		return dis.IBEQC
	}
	return dis.IBEQW
}

// emitLoadThrough loads a value from memory at *ptrSlot into dstSlot.
func (fl *funcLowerer) emitLoadThrough(dstSlot, ptrSlot int32, t types.Type) {
	dt := GoTypeToDis(t)
	if dt.IsPtr {
		fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(ptrSlot, 0), dis.FP(dstSlot)))
	} else {
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(ptrSlot, 0), dis.FP(dstSlot)))
	}
}

// emitStoreThrough stores a value from srcSlot to memory at *ptrSlot.
func (fl *funcLowerer) emitStoreThrough(srcSlot, ptrSlot int32, t types.Type) {
	dt := GoTypeToDis(t)
	if dt.IsPtr {
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(srcSlot), dis.FPInd(ptrSlot, 0)))
	} else {
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(srcSlot), dis.FPInd(ptrSlot, 0)))
	}
}

// ============================================================
// Defer operations
//
// Static defers are inlined at RunDefers sites in LIFO order.
// SSA values are immutable, so arguments captured at Defer time
// remain valid at RunDefers time.
// ============================================================

// lowerDefer captures a deferred call onto the LIFO stack.
// No instructions are emitted — the call is expanded at RunDefers time.
func (fl *funcLowerer) lowerDefer(instr *ssa.Defer) error {
	fl.deferStack = append(fl.deferStack, instr.Call)
	return nil
}

// lowerRunDefers emits all deferred calls in LIFO order (last defer = first call).
func (fl *funcLowerer) lowerRunDefers(instr *ssa.RunDefers) error {
	for i := len(fl.deferStack) - 1; i >= 0; i-- {
		call := fl.deferStack[i]
		if err := fl.emitDeferredCall(call); err != nil {
			return fmt.Errorf("deferred call %d: %w", i, err)
		}
	}
	return nil
}

// emitDeferredCall dispatches a single deferred call by callee type.
func (fl *funcLowerer) emitDeferredCall(call ssa.CallCommon) error {
	// Interface method invocation: defer iface.Method()
	if call.IsInvoke() {
		// For interface invocations, the receiver is call.Value and the method
		// is identified by call.Method. We emit this as a direct call to the
		// concrete method if we can resolve it, otherwise skip (rare in practice).
		return nil // Interface defer is a no-op for now (rare pattern)
	}
	switch callee := call.Value.(type) {
	case *ssa.Builtin:
		return fl.emitDeferredBuiltin(callee, call.Args)
	case *ssa.Function:
		fl.emitDeferredDirectCall(callee, call.Args)
		return nil
	case *ssa.MakeClosure:
		return fl.emitDeferredClosureCall(call)
	default:
		// Function value: closure or method value with Signature type
		if _, ok := call.Value.Type().Underlying().(*types.Signature); ok {
			return fl.emitDeferredClosureCall(call)
		}
		return fmt.Errorf("unsupported deferred call target: %T", call.Value)
	}
}

// emitDeferredBuiltin handles deferred builtin calls (e.g., defer println("bye")).
func (fl *funcLowerer) emitDeferredBuiltin(builtin *ssa.Builtin, args []ssa.Value) error {
	switch builtin.Name() {
	case "println", "print":
		for i, arg := range args {
			if i > 0 {
				fl.emitSysPrint(" ")
			}
			if err := fl.emitPrintArg(arg); err != nil {
				return err
			}
		}
		fl.emitSysPrint("\n")
		return nil
	case "close":
		// Same as lowerClose: set closed flag + NBALT send zero to wake blocked receivers
		chanSlot := fl.materialize(args[0])
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FPInd(chanSlot, 8)))

		chanType := args[0].Type().Underlying().(*types.Chan)
		elemType := chanType.Elem()
		elemDt := GoTypeToDis(elemType)
		iby2wd := int32(dis.IBY2WD)

		zeroSlot := fl.frame.AllocWord("dclose.zero")
		if elemDt.IsPtr {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(zeroSlot)))
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(zeroSlot)))
		}
		altBase := fl.frame.AllocWord("dclose.alt.nsend")
		fl.frame.AllocWord("dclose.alt.nrecv")
		fl.frame.AllocPointer("dclose.alt.ch")
		fl.frame.AllocWord("dclose.alt.ptr")

		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(altBase)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(altBase+iby2wd)))
		tmpRaw := fl.allocPtrTemp("dclose.raw")
		fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(chanSlot, 0), dis.FP(tmpRaw)))
		fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmpRaw), dis.FP(altBase+2*iby2wd)))
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(zeroSlot), dis.FP(altBase+3*iby2wd)))
		nbaltResult := fl.frame.AllocWord("dclose.nbalt.result")
		fl.emit(dis.Inst2(dis.INBALT, dis.FP(altBase), dis.FP(nbaltResult)))
		return nil
	case "delete":
		// Deferred delete: same as regular lowerMapDelete but with raw args.
		// Build a synthetic ssa.Call-like invocation. Since delete is complex,
		// we emit the delete inline using the same map/key materialization.
		return fl.emitDeferredMapDelete(args[0], args[1])
	case "recover":
		// defer recover() — result is discarded in defer context.
		// recover() is a no-op when called directly; it only has effect
		// when called from a deferred function. In the defer builtin path,
		// it's just a no-op (the exception handler captures the value).
		return nil
	case "len", "cap", "append", "copy":
		// These are side-effect-free (or append returns a new slice).
		// Deferring them is a no-op since the result is discarded.
		return nil
	case "min", "max", "clear":
		// Side-effect-free (min/max) or handled inline.
		// clear in defer could matter but is rare.
		if builtin.Name() == "clear" && len(args) > 0 {
			// Emit inline clear for map/slice
			mapSlot := fl.materialize(args[0])
			if _, ok := args[0].Type().Underlying().(*types.Map); ok {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FPInd(mapSlot, 16)))
			}
		}
		return nil
	default:
		return fmt.Errorf("unsupported deferred builtin: %s", builtin.Name())
	}
}

// emitDeferredDirectCall emits IFRAME + args + CALL for a deferred function.
func (fl *funcLowerer) emitDeferredDirectCall(callee *ssa.Function, args []ssa.Value) {
	type argInfo struct {
		off   int32
		isPtr bool
		st    *types.Struct
	}
	var argInfos []argInfo
	for _, arg := range args {
		off := fl.materialize(arg)
		dt := GoTypeToDis(arg.Type())
		var st *types.Struct
		if s, ok := arg.Type().Underlying().(*types.Struct); ok {
			st = s
		}
		argInfos = append(argInfos, argInfo{off, dt.IsPtr, st})
	}

	callFrame := fl.frame.AllocWord("")
	iframeIdx := len(fl.insts)
	fl.emit(dis.Inst2(dis.IFRAME, dis.Imm(0), dis.FP(callFrame)))

	calleeOff := int32(dis.MaxTemp)
	for _, a := range argInfos {
		if a.st != nil {
			fieldOff := int32(0)
			for i := 0; i < a.st.NumFields(); i++ {
				fdt := GoTypeToDis(a.st.Field(i).Type())
				if fdt.IsPtr {
					fl.emit(dis.Inst2(dis.IMOVP, dis.FP(a.off+fieldOff), dis.FPInd(callFrame, calleeOff+fieldOff)))
				} else {
					fl.emit(dis.Inst2(dis.IMOVW, dis.FP(a.off+fieldOff), dis.FPInd(callFrame, calleeOff+fieldOff)))
				}
				fieldOff += fdt.Size
			}
			calleeOff += GoTypeToDis(a.st).Size
		} else if a.isPtr {
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(a.off), dis.FPInd(callFrame, calleeOff)))
			calleeOff += int32(dis.IBY2WD)
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(a.off), dis.FPInd(callFrame, calleeOff)))
			calleeOff += int32(dis.IBY2WD)
		}
	}

	icallIdx := len(fl.insts)
	fl.emit(dis.Inst2(dis.ICALL, dis.FP(callFrame), dis.Imm(0)))

	fl.funcCallPatches = append(fl.funcCallPatches,
		funcCallPatch{instIdx: iframeIdx, callee: callee, patchKind: patchIFRAME},
		funcCallPatch{instIdx: icallIdx, callee: callee, patchKind: patchICALL},
	)
}

// emitDeferredClosureCall emits a call to a deferred closure.
func (fl *funcLowerer) emitDeferredClosureCall(call ssa.CallCommon) error {
	innerFn := fl.comp.resolveClosureTarget(call.Value)
	if innerFn == nil {
		return fmt.Errorf("cannot statically resolve deferred closure target for %v", call.Value)
	}

	closureSlot := fl.slotOf(call.Value)
	callFrame := fl.frame.AllocWord("")

	iframeIdx := len(fl.insts)
	fl.emit(dis.Inst2(dis.IFRAME, dis.Imm(0), dis.FP(callFrame)))

	// Pass closure pointer as hidden first param
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(closureSlot), dis.FPInd(callFrame, int32(dis.MaxTemp))))

	// Pass actual args
	calleeOff := int32(dis.MaxTemp + dis.IBY2WD)
	for _, arg := range call.Args {
		argOff := fl.materialize(arg)
		dt := GoTypeToDis(arg.Type())
		if dt.IsPtr {
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(argOff), dis.FPInd(callFrame, calleeOff)))
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(argOff), dis.FPInd(callFrame, calleeOff)))
		}
		calleeOff += dt.Size
	}

	icallIdx := len(fl.insts)
	fl.emit(dis.Inst2(dis.ICALL, dis.FP(callFrame), dis.Imm(0)))

	fl.funcCallPatches = append(fl.funcCallPatches,
		funcCallPatch{instIdx: iframeIdx, callee: innerFn, patchKind: patchIFRAME},
		funcCallPatch{instIdx: icallIdx, callee: innerFn, patchKind: patchICALL},
	)
	return nil
}

// emitZeroDivCheck emits an explicit zero-divisor check before integer division.
// ARM64's sdiv instruction returns 0 for division by zero instead of trapping,
// so we must check explicitly and raise "zero divide" to match Go semantics.
// Layout: BNEW divisor, $0, $+2; RAISE "zero divide"(mp)
func (fl *funcLowerer) emitZeroDivCheck(divisor dis.Operand) {
	zdivStr := fl.comp.AllocString("zero divide")
	skipPC := int32(len(fl.insts)) + 2 // skip over BNEW and RAISE
	fl.emit(dis.NewInst(dis.IBNEW, divisor, dis.Imm(0), dis.Imm(skipPC)))
	fl.emit(dis.Inst{Op: dis.IRAISE, Src: dis.MP(zdivStr), Mid: dis.NoOperand, Dst: dis.NoOperand})
}

// lowerPanic emits IRAISE with the panic value (a string).
// IRAISE: src = pointer to string exception value.
func (fl *funcLowerer) lowerPanic(instr *ssa.Panic) error {
	// panic() takes interface{}. We need a string for IRAISE.
	// If the argument is already a string, use it directly.
	// For interface values: extract the value word and convert to string.
	argType := instr.X.Type()
	argSlot := fl.materialize(instr.X)

	if basic, ok := argType.Underlying().(*types.Basic); ok && basic.Kind() == types.String {
		// Direct string value
		fl.emit(dis.Inst{Op: dis.IRAISE, Src: dis.FP(argSlot), Mid: dis.NoOperand, Dst: dis.NoOperand})
		return nil
	}

	// Interface value: [tag, value]. The value word might be a string or int.
	// Convert value to string: try CVTWC (int→string) as a reasonable default,
	// but check if it's already a string-typed interface by checking tag.
	if _, ok := argType.Underlying().(*types.Interface); ok {
		valSlot := argSlot + int32(dis.IBY2WD) // value word at offset 8
		// Use the value word — if it came from panic("str"), it's a string ptr.
		// If it came from panic(42), it's an int. We pass the value word
		// directly to RAISE; Dis RAISE accepts strings (will format as exception).
		// For non-string values, convert to string first.
		strSlot := fl.frame.AllocPointer("panic.str")
		fl.emit(dis.Inst2(dis.ICVTWC, dis.FP(valSlot), dis.FP(strSlot)))
		fl.emit(dis.Inst{Op: dis.IRAISE, Src: dis.FP(strSlot), Mid: dis.NoOperand, Dst: dis.NoOperand})
		return nil
	}

	// Non-string, non-interface: convert to string
	if basic, ok := argType.Underlying().(*types.Basic); ok && basic.Info()&types.IsInteger != 0 {
		strSlot := fl.frame.AllocPointer("panic.str")
		fl.emit(dis.Inst2(dis.ICVTWC, dis.FP(argSlot), dis.FP(strSlot)))
		fl.emit(dis.Inst{Op: dis.IRAISE, Src: dis.FP(strSlot), Mid: dis.NoOperand, Dst: dis.NoOperand})
		return nil
	}

	// Fallback: use as-is (might be string already from type assertion)
	fl.emit(dis.Inst{Op: dis.IRAISE, Src: dis.FP(argSlot), Mid: dis.NoOperand, Dst: dis.NoOperand})
	return nil
}

// copyIface copies a 2-word interface value (tag + value) between frame slots.
func (fl *funcLowerer) copyIface(src, dst int32) {
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(src), dis.FP(dst)))                          // tag
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(src+int32(dis.IBY2WD)), dis.FP(dst+int32(dis.IBY2WD)))) // value
}

// concreteTypeName extracts the concrete type name for type tag allocation.
func concreteTypeName(t types.Type) string {
	if named, ok := t.(*types.Named); ok {
		return named.Obj().Name()
	}
	return t.String()
}

// lowerMakeInterface stores the underlying value into a tagged interface slot.
// Interface layout: [tag (WORD)] [value (WORD)].
// Tag is the type tag ID for the concrete type.
// Value is the raw value (for ≤1 word) or pointer to struct data (for >1 word).
func (fl *funcLowerer) lowerMakeInterface(instr *ssa.MakeInterface) error {
	srcSlot := fl.materialize(instr.X)
	dstSlot := fl.slotOf(instr)
	tag := fl.comp.AllocTypeTag(concreteTypeName(instr.X.Type()))
	dt := GoTypeToDis(instr.X.Type())

	// Store type tag at dst+0
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(tag), dis.FP(dstSlot)))
	// Store value at dst+8
	if dt.Size > int32(dis.IBY2WD) {
		// Struct or multi-word: store address of the data
		fl.emit(dis.Inst2(dis.ILEA, dis.FP(srcSlot), dis.FP(dstSlot+int32(dis.IBY2WD))))
	} else {
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(srcSlot), dis.FP(dstSlot+int32(dis.IBY2WD))))
	}
	return nil
}

// lowerTypeAssert extracts a concrete value from a tagged interface.
// Interface layout: [tag (WORD)] [value (WORD)].
// For non-commaok: checks tag, panics on mismatch.
// For commaok: checks tag, returns (value, ok).
func (fl *funcLowerer) lowerTypeAssert(instr *ssa.TypeAssert) error {
	srcSlot := fl.slotOf(instr.X) // interface base: tag at srcSlot, value at srcSlot+8
	dst := fl.slotOf(instr)
	iby2wd := int32(dis.IBY2WD)

	// Check if asserting to another interface type
	if _, isIface := instr.AssertedType.Underlying().(*types.Interface); isIface {
		// Interface-to-interface: just copy the 2 words (tag stays the same)
		if instr.CommaOk {
			// Result tuple: (interface, bool)
			fl.copyIface(srcSlot, dst)
			// ok = (tag != 0) — any non-nil interface satisfies
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst+2*iby2wd)))
		} else {
			fl.copyIface(srcSlot, dst)
		}
		return nil
	}

	dt := GoTypeToDis(instr.AssertedType)
	tag := fl.comp.AllocTypeTag(concreteTypeName(instr.AssertedType))

	if instr.CommaOk {
		// Result is a tuple: (value, bool).
		// Layout depends on value size: value at dst, ok after value.
		//   BEQW $tag, FP(srcSlot), $match_pc
		//   MOVW $0, FP(dst)          ; value = 0
		//   MOVW $0, FP(dst+dtSize)   ; ok = false
		//   JMP $done_pc
		// match_pc:
		//   MOVW/MOVP FP(srcSlot+8) → FP(dst)  ; copy value
		//   MOVW $1, FP(dst+dtSize)             ; ok = true
		// done_pc:

		beqwIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(tag), dis.FP(srcSlot), dis.Imm(0))) // placeholder

		// No match path: zero value for type (H for pointer types, 0 for scalars)
		if dt.IsPtr {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst))) // H
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		}
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+dt.Size)))
		jmpIdx := len(fl.insts)
		fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0))) // placeholder

		// Match path
		matchPC := int32(len(fl.insts))
		fl.insts[beqwIdx].Dst = dis.Imm(matchPC)
		if dt.IsPtr {
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(srcSlot+iby2wd), dis.FP(dst)))
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(srcSlot+iby2wd), dis.FP(dst)))
		}
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst+dt.Size)))

		// Patch JMP
		donePC := int32(len(fl.insts))
		fl.insts[jmpIdx].Dst = dis.Imm(donePC)
	} else {
		// Non-commaok: check tag, panic on mismatch
		//   BEQW $tag, FP(srcSlot), $ok_pc
		//   RAISE "interface conversion"
		// ok_pc:
		//   MOVW/MOVP FP(srcSlot+8) → FP(dst)

		beqwIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.Imm(tag), dis.FP(srcSlot), dis.Imm(0))) // placeholder

		// Panic path
		panicStr := fl.comp.AllocString("interface conversion")
		panicSlot := fl.frame.AllocPointer("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(panicStr), dis.FP(panicSlot)))
		fl.emit(dis.Inst{Op: dis.IRAISE, Src: dis.FP(panicSlot), Mid: dis.NoOperand, Dst: dis.NoOperand})

		// OK path
		okPC := int32(len(fl.insts))
		fl.insts[beqwIdx].Dst = dis.Imm(okPC)
		if dt.IsPtr {
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(srcSlot+iby2wd), dis.FP(dst)))
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(srcSlot+iby2wd), dis.FP(dst)))
		}
	}
	return nil
}

// lowerChangeInterface converts between interface types (copy 2-word tag+value).
func (fl *funcLowerer) lowerChangeInterface(instr *ssa.ChangeInterface) error {
	srcSlot := fl.slotOf(instr.X)
	dstSlot := fl.slotOf(instr)
	fl.copyIface(srcSlot, dstSlot)
	return nil
}

func (fl *funcLowerer) lowerConvert(instr *ssa.Convert) error {
	dst := fl.slotOf(instr)
	src := fl.operandOf(instr.X)

	srcType := instr.X.Type().Underlying()
	dstType := instr.Type().Underlying()

	// string → []byte (CVTCA)
	if isStringType(srcType) && isByteSlice(dstType) {
		fl.emit(dis.Inst2(dis.ICVTCA, src, dis.FP(dst)))
		return nil
	}

	// []byte → string (CVTAC)
	if isByteSlice(srcType) && isStringType(dstType) {
		fl.emit(dis.Inst2(dis.ICVTAC, src, dis.FP(dst)))
		return nil
	}

	// string → []rune: iterate string runes into an int array
	if isStringType(srcType) && isRuneSlice(dstType) {
		return fl.emitStringToRuneSlice(src, dst)
	}

	// []rune → string: build string from rune array
	if isRuneSlice(srcType) && isStringType(dstType) {
		return fl.emitRuneSliceToString(src, dst)
	}

	// int/rune → string (create 1-char string from character code point)
	// SSA generates this for string(rune(x)) or string(65)
	if isIntegerType(srcType) && isStringType(dstType) {
		// INSC: src=rune, mid=index(0), dst=string
		// When dst is H (nil), INSC creates a new 1-char string.
		fl.emit(dis.NewInst(dis.IINSC, src, dis.Imm(0), dis.FP(dst)))
		return nil
	}

	// int → float (CVTWF)
	if isIntegerType(srcType) && isFloatType(dstType) {
		fl.emit(dis.Inst2(dis.ICVTWF, src, dis.FP(dst)))
		return nil
	}

	// float → int (CVTFW)
	if isFloatType(srcType) && isIntegerType(dstType) {
		fl.emit(dis.Inst2(dis.ICVTFW, src, dis.FP(dst)))
		return nil
	}

	// Default: integer/pointer conversions — move then truncate if narrowing
	fl.emit(dis.Inst2(dis.IMOVW, src, dis.FP(dst)))
	fl.emitSubWordTruncate(dst, dstType)
	return nil
}

func isIntegerType(t types.Type) bool {
	b, ok := t.(*types.Basic)
	if !ok {
		return false
	}
	switch b.Kind() {
	case types.Int, types.Int8, types.Int16, types.Int32, types.Int64,
		types.Uint, types.Uint8, types.Uint16, types.Uint32, types.Uint64, types.Uintptr:
		return true
	}
	return false
}

func isFloatType(t types.Type) bool {
	b, ok := t.(*types.Basic)
	return ok && (b.Kind() == types.Float32 || b.Kind() == types.Float64)
}

func isStringType(t types.Type) bool {
	b, ok := t.(*types.Basic)
	return ok && b.Kind() == types.String
}

func isByteSlice(t types.Type) bool {
	s, ok := t.(*types.Slice)
	if !ok {
		return false
	}
	b, ok := s.Elem().(*types.Basic)
	return ok && (b.Kind() == types.Byte || b.Kind() == types.Uint8)
}

func isRuneSlice(t types.Type) bool {
	s, ok := t.(*types.Slice)
	if !ok {
		return false
	}
	b, ok := s.Elem().(*types.Basic)
	return ok && (b.Kind() == types.Rune || b.Kind() == types.Int32)
}

// emitStringToRuneSlice converts a string to []rune ([]int32).
// Creates an int array of string length, then copies each rune via INDW.
func (fl *funcLowerer) emitStringToRuneSlice(src dis.Operand, dst int32) error {
	// Get string length in runes via LENC
	strLen := fl.frame.AllocWord("s2r.len")
	fl.emit(dis.Inst2(dis.ILENC, src, dis.FP(strLen)))

	// Create array of ints with length = string length
	elemTDIdx := fl.makeHeapTypeDesc(types.Typ[types.Int32])
	fl.emit(dis.NewInst(dis.INEWA, dis.FP(strLen), dis.Imm(int32(elemTDIdx)), dis.FP(dst)))

	// Loop: for i := 0; i < len; i++ { arr[i] = rune(str[i]) }
	idx := fl.frame.AllocWord("s2r.i")
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(idx)))

	loopPC := int32(len(fl.insts))
	doneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(idx), dis.FP(strLen), dis.Imm(0))) // if idx >= len → done

	// Get rune at index: INDC str, idx → runeSlot
	runeSlot := fl.frame.AllocWord("s2r.rune")
	fl.emit(dis.NewInst(dis.IINDC, src, dis.FP(idx), dis.FP(runeSlot)))

	// Store rune in array using INDX + MOVW
	elemAddr := fl.frame.AllocWord("s2r.addr")
	fl.emit(dis.NewInst(dis.IINDX, dis.FP(dst), dis.FP(elemAddr), dis.FP(idx)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(runeSlot), dis.FPInd(elemAddr, 0)))

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(idx), dis.FP(idx)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	donePC := int32(len(fl.insts))
	fl.insts[doneIdx].Dst = dis.Imm(donePC)
	return nil
}

// emitRuneSliceToString converts a []rune ([]int32) to a string.
// Builds the string by converting each rune via INSC and concatenating.
func (fl *funcLowerer) emitRuneSliceToString(src dis.Operand, dst int32) error {
	arrLen := fl.frame.AllocWord("r2s.len")
	fl.emit(dis.Inst2(dis.ILENA, src, dis.FP(arrLen)))

	emptyMP := fl.comp.AllocString("")
	fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyMP), dis.FP(dst)))

	idx := fl.frame.AllocWord("r2s.i")
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(idx)))

	loopPC := int32(len(fl.insts))
	doneIdx := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBGEW, dis.FP(idx), dis.FP(arrLen), dis.Imm(0))) // if idx >= len → done

	// Get rune at index
	runeSlot := fl.frame.AllocWord("r2s.rune")
	elemAddr := fl.frame.AllocWord("r2s.addr")
	fl.emit(dis.NewInst(dis.IINDX, src, dis.FP(elemAddr), dis.FP(idx)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(elemAddr, 0), dis.FP(runeSlot)))

	// Convert rune to 1-char string
	charStr := fl.frame.AllocTemp(true)
	fl.emit(dis.NewInst(dis.IINSC, dis.FP(runeSlot), dis.Imm(0), dis.FP(charStr)))

	// Concatenate: dst = dst + charStr
	tmp := fl.frame.AllocTemp(true)
	fl.emit(dis.NewInst(dis.IADDC, dis.FP(charStr), dis.FP(dst), dis.FP(tmp)))
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tmp), dis.FP(dst)))

	fl.emit(dis.NewInst(dis.IADDW, dis.Imm(1), dis.FP(idx), dis.FP(idx)))
	fl.emit(dis.Inst1(dis.IJMP, dis.Imm(loopPC)))

	donePC := int32(len(fl.insts))
	fl.insts[doneIdx].Dst = dis.Imm(donePC)
	return nil
}

func (fl *funcLowerer) lowerChangeType(instr *ssa.ChangeType) error {
	dst := fl.slotOf(instr)
	src := fl.operandOf(instr.X)
	dt := GoTypeToDis(instr.Type())
	if dt.IsPtr {
		fl.emit(dis.Inst2(dis.IMOVP, src, dis.FP(dst)))
	} else {
		fl.emit(dis.Inst2(dis.IMOVW, src, dis.FP(dst)))
	}
	return nil
}

func (fl *funcLowerer) lowerExtract(instr *ssa.Extract) error {
	// Extract pulls value #Index from a tuple (multi-return).
	// The tuple is stored as consecutive frame slots.
	tupleSlot := fl.slotOf(instr.Tuple)
	tup := instr.Tuple.Type().(*types.Tuple)

	// Compute offset of element #Index within the tuple
	elemOff := int32(0)
	for i := 0; i < instr.Index; i++ {
		dt := GoTypeToDis(tup.At(i).Type())
		elemOff += dt.Size
	}

	dst := fl.slotOf(instr)
	if _, ok := instr.Type().Underlying().(*types.Interface); ok {
		// Interface extract: copy 2 words (tag + value)
		fl.copyIface(tupleSlot+elemOff, dst)
	} else {
		dt := GoTypeToDis(instr.Type())
		if dt.IsPtr {
			fl.emit(dis.Inst2(dis.IMOVP, dis.FP(tupleSlot+elemOff), dis.FP(dst)))
		} else {
			fl.emit(dis.Inst2(dis.IMOVW, dis.FP(tupleSlot+elemOff), dis.FP(dst)))
		}
	}
	return nil
}

func (fl *funcLowerer) lowerLen(instr *ssa.Call) error {
	arg := instr.Call.Args[0]
	dst := fl.slotOf(instr)

	t := arg.Type().Underlying()
	switch t.(type) {
	case *types.Slice, *types.Array:
		// Check for constant nil slice
		if c, ok := arg.(*ssa.Const); ok && c.Value == nil {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return nil
		}
		src := fl.operandOf(arg)
		// Nil slice (H) check: if ptr == H → len = 0
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		skipIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, src, dis.Imm(-1), dis.Imm(0))) // if src == H → skip
		fl.emit(dis.Inst2(dis.ILENA, src, dis.FP(dst)))
		fl.insts[skipIdx].Dst = dis.Imm(int32(len(fl.insts)))
	case *types.Map:
		// Nil map check: if ptr == H → len = 0
		if c, ok := arg.(*ssa.Const); ok && c.Value == nil {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return nil
		}
		mapSlot := fl.slotOf(arg)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		skipIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.FP(mapSlot), dis.Imm(-1), dis.Imm(0)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(mapSlot, 16), dis.FP(dst)))
		fl.insts[skipIdx].Dst = dis.Imm(int32(len(fl.insts)))
	case *types.Chan:
		// Channel: use LENA on the raw channel (offset 0 of wrapper)
		chanSlot := fl.materialize(arg)
		rawCh := fl.frame.AllocWord("len.rawch")
		fl.emit(dis.Inst2(dis.IMOVP, dis.FPInd(chanSlot, 0), dis.FP(rawCh)))
		fl.emit(dis.Inst2(dis.ILENA, dis.FP(rawCh), dis.FP(dst)))
	default:
		// string
		src := fl.operandOf(arg)
		fl.emit(dis.Inst2(dis.ILENC, src, dis.FP(dst)))
	}
	return nil
}

func (fl *funcLowerer) lowerAppend(instr *ssa.Call) error {
	args := instr.Call.Args
	if len(args) != 2 {
		return fmt.Errorf("append: expected 2 args (slice, slice...), got %d", len(args))
	}

	// SSA transforms append(s, elems...) so both args are slices
	oldSlice := args[0]
	newSlice := args[1]

	// Get element type from slice type
	sliceType := oldSlice.Type().Underlying().(*types.Slice)
	elemType := sliceType.Elem()

	oldOff := fl.slotOf(oldSlice)
	newOff := fl.slotOf(newSlice)

	// Get lengths of both slices (nil-safe: nil slice → len 0)
	oldLenSlot := fl.frame.AllocWord("append.oldlen")
	newLenSlot := fl.frame.AllocWord("append.newlen")

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(oldLenSlot)))
	oldNilSkip := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(oldOff), dis.Imm(-1), dis.Imm(0)))
	fl.emit(dis.Inst2(dis.ILENA, dis.FP(oldOff), dis.FP(oldLenSlot)))
	fl.insts[oldNilSkip].Dst = dis.Imm(int32(len(fl.insts)))

	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(newLenSlot)))
	newNilSkip := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(newOff), dis.Imm(-1), dis.Imm(0)))
	fl.emit(dis.Inst2(dis.ILENA, dis.FP(newOff), dis.FP(newLenSlot)))
	fl.insts[newNilSkip].Dst = dis.Imm(int32(len(fl.insts)))

	// Total length = oldLen + newLen
	totalLenSlot := fl.frame.AllocWord("append.total")
	fl.emit(dis.NewInst(dis.IADDW, dis.FP(newLenSlot), dis.FP(oldLenSlot), dis.FP(totalLenSlot)))

	// Allocate new array with total length
	elemTDIdx := fl.makeHeapTypeDesc(elemType)
	dstSlot := fl.slotOf(instr) // result slot (pointer)
	fl.emit(dis.NewInst(dis.INEWA, dis.FP(totalLenSlot), dis.Imm(int32(elemTDIdx)), dis.FP(dstSlot)))

	// Copy old elements at offset 0 (skip if old was nil)
	oldCopySkip := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(oldOff), dis.Imm(-1), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.ISLICELA, dis.FP(oldOff), dis.Imm(0), dis.FP(dstSlot)))
	fl.insts[oldCopySkip].Dst = dis.Imm(int32(len(fl.insts)))

	// Copy new elements at offset oldLen (skip if new was nil)
	newCopySkip := len(fl.insts)
	fl.emit(dis.NewInst(dis.IBEQW, dis.FP(newOff), dis.Imm(-1), dis.Imm(0)))
	fl.emit(dis.NewInst(dis.ISLICELA, dis.FP(newOff), dis.FP(oldLenSlot), dis.FP(dstSlot)))
	fl.insts[newCopySkip].Dst = dis.Imm(int32(len(fl.insts)))

	return nil
}

// lowerCap handles cap(s) — Dis arrays have len == cap; channels read from wrapper offset 16.
func (fl *funcLowerer) lowerCap(instr *ssa.Call) error {
	arg := instr.Call.Args[0]
	dst := fl.slotOf(instr)

	if _, ok := arg.Type().Underlying().(*types.Chan); ok {
		// Channel: capacity stored in wrapper at offset 16
		chanSlot := fl.materialize(arg)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FPInd(chanSlot, 16), dis.FP(dst)))
		return nil
	}

	src := fl.operandOf(arg)
	fl.emit(dis.Inst2(dis.ILENA, src, dis.FP(dst)))
	return nil
}

// lowerCopy handles copy(dst, src) on slices.
// Copies min(len(dst), len(src)) elements from src to dst[0:].
// Returns the number of elements copied.
func (fl *funcLowerer) lowerCopy(instr *ssa.Call) error {
	dstArr := instr.Call.Args[0]
	srcArr := instr.Call.Args[1]
	dstArrSlot := fl.slotOf(dstArr)
	srcArrSlot := fl.slotOf(srcArr)

	// Get lengths
	dstLen := fl.frame.AllocWord("copy.dstlen")
	srcLen := fl.frame.AllocWord("copy.srclen")
	fl.emit(dis.Inst2(dis.ILENA, dis.FP(dstArrSlot), dis.FP(dstLen)))
	fl.emit(dis.Inst2(dis.ILENA, dis.FP(srcArrSlot), dis.FP(srcLen)))

	// min = srcLen (start with srcLen, reduce to dstLen if smaller)
	minLen := fl.frame.AllocWord("copy.min")
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(srcLen), dis.FP(minLen)))

	// if dstLen < srcLen, min = dstLen
	// BLTW: if src < mid goto dst  →  if dstLen < srcLen goto skip
	skipPC := fl.emit(dis.NewInst(dis.IBLTW, dis.FP(dstLen), dis.FP(srcLen), dis.Imm(0)))
	// dstLen >= srcLen, min stays srcLen → jump over
	noSwapPC := fl.emit(dis.Inst1(dis.IJMP, dis.Imm(0)))
	// dstLen < srcLen, min = dstLen
	fl.insts[skipPC].Dst = dis.Imm(int32(len(fl.insts)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.FP(dstLen), dis.FP(minLen)))
	fl.insts[noSwapPC].Dst = dis.Imm(int32(len(fl.insts)))

	// Sub-slice src to [0:min] in a temp
	srcCopy := fl.allocPtrTemp("copy.srctmp")
	fl.emit(dis.Inst2(dis.IMOVP, dis.FP(srcArrSlot), dis.FP(srcCopy)))
	fl.emit(dis.NewInst(dis.ISLICEA, dis.Imm(0), dis.FP(minLen), dis.FP(srcCopy)))

	// SLICELA copies srcCopy into dstArr at offset 0
	fl.emit(dis.NewInst(dis.ISLICELA, dis.FP(srcCopy), dis.Imm(0), dis.FP(dstArrSlot)))

	// Return value = minLen (only if result is used)
	if instr.Name() != "" {
		resultSlot := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(minLen), dis.FP(resultSlot)))
	}
	return nil
}

// Helper methods

func (fl *funcLowerer) emit(inst dis.Inst) int32 {
	pc := int32(len(fl.insts))
	fl.insts = append(fl.insts, inst)
	return pc
}

func (fl *funcLowerer) slotOf(v ssa.Value) int32 {
	if off, ok := fl.valueMap[v]; ok {
		return off
	}
	// Handle globals: allocate a frame slot and emit LEA to load the MP address
	if g, ok := v.(*ssa.Global); ok {
		return fl.loadGlobalAddr(g)
	}
	// Allocate on demand
	if _, ok := v.Type().Underlying().(*types.Interface); ok {
		// Interface: 2 consecutive WORDs (tag + value)
		off := fl.frame.AllocWord(v.Name() + ".tag")
		fl.frame.AllocWord(v.Name() + ".val")
		fl.valueMap[v] = off
		return off
	}
	// Complex: 2 consecutive float64 slots
	if IsComplexType(v.Type()) {
		off := fl.frame.AllocWord(v.Name() + ".re")
		fl.frame.AllocWord(v.Name() + ".im")
		fl.valueMap[v] = off
		return off
	}
	// Struct: allocate all fields contiguously
	if st, ok := v.Type().Underlying().(*types.Struct); ok {
		off := fl.allocStructFields(st, v.Name())
		fl.valueMap[v] = off
		return off
	}
	dt := GoTypeToDis(v.Type())
	var off int32
	if dt.IsPtr {
		off = fl.frame.AllocPointer(v.Name())
	} else {
		off = fl.frame.AllocWord(v.Name())
	}
	fl.valueMap[v] = off
	return off
}

// loadGlobalAddr allocates a frame slot and emits LEA to load a global's MP address.
// The result is cached in valueMap so LEA is only emitted once per function.
// The slot is NOT marked as a GC pointer because it points to module data (MP),
// not the heap. The GC manages MP separately via the MP type descriptor.
func (fl *funcLowerer) loadGlobalAddr(g *ssa.Global) int32 {
	// Compute the global's key: for non-main packages, prefix with package path
	globalKey := g.Name()
	if g.Package() != nil && g.Package().Pkg.Path() != "main" {
		globalKey = g.Package().Pkg.Path() + "." + g.Name()
	}
	mpOff, ok := fl.comp.GlobalOffset(globalKey)
	if !ok {
		elemType := g.Type().(*types.Pointer).Elem()
		dt := GoTypeToDis(elemType)
		mpOff = fl.comp.AllocGlobal(globalKey, dt.IsPtr)
	}
	slot := fl.frame.AllocWord("gaddr:" + globalKey) // NOT pointer: MP address, not heap
	fl.emit(dis.Inst2(dis.ILEA, dis.MP(mpOff), dis.FP(slot)))
	fl.valueMap[g] = slot
	return slot
}

// materialize ensures a value is in a frame slot and returns its offset.
// For constants, this emits the load instruction. Globals are handled by slotOf.
func (fl *funcLowerer) materialize(v ssa.Value) int32 {
	// If it's a *ssa.Function used as a value (func parameter), wrap in a closure struct
	if fn, ok := v.(*ssa.Function); ok {
		if _, isSig := fn.Type().Underlying().(*types.Signature); isSig {
			return fl.materializeFuncValue(fn)
		}
	}
	// If it's a constant, we need to emit code to load it
	if c, ok := v.(*ssa.Const); ok {
		// Interface constant (nil interface): allocate 2 WORDs
		if _, ok := v.Type().Underlying().(*types.Interface); ok {
			off := fl.frame.AllocWord("")
			fl.frame.AllocWord("")
			// Explicitly zero both tag and value — non-pointer frame
			// slots are NOT guaranteed to be zero-initialized by the VM.
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(off)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(off+int32(dis.IBY2WD))))
			return off
		}
		// Complex constant: allocate 2 float64 slots (real + imag)
		if IsComplexType(v.Type()) {
			off := fl.frame.AllocWord("")
			fl.frame.AllocWord("")
			if c.Value != nil {
				re, im := complexParts(c.Value)
				mpRe := fl.comp.AllocReal(re)
				mpIm := fl.comp.AllocReal(im)
				fl.emit(dis.Inst2(dis.IMOVF, dis.MP(mpRe), dis.FP(off)))
				fl.emit(dis.Inst2(dis.IMOVF, dis.MP(mpIm), dis.FP(off+int32(dis.IBY2WD))))
			} else {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(off)))
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(off+int32(dis.IBY2WD))))
			}
			return off
		}
		dt := GoTypeToDis(v.Type())
		var off int32
		if dt.IsPtr {
			off = fl.frame.AllocPointer("")
		} else {
			off = fl.frame.AllocWord("")
		}

		if c.Value == nil {
			// nil/zero - slot is already zeroed
			return off
		}

		switch c.Value.Kind() {
		case constant.Int:
			val, _ := constant.Int64Val(c.Value)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(int32(val)), dis.FP(off)))
		case constant.Float:
			val, _ := constant.Float64Val(c.Value)
			mpOff := fl.comp.AllocReal(val)
			fl.emit(dis.Inst2(dis.IMOVF, dis.MP(mpOff), dis.FP(off)))
		case constant.Bool:
			if constant.BoolVal(c.Value) {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(off)))
			} else {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(off)))
			}
		case constant.String:
			s := constant.StringVal(c.Value)
			mpOff := fl.comp.AllocString(s)
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(mpOff), dis.FP(off)))
		}
		return off
	}
	return fl.slotOf(v)
}

// materializeFuncValue wraps a top-level *ssa.Function used as a func value
// into a closure struct containing just a function tag (no free vars).
// This allows dynamic dispatch at call sites that receive func parameters.
func (fl *funcLowerer) materializeFuncValue(fn *ssa.Function) int32 {
	// Allocate (or reuse) function tag
	tag := fl.comp.AllocClosureTag(fn)

	// Create closure struct: {funcTag WORD @0} — 8 bytes, no pointers
	td := dis.NewTypeDesc(0, int(dis.IBY2WD))
	fl.callTypeDescs = append(fl.callTypeDescs, td)
	tdIdx := len(fl.callTypeDescs) - 1

	dst := fl.frame.AllocPointer("funcval:" + fn.Name())
	fl.emit(dis.Inst2(dis.INEW, dis.Imm(int32(tdIdx)), dis.FP(dst)))
	fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(tag), dis.FPInd(dst, 0)))

	// Also register in closureMap so resolveClosureTarget finds it
	// when this value is used in a call. We use the Function as key.
	fl.comp.closureMap[fn] = fn

	return dst
}

func (fl *funcLowerer) operandOf(v ssa.Value) dis.Operand {
	// Check if it's a constant
	if c, ok := v.(*ssa.Const); ok {
		return fl.constOperand(c)
	}
	// Otherwise it's in a frame slot (slotOf handles globals via loadGlobalAddr)
	return dis.FP(fl.slotOf(v))
}

func (fl *funcLowerer) constOperand(c *ssa.Const) dis.Operand {
	if c.Value == nil {
		// nil pointer/slice/map/chan/func → H (-1) in Dis; nil interface/zero value → 0
		switch c.Type().Underlying().(type) {
		case *types.Pointer, *types.Slice, *types.Map, *types.Chan, *types.Signature:
			return dis.Imm(-1)
		}
		return dis.Imm(0)
	}
	switch c.Value.Kind() {
	case constant.Int:
		val, _ := constant.Int64Val(c.Value)
		if val >= -0x20000000 && val <= 0x1FFFFFFF {
			return dis.Imm(int32(val))
		}
		// Large constant: must be stored in a frame slot
		off := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(int32(val)), dis.FP(off)))
		return dis.FP(off)
	case constant.Float:
		// Float constants must be materialized (no immediate form)
		val, _ := constant.Float64Val(c.Value)
		mpOff := fl.comp.AllocReal(val)
		off := fl.frame.AllocWord("")
		fl.emit(dis.Inst2(dis.IMOVF, dis.MP(mpOff), dis.FP(off)))
		return dis.FP(off)
	case constant.Bool:
		if constant.BoolVal(c.Value) {
			return dis.Imm(1)
		}
		return dis.Imm(0)
	case constant.String:
		// String constants need to be in the data section
		s := constant.StringVal(c.Value)
		mpOff := fl.comp.AllocString(s)
		off := fl.frame.AllocPointer("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(mpOff), dis.FP(off)))
		return dis.FP(off)
	default:
		return dis.Imm(0)
	}
}

func (fl *funcLowerer) arithOp(intOp, floatOp, stringOp dis.Op, basic *types.Basic) dis.Op {
	if basic == nil {
		return intOp
	}
	if isFloat(basic) {
		return floatOp
	}
	if basic.Kind() == types.String && stringOp != 0 {
		return stringOp
	}
	return intOp
}

func (fl *funcLowerer) compBranchOp(op token.Token, basic *types.Basic) dis.Op {
	isF := basic != nil && isFloat(basic)
	isC := basic != nil && basic.Kind() == types.String

	switch op {
	case token.EQL:
		if isF {
			return dis.IBEQF
		}
		if isC {
			return dis.IBEQC
		}
		return dis.IBEQW
	case token.NEQ:
		if isF {
			return dis.IBNEF
		}
		if isC {
			return dis.IBNEC
		}
		return dis.IBNEW
	case token.LSS:
		if isF {
			return dis.IBLTF
		}
		if isC {
			return dis.IBLTC
		}
		return dis.IBLTW
	case token.LEQ:
		if isF {
			return dis.IBLEF
		}
		if isC {
			return dis.IBLEC
		}
		return dis.IBLEW
	case token.GTR:
		if isF {
			return dis.IBGTF
		}
		if isC {
			return dis.IBGTC
		}
		return dis.IBGTW
	case token.GEQ:
		if isF {
			return dis.IBGEF
		}
		if isC {
			return dis.IBGEC
		}
		return dis.IBGEW
	}
	return dis.IBEQW
}

// indOpForElem returns the Dis index instruction for a given array element type.
// INDB for bytes, INDX for multi-word structs, INDW for everything else.
// INDW uses a fixed 8-byte stride; INDX uses the array's type descriptor size.
func (fl *funcLowerer) indOpForElem(elemType types.Type) dis.Op {
	if IsByteType(elemType) {
		return dis.IINDB
	}
	if _, ok := elemType.Underlying().(*types.Struct); ok {
		dt := GoTypeToDis(elemType)
		if dt.Size > int32(dis.IBY2WD) {
			return dis.IINDX
		}
	}
	return dis.IINDW
}

func isFloat(basic *types.Basic) bool {
	return basic.Info()&types.IsFloat != 0
}

// complexParts extracts the real and imaginary parts from a constant.Value
// representing a complex number.
func complexParts(v constant.Value) (float64, float64) {
	re, _ := constant.Float64Val(constant.Real(v))
	im, _ := constant.Float64Val(constant.Imag(v))
	return re, im
}

// subWordMask returns the AND mask needed to truncate a 64-bit value to the
// given sub-word type, or 0 if no masking is needed (full-width or signed types
// that need sign-extension instead).
// For unsigned sub-word types: returns the bit mask (0xFF, 0xFFFF, 0xFFFFFFFF).
// For signed sub-word types: returns negative mask (-0x100, -0x10000, -0x100000000)
// to signal that sign-extension is needed.
func subWordInfo(t types.Type) (mask int64, signed bool, needsMask bool) {
	basic, ok := t.Underlying().(*types.Basic)
	if !ok {
		return 0, false, false
	}
	switch basic.Kind() {
	case types.Uint8: // types.Byte is alias for Uint8
		return 0xFF, false, true
	case types.Uint16:
		return 0xFFFF, false, true
	case types.Uint32:
		return 0xFFFFFFFF, false, true
	case types.Int8:
		return 0xFF, true, true
	case types.Int16:
		return 0xFFFF, true, true
	case types.Int32:
		return 0xFFFFFFFF, true, true
	default:
		return 0, false, false
	}
}

// emitSubWordTruncate emits AND/sign-extension instructions to truncate a
// 64-bit Dis WORD to the correct sub-word width for the given type.
func (fl *funcLowerer) emitSubWordTruncate(dst int32, t types.Type) {
	mask, signed, needs := subWordInfo(t)
	if !needs {
		return
	}
	// AND with mask to clear upper bits
	fl.emit(dis.NewInst(dis.IANDW, dis.Imm(int32(mask)), dis.FP(dst), dis.FP(dst)))
	if signed {
		// Sign-extend: if the sign bit is set, OR in the upper bits.
		// For int8: if bit7 set, OR with ~0xFF
		// For int16: if bit15 set, OR with ~0xFFFF
		// For int32: if bit31 set, OR with ~0xFFFFFFFF
		// Since Dis WORD is 64-bit on ARM64 but operations treat as signed 64-bit,
		// and we AND'd already, we need:
		//   signBit = 1 << (width-1)
		//   if (val & signBit) != 0: val |= ^mask
		// But we can use a simpler approach with shift-left then arithmetic-shift-right.
		// SHL by (64-width), then SHR (arithmetic) by (64-width).
		// However, Dis SHR is arithmetic for WORD, so this works.
		var shift int32
		switch mask {
		case 0xFF:
			shift = 56 // 64-8
		case 0xFFFF:
			shift = 48 // 64-16
		case 0xFFFFFFFF:
			shift = 32 // 64-32
		}
		fl.emit(dis.NewInst(dis.ISHLW, dis.Imm(shift), dis.FP(dst), dis.FP(dst)))
		fl.emit(dis.NewInst(dis.ISHRW, dis.Imm(shift), dis.FP(dst), dis.FP(dst)))
	}
}

// closureSignaturesMatch checks if a function's Go-level signature matches
// a call-site signature. fn.Signature is the Go type-system signature and
// already excludes hidden parameters (closure pointers, free vars).
// For method values with a receiver, the receiver is the first formal param
// in the type signature, not part of Params().
func closureSignaturesMatch(fn *ssa.Function, callSig *types.Signature) bool {
	fnSig := fn.Signature

	// Compare parameter count and types
	if fnSig.Params().Len() != callSig.Params().Len() {
		return false
	}
	for i := 0; i < callSig.Params().Len(); i++ {
		if !types.Identical(fnSig.Params().At(i).Type(), callSig.Params().At(i).Type()) {
			return false
		}
	}

	// Compare results
	if fnSig.Results().Len() != callSig.Results().Len() {
		return false
	}
	for i := 0; i < callSig.Results().Len(); i++ {
		if !types.Identical(fnSig.Results().At(i).Type(), callSig.Results().At(i).Type()) {
			return false
		}
	}

	return true
}
