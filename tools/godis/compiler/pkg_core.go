// Package type stubs for core packages: fmt, strconv, errors, strings, bytes,
// sort, io, os, time, sync, log, flag, context, bufio, embed, unsafe, inferno/sys.
package compiler

import (
	"go/constant"
	"go/token"
	"go/types"
)

func init() {
	RegisterPackage("bufio", buildBufioPackage)
	RegisterPackage("bytes", buildBytesPackage)
	RegisterPackage("context", buildContextPackage)
	RegisterPackage("embed", buildEmbedPackage)
	RegisterPackage("errors", buildErrorsPackage)
	RegisterPackage("flag", buildFlagPackage)
	RegisterPackage("fmt", buildFmtPackage)
	RegisterPackage("io", buildIOPackage)
	RegisterPackage("log", buildLogPackage)
	RegisterPackage("os", buildOsPackage)
	RegisterPackage("sort", buildSortPackage)
	RegisterPackage("strconv", buildStrconvPackage)
	RegisterPackage("strings", buildStringsPackage)
	RegisterPackage("sync", buildSyncPackage)
	RegisterPackage("inferno/sys", buildSysPackage)
	RegisterPackage("time", buildTimePackage)
	RegisterPackage("unsafe", buildUnsafePackage)
}

// buildBufioPackage creates the type-checked bufio package stub.
func buildBufioPackage() *types.Package {
	pkg := types.NewPackage("bufio", "bufio")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	byteSliceIO := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
	readerType := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceIO)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerType.Complete()

	// io.Writer interface
	writerType := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceIO)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	writerType.Complete()

	// type Scanner struct { ... }
	scannerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "src", readerType, false),
	}, nil)
	scannerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Scanner", nil),
		scannerStruct, nil)
	scope.Insert(scannerType.Obj())
	scannerPtr := types.NewPointer(scannerType)

	// func NewScanner(r io.Reader) *Scanner
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewScanner",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", scannerPtr)),
			false)))

	// type Reader struct { ... }
	readerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "rd", readerType, false),
	}, nil)
	bufReaderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		readerStruct, nil)
	scope.Insert(bufReaderType.Obj())
	bufReaderPtr := types.NewPointer(bufReaderType)

	// func NewReader(rd io.Reader) *Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "rd", readerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", bufReaderPtr)),
			false)))

	// type Writer struct { ... }
	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "wr", writerType, false),
	}, nil)
	bufWriterType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(bufWriterType.Obj())
	bufWriterPtr := types.NewPointer(bufWriterType)

	// func NewWriter(w io.Writer) *Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", writerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", bufWriterPtr)),
			false)))

	// func ScanLines(data []byte, atEOF bool) (advance int, token []byte, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ScanLines",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "atEOF", types.Typ[types.Bool])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "advance", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "token_", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func ScanWords similar signature
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ScanWords",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "atEOF", types.Typ[types.Bool])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "advance", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "token_", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func ScanRunes similar signature
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ScanRunes",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "atEOF", types.Typ[types.Bool])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "advance", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "token_", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func ScanBytes similar signature
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ScanBytes",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "atEOF", types.Typ[types.Bool])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "advance", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "token_", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func NewReaderSize(rd io.Reader, size int) *Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReaderSize",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rd", readerType),
				types.NewVar(token.NoPos, pkg, "size", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", bufReaderPtr)),
			false)))

	// func NewWriterSize(w io.Writer, size int) *Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriterSize",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", writerType),
				types.NewVar(token.NoPos, pkg, "size", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", bufWriterPtr)),
			false)))

	// SplitFunc type
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	splitFuncSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "data", byteSlice),
			types.NewVar(token.NoPos, nil, "atEOF", types.Typ[types.Bool])),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "advance", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "token", byteSlice),
			types.NewVar(token.NoPos, nil, "err", errType)),
		false)

	// Scanner methods
	scanRecv := types.NewVar(token.NoPos, pkg, "s", scannerPtr)
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Scan",
		types.NewSignatureType(scanRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Text",
		types.NewSignatureType(scanRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(scanRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Err",
		types.NewSignatureType(scanRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Split",
		types.NewSignatureType(scanRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "split", splitFuncSig)),
			nil, false)))
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Buffer",
		types.NewSignatureType(scanRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "buf", byteSlice),
				types.NewVar(token.NoPos, nil, "max", types.Typ[types.Int])),
			nil, false)))

	// Reader methods
	readRecv := types.NewVar(token.NoPos, pkg, "b", bufReaderPtr)
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(readRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadByte",
		types.NewSignatureType(readRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadString",
		types.NewSignatureType(readRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delim", types.Typ[types.Byte])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadLine",
		types.NewSignatureType(readRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "line", byteSlice),
				types.NewVar(token.NoPos, nil, "isPrefix", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadRune",
		types.NewSignatureType(readRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, nil, "size", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnreadByte",
		types.NewSignatureType(readRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnreadRune",
		types.NewSignatureType(readRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Peek",
		types.NewSignatureType(readRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Buffered",
		types.NewSignatureType(readRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(readRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", readerType)),
			nil, false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadBytes",
		types.NewSignatureType(readRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delim", types.Typ[types.Byte])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadSlice",
		types.NewSignatureType(readRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delim", types.Typ[types.Byte])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "line", byteSlice),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteTo",
		types.NewSignatureType(readRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", writerType)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Discard",
		types.NewSignatureType(readRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "discarded", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	bufReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(readRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Writer methods
	writeRecv := types.NewVar(token.NoPos, pkg, "b", bufWriterPtr)
	bufWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(writeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "nn", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	bufWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteByte",
		types.NewSignatureType(writeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "c", types.Typ[types.Byte])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	bufWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteString",
		types.NewSignatureType(writeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	bufWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteRune",
		types.NewSignatureType(writeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", types.Typ[types.Rune])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "size", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	bufWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(writeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	bufWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Available",
		types.NewSignatureType(writeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	bufWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Buffered",
		types.NewSignatureType(writeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	bufWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(writeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", writerType)),
			nil, false)))
	bufWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadFrom",
		types.NewSignatureType(writeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", readerType)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	bufWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "AvailableBuffer",
		types.NewSignatureType(writeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))
	bufWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(writeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// type ReadWriter struct
	bufRWType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ReadWriter", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(bufRWType.Obj())

	// func NewReadWriter(r *Reader, w *Writer) *ReadWriter
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReadWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", bufReaderPtr),
				types.NewVar(token.NoPos, pkg, "w", bufWriterPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(bufRWType))),
			false)))

	// MaxScanTokenSize constant
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxScanTokenSize", types.Typ[types.Int], constant.MakeInt64(65536)))

	// ErrTooLong etc.
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrTooLong", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNegativeAdvance", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrAdvanceTooFar", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrBadReadCount", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrFinalToken", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrBufferFull", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrInvalidUnreadByte", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrInvalidUnreadRune", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNegativeCount", errType))

	pkg.MarkComplete()
	return pkg
}

func buildBytesPackage() *types.Package {
	pkg := types.NewPackage("bytes", "bytes")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// const MinRead = 512
	scope.Insert(types.NewConst(token.NoPos, pkg, "MinRead",
		types.Typ[types.Int], constant.MakeInt64(512)))

	// var ErrTooLarge error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrTooLarge",
		types.Universe.Lookup("error").Type()))

	// func Contains(b, subslice []byte) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Contains",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", byteSlice),
				types.NewVar(token.NoPos, pkg, "subslice", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Equal(a, b []byte) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "a", byteSlice),
				types.NewVar(token.NoPos, pkg, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Compare(a, b []byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "a", byteSlice),
				types.NewVar(token.NoPos, pkg, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	bbBool := func(name string) {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, pkg, "s", byteSlice),
					types.NewVar(token.NoPos, pkg, "prefix", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
				false)))
	}
	bbBool("HasPrefix")
	bbBool("HasSuffix")

	// func Index(s, sep []byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "sep", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func IndexByte(b []byte, c byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IndexByte",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", byteSlice),
				types.NewVar(token.NoPos, pkg, "c", types.Typ[types.Byte])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Count(s, sep []byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Count",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "sep", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	bbs := func(name string) {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "s", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
				false)))
	}
	bbs("TrimSpace")
	bbs("ToLower")
	bbs("ToUpper")

	// func Repeat(b []byte, count int) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Repeat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", byteSlice),
				types.NewVar(token.NoPos, pkg, "count", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func Join(s [][]byte, sep []byte) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Join",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.NewSlice(byteSlice)),
				types.NewVar(token.NoPos, pkg, "sep", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func Split(s, sep []byte) [][]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Split",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "sep", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(byteSlice))),
			false)))

	// func Replace(s, old, new []byte, n int) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Replace",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "old", byteSlice),
				types.NewVar(token.NoPos, pkg, "new", byteSlice),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func ReplaceAll(s, old, new []byte) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReplaceAll",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "old", byteSlice),
				types.NewVar(token.NoPos, pkg, "new", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func Trim(s []byte, cutset string) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Trim",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "cutset", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func TrimLeft(s []byte, cutset string) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimLeft",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "cutset", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func TrimRight(s []byte, cutset string) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimRight",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "cutset", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func TrimPrefix(s, prefix []byte) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimPrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "prefix", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func TrimSuffix(s, suffix []byte) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimSuffix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "suffix", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func LastIndex(s, sep []byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LastIndex",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "sep", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func SplitN(s, sep []byte, n int) [][]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SplitN",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "sep", byteSlice),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(byteSlice))),
			false)))

	// func Fields(s []byte) [][]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fields",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(byteSlice))),
			false)))

	// func EqualFold(s, t []byte) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EqualFold",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "t", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func ContainsRune(b []byte, r rune) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ContainsRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", byteSlice),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func ContainsAny(b []byte, chars string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ContainsAny",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", byteSlice),
				types.NewVar(token.NoPos, pkg, "chars", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Map(mapping func(r rune) rune, s []byte) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Map",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "mapping", types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
					types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Rune])),
					false)),
				types.NewVar(token.NoPos, pkg, "s", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// Buffer type
	bufType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Buffer", nil), types.NewStruct(nil, nil), nil)
	bufPtr := types.NewPointer(bufType)
	scope.Insert(bufType.Obj())

	// func NewBuffer(buf []byte) *Buffer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewBuffer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "buf", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", bufPtr)),
			false)))

	// func NewBufferString(s string) *Buffer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewBufferString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", bufPtr)),
			false)))

	// Buffer methods
	bufRecv := types.NewVar(token.NoPos, pkg, "b", bufPtr)

	// func (b *Buffer) Write(p []byte) (n int, err error)
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", types.Universe.Lookup("error").Type())),
			false)))

	// func (b *Buffer) WriteString(s string) (n int, err error)
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteString",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", types.Universe.Lookup("error").Type())),
			false)))

	// func (b *Buffer) WriteByte(c byte) error
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteByte",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "c", types.Typ[types.Byte])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Universe.Lookup("error").Type())),
			false)))

	// func (b *Buffer) String() string
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (b *Buffer) Bytes() []byte
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func (b *Buffer) Len() int
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func (b *Buffer) Reset()
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(bufRecv, nil, nil, nil, nil, false)))

	// func (b *Buffer) Read(p []byte) (n int, err error)
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", types.Universe.Lookup("error").Type())),
			false)))

	// func (b *Buffer) ReadByte() (byte, error)
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadByte",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "", types.Universe.Lookup("error").Type())),
			false)))

	// func (b *Buffer) ReadString(delim byte) (line string, err error)
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadString",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "delim", types.Typ[types.Byte])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "line", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "err", types.Universe.Lookup("error").Type())),
			false)))

	// More bytes functions
	errType := types.Universe.Lookup("error").Type()
	funcPred := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
		false)

	bbs("ToTitle")
	bbs("Title")
	bbs("ToValidUTF8")
	bbs("Runes")

	// func IndexAny(s []byte, chars string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IndexAny",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "chars", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func LastIndexByte(s []byte, c byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LastIndexByte",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "c", types.Typ[types.Byte])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func LastIndexAny(s []byte, chars string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LastIndexAny",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "chars", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func IndexRune(s []byte, r rune) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IndexRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func IndexFunc(s []byte, f func(rune) bool) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IndexFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "f", funcPred)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func LastIndexFunc(s []byte, f func(rune) bool) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LastIndexFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "f", funcPred)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func SplitAfter(s, sep []byte) [][]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SplitAfter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "sep", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(byteSlice))),
			false)))

	// func SplitAfterN(s, sep []byte, n int) [][]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SplitAfterN",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "sep", byteSlice),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(byteSlice))),
			false)))

	// func FieldsFunc(s []byte, f func(rune) bool) [][]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FieldsFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "f", funcPred)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(byteSlice))),
			false)))

	// func ContainsFunc(b []byte, f func(rune) bool) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ContainsFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", byteSlice),
				types.NewVar(token.NoPos, pkg, "f", funcPred)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func TrimFunc(s []byte, f func(rune) bool) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "f", funcPred)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func TrimLeftFunc(s []byte, f func(rune) bool) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimLeftFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "f", funcPred)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func TrimRightFunc(s []byte, f func(rune) bool) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimRightFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "f", funcPred)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func Clone(b []byte) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func CutPrefix(s, prefix []byte) (after []byte, found bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CutPrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "prefix", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "after", byteSlice),
				types.NewVar(token.NoPos, pkg, "found", types.Typ[types.Bool])),
			false)))

	// func CutSuffix(s, suffix []byte) (before []byte, found bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CutSuffix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "suffix", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "before", byteSlice),
				types.NewVar(token.NoPos, pkg, "found", types.Typ[types.Bool])),
			false)))

	// func Cut(s, sep []byte) (before, after []byte, found bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Cut",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", byteSlice),
				types.NewVar(token.NoPos, pkg, "sep", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "before", byteSlice),
				types.NewVar(token.NoPos, pkg, "after", byteSlice),
				types.NewVar(token.NoPos, pkg, "found", types.Typ[types.Bool])),
			false)))

	// Additional Buffer methods
	// func (b *Buffer) Cap() int
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cap",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func (b *Buffer) Grow(n int)
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "Grow",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			nil, false)))

	// func (b *Buffer) WriteRune(r rune) (n int, err error)
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteRune",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func (b *Buffer) ReadRune() (r rune, size int, err error)
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadRune",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, pkg, "size", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func (b *Buffer) UnreadByte() error
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnreadByte",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (b *Buffer) UnreadRune() error
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnreadRune",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (b *Buffer) ReadBytes(delim byte) (line []byte, err error)
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadBytes",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "delim", types.Typ[types.Byte])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "line", byteSlice),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func (b *Buffer) Next(n int) []byte
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func (b *Buffer) Truncate(n int)
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "Truncate",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			nil, false)))

	// func (b *Buffer) WriteTo(w io.Writer) (n int64, err error)
	ioWriterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterIface.Complete()
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteTo",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func (b *Buffer) ReadFrom(r io.Reader) (n int64, err error)
	ioReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderIface.Complete()
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadFrom",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReaderIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func (b *Buffer) Available() int — Go 1.21+
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "Available",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func (b *Buffer) AvailableBuffer() []byte — Go 1.21+
	bufType.AddMethod(types.NewFunc(token.NoPos, pkg, "AvailableBuffer",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func NewReader(b []byte) *Reader — stub
	readerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Reader", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(readerType.Obj())
	readerPtr := types.NewPointer(readerType)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", readerPtr)),
			false)))

	// Reader methods
	rRecv := types.NewVar(token.NoPos, pkg, "r", readerPtr)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadByte",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", byteSlice)),
			nil, false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadAt",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", byteSlice),
				types.NewVar(token.NoPos, pkg, "off", types.Typ[types.Int64])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seek",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "offset", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "whence", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteTo",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnreadByte",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadRune",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ch", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, pkg, "size", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnreadRune",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// unicode.SpecialCase stand-in ([]CaseRange opaque)
	specialCaseType := types.NewSlice(types.NewStruct(nil, nil))

	// func ToUpperSpecial(c unicode.SpecialCase, s []byte) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToUpperSpecial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", specialCaseType),
				types.NewVar(token.NoPos, pkg, "s", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func ToLowerSpecial(c unicode.SpecialCase, s []byte) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToLowerSpecial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", specialCaseType),
				types.NewVar(token.NoPos, pkg, "s", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func ToTitleSpecial(c unicode.SpecialCase, s []byte) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToTitleSpecial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", specialCaseType),
				types.NewVar(token.NoPos, pkg, "s", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildContextPackage creates the type-checked context package stub.
func buildContextPackage() *types.Package {
	pkg := types.NewPackage("context", "context")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Context interface { Deadline, Done, Err, Value }
	anyTypeCtx := types.NewInterfaceType(nil, nil)
	anyTypeCtx.Complete()
	emptyStructType := types.NewStruct(nil, nil)
	ctxIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Deadline",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "deadline", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
				false)),
		types.NewFunc(token.NoPos, pkg, "Done",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "",
					types.NewChan(types.RecvOnly, emptyStructType))),
				false)),
		types.NewFunc(token.NoPos, pkg, "Err",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Value",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyTypeCtx)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyTypeCtx)),
				false)),
	}, nil)
	ctxIface.Complete()
	ctxType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Context", nil),
		ctxIface, nil)
	scope.Insert(ctxType.Obj())

	// type CancelFunc func()
	cancelSig := types.NewSignatureType(nil, nil, nil, nil, nil, false)
	cancelType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CancelFunc", nil),
		cancelSig, nil)
	scope.Insert(cancelType.Obj())

	// func Background() Context
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Background",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ctxType)),
			false)))

	// func TODO() Context
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TODO",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ctxType)),
			false)))

	// func WithCancel(parent Context) (Context, CancelFunc)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithCancel",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "parent", ctxType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ctxType),
				types.NewVar(token.NoPos, pkg, "", cancelType)),
			false)))

	// func WithValue(parent Context, key, val any) Context
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "parent", ctxType),
				types.NewVar(token.NoPos, pkg, "key", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "val", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ctxType)),
			false)))

	// var Canceled error
	scope.Insert(types.NewVar(token.NoPos, pkg, "Canceled", errType))

	// var DeadlineExceeded error
	scope.Insert(types.NewVar(token.NoPos, pkg, "DeadlineExceeded", errType))

	// type CancelCauseFunc func(cause error)
	cancelCauseSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "cause", errType)),
		nil, false)
	cancelCauseType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CancelCauseFunc", nil),
		cancelCauseSig, nil)
	scope.Insert(cancelCauseType.Obj())

	// func WithTimeout(parent Context, timeout time.Duration) (Context, CancelFunc)
	// time.Duration is int64 underneath
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithTimeout",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "parent", ctxType),
				types.NewVar(token.NoPos, pkg, "timeout", types.Typ[types.Int64])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ctxType),
				types.NewVar(token.NoPos, pkg, "", cancelType)),
			false)))

	// func WithDeadline(parent Context, d time.Time) (Context, CancelFunc)
	// time.Time as empty struct placeholder
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithDeadline",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "parent", ctxType),
				types.NewVar(token.NoPos, pkg, "d", types.NewStruct(nil, nil))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ctxType),
				types.NewVar(token.NoPos, pkg, "", cancelType)),
			false)))

	// func WithCancelCause(parent Context) (ctx Context, cancel CancelCauseFunc)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithCancelCause",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "parent", ctxType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ctxType),
				types.NewVar(token.NoPos, pkg, "", cancelCauseType)),
			false)))

	// func Cause(c Context) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Cause",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "c", ctxType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func AfterFunc(ctx Context, f func()) (stop func() bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AfterFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "f", types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
					false))),
			false)))

	// func WithoutCancel(parent Context) Context
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithoutCancel",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "parent", ctxType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ctxType)),
			false)))

	// func WithDeadlineCause(parent Context, d time.Time, cause error) (Context, CancelFunc)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithDeadlineCause",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "parent", ctxType),
				types.NewVar(token.NoPos, pkg, "d", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "cause", errType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ctxType),
				types.NewVar(token.NoPos, pkg, "", cancelType)),
			false)))

	// func WithTimeoutCause(parent Context, timeout time.Duration, cause error) (Context, CancelFunc)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithTimeoutCause",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "parent", ctxType),
				types.NewVar(token.NoPos, pkg, "timeout", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "cause", errType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ctxType),
				types.NewVar(token.NoPos, pkg, "", cancelType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildEmbedPackage creates the type-checked embed package stub.
func buildEmbedPackage() *types.Package {
	pkg := types.NewPackage("embed", "embed")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()

	// type FS struct { ... }
	fsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "files", types.Typ[types.Int], false),
	}, nil)
	fsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FS", nil),
		fsStruct, nil)
	scope.Insert(fsType.Obj())

	// fs.File interface { Stat() (FileInfo, error); Read([]byte) (int, error); Close() error }
	byteSliceEmbed := types.NewSlice(types.Typ[types.Byte])
	fsFileIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Stat",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.NewInterfaceType([]*types.Func{
						types.NewFunc(token.NoPos, nil, "Name",
							types.NewSignatureType(nil, nil, nil, nil,
								types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
						types.NewFunc(token.NoPos, nil, "Size",
							types.NewSignatureType(nil, nil, nil, nil,
								types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
						types.NewFunc(token.NoPos, nil, "IsDir",
							types.NewSignatureType(nil, nil, nil, nil,
								types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
					}, nil)),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceEmbed)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	fsFileIface.Complete()

	// fs.DirEntry interface { Name() string; IsDir() bool; Type() FileMode; Info() (FileInfo, error) }
	fsDirEntryIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Type",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)),
	}, nil)
	fsDirEntryIface.Complete()

	// FS methods
	fsRecv := types.NewVar(token.NoPos, nil, "f", fsType)
	fsType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", fsFileIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	fsType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadDir",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(fsDirEntryIface)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	fsType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadFile",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Sub(dir string) (fs.FS, error) - returns an fs.FS stand-in interface
	embedFsIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fsFileIface),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	embedFsIface.Complete()
	fsType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sub",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", embedFsIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildErrorsPackage creates the type-checked errors package stub
// with the signature for New(text string) error.
func buildErrorsPackage() *types.Package {
	pkg := types.NewPackage("errors", "errors")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// func New(text string) error
	newSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String])),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New", newSig))

	// func Is(err, target error) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Is",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "err", errType),
				types.NewVar(token.NoPos, pkg, "target", errType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Unwrap(err error) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func As(err error, target any) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "As",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "err", errType),
				types.NewVar(token.NoPos, pkg, "target", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Join(errs ...error) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Join",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "errs",
				types.NewSlice(errType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// var ErrUnsupported error (Go 1.21+)
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrUnsupported", errType))

	pkg.MarkComplete()
	return pkg
}

// buildFlagPackage creates the type-checked flag package stub.
func buildFlagPackage() *types.Package {
	pkg := types.NewPackage("flag", "flag")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Writer stand-in for SetOutput/Output
	ioWriterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
	}, nil)
	ioWriterIface.Complete()

	// func Parse()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func String(name string, value string, usage string) *string
	strPtr := types.NewPointer(types.Typ[types.String])
	scope.Insert(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", strPtr)),
			false)))

	// func Int(name string, value int, usage string) *int
	intPtr := types.NewPointer(types.Typ[types.Int])
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func Bool(name string, value bool, usage string) *bool
	boolPtr := types.NewPointer(types.Typ[types.Bool])
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Bool",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", boolPtr)),
			false)))

	// func Arg(i int) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Arg",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Args() []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Args",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// func NArg() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NArg",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func NFlag() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NFlag",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Float64(name string, value float64, usage string) *float64
	float64Ptr := types.NewPointer(types.Typ[types.Float64])
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", float64Ptr)),
			false)))

	// func Int64(name string, value int64, usage string) *int64
	int64Ptr := types.NewPointer(types.Typ[types.Int64])
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", int64Ptr)),
			false)))

	// func Uint(name string, value uint, usage string) *uint
	uintPtr := types.NewPointer(types.Typ[types.Uint])
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Uint]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", uintPtr)),
			false)))

	// func Uint64(name string, value uint64, usage string) *uint64
	uint64Ptr := types.NewPointer(types.Typ[types.Uint64])
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", uint64Ptr)),
			false)))

	// func Duration(name string, value time.Duration, usage string) *time.Duration
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Duration",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", int64Ptr)),
			false)))

	// Var functions (set variable directly)
	// func StringVar(p *string, name string, value string, usage string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StringVar",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", strPtr),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			nil, false)))

	// func IntVar(p *int, name string, value int, usage string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IntVar",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", intPtr),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			nil, false)))

	// func BoolVar(p *bool, name string, value bool, usage string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BoolVar",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", boolPtr),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			nil, false)))

	// func Parsed() bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Parsed",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Set(name, value string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Value interface (forward declaration needed for Flag struct)
	valueIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, pkg, "Set",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	valueIface.Complete()
	valueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Value", nil),
		valueIface, nil)
	scope.Insert(valueType.Obj())

	// func Lookup(name string) *Flag
	// type Flag struct { Name, Usage, DefValue string; Value Value }
	flagStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Usage", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", valueType, false),
		types.NewField(token.NoPos, pkg, "DefValue", types.Typ[types.String], false),
	}, nil)
	flagType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Flag", nil),
		flagStruct, nil)
	scope.Insert(flagType.Obj())
	flagTypePtr := types.NewPointer(flagType)

	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", flagTypePtr)),
			false)))

	// type FlagSet struct {}
	flagSetStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Usage", types.NewSignatureType(nil, nil, nil, nil, nil, false), false),
	}, nil)
	flagSetType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FlagSet", nil),
		flagSetStruct, nil)
	scope.Insert(flagSetType.Obj())
	flagSetPtr := types.NewPointer(flagSetType)

	// func NewFlagSet(name string, errorHandling ErrorHandling) *FlagSet
	errorHandlingType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ErrorHandling", nil),
		types.Typ[types.Int], nil)
	scope.Insert(errorHandlingType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "ContinueOnError", errorHandlingType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ExitOnError", errorHandlingType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "PanicOnError", errorHandlingType, constant.MakeInt64(2)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFlagSet",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "errorHandling", errorHandlingType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", flagSetPtr)),
			false)))

	// func CommandLine() *FlagSet
	scope.Insert(types.NewVar(token.NoPos, pkg, "CommandLine", flagSetPtr))

	// FlagSet methods (same as package-level)
	fsRecv := types.NewVar(token.NoPos, nil, "f", flagSetPtr)
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "arguments", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", strPtr)),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bool",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", boolPtr)),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parsed",
		types.NewSignatureType(fsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "NArg",
		types.NewSignatureType(fsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "NFlag",
		types.NewSignatureType(fsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Arg",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Args",
		types.NewSignatureType(fsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// FlagSet remaining methods (mirror package-level functions)
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", float64Ptr)),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int64",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", int64Ptr)),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Uint]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", uintPtr)),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", uint64Ptr)),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Duration",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", int64Ptr)),
			false)))
	// FlagSet Var functions
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "StringVar",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", strPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			nil, false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "IntVar",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", intPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			nil, false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "BoolVar",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", boolPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			nil, false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64Var",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", float64Ptr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			nil, false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int64Var",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", int64Ptr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			nil, false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "UintVar",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", uintPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Uint]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			nil, false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64Var",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", uint64Ptr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			nil, false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "DurationVar",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", int64Ptr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			nil, false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", flagTypePtr)),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "PrintDefaults",
		types.NewSignatureType(fsRecv, nil, nil, nil, nil, false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetOutput",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "output", ioWriterIface)),
			nil, false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(fsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "ErrorHandling",
		types.NewSignatureType(fsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errorHandlingType)),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Output",
		types.NewSignatureType(fsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ioWriterIface)),
			false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "errorHandling", errorHandlingType)),
			nil, false)))
	flagFnType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "fn",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", flagTypePtr)),
				nil, false))),
		nil, false)
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Visit",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "fn",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", flagTypePtr)),
					nil, false))),
			nil, false)))
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "VisitAll",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "fn",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", flagTypePtr)),
					nil, false))),
			nil, false)))

	// Package-level missing functions
	// func PrintDefaults()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PrintDefaults",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))
	// func Visit(fn func(*Flag))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Visit", flagFnType))
	// func VisitAll(fn func(*Flag))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "VisitAll", flagFnType))
	// func Float64Var(p *float64, name string, value float64, usage string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float64Var",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", float64Ptr),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			nil, false)))
	// func Int64Var(p *int64, name string, value int64, usage string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int64Var",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", int64Ptr),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			nil, false)))
	// func UintVar(p *uint, name string, value uint, usage string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UintVar",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", uintPtr),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Uint]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			nil, false)))
	// func Uint64Var(p *uint64, name string, value uint64, usage string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint64Var",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", uint64Ptr),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			nil, false)))
	// func DurationVar(p *int64, name string, value int64, usage string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DurationVar",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", int64Ptr),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			nil, false)))
	// func Func(name, usage string, fn func(string) error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Func",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "fn",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
						false))),
			nil, false)))
	// func BoolFunc(name, usage string, fn func(string) error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BoolFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "fn",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
						false))),
			nil, false)))
	// encoding.TextUnmarshaler stand-in for TextVar
	textUnmarshalerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "UnmarshalText",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "text", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	textUnmarshalerIface.Complete()

	// func TextVar(p encoding.TextUnmarshaler, name, usage string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TextVar",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", textUnmarshalerIface),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			nil, false)))
	// func UnquoteUsage(flag *Flag) (name string, usage string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UnquoteUsage",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "flag", flagTypePtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Var(value Value, name string, usage string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Var",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "value", valueType),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "usage", types.Typ[types.String])),
			nil, false)))

	// FlagSet.Var
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Var",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "value", valueType),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			nil, false)))
	// FlagSet.Func
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Func",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "fn",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
						false))),
			nil, false)))
	// FlagSet.BoolFunc
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "BoolFunc",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "fn",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
						false))),
			nil, false)))
	// FlagSet.TextVar
	flagSetType.AddMethod(types.NewFunc(token.NoPos, pkg, "TextVar",
		types.NewSignatureType(fsRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", textUnmarshalerIface),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "usage", types.Typ[types.String])),
			nil, false)))

	// Getter interface (extends Value with Get() any)
	getterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Get",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
				false)),
	}, []types.Type{valueType})
	getterIface.Complete()
	getterType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Getter", nil),
		getterIface, nil)
	scope.Insert(getterType.Obj())

	// var ErrHelp error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrHelp", errType))

	// var Usage func()
	scope.Insert(types.NewVar(token.NoPos, pkg, "Usage", types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func SetOutput(w io.Writer)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetOutput",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "output", ioWriterIface)),
			nil, false)))

	// func Output() io.Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Output",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioWriterIface)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildFmtPackage creates the type-checked fmt package stub
// with signatures for Sprintf, Printf, and Println.
func buildFmtPackage() *types.Package {
	pkg := types.NewPackage("fmt", "fmt")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anySlice := types.NewSlice(types.NewInterfaceType(nil, nil))

	// func Sprintf(format string, a ...any) string
	sprintfSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
			types.NewVar(token.NoPos, pkg, "a", anySlice),
		),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sprintf", sprintfSig))

	// func Printf(format string, a ...any) (int, error)
	printfSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
			types.NewVar(token.NoPos, pkg, "a", anySlice),
		),
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
			types.NewVar(token.NoPos, pkg, "", errType),
		),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Printf", printfSig))

	// func Println(a ...any) (int, error)
	printlnSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, pkg, "a", anySlice)),
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
			types.NewVar(token.NoPos, pkg, "", errType),
		),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Println", printlnSig))

	// func Errorf(format string, a ...any) error
	errorfSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
			types.NewVar(token.NoPos, pkg, "a", anySlice),
		),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Errorf", errorfSig))

	// func Sprint(a ...any) string
	sprintSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, pkg, "a", anySlice)),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sprint", sprintSig))

	// func Print(a ...any) (int, error)
	printSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, pkg, "a", anySlice)),
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
			types.NewVar(token.NoPos, pkg, "", errType),
		),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Print", printSig))

	// io.Writer interface for Fprint/Fprintf/Fprintln
	writerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	writerIface.Complete()

	// func Fprintf(w io.Writer, format string, a ...any) (int, error)
	fprintfSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "w", writerIface),
			types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
			types.NewVar(token.NoPos, pkg, "a", anySlice),
		),
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
			types.NewVar(token.NoPos, pkg, "", errType),
		),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fprintf", fprintfSig))

	// func Fprintln(w io.Writer, a ...any) (int, error)
	fprintlnSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "w", writerIface),
			types.NewVar(token.NoPos, pkg, "a", anySlice),
		),
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
			types.NewVar(token.NoPos, pkg, "", errType),
		),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fprintln", fprintlnSig))

	// func Fprint(w io.Writer, a ...any) (int, error)
	fprintSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "w", writerIface),
			types.NewVar(token.NoPos, pkg, "a", anySlice),
		),
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
			types.NewVar(token.NoPos, pkg, "", errType),
		),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fprint", fprintSig))

	// func Sprintln(a ...any) string
	sprintlnSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, pkg, "a", anySlice)),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sprintln", sprintlnSig))

	// func Sscan(str string, a ...any) (int, error)
	sscanSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "str", types.Typ[types.String]),
			types.NewVar(token.NoPos, pkg, "a", anySlice)),
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
			types.NewVar(token.NoPos, pkg, "", errType)),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sscan", sscanSig))

	// func Sscanf(str string, format string, a ...any) (int, error)
	sscanfSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "str", types.Typ[types.String]),
			types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
			types.NewVar(token.NoPos, pkg, "a", anySlice)),
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
			types.NewVar(token.NoPos, pkg, "", errType)),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sscanf", sscanfSig))

	// type Stringer interface { String() string }
	stringerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
	}, nil)
	stringerIface.Complete()
	stringerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Stringer", nil),
		stringerIface, nil)
	scope.Insert(stringerType.Obj())

	// type GoStringer interface { GoString() string }
	goStringerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "GoString",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
	}, nil)
	goStringerIface.Complete()
	goStringerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "GoStringer", nil),
		goStringerIface, nil)
	scope.Insert(goStringerType.Obj())

	// type State interface { Write, Width, Precision, Flag }
	byteSliceForState := types.NewSlice(types.Typ[types.Byte])
	stateIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceForState)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "Width",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "wid", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Precision",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "prec", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Flag",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
	}, nil)
	stateIface.Complete()
	stateType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "State", nil), stateIface, nil)
	scope.Insert(stateType.Obj())

	// type Formatter interface { Format(f State, verb rune) }
	formatterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Format",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "f", stateType),
					types.NewVar(token.NoPos, nil, "verb", types.Typ[types.Rune])),
				nil, false)),
	}, nil)
	formatterIface.Complete()
	formatterType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Formatter", nil), formatterIface, nil)
	scope.Insert(formatterType.Obj())

	// type ScanState interface { ReadRune, UnreadRune, SkipSpace, Token, Width, Read }
	scanStateIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ReadRune",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Rune]),
					types.NewVar(token.NoPos, nil, "size", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "UnreadRune",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "SkipSpace",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, pkg, "Token",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "skipSpace", types.Typ[types.Bool]),
					types.NewVar(token.NoPos, nil, "f",
						types.NewSignatureType(nil, nil, nil,
							types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Rune])),
							types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "token", types.NewSlice(types.Typ[types.Byte])),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "Width",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "wid", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "buf", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
	}, nil)
	scanStateIface.Complete()
	scanStateType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ScanState", nil), scanStateIface, nil)
	scope.Insert(scanStateType.Obj())

	// type Scanner interface { Scan(state ScanState, verb rune) error }
	scannerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Scan",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "state", scanStateType),
					types.NewVar(token.NoPos, nil, "verb", types.Typ[types.Rune])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	scannerIface.Complete()
	scannerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Scanner", nil), scannerIface, nil)
	scope.Insert(scannerType.Obj())

	// io.Reader interface for Fscan/Fscanf/Fscanln
	readerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerIface.Complete()

	// func Scan(a ...any) (int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Scan",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "a", anySlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func Scanf(format string, a ...any) (int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Scanf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "a", anySlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func Scanln(a ...any) (int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Scanln",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "a", anySlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func Sscanln(str string, a ...any) (int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sscanln",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "str", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "a", anySlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func Fscan(r io.Reader, a ...any) (int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fscan",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", readerIface),
				types.NewVar(token.NoPos, pkg, "a", anySlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func Fscanf(r io.Reader, format string, a ...any) (int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fscanf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", readerIface),
				types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "a", anySlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func Fscanln(r io.Reader, a ...any) (int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fscanln",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", readerIface),
				types.NewVar(token.NoPos, pkg, "a", anySlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func Appendf(b []byte, format string, a ...any) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Appendf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "a", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			true)))

	// func Append(b []byte, a ...any) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Append",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "a", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			true)))

	// func Appendln(b []byte, a ...any) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Appendln",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "a", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			true)))

	// FormatString(state State, verb rune) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FormatString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "state", stateType),
				types.NewVar(token.NoPos, pkg, "verb", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildIOPackage() *types.Package {
	pkg := types.NewPackage("io", "io")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Reader interface { Read(p []byte) (n int, err error) }
	readerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerIface.Complete()
	readerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		readerIface, nil)
	scope.Insert(readerType.Obj())

	// type Writer interface { Write(p []byte) (n int, err error) }
	writerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	writerIface.Complete()
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerIface, nil)
	scope.Insert(writerType.Obj())

	// var EOF error
	scope.Insert(types.NewVar(token.NoPos, pkg, "EOF", errType))

	// var Discard Writer
	scope.Insert(types.NewVar(token.NoPos, pkg, "Discard", writerType))

	// func ReadAll(r Reader) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadAll",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func WriteString(w Writer, s string) (n int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", writerType),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func Copy(dst Writer, src Reader) (written int64, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Copy",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", writerType),
				types.NewVar(token.NoPos, pkg, "src", readerType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "written", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// type Closer interface { Close() error }
	closerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	closerIface.Complete()
	closerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Closer", nil),
		closerIface, nil)
	scope.Insert(closerType.Obj())

	// type ReadCloser interface
	rcIface := types.NewInterfaceType(nil, []types.Type{readerIface, closerIface})
	rcIface.Complete()
	readCloserType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReadCloser", nil),
		rcIface, nil)
	scope.Insert(readCloserType.Obj())

	// func NopCloser(r Reader) ReadCloser
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NopCloser",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", readCloserType)),
			false)))

	// type WriteCloser interface
	wcIface := types.NewInterfaceType(nil, []types.Type{writerIface, closerIface})
	wcIface.Complete()
	writeCloserType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WriteCloser", nil),
		wcIface, nil)
	scope.Insert(writeCloserType.Obj())

	// type ReadWriter interface
	rwIface := types.NewInterfaceType(nil, []types.Type{readerIface, writerIface})
	rwIface.Complete()
	readWriterType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReadWriter", nil),
		rwIface, nil)
	scope.Insert(readWriterType.Obj())

	// type ReadWriteCloser interface
	rwcIface := types.NewInterfaceType(nil, []types.Type{readerIface, writerIface, closerIface})
	rwcIface.Complete()
	readWriteCloserType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReadWriteCloser", nil),
		rwcIface, nil)
	scope.Insert(readWriteCloserType.Obj())

	// type Seeker interface { Seek(offset int64, whence int) (int64, error) }
	seekerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Seek",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	seekerIface.Complete()
	seekerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Seeker", nil),
		seekerIface, nil)
	scope.Insert(seekerType.Obj())

	// type ReadSeeker interface
	rsIface := types.NewInterfaceType(nil, []types.Type{readerIface, seekerIface})
	rsIface.Complete()
	readSeekerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReadSeeker", nil),
		rsIface, nil)
	scope.Insert(readSeekerType.Obj())

	// type WriteSeeker interface
	wsIface := types.NewInterfaceType(nil, []types.Type{writerIface, seekerIface})
	wsIface.Complete()
	writeSeekerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WriteSeeker", nil),
		wsIface, nil)
	scope.Insert(writeSeekerType.Obj())

	// type ReadSeekCloser interface { Reader; Seeker; Closer }
	rscIface := types.NewInterfaceType(nil, []types.Type{readerIface, seekerIface, closerIface})
	rscIface.Complete()
	readSeekCloserType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReadSeekCloser", nil),
		rscIface, nil)
	scope.Insert(readSeekCloserType.Obj())

	// type ReaderAt interface
	readerAtIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte])),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerAtIface.Complete()
	readerAtType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReaderAt", nil),
		readerAtIface, nil)
	scope.Insert(readerAtType.Obj())

	// type WriterAt interface
	writerAtIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "WriteAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte])),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	writerAtIface.Complete()
	writerAtType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WriterAt", nil),
		writerAtIface, nil)
	scope.Insert(writerAtType.Obj())

	// type ByteReader interface { ReadByte() (byte, error) }
	byteReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ReadByte",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Byte]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	byteReaderIface.Complete()
	byteReaderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ByteReader", nil),
		byteReaderIface, nil)
	scope.Insert(byteReaderType.Obj())

	// type ByteWriter interface { WriteByte(c byte) error }
	byteWriterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "WriteByte",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", types.Typ[types.Byte])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	byteWriterIface.Complete()
	byteWriterType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ByteWriter", nil),
		byteWriterIface, nil)
	scope.Insert(byteWriterType.Obj())

	// type StringWriter interface { WriteString(s string) (n int, err error) }
	stringWriterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "WriteString",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	stringWriterIface.Complete()
	stringWriterType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "StringWriter", nil),
		stringWriterIface, nil)
	scope.Insert(stringWriterType.Obj())

	// Seek whence constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "SeekStart", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SeekCurrent", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SeekEnd", types.Typ[types.Int], constant.MakeInt64(2)))

	// var ErrUnexpectedEOF error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrUnexpectedEOF", errType))
	// var ErrClosedPipe error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrClosedPipe", errType))
	// var ErrShortWrite error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrShortWrite", errType))
	// var ErrShortBuffer error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrShortBuffer", errType))
	// var ErrNoProgress error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNoProgress", errType))

	// func Pipe() (*PipeReader, *PipeWriter)
	pipeReaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "PipeReader", nil), types.NewStruct(nil, nil), nil)
	pipeWriterType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "PipeWriter", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(pipeReaderType.Obj())
	scope.Insert(pipeWriterType.Obj())
	pipeReaderPtr := types.NewPointer(pipeReaderType)
	pipeWriterPtr := types.NewPointer(pipeWriterType)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pipe",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", pipeReaderPtr),
				types.NewVar(token.NoPos, pkg, "", pipeWriterPtr)),
			false)))

	// PipeReader methods
	prRecv := types.NewVar(token.NoPos, nil, "r", pipeReaderPtr)
	pipeReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(prRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	pipeReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(prRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	pipeReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "CloseWithError",
		types.NewSignatureType(prRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// PipeWriter methods
	pwRecv := types.NewVar(token.NoPos, nil, "w", pipeWriterPtr)
	pipeWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(pwRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	pipeWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(pwRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	pipeWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "CloseWithError",
		types.NewSignatureType(pwRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func LimitReader(r Reader, n int64) Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LimitReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", readerType),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", readerType)),
			false)))

	// func TeeReader(r Reader, w Writer) Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TeeReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", readerType),
				types.NewVar(token.NoPos, pkg, "w", writerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", readerType)),
			false)))

	// func MultiReader(readers ...Reader) Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MultiReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "readers", readerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", readerType)),
			true)))

	// func MultiWriter(writers ...Writer) Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MultiWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "writers", writerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", writerType)),
			true)))

	// func CopyN(dst Writer, src Reader, n int64) (written int64, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CopyN",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", writerType),
				types.NewVar(token.NoPos, pkg, "src", readerType),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int64])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "written", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func CopyBuffer(dst Writer, src Reader, buf []byte) (written int64, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CopyBuffer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", writerType),
				types.NewVar(token.NoPos, pkg, "src", readerType),
				types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "written", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func ReadFull(r Reader, buf []byte) (n int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadFull",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", readerType),
				types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func ReadAtLeast(r Reader, buf []byte, min int) (n int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadAtLeast",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", readerType),
				types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "min", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// type LimitedReader struct { R Reader; N int64 }
	limitedReaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "R", readerType, false),
		types.NewField(token.NoPos, pkg, "N", types.Typ[types.Int64], false),
	}, nil)
	limitedReaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "LimitedReader", nil), limitedReaderStruct, nil)
	scope.Insert(limitedReaderType.Obj())
	lrPtr := types.NewPointer(limitedReaderType)
	limitedReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", lrPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))

	// type SectionReader struct {}
	sectionReaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SectionReader", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(sectionReaderType.Obj())
	srPtr := types.NewPointer(sectionReaderType)
	sectionReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "s", srPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	sectionReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seek",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "s", srPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	sectionReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadAt",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "s", srPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	sectionReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "s", srPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))

	// func NewSectionReader(r ReaderAt, off int64, n int64) *SectionReader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewSectionReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", readerAtType),
				types.NewVar(token.NoPos, pkg, "off", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", srPtr)),
			false)))

	_ = readCloserType
	_ = writeCloserType
	_ = readWriterType
	_ = readWriteCloserType
	_ = readSeekerType
	_ = writeSeekerType
	_ = writerAtType
	_ = byteReaderType
	_ = byteWriterType
	_ = stringWriterType

	// type RuneReader interface { ReadRune() (r rune, size int, err error) }
	runeReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ReadRune",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Rune]),
					types.NewVar(token.NoPos, nil, "size", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	runeReaderIface.Complete()
	runeReaderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RuneReader", nil),
		runeReaderIface, nil)
	scope.Insert(runeReaderType.Obj())

	// type RuneScanner interface { ReadRune + UnreadRune }
	runeScannerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ReadRune",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Rune]),
					types.NewVar(token.NoPos, nil, "size", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "UnreadRune",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	runeScannerIface.Complete()
	runeScannerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RuneScanner", nil),
		runeScannerIface, nil)
	scope.Insert(runeScannerType.Obj())

	// type ByteScanner interface { ReadByte + UnreadByte }
	byteScannerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ReadByte",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Byte]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "UnreadByte",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	byteScannerIface.Complete()
	byteScannerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ByteScanner", nil),
		byteScannerIface, nil)
	scope.Insert(byteScannerType.Obj())

	// type WriterTo interface { WriteTo(w Writer) (n int64, err error) }
	writerToIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "WriteTo",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "w", writerType)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	writerToIface.Complete()
	writerToType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WriterTo", nil),
		writerToIface, nil)
	scope.Insert(writerToType.Obj())

	// type ReaderFrom interface { ReadFrom(r Reader) (n int64, err error) }
	readerFromIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ReadFrom",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "r", readerType)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerFromIface.Complete()
	readerFromType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReaderFrom", nil),
		readerFromIface, nil)
	scope.Insert(readerFromType.Obj())

	// type ReadWriteSeeker interface
	rwsIface := types.NewInterfaceType(nil, []types.Type{readerIface, writerIface, seekerIface})
	rwsIface.Complete()
	readWriteSeekerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReadWriteSeeker", nil),
		rwsIface, nil)
	scope.Insert(readWriteSeekerType.Obj())

	_ = runeReaderType
	_ = runeScannerType
	_ = byteScannerType
	_ = writerToType
	_ = readerFromType
	_ = readWriteSeekerType

	// type OffsetWriter struct — opaque (Go 1.20+)
	offsetWriterStruct := types.NewStruct(nil, nil)
	offsetWriterType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "OffsetWriter", nil),
		offsetWriterStruct, nil)
	scope.Insert(offsetWriterType.Obj())
	offsetWriterPtr := types.NewPointer(offsetWriterType)
	offsetWriterRecv := types.NewVar(token.NoPos, pkg, "", offsetWriterPtr)

	// func NewOffsetWriter(w WriterAt, off int64) *OffsetWriter
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewOffsetWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", writerAtIface),
				types.NewVar(token.NoPos, pkg, "off", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", offsetWriterPtr)),
			false)))

	// OffsetWriter methods: Write, WriteAt, Seek
	bSlice := types.NewSlice(types.Typ[types.Byte])
	offsetWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(offsetWriterRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", bSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	offsetWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteAt",
		types.NewSignatureType(offsetWriterRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", bSlice),
				types.NewVar(token.NoPos, pkg, "off", types.Typ[types.Int64])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	offsetWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seek",
		types.NewSignatureType(offsetWriterRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "offset", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "whence", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildLogPackage() *types.Package {
	pkg := types.NewPackage("log", "log")
	scope := pkg.Scope()

	// func Println(v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Println",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v",
				types.NewSlice(types.NewInterfaceType(nil, nil)))),
			nil, true)))

	// func Printf(format string, v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Printf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "v",
					types.NewSlice(types.NewInterfaceType(nil, nil)))),
			nil, true)))

	// func Fatal(v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fatal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v",
				types.NewSlice(types.NewInterfaceType(nil, nil)))),
			nil, true)))

	// func Fatalf(format string, v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fatalf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "v",
					types.NewSlice(types.NewInterfaceType(nil, nil)))),
			nil, true)))

	anySlice := types.NewSlice(types.NewInterfaceType(nil, nil))
	errType := types.Universe.Lookup("error").Type()

	// func Print(v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Print",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))

	// func Fatalln(v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fatalln",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))

	// func Panic(v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Panic",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))

	// func Panicln(v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Panicln",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))

	// func Panicf(format string, v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Panicf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))

	// func SetFlags(flag int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetFlags",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "flag", types.Typ[types.Int])),
			nil, false)))

	// func Flags() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Flags",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// func SetPrefix(prefix string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetPrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "prefix", types.Typ[types.String])),
			nil, false)))

	// func Prefix() string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Prefix",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// func SetOutput(w io.Writer)
	logByteSlice := types.NewSlice(types.Typ[types.Byte])
	writerType := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", logByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	writerType.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetOutput",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", writerType)),
			nil, false)))

	// func Writer() io.Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Writer",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", writerType)),
			false)))

	// func Output(calldepth int, s string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Output",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "calldepth", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Logger type
	loggerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Logger", nil), types.NewStruct(nil, nil), nil)
	loggerPtr := types.NewPointer(loggerType)
	scope.Insert(loggerType.Obj())

	// func New(out io.Writer, prefix string, flag int) *Logger
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "out", writerType),
				types.NewVar(token.NoPos, nil, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "flag", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", loggerPtr)),
			false)))

	// func Default() *Logger
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Default",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", loggerPtr)),
			false)))

	logRecv := types.NewVar(token.NoPos, pkg, "l", loggerPtr)

	// (*Logger).Println, Printf, Print, Fatal, Fatalf, Fatalln, Panic, Panicln, Panicf
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Println",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Printf",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Print",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fatal",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fatalf",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fatalln",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Panic",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Panicf",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Panicln",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v", anySlice)),
			nil, true)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Output",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "calldepth", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetPrefix",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "prefix", types.Typ[types.String])),
			nil, false)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Prefix",
		types.NewSignatureType(logRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetFlags",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "flag", types.Typ[types.Int])),
			nil, false)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flags",
		types.NewSignatureType(logRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetOutput",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", writerType)),
			nil, false)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Writer",
		types.NewSignatureType(logRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", writerType)),
			false)))

	// Log flag constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "Ldate", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Ltime", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Lmicroseconds", types.Typ[types.Int], constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Llongfile", types.Typ[types.Int], constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Lshortfile", types.Typ[types.Int], constant.MakeInt64(16)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LUTC", types.Typ[types.Int], constant.MakeInt64(32)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Lmsgprefix", types.Typ[types.Int], constant.MakeInt64(64)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LstdFlags", types.Typ[types.Int], constant.MakeInt64(3)))

	pkg.MarkComplete()
	return pkg
}

// buildOsPackage creates the type-checked os package stub.
func buildOsPackage() *types.Package {
	pkg := types.NewPackage("os", "os")
	scope := pkg.Scope()

	// func Exit(code int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Exit",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "code", types.Typ[types.Int])),
			nil,
			false)))

	// func Getenv(key string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getenv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Getwd() (string, error)
	errType := types.Universe.Lookup("error").Type()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getwd",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// var Args []string
	scope.Insert(types.NewVar(token.NoPos, pkg, "Args", types.NewSlice(types.Typ[types.String])))

	// var Stdin, Stdout, Stderr *File (simplified as int for now)
	fileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "fd", types.Typ[types.Int], false),
	}, nil)
	fileType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "File", nil),
		fileStruct, nil)
	scope.Insert(fileType.Obj())
	filePtr := types.NewPointer(fileType)
	scope.Insert(types.NewVar(token.NoPos, pkg, "Stdin", filePtr))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Stdout", filePtr))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Stderr", filePtr))

	// func Mkdir(name string, perm uint32) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Mkdir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "perm", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Remove(name string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Remove",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ReadFile(name string) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func WriteFile(name string, data []byte, perm uint32) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "perm", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Chdir(dir string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chdir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Rename(oldpath, newpath string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Rename",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "oldpath", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "newpath", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func MkdirAll(path string, perm uint32) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MkdirAll",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "perm", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func RemoveAll(path string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RemoveAll",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func TempDir() string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TempDir",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func UserHomeDir() (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UserHomeDir",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Environ() []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Environ",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// func Setenv(key, value string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Setenv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func IsNotExist(err error) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsNotExist",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IsExist(err error) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsExist",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IsPermission(err error) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsPermission",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// type FileMode uint32
	fileModeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FileMode", nil),
		types.Typ[types.Uint32], nil)
	scope.Insert(fileModeType.Obj())

	// FileMode constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeDir", fileModeType, constant.MakeInt64(1<<31)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModePerm", fileModeType, constant.MakeInt64(0777)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeAppend", fileModeType, constant.MakeInt64(1<<30)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeExclusive", fileModeType, constant.MakeInt64(1<<29)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeTemporary", fileModeType, constant.MakeInt64(1<<28)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeSymlink", fileModeType, constant.MakeInt64(1<<27)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeDevice", fileModeType, constant.MakeInt64(1<<26)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeNamedPipe", fileModeType, constant.MakeInt64(1<<25)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeSocket", fileModeType, constant.MakeInt64(1<<24)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeSetuid", fileModeType, constant.MakeInt64(1<<23)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeSetgid", fileModeType, constant.MakeInt64(1<<22)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeCharDevice", fileModeType, constant.MakeInt64(1<<21)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeSticky", fileModeType, constant.MakeInt64(1<<20)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeIrregular", fileModeType, constant.MakeInt64(1<<19)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeType", fileModeType, constant.MakeInt64(1<<31|1<<30|1<<29|1<<28|1<<27|1<<26|1<<25|1<<24|1<<19)))

	// FileMode methods
	fileModeType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsDir",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", fileModeType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	fileModeType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsRegular",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", fileModeType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	fileModeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Perm",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", fileModeType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fileModeType)),
			false)))
	fileModeType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", fileModeType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	fileModeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Type",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", fileModeType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fileModeType)),
			false)))

	// Open flags
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_RDONLY", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_WRONLY", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_RDWR", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_APPEND", types.Typ[types.Int], constant.MakeInt64(1024)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_CREATE", types.Typ[types.Int], constant.MakeInt64(64)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_EXCL", types.Typ[types.Int], constant.MakeInt64(128)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_SYNC", types.Typ[types.Int], constant.MakeInt64(4096)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_TRUNC", types.Typ[types.Int], constant.MakeInt64(512)))

	// Seek constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "SEEK_SET", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SEEK_CUR", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SEEK_END", types.Typ[types.Int], constant.MakeInt64(2)))

	// type FileInfo interface (fs.FileInfo compatible)
	anyTypeOs := types.NewInterfaceType(nil, nil)
	anyTypeOs.Complete()
	fileInfoIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, pkg, "Mode",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", fileModeType)), false)),
		types.NewFunc(token.NoPos, pkg, "ModTime",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, pkg, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Sys",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyTypeOs)), false)),
	}, nil)
	fileInfoIface.Complete()
	fileInfoType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FileInfo", nil),
		fileInfoIface, nil)
	scope.Insert(fileInfoType.Obj())

	// type DirEntry interface
	dirEntryIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Type",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", fileModeType)), false)),
		types.NewFunc(token.NoPos, pkg, "Info",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fileInfoIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	dirEntryIface.Complete()
	dirEntryType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "DirEntry", nil),
		dirEntryIface, nil)
	scope.Insert(dirEntryType.Obj())

	// type PathError struct
	pathErrorType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "PathError", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Op", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Err", errType, false),
		}, nil), nil)
	scope.Insert(pathErrorType.Obj())
	pathErrorPtr := types.NewPointer(pathErrorType)

	// PathError.Error() string
	pathErrorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "e", pathErrorPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// PathError.Unwrap() error
	pathErrorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "e", pathErrorPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// PathError.Timeout() bool
	pathErrorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "e", pathErrorPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// type LinkError struct
	linkErrorType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "LinkError", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Op", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Old", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "New", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Err", errType, false),
		}, nil), nil)
	scope.Insert(linkErrorType.Obj())
	linkErrorPtr := types.NewPointer(linkErrorType)

	// LinkError.Error() string
	linkErrorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "e", linkErrorPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// LinkError.Unwrap() error
	linkErrorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "e", linkErrorPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type Signal interface { String, Signal }
	signalIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Signal",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
	}, nil)
	signalIface.Complete()
	signalType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Signal", nil),
		signalIface, nil)
	scope.Insert(signalType.Obj())

	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// func Open(name string) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Create(name string) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Create",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func OpenFile(name string, flag int, perm FileMode) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OpenFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "flag", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "perm", fileModeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Stat(name string) (FileInfo, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Stat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", fileInfoType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Lstat(name string) (FileInfo, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lstat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", fileInfoType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ReadDir(name string) ([]DirEntry, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(dirEntryType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Hostname() (name string, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Hostname",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func LookupEnv(key string) (string, bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupEnv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Executable() (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Executable",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func CreateTemp(dir, pattern string) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CreateTemp",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func MkdirTemp(dir, pattern string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MkdirTemp",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Unsetenv(key string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unsetenv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Getpid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getpid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Getuid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getuid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Getgid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getgid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Getppid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getppid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Getegid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getegid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Geteuid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Geteuid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Getgroups() ([]int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getgroups",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Int])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Clearenv()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Clearenv",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// var ErrNotExist, ErrExist, ErrPermission, ErrClosed error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNotExist", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrExist", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrPermission", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrClosed", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrInvalid", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrDeadlineExceeded", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrProcessDone", errType))

	// const DevNull = "/dev/null"
	scope.Insert(types.NewConst(token.NoPos, pkg, "DevNull", types.Typ[types.String], constant.MakeString("/dev/null")))
	// const PathSeparator = '/'
	scope.Insert(types.NewConst(token.NoPos, pkg, "PathSeparator", types.Typ[types.Rune], constant.MakeInt64('/')))
	// const PathListSeparator = ':'
	scope.Insert(types.NewConst(token.NoPos, pkg, "PathListSeparator", types.Typ[types.Rune], constant.MakeInt64(':')))

	// File methods
	fileRecv := types.NewVar(token.NoPos, pkg, "f", filePtr)

	// (*File).Read(b []byte) (n int, err error)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))

	// (*File).Write(b []byte) (n int, err error)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))

	// (*File).WriteString(s string) (n int, err error)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteString",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))

	// (*File).Close() error
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).Name() string
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// (*File).Stat() (FileInfo, error)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stat",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", fileInfoType),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).Seek(offset int64, whence int) (int64, error)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seek",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).Sync() error
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sync",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).Chmod(mode FileMode) error
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Chmod",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "mode", fileModeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).ReadDir(n int) ([]DirEntry, error)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadDir",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(dirEntryType)),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).Fd() uintptr
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fd",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uintptr])),
			false)))

	// (*File).Truncate(size int64) error
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Truncate",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "size", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).WriteAt(b []byte, off int64) (n int, err error)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteAt",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "b", byteSlice),
				types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))

	// (*File).ReadAt(b []byte, off int64) (n int, err error)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadAt",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "b", byteSlice),
				types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))

	// --- Additional os functions ---

	// func UserCacheDir() (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UserCacheDir",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func UserConfigDir() (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UserConfigDir",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Chmod(name string, mode FileMode) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chmod",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", fileModeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Chown(name string, uid, gid int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chown",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "uid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "gid", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Link(oldname, newname string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Link",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "oldname", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "newname", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Symlink(oldname, newname string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Symlink",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "oldname", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "newname", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Readlink(name string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Readlink",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func SameFile(fi1, fi2 FileInfo) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SameFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fi1", fileInfoType),
				types.NewVar(token.NoPos, pkg, "fi2", fileInfoType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Pipe() (r *File, w *File, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pipe",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", filePtr),
				types.NewVar(token.NoPos, pkg, "w", filePtr),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func Truncate(name string, size int64) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Truncate",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "size", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// (*File).Fd() uintptr
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fd",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uintptr])),
			false)))

	// (*File).Readdir(n int) ([]FileInfo, error)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Readdir",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(fileInfoType)),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).Readdirnames(n int) ([]string, error)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Readdirnames",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).SetDeadline(t time.Time) error — time.Time as int64
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetDeadline",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func Expand(s string, mapping func(string) string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Expand",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mapping",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
						false))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ExpandEnv(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ExpandEnv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// fs.File stand-in interface { Read, Close, Stat }
	byteSliceOS := types.NewSlice(types.Typ[types.Byte])
	fsFileIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceOS)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Stat",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", anyTypeOs),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	fsFileIface.Complete()

	// fs.FS stand-in for DirFS return
	fsIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fsFileIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	fsIface.Complete()

	// func DirFS(dir string) fs.FS
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DirFS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", fsIface)),
			false)))

	// func NewFile(fd uintptr, name string) *File
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Uintptr]),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", filePtr)),
			false)))

	// func IsTimeout(err error) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsTimeout",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// var ErrNoDeadline error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNoDeadline", errType))

	// type Root struct (Go 1.24+)
	rootStruct := types.NewStruct(nil, nil)
	rootType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Root", nil),
		rootStruct, nil)
	scope.Insert(rootType.Obj())
	rootPtr := types.NewPointer(rootType)
	rootRecv := types.NewVar(token.NoPos, nil, "r", rootPtr)

	// func OpenRoot(name string) (*Root, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OpenRoot",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", rootPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// (*Root).Open(name string) (*File, error)
	rootType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(rootRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", filePtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Root).OpenFile(name string, flag int, perm FileMode) (*File, error)
	rootType.AddMethod(types.NewFunc(token.NoPos, pkg, "OpenFile",
		types.NewSignatureType(rootRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "flag", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "perm", fileModeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", filePtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Root).Create(name string) (*File, error)
	rootType.AddMethod(types.NewFunc(token.NoPos, pkg, "Create",
		types.NewSignatureType(rootRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", filePtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Root).Mkdir(name string, perm FileMode) error
	rootType.AddMethod(types.NewFunc(token.NoPos, pkg, "Mkdir",
		types.NewSignatureType(rootRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "perm", fileModeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Root).Remove(name string) error
	rootType.AddMethod(types.NewFunc(token.NoPos, pkg, "Remove",
		types.NewSignatureType(rootRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Root).Stat(name string) (FileInfo, error)
	rootType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stat",
		types.NewSignatureType(rootRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", fileInfoType),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Root).Lstat(name string) (FileInfo, error)
	rootType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lstat",
		types.NewSignatureType(rootRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", fileInfoType),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Root).Close() error
	rootType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(rootRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Root).Name() string
	rootType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(rootRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// type SyscallError struct { Syscall string; Err error }
	syscallErrorStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Syscall", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	syscallErrorType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SyscallError", nil),
		syscallErrorStruct, nil)
	scope.Insert(syscallErrorType.Obj())
	syscallErrorPtr := types.NewPointer(syscallErrorType)
	syscallErrorRecv := types.NewVar(token.NoPos, pkg, "", syscallErrorPtr)
	syscallErrorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(syscallErrorRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))
	syscallErrorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(syscallErrorRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	syscallErrorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(syscallErrorRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewSyscallError(syscall string, err error) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewSyscallError",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "syscall", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type ProcessState struct — opaque
	processStateStruct := types.NewStruct(nil, nil)
	processStateType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ProcessState", nil),
		processStateStruct, nil)
	scope.Insert(processStateType.Obj())
	processStatePtr := types.NewPointer(processStateType)
	processStateRecv := types.NewVar(token.NoPos, pkg, "", processStatePtr)

	// time.Duration stand-in for process time methods
	durationType := types.Typ[types.Int64]

	processStateType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExitCode",
		types.NewSignatureType(processStateRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	processStateType.AddMethod(types.NewFunc(token.NoPos, pkg, "Exited",
		types.NewSignatureType(processStateRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	processStateType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pid",
		types.NewSignatureType(processStateRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	processStateType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(processStateRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))
	processStateType.AddMethod(types.NewFunc(token.NoPos, pkg, "Success",
		types.NewSignatureType(processStateRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	processStateType.AddMethod(types.NewFunc(token.NoPos, pkg, "SystemTime",
		types.NewSignatureType(processStateRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", durationType)),
			false)))
	processStateType.AddMethod(types.NewFunc(token.NoPos, pkg, "UserTime",
		types.NewSignatureType(processStateRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", durationType)),
			false)))

	// type Process struct — opaque
	processStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pid", types.Typ[types.Int], false),
	}, nil)
	processType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Process", nil),
		processStruct, nil)
	scope.Insert(processType.Obj())
	processPtr := types.NewPointer(processType)
	processRecv := types.NewVar(token.NoPos, pkg, "", processPtr)

	processType.AddMethod(types.NewFunc(token.NoPos, pkg, "Kill",
		types.NewSignatureType(processRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	processType.AddMethod(types.NewFunc(token.NoPos, pkg, "Release",
		types.NewSignatureType(processRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	processType.AddMethod(types.NewFunc(token.NoPos, pkg, "Signal",
		types.NewSignatureType(processRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "sig", signalIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	processType.AddMethod(types.NewFunc(token.NoPos, pkg, "Wait",
		types.NewSignatureType(processRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", processStatePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func FindProcess(pid int) (*Process, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FindProcess",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "pid", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", processPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type ProcAttr struct { Dir string; Env []string; Files []*File }
	procAttrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dir", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Env", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Files", types.NewSlice(filePtr), false),
	}, nil)
	procAttrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ProcAttr", nil),
		procAttrStruct, nil)
	scope.Insert(procAttrType.Obj())

	// func StartProcess(name string, argv []string, attr *ProcAttr) (*Process, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StartProcess",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "argv", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "attr", types.NewPointer(procAttrType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", processPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// ---- Additional missing os functions ----

	// func Chtimes(name string, atime time.Time, mtime time.Time) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chtimes",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "atime", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "mtime", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Lchown(name string, uid, gid int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lchown",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "uid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "gid", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Getpagesize() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getpagesize",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// var Interrupt, Kill Signal
	scope.Insert(types.NewVar(token.NoPos, pkg, "Interrupt", signalIface))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Kill", signalIface))

	// (*File).Chown(uid, gid int) error
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Chown",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "uid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "gid", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).Chdir() error
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Chdir",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).SetReadDeadline(t time.Time) error
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetReadDeadline",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).SetWriteDeadline(t time.Time) error
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetWriteDeadline",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*File).ReadFrom(r io.Reader) (n int64, err error)
	ioReaderOS := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
	}, nil)
	ioReaderOS.Complete()
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadFrom",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", ioReaderOS)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))

	// (*File).SyscallConn() (syscall.RawConn, error)
	// syscall.RawConn is an interface with Control/Read/Write methods
	rawConnIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Control",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "fd", types.Typ[types.Uintptr])),
						nil, false))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "fd", types.Typ[types.Uintptr])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
						false))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "fd", types.Typ[types.Uintptr])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
						false))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	rawConnIface.Complete()
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "SyscallConn",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", rawConnIface),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// ProcessState.Sys() interface{}
	processStateType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sys",
		types.NewSignatureType(processStateRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
			false)))

	// ProcessState.SysUsage() interface{}
	processStateType.AddMethod(types.NewFunc(token.NoPos, pkg, "SysUsage",
		types.NewSignatureType(processStateRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
			false)))

	// func Abs(path string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Abs",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func CopyFS(dir string, fsys fs.FS) error — Go 1.23+
	// fs.FS stand-in
	fsIfaceOS := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil)),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	fsIfaceOS.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CopyFS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "fsys", fsIfaceOS)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildSortPackage() *types.Package {
	pkg := types.NewPackage("sort", "sort")
	scope := pkg.Scope()

	// type Interface interface { Len() int; Less(i, j int) bool; Swap(i, j int) }
	sortIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Len",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "Less",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Swap",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
				nil, false)),
	}, nil)
	sortIface.Complete()
	ifaceType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Interface", nil),
		sortIface, nil)
	scope.Insert(ifaceType.Obj())

	// func Ints(x []int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Ints",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x",
				types.NewSlice(types.Typ[types.Int]))),
			nil, false)))

	// func Strings(x []string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Strings",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x",
				types.NewSlice(types.Typ[types.String]))),
			nil, false)))

	// func Slice(x any, less func(i, j int) bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Slice",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, nil, "less",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(
							types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
							types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
						false))),
			nil, false)))

	// func IntsAreSorted(x []int) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IntsAreSorted",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x",
				types.NewSlice(types.Typ[types.Int]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func Float64s(x []float64)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float64s",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x",
				types.NewSlice(types.Typ[types.Float64]))),
			nil, false)))

	// func Search(n int, f func(int) bool) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Search",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
						false))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// func SearchInts(a []int, x int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SearchInts",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "a", types.NewSlice(types.Typ[types.Int])),
				types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// func SearchStrings(a []string, x string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SearchStrings",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "a", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "x", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// func SliceIsSorted(x any, less func(i, j int) bool) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SliceIsSorted",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, nil, "less",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(
							types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
							types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
						false))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func Reverse(data Interface) Interface
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Reverse",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", ifaceType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ifaceType)),
			false)))

	// func SliceStable(x any, less func(i, j int) bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SliceStable",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, nil, "less",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(
							types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
							types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
						false))),
			nil, false)))

	// func Sort(data Interface)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sort",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", ifaceType)),
			nil, false)))

	// func Stable(data Interface)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Stable",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", ifaceType)),
			nil, false)))

	// func Find(n int, cmp func(int) int) (i int, found bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Find",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "cmp",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
						false))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "found", types.Typ[types.Bool])),
			false)))

	// func Float64sAreSorted(x []float64) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float64sAreSorted",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x",
				types.NewSlice(types.Typ[types.Float64]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func StringsAreSorted(x []string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StringsAreSorted",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x",
				types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func SearchFloat64s(a []float64, x float64) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SearchFloat64s",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "a", types.NewSlice(types.Typ[types.Float64])),
				types.NewVar(token.NoPos, nil, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// func IsSorted(data Interface) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsSorted",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", ifaceType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// type IntSlice []int
	intSliceType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "IntSlice", nil),
		types.NewSlice(types.Typ[types.Int]), nil)
	scope.Insert(intSliceType.Obj())
	intSliceRecv := types.NewVar(token.NoPos, nil, "x", intSliceType)
	intSliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(intSliceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	intSliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Less",
		types.NewSignatureType(intSliceRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	intSliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(intSliceRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
			nil, false)))
	intSliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sort",
		types.NewSignatureType(intSliceRecv, nil, nil, nil, nil, false)))
	intSliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Search",
		types.NewSignatureType(intSliceRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// type Float64Slice []float64
	float64SliceType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Float64Slice", nil),
		types.NewSlice(types.Typ[types.Float64]), nil)
	scope.Insert(float64SliceType.Obj())
	f64SliceRecv := types.NewVar(token.NoPos, nil, "x", float64SliceType)
	float64SliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(f64SliceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	float64SliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Less",
		types.NewSignatureType(f64SliceRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	float64SliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(f64SliceRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
			nil, false)))
	float64SliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sort",
		types.NewSignatureType(f64SliceRecv, nil, nil, nil, nil, false)))
	float64SliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Search",
		types.NewSignatureType(f64SliceRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// type StringSlice []string
	stringSliceType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "StringSlice", nil),
		types.NewSlice(types.Typ[types.String]), nil)
	scope.Insert(stringSliceType.Obj())
	strSliceRecv := types.NewVar(token.NoPos, nil, "x", stringSliceType)
	stringSliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(strSliceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	stringSliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Less",
		types.NewSignatureType(strSliceRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	stringSliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(strSliceRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
			nil, false)))
	stringSliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sort",
		types.NewSignatureType(strSliceRecv, nil, nil, nil, nil, false)))
	stringSliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Search",
		types.NewSignatureType(strSliceRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	pkg.MarkComplete()
	return pkg
}

// buildStrconvPackage creates the type-checked strconv package stub
// with signatures for Itoa, Atoi, FormatInt, FormatBool, ParseBool, etc.
func buildStrconvPackage() *types.Package {
	pkg := types.NewPackage("strconv", "strconv")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// func Itoa(i int) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Itoa",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Atoi(s string) (int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Atoi",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func FormatInt(i int64, base int) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FormatInt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "base", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func FormatBool(b bool) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FormatBool",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ParseBool(str string) (bool, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseBool",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "str", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func FormatFloat(f float64, fmt byte, prec, bitSize int) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FormatFloat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "f", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "fmt", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "prec", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "bitSize", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ParseInt(s string, base int, bitSize int) (int64, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseInt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "base", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "bitSize", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseUint(s string, base int, bitSize int) (uint64, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseUint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "base", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "bitSize", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func FormatUint(i uint64, base int) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FormatUint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "base", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Quote(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Quote",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Unquote(s string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unquote",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func AppendInt(dst []byte, i int64, base int) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendInt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "base", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func ParseFloat(s string, bitSize int) (float64, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseFloat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "bitSize", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	byteSlice := types.NewSlice(types.Typ[types.Byte])
	strToStr := func(name string) {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
				false)))
	}
	strToStr("QuoteToASCII")
	strToStr("QuoteToGraphic")

	// func QuoteRune(r rune) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "QuoteRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func QuoteRuneToASCII(r rune) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "QuoteRuneToASCII",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func QuoteRuneToGraphic(r rune) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "QuoteRuneToGraphic",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func CanBackquote(s string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CanBackquote",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IsPrint(r rune) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsPrint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IsGraphic(r rune) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsGraphic",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func UnquoteChar(s string, quote byte) (value rune, multibyte bool, tail string, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UnquoteChar",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "quote", types.Typ[types.Byte])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, pkg, "multibyte", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, pkg, "tail", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Append functions
	// func AppendBool(dst []byte, b bool) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendBool",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", byteSlice),
				types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func AppendFloat(dst []byte, f float64, fmt byte, prec, bitSize int) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendFloat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", byteSlice),
				types.NewVar(token.NoPos, pkg, "f", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "fmt", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "prec", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "bitSize", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func AppendQuote(dst []byte, s string) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendQuote",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", byteSlice),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func AppendQuoteRune(dst []byte, r rune) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendQuoteRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", byteSlice),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func AppendQuoteToASCII(dst []byte, s string) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendQuoteToASCII",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", byteSlice),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func AppendQuoteRuneToASCII(dst []byte, r rune) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendQuoteRuneToASCII",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", byteSlice),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func AppendQuoteToGraphic(dst []byte, s string) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendQuoteToGraphic",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", byteSlice),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func AppendQuoteRuneToGraphic(dst []byte, r rune) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendQuoteRuneToGraphic",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", byteSlice),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func AppendUint(dst []byte, i uint64, base int) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendUint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", byteSlice),
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "base", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func FormatComplex(c complex128, fmt byte, prec, bitSize int) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FormatComplex",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", types.Typ[types.Complex128]),
				types.NewVar(token.NoPos, pkg, "fmt", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "prec", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "bitSize", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ParseComplex(s string, bitSize int) (complex128, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseComplex",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "bitSize", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Complex128]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Error types
	numErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Func", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Num", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	numErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NumError", nil),
		numErrStruct, nil)
	scope.Insert(numErrType.Obj())
	numErrPtr := types.NewPointer(numErrType)
	numErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "e", numErrPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	numErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "e", numErrPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Sentinel errors
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrRange", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrSyntax", errType))

	// Constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "IntSize", types.Typ[types.UntypedInt], constant.MakeInt64(64)))

	// func QuotedPrefix(s string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "QuotedPrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildStringsPackage creates the type-checked strings package stub.
func buildStringsPackage() *types.Package {
	pkg := types.NewPackage("strings", "strings")
	scope := pkg.Scope()

	// func Contains(s, substr string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Contains",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "substr", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func HasPrefix(s, prefix string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HasPrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func HasSuffix(s, suffix string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HasSuffix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "suffix", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Index(s, substr string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "substr", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func TrimSpace(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimSpace",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Split(s, sep string) []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Split",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "sep", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// func Join(elems []string, sep string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Join",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "elems", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "sep", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Replace(s, old, new string, n int) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Replace",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "old", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "new", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ToUpper(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToUpper",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ToLower(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToLower",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Repeat(s string, count int) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Repeat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "count", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Count(s, substr string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Count",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "substr", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func EqualFold(s, t string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EqualFold",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "t", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Fields(s string) []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fields",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// func Trim(s string, cutset string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Trim",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "cutset", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func TrimLeft(s string, cutset string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimLeft",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "cutset", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func TrimRight(s string, cutset string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimRight",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "cutset", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func TrimPrefix(s, prefix string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimPrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func TrimSuffix(s, suffix string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimSuffix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "suffix", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ReplaceAll(s, old, new string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReplaceAll",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "old", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "new", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ContainsRune(s string, r rune) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ContainsRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func ContainsAny(s, chars string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ContainsAny",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "chars", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IndexByte(s string, c byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IndexByte",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "c", types.Typ[types.Byte])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func IndexRune(s string, r rune) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IndexRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func LastIndex(s, substr string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LastIndex",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "substr", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Title(s string) string (deprecated but still used)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Title",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Map(mapping func(rune) rune, s string) string
	mapFuncSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Rune])),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Map",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "mapping", mapFuncSig),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func NewReader(s string) *Reader
	readerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "s", types.Typ[types.String], false),
	}, nil)
	readerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		readerStruct, nil)
	scope.Insert(readerType.Obj())
	readerPtr := types.NewPointer(readerType)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", readerPtr)),
			false)))

	// type Builder struct { ... }
	builderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "buf", types.Typ[types.String], false),
	}, nil)
	builderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Builder", nil),
		builderStruct, nil)
	scope.Insert(builderType.Obj())
	builderPtr := types.NewPointer(builderType)
	builderType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteString",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "b", builderPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
			false)))
	builderType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "b", builderPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	builderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "b", builderPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	builderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "b", builderPtr),
			nil, nil, nil, nil, false)))
	builderType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteByte",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "b", builderPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "c", types.Typ[types.Byte])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
			false)))
	builderType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteRune",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "b", builderPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", types.Typ[types.Rune])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
			false)))

	// func NewReplacer(oldnew ...string) *Replacer
	replacerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "r", types.Typ[types.Int], false),
	}, nil)
	replacerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Replacer", nil),
		replacerStruct, nil)
	scope.Insert(replacerType.Obj())
	replacerPtr := types.NewPointer(replacerType)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReplacer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "oldnew",
				types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", replacerPtr)),
			true)))

	// func Cut(s, sep string) (before, after string, found bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Cut",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "sep", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "before", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "after", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "found", types.Typ[types.Bool])),
			false)))

	// func CutPrefix(s, prefix string) (after string, found bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CutPrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "after", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "found", types.Typ[types.Bool])),
			false)))

	// func CutSuffix(s, suffix string) (before string, found bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CutSuffix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "suffix", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "before", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "found", types.Typ[types.Bool])),
			false)))

	// func Clone(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func SplitN(s, sep string, n int) []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SplitN",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "sep", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// func SplitAfter(s, sep string) []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SplitAfter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "sep", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// func SplitAfterN(s, sep string, n int) []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SplitAfterN",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "sep", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// func ToTitle(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToTitle",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ToValidUTF8(s, replacement string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToValidUTF8",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "replacement", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func IndexAny(s, chars string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IndexAny",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "chars", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func LastIndexByte(s string, c byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LastIndexByte",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "c", types.Typ[types.Byte])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func LastIndexAny(s, chars string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LastIndexAny",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "chars", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func IndexFunc(s string, f func(rune) bool) int
	runePredSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "r", types.Typ[types.Rune])),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IndexFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "f", runePredSig)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func LastIndexFunc(s string, f func(rune) bool) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LastIndexFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "f", runePredSig)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func FieldsFunc(s string, f func(rune) bool) []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FieldsFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "f", runePredSig)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// func ContainsFunc(s string, f func(rune) bool) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ContainsFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "f", runePredSig)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Compare(a, b string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "a", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "b", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func TrimFunc(s string, f func(rune) bool) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "f", runePredSig)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func TrimLeftFunc(s string, f func(rune) bool) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimLeftFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "f", runePredSig)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func TrimRightFunc(s string, f func(rune) bool) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimRightFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "f", runePredSig)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Builder additional methods: Write, Grow, Cap
	builderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "b", builderPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
			false)))
	builderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Grow",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "b", builderPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			nil, false)))
	builderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cap",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "b", builderPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Replacer methods: Replace, WriteString
	replacerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Replace",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", replacerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	// io.Writer interface for WriteString
	strWriterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", types.Universe.Lookup("error").Type())),
				false)),
	}, nil)
	strWriterIface.Complete()
	replacerType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteString",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", replacerPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "w", strWriterIface),
				types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
			false)))

	// Reader methods: Read, ReadByte, ReadRune, UnreadByte, UnreadRune, Len, Size, Reset, Seek, WriteTo, ReadAt
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadByte",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadRune",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnreadByte",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnreadRune",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			nil, false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seek",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
			false)))
	// io.Writer for WriteTo
	errTypeStr := types.Universe.Lookup("error").Type()
	ioWriterStr := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errTypeStr)),
				false)),
	}, nil)
	ioWriterStr.Complete()

	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteTo",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", ioWriterStr)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "", errTypeStr)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadAt",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
			false)))

	// unicode.SpecialCase stand-in ([]CaseRange opaque)
	specialCaseType := types.NewSlice(types.NewStruct(nil, nil))

	// func ToUpperSpecial(c unicode.SpecialCase, s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToUpperSpecial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", specialCaseType),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ToLowerSpecial(c unicode.SpecialCase, s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToLowerSpecial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", specialCaseType),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ToTitleSpecial(c unicode.SpecialCase, s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToTitleSpecial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", specialCaseType),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildSyncPackage() *types.Package {
	pkg := types.NewPackage("sync", "sync")
	scope := pkg.Scope()

	// type Mutex struct{ locked int }
	mutexStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "locked", types.Typ[types.Int], false),
	}, nil)
	mutexType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Mutex", nil),
		mutexStruct, nil)
	scope.Insert(mutexType.Obj())

	mutexPtr := types.NewPointer(mutexType)
	mutexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lock",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "m", mutexPtr),
			nil, nil, nil, nil, false)))
	mutexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unlock",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "m", mutexPtr),
			nil, nil, nil, nil, false)))

	// type WaitGroup struct{ count int; ch chan int }
	wgStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "count", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "ch", types.NewChan(types.SendRecv, types.Typ[types.Int]), false),
	}, nil)
	wgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WaitGroup", nil),
		wgStruct, nil)
	scope.Insert(wgType.Obj())

	wgPtr := types.NewPointer(wgType)
	wgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "wg", wgPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Int])),
			nil, false)))
	wgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Done",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "wg", wgPtr),
			nil, nil, nil, nil, false)))
	wgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Wait",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "wg", wgPtr),
			nil, nil, nil, nil, false)))

	// type Once struct{ done int }
	onceStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "done", types.Typ[types.Int], false),
	}, nil)
	onceType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Once", nil),
		onceStruct, nil)
	scope.Insert(onceType.Obj())

	oncePtr := types.NewPointer(onceType)
	onceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Do",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "o", oncePtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f",
				types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			nil, false)))

	// type RWMutex struct{ locked int }
	rwMutexStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "locked", types.Typ[types.Int], false),
	}, nil)
	rwMutexType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RWMutex", nil),
		rwMutexStruct, nil)
	scope.Insert(rwMutexType.Obj())

	rwMutexPtr := types.NewPointer(rwMutexType)
	rwMutexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lock",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "rw", rwMutexPtr),
			nil, nil, nil, nil, false)))
	rwMutexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unlock",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "rw", rwMutexPtr),
			nil, nil, nil, nil, false)))
	rwMutexType.AddMethod(types.NewFunc(token.NoPos, pkg, "RLock",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "rw", rwMutexPtr),
			nil, nil, nil, nil, false)))
	rwMutexType.AddMethod(types.NewFunc(token.NoPos, pkg, "RUnlock",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "rw", rwMutexPtr),
			nil, nil, nil, nil, false)))

	// type Map struct{ data int } — simplified
	mapStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	mapType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Map", nil),
		mapStruct, nil)
	scope.Insert(mapType.Obj())

	anyType := types.Universe.Lookup("any").Type()
	mapPtr := types.NewPointer(mapType)
	// func (m *Map) Store(key, value any)
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "Store",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", mapPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", anyType),
				types.NewVar(token.NoPos, nil, "value", anyType)),
			nil, false)))
	// func (m *Map) Load(key any) (value any, ok bool)
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "Load",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", mapPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyType)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "value", anyType),
				types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
			false)))
	// func (m *Map) Delete(key any)
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "Delete",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", mapPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyType)),
			nil, false)))

	// type Pool struct{ New func() any }
	poolStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "New",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyType)), false), false),
	}, nil)
	poolType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Pool", nil),
		poolStruct, nil)
	scope.Insert(poolType.Obj())

	poolPtr := types.NewPointer(poolType)
	// func (p *Pool) Get() any
	poolType.AddMethod(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", poolPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", anyType)),
			false)))
	// func (p *Pool) Put(x any)
	poolType.AddMethod(types.NewFunc(token.NoPos, pkg, "Put",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", poolPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", anyType)),
			nil, false)))

	// Map additional methods
	// func (m *Map) LoadOrStore(key, value any) (actual any, loaded bool)
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "LoadOrStore",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", mapPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", anyType),
				types.NewVar(token.NoPos, nil, "value", anyType)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "actual", anyType),
				types.NewVar(token.NoPos, nil, "loaded", types.Typ[types.Bool])),
			false)))
	// func (m *Map) LoadAndDelete(key any) (value any, loaded bool)
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "LoadAndDelete",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", mapPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyType)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "value", anyType),
				types.NewVar(token.NoPos, nil, "loaded", types.Typ[types.Bool])),
			false)))
	// func (m *Map) Range(f func(key, value any) bool)
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "Range",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", mapPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "key", anyType),
						types.NewVar(token.NoPos, nil, "value", anyType)),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
					false))),
			nil, false)))
	// func (m *Map) Swap(key, value any) (previous any, loaded bool)
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", mapPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", anyType),
				types.NewVar(token.NoPos, nil, "value", anyType)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "previous", anyType),
				types.NewVar(token.NoPos, nil, "loaded", types.Typ[types.Bool])),
			false)))
	// func (m *Map) CompareAndSwap(key, old, new any) bool
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "CompareAndSwap",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", mapPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", anyType),
				types.NewVar(token.NoPos, nil, "old", anyType),
				types.NewVar(token.NoPos, nil, "new", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	// func (m *Map) CompareAndDelete(key, old any) bool
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "CompareAndDelete",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", mapPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", anyType),
				types.NewVar(token.NoPos, nil, "old", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// Mutex.TryLock
	mutexType.AddMethod(types.NewFunc(token.NoPos, pkg, "TryLock",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "m", mutexPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// RWMutex.TryLock, TryRLock, RLocker
	rwMutexType.AddMethod(types.NewFunc(token.NoPos, pkg, "TryLock",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "rw", rwMutexPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	rwMutexType.AddMethod(types.NewFunc(token.NoPos, pkg, "TryRLock",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "rw", rwMutexPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// type Locker interface { Lock(); Unlock() }
	// (define early so RLocker can reference it)
	lockerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Lock",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, pkg, "Unlock",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
	}, nil)
	lockerIface.Complete()
	lockerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Locker", nil),
		lockerIface, nil)
	scope.Insert(lockerType.Obj())

	// func (rw *RWMutex) RLocker() Locker
	rwMutexType.AddMethod(types.NewFunc(token.NoPos, pkg, "RLocker",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "rw", rwMutexPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", lockerType)),
			false)))

	// type Cond struct { L Locker }
	condStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "L", lockerType, false),
	}, nil)
	condType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Cond", nil),
		condStruct, nil)
	scope.Insert(condType.Obj())
	condPtr := types.NewPointer(condType)

	// func NewCond(l Locker) *Cond
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewCond",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "l", lockerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", condPtr)),
			false)))
	condType.AddMethod(types.NewFunc(token.NoPos, pkg, "Wait",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", condPtr),
			nil, nil, nil, nil, false)))
	condType.AddMethod(types.NewFunc(token.NoPos, pkg, "Signal",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", condPtr),
			nil, nil, nil, nil, false)))
	condType.AddMethod(types.NewFunc(token.NoPos, pkg, "Broadcast",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", condPtr),
			nil, nil, nil, nil, false)))

	// type OnceFunc — not a type, but a function
	// func OnceFunc(f func()) func()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OnceFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "",
				types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			false)))
	// func OnceValue[T any](f func() T) func() T — simplified as func(func() any) func() any
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OnceValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", anyType)), false))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", anyType)), false))),
			false)))

	// func OnceValues[T1, T2 any](f func() (T1, T2)) func() (T1, T2) — simplified as func(func() (any, any)) func() (any, any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OnceValues",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", anyType),
						types.NewVar(token.NoPos, nil, "", anyType)), false))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", anyType),
						types.NewVar(token.NoPos, nil, "", anyType)), false))),
			false)))

	// func (m *Map) Clear() — Go 1.23+
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "Clear",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", mapPtr),
			nil, nil, nil, nil, false)))

	// func (wg *WaitGroup) Go(f func()) — Go 1.25+
	wgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Go",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "wg", wgPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f",
				types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

// buildSysPackage creates the type-checked inferno/sys package with
// FD type and function signatures matching the Inferno Sys module.
func buildSysPackage() *types.Package {
	pkg := types.NewPackage("inferno/sys", "sys")

	// FD type: opaque struct wrapping a file descriptor
	fdStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "fd", types.Typ[types.Int], false),
	}, nil)
	fdNamed := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FD", nil), fdStruct, nil)
	fdPtr := types.NewPointer(fdNamed)

	scope := pkg.Scope()
	scope.Insert(fdNamed.Obj())

	// Fildes(fd int) *FD
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fildes",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "fd", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fdPtr)),
			false)))

	// Open(name string, mode int) *FD
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "mode", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fdPtr)),
			false)))

	// Write(fd *FD, buf []byte, n int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fd", fdPtr),
				types.NewVar(token.NoPos, nil, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Read(fd *FD, buf []byte, n int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fd", fdPtr),
				types.NewVar(token.NoPos, nil, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Fprint(fd *FD, s string, args ...any) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fprint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fd", fdPtr),
				types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Sleep(ms int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sleep",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "ms", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Millisec() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Millisec",
		types.NewSignatureType(nil, nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Create(name string, mode int, perm int) *FD
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Create",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "mode", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "perm", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fdPtr)),
			false)))

	// Seek(fd *FD, off int, start int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Seek",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fd", fdPtr),
				types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "start", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Bind(name string, old string, flags int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Bind",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "old", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "flags", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Chdir(path string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chdir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Remove(name string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Remove",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Pipe(fds []FD) int — simplified: takes slice of *FD, returns int
	// In Limbo: pipe(fds: array of ref FD): int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pipe",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "fds", types.NewSlice(fdPtr))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Dup(old int, new int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "old", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Pctl(flags int, movefd []int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pctl",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "flags", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "movefd", types.NewSlice(types.Typ[types.Int]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Constants: OREAD=0, OWRITE=1, ORDWR=2, OTRUNC=16, ORCLOSE=64, OEXCL=4096
	scope.Insert(types.NewConst(token.NoPos, pkg, "OREAD", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "OWRITE", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ORDWR", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "OTRUNC", types.Typ[types.Int], constant.MakeInt64(16)))

	// Bind flags
	scope.Insert(types.NewConst(token.NoPos, pkg, "MREPL", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MBEFORE", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MAFTER", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MCREATE", types.Typ[types.Int], constant.MakeInt64(4)))

	// Pctl flags
	scope.Insert(types.NewConst(token.NoPos, pkg, "NEWPGRP", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FORKNS", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FORKFD", types.Typ[types.Int], constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NEWFD", types.Typ[types.Int], constant.MakeInt64(8)))

	// Seek constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "SEEKSTART", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SEEKRELA", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SEEKEND", types.Typ[types.Int], constant.MakeInt64(2)))

	pkg.MarkComplete()
	return pkg
}

// buildTimePackage creates the type-checked time package stub.
// Duration is int64 (nanoseconds). Time is a struct wrapping milliseconds.
func buildTimePackage() *types.Package {
	pkg := types.NewPackage("time", "time")
	scope := pkg.Scope()

	// type Duration int64 (nanoseconds)
	durationType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Duration", nil),
		types.Typ[types.Int64], nil)
	scope.Insert(durationType.Obj())

	// type Time struct { msec int }
	timeStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "msec", types.Typ[types.Int], false),
	}, nil)
	timeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Time", nil),
		timeStruct, nil)
	scope.Insert(timeType.Obj())

	// func Now() Time
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Now",
		types.NewSignatureType(nil, nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))

	// func Since(t Time) Duration
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Since",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", timeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", durationType)),
			false)))

	// func Sleep(d Duration)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sleep",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", durationType)),
			nil,
			false)))

	// func After(d Duration) <-chan Time
	chanType := types.NewChan(types.RecvOnly, timeType)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "After",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", durationType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", chanType)),
			false)))

	// Duration constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "Nanosecond", durationType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Microsecond", durationType, constant.MakeInt64(1000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Millisecond", durationType, constant.MakeInt64(1000000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Second", durationType, constant.MakeInt64(1000000000)))

	// func (d Duration) Milliseconds() int64
	durationType.AddMethod(types.NewFunc(token.NoPos, pkg, "Milliseconds",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "d", durationType),
			nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))

	// func (t Time) Sub(u Time) Duration
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sub",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "u", timeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", durationType)),
			false)))

	// Additional Duration constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "Minute", durationType, constant.MakeInt64(60000000000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Hour", durationType, constant.MakeInt64(3600000000000)))

	// func (t Time) Unix() int64
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unix",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))

	// func (t Time) UnixMilli() int64
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnixMilli",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))

	// func (t Time) Format(layout string) string
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Format",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "layout", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// func (t Time) String() string
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// func (t Time) IsZero() bool
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsZero",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func (t Time) Before(u Time) bool
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Before",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "u", timeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func (t Time) After(u Time) bool
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "After",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "u", timeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func (t Time) Equal(u Time) bool
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "u", timeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func (t Time) Add(d Duration) Time
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", durationType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))

	// func (d Duration) String() string
	durationType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "d", durationType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// func (d Duration) Seconds() float64
	durationType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seconds",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "d", durationType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])),
			false)))

	// func NewTimer(d Duration) *Timer — simplified as returning Time
	// func NewTicker(d Duration) *Ticker — simplified
	// We'll provide Tick as a channel-returning function
	// func Tick(d Duration) <-chan Time
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Tick",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", durationType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", chanType)),
			false)))

	// func Parse(layout, value string) (Time, error)
	errType := types.Universe.Lookup("error").Type()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "layout", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", timeType),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func ParseInLocation(layout, value string, loc *Location) (Time, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseInLocation",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "layout", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "loc", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", timeType),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func Date(year int, month int, day, hour, min, sec, nsec int, loc *Location) Time
	// Simplified — we just take ints
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Date",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "year", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "month", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "day", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "hour", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "min", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "sec", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "nsec", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "loc", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))

	// Layout constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "RFC3339", types.Typ[types.String],
		constant.MakeString("2006-01-02T15:04:05Z07:00")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RFC1123", types.Typ[types.String],
		constant.MakeString("Mon, 02 Jan 2006 15:04:05 MST")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Kitchen", types.Typ[types.String],
		constant.MakeString("3:04PM")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RFC822", types.Typ[types.String],
		constant.MakeString("02 Jan 06 15:04 MST")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RFC850", types.Typ[types.String],
		constant.MakeString("Monday, 02-Jan-06 15:04:05 MST")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ANSIC", types.Typ[types.String],
		constant.MakeString("Mon Jan _2 15:04:05 2006")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "UnixDate", types.Typ[types.String],
		constant.MakeString("Mon Jan _2 15:04:05 MST 2006")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RubyDate", types.Typ[types.String],
		constant.MakeString("Mon Jan 02 15:04:05 -0700 2006")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RFC3339Nano", types.Typ[types.String],
		constant.MakeString("2006-01-02T15:04:05.999999999Z07:00")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DateTime", types.Typ[types.String],
		constant.MakeString("2006-01-02 15:04:05")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DateOnly", types.Typ[types.String],
		constant.MakeString("2006-01-02")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TimeOnly", types.Typ[types.String],
		constant.MakeString("15:04:05")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Stamp", types.Typ[types.String],
		constant.MakeString("Jan _2 15:04:05")))

	// type Month int
	monthType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Month", nil),
		types.Typ[types.Int], nil)
	scope.Insert(monthType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "January", monthType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "February", monthType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "March", monthType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "April", monthType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "May", monthType, constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "June", monthType, constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "July", monthType, constant.MakeInt64(7)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "August", monthType, constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "September", monthType, constant.MakeInt64(9)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "October", monthType, constant.MakeInt64(10)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "November", monthType, constant.MakeInt64(11)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "December", monthType, constant.MakeInt64(12)))
	monthType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "m", monthType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// type Weekday int
	weekdayType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Weekday", nil),
		types.Typ[types.Int], nil)
	scope.Insert(weekdayType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "Sunday", weekdayType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Monday", weekdayType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Tuesday", weekdayType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Wednesday", weekdayType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Thursday", weekdayType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Friday", weekdayType, constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Saturday", weekdayType, constant.MakeInt64(6)))

	weekdayType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "d", weekdayType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// type Location struct { name string }
	locStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "name", types.Typ[types.String], false),
	}, nil)
	locType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Location", nil),
		locStruct, nil)
	scope.Insert(locType.Obj())
	locPtr := types.NewPointer(locType)

	locType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "l", locPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// var UTC, Local *Location
	scope.Insert(types.NewVar(token.NoPos, pkg, "UTC", locPtr))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Local", locPtr))

	// func LoadLocation(name string) (*Location, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LoadLocation",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", locPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func FixedZone(name string, offset int) *Location
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FixedZone",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", locPtr)),
			false)))

	// func Until(t Time) Duration
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Until",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", timeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", durationType)),
			false)))

	// func ParseDuration(s string) (Duration, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseDuration",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", durationType),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func NewTicker(d Duration) *Ticker
	tickerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "C", chanType, false),
	}, nil)
	tickerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Ticker", nil),
		tickerStruct, nil)
	scope.Insert(tickerType.Obj())
	tickerPtr := types.NewPointer(tickerType)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTicker",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", durationType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", tickerPtr)),
			false)))
	tickerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stop",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", tickerPtr),
			nil, nil, nil, nil, false)))
	tickerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", tickerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", durationType)),
			nil, false)))
	// func (t *Ticker) Chan() <-chan Time — Go 1.23+
	tickerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Chan",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", tickerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", chanType)),
			false)))

	// func NewTimer(d Duration) *Timer
	timerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "C", chanType, false),
	}, nil)
	timerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Timer", nil),
		timerStruct, nil)
	scope.Insert(timerType.Obj())
	timerPtr := types.NewPointer(timerType)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTimer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", durationType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timerPtr)),
			false)))
	timerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stop",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	timerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", durationType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	// func (t *Timer) Chan() <-chan Time — Go 1.23+
	timerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Chan",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", chanType)),
			false)))

	// func AfterFunc(d Duration, f func()) *Timer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AfterFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "d", durationType),
				types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timerPtr)),
			false)))

	// func Unix(sec int64, nsec int64) Time
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "sec", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "nsec", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))

	// func UnixMilli(msec int64) Time
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UnixMilli",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "msec", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))

	// func UnixMicro(usec int64) Time
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UnixMicro",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "usec", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))

	// Time additional methods
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Year",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Month",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", monthType)),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Day",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Hour",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Minute",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Second",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Nanosecond",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Weekday",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", weekdayType)),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Location",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", locPtr)),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "In",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "loc", locPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "UTC",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Local",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnixNano",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnixMicro",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Round",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", durationType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Truncate",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", durationType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "AppendFormat",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "layout", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalJSON",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Duration additional methods
	durationType.AddMethod(types.NewFunc(token.NoPos, pkg, "Hours",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "d", durationType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])),
			false)))
	durationType.AddMethod(types.NewFunc(token.NoPos, pkg, "Minutes",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "d", durationType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])),
			false)))
	durationType.AddMethod(types.NewFunc(token.NoPos, pkg, "Microseconds",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "d", durationType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	durationType.AddMethod(types.NewFunc(token.NoPos, pkg, "Nanoseconds",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "d", durationType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	durationType.AddMethod(types.NewFunc(token.NoPos, pkg, "Abs",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "d", durationType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", durationType)),
			false)))
	durationType.AddMethod(types.NewFunc(token.NoPos, pkg, "Truncate",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "d", durationType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "m", durationType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", durationType)),
			false)))
	durationType.AddMethod(types.NewFunc(token.NoPos, pkg, "Round",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "d", durationType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "m", durationType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", durationType)),
			false)))

	// func (t Time) Compare(u Time) int — Go 1.20+
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "u", timeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// func (t Time) Clock() (hour, min, sec int)
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Clock",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "hour", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "min", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "sec", types.Typ[types.Int])),
			false)))

	// func (t Time) Date() (year int, month Month, day int)
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Date",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "year", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "month", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "day", types.Typ[types.Int])),
			false)))

	// func (t Time) YearDay() int
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "YearDay",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// func (t Time) ISOWeek() (year, week int)
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "ISOWeek",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "year", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "week", types.Typ[types.Int])),
			false)))

	// func (t Time) Zone() (name string, offset int)
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Zone",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int])),
			false)))

	// func (t Time) ZoneBounds() (start, end Time)
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "ZoneBounds",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "start", timeType),
				types.NewVar(token.NoPos, nil, "end", timeType)),
			false)))

	// func (t Time) IsDST() bool
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsDST",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func (t Time) AddDate(years int, months int, days int) Time
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddDate",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "years", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "months", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "days", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))

	// func (t Time) IsValid() bool — Go 1.20+  (named IsZero complement)
	// Note: This was added as time.Time.IsValid() in a proposal but is not yet in stdlib.
	// We provide it for forward compatibility.

	// func (t Time) GoString() string
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "GoString",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// func (t Time) MarshalBinary() ([]byte, error)
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalBinary",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (t *Time) UnmarshalJSON(data []byte) error
	timePtrRecv := types.NewVar(token.NoPos, nil, "t", types.NewPointer(timeType))
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalJSON",
		types.NewSignatureType(timePtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (t *Time) UnmarshalText(data []byte) error
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(timePtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (t *Time) UnmarshalBinary(data []byte) error
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalBinary",
		types.NewSignatureType(timePtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (t *Time) GobDecode(data []byte) error
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "GobDecode",
		types.NewSignatureType(timePtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (t Time) GobEncode() ([]byte, error)
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "GobEncode",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildUnsafePackage() *types.Package {
	pkg := types.NewPackage("unsafe", "unsafe")
	scope := pkg.Scope()

	// type Pointer *ArbitraryType — modeled as uintptr
	pointerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Pointer", nil),
		types.Typ[types.Uintptr], nil)
	scope.Insert(pointerType.Obj())

	// func Sizeof(x ArbitraryType) uintptr
	anyType := types.NewInterfaceType(nil, nil)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sizeof",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uintptr])),
			false)))

	// func Offsetof(x ArbitraryType) uintptr
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Offsetof",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uintptr])),
			false)))

	// func Alignof(x ArbitraryType) uintptr
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Alignof",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uintptr])),
			false)))

	// func Add(ptr Pointer, len IntegerType) Pointer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ptr", pointerType),
				types.NewVar(token.NoPos, pkg, "len", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointerType)),
			false)))

	// func Slice(ptr *ArbitraryType, len IntegerType) []ArbitraryType
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Slice",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ptr", types.NewPointer(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "len", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func String(ptr *byte, len IntegerType) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ptr", types.NewPointer(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "len", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func SliceData(slice []ArbitraryType) *ArbitraryType
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SliceData",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "slice", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(types.Typ[types.Byte]))),
			false)))

	// func StringData(str string) *byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StringData",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "str", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(types.Typ[types.Byte]))),
			false)))

	// type SliceHeader struct { Data uintptr; Len int; Cap int }
	sliceHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Data", types.Typ[types.Uintptr], false),
		types.NewField(token.NoPos, pkg, "Len", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Cap", types.Typ[types.Int], false),
	}, nil)
	sliceHeaderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SliceHeader", nil),
		sliceHeaderStruct, nil)
	scope.Insert(sliceHeaderType.Obj())

	// type StringHeader struct { Data uintptr; Len int }
	stringHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Data", types.Typ[types.Uintptr], false),
		types.NewField(token.NoPos, pkg, "Len", types.Typ[types.Int], false),
	}, nil)
	stringHeaderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "StringHeader", nil),
		stringHeaderStruct, nil)
	scope.Insert(stringHeaderType.Obj())

	pkg.MarkComplete()
	return pkg
}
