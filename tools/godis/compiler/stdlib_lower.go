package compiler

// stdlib_lower.go — additional stdlib lowering implementations for packages
// added in stdlib_packages.go.

import (
	"strings"

	"golang.org/x/tools/go/ssa"

	"github.com/NERVsystems/infernode/tools/godis/dis"
)

// ============================================================
// crypto/sha512 package
// ============================================================

func (fl *funcLowerer) lowerCryptoSHA512Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Sum512", "Sum384", "Sum512_224", "Sum512_256":
		// sha512.SumXxx(data) → nil slice stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "New", "New384", "New512_224", "New512_256":
		// sha512.NewXxx() → 0 stub handle
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// crypto/subtle package
// ============================================================

func (fl *funcLowerer) lowerCryptoSubtleCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "ConstantTimeCompare":
		// subtle.ConstantTimeCompare(x, y) → 0 stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "ConstantTimeSelect":
		// subtle.ConstantTimeSelect(v, x, y) → x when v=1, y when v=0
		vSlot := fl.materialize(instr.Call.Args[0])
		xSlot := fl.materialize(instr.Call.Args[1])
		ySlot := fl.materialize(instr.Call.Args[2])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(ySlot), dis.FP(dst)))
		skipIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.FP(vSlot), dis.Imm(0), dis.Imm(0)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(xSlot), dis.FP(dst)))
		fl.insts[skipIdx].Dst = dis.Imm(int32(len(fl.insts)))
		return true, nil
	case "ConstantTimeEq":
		// subtle.ConstantTimeEq(x, y) → 1 if x==y, else 0
		xSlot := fl.materialize(instr.Call.Args[0])
		ySlot := fl.materialize(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		skipIdx := len(fl.insts)
		fl.emit(dis.NewInst(dis.IBEQW, dis.FP(xSlot), dis.FP(ySlot), dis.Imm(0)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.insts[skipIdx].Dst = dis.Imm(int32(len(fl.insts)))
		return true, nil
	case "XORBytes":
		// subtle.XORBytes(dst, x, y) → 0 stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// encoding/gob package
// ============================================================

func (fl *funcLowerer) lowerEncodingGobCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewEncoder", "NewDecoder":
		// gob.NewEncoder/NewDecoder → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Register", "RegisterName":
		// gob.Register/RegisterName — no-op
		return true, nil
	case "Encode", "Decode", "EncodeValue", "DecodeValue":
		if callee.Signature.Recv() != nil {
			// Encoder.Encode/EncodeValue / Decoder.Decode/DecodeValue → nil error
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
// encoding/ascii85 package
// ============================================================

func (fl *funcLowerer) lowerEncodingASCII85Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Encode":
		// ascii85.Encode(dst, src) → 0 stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "MaxEncodedLen":
		// ascii85.MaxEncodedLen(n) → n*5/4+4 (approximation)
		nSlot := fl.materialize(instr.Call.Args[0])
		dst := fl.slotOf(instr)
		fl.emit(dis.NewInst(dis.IMULW, dis.Imm(2), dis.FP(nSlot), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// container/list package
// ============================================================

func (fl *funcLowerer) lowerContainerListCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	switch name {
	case "New":
		// list.New() → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "PushBack", "PushFront", "InsertBefore", "InsertAfter":
		if callee.Signature.Recv() != nil {
			// returns *Element → nil stub
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Len":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Front", "Back":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Remove":
		if callee.Signature.Recv() != nil {
			// returns any → nil
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Next", "Prev":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Init":
		if callee.Signature.Recv() != nil {
			// returns *List → nil
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "MoveToFront", "MoveToBack", "MoveBefore", "MoveAfter", "PushBackList", "PushFrontList":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
		return false, nil
	}
	return false, nil
}

// ============================================================
// container/ring package
// ============================================================

func (fl *funcLowerer) lowerContainerRingCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "New":
		// ring.New(n) → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Len":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Next", "Prev", "Move", "Link", "Unlink":
		if callee.Signature.Recv() != nil {
			// returns *Ring → nil
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Do":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
		return false, nil
	}
	return false, nil
}

// ============================================================
// container/heap package
// ============================================================

func (fl *funcLowerer) lowerContainerHeapCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Init":
		// heap.Init(h) — no-op
		return true, nil
	case "Push":
		// heap.Push(h, x) — no-op
		return true, nil
	case "Pop":
		// heap.Pop(h) → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Fix":
		// heap.Fix(h, i) — no-op
		return true, nil
	case "Remove":
		// heap.Remove(h, i) → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// image package
// ============================================================

func (fl *funcLowerer) lowerImageCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Pt":
		// image.Pt(X, Y) → Point{X, Y}
		xSlot := fl.materialize(instr.Call.Args[0])
		ySlot := fl.materialize(instr.Call.Args[1])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(xSlot), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(ySlot), dis.FP(dst+iby2wd)))
		return true, nil
	case "Rect":
		// image.Rect(x0, y0, x1, y1) → Rectangle{Min{x0,y0}, Max{x1,y1}}
		x0Slot := fl.materialize(instr.Call.Args[0])
		y0Slot := fl.materialize(instr.Call.Args[1])
		x1Slot := fl.materialize(instr.Call.Args[2])
		y1Slot := fl.materialize(instr.Call.Args[3])
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(x0Slot), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(y0Slot), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(x1Slot), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.FP(y1Slot), dis.FP(dst+3*iby2wd)))
		return true, nil
	case "NewRGBA", "NewNRGBA", "NewGray", "NewAlpha", "NewUniform":
		// image.NewXxx(...) → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "DecodeConfig":
		// image.DecodeConfig(r) → (Config{}, "", nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		// Config has 3 int fields (12 bytes) + string + error (2 words)
		for i := int32(0); i < 7; i++ {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i*iby2wd)))
		}
		return true, nil
	case "Decode":
		// image.Decode(r) → (nil, "", nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))       // image (interface tag)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd))) // image (interface val)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst+2*iby2wd))) // format string
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))       // error tag
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+4*iby2wd)))       // error val
		return true, nil
	case "RegisterFormat":
		return true, nil // no-op
	// Point methods
	case "Add":
		if callee.Signature.Recv() != nil && strings.Contains(callee.String(), "Point") {
			// Point.Add(q) → Point{p.X+q.X, p.Y+q.Y} — zero stub
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		if callee.Signature.Recv() != nil && strings.Contains(callee.String(), "Rectangle") {
			// Rectangle.Add(p) → zero Rectangle
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			for i := int32(0); i < 4; i++ {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i*iby2wd)))
			}
			return true, nil
		}
		return false, nil
	case "Sub":
		if callee.Signature.Recv() != nil && strings.Contains(callee.String(), "Point") {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		if callee.Signature.Recv() != nil && strings.Contains(callee.String(), "Rectangle") {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			for i := int32(0); i < 4; i++ {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i*iby2wd)))
			}
			return true, nil
		}
		return false, nil
	case "Mul", "Div":
		if callee.Signature.Recv() != nil && strings.Contains(callee.String(), "Point") {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "In":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Eq":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "String":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	// Rectangle methods
	case "Dx", "Dy":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Size":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		return false, nil
	case "Empty", "Overlaps":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "Intersect", "Union", "Inset", "Canon":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			for i := int32(0); i < 4; i++ {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i*iby2wd)))
			}
			return true, nil
		}
		return false, nil
	case "Bounds":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			for i := int32(0); i < 4; i++ {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i*iby2wd)))
			}
			return true, nil
		}
		return false, nil
	case "SubImage":
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
// image/color package
// ============================================================

func (fl *funcLowerer) lowerImageColorCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "ModelFunc":
		// ModelFunc(f) → nil Model
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// image/png and image/jpeg codecs
// ============================================================

func (fl *funcLowerer) lowerImageCodecCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Encode":
		// png.Encode / jpeg.Encode → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Decode":
		// png.Decode / jpeg.Decode → (nil, nil) stub
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
// debug/buildinfo package
// ============================================================

func (fl *funcLowerer) lowerDebugBuildInfoCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "ReadFile":
		// buildinfo.ReadFile(name) → (nil, nil) stub
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
// go/* packages (ast, token, parser, format)
// ============================================================

func (fl *funcLowerer) lowerGoToolCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	switch {
	case name == "NewFileSet":
		// token.NewFileSet() → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case name == "ParseFile":
		// parser.ParseFile(...) → (nil, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case name == "Source":
		// format.Source(src) → (nil, nil) stub
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
// net/http/cookiejar package
// ============================================================

func (fl *funcLowerer) lowerNetHTTPCookiejarCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "New":
		// cookiejar.New(o) → (nil, nil) stub
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
// net/http/pprof package
// ============================================================

func (fl *funcLowerer) lowerNetHTTPPprofCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Index":
		// pprof.Index(w, r) — no-op
		return true, nil
	}
	return false, nil
}

// ============================================================
// os/user package
// ============================================================

func (fl *funcLowerer) lowerOsUserCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Current", "Lookup", "LookupId":
		// user.Current/Lookup/LookupId → (*User, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "LookupGroup", "LookupGroupId":
		// user.LookupGroup/LookupGroupId → (*Group, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "GroupIds":
		if callee.Signature.Recv() != nil {
			// User.GroupIds() → (nil, nil) stub
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Error":
		if callee.Signature.Recv() != nil {
			// UnknownUser*Error.Error() → ""
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	}
	return false, nil
}

// ============================================================
// regexp/syntax package
// ============================================================

func (fl *funcLowerer) lowerRegexpSyntaxCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	// Constants only, no function calls to lower
	return false, nil
}

// ============================================================
// runtime/debug package
// ============================================================

func (fl *funcLowerer) lowerRuntimeDebugCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Stack":
		// debug.Stack() → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "PrintStack", "FreeOSMemory", "ReadGCStats", "SetTraceback":
		// no-op
		return true, nil
	case "SetGCPercent":
		// debug.SetGCPercent(percent) → 100 (previous value)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(100), dis.FP(dst)))
		return true, nil
	case "SetMaxStack":
		// debug.SetMaxStack(bytes) → 1000000000 (previous value)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1000000000), dis.FP(dst)))
		return true, nil
	case "SetMaxThreads":
		// debug.SetMaxThreads(threads) → 10000 (previous value)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(10000), dis.FP(dst)))
		return true, nil
	case "SetPanicOnFault":
		// debug.SetPanicOnFault(enabled) → false (previous value)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "ReadBuildInfo":
		// debug.ReadBuildInfo() → (nil, false) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "String":
		if callee.Signature.Recv() != nil {
			// BuildInfo.String() → ""
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	}
	return false, nil
}

// ============================================================
// runtime/pprof package
// ============================================================

func (fl *funcLowerer) lowerRuntimePprofCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "StartCPUProfile", "WriteHeapProfile":
		// pprof.StartCPUProfile/WriteHeapProfile(w) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "StopCPUProfile", "SetGoroutineLabels":
		// no-op
		return true, nil
	case "Lookup", "NewProfile":
		// Lookup/NewProfile(name) → nil *Profile
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Profiles":
		// Profiles() → nil slice
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Profile methods
	case "Name":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	case "Count":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Add", "Remove":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	case "WriteTo":
		if callee.Signature.Recv() != nil {
			// Profile.WriteTo(w, debug) → nil error
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
// text/scanner package
// ============================================================

func (fl *funcLowerer) lowerTextScannerCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Init":
		if callee.Signature.Recv() != nil {
			// Scanner.Init(src) → nil *Scanner
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Scan", "Peek", "Next":
		if callee.Signature.Recv() != nil {
			// Scanner.Scan/Peek/Next() → EOF (-1)
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
			return true, nil
		}
	case "TokenText":
		if callee.Signature.Recv() != nil {
			// Scanner.TokenText() → ""
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	case "Pos":
		if callee.Signature.Recv() != nil {
			// Scanner.Pos() → zero Position
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			for i := int32(0); i < 4; i++ {
				fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i*iby2wd)))
			}
			return true, nil
		}
	case "TokenString":
		// scanner.TokenString(tok) → ""
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "IsValid":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "String":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	}
	return false, nil
}

// ============================================================
// text/tabwriter package
// ============================================================

func (fl *funcLowerer) lowerTextTabwriterCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewWriter":
		// tabwriter.NewWriter(...) → nil *Writer stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Init":
		if callee.Signature.Recv() != nil {
			// Writer.Init(...) → nil *Writer
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Write":
		if callee.Signature.Recv() != nil {
			// Writer.Write(buf) → (0, nil)
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
