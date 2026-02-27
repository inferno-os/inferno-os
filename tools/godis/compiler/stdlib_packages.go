package compiler

// stdlib_packages.go — additional standard library package stubs.
// These are buildXxxPackage() functions called from stubImporter.Import().

import (
	"go/constant"
	"go/token"
	"go/types"
)

func buildCryptoSHA512Package() *types.Package {
	pkg := types.NewPackage("crypto/sha512", "sha512")
	scope := pkg.Scope()

	scope.Insert(types.NewConst(token.NoPos, pkg, "Size", types.Typ[types.Int], constant.MakeInt64(64)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Size256", types.Typ[types.Int], constant.MakeInt64(32)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BlockSize", types.Typ[types.Int], constant.MakeInt64(128)))

	// func Sum512(data []byte) [64]byte — simplified as returning []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum512",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// const Size224 = 28
	scope.Insert(types.NewConst(token.NoPos, pkg, "Size224", types.Typ[types.Int], constant.MakeInt64(28)))
	// const Size384 = 48
	scope.Insert(types.NewConst(token.NoPos, pkg, "Size384", types.Typ[types.Int], constant.MakeInt64(48)))

	// func Sum384(data []byte) [48]byte — simplified as returning []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum384",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func Sum512_224(data []byte) [28]byte — simplified as returning []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum512_224",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func Sum512_256(data []byte) [32]byte — simplified as returning []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum512_256",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// hash.Hash interface (Write, Sum, Reset, Size, BlockSize)
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	hashIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", types.Universe.Lookup("error").Type())),
				false)),
		types.NewFunc(token.NoPos, nil, "Sum",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
				false)),
		types.NewFunc(token.NoPos, nil, "Reset",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
		types.NewFunc(token.NoPos, nil, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	hashIface.Complete()

	// func New() hash.Hash
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)),
			false)))

	// func New384() hash.Hash
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New384",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)),
			false)))

	// func New512_224() hash.Hash
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New512_224",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)),
			false)))

	// func New512_256() hash.Hash
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New512_256",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildCryptoSubtlePackage() *types.Package {
	pkg := types.NewPackage("crypto/subtle", "subtle")
	scope := pkg.Scope()

	// func ConstantTimeCompare(x, y []byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ConstantTimeCompare",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "y", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func ConstantTimeSelect(v, x, y int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ConstantTimeSelect",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "v", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func ConstantTimeEq(x, y int32) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ConstantTimeEq",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Int32]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func XORBytes(dst, x, y []byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "XORBytes",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "x", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "y", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func ConstantTimeByteEq(x, y uint8) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ConstantTimeByteEq",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Uint8])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func ConstantTimeCopy(v int, x, y []byte)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ConstantTimeCopy",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "v", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "x", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "y", types.NewSlice(types.Typ[types.Byte]))),
			nil, false)))

	// func ConstantTimeLessOrEq(x, y int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ConstantTimeLessOrEq",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildEncodingGobPackage() *types.Package {
	pkg := types.NewPackage("encoding/gob", "gob")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anyType := types.Universe.Lookup("any").Type()

	// type Encoder struct
	encStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	encType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Encoder", nil),
		encStruct, nil)
	scope.Insert(encType.Obj())
	encPtr := types.NewPointer(encType)

	// type Decoder struct
	decStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	decType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Decoder", nil),
		decStruct, nil)
	scope.Insert(decType.Obj())
	decPtr := types.NewPointer(decType)

	// io interfaces
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriter.Complete()
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// func NewEncoder(w io.Writer) *Encoder
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewEncoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriter)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", encPtr)),
			false)))

	// func NewDecoder(r io.Reader) *Decoder
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewDecoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", decPtr)),
			false)))

	// func (enc *Encoder) Encode(e any) error
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "e", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (dec *Decoder) Decode(e any) error
	decType.AddMethod(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "dec", decPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "e", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Register(value any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Register",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "value", anyType)),
			nil, false)))

	// func RegisterName(name string, value any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RegisterName",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", anyType)),
			nil, false)))

	// func (enc *Encoder) EncodeValue(value reflect.Value) error — simplified to any
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "EncodeValue",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "value", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (dec *Decoder) DecodeValue(value reflect.Value) error — simplified to any
	decType.AddMethod(types.NewFunc(token.NoPos, pkg, "DecodeValue",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "dec", decPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "value", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type CommonType struct { Name string; Id typeId }
	commonStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Id", types.Typ[types.Int], false),
	}, nil)
	commonType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CommonType", nil),
		commonStruct, nil)
	scope.Insert(commonType.Obj())

	// type GobEncoder interface { GobEncode() ([]byte, error) }
	gobEncoderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "GobEncode",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", byteSlice),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	gobEncoderIface.Complete()
	gobEncoderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "GobEncoder", nil),
		gobEncoderIface, nil)
	scope.Insert(gobEncoderType.Obj())

	// type GobDecoder interface { GobDecode([]byte) error }
	gobDecoderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "GobDecode",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "data", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	gobDecoderIface.Complete()
	gobDecoderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "GobDecoder", nil),
		gobDecoderIface, nil)
	scope.Insert(gobDecoderType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildEncodingASCII85Package() *types.Package {
	pkg := types.NewPackage("encoding/ascii85", "ascii85")
	scope := pkg.Scope()

	// func Encode(dst, src []byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "src", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func MaxEncodedLen(n int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MaxEncodedLen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// func Decode(dst, src []byte, flush bool) (ndst, nsrc int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", byteSlice),
				types.NewVar(token.NoPos, pkg, "src", byteSlice),
				types.NewVar(token.NoPos, pkg, "flush", types.Typ[types.Bool])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ndst", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "nsrc", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// io.Writer and io.Reader stand-ins
	ioWriterASCII := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
	}, nil)
	ioWriterASCII.Complete()

	// io.WriteCloser stand-in
	ioWriteCloserASCII := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	ioWriteCloserASCII.Complete()

	ioReaderASCII := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
	}, nil)
	ioReaderASCII.Complete()

	// func NewEncoder(w io.Writer) io.WriteCloser
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewEncoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterASCII)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioWriteCloserASCII)),
			false)))

	// func NewDecoder(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewDecoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReaderASCII)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReaderASCII)),
			false)))

	// type CorruptInputError int64
	corruptType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CorruptInputError", nil),
		types.Typ[types.Int64], nil)
	scope.Insert(corruptType.Obj())
	corruptType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", corruptType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	pkg.MarkComplete()
	return pkg
}

func buildContainerListPackage() *types.Package {
	pkg := types.NewPackage("container/list", "list")
	scope := pkg.Scope()
	anyType := types.Universe.Lookup("any").Type()

	// type Element struct { Value any }
	elemStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Value", anyType, false),
	}, nil)
	elemType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Element", nil),
		elemStruct, nil)
	scope.Insert(elemType.Obj())
	elemPtr := types.NewPointer(elemType)

	// type List struct
	listStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "len", types.Typ[types.Int], false),
	}, nil)
	listType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "List", nil),
		listStruct, nil)
	scope.Insert(listType.Obj())
	listPtr := types.NewPointer(listType)

	// func New() *List
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", listPtr)),
			false)))

	// func (l *List) PushBack(v any) *Element
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "PushBack",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) PushFront(v any) *Element
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "PushFront",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) Len() int
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func (l *List) Front() *Element
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "Front",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) Remove(e *Element) any
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "Remove",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "e", elemPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func (e *Element) Next() *Element
	elemType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", elemPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (e *Element) Prev() *Element
	elemType.AddMethod(types.NewFunc(token.NoPos, pkg, "Prev",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", elemPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) Back() *Element
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "Back",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) Init() *List
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", listPtr)),
			false)))

	// func (l *List) InsertBefore(v any, mark *Element) *Element
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "InsertBefore",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "v", anyType),
				types.NewVar(token.NoPos, pkg, "mark", elemPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) InsertAfter(v any, mark *Element) *Element
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "InsertAfter",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "v", anyType),
				types.NewVar(token.NoPos, pkg, "mark", elemPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) MoveToFront(e *Element)
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "MoveToFront",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "e", elemPtr)),
			nil, false)))

	// func (l *List) MoveToBack(e *Element)
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "MoveToBack",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "e", elemPtr)),
			nil, false)))

	// func (l *List) MoveBefore(e, mark *Element)
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "MoveBefore",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "e", elemPtr),
				types.NewVar(token.NoPos, pkg, "mark", elemPtr)),
			nil, false)))

	// func (l *List) MoveAfter(e, mark *Element)
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "MoveAfter",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "e", elemPtr),
				types.NewVar(token.NoPos, pkg, "mark", elemPtr)),
			nil, false)))

	// func (l *List) PushBackList(other *List)
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "PushBackList",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "other", listPtr)),
			nil, false)))

	// func (l *List) PushFrontList(other *List)
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "PushFrontList",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "other", listPtr)),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildContainerRingPackage() *types.Package {
	pkg := types.NewPackage("container/ring", "ring")
	scope := pkg.Scope()

	ringStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Value", types.Universe.Lookup("any").Type(), false),
	}, nil)
	ringType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Ring", nil),
		ringStruct, nil)
	scope.Insert(ringType.Obj())
	ringPtr := types.NewPointer(ringType)

	// func New(n int) *Ring
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ringPtr)),
			false)))

	// func (r *Ring) Len() int
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func (r *Ring) Next() *Ring
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ringPtr)),
			false)))

	// func (r *Ring) Prev() *Ring
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Prev",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ringPtr)),
			false)))

	// func (r *Ring) Move(n int) *Ring
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Move",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ringPtr)),
			false)))

	// func (r *Ring) Link(s *Ring) *Ring
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Link",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", ringPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ringPtr)),
			false)))

	// func (r *Ring) Unlink(n int) *Ring
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unlink",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ringPtr)),
			false)))

	// func (r *Ring) Do(f func(any))
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Do",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("any").Type())),
					nil, false))),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildContainerHeapPackage() *types.Package {
	pkg := types.NewPackage("container/heap", "heap")
	scope := pkg.Scope()
	anyType := types.Universe.Lookup("any").Type()

	// type Interface interface { Len() int; Less(i, j int) bool; Swap(i, j int); Push(x any); Pop() any }
	heapIface := types.NewInterfaceType([]*types.Func{
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
		types.NewFunc(token.NoPos, pkg, "Push",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "x", anyType)),
				nil, false)),
		types.NewFunc(token.NoPos, pkg, "Pop",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyType)), false)),
	}, nil)
	heapIface.Complete()
	heapIfaceType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Interface", nil), heapIface, nil)
	scope.Insert(heapIfaceType.Obj())

	// func Init(h Interface)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "h", heapIfaceType)),
			nil, false)))

	// func Push(h Interface, x any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Push",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", heapIfaceType),
				types.NewVar(token.NoPos, pkg, "x", anyType)),
			nil, false)))

	// func Pop(h Interface) any
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pop",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "h", heapIfaceType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func Fix(h Interface, i int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", heapIfaceType),
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int])),
			nil, false)))

	// func Remove(h Interface, i int) any
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Remove",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", heapIfaceType),
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildImagePackage() *types.Package {
	pkg := types.NewPackage("image", "image")
	scope := pkg.Scope()

	// type Point struct { X, Y int }
	pointStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "X", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Int], false),
	}, nil)
	pointType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Point", nil),
		pointStruct, nil)
	scope.Insert(pointType.Obj())

	// func Pt(X, Y int) Point
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "X", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "Y", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointType)),
			false)))

	// type Rectangle struct { Min, Max Point }
	rectStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Min", pointType, false),
		types.NewField(token.NoPos, pkg, "Max", pointType, false),
	}, nil)
	rectType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Rectangle", nil),
		rectStruct, nil)
	scope.Insert(rectType.Obj())

	// func Rect(x0, y0, x1, y1 int) Rectangle
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Rect",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x0", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "y0", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "x1", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "y1", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))

	// Forward-declare Image type (will be set to real interface after all structs are defined)
	imageType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Image", nil),
		types.NewInterfaceType(nil, nil), nil)

	// type RGBA struct
	rgbaStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", types.NewSlice(types.Typ[types.Uint8]), false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	rgbaType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RGBA", nil),
		rgbaStruct, nil)
	scope.Insert(rgbaType.Obj())

	// func NewRGBA(r Rectangle) *RGBA
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRGBA",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(rgbaType))),
			false)))

	rgbaPtr := types.NewPointer(rgbaType)

	// color.Color stand-in interface (defined early for use in At/Set methods)
	colorIfaceLocal := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIfaceLocal.Complete()

	// Helper to add standard image type methods
	addImageMethods := func(imgType *types.Named, imgPtr *types.Pointer) {
		imgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bounds",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", imgPtr),
				nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
				false)))
		imgType.AddMethod(types.NewFunc(token.NoPos, pkg, "At",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", imgPtr),
				nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfaceLocal)),
				false)))
		imgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", imgPtr),
				nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "c", colorIfaceLocal)),
				nil, false)))
		imgType.AddMethod(types.NewFunc(token.NoPos, pkg, "SubImage",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", imgPtr),
				nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", imageType)),
				false)))
		imgType.AddMethod(types.NewFunc(token.NoPos, pkg, "PixOffset",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", imgPtr),
				nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)))
		imgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Opaque",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", imgPtr),
				nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
				false)))
	}

	// RGBA methods
	addImageMethods(rgbaType, rgbaPtr)

	pixSlice := types.NewSlice(types.Typ[types.Uint8])

	// type NRGBA struct { Pix, Stride, Rect }
	nrgbaStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	nrgbaType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NRGBA", nil),
		nrgbaStruct, nil)
	scope.Insert(nrgbaType.Obj())
	nrgbaPtr := types.NewPointer(nrgbaType)
	addImageMethods(nrgbaType, nrgbaPtr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewNRGBA",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", nrgbaPtr)),
			false)))

	// type Gray struct
	grayStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	grayType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Gray", nil),
		grayStruct, nil)
	scope.Insert(grayType.Obj())
	grayPtr := types.NewPointer(grayType)
	addImageMethods(grayType, grayPtr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewGray",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", grayPtr)),
			false)))

	// type Alpha struct
	alphaStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	alphaType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Alpha", nil),
		alphaStruct, nil)
	scope.Insert(alphaType.Obj())
	alphaPtr := types.NewPointer(alphaType)
	addImageMethods(alphaType, alphaPtr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewAlpha",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", alphaPtr)),
			false)))

	// type RGBA64 struct { Pix, Stride, Rect }
	rgba64Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	rgba64Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RGBA64", nil),
		rgba64Struct, nil)
	scope.Insert(rgba64Type.Obj())
	rgba64Ptr := types.NewPointer(rgba64Type)
	addImageMethods(rgba64Type, rgba64Ptr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRGBA64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rgba64Ptr)),
			false)))

	// type NRGBA64 struct { Pix, Stride, Rect }
	nrgba64Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	nrgba64Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NRGBA64", nil),
		nrgba64Struct, nil)
	scope.Insert(nrgba64Type.Obj())
	nrgba64Ptr := types.NewPointer(nrgba64Type)
	addImageMethods(nrgba64Type, nrgba64Ptr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewNRGBA64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", nrgba64Ptr)),
			false)))

	// type Gray16 struct { Pix, Stride, Rect }
	gray16Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	gray16Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Gray16", nil),
		gray16Struct, nil)
	scope.Insert(gray16Type.Obj())
	gray16Ptr := types.NewPointer(gray16Type)
	addImageMethods(gray16Type, gray16Ptr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewGray16",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", gray16Ptr)),
			false)))

	// type Paletted struct { Pix, Stride, Rect, Palette }
	palettedStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
		types.NewField(token.NoPos, pkg, "Palette", types.NewSlice(colorIfaceLocal), false),
	}, nil)
	palettedType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Paletted", nil),
		palettedStruct, nil)
	scope.Insert(palettedType.Obj())
	palettedPtr := types.NewPointer(palettedType)
	addImageMethods(palettedType, palettedPtr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewPaletted",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", rectType),
				types.NewVar(token.NoPos, pkg, "p", types.NewSlice(colorIfaceLocal))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", palettedPtr)),
			false)))

	// color.Color interface — RGBA() (r, g, b, a uint32)
	colorIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIface.Complete()

	// color.Model interface
	colorModelIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Convert",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorIface)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIface)),
				false)),
	}, nil)
	colorModelIface.Complete()

	// type Uniform struct { C color.Color }
	uniformStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "C", colorIface, false),
	}, nil)
	uniformType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Uniform", nil),
		uniformStruct, nil)
	scope.Insert(uniformType.Obj())

	// func NewUniform(c color.Color) *Uniform
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewUniform",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "c", colorIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(uniformType))),
			false)))

	// type Config struct { ColorModel color.Model, Width int, Height int }
	configStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ColorModel", colorModelIface, false),
		types.NewField(token.NoPos, pkg, "Width", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Height", types.Typ[types.Int], false),
	}, nil)
	configType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Config", nil),
		configStruct, nil)
	scope.Insert(configType.Obj())

	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// Image interface
	imageIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelIface)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectType)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIface)),
				false)),
	}, nil)
	imageIface.Complete()
	imageType.SetUnderlying(imageIface)
	scope.Insert(imageType.Obj())

	// func DecodeConfig(r io.Reader) (Config, string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeConfig",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", configType),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Decode(r io.Reader) (Image, string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// decode func type: func(io.Reader) (Image, error)
	decodeFuncType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "r", ioReader)),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", imageIface),
			types.NewVar(token.NoPos, nil, "", errType)),
		false)
	// decodeConfig func type: func(io.Reader) (Config, error)
	decodeConfigFuncType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "r", ioReader)),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", configType),
			types.NewVar(token.NoPos, nil, "", errType)),
		false)

	// func RegisterFormat(name, magic string, decode func(io.Reader)(Image, error), decodeConfig func(io.Reader)(Config, error))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RegisterFormat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "magic", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "decode", decodeFuncType),
				types.NewVar(token.NoPos, pkg, "decodeConfig", decodeConfigFuncType)),
			nil, false)))

	// Point methods
	pointPtr := types.NewPointer(pointType)
	_ = pointPtr
	// func (p Point) Add(q Point) Point
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "q", pointType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointType)),
			false)))
	// func (p Point) Sub(q Point) Point
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sub",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "q", pointType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointType)),
			false)))
	// func (p Point) Mul(k int) Point
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "Mul",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "k", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointType)),
			false)))
	// func (p Point) Div(k int) Point
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "Div",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "k", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointType)),
			false)))
	// func (p Point) In(r Rectangle) bool
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "In",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	// func (p Point) Eq(q Point) bool
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "Eq",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "q", pointType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	// func (p Point) String() string
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Rectangle methods
	// func (r Rectangle) Dx() int
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Dx",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	// func (r Rectangle) Dy() int
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Dy",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	// func (r Rectangle) Size() Point
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointType)),
			false)))
	// func (r Rectangle) Empty() bool
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Empty",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	// func (r Rectangle) Eq(s Rectangle) bool
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Eq",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	// func (r Rectangle) Overlaps(s Rectangle) bool
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Overlaps",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	// func (r Rectangle) In(s Rectangle) bool
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "In",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	// func (r Rectangle) Intersect(s Rectangle) Rectangle
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Intersect",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))
	// func (r Rectangle) Union(s Rectangle) Rectangle
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Union",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))
	// func (r Rectangle) Add(p Point) Rectangle
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", pointType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))
	// func (r Rectangle) Sub(p Point) Rectangle
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sub",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", pointType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))
	// func (r Rectangle) Inset(n int) Rectangle
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Inset",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))
	// func (r Rectangle) Canon() Rectangle
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Canon",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))
	// func (r Rectangle) String() string
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// var ZP Point (deprecated but still used)
	scope.Insert(types.NewVar(token.NoPos, pkg, "ZP", pointType))
	// var ZR Rectangle (deprecated but still used)
	scope.Insert(types.NewVar(token.NoPos, pkg, "ZR", rectType))

	pkg.MarkComplete()
	return pkg
}

func buildImageColorPackage() *types.Package {
	pkg := types.NewPackage("image/color", "color")
	scope := pkg.Scope()

	// type RGBA struct { R, G, B, A uint8 }
	rgbaStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "R", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "G", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "B", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint8], false),
	}, nil)
	rgbaType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RGBA", nil),
		rgbaStruct, nil)
	scope.Insert(rgbaType.Obj())

	// type NRGBA struct { R, G, B, A uint8 }
	nrgbaStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "R", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "G", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "B", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint8], false),
	}, nil)
	nrgbaType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NRGBA", nil),
		nrgbaStruct, nil)
	scope.Insert(nrgbaType.Obj())

	// type Gray struct { Y uint8 }
	grayStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Uint8], false),
	}, nil)
	grayType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Gray", nil),
		grayStruct, nil)
	scope.Insert(grayType.Obj())

	// type Alpha struct { A uint8 }
	alphaStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint8], false),
	}, nil)
	alphaType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Alpha", nil),
		alphaStruct, nil)
	scope.Insert(alphaType.Obj())

	// type RGBA64 struct { R, G, B, A uint16 }
	rgba64Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "R", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "G", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "B", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint16], false),
	}, nil)
	rgba64Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RGBA64", nil),
		rgba64Struct, nil)
	scope.Insert(rgba64Type.Obj())

	// Color interface { RGBA() (r, g, b, a uint32) }
	colorIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIface.Complete()
	colorType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Color", nil),
		colorIface, nil)
	scope.Insert(colorType.Obj())

	// Add RGBA() method to concrete color types
	rgbaMethod := types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", rgbaType), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
			false))
	rgbaType.AddMethod(rgbaMethod)
	nrgbaType.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", nrgbaType), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
			false)))
	grayType.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", grayType), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
			false)))
	alphaType.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", alphaType), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
			false)))
	rgba64Type.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", rgba64Type), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
			false)))

	// Model interface { Convert(c Color) Color }
	modelIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Convert",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorType)),
				false)),
	}, nil)
	modelIface.Complete()
	modelType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Model", nil),
		modelIface, nil)
	scope.Insert(modelType.Obj())

	// Model vars
	scope.Insert(types.NewVar(token.NoPos, pkg, "RGBAModel", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "RGBA64Model", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "NRGBAModel", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "GrayModel", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "AlphaModel", modelType))

	// func ModelFunc(f func(Color) Color) Model
	modelFuncSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorType)),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", colorType)),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ModelFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f", modelFuncSig)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", modelType)),
			false)))

	// type NRGBA64 struct { R, G, B, A uint16 }
	nrgba64Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "R", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "G", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "B", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint16], false),
	}, nil)
	nrgba64Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NRGBA64", nil),
		nrgba64Struct, nil)
	scope.Insert(nrgba64Type.Obj())

	// type Gray16 struct { Y uint16 }
	gray16Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Uint16], false),
	}, nil)
	gray16Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Gray16", nil),
		gray16Struct, nil)
	scope.Insert(gray16Type.Obj())

	// type Alpha16 struct { A uint16 }
	alpha16Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint16], false),
	}, nil)
	alpha16Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Alpha16", nil),
		alpha16Struct, nil)
	scope.Insert(alpha16Type.Obj())

	// Add RGBA() method to new color types
	rgbaTuple := types.NewTuple(
		types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
		types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
		types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
		types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32]))
	nrgba64Type.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", nrgba64Type), nil, nil, nil, rgbaTuple, false)))
	gray16Type.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", gray16Type), nil, nil, nil, rgbaTuple, false)))
	alpha16Type.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", alpha16Type), nil, nil, nil, rgbaTuple, false)))

	// type YCbCr struct { Y, Cb, Cr uint8 }
	ycbcrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Cb", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Cr", types.Typ[types.Uint8], false),
	}, nil)
	ycbcrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "YCbCr", nil),
		ycbcrStruct, nil)
	scope.Insert(ycbcrType.Obj())
	ycbcrType.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", ycbcrType), nil, nil, nil, rgbaTuple, false)))

	// type NYCbCrA struct { Y, Cb, Cr, A uint8 }
	nycbcraStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Cb", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Cr", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint8], false),
	}, nil)
	nycbcraType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NYCbCrA", nil),
		nycbcraStruct, nil)
	scope.Insert(nycbcraType.Obj())
	nycbcraType.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", nycbcraType), nil, nil, nil, rgbaTuple, false)))

	// type CMYK struct { C, M, Y, K uint8 }
	cmykStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "C", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "M", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "K", types.Typ[types.Uint8], false),
	}, nil)
	cmykType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CMYK", nil),
		cmykStruct, nil)
	scope.Insert(cmykType.Obj())
	cmykType.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", cmykType), nil, nil, nil, rgbaTuple, false)))

	// type Palette []Color
	paletteType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Palette", nil),
		types.NewSlice(colorType), nil)
	scope.Insert(paletteType.Obj())
	palRecv := types.NewVar(token.NoPos, nil, "p", paletteType)
	paletteType.AddMethod(types.NewFunc(token.NoPos, pkg, "Convert",
		types.NewSignatureType(palRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", colorType)), false)))
	paletteType.AddMethod(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(palRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// Additional Model vars
	scope.Insert(types.NewVar(token.NoPos, pkg, "NRGBA64Model", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Gray16Model", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Alpha16Model", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "YCbCrModel", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "NYCbCrAModel", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "CMYKModel", modelType))

	// Color conversion functions
	// func RGBToYCbCr(r, g, b uint8) (uint8, uint8, uint8)
	u8Tuple := types.NewTuple(
		types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8]),
		types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8]),
		types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8]))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RGBToYCbCr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "g", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Uint8])),
			u8Tuple, false)))
	// func YCbCrToRGB(y, cb, cr uint8) (uint8, uint8, uint8)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "YCbCrToRGB",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "cb", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "cr", types.Typ[types.Uint8])),
			u8Tuple, false)))
	// func RGBToCMYK(r, g, b uint8) (uint8, uint8, uint8, uint8)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RGBToCMYK",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "g", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Uint8])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8])), false)))
	// func CMYKToRGB(c, m, y, k uint8) (uint8, uint8, uint8)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CMYKToRGB",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "m", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "k", types.Typ[types.Uint8])),
			u8Tuple, false)))

	// var White, Black, Transparent, Opaque
	scope.Insert(types.NewVar(token.NoPos, pkg, "White", rgbaType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Black", rgbaType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Transparent", alphaType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Opaque", alphaType))

	pkg.MarkComplete()
	return pkg
}

func buildImagePNGPackage() *types.Package {
	pkg := types.NewPackage("image/png", "png")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriter.Complete()
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// image.Image stand-in interface { ColorModel() color.Model; Bounds() Rectangle; At(x, y int) color.Color }
	colorIfacePNG := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIfacePNG.Complete()
	colorModelPNG := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Convert",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorIfacePNG)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfacePNG)),
				false)),
	}, nil)
	colorModelPNG.Complete()
	rectStructPNG := types.NewStruct([]*types.Var{
		types.NewVar(token.NoPos, nil, "Min", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
		types.NewVar(token.NoPos, nil, "Max", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
	}, nil)
	imageIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelPNG)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectStructPNG)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfacePNG)),
				false)),
	}, nil)
	imageIface.Complete()

	// type CompressionLevel int
	compType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CompressionLevel", nil),
		types.Typ[types.Int], nil)
	scope.Insert(compType.Obj())

	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultCompression", compType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NoCompression", compType, constant.MakeInt64(-1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BestSpeed", compType, constant.MakeInt64(-2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BestCompression", compType, constant.MakeInt64(-3)))

	// type Encoder struct { CompressionLevel CompressionLevel }
	encoderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "CompressionLevel", compType, false),
	}, nil)
	encoderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Encoder", nil),
		encoderStruct, nil)
	scope.Insert(encoderType.Obj())
	encoderPtr := types.NewPointer(encoderType)

	// func (enc *Encoder) Encode(w io.Writer, m image.Image) error
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "enc", encoderPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "m", imageIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type FormatError string
	formatErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FormatError", nil),
		types.Typ[types.String], nil)
	formatErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", formatErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(formatErrType.Obj())

	// type UnsupportedError string
	unsupportedErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnsupportedError", nil),
		types.Typ[types.String], nil)
	unsupportedErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unsupportedErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unsupportedErrType.Obj())

	// func Encode(w io.Writer, m image.Image) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "m", imageIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Decode(r io.Reader) (image.Image, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DecodeConfig(r io.Reader) (image.Config, error)
	configStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Width", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Height", types.Typ[types.Int], false),
	}, nil)
	configType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Config", nil),
		configStruct, nil)
	_ = configType
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeConfig",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildImageJPEGPackage() *types.Package {
	pkg := types.NewPackage("image/jpeg", "jpeg")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriter.Complete()
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// image.Image stand-in interface { ColorModel(); Bounds(); At() }
	colorIfaceJPG := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIfaceJPG.Complete()
	colorModelJPG := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Convert",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorIfaceJPG)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfaceJPG)),
				false)),
	}, nil)
	colorModelJPG.Complete()
	rectStructJPG := types.NewStruct([]*types.Var{
		types.NewVar(token.NoPos, nil, "Min", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
		types.NewVar(token.NoPos, nil, "Max", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
	}, nil)
	imageIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelJPG)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectStructJPG)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfaceJPG)),
				false)),
	}, nil)
	imageIface.Complete()

	// type Options struct { Quality int }
	optionsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Quality", types.Typ[types.Int], false),
	}, nil)
	optionsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Options", nil),
		optionsStruct, nil)
	scope.Insert(optionsType.Obj())

	// type FormatError string
	formatErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FormatError", nil),
		types.Typ[types.String], nil)
	formatErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", formatErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(formatErrType.Obj())

	// type UnsupportedError string
	unsupportedErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnsupportedError", nil),
		types.Typ[types.String], nil)
	unsupportedErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unsupportedErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unsupportedErrType.Obj())

	// func Encode(w io.Writer, m image.Image, o *Options) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "m", imageIface),
				types.NewVar(token.NoPos, pkg, "o", types.NewPointer(optionsType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Decode(r io.Reader) (image.Image, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DecodeConfig(r io.Reader) (image.Config, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeConfig",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultQuality", types.Typ[types.Int], constant.MakeInt64(75)))

	pkg.MarkComplete()
	return pkg
}

func buildDebugBuildInfoPackage() *types.Package {
	pkg := types.NewPackage("debug/buildinfo", "buildinfo")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type BuildInfo = debug.BuildInfo (same as runtime/debug.BuildInfo)
	// type BuildInfo struct { GoVersion string; Path string; Main Module; Deps []*Module; Settings []BuildSetting }
	moduleStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Sum", types.Typ[types.String], false),
	}, nil)
	moduleType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Module", nil), moduleStruct, nil)

	buildSettingStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Key", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.String], false),
	}, nil)
	buildSettingType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BuildSetting", nil), buildSettingStruct, nil)

	infoStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "GoVersion", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Main", moduleType, false),
		types.NewField(token.NoPos, pkg, "Deps", types.NewSlice(types.NewPointer(moduleType)), false),
		types.NewField(token.NoPos, pkg, "Settings", types.NewSlice(buildSettingType), false),
	}, nil)
	infoType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BuildInfo", nil), infoStruct, nil)
	scope.Insert(infoType.Obj())
	infoPtr := types.NewPointer(infoType)
	infoType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "bi", infoPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// func ReadFile(name string) (*BuildInfo, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", infoPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.ReaderAt interface for Read
	byteSliceBI := types.NewSlice(types.Typ[types.Byte])
	readerAtBI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSliceBI),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerAtBI.Complete()

	// func Read(r io.ReaderAt) (*BuildInfo, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerAtBI)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", infoPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoASTPackage() *types.Package {
	pkg := types.NewPackage("go/ast", "ast")
	scope := pkg.Scope()

	// Pos type (simplified as int, same underlying type as token.Pos)
	posType := types.Typ[types.Int]

	// type Node interface { Pos() token.Pos; End() token.Pos }
	nodeIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
		types.NewFunc(token.NoPos, pkg, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
	}, nil)
	nodeIface.Complete()
	nodeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Node", nil), nodeIface, nil)
	scope.Insert(nodeType.Obj())

	// type Expr interface { Node; exprNode() }
	exprIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
		types.NewFunc(token.NoPos, pkg, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
	}, nil)
	exprIface.Complete()
	exprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Expr", nil), exprIface, nil)
	scope.Insert(exprType.Obj())

	// type Stmt interface { Node; stmtNode() }
	stmtIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
		types.NewFunc(token.NoPos, pkg, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
	}, nil)
	stmtIface.Complete()
	stmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Stmt", nil), stmtIface, nil)
	scope.Insert(stmtType.Obj())

	// type Decl interface { Node; declNode() }
	declIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
		types.NewFunc(token.NoPos, pkg, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
	}, nil)
	declIface.Complete()
	declType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Decl", nil), declIface, nil)
	scope.Insert(declType.Obj())

	// type Spec interface (same shape as Node)
	specIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
		types.NewFunc(token.NoPos, pkg, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
	}, nil)
	specIface.Complete()
	specType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Spec", nil), specIface, nil)
	scope.Insert(specType.Obj())

	// type Object struct { Kind ObjKind; Name string; Decl interface{}; Data interface{}; Type interface{} }
	objKindType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ObjKind", nil), types.Typ[types.Int], nil)
	scope.Insert(objKindType.Obj())
	for i, name := range []string{"Bad", "Pkg", "Con", "Typ", "Var", "Fun", "Lbl"} {
		scope.Insert(types.NewConst(token.NoPos, pkg, name, objKindType, constant.MakeInt64(int64(i))))
	}

	anyType := types.NewInterfaceType(nil, nil)
	objectStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Kind", objKindType, false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Decl", anyType, false),
		types.NewField(token.NoPos, pkg, "Data", anyType, false),
		types.NewField(token.NoPos, pkg, "Type", anyType, false),
	}, nil)
	objectType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Object", nil), objectStruct, nil)
	scope.Insert(objectType.Obj())
	objectPtr := types.NewPointer(objectType)

	// type Ident struct { NamePos token.Pos; Name string; Obj *Object }
	identStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "NamePos", posType, false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Obj", objectPtr, false),
	}, nil)
	identType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Ident", nil), identStruct, nil)
	scope.Insert(identType.Obj())
	identPtr := types.NewPointer(identType)

	// type Scope struct { Outer *Scope; Objects map[string]*Object }
	scopeObjType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Scope", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(scopeObjType.Obj())
	scopePtr := types.NewPointer(scopeObjType)
	scopeRecv := types.NewVar(token.NoPos, nil, "s", scopePtr)
	scopeObjType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", objectPtr)), false)))
	scopeObjType.AddMethod(types.NewFunc(token.NoPos, pkg, "Insert",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "obj", objectPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", objectPtr)), false)))
	scopeObjType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewScope",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "outer", scopePtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtr)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewObj",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "kind", objKindType),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", objectPtr)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewIdent",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", identPtr)), false)))

	// type BasicLit struct { ValuePos token.Pos; Kind token.Token; Value string }
	basicLitStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ValuePos", posType, false),
		types.NewField(token.NoPos, pkg, "Kind", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.String], false),
	}, nil)
	basicLitType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BasicLit", nil), basicLitStruct, nil)
	scope.Insert(basicLitType.Obj())

	// type CommentGroup struct { List []*Comment }
	commentStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Slash", posType, false),
		types.NewField(token.NoPos, pkg, "Text", types.Typ[types.String], false),
	}, nil)
	commentType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Comment", nil), commentStruct, nil)
	scope.Insert(commentType.Obj())

	commentGroupStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "List", types.NewSlice(types.NewPointer(commentType)), false),
	}, nil)
	commentGroupType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CommentGroup", nil), commentGroupStruct, nil)
	scope.Insert(commentGroupType.Obj())
	commentGroupPtr := types.NewPointer(commentGroupType)
	commentGroupType.AddMethod(types.NewFunc(token.NoPos, pkg, "Text",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "g", commentGroupPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type FieldList struct { Opening token.Pos; List []*Field; Closing token.Pos }
	fieldStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Names", types.NewSlice(identPtr), false),
		types.NewField(token.NoPos, pkg, "Type", exprType, false),
		types.NewField(token.NoPos, pkg, "Tag", types.NewPointer(basicLitType), false),
		types.NewField(token.NoPos, pkg, "Comment", commentGroupPtr, false),
	}, nil)
	fieldType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Field", nil), fieldStruct, nil)
	scope.Insert(fieldType.Obj())
	fieldListStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Opening", posType, false),
		types.NewField(token.NoPos, pkg, "List", types.NewSlice(types.NewPointer(fieldType)), false),
		types.NewField(token.NoPos, pkg, "Closing", posType, false),
	}, nil)
	fieldListType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FieldList", nil), fieldListStruct, nil)
	scope.Insert(fieldListType.Obj())
	fieldListPtr := types.NewPointer(fieldListType)
	fieldListType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumFields",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "f", fieldListPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// type FuncType struct { Func token.Pos; Params, Results *FieldList }
	funcTypeStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Func", posType, false),
		types.NewField(token.NoPos, pkg, "Params", fieldListPtr, false),
		types.NewField(token.NoPos, pkg, "Results", fieldListPtr, false),
	}, nil)
	funcTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FuncType", nil), funcTypeStruct, nil)
	scope.Insert(funcTypeType.Obj())

	// type FuncDecl struct { Doc *CommentGroup; Recv *FieldList; Name *Ident; Type *FuncType; Body *BlockStmt }
	blockStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BlockStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Lbrace", posType, false),
			types.NewField(token.NoPos, pkg, "List", types.NewSlice(stmtType), false),
			types.NewField(token.NoPos, pkg, "Rbrace", posType, false),
		}, nil), nil)
	scope.Insert(blockStmtType.Obj())

	funcDeclStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Doc", commentGroupPtr, false),
		types.NewField(token.NoPos, pkg, "Recv", fieldListPtr, false),
		types.NewField(token.NoPos, pkg, "Name", identPtr, false),
		types.NewField(token.NoPos, pkg, "Type", types.NewPointer(funcTypeType), false),
		types.NewField(token.NoPos, pkg, "Body", types.NewPointer(blockStmtType), false),
	}, nil)
	funcDeclType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FuncDecl", nil), funcDeclStruct, nil)
	scope.Insert(funcDeclType.Obj())

	// type GenDecl struct { Doc *CommentGroup; TokPos token.Pos; Tok token.Token; Specs []Spec }
	genDeclStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Doc", commentGroupPtr, false),
		types.NewField(token.NoPos, pkg, "TokPos", posType, false),
		types.NewField(token.NoPos, pkg, "Tok", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Lparen", posType, false),
		types.NewField(token.NoPos, pkg, "Specs", types.NewSlice(specType), false),
		types.NewField(token.NoPos, pkg, "Rparen", posType, false),
	}, nil)
	genDeclType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "GenDecl", nil), genDeclStruct, nil)
	scope.Insert(genDeclType.Obj())

	// type ImportSpec struct { Doc *CommentGroup; Name *Ident; Path *BasicLit; Comment *CommentGroup }
	importSpecStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Doc", commentGroupPtr, false),
		types.NewField(token.NoPos, pkg, "Name", identPtr, false),
		types.NewField(token.NoPos, pkg, "Path", types.NewPointer(basicLitType), false),
		types.NewField(token.NoPos, pkg, "Comment", commentGroupPtr, false),
	}, nil)
	importSpecType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ImportSpec", nil), importSpecStruct, nil)
	scope.Insert(importSpecType.Obj())

	// type File struct
	fileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Doc", commentGroupPtr, false),
		types.NewField(token.NoPos, pkg, "Package", posType, false),
		types.NewField(token.NoPos, pkg, "Name", identPtr, false),
		types.NewField(token.NoPos, pkg, "Decls", types.NewSlice(declType), false),
		types.NewField(token.NoPos, pkg, "Scope", scopePtr, false),
		types.NewField(token.NoPos, pkg, "Imports", types.NewSlice(types.NewPointer(importSpecType)), false),
		types.NewField(token.NoPos, pkg, "Unresolved", types.NewSlice(identPtr), false),
		types.NewField(token.NoPos, pkg, "Comments", types.NewSlice(commentGroupPtr), false),
	}, nil)
	fileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "File", nil), fileStruct, nil)
	scope.Insert(fileType.Obj())

	// type Package struct { Name string; Scope *Scope; Imports map[string]*Object; Files map[string]*File }
	packageStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Scope", scopePtr, false),
		types.NewField(token.NoPos, pkg, "Files", types.NewMap(types.Typ[types.String], types.NewPointer(fileType)), false),
	}, nil)
	packageType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Package", nil), packageStruct, nil)
	scope.Insert(packageType.Obj())

	// Helper functions
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Inspect",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "node", nodeType),
				types.NewVar(token.NoPos, nil, "f", types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "node", nodeType)),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false))),
			nil, false)))

	// type Visitor interface { Visit(node Node) (w Visitor) }
	// Self-referential: create named type first, then set underlying interface
	visitorType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Visitor", nil), types.NewInterfaceType(nil, nil), nil)
	visitorIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Visit",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "node", nodeType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "w", visitorType)), false)),
	}, nil)
	visitorIface.Complete()
	visitorType.SetUnderlying(visitorIface)
	scope.Insert(visitorType.Obj())

	scope.Insert(types.NewFunc(token.NoPos, pkg, "Walk",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "v", visitorType),
				types.NewVar(token.NoPos, nil, "node", nodeType)),
			nil, false)))

	// *token.FileSet stand-in for Print/Fprint
	fsetPtr := types.NewPointer(types.NewStruct(nil, nil))
	errTypeAST := types.Universe.Lookup("error").Type()

	scope.Insert(types.NewFunc(token.NoPos, pkg, "Print",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fset", fsetPtr),
				types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errTypeAST)), false)))

	// io.Writer for Fprint
	byteSliceAST := types.NewSlice(types.Typ[types.Byte])
	ioWriterAST := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceAST)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errTypeAST)),
				false)),
	}, nil)
	ioWriterAST.Complete()

	// FieldFilter func(name string, value reflect.Value) bool — simplified as any
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fprint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "w", ioWriterAST),
				types.NewVar(token.NoPos, nil, "fset", fsetPtr),
				types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, nil, "f", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errTypeAST)), false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsExported",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// token.Token stand-in
	tokenIntType := types.Typ[types.Int]

	// --- Expression node types ---

	// type BadExpr struct { From, To token.Pos }
	badExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BadExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "From", posType, false),
			types.NewField(token.NoPos, pkg, "To", posType, false),
		}, nil), nil)
	scope.Insert(badExprType.Obj())

	// type Ellipsis struct { Ellipsis token.Pos; Elt Expr }
	ellipsisType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Ellipsis", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Ellipsis", posType, false),
			types.NewField(token.NoPos, pkg, "Elt", exprType, false),
		}, nil), nil)
	scope.Insert(ellipsisType.Obj())

	// type UnaryExpr struct { OpPos token.Pos; Op token.Token; X Expr }
	unaryExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UnaryExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "OpPos", posType, false),
			types.NewField(token.NoPos, pkg, "Op", tokenIntType, false),
			types.NewField(token.NoPos, pkg, "X", exprType, false),
		}, nil), nil)
	scope.Insert(unaryExprType.Obj())

	// type BinaryExpr struct { X Expr; OpPos token.Pos; Op token.Token; Y Expr }
	binaryExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BinaryExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "OpPos", posType, false),
			types.NewField(token.NoPos, pkg, "Op", tokenIntType, false),
			types.NewField(token.NoPos, pkg, "Y", exprType, false),
		}, nil), nil)
	scope.Insert(binaryExprType.Obj())

	// type StarExpr struct { Star token.Pos; X Expr }
	starExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "StarExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Star", posType, false),
			types.NewField(token.NoPos, pkg, "X", exprType, false),
		}, nil), nil)
	scope.Insert(starExprType.Obj())

	// type CallExpr struct { Fun Expr; Lparen token.Pos; Args []Expr; Ellipsis token.Pos; Rparen token.Pos }
	callExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CallExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Fun", exprType, false),
			types.NewField(token.NoPos, pkg, "Lparen", posType, false),
			types.NewField(token.NoPos, pkg, "Args", types.NewSlice(exprType), false),
			types.NewField(token.NoPos, pkg, "Ellipsis", posType, false),
			types.NewField(token.NoPos, pkg, "Rparen", posType, false),
		}, nil), nil)
	scope.Insert(callExprType.Obj())

	// type SelectorExpr struct { X Expr; Sel *Ident }
	selectorExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SelectorExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Sel", identPtr, false),
		}, nil), nil)
	scope.Insert(selectorExprType.Obj())

	// type IndexExpr struct { X Expr; Lbrack token.Pos; Index Expr; Rbrack token.Pos }
	indexExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "IndexExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Lbrack", posType, false),
			types.NewField(token.NoPos, pkg, "Index", exprType, false),
			types.NewField(token.NoPos, pkg, "Rbrack", posType, false),
		}, nil), nil)
	scope.Insert(indexExprType.Obj())

	// type IndexListExpr struct { X Expr; Lbrack token.Pos; Indices []Expr; Rbrack token.Pos }
	indexListExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "IndexListExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Lbrack", posType, false),
			types.NewField(token.NoPos, pkg, "Indices", types.NewSlice(exprType), false),
			types.NewField(token.NoPos, pkg, "Rbrack", posType, false),
		}, nil), nil)
	scope.Insert(indexListExprType.Obj())

	// type SliceExpr struct { X Expr; Lbrack token.Pos; Low, High, Max Expr; Slice3 bool; Rbrack token.Pos }
	sliceExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SliceExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Lbrack", posType, false),
			types.NewField(token.NoPos, pkg, "Low", exprType, false),
			types.NewField(token.NoPos, pkg, "High", exprType, false),
			types.NewField(token.NoPos, pkg, "Max", exprType, false),
			types.NewField(token.NoPos, pkg, "Slice3", types.Typ[types.Bool], false),
			types.NewField(token.NoPos, pkg, "Rbrack", posType, false),
		}, nil), nil)
	scope.Insert(sliceExprType.Obj())

	// type TypeAssertExpr struct { X Expr; Lparen token.Pos; Type Expr; Rparen token.Pos }
	typeAssertExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TypeAssertExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Lparen", posType, false),
			types.NewField(token.NoPos, pkg, "Type", exprType, false),
			types.NewField(token.NoPos, pkg, "Rparen", posType, false),
		}, nil), nil)
	scope.Insert(typeAssertExprType.Obj())

	// type ParenExpr struct { Lparen token.Pos; X Expr; Rparen token.Pos }
	parenExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ParenExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Lparen", posType, false),
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Rparen", posType, false),
		}, nil), nil)
	scope.Insert(parenExprType.Obj())

	// type FuncLit struct { Type *FuncType; Body *BlockStmt }
	funcLitType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FuncLit", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Type", types.NewPointer(funcTypeType), false),
			types.NewField(token.NoPos, pkg, "Body", types.NewPointer(blockStmtType), false),
		}, nil), nil)
	scope.Insert(funcLitType.Obj())

	// type CompositeLit struct { Type Expr; Lbrace token.Pos; Elts []Expr; Rbrace token.Pos; Incomplete bool }
	compositeLitType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CompositeLit", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Type", exprType, false),
			types.NewField(token.NoPos, pkg, "Lbrace", posType, false),
			types.NewField(token.NoPos, pkg, "Elts", types.NewSlice(exprType), false),
			types.NewField(token.NoPos, pkg, "Rbrace", posType, false),
			types.NewField(token.NoPos, pkg, "Incomplete", types.Typ[types.Bool], false),
		}, nil), nil)
	scope.Insert(compositeLitType.Obj())

	// type KeyValueExpr struct { Key Expr; Colon token.Pos; Value Expr }
	keyValueExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "KeyValueExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Key", exprType, false),
			types.NewField(token.NoPos, pkg, "Colon", posType, false),
			types.NewField(token.NoPos, pkg, "Value", exprType, false),
		}, nil), nil)
	scope.Insert(keyValueExprType.Obj())

	// --- Type expression node types ---

	// type ArrayType struct { Lbrack token.Pos; Len Expr; Elt Expr }
	arrayTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ArrayType", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Lbrack", posType, false),
			types.NewField(token.NoPos, pkg, "Len", exprType, false),
			types.NewField(token.NoPos, pkg, "Elt", exprType, false),
		}, nil), nil)
	scope.Insert(arrayTypeType.Obj())

	// type StructType struct { Struct token.Pos; Fields *FieldList; Incomplete bool }
	structTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "StructType", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Struct", posType, false),
			types.NewField(token.NoPos, pkg, "Fields", fieldListPtr, false),
			types.NewField(token.NoPos, pkg, "Incomplete", types.Typ[types.Bool], false),
		}, nil), nil)
	scope.Insert(structTypeType.Obj())

	// type InterfaceType struct { Interface token.Pos; Methods *FieldList; Incomplete bool }
	interfaceTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "InterfaceType", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Interface", posType, false),
			types.NewField(token.NoPos, pkg, "Methods", fieldListPtr, false),
			types.NewField(token.NoPos, pkg, "Incomplete", types.Typ[types.Bool], false),
		}, nil), nil)
	scope.Insert(interfaceTypeType.Obj())

	// type MapType struct { Map token.Pos; Key Expr; Value Expr }
	mapTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "MapType", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Map", posType, false),
			types.NewField(token.NoPos, pkg, "Key", exprType, false),
			types.NewField(token.NoPos, pkg, "Value", exprType, false),
		}, nil), nil)
	scope.Insert(mapTypeType.Obj())

	// type ChanDir int; const SEND, RECV, SEND|RECV
	chanDirType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ChanDir", nil), types.Typ[types.Int], nil)
	scope.Insert(chanDirType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "SEND", chanDirType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RECV", chanDirType, constant.MakeInt64(2)))

	// type ChanType struct { Begin token.Pos; Arrow token.Pos; Dir ChanDir; Value Expr }
	chanTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ChanType", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Begin", posType, false),
			types.NewField(token.NoPos, pkg, "Arrow", posType, false),
			types.NewField(token.NoPos, pkg, "Dir", chanDirType, false),
			types.NewField(token.NoPos, pkg, "Value", exprType, false),
		}, nil), nil)
	scope.Insert(chanTypeType.Obj())

	// --- Statement node types ---

	// type BadStmt struct { From, To token.Pos }
	badStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BadStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "From", posType, false),
			types.NewField(token.NoPos, pkg, "To", posType, false),
		}, nil), nil)
	scope.Insert(badStmtType.Obj())

	// type EmptyStmt struct { Semicolon token.Pos; Implicit bool }
	emptyStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "EmptyStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Semicolon", posType, false),
			types.NewField(token.NoPos, pkg, "Implicit", types.Typ[types.Bool], false),
		}, nil), nil)
	scope.Insert(emptyStmtType.Obj())

	// type ExprStmt struct { X Expr }
	exprStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ExprStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
		}, nil), nil)
	scope.Insert(exprStmtType.Obj())

	// type SendStmt struct { Chan Expr; Arrow token.Pos; Value Expr }
	sendStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SendStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Chan", exprType, false),
			types.NewField(token.NoPos, pkg, "Arrow", posType, false),
			types.NewField(token.NoPos, pkg, "Value", exprType, false),
		}, nil), nil)
	scope.Insert(sendStmtType.Obj())

	// type IncDecStmt struct { X Expr; TokPos token.Pos; Tok token.Token }
	incDecStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "IncDecStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "TokPos", posType, false),
			types.NewField(token.NoPos, pkg, "Tok", tokenIntType, false),
		}, nil), nil)
	scope.Insert(incDecStmtType.Obj())

	// type AssignStmt struct { Lhs []Expr; TokPos token.Pos; Tok token.Token; Rhs []Expr }
	assignStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "AssignStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Lhs", types.NewSlice(exprType), false),
			types.NewField(token.NoPos, pkg, "TokPos", posType, false),
			types.NewField(token.NoPos, pkg, "Tok", tokenIntType, false),
			types.NewField(token.NoPos, pkg, "Rhs", types.NewSlice(exprType), false),
		}, nil), nil)
	scope.Insert(assignStmtType.Obj())

	// type GoStmt struct { Go token.Pos; Call *CallExpr }
	goStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "GoStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Go", posType, false),
			types.NewField(token.NoPos, pkg, "Call", types.NewPointer(callExprType), false),
		}, nil), nil)
	scope.Insert(goStmtType.Obj())

	// type DeferStmt struct { Defer token.Pos; Call *CallExpr }
	deferStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "DeferStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Defer", posType, false),
			types.NewField(token.NoPos, pkg, "Call", types.NewPointer(callExprType), false),
		}, nil), nil)
	scope.Insert(deferStmtType.Obj())

	// type ReturnStmt struct { Return token.Pos; Results []Expr }
	returnStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ReturnStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Return", posType, false),
			types.NewField(token.NoPos, pkg, "Results", types.NewSlice(exprType), false),
		}, nil), nil)
	scope.Insert(returnStmtType.Obj())

	// type BranchStmt struct { TokPos token.Pos; Tok token.Token; Label *Ident }
	branchStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BranchStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "TokPos", posType, false),
			types.NewField(token.NoPos, pkg, "Tok", tokenIntType, false),
			types.NewField(token.NoPos, pkg, "Label", identPtr, false),
		}, nil), nil)
	scope.Insert(branchStmtType.Obj())

	blockStmtPtr := types.NewPointer(blockStmtType)

	// type IfStmt struct { If token.Pos; Init Stmt; Cond Expr; Body *BlockStmt; Else Stmt }
	ifStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "IfStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "If", posType, false),
			types.NewField(token.NoPos, pkg, "Init", stmtType, false),
			types.NewField(token.NoPos, pkg, "Cond", exprType, false),
			types.NewField(token.NoPos, pkg, "Body", blockStmtPtr, false),
			types.NewField(token.NoPos, pkg, "Else", stmtType, false),
		}, nil), nil)
	scope.Insert(ifStmtType.Obj())

	// type CaseClause struct { Case token.Pos; List []Expr; Colon token.Pos; Body []Stmt }
	caseClauseType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CaseClause", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Case", posType, false),
			types.NewField(token.NoPos, pkg, "List", types.NewSlice(exprType), false),
			types.NewField(token.NoPos, pkg, "Colon", posType, false),
			types.NewField(token.NoPos, pkg, "Body", types.NewSlice(stmtType), false),
		}, nil), nil)
	scope.Insert(caseClauseType.Obj())

	// type SwitchStmt struct { Switch token.Pos; Init Stmt; Tag Expr; Body *BlockStmt }
	switchStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SwitchStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Switch", posType, false),
			types.NewField(token.NoPos, pkg, "Init", stmtType, false),
			types.NewField(token.NoPos, pkg, "Tag", exprType, false),
			types.NewField(token.NoPos, pkg, "Body", blockStmtPtr, false),
		}, nil), nil)
	scope.Insert(switchStmtType.Obj())

	// type TypeSwitchStmt struct { Switch token.Pos; Init Stmt; Assign Stmt; Body *BlockStmt }
	typeSwitchStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TypeSwitchStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Switch", posType, false),
			types.NewField(token.NoPos, pkg, "Init", stmtType, false),
			types.NewField(token.NoPos, pkg, "Assign", stmtType, false),
			types.NewField(token.NoPos, pkg, "Body", blockStmtPtr, false),
		}, nil), nil)
	scope.Insert(typeSwitchStmtType.Obj())

	// type CommClause struct { Case token.Pos; Comm Stmt; Colon token.Pos; Body []Stmt }
	commClauseType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CommClause", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Case", posType, false),
			types.NewField(token.NoPos, pkg, "Comm", stmtType, false),
			types.NewField(token.NoPos, pkg, "Colon", posType, false),
			types.NewField(token.NoPos, pkg, "Body", types.NewSlice(stmtType), false),
		}, nil), nil)
	scope.Insert(commClauseType.Obj())

	// type SelectStmt struct { Select token.Pos; Body *BlockStmt }
	selectStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SelectStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Select", posType, false),
			types.NewField(token.NoPos, pkg, "Body", blockStmtPtr, false),
		}, nil), nil)
	scope.Insert(selectStmtType.Obj())

	// type ForStmt struct { For token.Pos; Init Stmt; Cond Expr; Post Stmt; Body *BlockStmt }
	forStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ForStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "For", posType, false),
			types.NewField(token.NoPos, pkg, "Init", stmtType, false),
			types.NewField(token.NoPos, pkg, "Cond", exprType, false),
			types.NewField(token.NoPos, pkg, "Post", stmtType, false),
			types.NewField(token.NoPos, pkg, "Body", blockStmtPtr, false),
		}, nil), nil)
	scope.Insert(forStmtType.Obj())

	// type RangeStmt struct { For token.Pos; Key, Value Expr; TokPos token.Pos; Tok token.Token; X Expr; Body *BlockStmt }
	rangeStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "RangeStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "For", posType, false),
			types.NewField(token.NoPos, pkg, "Key", exprType, false),
			types.NewField(token.NoPos, pkg, "Value", exprType, false),
			types.NewField(token.NoPos, pkg, "TokPos", posType, false),
			types.NewField(token.NoPos, pkg, "Tok", tokenIntType, false),
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Body", blockStmtPtr, false),
		}, nil), nil)
	scope.Insert(rangeStmtType.Obj())

	// type LabeledStmt struct { Label *Ident; Colon token.Pos; Stmt Stmt }
	labeledStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "LabeledStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Label", identPtr, false),
			types.NewField(token.NoPos, pkg, "Colon", posType, false),
			types.NewField(token.NoPos, pkg, "Stmt", stmtType, false),
		}, nil), nil)
	scope.Insert(labeledStmtType.Obj())

	// type DeclStmt struct { Decl Decl }
	declStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "DeclStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Decl", declType, false),
		}, nil), nil)
	scope.Insert(declStmtType.Obj())

	// --- Declaration/Spec node types ---

	// type BadDecl struct { From, To token.Pos }
	badDeclType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BadDecl", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "From", posType, false),
			types.NewField(token.NoPos, pkg, "To", posType, false),
		}, nil), nil)
	scope.Insert(badDeclType.Obj())

	// type ValueSpec struct { Doc *CommentGroup; Names []*Ident; Type Expr; Values []Expr; Comment *CommentGroup }
	valueSpecType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ValueSpec", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Doc", commentGroupPtr, false),
			types.NewField(token.NoPos, pkg, "Names", types.NewSlice(identPtr), false),
			types.NewField(token.NoPos, pkg, "Type", exprType, false),
			types.NewField(token.NoPos, pkg, "Values", types.NewSlice(exprType), false),
			types.NewField(token.NoPos, pkg, "Comment", commentGroupPtr, false),
		}, nil), nil)
	scope.Insert(valueSpecType.Obj())

	// type TypeSpec struct { Doc *CommentGroup; Name *Ident; TypeParams *FieldList; Assign token.Pos; Type Expr; Comment *CommentGroup }
	typeSpecType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TypeSpec", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Doc", commentGroupPtr, false),
			types.NewField(token.NoPos, pkg, "Name", identPtr, false),
			types.NewField(token.NoPos, pkg, "TypeParams", fieldListPtr, false),
			types.NewField(token.NoPos, pkg, "Assign", posType, false),
			types.NewField(token.NoPos, pkg, "Type", exprType, false),
			types.NewField(token.NoPos, pkg, "Comment", commentGroupPtr, false),
		}, nil), nil)
	scope.Insert(typeSpecType.Obj())

	// --- Additional utility functions ---

	// func FilterDecl(decl Decl, f Filter) bool
	// type Filter = func(string) bool
	filterType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FilterDecl",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "decl", declType),
				types.NewVar(token.NoPos, nil, "f", filterType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "FilterFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "src", types.NewPointer(fileType)),
				types.NewVar(token.NoPos, nil, "f", filterType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "FilterPackage",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pkg", types.NewPointer(packageType)),
				types.NewVar(token.NoPos, nil, "f", filterType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func NotNilFilter(_ string, v reflect.Value) bool — exported as simple func
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NotNilFilter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "v", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func FileExports(src *File) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FileExports",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "src", types.NewPointer(fileType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func PackageExports(pkg *Package) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PackageExports",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pkg", types.NewPointer(packageType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func MergePackageFiles(pkg *Package, mode MergeMode) *File
	// type MergeMode uint
	mergeModeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "MergeMode", nil), types.Typ[types.Uint], nil)
	scope.Insert(mergeModeType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "FilterFuncDuplicates", mergeModeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FilterUnassociatedComments", mergeModeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FilterImportDuplicates", mergeModeType, constant.MakeInt64(4)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "MergePackageFiles",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pkg", types.NewPointer(packageType)),
				types.NewVar(token.NoPos, nil, "mode", mergeModeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(fileType))), false)))

	// Suppress unused variable warnings
	_ = badExprType
	_ = ellipsisType
	_ = unaryExprType
	_ = binaryExprType
	_ = starExprType
	_ = callExprType
	_ = selectorExprType
	_ = indexExprType
	_ = indexListExprType
	_ = sliceExprType
	_ = typeAssertExprType
	_ = parenExprType
	_ = funcLitType
	_ = compositeLitType
	_ = keyValueExprType
	_ = arrayTypeType
	_ = structTypeType
	_ = interfaceTypeType
	_ = mapTypeType
	_ = chanTypeType
	_ = badStmtType
	_ = emptyStmtType
	_ = exprStmtType
	_ = sendStmtType
	_ = incDecStmtType
	_ = assignStmtType
	_ = goStmtType
	_ = deferStmtType
	_ = returnStmtType
	_ = branchStmtType
	_ = ifStmtType
	_ = caseClauseType
	_ = switchStmtType
	_ = typeSwitchStmtType
	_ = commClauseType
	_ = selectStmtType
	_ = forStmtType
	_ = rangeStmtType
	_ = labeledStmtType
	_ = declStmtType
	_ = badDeclType
	_ = valueSpecType
	_ = typeSpecType

	// func SortImports(fset *token.FileSet, f *File)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SortImports",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fset", fsetPtr),
				types.NewVar(token.NoPos, nil, "f", types.NewPointer(fileType))),
			nil, false)))

	// func Unparen(e Expr) Expr
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unparen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "e", exprType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", exprType)), false)))

	// func IsGenerated(file *File) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsGenerated",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "file", types.NewPointer(fileType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// type Filter func(string) bool
	astFilterTypeName := types.NewTypeName(token.NoPos, pkg, "Filter", nil)
	astFilterNamed := types.NewNamed(astFilterTypeName, filterType, nil)
	_ = astFilterNamed
	scope.Insert(astFilterTypeName)

	// type CommentMap map[Node][]*CommentGroup
	commentMapType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CommentMap", nil),
		types.NewMap(nodeType, types.NewSlice(types.NewPointer(commentGroupType))), nil)
	scope.Insert(commentMapType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildGoTokenPackage() *types.Package {
	pkg := types.NewPackage("go/token", "token")
	scope := pkg.Scope()

	// type Token int
	tokenType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Token", nil),
		types.Typ[types.Int], nil)
	scope.Insert(tokenType.Obj())
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "tok", tokenType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsLiteral",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "tok", tokenType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsOperator",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "tok", tokenType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsKeyword",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "tok", tokenType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "Precedence",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "tok", tokenType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// Token constants
	for i, name := range []string{
		"ILLEGAL", "EOF", "COMMENT",
		"IDENT", "INT", "FLOAT", "IMAG", "CHAR", "STRING",
		"ADD", "SUB", "MUL", "QUO", "REM",
		"AND", "OR", "XOR", "SHL", "SHR", "AND_NOT",
		"ADD_ASSIGN", "SUB_ASSIGN", "MUL_ASSIGN", "QUO_ASSIGN", "REM_ASSIGN",
		"LAND", "LOR", "ARROW", "INC", "DEC",
		"EQL", "LSS", "GTR", "ASSIGN", "NOT",
		"NEQ", "LEQ", "GEQ", "DEFINE", "ELLIPSIS",
		"LPAREN", "LBRACK", "LBRACE", "COMMA", "PERIOD",
		"RPAREN", "RBRACK", "RBRACE", "SEMICOLON", "COLON",
		"BREAK", "CASE", "CHAN", "CONST", "CONTINUE",
		"DEFAULT", "DEFER", "ELSE", "FALLTHROUGH", "FOR",
		"FUNC", "GO", "GOTO", "IF", "IMPORT",
		"INTERFACE", "MAP", "PACKAGE", "RANGE", "RETURN",
		"SELECT", "STRUCT", "SWITCH", "TYPE", "VAR",
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, name, tokenType, constant.MakeInt64(int64(i))))
	}

	// func Lookup(ident string) Token
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ident", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tokenType)), false)))

	// type Pos int
	posType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Pos", nil),
		types.Typ[types.Int], nil)
	scope.Insert(posType.Obj())
	posType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", posType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NoPos", posType, constant.MakeInt64(0)))

	// type Position struct
	positionStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Filename", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Column", types.Typ[types.Int], false),
	}, nil)
	positionType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Position", nil),
		positionStruct, nil)
	scope.Insert(positionType.Obj())
	positionType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "pos", positionType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	positionType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "pos", positionType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type File struct (opaque)
	fileType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "File", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(fileType.Obj())
	filePtr := types.NewPointer(fileType)
	fileRecv := types.NewVar(token.NoPos, nil, "f", filePtr)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Base",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "LineCount",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pos",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Offset",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", posType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Position",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", posType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", positionType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Line",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", posType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddLine",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int])),
			nil, false)))

	// type FileSet struct (opaque)
	fsetType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FileSet", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(fsetType.Obj())
	fsetPtr := types.NewPointer(fsetType)
	fsetRecv := types.NewVar(token.NoPos, nil, "s", fsetPtr)

	// func NewFileSet() *FileSet
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFileSet",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", fsetPtr)),
			false)))

	// FileSet methods
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddFile",
		types.NewSignatureType(fsetRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "filename", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "base", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "size", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", filePtr)), false)))
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Position",
		types.NewSignatureType(fsetRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", posType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", positionType)), false)))
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "File",
		types.NewSignatureType(fsetRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", posType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", filePtr)), false)))
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Base",
		types.NewSignatureType(fsetRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// FileSet.Iterate(f func(*File) bool)
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Iterate",
		types.NewSignatureType(fsetRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", filePtr)),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false))),
			nil, false)))

	// File.SetLines(lines []int) bool
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetLines",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "lines", types.NewSlice(types.Typ[types.Int]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// File.SetLinesForContent(content []byte)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetLinesForContent",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "content", types.NewSlice(types.Typ[types.Byte]))),
			nil, false)))

	// File.MergeLine(line int)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "MergeLine",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "line", types.Typ[types.Int])),
			nil, false)))

	// File.LineStart(line int) Pos
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "LineStart",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "line", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)))

	// File.PositionFor(p Pos, adjusted bool) Position
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "PositionFor",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", posType),
				types.NewVar(token.NoPos, nil, "adjusted", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", positionType)), false)))

	// FileSet.PositionFor(p Pos, adjusted bool) Position
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "PositionFor",
		types.NewSignatureType(fsetRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", posType),
				types.NewVar(token.NoPos, nil, "adjusted", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", positionType)), false)))

	// File.AddLineColumnInfo(offset, line, column int)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddLineColumnInfo",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "filename", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "line", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "column", types.Typ[types.Int])),
			nil, false)))

	// Precedence constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "LowestPrec", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "UnaryPrec", types.Typ[types.Int], constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "HighestPrec", types.Typ[types.Int], constant.MakeInt64(7)))

	// func IsKeyword(name string) bool (package-level)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsKeyword",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func IsExported(name string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsExported",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func IsIdentifier(name string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsIdentifier",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// FileSet.Read and FileSet.Write for serialization
	readFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "decode",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())), false))),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())), false)
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read", types.NewSignatureType(fsetRecv, nil, nil,
		readFn.Params(), readFn.Results(), false)))
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write", types.NewSignatureType(fsetRecv, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "encode",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())), false))),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())), false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoParserPackage() *types.Package {
	pkg := types.NewPackage("go/parser", "parser")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anyType := types.Universe.Lookup("any").Type()

	// type Mode uint
	modeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Mode", nil), types.Typ[types.Uint], nil)
	scope.Insert(modeType.Obj())

	// Mode constants
	for i, name := range []string{"PackageClauseOnly", "ImportsOnly", "ParseComments",
		"Trace", "DeclarationErrors", "SpuriousErrors", "SkipObjectResolution", "AllErrors"} {
		val := int64(1 << i)
		if name == "AllErrors" {
			val = 1 << 5 // same as SpuriousErrors
		}
		scope.Insert(types.NewConst(token.NoPos, pkg, name, modeType, constant.MakeInt64(val)))
	}

	// Opaque fset and file types (cross-package references simplified)
	fsetType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "fset", nil), types.NewStruct(nil, nil), nil)
	fileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "file", nil), types.NewStruct(nil, nil), nil)

	// func ParseFile(fset *token.FileSet, filename string, src any, mode Mode) (*ast.File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fset", types.NewPointer(fsetType)),
				types.NewVar(token.NoPos, pkg, "filename", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "src", anyType),
				types.NewVar(token.NoPos, pkg, "mode", modeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(fileType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// *ast.Package opaque pointer for ParseDir return
	astPkgPtr := types.NewPointer(types.NewStruct(nil, nil))

	// ast.Expr stand-in interface (has Pos/End methods like all ast.Node types)
	astExprIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
		types.NewFunc(token.NoPos, nil, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	astExprIface.Complete()

	// filter is func(fs.FileInfo) bool — fs.FileInfo has Name/Size/Mode/ModTime/IsDir/Sys
	filterFuncType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "info", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, nil, "Name",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
			types.NewFunc(token.NoPos, nil, "IsDir",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		}, nil))),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
		false)

	// func ParseDir(fset *token.FileSet, path string, filter func(fs.FileInfo) bool, mode Mode) (map[string]*ast.Package, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fset", types.NewPointer(fsetType)),
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "filter", filterFuncType),
				types.NewVar(token.NoPos, pkg, "mode", modeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewMap(types.Typ[types.String], astPkgPtr)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseExprFrom(fset *token.FileSet, filename string, src any, mode Mode) (ast.Expr, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseExprFrom",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fset", types.NewPointer(fsetType)),
				types.NewVar(token.NoPos, pkg, "filename", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "src", anyType),
				types.NewVar(token.NoPos, pkg, "mode", modeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", astExprIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseExpr(x string) (ast.Expr, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseExpr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", astExprIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoFormatPackage() *types.Package {
	pkg := types.NewPackage("go/format", "format")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Writer interface for Node dst
	ioWriterFmt := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterFmt.Complete()

	// func Source(src []byte) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Source",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "src", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Node(dst io.Writer, fset *token.FileSet, node interface{}) error
	fsetPtrFmt := types.NewPointer(types.NewStruct(nil, nil)) // *token.FileSet stand-in
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Node",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", ioWriterFmt),
				types.NewVar(token.NoPos, pkg, "fset", fsetPtrFmt),
				types.NewVar(token.NoPos, pkg, "node", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildNetHTTPCookiejarPackage() *types.Package {
	pkg := types.NewPackage("net/http/cookiejar", "cookiejar")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// PublicSuffixList interface
	pslIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "PublicSuffix",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "domain", types.Typ[types.String])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
	}, nil)
	pslIface.Complete()
	pslType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PublicSuffixList", nil),
		pslIface, nil)
	scope.Insert(pslType.Obj())

	// type Options struct { PublicSuffixList PublicSuffixList }
	optionsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "PublicSuffixList", pslType, false),
	}, nil)
	optionsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Options", nil),
		optionsStruct, nil)
	scope.Insert(optionsType.Obj())

	// *url.URL (opaque)
	urlStruct := types.NewStruct(nil, nil)
	urlPtr := types.NewPointer(urlStruct)

	// *http.Cookie (opaque)
	cookieStruct := types.NewStruct(nil, nil)
	cookiePtr := types.NewPointer(cookieStruct)

	// type Jar struct {}
	jarStruct := types.NewStruct(nil, nil)
	jarType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Jar", nil),
		jarStruct, nil)
	scope.Insert(jarType.Obj())
	jarPtr := types.NewPointer(jarType)

	jarRecv := types.NewVar(token.NoPos, nil, "j", jarPtr)
	// func (j *Jar) Cookies(u *url.URL) []*http.Cookie
	jarType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cookies",
		types.NewSignatureType(jarRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "u", urlPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(cookiePtr))),
			false)))

	// func (j *Jar) SetCookies(u *url.URL, cookies []*http.Cookie)
	jarType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetCookies",
		types.NewSignatureType(jarRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "u", urlPtr),
				types.NewVar(token.NoPos, nil, "cookies", types.NewSlice(cookiePtr))),
			nil, false)))

	// func New(o *Options) (*Jar, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "o", types.NewPointer(optionsType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", jarPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildNetHTTPPprofPackage() *types.Package {
	pkg := types.NewPackage("net/http/pprof", "pprof")
	scope := pkg.Scope()

	// http.ResponseWriter interface { Header() Header; Write([]byte) (int, error); WriteHeader(statusCode int) }
	errTypePprof := types.Universe.Lookup("error").Type()
	headerMapType := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))
	responseWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerMapType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errTypePprof)),
				false)),
		types.NewFunc(token.NoPos, nil, "WriteHeader",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "statusCode", types.Typ[types.Int])),
				nil, false)),
	}, nil)
	responseWriter.Complete()
	// *http.Request (simplified as pointer to empty struct)
	requestStruct := types.NewStruct(nil, nil)
	requestPtr := types.NewPointer(requestStruct)

	// func Index(w http.ResponseWriter, r *http.Request)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriter),
				types.NewVar(token.NoPos, pkg, "r", requestPtr)),
			nil, false)))

	// func Cmdline(w http.ResponseWriter, r *http.Request)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Cmdline",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriter),
				types.NewVar(token.NoPos, pkg, "r", requestPtr)),
			nil, false)))

	// func Profile(w http.ResponseWriter, r *http.Request)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Profile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriter),
				types.NewVar(token.NoPos, pkg, "r", requestPtr)),
			nil, false)))

	// func Symbol(w http.ResponseWriter, r *http.Request)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Symbol",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriter),
				types.NewVar(token.NoPos, pkg, "r", requestPtr)),
			nil, false)))

	// func Trace(w http.ResponseWriter, r *http.Request)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Trace",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriter),
				types.NewVar(token.NoPos, pkg, "r", requestPtr)),
			nil, false)))

	// func Handler(name string) http.Handler
	// http.Handler: interface with ServeHTTP(ResponseWriter, *Request)
	httpHandlerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ServeHTTP",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "w", responseWriter),
					types.NewVar(token.NoPos, nil, "r", requestPtr)),
				nil, false)),
	}, nil)
	httpHandlerIface.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Handler",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", httpHandlerIface)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildOsUserPackage() *types.Package {
	pkg := types.NewPackage("os/user", "user")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	userStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Uid", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Gid", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Username", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "HomeDir", types.Typ[types.String], false),
	}, nil)
	userType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "User", nil),
		userStruct, nil)
	scope.Insert(userType.Obj())
	userPtr := types.NewPointer(userType)

	// func Current() (*User, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Current",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", userPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Lookup(username string) (*User, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "username", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", userPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func LookupId(uid string) (*User, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupId",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "uid", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", userPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// User.GroupIds() ([]string, error)
	userType.AddMethod(types.NewFunc(token.NoPos, pkg, "GroupIds",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "u", userPtr),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type Group struct
	groupStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Gid", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
	}, nil)
	groupType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Group", nil),
		groupStruct, nil)
	scope.Insert(groupType.Obj())
	groupPtr := types.NewPointer(groupType)

	// func LookupGroup(name string) (*Group, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupGroup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", groupPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func LookupGroupId(gid string) (*Group, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupGroupId",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "gid", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", groupPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type UnknownUserError string
	unknownUserType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnknownUserError", nil),
		types.Typ[types.String], nil)
	unknownUserType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownUserType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unknownUserType.Obj())

	// type UnknownUserIdError int
	unknownUserIdType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnknownUserIdError", nil),
		types.Typ[types.Int], nil)
	unknownUserIdType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownUserIdType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unknownUserIdType.Obj())

	// type UnknownGroupError string
	unknownGroupType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnknownGroupError", nil),
		types.Typ[types.String], nil)
	unknownGroupType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownGroupType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unknownGroupType.Obj())

	// type UnknownGroupIdError string
	unknownGroupIdType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnknownGroupIdError", nil),
		types.Typ[types.String], nil)
	unknownGroupIdType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownGroupIdType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unknownGroupIdType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildRegexpSyntaxPackage() *types.Package {
	pkg := types.NewPackage("regexp/syntax", "syntax")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Flags uint16
	flagsType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Flags", nil), types.Typ[types.Uint16], nil)
	scope.Insert(flagsType.Obj())
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"FoldCase", 1}, {"Literal", 2}, {"ClassNL", 4}, {"DotNL", 8},
		{"OneLine", 16}, {"NonGreedy", 32}, {"PerlX", 64}, {"UnicodeGroups", 128},
		{"WasDollar", 256}, {"Simple", 512},
		{"MatchNL", 4 | 8}, {"Perl", 0xD2}, {"POSIX", 0},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, flagsType, constant.MakeInt64(c.val)))
	}

	// type Op uint8
	opType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Op", nil), types.Typ[types.Uint8], nil)
	scope.Insert(opType.Obj())
	opType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "i", opType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	for i, name := range []string{
		"OpNoMatch", "OpEmptyMatch", "OpLiteral", "OpCharClass", "OpAnyCharNotNL",
		"OpAnyChar", "OpBeginLine", "OpEndLine", "OpBeginText", "OpEndText",
		"OpWordBoundary", "OpNoWordBoundary", "OpCapture", "OpStar", "OpPlus",
		"OpQuest", "OpRepeat", "OpConcat", "OpAlternate",
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, name, opType, constant.MakeInt64(int64(i+1))))
	}

	// type Regexp struct
	regexpType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Regexp", nil), types.NewStruct(nil, nil), nil)
	regexpStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Op", opType, false),
		types.NewField(token.NoPos, pkg, "Flags", flagsType, false),
		types.NewField(token.NoPos, pkg, "Sub", types.NewSlice(types.NewPointer(regexpType)), false),
		types.NewField(token.NoPos, pkg, "Rune", types.NewSlice(types.Typ[types.Rune]), false),
		types.NewField(token.NoPos, pkg, "Min", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Max", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Cap", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
	}, nil)
	regexpType.SetUnderlying(regexpStruct)
	scope.Insert(regexpType.Obj())
	regexpPtr := types.NewPointer(regexpType)
	regexpRecv := types.NewVar(token.NoPos, nil, "re", regexpPtr)
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "x", regexpPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "y", regexpPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "Simplify",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", regexpPtr)), false)))
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "MaxCap",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "CapNames",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String]))), false)))

	// type Inst struct
	instOpType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "InstOp", nil), types.Typ[types.Uint8], nil)
	scope.Insert(instOpType.Obj())
	instStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Op", instOpType, false),
		types.NewField(token.NoPos, pkg, "Out", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Arg", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Rune", types.NewSlice(types.Typ[types.Rune]), false),
	}, nil)
	instType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Inst", nil), instStruct, nil)
	scope.Insert(instType.Obj())
	instType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "i", types.NewPointer(instType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Prog struct
	progStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Inst", types.NewSlice(instType), false),
		types.NewField(token.NoPos, pkg, "Start", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "NumCap", types.Typ[types.Int], false),
	}, nil)
	progType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Prog", nil), progStruct, nil)
	scope.Insert(progType.Obj())
	progPtr := types.NewPointer(progType)
	progType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", progPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type EmptyOp uint8
	emptyOpType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "EmptyOp", nil), types.Typ[types.Uint8], nil)
	scope.Insert(emptyOpType.Obj())
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"EmptyBeginLine", 1}, {"EmptyEndLine", 2}, {"EmptyBeginText", 4},
		{"EmptyEndText", 8}, {"EmptyWordBoundary", 16}, {"EmptyNoWordBoundary", 32},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, emptyOpType, constant.MakeInt64(c.val)))
	}

	// type Error struct { Code ErrorCode; Expr string }
	errorCodeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ErrorCode", nil), types.Typ[types.String], nil)
	scope.Insert(errorCodeType.Obj())
	for _, name := range []string{
		"ErrInternalError", "ErrInvalidCharClass", "ErrInvalidCharRange",
		"ErrInvalidEscape", "ErrInvalidNamedCapture", "ErrInvalidPerlOp",
		"ErrInvalidRepeatOp", "ErrInvalidRepeatSize", "ErrInvalidUTF8",
		"ErrMissingBracket", "ErrMissingParen", "ErrMissingRepeatArgument",
		"ErrNestingDepth", "ErrUnexpectedParen",
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, name, errorCodeType, constant.MakeString(name)))
	}

	syntaxErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Code", errorCodeType, false),
		types.NewField(token.NoPos, pkg, "Expr", types.Typ[types.String], false),
	}, nil)
	syntaxErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Error", nil), syntaxErrStruct, nil)
	syntaxErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(syntaxErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(syntaxErrType.Obj())

	// func Parse(s string, flags Flags) (*Regexp, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "flags", flagsType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", regexpPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Compile(re *Regexp) (*Prog, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "re", regexpPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", progPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func IsWordChar(r rune) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsWordChar",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func EmptyOpContext(r1, r2 rune) EmptyOp
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EmptyOpContext",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r1", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, pkg, "r2", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", emptyOpType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildRuntimeDebugPackage() *types.Package {
	pkg := types.NewPackage("runtime/debug", "debug")
	scope := pkg.Scope()

	// Module type — use forward declaration for self-referential Replace *Module field
	moduleType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Module", nil),
		types.NewStruct(nil, nil), nil) // placeholder
	moduleStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Sum", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Replace", types.NewPointer(moduleType), false),
	}, nil)
	moduleType.SetUnderlying(moduleStruct)
	scope.Insert(moduleType.Obj())

	// BuildSetting type
	buildSettingStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Key", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.String], false),
	}, nil)
	buildSettingType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "BuildSetting", nil),
		buildSettingStruct, nil)
	scope.Insert(buildSettingType.Obj())

	// BuildInfo type
	buildInfoStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "GoVersion", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Main", moduleType, false),
		types.NewField(token.NoPos, pkg, "Deps", types.NewSlice(types.NewPointer(moduleType)), false),
		types.NewField(token.NoPos, pkg, "Settings", types.NewSlice(buildSettingType), false),
	}, nil)
	buildInfoType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "BuildInfo", nil),
		buildInfoStruct, nil)
	scope.Insert(buildInfoType.Obj())
	buildInfoPtr := types.NewPointer(buildInfoType)

	// BuildInfo.String() method
	buildInfoType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "bi", buildInfoPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Stack() []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Stack",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func PrintStack()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PrintStack",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func FreeOSMemory()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FreeOSMemory",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func SetGCPercent(percent int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetGCPercent",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "percent", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func SetMaxStack(bytes int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetMaxStack",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "bytes", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func SetMaxThreads(threads int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetMaxThreads",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "threads", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func SetPanicOnFault(enabled bool) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetPanicOnFault",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "enabled", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func SetTraceback(level string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetTraceback",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "level", types.Typ[types.String])),
			nil, false)))

	// func ReadBuildInfo() (*BuildInfo, bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadBuildInfo",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", buildInfoPtr),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// GCStats type
	// time.Duration is int64, time.Time is int64 stand-in
	gcStatsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "LastGC", types.Typ[types.Int64], false),    // time.Time
		types.NewField(token.NoPos, pkg, "NumGC", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "PauseTotal", types.Typ[types.Int64], false), // time.Duration
		types.NewField(token.NoPos, pkg, "Pause", types.NewSlice(types.Typ[types.Int64]), false), // []time.Duration
		types.NewField(token.NoPos, pkg, "PauseEnd", types.NewSlice(types.Typ[types.Int64]), false), // []time.Time
		types.NewField(token.NoPos, pkg, "PauseQuantiles", types.NewSlice(types.Typ[types.Int64]), false), // []time.Duration
	}, nil)
	gcStatsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "GCStats", nil),
		gcStatsStruct, nil)
	scope.Insert(gcStatsType.Obj())

	// func ReadGCStats(stats *GCStats)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadGCStats",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "stats", types.NewPointer(gcStatsType))),
			nil, false)))

	// func ParseBuildInfo(data string) (bi *BuildInfo, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseBuildInfo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", buildInfoPtr),
				types.NewVar(token.NoPos, pkg, "", types.Universe.Lookup("error").Type())),
			false)))

	// func SetMemoryLimit(limit int64) int64 — Go 1.19+
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetMemoryLimit",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "limit", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))

	// func WriteHeapDump(fd uintptr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteHeapDump",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Uintptr])),
			nil, false)))

	// func SetCrashOutput(f *os.File, opts CrashOptions) error — Go 1.23+
	// Simplified with opaque *os.File stand-in
	errType := types.Universe.Lookup("error").Type()
	osFileStandin := types.NewPointer(types.NewStruct(nil, nil))
	crashOptsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CrashOptions", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(crashOptsType.Obj())
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetCrashOutput",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "f", osFileStandin),
				types.NewVar(token.NoPos, pkg, "opts", crashOptsType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildRuntimePprofPackage() *types.Package {
	pkg := types.NewPackage("runtime/pprof", "pprof")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlicePP := types.NewSlice(types.Typ[types.Byte])

	// io.Writer interface for WriteTo, StartCPUProfile, WriteHeapProfile
	ioWriterPP := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlicePP)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterPP.Complete()

	anyType := types.NewInterfaceType(nil, nil)
	anyType.Complete()

	// Profile type
	profileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	profileType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Profile", nil),
		profileStruct, nil)
	scope.Insert(profileType.Obj())
	profilePtr := types.NewPointer(profileType)

	// Profile.Name() string
	profileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "p", profilePtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Profile.Count() int
	profileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Count",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "p", profilePtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// Profile.Add(value any, skip int)
	profileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "p", profilePtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "value", anyType),
				types.NewVar(token.NoPos, pkg, "skip", types.Typ[types.Int])),
			nil, false)))

	// Profile.Remove(value any)
	profileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Remove",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "p", profilePtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "value", anyType)),
			nil, false)))

	// Profile.WriteTo(w io.Writer, debug int) error
	profileType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteTo",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "p", profilePtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriterPP),
				types.NewVar(token.NoPos, pkg, "debug", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Lookup(name string) *Profile
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", profilePtr)),
			false)))

	// func NewProfile(name string) *Profile
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewProfile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", profilePtr)),
			false)))

	// func Profiles() []*Profile
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Profiles",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(profilePtr))),
			false)))

	// func StartCPUProfile(w io.Writer) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StartCPUProfile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterPP)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func StopCPUProfile()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StopCPUProfile",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func WriteHeapProfile(w io.Writer) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteHeapProfile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterPP)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// context.Context stand-in for label functions
	ctxIfacePP := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Deadline",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Done",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewChan(types.RecvOnly, types.NewStruct(nil, nil)))), false)),
		types.NewFunc(token.NoPos, nil, "Err",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Value",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyType)), false)),
	}, nil)
	ctxIfacePP.Complete()

	// type LabelSet struct{}
	labelSetType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "LabelSet", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(labelSetType.Obj())

	// func SetGoroutineLabels(ctx context.Context)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetGoroutineLabels",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ctx", ctxIfacePP)),
			nil, false)))

	// func Labels(args ...string) LabelSet
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Labels",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", labelSetType)),
			true))) // variadic

	// func Label(ctx context.Context, key string) (string, bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Label",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIfacePP),
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func ForLabels(ctx context.Context, fn func(key, value string) bool)
	forLabelsFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
			types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ForLabels",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIfacePP),
				types.NewVar(token.NoPos, pkg, "fn", forLabelsFn)),
			nil, false)))

	// func WithLabels(ctx context.Context, labels LabelSet) context.Context
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithLabels",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIfacePP),
				types.NewVar(token.NoPos, pkg, "labels", labelSetType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ctxIfacePP)),
			false)))

	// func Do(ctx context.Context, labels LabelSet, f func(context.Context))
	doFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", ctxIfacePP)),
		nil, false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Do",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIfacePP),
				types.NewVar(token.NoPos, pkg, "labels", labelSetType),
				types.NewVar(token.NoPos, pkg, "f", doFn)),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildTextScannerPackage() *types.Package {
	pkg := types.NewPackage("text/scanner", "scanner")
	scope := pkg.Scope()

	// Position type
	posStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Filename", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Column", types.Typ[types.Int], false),
	}, nil)
	posType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Position", nil),
		posStruct, nil)
	scope.Insert(posType.Obj())

	// Position.IsValid() bool
	posType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "pos", types.NewPointer(posType)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// Position.String() string
	posType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "pos", posType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func(s *Scanner, msg string) type for Error field — use forward ref via scannerPtr
	// We need scannerPtr for the function type, but Scanner hasn't been declared yet.
	// Use a *struct{} stand-in for the Error callback's *Scanner param.
	scannerStandIn := types.NewPointer(types.NewStruct(nil, nil))
	errorFuncType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "s", scannerStandIn),
			types.NewVar(token.NoPos, nil, "msg", types.Typ[types.String])),
		nil, false)

	// func(ch rune, i int) bool type for IsIdentRune field
	isIdentRuneType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "ch", types.Typ[types.Int32]),
			types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
		false)

	// Scanner type
	scannerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Mode", types.Typ[types.Uint], false),
		types.NewField(token.NoPos, pkg, "Whitespace", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Position", posType, true), // embedded
		types.NewField(token.NoPos, pkg, "IsIdentRune", isIdentRuneType, false),
		types.NewField(token.NoPos, pkg, "Error", errorFuncType, false),
		types.NewField(token.NoPos, pkg, "ErrorCount", types.Typ[types.Int], false),
	}, nil)
	scannerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Scanner", nil),
		scannerStruct, nil)
	scope.Insert(scannerType.Obj())
	scannerPtr := types.NewPointer(scannerType)

	// io.Reader stand-in for Init
	errType := types.Universe.Lookup("error").Type()
	ioReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderIface.Complete()

	// Scanner.Init(src io.Reader) *Scanner
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "s", scannerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "src", ioReaderIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", scannerPtr)),
			false)))

	// Scanner.Scan() rune
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Scan",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "s", scannerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))

	// Scanner.Peek() rune
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Peek",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "s", scannerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))

	// Scanner.Next() rune
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "s", scannerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))

	// Scanner.TokenText() string
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "TokenText",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "s", scannerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Scanner.Pos() Position
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pos",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "s", scannerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", posType)),
			false)))

	// func TokenString(tok rune) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TokenString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "tok", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "EOF", types.Typ[types.Int32], constant.MakeInt64(-1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Ident", types.Typ[types.Int32], constant.MakeInt64(-2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Int", types.Typ[types.Int32], constant.MakeInt64(-3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Float", types.Typ[types.Int32], constant.MakeInt64(-4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Char", types.Typ[types.Int32], constant.MakeInt64(-5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "String", types.Typ[types.Int32], constant.MakeInt64(-6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RawString", types.Typ[types.Int32], constant.MakeInt64(-7)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Comment", types.Typ[types.Int32], constant.MakeInt64(-8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanIdents", types.Typ[types.Uint], constant.MakeUint64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanInts", types.Typ[types.Uint], constant.MakeUint64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanFloats", types.Typ[types.Uint], constant.MakeUint64(16)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanChars", types.Typ[types.Uint], constant.MakeUint64(32)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanStrings", types.Typ[types.Uint], constant.MakeUint64(64)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanRawStrings", types.Typ[types.Uint], constant.MakeUint64(128)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanComments", types.Typ[types.Uint], constant.MakeUint64(256)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SkipComments", types.Typ[types.Uint], constant.MakeUint64(512)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "GoTokens", types.Typ[types.Uint], constant.MakeUint64(1012)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "GoWhitespace", types.Typ[types.Uint64], constant.MakeUint64(1<<'\t'|1<<'\n'|1<<'\r'|1<<' ')))

	pkg.MarkComplete()
	return pkg
}

func buildTextTabwriterPackage() *types.Package {
	pkg := types.NewPackage("text/tabwriter", "tabwriter")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSliceTW := types.NewSlice(types.Typ[types.Byte])

	// io.Writer interface for output parameter
	ioWriterTW := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceTW)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterTW.Complete()

	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())
	writerPtr := types.NewPointer(writerType)

	// func NewWriter(output io.Writer, minwidth, tabwidth, padding int, padchar byte, flags uint) *Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "output", ioWriterTW),
				types.NewVar(token.NoPos, pkg, "minwidth", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "tabwidth", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "padding", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "padchar", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "flags", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", writerPtr)),
			false)))

	// Writer.Init(output io.Writer, minwidth, tabwidth, padding int, padchar byte, flags uint) *Writer
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "w", writerPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "output", ioWriterTW),
				types.NewVar(token.NoPos, pkg, "minwidth", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "tabwidth", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "padding", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "padchar", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "flags", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", writerPtr)),
			false)))

	// Writer.Write(buf []byte) (n int, err error)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "w", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Writer.Flush() error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "w", writerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Constants for flags
	scope.Insert(types.NewConst(token.NoPos, pkg, "FilterHTML", types.Typ[types.Uint], constant.MakeUint64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StripEscape", types.Typ[types.Uint], constant.MakeUint64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AlignRight", types.Typ[types.Uint], constant.MakeUint64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DiscardEmptyColumns", types.Typ[types.Uint], constant.MakeUint64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TabIndent", types.Typ[types.Uint], constant.MakeUint64(16)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Debug", types.Typ[types.Uint], constant.MakeUint64(32)))

	// Escape constant
	scope.Insert(types.NewConst(token.NoPos, pkg, "Escape", types.Typ[types.Byte], constant.MakeInt64(0xff)))

	pkg.MarkComplete()
	return pkg
}
