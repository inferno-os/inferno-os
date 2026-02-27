package compiler

// stdlib_lower3.go — lowering implementations for additional stdlib packages.

import (
	"golang.org/x/tools/go/ssa"

	"github.com/NERVsystems/infernode/tools/godis/dis"
)

func (fl *funcLowerer) lowerEncodingBase32Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewEncoding":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "EncodeToString":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "DecodeString":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Encode":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	case "Decode":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "EncodedLen", "DecodedLen":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "WithPadding":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	}
	return false, nil
}

func (fl *funcLowerer) lowerCryptoDESCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewCipher", "NewTripleDESCipher":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerCryptoRC4Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "NewCipher":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "XORKeyStream":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	case "Reset":
		if callee.Signature.Recv() != nil {
			return true, nil // no-op
		}
	}
	return false, nil
}

func (fl *funcLowerer) lowerSyscallCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Getenv":
		// Getenv(key) → ("", false)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Getpid":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	case "Getuid", "Getgid":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Exit":
		// Exit(code) — no-op stub (could emit IRAISE)
		return true, nil
	case "Open":
		// Open(path, mode, perm) → (-1, ENOSYS)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(-1), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "Close":
		// Close(fd) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Read", "Write":
		// Read/Write(fd, p) → (0, nil)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerMathCmplxCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Abs", "Phase":
		// Returns float64
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "IsNaN", "IsInf":
		// Returns bool
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Sqrt", "Exp", "Log", "Sin", "Cos", "Tan",
		"Asin", "Acos", "Atan", "Sinh", "Cosh", "Tanh",
		"Conj", "Log10", "Log2", "Pow":
		// Returns complex128 (2 float64s = 2 words on Dis)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Polar":
		// Returns (r, theta float64)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Rect", "Inf", "NaN":
		// Returns complex128
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerNetSMTPCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "SendMail":
		// SendMail(...) → nil error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "PlainAuth", "CRAMMD5Auth":
		// Returns Auth (interface) stub
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Dial":
		// Dial(addr) → (*Client, error)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Close", "Mail", "Rcpt", "Quit", "Hello", "Auth", "StartTLS", "Reset", "Noop", "Verify":
		if callee.Signature.Recv() != nil {
			// → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Data":
		if callee.Signature.Recv() != nil {
			// → (nil io.WriteCloser, nil error)
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		}
	case "Extension":
		if callee.Signature.Recv() != nil {
			// → (false, "")
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "NewClient":
		// smtp.NewClient(conn, host) → (*Client, error)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerNetRPCCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Dial", "DialHTTP", "DialHTTPPath":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	case "NewServer":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Register", "RegisterName":
		if callee.Signature.Recv() != nil {
			// Server.Register/RegisterName → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
		// package-level Register/RegisterName
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Call":
		if callee.Signature.Recv() != nil {
			// Client.Call → nil error
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	case "Go":
		if callee.Signature.Recv() != nil {
			// Client.Go → nil *Call stub
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
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
	case "HandleHTTP":
		if callee.Signature.Recv() != nil {
			return true, nil // Server.HandleHTTP — no-op
		}
		return true, nil // package-level HandleHTTP — no-op
	case "Accept", "ServeConn":
		return true, nil // no-op
	case "Error":
		if callee.Signature.Recv() != nil {
			// ServerError.Error() → ""
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
	}
	return false, nil
}

func (fl *funcLowerer) lowerTextTemplateParseCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	// text/template/parse only has types and constants, no lowerable functions
	return false, nil
}

func (fl *funcLowerer) lowerEncodingASN1Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Marshal", "MarshalWithParams":
		// Marshal(val) → (nil []byte, nil error) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	case "Unmarshal", "UnmarshalWithParams":
		// Unmarshal(b, val) → (nil rest, nil error) stub
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	// BitString methods
	case "At":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	case "RightAlign":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	// ObjectIdentifier methods
	case "Equal":
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
	// Error types
	case "Error":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerCryptoX509PkixCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	// Only types, no functions to lower
	switch callee.Name() {
	case "String":
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	}
	return false, nil
}

func (fl *funcLowerer) lowerCryptoDSACall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	// Only types and constants, no lowerable functions
	return false, nil
}

func (fl *funcLowerer) lowerNetRPCJSONRPCCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Dial":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerCryptoCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	switch name {
	case "Available", "Size", "HashFunc":
		// Hash method calls
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	}
	return false, nil
}

func (fl *funcLowerer) lowerHashAdler32Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "New":
		// New() → hash.Hash32 (interface)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Checksum":
		// Checksum(data) → uint32
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerHashCRC64Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "New":
		// New(tab) → hash.Hash64 (interface)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "MakeTable":
		// MakeTable(poly) → *Table
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Checksum":
		// Checksum(data, tab) → uint64
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerEncodingCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	// encoding package only has interfaces (BinaryMarshaler, TextMarshaler, etc.)
	// No package-level functions to lower
	return false, nil
}

func (fl *funcLowerer) lowerGoConstantCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "MakeBool", "MakeString", "MakeInt64", "MakeFloat64":
		// Make*(x) → Value (interface)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "BoolVal":
		// BoolVal(x) → bool
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "StringVal":
		// StringVal(x) → string
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Int64Val", "Float64Val":
		// Int64Val/Float64Val(x) → (val, exact bool)
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Compare":
		// Compare(x, op, y) → bool
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerGoScannerCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Error":
		// Error.Error() → string
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Len":
		// ErrorList.Len() → int
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	}
	return false, nil
}

func (fl *funcLowerer) lowerRuntimeTraceCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Start":
		// Start(w) → error
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Stop":
		// Stop() — no-op
		return true, nil
	case "IsEnabled":
		// IsEnabled() → bool (always false in Dis VM)
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerCryptoECDHCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "P256", "P384", "P521", "X25519":
		// Curve factory → Curve struct
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "PublicKey":
		// PrivateKey.PublicKey() → *PublicKey
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "Bytes":
		// PrivateKey.Bytes() or PublicKey.Bytes() → []byte
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
	case "ECDH":
		// PrivateKey.ECDH(remote) → ([]byte, error)
		if callee.Signature.Recv() != nil {
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		}
	}
	return false, nil
}

func (fl *funcLowerer) lowerMathRandV2Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Int", "IntN", "N":
		// Returns int
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Int64", "Int64N":
		// Returns int64
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Uint32":
		// Returns uint32
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Uint64":
		// Returns uint64
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Float32":
		// Returns float32
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Float64":
		// Returns float64
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Shuffle":
		// Shuffle(n, swap) — no-op
		return true, nil
	}
	return false, nil
}

// ============================================================
// testing package
// ============================================================

func (fl *funcLowerer) lowerDatabaseSQLDriverCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "IsScanValue", "IsValue":
		// Returns bool → false
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerGoDocCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "New":
		// doc.New(...) → nil *Package
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Synopsis":
		// doc.Synopsis(text) → "" stub
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	case "ToHTML", "ToText":
		// no-op
		return true, nil
	}
	return false, nil
}

func (fl *funcLowerer) lowerTestingCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()

	// Package-level functions
	if callee.Signature.Recv() == nil {
		switch name {
		case "Short", "Verbose":
			// testing.Short/Verbose() → false
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		case "AllocsPerRun":
			// testing.AllocsPerRun(runs, f) → 0.0
			dst := fl.slotOf(instr)
			zOff := fl.comp.AllocReal(0.0)
			fl.emit(dis.Inst2(dis.IMOVF, dis.MP(zOff), dis.FP(dst)))
			return true, nil
		case "Coverage":
			// testing.Coverage() → 0.0
			dst := fl.slotOf(instr)
			zOff := fl.comp.AllocReal(0.0)
			fl.emit(dis.Inst2(dis.IMOVF, dis.MP(zOff), dis.FP(dst)))
			return true, nil
		case "CoverMode":
			// testing.CoverMode() → ""
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		case "Benchmark":
			// testing.Benchmark(f) → zero BenchmarkResult
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		case "Main":
			// testing.Main(...) → no-op
			return true, nil
		}
		return false, nil
	}

	// Method calls on T, B, M
	switch name {
	// Logging/error methods — no-op (test harness not applicable in Dis)
	case "Error", "Errorf", "Fatal", "Fatalf", "Log", "Logf", "Skip", "Skipf":
		return true, nil
	// Control flow methods — no-op
	case "Fail", "FailNow", "SkipNow", "Helper", "Parallel", "Cleanup",
		"Setenv", "ResetTimer", "StartTimer", "StopTimer", "ReportAllocs",
		"SetBytes", "ReportMetric", "SetParallelism", "RunParallel":
		return true, nil
	// Bool-returning methods
	case "Failed", "Skipped":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// String-returning methods
	case "Name", "TempDir":
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	// Run returns bool
	case "Run":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(1), dis.FP(dst)))
		return true, nil
	// Deadline returns (time, bool)
	case "Deadline":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	// PB.Next() → false
	case "Next":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// B.Elapsed() → 0
	case "Elapsed":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// BenchmarkResult methods
	case "NsPerOp", "AllocsPerOp", "AllocedBytesPerOp":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "MemString":
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// net/netip
// ============================================================

func (fl *funcLowerer) lowerNetNetipCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	sig := callee.Signature

	// Methods on Addr, AddrPort, Prefix
	if sig.Recv() != nil {
		switch name {
		// Bool-returning methods
		case "IsValid", "Is4", "Is6", "Is4In6", "IsLoopback", "IsMulticast",
			"IsPrivate", "IsGlobalUnicast", "IsLinkLocalUnicast", "IsLinkLocalMulticast",
			"IsInterfaceLocalMulticast", "IsUnspecified", "IsSingleIP", "Less",
			"Contains", "Overlaps":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		// Int-returning methods
		case "BitLen", "Compare", "Port":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		case "Bits":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		// String-returning methods
		case "Zone", "String", "StringExpanded":
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		// Addr-returning methods (3 words: hi, lo, z)
		case "Unmap", "WithZone", "Prev", "Next", "Addr":
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		// Slice-returning methods
		case "AsSlice":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		// MarshalText, MarshalBinary → ([]byte, error)
		case "MarshalText", "MarshalBinary":
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			return true, nil
		// Prefix → (Prefix, error)
		case "Prefix":
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
			return true, nil
		// Masked → Prefix
		case "Masked":
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
			return true, nil
		// As4 → [4]byte
		case "As4":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		// As16 → [16]byte
		case "As16":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	}

	// Package-level functions
	switch name {
	// Functions returning Addr (3 words)
	case "AddrFrom4", "AddrFrom16", "MustParseAddr", "IPv4Unspecified",
		"IPv6Unspecified", "IPv6LinkLocalAllNodes", "IPv6Loopback":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	// AddrFromSlice → (Addr, bool) = 4 words
	case "AddrFromSlice":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	// ParseAddr → (Addr, error) = 4 words
	case "ParseAddr":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	// AddrPortFrom → AddrPort
	case "AddrPortFrom", "MustParseAddrPort":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	// ParseAddrPort → (AddrPort, error)
	case "ParseAddrPort":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		for i := int32(0); i < 5; i++ {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i*iby2wd)))
		}
		return true, nil
	// PrefixFrom, MustParsePrefix → Prefix
	case "PrefixFrom", "MustParsePrefix":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		for i := int32(0); i < 4; i++ {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i*iby2wd)))
		}
		return true, nil
	// ParsePrefix → (Prefix, error)
	case "ParsePrefix":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		for i := int32(0); i < 5; i++ {
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+i*iby2wd)))
		}
		return true, nil
	}
	return false, nil
}

// ============================================================
// iter
// ============================================================

func (fl *funcLowerer) lowerIterCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	switch name {
	case "Pull":
		// Returns (next func, stop func) = 2 pointers
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	case "Pull2":
		// Returns (next func, stop func) = 2 pointers
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// unique
// ============================================================

func (fl *funcLowerer) lowerUniqueCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	sig := callee.Signature

	if sig.Recv() != nil {
		switch name {
		case "Value":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	}

	switch name {
	case "Make":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// testing/quick
// ============================================================

func (fl *funcLowerer) lowerTestingQuickCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	sig := callee.Signature

	if sig.Recv() != nil {
		switch name {
		case "Error":
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	}

	switch name {
	// Check, CheckEqual → error
	case "Check", "CheckEqual":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+int32(dis.IBY2WD))))
		return true, nil
	// Value → (interface{}, bool)
	case "Value":
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
// testing/slogtest
// ============================================================

func (fl *funcLowerer) lowerTestingSlogtestCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	switch name {
	case "Run":
		return true, nil
	case "TestHandler":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+int32(dis.IBY2WD))))
		return true, nil
	}
	return false, nil
}

// ============================================================
// go/build/constraint
// ============================================================

func (fl *funcLowerer) lowerGoBuildConstraintCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	sig := callee.Signature

	if sig.Recv() != nil {
		switch name {
		case "Error":
			dst := fl.slotOf(instr)
			emptyOff := fl.comp.AllocString("")
			fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	}

	switch name {
	// Parse → (Expr, error) = interface + error = 4 words
	case "Parse":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
		return true, nil
	// IsGoBuild, IsPlusBuild → bool
	case "IsGoBuild", "IsPlusBuild":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// PlusBuildLines → ([]string, error)
	case "PlusBuildLines":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	// GoVersion → string
	case "GoVersion":
		dst := fl.slotOf(instr)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// go/doc/comment
// ============================================================

func (fl *funcLowerer) lowerGoDocCommentCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	sig := callee.Signature

	if sig.Recv() != nil {
		switch name {
		// Parser.Parse → *Doc
		case "Parse":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		// Printer.HTML/Markdown/Text/Comment → []byte
		case "HTML", "Markdown", "Text", "Comment":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	}

	switch name {
	case "DefaultLookupPackage":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		emptyOff := fl.comp.AllocString("")
		fl.emit(dis.Inst2(dis.IMOVP, dis.MP(emptyOff), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// go/importer
// ============================================================

func (fl *funcLowerer) lowerGoImporterCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	switch name {
	case "Default", "For", "ForCompiler":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// mime/quotedprintable
// ============================================================

func (fl *funcLowerer) lowerMimeQuotedprintableCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	sig := callee.Signature

	if sig.Recv() != nil {
		switch name {
		// Read, Write → (int, error)
		case "Read", "Write":
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			return true, nil
		// Close → error
		case "Close":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+int32(dis.IBY2WD))))
			return true, nil
		}
		return false, nil
	}

	switch name {
	// NewReader → *Reader
	case "NewReader":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// NewWriter → *Writer
	case "NewWriter":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// net/http/httptrace
// ============================================================

func (fl *funcLowerer) lowerNetHTTPHttptraceCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	switch name {
	// WithClientTrace → context.Context (interface)
	case "WithClientTrace":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	// ContextClientTrace → *ClientTrace
	case "ContextClientTrace":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// net/http/cgi + net/http/fcgi
// ============================================================

func (fl *funcLowerer) lowerNetHTTPCgiFcgiCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	sig := callee.Signature

	if sig.Recv() != nil {
		switch name {
		case "ServeHTTP":
			return true, nil // void
		}
		return false, nil
	}

	switch name {
	// Serve → error
	case "Serve":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+int32(dis.IBY2WD))))
		return true, nil
	// Request → (*http.Request, error) = 2 words
	case "Request":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	// RequestFromMap → (*http.Request, error)
	case "RequestFromMap":
		dst := fl.slotOf(instr)
		iby2wd := int32(dis.IBY2WD)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
		return true, nil
	// ProcessEnv → map[string]string
	case "ProcessEnv":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	}
	return false, nil
}

// ============================================================
// image/color/palette
// ============================================================

func (fl *funcLowerer) lowerImageColorPaletteCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	// This package only has variables (Plan9, WebSafe), no callable functions
	return false, nil
}

// ============================================================
// runtime/metrics
// ============================================================

func (fl *funcLowerer) lowerRuntimeMetricsCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	sig := callee.Signature

	if sig.Recv() != nil {
		switch name {
		case "Kind":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		case "Uint64":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		case "Float64":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVF, dis.Imm(0), dis.FP(dst)))
			return true, nil
		case "Float64Histogram":
			dst := fl.slotOf(instr)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			return true, nil
		}
		return false, nil
	}

	switch name {
	case "All":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		return true, nil
	case "Read":
		return true, nil // void
	}
	return false, nil
}

// ============================================================
// runtime/coverage
// ============================================================

func (fl *funcLowerer) lowerRuntimeCoverageCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	switch name {
	case "WriteCountersDir", "WriteCounters", "WriteMetaDir", "WriteMeta", "ClearCounters":
		dst := fl.slotOf(instr)
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
		fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+int32(dis.IBY2WD))))
		return true, nil
	}
	return false, nil
}

// ============================================================
// plugin
// ============================================================

func (fl *funcLowerer) lowerPluginCall(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	name := callee.Name()
	sig := callee.Signature

	if sig.Recv() != nil {
		switch name {
		// Plugin.Lookup → (Symbol, error) = interface(2) + error(2) = 4 words
		case "Lookup":
			dst := fl.slotOf(instr)
			iby2wd := int32(dis.IBY2WD)
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+2*iby2wd)))
			fl.emit(dis.Inst2(dis.IMOVW, dis.Imm(0), dis.FP(dst+3*iby2wd)))
			return true, nil
		}
		return false, nil
	}

	switch name {
	// Open → (*Plugin, error)
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
