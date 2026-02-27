// Package type stubs for encoding packages: encoding, encoding/hex,
// encoding/base64, encoding/base32, encoding/json, encoding/binary,
// encoding/csv, encoding/xml, encoding/pem, encoding/gob, encoding/ascii85,
// encoding/asn1.
package compiler

import (
	"go/constant"
	"go/token"
	"go/types"
)

func init() {
	RegisterPackage("encoding/ascii85", buildEncodingASCII85Package)
	RegisterPackage("encoding/asn1", buildEncodingASN1Package)
	RegisterPackage("encoding/base32", buildEncodingBase32Package)
	RegisterPackage("encoding/base64", buildEncodingBase64Package)
	RegisterPackage("encoding/binary", buildEncodingBinaryPackage)
	RegisterPackage("encoding/csv", buildEncodingCSVPackage)
	RegisterPackage("encoding/gob", buildEncodingGobPackage)
	RegisterPackage("encoding/hex", buildEncodingHexPackage)
	RegisterPackage("encoding/json", buildEncodingJSONPackage)
	RegisterPackage("encoding/json/jsontext", buildEncodingJSONTextPackage)
	RegisterPackage("encoding/json/v2", buildEncodingJSONV2Package)
	RegisterPackage("encoding/pem", buildEncodingPEMPackage)
	RegisterPackage("encoding", buildEncodingPackage)
	RegisterPackage("encoding/xml", buildEncodingXMLPackage)
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

func buildEncodingASN1Package() *types.Package {
	pkg := types.NewPackage("encoding/asn1", "asn1")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	anyType := types.NewInterfaceType(nil, nil)

	// func Marshal(val any) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Marshal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "val", anyType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Unmarshal(b []byte, val any) (rest []byte, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unmarshal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", byteSlice),
				types.NewVar(token.NoPos, pkg, "val", anyType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rest", byteSlice),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func MarshalWithParams(val any, params string) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MarshalWithParams",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "val", anyType),
				types.NewVar(token.NoPos, pkg, "params", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func UnmarshalWithParams(b []byte, val any, params string) (rest []byte, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UnmarshalWithParams",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", byteSlice),
				types.NewVar(token.NoPos, pkg, "val", anyType),
				types.NewVar(token.NoPos, pkg, "params", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rest", byteSlice),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// type ObjectIdentifier []int
	oidType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ObjectIdentifier", nil),
		types.NewSlice(types.Typ[types.Int]), nil)
	scope.Insert(oidType.Obj())

	// type RawContent []byte
	rawContentType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RawContent", nil),
		byteSlice, nil)
	scope.Insert(rawContentType.Obj())

	// type RawValue struct { ... }
	rawValueStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Class", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Tag", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "IsCompound", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Bytes", byteSlice, false),
		types.NewField(token.NoPos, pkg, "FullBytes", byteSlice, false),
	}, nil)
	rawValueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RawValue", nil),
		rawValueStruct, nil)
	scope.Insert(rawValueType.Obj())

	// type BitString struct { ... }
	bitStringStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Bytes", byteSlice, false),
		types.NewField(token.NoPos, pkg, "BitLength", types.Typ[types.Int], false),
	}, nil)
	bitStringType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "BitString", nil),
		bitStringStruct, nil)
	scope.Insert(bitStringType.Obj())

	// BitString methods
	// func (b BitString) At(i int) int
	bitStringType.AddMethod(types.NewFunc(token.NoPos, pkg, "At",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "b", bitStringType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	// func (b BitString) RightAlign() []byte
	bitStringType.AddMethod(types.NewFunc(token.NoPos, pkg, "RightAlign",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "b", bitStringType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))

	// ObjectIdentifier methods
	// func (oi ObjectIdentifier) Equal(other ObjectIdentifier) bool
	oidType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "oi", oidType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "other", oidType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	// func (oi ObjectIdentifier) String() string
	oidType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "oi", oidType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// type Flag struct { ... }
	flagStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	flagType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Flag", nil),
		flagStruct, nil)
	scope.Insert(flagType.Obj())

	// type Enumerated int
	enumType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Enumerated", nil),
		types.Typ[types.Int], nil)
	scope.Insert(enumType.Obj())

	// type SyntaxError struct { Msg string }
	syntaxErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Msg", types.Typ[types.String], false),
	}, nil)
	syntaxErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SyntaxError", nil),
		syntaxErrStruct, nil)
	syntaxErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", syntaxErrType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(syntaxErrType.Obj())

	// type StructuralError struct { Msg string }
	structuralErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Msg", types.Typ[types.String], false),
	}, nil)
	structuralErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "StructuralError", nil),
		structuralErrStruct, nil)
	structuralErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", structuralErrType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(structuralErrType.Obj())

	// Tag constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagBoolean", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagInteger", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagBitString", types.Typ[types.Int], constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagOctetString", types.Typ[types.Int], constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagNULL", types.Typ[types.Int], constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagOID", types.Typ[types.Int], constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagEnum", types.Typ[types.Int], constant.MakeInt64(10)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagUTF8String", types.Typ[types.Int], constant.MakeInt64(12)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagSequence", types.Typ[types.Int], constant.MakeInt64(16)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagSet", types.Typ[types.Int], constant.MakeInt64(17)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagPrintableString", types.Typ[types.Int], constant.MakeInt64(19)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagIA5String", types.Typ[types.Int], constant.MakeInt64(22)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagUTCTime", types.Typ[types.Int], constant.MakeInt64(23)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagGeneralizedTime", types.Typ[types.Int], constant.MakeInt64(24)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TagBMPString", types.Typ[types.Int], constant.MakeInt64(30)))

	// Class constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "ClassUniversal", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ClassApplication", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ClassContextSpecific", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ClassPrivate", types.Typ[types.Int], constant.MakeInt64(3)))

	// var NullRawValue, NullBytes
	scope.Insert(types.NewVar(token.NoPos, pkg, "NullRawValue", rawValueType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "NullBytes", byteSlice))

	pkg.MarkComplete()
	return pkg
}

func buildEncodingBase32Package() *types.Package {
	pkg := types.NewPackage("encoding/base32", "base32")
	scope := pkg.Scope()

	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type Encoding struct { ... }
	encStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	encType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Encoding", nil),
		encStruct, nil)
	scope.Insert(encType.Obj())
	encPtr := types.NewPointer(encType)

	// var StdEncoding, HexEncoding *Encoding
	scope.Insert(types.NewVar(token.NoPos, pkg, "StdEncoding", encPtr))
	scope.Insert(types.NewVar(token.NoPos, pkg, "HexEncoding", encPtr))

	// func NewEncoding(encoder string) *Encoding
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewEncoding",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "encoder", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", encPtr)),
			false)))

	// Methods on *Encoding
	errType := types.Universe.Lookup("error").Type()
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "EncodeToString",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "src", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "DecodeString",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", byteSlice),
				types.NewVar(token.NoPos, nil, "src", byteSlice)),
			nil, false)))
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", byteSlice),
				types.NewVar(token.NoPos, nil, "src", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "EncodedLen",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "DecodedLen",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "WithPadding",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "padding", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", encType)),
			false)))

	// Encoding.AppendEncode(dst, src []byte) []byte
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "AppendEncode",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", byteSlice),
				types.NewVar(token.NoPos, nil, "src", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))

	// Encoding.AppendDecode(dst, src []byte) ([]byte, error)
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "AppendDecode",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", byteSlice),
				types.NewVar(token.NoPos, nil, "src", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Encoding.Strict() *Encoding
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "Strict",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", encPtr)),
			false)))

	// type CorruptInputError int64
	corruptInputType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CorruptInputError", nil),
		types.Typ[types.Int64], nil)
	corruptInputType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "e", corruptInputType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(corruptInputType.Obj())

	// io.Writer stand-in for NewEncoder
	ioWriterBase32 := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterBase32.Complete()

	// io.Reader stand-in for NewDecoder
	ioReaderBase32 := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderBase32.Complete()

	// io.WriteCloser stand-in
	ioWriteCloserBase32 := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioWriteCloserBase32.Complete()

	// func NewEncoder(enc *Encoding, w io.Writer) io.WriteCloser
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewEncoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "enc", encPtr),
				types.NewVar(token.NoPos, pkg, "w", ioWriterBase32)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioWriteCloserBase32)),
			false)))

	// func NewDecoder(enc *Encoding, r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewDecoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "enc", encPtr),
				types.NewVar(token.NoPos, pkg, "r", ioReaderBase32)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReaderBase32)),
			false)))

	// const NoPadding rune = -1
	scope.Insert(types.NewConst(token.NoPos, pkg, "NoPadding", types.Typ[types.Rune], constant.MakeInt64(-1)))
	// const StdPadding rune = '='
	scope.Insert(types.NewConst(token.NoPos, pkg, "StdPadding", types.Typ[types.Rune], constant.MakeInt64('=')))

	// var RawStdEncoding, RawHexEncoding *Encoding
	scope.Insert(types.NewVar(token.NoPos, pkg, "RawStdEncoding", encPtr))
	scope.Insert(types.NewVar(token.NoPos, pkg, "RawHexEncoding", encPtr))

	pkg.MarkComplete()
	return pkg
}

func buildEncodingBase64Package() *types.Package {
	pkg := types.NewPackage("encoding/base64", "base64")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Encoding struct{ ... } (opaque)
	encStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "alphabet", types.Typ[types.String], false),
	}, nil)
	encType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Encoding", nil),
		encStruct, nil)
	scope.Insert(encType.Obj())
	encPtr := types.NewPointer(encType)

	// Methods
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "EncodeToString",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "src", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "DecodeString",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "EncodedLen",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "DecodedLen",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "enc", encPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Encode/Decode raw methods
	encRecv := types.NewVar(token.NoPos, nil, "enc", encPtr)
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(encRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "src", types.NewSlice(types.Typ[types.Byte]))),
			nil, false)))
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(encRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "src", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "Strict",
		types.NewSignatureType(encRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", encPtr)),
			false)))
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "WithPadding",
		types.NewSignatureType(encRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "padding", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", encPtr)),
			false)))

	// Encoding.AppendEncode(dst, src []byte) []byte
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "AppendEncode",
		types.NewSignatureType(encRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "src", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// Encoding.AppendDecode(dst, src []byte) ([]byte, error)
	encType.AddMethod(types.NewFunc(token.NoPos, pkg, "AppendDecode",
		types.NewSignatureType(encRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "src", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func NewEncoding(encoder string) *Encoding
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewEncoding",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "encoder", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", encPtr)),
			false)))

	// io interfaces for base64 functions
	b64ByteSlice := types.NewSlice(types.Typ[types.Byte])
	ioWriterType := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", b64ByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterType.Complete()

	ioWriteCloserType := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", b64ByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioWriteCloserType.Complete()

	ioReaderType := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", b64ByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderType.Complete()

	// func NewEncoder(enc *Encoding, w io.Writer) io.WriteCloser
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewEncoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "enc", encPtr),
				types.NewVar(token.NoPos, nil, "w", ioWriterType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ioWriteCloserType)),
			false)))
	// func NewDecoder(enc *Encoding, r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewDecoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "enc", encPtr),
				types.NewVar(token.NoPos, nil, "r", ioReaderType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ioReaderType)),
			false)))

	// NoPadding and StdPadding constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "NoPadding", types.Typ[types.Int32], constant.MakeInt64(-1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StdPadding", types.Typ[types.Int32], constant.MakeInt64(int64('='))))

	// CorruptInputError type
	corruptType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CorruptInputError", nil),
		types.Typ[types.Int64], nil)
	corruptType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", corruptType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(corruptType.Obj())

	// var StdEncoding *Encoding
	scope.Insert(types.NewVar(token.NoPos, pkg, "StdEncoding", encPtr))
	scope.Insert(types.NewVar(token.NoPos, pkg, "URLEncoding", encPtr))
	scope.Insert(types.NewVar(token.NoPos, pkg, "RawStdEncoding", encPtr))
	scope.Insert(types.NewVar(token.NoPos, pkg, "RawURLEncoding", encPtr))

	pkg.MarkComplete()
	return pkg
}

// buildEncodingBinaryPackage creates the type-checked encoding/binary package stub.
func buildEncodingBinaryPackage() *types.Package {
	pkg := types.NewPackage("encoding/binary", "binary")
	scope := pkg.Scope()

	// type ByteOrder interface { Uint16, Uint32, Uint64, PutUint16, PutUint32, PutUint64, String }
	byteSliceBin := types.NewSlice(types.Typ[types.Byte])
	byteOrderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Uint16",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceBin)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint16])), false)),
		types.NewFunc(token.NoPos, pkg, "Uint32",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceBin)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)),
		types.NewFunc(token.NoPos, pkg, "Uint64",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceBin)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)),
		types.NewFunc(token.NoPos, pkg, "PutUint16",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "b", byteSliceBin),
					types.NewVar(token.NoPos, nil, "v", types.Typ[types.Uint16])),
				nil, false)),
		types.NewFunc(token.NoPos, pkg, "PutUint32",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "b", byteSliceBin),
					types.NewVar(token.NoPos, nil, "v", types.Typ[types.Uint32])),
				nil, false)),
		types.NewFunc(token.NoPos, pkg, "PutUint64",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "b", byteSliceBin),
					types.NewVar(token.NoPos, nil, "v", types.Typ[types.Uint64])),
				nil, false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	byteOrderIface.Complete()
	byteOrderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ByteOrder", nil),
		byteOrderIface, nil)
	scope.Insert(byteOrderType.Obj())

	// var BigEndian, LittleEndian ByteOrder
	scope.Insert(types.NewVar(token.NoPos, pkg, "BigEndian", byteOrderType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "LittleEndian", byteOrderType))

	// io.Writer interface for binary.Write
	errType := types.Universe.Lookup("error").Type()
	writerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceBin)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	writerIface.Complete()

	// io.Reader interface for binary.Read
	readerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceBin)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerIface.Complete()

	anyType := types.NewInterfaceType(nil, nil)
	anyType.Complete()

	// func Write(w io.Writer, order ByteOrder, data any) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", writerIface),
				types.NewVar(token.NoPos, pkg, "order", byteOrderType),
				types.NewVar(token.NoPos, pkg, "data", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Read(r io.Reader, order ByteOrder, data any) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", readerIface),
				types.NewVar(token.NoPos, pkg, "order", byteOrderType),
				types.NewVar(token.NoPos, pkg, "data", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func PutUvarint(buf []byte, x uint64) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PutUvarint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Uvarint(buf []byte) (uint64, int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uvarint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func PutVarint(buf []byte, x int64) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PutVarint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Varint(buf []byte) (int64, int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Varint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Size(v any) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func AppendUvarint(buf []byte, x uint64) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendUvarint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func AppendVarint(buf []byte, x int64) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendVarint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// var NativeEndian ByteOrder
	scope.Insert(types.NewVar(token.NoPos, pkg, "NativeEndian", byteOrderType))

	// type AppendByteOrder interface (extends ByteOrder with AppendUint16/32/64)
	appendByteOrderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Uint16",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceBin)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint16])), false)),
		types.NewFunc(token.NoPos, pkg, "Uint32",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceBin)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)),
		types.NewFunc(token.NoPos, pkg, "Uint64",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceBin)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)),
		types.NewFunc(token.NoPos, pkg, "PutUint16",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "b", byteSliceBin),
					types.NewVar(token.NoPos, nil, "v", types.Typ[types.Uint16])),
				nil, false)),
		types.NewFunc(token.NoPos, pkg, "PutUint32",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "b", byteSliceBin),
					types.NewVar(token.NoPos, nil, "v", types.Typ[types.Uint32])),
				nil, false)),
		types.NewFunc(token.NoPos, pkg, "PutUint64",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "b", byteSliceBin),
					types.NewVar(token.NoPos, nil, "v", types.Typ[types.Uint64])),
				nil, false)),
		types.NewFunc(token.NoPos, pkg, "AppendUint16",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "b", byteSliceBin),
					types.NewVar(token.NoPos, nil, "v", types.Typ[types.Uint16])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSliceBin)), false)),
		types.NewFunc(token.NoPos, pkg, "AppendUint32",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "b", byteSliceBin),
					types.NewVar(token.NoPos, nil, "v", types.Typ[types.Uint32])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSliceBin)), false)),
		types.NewFunc(token.NoPos, pkg, "AppendUint64",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "b", byteSliceBin),
					types.NewVar(token.NoPos, nil, "v", types.Typ[types.Uint64])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSliceBin)), false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	appendByteOrderIface.Complete()
	appendByteOrderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "AppendByteOrder", nil),
		appendByteOrderIface, nil)
	scope.Insert(appendByteOrderType.Obj())

	// const MaxVarintLen16, MaxVarintLen32, MaxVarintLen64
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxVarintLen16", types.Typ[types.Int], constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxVarintLen32", types.Typ[types.Int], constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxVarintLen64", types.Typ[types.Int], constant.MakeInt64(10)))

	// io.ByteReader stand-in for ReadUvarint/ReadVarint
	byteReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadByte",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Byte]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	byteReaderIface.Complete()

	// func ReadUvarint(r io.ByteReader) (uint64, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadUvarint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", byteReaderIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ReadVarint(r io.ByteReader) (int64, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadVarint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", byteReaderIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Encode(buf []byte, order ByteOrder, data any) (int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "order", byteOrderType),
				types.NewVar(token.NoPos, pkg, "data", types.NewInterfaceType(nil, nil))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Decode(buf []byte, order ByteOrder, data any) (int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "order", byteOrderType),
				types.NewVar(token.NoPos, pkg, "data", types.NewInterfaceType(nil, nil))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Append(order ByteOrder, buf []byte, data any) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Append",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "order", byteOrderType),
				types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "data", types.NewInterfaceType(nil, nil))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildEncodingCSVPackage creates the type-checked encoding/csv package stub.
func buildEncodingCSVPackage() *types.Package {
	pkg := types.NewPackage("encoding/csv", "csv")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Reader struct { ... }
	readerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Comma", types.Typ[types.Int32], false),
		types.NewField(token.NoPos, pkg, "Comment", types.Typ[types.Int32], false),
		types.NewField(token.NoPos, pkg, "FieldsPerRecord", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "LazyQuotes", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "TrimLeadingSpace", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "ReuseRecord", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "TrailingComma", types.Typ[types.Bool], false),
	}, nil)
	readerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		readerStruct, nil)
	scope.Insert(readerType.Obj())
	readerPtr := types.NewPointer(readerType)

	// io interfaces for CSV
	csvByteSlice := types.NewSlice(types.Typ[types.Byte])
	ioReaderCSV := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", csvByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderCSV.Complete()
	ioWriterCSV := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", csvByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterCSV.Complete()

	// func NewReader(r io.Reader) *Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReaderCSV)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", readerPtr)),
			false)))

	// type Writer struct { ... }
	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Comma", types.Typ[types.Int32], false),
		types.NewField(token.NoPos, pkg, "UseCRLF", types.Typ[types.Bool], false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())
	writerPtr := types.NewPointer(writerType)

	// func NewWriter(w io.Writer) *Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterCSV)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", writerPtr)),
			false)))

	// Reader methods
	strSlice := types.NewSlice(types.Typ[types.String])
	// func (*Reader) Read() (record []string, err error)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil,
			nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "record", strSlice),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func (*Reader) ReadAll() (records [][]string, err error)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadAll",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil,
			nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "records", types.NewSlice(strSlice)),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func (*Reader) FieldPos(field int) (line, column int)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "FieldPos",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "field", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "line", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "column", types.Typ[types.Int])),
			false)))

	// func (*Reader) InputOffset() int64
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "InputOffset",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))

	// type ParseError
	parseErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "StartLine", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Column", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	parseErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ParseError", nil),
		parseErrStruct, nil)
	parseErrPtr := types.NewPointer(parseErrType)
	parseErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", parseErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	parseErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", parseErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	scope.Insert(parseErrType.Obj())

	// Writer methods
	// func (*Writer) Write(record []string) error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "record", strSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (*Writer) WriteAll(records [][]string) error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteAll",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "records", types.NewSlice(strSlice))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (*Writer) Flush()
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil, nil, nil, false)))

	// func (*Writer) Error() error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// var ErrFieldCount, ErrQuote, ErrBareQuote, ErrTrailingComma error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrFieldCount", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrQuote", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrBareQuote", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrTrailingComma", errType))

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

func buildEncodingHexPackage() *types.Package {
	pkg := types.NewPackage("encoding/hex", "hex")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// func EncodeToString(src []byte) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EncodeToString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "src", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func DecodeString(s string) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func EncodedLen(n int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EncodedLen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func DecodedLen(x int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodedLen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Encode(dst, src []byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "src", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Decode(dst, src []byte) (int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "src", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Dump(data []byte) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dump",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// io interfaces for hex functions
	hexByteSlice := types.NewSlice(types.Typ[types.Byte])
	ioWriterHex := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", hexByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterHex.Complete()

	ioReaderHex := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", hexByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderHex.Complete()

	ioWriteCloserHex := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", hexByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioWriteCloserHex.Complete()

	// func NewEncoder(w io.Writer) io.Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewEncoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterHex)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioWriterHex)),
			false)))

	// func NewDecoder(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewDecoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReaderHex)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReaderHex)),
			false)))

	// func Dumper(w io.Writer) io.WriteCloser
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dumper",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterHex)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioWriteCloserHex)),
			false)))

	// type InvalidByteError byte (satisfies error)
	invalidByteType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "InvalidByteError", nil),
		types.Typ[types.Byte], nil)
	invalidByteType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", invalidByteType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(invalidByteType.Obj())

	// var ErrLength error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrLength", errType))

	// func AppendEncode(dst, src []byte) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendEncode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "src", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func AppendDecode(dst, src []byte) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendDecode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "src", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildEncodingJSONPackage creates the type-checked encoding/json package stub.
func buildEncodingJSONPackage() *types.Package {
	pkg := types.NewPackage("encoding/json", "json")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anyType := types.NewInterfaceType(nil, nil)

	// func Marshal(v any) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Marshal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func MarshalIndent(v any, prefix, indent string) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MarshalIndent",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "v", anyType),
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "indent", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Unmarshal(data []byte, v any) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unmarshal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Valid(data []byte) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Valid",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// bytes.Buffer stand-in for Compact/Indent/HTMLEscape dst parameter
	bufferStruct := types.NewStruct(nil, nil)
	bufferType := types.NewNamed(
		types.NewTypeName(token.NoPos, nil, "Buffer", nil),
		bufferStruct, nil)
	bufferPtr := types.NewPointer(bufferType)
	bufRecv := types.NewVar(token.NoPos, nil, "b", bufferPtr)
	bufferType.AddMethod(types.NewFunc(token.NoPos, nil, "Write",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)), false)))
	bufferType.AddMethod(types.NewFunc(token.NoPos, nil, "WriteString",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)), false)))
	bufferType.AddMethod(types.NewFunc(token.NoPos, nil, "Bytes",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte]))), false)))
	bufferType.AddMethod(types.NewFunc(token.NoPos, nil, "String",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	bufferType.AddMethod(types.NewFunc(token.NoPos, nil, "Len",
		types.NewSignatureType(bufRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	bufferType.AddMethod(types.NewFunc(token.NoPos, nil, "Reset",
		types.NewSignatureType(bufRecv, nil, nil, nil, nil, false)))
	bufferType.AddMethod(types.NewFunc(token.NoPos, nil, "WriteByte",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "c", types.Typ[types.Byte])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	bufferType.AddMethod(types.NewFunc(token.NoPos, nil, "ReadFrom",
		types.NewSignatureType(bufRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", types.NewInterfaceType([]*types.Func{
				types.NewFunc(token.NoPos, nil, "Read",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
						types.NewTuple(
							types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
							types.NewVar(token.NoPos, nil, "err", errType)), false)),
			}, nil))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "err", errType)), false)))

	// func Compact(dst *bytes.Buffer, src []byte) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compact",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", bufferPtr),
				types.NewVar(token.NoPos, pkg, "src", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Indent(dst *bytes.Buffer, src []byte, prefix, indent string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Indent",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", bufferPtr),
				types.NewVar(token.NoPos, pkg, "src", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "indent", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func HTMLEscape(dst *bytes.Buffer, src []byte)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HTMLEscape",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", bufferPtr),
				types.NewVar(token.NoPos, pkg, "src", types.NewSlice(types.Typ[types.Byte]))),
			nil, false)))

	// io.Writer interface for NewEncoder
	ioWriterJSON := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterJSON.Complete()

	// io.Reader interface for NewDecoder
	ioReaderJSON := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderJSON.Complete()

	// type Encoder struct {}
	encoderStruct := types.NewStruct(nil, nil)
	encoderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Encoder", nil),
		encoderStruct, nil)
	scope.Insert(encoderType.Obj())
	encoderPtr := types.NewPointer(encoderType)

	// func NewEncoder(w io.Writer) *Encoder
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewEncoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterJSON)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", encoderPtr)),
			false)))

	// Encoder methods
	encRecv := types.NewVar(token.NoPos, nil, "enc", encoderPtr)
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(encRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetIndent",
		types.NewSignatureType(encRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "indent", types.Typ[types.String])),
			nil, false)))
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetEscapeHTML",
		types.NewSignatureType(encRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "on", types.Typ[types.Bool])),
			nil, false)))

	// type Decoder struct {}
	decoderStruct := types.NewStruct(nil, nil)
	decoderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Decoder", nil),
		decoderStruct, nil)
	scope.Insert(decoderType.Obj())
	decoderPtr := types.NewPointer(decoderType)

	// func NewDecoder(r io.Reader) *Decoder
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewDecoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReaderJSON)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", decoderPtr)),
			false)))

	// Decoder methods
	decRecv := types.NewVar(token.NoPos, nil, "dec", decoderPtr)
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(decRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "More",
		types.NewSignatureType(decRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "UseNumber",
		types.NewSignatureType(decRecv, nil, nil, nil, nil, false)))
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "DisallowUnknownFields",
		types.NewSignatureType(decRecv, nil, nil, nil, nil, false)))
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Token",
		types.NewSignatureType(decRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", anyType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Buffered",
		types.NewSignatureType(decRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReaderJSON)),
			false)))
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "InputOffset",
		types.NewSignatureType(decRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))

	// type Number string
	numberType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Number", nil),
		types.Typ[types.String], nil)
	scope.Insert(numberType.Obj())

	// type RawMessage []byte
	rawMsgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RawMessage", nil),
		types.NewSlice(types.Typ[types.Byte]), nil)
	scope.Insert(rawMsgType.Obj())

	// Marshaler interface: MarshalJSON() ([]byte, error)
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	marshalerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "MarshalJSON",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", byteSlice),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	marshalerIface.Complete()
	marshalerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Marshaler", nil),
		marshalerIface, nil)
	scope.Insert(marshalerType.Obj())

	// Unmarshaler interface: UnmarshalJSON([]byte) error
	unmarshalerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "UnmarshalJSON",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "data", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	unmarshalerIface.Complete()
	unmarshalerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Unmarshaler", nil),
		unmarshalerIface, nil)
	scope.Insert(unmarshalerType.Obj())

	// Number methods
	numberType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "n", numberType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	numberType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "n", numberType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	numberType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int64",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "n", numberType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// type Delim rune
	delimType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Delim", nil),
		types.Typ[types.Rune], nil)
	scope.Insert(delimType.Obj())

	// type Token interface{}
	tokenIface := types.NewInterfaceType(nil, nil)
	tokenIface.Complete()
	tokenType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Token", nil),
		tokenIface, nil)
	scope.Insert(tokenType.Obj())

	// type SyntaxError struct { Offset int64; msg string }
	syntaxErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Int64], false),
	}, nil)
	syntaxErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SyntaxError", nil),
		syntaxErrStruct, nil)
	scope.Insert(syntaxErrType.Obj())
	syntaxErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "e", types.NewPointer(syntaxErrType)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// type UnmarshalTypeError struct { Value string; Type reflect.Type; Offset int64; Struct string; Field string }
	unmarshalTypeErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Struct", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Field", types.Typ[types.String], false),
	}, nil)
	unmarshalTypeErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnmarshalTypeError", nil),
		unmarshalTypeErrStruct, nil)
	scope.Insert(unmarshalTypeErrType.Obj())
	unmarshalTypeErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "e", types.NewPointer(unmarshalTypeErrType)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// type InvalidUnmarshalError struct { Type reflect.Type }
	invalidUnmarshalErrStruct := types.NewStruct([]*types.Var{}, nil)
	invalidUnmarshalErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "InvalidUnmarshalError", nil),
		invalidUnmarshalErrStruct, nil)
	scope.Insert(invalidUnmarshalErrType.Obj())
	invalidUnmarshalErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "e", types.NewPointer(invalidUnmarshalErrType)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// type MarshalerError struct {}
	marshalerErrStruct := types.NewStruct([]*types.Var{}, nil)
	marshalerErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "MarshalerError", nil),
		marshalerErrStruct, nil)
	scope.Insert(marshalerErrType.Obj())
	marshalerErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "e", types.NewPointer(marshalerErrType)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	marshalerErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "e", types.NewPointer(marshalerErrType)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// type UnsupportedTypeError struct { Type reflect.Type }
	unsupportedTypeErrStruct := types.NewStruct([]*types.Var{}, nil)
	unsupportedTypeErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnsupportedTypeError", nil),
		unsupportedTypeErrStruct, nil)
	scope.Insert(unsupportedTypeErrType.Obj())
	unsupportedTypeErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "e", types.NewPointer(unsupportedTypeErrType)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// type UnsupportedValueError struct { Value reflect.Value; Str string }
	unsupportedValueErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Str", types.Typ[types.String], false),
	}, nil)
	unsupportedValueErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnsupportedValueError", nil),
		unsupportedValueErrStruct, nil)
	scope.Insert(unsupportedValueErrType.Obj())
	unsupportedValueErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "e", types.NewPointer(unsupportedValueErrType)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// RawMessage methods: MarshalJSON, UnmarshalJSON
	rawMsgType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalJSON",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "m", rawMsgType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	rawMsgType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalJSON",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "m", types.NewPointer(rawMsgType)),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// type InvalidUTF8Error (deprecated) with Error() string
	iue8Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "S", types.Typ[types.String], false),
	}, nil)
	iue8Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "InvalidUTF8Error", nil),
		iue8Struct, nil)
	iue8Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "", types.NewPointer(iue8Type)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(iue8Type.Obj())

	// type UnmarshalFieldError (deprecated) with Error() string
	ufeStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Key", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Type", types.NewInterfaceType(nil, nil), false),
		types.NewField(token.NoPos, pkg, "Field", types.NewInterfaceType(nil, nil), false),
	}, nil)
	ufeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnmarshalFieldError", nil),
		ufeStruct, nil)
	ufeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "", types.NewPointer(ufeType)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(ufeType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildEncodingJSONTextPackage() *types.Package {
	pkg := types.NewPackage("encoding/json/jsontext", "jsontext")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()

	// type Value []byte
	valueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Value", nil),
		byteSlice, nil)
	scope.Insert(valueType.Obj())

	valueRecv := types.NewVar(token.NoPos, pkg, "", valueType)

	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Indent",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "indent", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Compact",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Canonicalize",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type Kind int
	kindType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Kind", nil),
		types.Typ[types.Int], nil)
	scope.Insert(kindType.Obj())

	// type Token struct — opaque
	tokenStruct := types.NewStruct(nil, nil)
	tokenType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Token", nil),
		tokenStruct, nil)
	scope.Insert(tokenType.Obj())

	tokenRecv := types.NewVar(token.NoPos, pkg, "", tokenType)
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "Kind",
		types.NewSignatureType(tokenRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", kindType)),
			false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bool",
		types.NewSignatureType(tokenRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float",
		types.NewSignatureType(tokenRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(tokenRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint",
		types.NewSignatureType(tokenRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(tokenRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// type Encoder struct — opaque
	encoderStruct := types.NewStruct(nil, nil)
	encoderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Encoder", nil),
		encoderStruct, nil)
	scope.Insert(encoderType.Obj())
	encoderPtr := types.NewPointer(encoderType)
	encoderRecv := types.NewVar(token.NoPos, pkg, "", encoderPtr)

	// type Decoder struct — opaque
	decoderStruct := types.NewStruct(nil, nil)
	decoderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Decoder", nil),
		decoderStruct, nil)
	scope.Insert(decoderType.Obj())
	decoderPtr := types.NewPointer(decoderType)
	decoderRecv := types.NewVar(token.NoPos, pkg, "", decoderPtr)

	// Encoder methods
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteToken",
		types.NewSignatureType(encoderRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "t", tokenType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteValue",
		types.NewSignatureType(encoderRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "OutputOffset",
		types.NewSignatureType(encoderRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))

	// Decoder methods
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadToken",
		types.NewSignatureType(decoderRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tokenType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadValue",
		types.NewSignatureType(decoderRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", valueType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "InputOffset",
		types.NewSignatureType(decoderRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "PeekKind",
		types.NewSignatureType(decoderRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", kindType)),
			false)))

	// io.Writer/Reader stand-in
	writerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	writerIface.Complete()

	readerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerIface.Complete()

	// func NewEncoder(w io.Writer) *Encoder
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewEncoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", writerIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", encoderPtr)),
			false)))

	// func NewDecoder(r io.Reader) *Decoder
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewDecoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", decoderPtr)),
			false)))

	// Kind constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "InvalidKind", kindType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NullKind", kindType, constant.MakeInt64('n')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FalseKind", kindType, constant.MakeInt64('f')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TrueKind", kindType, constant.MakeInt64('t')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StringKind", kindType, constant.MakeInt64('"')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NumberKind", kindType, constant.MakeInt64('0')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ObjectStartKind", kindType, constant.MakeInt64('{')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ObjectEndKind", kindType, constant.MakeInt64('}')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ArrayStartKind", kindType, constant.MakeInt64('[')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ArrayEndKind", kindType, constant.MakeInt64(']')))

	pkg.MarkComplete()
	return pkg
}

func buildEncodingJSONV2Package() *types.Package {
	pkg := types.NewPackage("encoding/json/v2", "json")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()
	emptyIface := types.NewInterfaceType(nil, nil)
	emptyIface.Complete()

	// type Options struct — opaque
	optionsStruct := types.NewStruct(nil, nil)
	optionsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Options", nil),
		optionsStruct, nil)
	scope.Insert(optionsType.Obj())

	// func Marshal(in any, opts ...Options) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Marshal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "in", emptyIface),
				types.NewVar(token.NoPos, pkg, "opts", types.NewSlice(optionsType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func Unmarshal(in []byte, out any, opts ...Options) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unmarshal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "in", byteSlice),
				types.NewVar(token.NoPos, pkg, "out", emptyIface),
				types.NewVar(token.NoPos, pkg, "opts", types.NewSlice(optionsType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// io.Writer/Reader stand-in interfaces
	writerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	writerIface.Complete()

	readerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerIface.Complete()

	// func MarshalWrite(out io.Writer, in any, opts ...Options) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MarshalWrite",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "out", writerIface),
				types.NewVar(token.NoPos, pkg, "in", emptyIface),
				types.NewVar(token.NoPos, pkg, "opts", types.NewSlice(optionsType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func UnmarshalRead(in io.Reader, out any, opts ...Options) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UnmarshalRead",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "in", readerIface),
				types.NewVar(token.NoPos, pkg, "out", emptyIface),
				types.NewVar(token.NoPos, pkg, "opts", types.NewSlice(optionsType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	pkg.MarkComplete()
	return pkg
}

// buildEncodingPEMPackage creates the type-checked encoding/pem package stub.
func buildEncodingPEMPackage() *types.Package {
	pkg := types.NewPackage("encoding/pem", "pem")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Block struct
	blockStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Type", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Headers", types.NewMap(types.Typ[types.String], types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Bytes", types.NewSlice(types.Typ[types.Byte]), false),
	}, nil)
	blockType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Block", nil),
		blockStruct, nil)
	scope.Insert(blockType.Obj())
	blockPtr := types.NewPointer(blockType)

	// func Decode(data []byte) (p *Block, rest []byte)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", blockPtr),
				types.NewVar(token.NoPos, pkg, "rest", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func Encode(out io.Writer, b *Block) error
	pemByteSlice := types.NewSlice(types.Typ[types.Byte])
	ioWriterPEM := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", pemByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterPEM.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "out", ioWriterPEM),
				types.NewVar(token.NoPos, pkg, "b", blockPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func EncodeToMemory(b *Block) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EncodeToMemory",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", blockPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildEncodingPackage() *types.Package {
	pkg := types.NewPackage("encoding", "encoding")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	for _, name := range []string{"BinaryMarshaler", "TextMarshaler"} {
		method := "MarshalBinary"
		if name == "TextMarshaler" {
			method = "MarshalText"
		}
		iface := types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, method,
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)
		iface.Complete()
		t := types.NewNamed(types.NewTypeName(token.NoPos, pkg, name, nil), iface, nil)
		scope.Insert(t.Obj())
	}
	for _, name := range []string{"BinaryUnmarshaler", "TextUnmarshaler"} {
		method := "UnmarshalBinary"
		if name == "TextUnmarshaler" {
			method = "UnmarshalText"
		}
		iface := types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, method,
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "data", byteSlice)),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)
		iface.Complete()
		t := types.NewNamed(types.NewTypeName(token.NoPos, pkg, name, nil), iface, nil)
		scope.Insert(t.Obj())
	}
	pkg.MarkComplete()
	return pkg
}

// buildEncodingXMLPackage creates the type-checked encoding/xml package stub.
func buildEncodingXMLPackage() *types.Package {
	pkg := types.NewPackage("encoding/xml", "xml")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anyType := types.Universe.Lookup("any").Type()

	// func Marshal(v any) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Marshal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Unmarshal(data []byte, v any) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unmarshal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func MarshalIndent(v any, prefix, indent string) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MarshalIndent",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "v", anyType),
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "indent", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	scope.Insert(types.NewConst(token.NoPos, pkg, "Header", types.Typ[types.String],
		constant.MakeString("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")))

	// io.Writer interface for XML functions
	xmlByteSlice := types.NewSlice(types.Typ[types.Byte])
	ioWriterXML := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", xmlByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterXML.Complete()

	// io.Reader interface for XML functions
	ioReaderXML := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", xmlByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderXML.Complete()

	// func EscapeText(w io.Writer, data []byte) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EscapeText",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriterXML),
				types.NewVar(token.NoPos, pkg, "data", xmlByteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Escape(w io.Writer, data []byte)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Escape",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriterXML),
				types.NewVar(token.NoPos, pkg, "data", xmlByteSlice)),
			nil, false)))

	// func CopyToken(t Token) Token
	tokenType := types.NewInterfaceType(nil, nil)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CopyToken",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "t", tokenType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tokenType)),
			false)))

	// type Token interface{}
	tokenTypeName := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Token", nil),
		tokenType, nil)
	scope.Insert(tokenTypeName.Obj())

	// type Encoder struct {}
	encoderStruct := types.NewStruct(nil, nil)
	encoderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Encoder", nil),
		encoderStruct, nil)
	scope.Insert(encoderType.Obj())
	encoderPtr := types.NewPointer(encoderType)

	// func NewEncoder(w io.Writer) *Encoder
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewEncoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterXML)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", encoderPtr)),
			false)))

	// Encoder methods
	encRecv := types.NewVar(token.NoPos, nil, "enc", encoderPtr)
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(encRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "EncodeToken",
		types.NewSignatureType(encRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "t", tokenType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	// Forward-declare StartElement for EncodeElement; actual struct set below
	startElemTypeName := types.NewTypeName(token.NoPos, pkg, "StartElement", nil)
	startElemType := types.NewNamed(startElemTypeName, nil, nil)

	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "EncodeElement",
		types.NewSignatureType(encRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "v", anyType),
				types.NewVar(token.NoPos, pkg, "start", startElemType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(encRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Indent",
		types.NewSignatureType(encRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "indent", types.Typ[types.String])),
			nil, false)))

	// type Decoder struct { Strict bool; AutoClose []string; Entity map[string]string; CharsetReader func(...); DefaultSpace string }
	charsetReaderFnXML := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "charset", types.Typ[types.String]),
			types.NewVar(token.NoPos, nil, "input", ioReaderXML)),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", ioReaderXML),
			types.NewVar(token.NoPos, nil, "", errType)),
		false)
	decoderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Strict", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "AutoClose", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Entity", types.NewMap(types.Typ[types.String], types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "CharsetReader", charsetReaderFnXML, false),
		types.NewField(token.NoPos, pkg, "DefaultSpace", types.Typ[types.String], false),
	}, nil)
	decoderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Decoder", nil),
		decoderStruct, nil)
	scope.Insert(decoderType.Obj())
	decoderPtr := types.NewPointer(decoderType)

	// func NewDecoder(r io.Reader) *Decoder
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewDecoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReaderXML)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", decoderPtr)),
			false)))

	// Decoder methods
	decRecv := types.NewVar(token.NoPos, nil, "d", decoderPtr)
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(decRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "DecodeElement",
		types.NewSignatureType(decRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "v", anyType),
				types.NewVar(token.NoPos, pkg, "start", types.NewPointer(startElemType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Token",
		types.NewSignatureType(decRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tokenType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Skip",
		types.NewSignatureType(decRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Common XML types
	// type Name struct { Space, Local string }
	nameStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Space", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Local", types.Typ[types.String], false),
	}, nil)
	nameType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Name", nil),
		nameStruct, nil)
	scope.Insert(nameType.Obj())

	// type Attr struct { Name Name; Value string }
	attrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", nameType, false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.String], false),
	}, nil)
	attrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Attr", nil),
		attrStruct, nil)
	scope.Insert(attrType.Obj())

	// Set StartElement underlying struct (forward-declared above for EncodeElement)
	startElemStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", nameType, false),
		types.NewField(token.NoPos, pkg, "Attr", types.NewSlice(attrType), false),
	}, nil)
	startElemType.SetUnderlying(startElemStruct)
	scope.Insert(startElemType.Obj())

	// type EndElement struct { Name Name }
	endElemStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", nameType, false),
	}, nil)
	endElemType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "EndElement", nil),
		endElemStruct, nil)
	scope.Insert(endElemType.Obj())

	// type CharData []byte
	charDataType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CharData", nil),
		types.NewSlice(types.Typ[types.Byte]), nil)
	scope.Insert(charDataType.Obj())

	// type Comment []byte
	commentType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Comment", nil),
		types.NewSlice(types.Typ[types.Byte]), nil)
	scope.Insert(commentType.Obj())

	// type ProcInst struct { Target string; Inst []byte }
	procInstStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Target", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Inst", types.NewSlice(types.Typ[types.Byte]), false),
	}, nil)
	procInstType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ProcInst", nil),
		procInstStruct, nil)
	scope.Insert(procInstType.Obj())

	// type Directive []byte
	directiveType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Directive", nil),
		types.NewSlice(types.Typ[types.Byte]), nil)
	scope.Insert(directiveType.Obj())

	// Marshaler interface: MarshalXML(e *Encoder, start StartElement) error
	marshalerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "MarshalXML",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "e", encoderPtr),
					types.NewVar(token.NoPos, nil, "start", startElemType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	marshalerIface.Complete()
	marshalerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Marshaler", nil),
		marshalerIface, nil)
	scope.Insert(marshalerType.Obj())

	// Unmarshaler interface: UnmarshalXML(d *Decoder, start StartElement) error
	unmarshalerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "UnmarshalXML",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "d", decoderPtr),
					types.NewVar(token.NoPos, nil, "start", startElemType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	unmarshalerIface.Complete()
	unmarshalerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Unmarshaler", nil),
		unmarshalerIface, nil)
	scope.Insert(unmarshalerType.Obj())

	// StartElement methods
	startElemType.AddMethod(types.NewFunc(token.NoPos, pkg, "Copy",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", startElemType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", startElemType)),
			false)))
	startElemType.AddMethod(types.NewFunc(token.NoPos, pkg, "End",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", startElemType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", endElemType)),
			false)))

	// CharData.Copy, Comment.Copy
	charDataType.AddMethod(types.NewFunc(token.NoPos, pkg, "Copy",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", charDataType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", charDataType)),
			false)))
	commentType.AddMethod(types.NewFunc(token.NoPos, pkg, "Copy",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", commentType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", commentType)),
			false)))
	procInstType.AddMethod(types.NewFunc(token.NoPos, pkg, "Copy",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", procInstType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", procInstType)),
			false)))
	directiveType.AddMethod(types.NewFunc(token.NoPos, pkg, "Copy",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "d", directiveType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", directiveType)),
			false)))

	// Decoder.RawToken
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "RawToken",
		types.NewSignatureType(decRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", tokenType),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Decoder.InputOffset
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "InputOffset",
		types.NewSignatureType(decRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))

	// Error types
	// type SyntaxError struct { Msg string; Line int }
	syntaxErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Msg", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
	}, nil)
	syntaxErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SyntaxError", nil),
		syntaxErrStruct, nil)
	syntaxErrPtr := types.NewPointer(syntaxErrType)
	syntaxErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", syntaxErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(syntaxErrType.Obj())

	// type TagPathError struct { Struct reflect.Type; ... }
	tagPathErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Field1", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Tag1", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Field2", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Tag2", types.Typ[types.String], false),
	}, nil)
	tagPathErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "TagPathError", nil),
		tagPathErrStruct, nil)
	tagPathErrPtr := types.NewPointer(tagPathErrType)
	tagPathErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", tagPathErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(tagPathErrType.Obj())

	// reflect.Type stand-in (minimal interface)
	reflectTypeIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, nil, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, nil, "Kind",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	reflectTypeIface.Complete()

	// type UnsupportedTypeError struct { Type reflect.Type }
	unsupTypeErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Type", reflectTypeIface, false),
	}, nil)
	unsupTypeErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnsupportedTypeError", nil),
		unsupTypeErrStruct, nil)
	unsupTypeErrPtr := types.NewPointer(unsupTypeErrType)
	unsupTypeErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unsupTypeErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unsupTypeErrType.Obj())

	// type TokenReader interface { Token() (Token, error) }
	tokenReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Token",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", tokenType),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	tokenReaderIface.Complete()
	tokenReaderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "TokenReader", nil),
		tokenReaderIface, nil)
	scope.Insert(tokenReaderType.Obj())

	// func NewTokenDecoder(t TokenReader) *Decoder
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTokenDecoder",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "t", tokenReaderIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", decoderPtr)),
			false)))

	// MarshalerAttr interface: MarshalXMLAttr(name Name) (Attr, error)
	marshalerAttrIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "MarshalXMLAttr",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", nameType)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", attrType),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	marshalerAttrIface.Complete()
	marshalerAttrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "MarshalerAttr", nil),
		marshalerAttrIface, nil)
	scope.Insert(marshalerAttrType.Obj())

	// UnmarshalerAttr interface: UnmarshalXMLAttr(attr Attr) error
	unmarshalerAttrIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "UnmarshalXMLAttr",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "attr", attrType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	unmarshalerAttrIface.Complete()
	unmarshalerAttrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnmarshalerAttr", nil),
		unmarshalerAttrIface, nil)
	scope.Insert(unmarshalerAttrType.Obj())

	// Encoder.Close() error
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(encRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Decoder.InputPos() (line, column int)
	decoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "InputPos",
		types.NewSignatureType(decRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "line", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "column", types.Typ[types.Int])),
			false)))

	// var HTMLAutoClose []string
	scope.Insert(types.NewVar(token.NoPos, pkg, "HTMLAutoClose",
		types.NewSlice(types.Typ[types.String])))

	// var HTMLEntity map[string]string
	scope.Insert(types.NewVar(token.NoPos, pkg, "HTMLEntity",
		types.NewMap(types.Typ[types.String], types.Typ[types.String])))

	pkg.MarkComplete()
	return pkg
}
