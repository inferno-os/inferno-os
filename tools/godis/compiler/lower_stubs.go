// lower_stubs.go — stub lowering implementations for stdlib packages that
// return placeholder values. These handle type-checking but don't produce
// meaningful runtime behavior.
package compiler

import (
	"strings"

	"golang.org/x/tools/go/ssa"

	"github.com/NERVsystems/infernode/tools/godis/dis"
)

func init() {
	RegisterStdlibLowerer("crypto/sha512", (*funcLowerer).lowerCryptoSHA512Call)
	RegisterStdlibLowerer("crypto/subtle", (*funcLowerer).lowerCryptoSubtleCall)
	RegisterStdlibLowerer("crypto/sha1", (*funcLowerer).lowerCryptoSHA1Call)
	RegisterStdlibLowerer("crypto/des", (*funcLowerer).lowerCryptoDESCall)
	RegisterStdlibLowerer("crypto/rc4", (*funcLowerer).lowerCryptoRC4Call)
	RegisterStdlibLowerer("crypto/dsa", (*funcLowerer).lowerCryptoDSACall)
	RegisterStdlibLowerer("crypto/ecdh", (*funcLowerer).lowerCryptoECDHCall)
	RegisterStdlibLowerer("crypto/x509/pkix", (*funcLowerer).lowerCryptoX509PkixCall)
	RegisterStdlibLowerer("crypto", (*funcLowerer).lowerCryptoCall)
	RegisterStdlibLowerer("encoding/gob", (*funcLowerer).lowerEncodingGobCall)
	RegisterStdlibLowerer("encoding/ascii85", (*funcLowerer).lowerEncodingASCII85Call)
	RegisterStdlibLowerer("encoding/base32", (*funcLowerer).lowerEncodingBase32Call)
	RegisterStdlibLowerer("encoding/asn1", (*funcLowerer).lowerEncodingASN1Call)
	RegisterStdlibLowerer("encoding", (*funcLowerer).lowerEncodingCall)
	RegisterStdlibLowerer("container/list", (*funcLowerer).lowerContainerListCall)
	RegisterStdlibLowerer("container/ring", (*funcLowerer).lowerContainerRingCall)
	RegisterStdlibLowerer("container/heap", (*funcLowerer).lowerContainerHeapCall)
	RegisterStdlibLowerer("image", (*funcLowerer).lowerImageCall)
	RegisterStdlibLowerer("image/color", (*funcLowerer).lowerImageColorCall)
	RegisterStdlibLowerer("image/png", (*funcLowerer).lowerImageCodecCall)
	RegisterStdlibLowerer("image/jpeg", (*funcLowerer).lowerImageCodecCall)
	RegisterStdlibLowerer("image/draw", (*funcLowerer).lowerImageDrawCall)
	RegisterStdlibLowerer("image/gif", (*funcLowerer).lowerImageGIFCall)
	RegisterStdlibLowerer("image/color/palette", (*funcLowerer).lowerImageColorPaletteCall)
	RegisterStdlibLowerer("debug/buildinfo", (*funcLowerer).lowerDebugBuildInfoCall)
	RegisterStdlibLowerer("debug/elf", (*funcLowerer).lowerDebugFormatCall)
	RegisterStdlibLowerer("debug/dwarf", (*funcLowerer).lowerDebugFormatCall)
	RegisterStdlibLowerer("debug/pe", (*funcLowerer).lowerDebugFormatCall)
	RegisterStdlibLowerer("debug/macho", (*funcLowerer).lowerDebugFormatCall)
	RegisterStdlibLowerer("debug/gosym", (*funcLowerer).lowerDebugFormatCall)
	RegisterStdlibLowerer("debug/plan9obj", (*funcLowerer).lowerDebugFormatCall)
	RegisterStdlibLowerer("go/ast", (*funcLowerer).lowerGoToolCall)
	RegisterStdlibLowerer("go/token", (*funcLowerer).lowerGoToolCall)
	RegisterStdlibLowerer("go/parser", (*funcLowerer).lowerGoToolCall)
	RegisterStdlibLowerer("go/format", (*funcLowerer).lowerGoToolCall)
	RegisterStdlibLowerer("go/printer", (*funcLowerer).lowerGoPrinterCall)
	RegisterStdlibLowerer("go/build", (*funcLowerer).lowerGoBuildCall)
	RegisterStdlibLowerer("go/build/constraint", (*funcLowerer).lowerGoBuildConstraintCall)
	RegisterStdlibLowerer("go/types", (*funcLowerer).lowerGoTypesCall)
	RegisterStdlibLowerer("go/constant", (*funcLowerer).lowerGoConstantCall)
	RegisterStdlibLowerer("go/scanner", (*funcLowerer).lowerGoScannerCall)
	RegisterStdlibLowerer("go/doc", (*funcLowerer).lowerGoDocCall)
	RegisterStdlibLowerer("go/doc/comment", (*funcLowerer).lowerGoDocCommentCall)
	RegisterStdlibLowerer("go/importer", (*funcLowerer).lowerGoImporterCall)
	RegisterStdlibLowerer("net/http/cookiejar", (*funcLowerer).lowerNetHTTPCookiejarCall)
	RegisterStdlibLowerer("net/http/pprof", (*funcLowerer).lowerNetHTTPPprofCall)
	RegisterStdlibLowerer("net/http/httptest", (*funcLowerer).lowerNetHTTPTestCall)
	RegisterStdlibLowerer("net/http/httptrace", (*funcLowerer).lowerNetHTTPHttptraceCall)
	RegisterStdlibLowerer("net/http/cgi", (*funcLowerer).lowerNetHTTPCgiFcgiCall)
	RegisterStdlibLowerer("net/http/fcgi", (*funcLowerer).lowerNetHTTPCgiFcgiCall)
	RegisterStdlibLowerer("net/smtp", (*funcLowerer).lowerNetSMTPCall)
	RegisterStdlibLowerer("net/rpc", (*funcLowerer).lowerNetRPCCall)
	RegisterStdlibLowerer("net/rpc/jsonrpc", (*funcLowerer).lowerNetRPCJSONRPCCall)
	RegisterStdlibLowerer("net/netip", (*funcLowerer).lowerNetNetipCall)
	RegisterStdlibLowerer("database/sql/driver", (*funcLowerer).lowerDatabaseSQLDriverCall)
	RegisterStdlibLowerer("os/user", (*funcLowerer).lowerOsUserCall)
	RegisterStdlibLowerer("regexp/syntax", (*funcLowerer).lowerRegexpSyntaxCall)
	RegisterStdlibLowerer("runtime/debug", (*funcLowerer).lowerRuntimeDebugCall)
	RegisterStdlibLowerer("runtime/pprof", (*funcLowerer).lowerRuntimePprofCall)
	RegisterStdlibLowerer("runtime/trace", (*funcLowerer).lowerRuntimeTraceCall)
	RegisterStdlibLowerer("runtime/metrics", (*funcLowerer).lowerRuntimeMetricsCall)
	RegisterStdlibLowerer("runtime/coverage", (*funcLowerer).lowerRuntimeCoverageCall)
	RegisterStdlibLowerer("text/scanner", (*funcLowerer).lowerTextScannerCall)
	RegisterStdlibLowerer("text/tabwriter", (*funcLowerer).lowerTextTabwriterCall)
	RegisterStdlibLowerer("text/template/parse", (*funcLowerer).lowerTextTemplateParseCall)
	RegisterStdlibLowerer("compress/zlib", (*funcLowerer).lowerCompressZlibCall)
	RegisterStdlibLowerer("compress/bzip2", (*funcLowerer).lowerCompressBzip2Call)
	RegisterStdlibLowerer("compress/lzw", (*funcLowerer).lowerCompressLzwCall)
	RegisterStdlibLowerer("hash/fnv", (*funcLowerer).lowerHashFNVCall)
	RegisterStdlibLowerer("hash/maphash", (*funcLowerer).lowerHashMaphashCall)
	RegisterStdlibLowerer("hash/adler32", (*funcLowerer).lowerHashAdler32Call)
	RegisterStdlibLowerer("hash/crc64", (*funcLowerer).lowerHashCRC64Call)
	RegisterStdlibLowerer("expvar", (*funcLowerer).lowerExpvarCall)
	RegisterStdlibLowerer("log/syslog", (*funcLowerer).lowerLogSyslogCall)
	RegisterStdlibLowerer("index/suffixarray", (*funcLowerer).lowerIndexSuffixarrayCall)
	RegisterStdlibLowerer("testing", (*funcLowerer).lowerTestingCall)
	RegisterStdlibLowerer("testing/fstest", (*funcLowerer).lowerTestingFstestCall)
	RegisterStdlibLowerer("testing/iotest", (*funcLowerer).lowerTestingIotestCall)
	RegisterStdlibLowerer("testing/quick", (*funcLowerer).lowerTestingQuickCall)
	RegisterStdlibLowerer("testing/slogtest", (*funcLowerer).lowerTestingSlogtestCall)
	RegisterStdlibLowerer("sync/errgroup", (*funcLowerer).lowerSyncErrgroupCall)
	RegisterStdlibLowerer("syscall", (*funcLowerer).lowerSyscallCall)
	RegisterStdlibLowerer("math/cmplx", (*funcLowerer).lowerMathCmplxCall)
	RegisterStdlibLowerer("math/rand/v2", (*funcLowerer).lowerMathRandV2Call)
	RegisterStdlibLowerer("mime/quotedprintable", (*funcLowerer).lowerMimeQuotedprintableCall)
	RegisterStdlibLowerer("iter", (*funcLowerer).lowerIterCall)
	RegisterStdlibLowerer("unique", (*funcLowerer).lowerUniqueCall)
	RegisterStdlibLowerer("plugin", (*funcLowerer).lowerPluginCall)
	RegisterStdlibLowerer("time/tzdata", func(fl *funcLowerer, instr *ssa.Call, callee *ssa.Function) (bool, error) {
		return true, nil // side-effect-only import, no callable functions
	})
}


// --- merged from stdlib_lower.go ---

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

// --- merged from stdlib_lower2.go ---

func (fl *funcLowerer) lowerCryptoSHA1Call(instr *ssa.Call, callee *ssa.Function) (bool, error) {
	switch callee.Name() {
	case "Sum":
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

// --- merged from stdlib_lower3.go ---

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
			return true, nil 		}
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
