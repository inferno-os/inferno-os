package compiler

// stdlib_lower2.go — more stdlib lowering implementations.

import (
	"golang.org/x/tools/go/ssa"

	"github.com/NERVsystems/infernode/tools/godis/dis"
)

func (fl *funcLowerer) lowerCryptoSHA1Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Sum":
		// sha1.Sum(data) → nil slice stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "New":
		// sha1.New() → 0 stub handle
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerCompressZlibCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewReader":
		// zlib.NewReader(r) → (io.ReadCloser, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "NewReaderDict":
		// zlib.NewReaderDict(r, dict) → (io.ReadCloser, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "NewWriter":
		// zlib.NewWriter(w) → *Writer stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewWriterLevel":
		// zlib.NewWriterLevel(w, level) → (*Writer, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "NewWriterLevelDict":
		// zlib.NewWriterLevelDict(w, level, dict) → (*Writer, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	// Writer methods
	case "Write":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Close":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Flush":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Reset":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	}
	return false, nil
}

func (fl *funcLowerer) lowerCompressBzip2Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewReader":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerCompressLzwCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewReader", "NewWriter":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerHashFNVCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "New32", "New32a", "New64", "New64a", "New128", "New128a":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerHashMaphashCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "MakeSeed":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Bytes", "String":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerImageDrawCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Draw", "DrawMask":
		// draw.Draw/DrawMask(...) — no-op
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerImageGIFCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Decode", "DecodeAll":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Encode", "EncodeAll":
		// gif.Encode/EncodeAll → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerExpvarCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewInt", "NewString", "NewFloat", "NewMap":
		// expvar.NewXxx(name) → nil *Xxx
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Get":
		// expvar.Get(name) → nil Var (interface)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Publish":
		// expvar.Publish(name, v) — no-op
		return true, nil
	case "Do":
		// expvar.Do(f) — no-op
		return true, nil
	case "Handler":
		// expvar.Handler() → nil http.Handler (interface)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Var method calls (String)
	case "String":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	case "Set":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	case "Add":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	case "Value":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	}
	return false, nil
}

func (fl *funcLowerer) lowerLogSyslogCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "New":
		// syslog.New(priority, tag) → (*Writer, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Dial":
		// syslog.Dial(network, raddr, priority, tag) → (*Writer, nil) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	// Writer methods
	case "Write":
		if callee.Signature.Recv() != nil {
			// Writer.Write(b) → (0, nil)
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
	case "Emerg", "Alert", "Crit", "Err", "Warning", "Notice", "Info", "Debug":
		if callee.Signature.Recv() != nil {
			// Writer.Emerg/Alert/etc(m) → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	}
	return false, nil
}

func (fl *funcLowerer) lowerIndexSuffixarrayCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "New":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerGoPrinterCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Fprint":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerGoBuildCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	return false, nil // only types/vars, no functions
}

func (fl *funcLowerer) lowerGoTypesCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	return false, nil // only types, no functions
}

func (fl *funcLowerer) lowerNetHTTPTestCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewServer", "NewTLSServer", "NewUnstartedServer":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewRecorder":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "NewRequest":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// Server methods
	case "Close", "CloseClientConnections", "Start", "StartTLS":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	case "Client", "Certificate":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	// ResponseRecorder methods
	case "Header":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Write", "WriteString":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "WriteHeader", "Flush":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	case "Result":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	}
	return false, nil
}

func (fl *funcLowerer) lowerTestingFstestCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "TestFS":
		// TestFS(fsys, expected...) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	// MapFS methods
	case "Open", "Stat", "Sub":
		if callee.Signature.Recv() != nil {
			// → (nil, nil)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
	case "ReadFile":
		if callee.Signature.Recv() != nil {
			// → (nil, nil)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "ReadDir":
		if callee.Signature.Recv() != nil {
			// → (nil, nil)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	}
	return false, nil
}

func (fl *funcLowerer) lowerTestingIotestCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "ErrReader", "HalfReader", "DataErrReader", "OneByteReader",
		"TimeoutReader", "TruncateWriter", "NewReadLogger", "NewWriteLogger":
		// All return a reader/writer → nil stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "TestReader":
		// TestReader(r, content) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerDebugFormatCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Open":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerSyncErrgroupCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Go":
		// (*Group).Go(f) — stub: just call f and ignore error
		// In real errgroup, this spawns a goroutine. Here, no-op.
		return true, nil
	case "Wait":
		// (*Group).Wait() → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "SetLimit":
		// (*Group).SetLimit(n) — no-op
		return true, nil
	case "TryGo":
		// (*Group).TryGo(f) → true
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "WithContext":
		// WithContext(ctx) → (nil group, ctx)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	}
	return false, nil
}
