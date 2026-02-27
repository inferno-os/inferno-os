package compiler

// stdlib_packages2.go — more standard library package stubs.

import (
	"go/constant"
	"go/token"
	"go/types"
)

func buildCryptoSHA1Package() *types.Package {
	pkg := types.NewPackage("crypto/sha1", "sha1")
	scope := pkg.Scope()

	scope.Insert(types.NewConst(token.NoPos, pkg, "Size", types.Typ[types.Int], constant.MakeInt64(20)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BlockSize", types.Typ[types.Int], constant.MakeInt64(64)))

	// func Sum(data []byte) [20]byte — simplified as []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// hash.Hash interface
	byteSliceSha1 := types.NewSlice(types.Typ[types.Byte])
	hashIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceSha1)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", types.Universe.Lookup("error").Type())),
				false)),
		types.NewFunc(token.NoPos, nil, "Sum",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceSha1)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSliceSha1)),
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

	// func Sum(data []byte) [20]byte — simplified as returning []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSliceSha1)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSliceSha1)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildCompressZlibPackage() *types.Package {
	pkg := types.NewPackage("compress/zlib", "zlib")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
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

	// io.Writer interface
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

	// io.ReadCloser interface
	ioReadCloser := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
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
	ioReadCloser.Complete()

	// Resetter interface
	resetterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Reset",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", ioReader),
					types.NewVar(token.NoPos, nil, "dict", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	resetterIface.Complete()
	resetterType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Resetter", nil),
		resetterIface, nil)
	scope.Insert(resetterType.Obj())

	// type Writer struct
	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())
	writerPtr := types.NewPointer(writerType)

	writerRecv := types.NewVar(token.NoPos, nil, "z", writerPtr)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(writerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(writerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", ioWriter)),
			nil, false)))

	// func NewReader(r io.Reader) (io.ReadCloser, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ioReadCloser),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewWriter(w io.Writer) *Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriter)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", writerPtr)),
			false)))

	scope.Insert(types.NewConst(token.NoPos, pkg, "NoCompression", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BestSpeed", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BestCompression", types.Typ[types.Int], constant.MakeInt64(9)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultCompression", types.Typ[types.Int], constant.MakeInt64(-1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "HuffmanOnly", types.Typ[types.Int], constant.MakeInt64(-2)))

	// func NewWriterLevel(w io.Writer, level int) (*Writer, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriterLevel",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "level", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", writerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewReaderDict(r io.Reader, dict []byte) (io.ReadCloser, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReaderDict",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", ioReader),
				types.NewVar(token.NoPos, pkg, "dict", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ioReadCloser),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewWriterLevelDict(w io.Writer, level int, dict []byte) (*Writer, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriterLevelDict",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "level", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "dict", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", writerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// var ErrChecksum, ErrDictionary, ErrHeader error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrChecksum", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrDictionary", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrHeader", errType))

	pkg.MarkComplete()
	return pkg
}

func buildCompressBzip2Package() *types.Package {
	pkg := types.NewPackage("compress/bzip2", "bzip2")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
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

	// func NewReader(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// type StructuralError string
	structuralErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "StructuralError", nil),
		types.Typ[types.String], nil)
	structuralErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", structuralErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(structuralErrType.Obj())
	_ = errType

	pkg.MarkComplete()
	return pkg
}

func buildCompressLzwPackage() *types.Package {
	pkg := types.NewPackage("compress/lzw", "lzw")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.ReadCloser interface
	ioReadCloser := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
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
	ioReadCloser.Complete()

	// io.WriteCloser interface
	ioWriteCloser := types.NewInterfaceType([]*types.Func{
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
	ioWriteCloser.Complete()

	// io.Reader interface
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

	// io.Writer interface
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

	// type Order int
	orderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Order", nil), types.Typ[types.Int], nil)
	scope.Insert(orderType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "LSB", orderType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MSB", orderType, constant.MakeInt64(1)))

	// func NewReader(r io.Reader, order Order, litWidth int) io.ReadCloser
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", ioReader),
				types.NewVar(token.NoPos, pkg, "order", orderType),
				types.NewVar(token.NoPos, pkg, "litWidth", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReadCloser)),
			false)))

	// func NewWriter(w io.Writer, order Order, litWidth int) io.WriteCloser
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "order", orderType),
				types.NewVar(token.NoPos, pkg, "litWidth", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioWriteCloser)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildHashFNVPackage() *types.Package {
	pkg := types.NewPackage("hash/fnv", "fnv")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// hash.Hash interface
	hashIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
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

	// New32, New32a return hash.Hash32 (use hash.Hash)
	// New64, New64a return hash.Hash64 (use hash.Hash)
	// New128, New128a return hash.Hash (use hash.Hash)
	for _, name := range []string{"New32", "New32a", "New64", "New64a", "New128", "New128a"} {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)),
				false)))
	}

	pkg.MarkComplete()
	return pkg
}

func buildHashMaphashPackage() *types.Package {
	pkg := types.NewPackage("hash/maphash", "maphash")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type Seed struct (opaque)
	seedType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Seed", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(seedType.Obj())

	// func MakeSeed() Seed
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeSeed",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", seedType)),
			false)))

	// type Hash struct (opaque)
	hashType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Hash", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(hashType.Obj())
	hashPtr := types.NewPointer(hashType)
	hashRecv := types.NewVar(token.NoPos, nil, "h", hashPtr)

	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(hashRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteByte",
		types.NewSignatureType(hashRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.Typ[types.Byte])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteString",
		types.NewSignatureType(hashRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sum64",
		types.NewSignatureType(hashRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seed",
		types.NewSignatureType(hashRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", seedType)), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetSeed",
		types.NewSignatureType(hashRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "seed", seedType)),
			nil, false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(hashRecv, nil, nil, nil, nil, false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(hashRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "BlockSize",
		types.NewSignatureType(hashRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sum",
		types.NewSignatureType(hashRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)))

	// func Bytes(seed Seed, b []byte) uint64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "seed", seedType),
				types.NewVar(token.NoPos, pkg, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))

	// func String(seed Seed, s string) uint64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "seed", seedType),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildImageDrawPackage() *types.Package {
	pkg := types.NewPackage("image/draw", "draw")
	scope := pkg.Scope()

	// type Op int
	opType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Op", nil),
		types.Typ[types.Int], nil)
	scope.Insert(opType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "Over", opType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Src", opType, constant.MakeInt64(1)))


	// image.Rectangle stand-in
	rectStruct := types.NewStruct([]*types.Var{
		types.NewVar(token.NoPos, nil, "Min", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
		types.NewVar(token.NoPos, nil, "Max", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
	}, nil)

	// image.Point stand-in
	pointStruct := types.NewStruct([]*types.Var{
		types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
		types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
	}, nil)

	// color.Color stand-in interface { RGBA() (r, g, b, a uint32) }
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

	// color.Model stand-in interface { Convert(c Color) Color }
	colorModelIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Convert",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorIface)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIface)),
				false)),
	}, nil)
	colorModelIface.Complete()

	// image.Image stand-in interface { ColorModel() color.Model; Bounds() Rectangle; At(x, y int) color.Color }
	srcIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelIface)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectStruct)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIface)),
				false)),
	}, nil)
	srcIface.Complete()

	// draw.Image interface — extends image.Image with Set(x, y int, c color.Color)
	imgIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelIface)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectStruct)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIface)),
				false)),
		types.NewFunc(token.NoPos, nil, "Set",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "c", colorIface)),
				nil, false)),
	}, nil)
	imgIface.Complete()
	imgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Image", nil),
		imgIface, nil)
	scope.Insert(imgType.Obj())

	// Drawer interface { Draw(dst Image, r image.Rectangle, src image.Image, sp image.Point) }
	drawerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Draw",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", imgType),
					types.NewVar(token.NoPos, nil, "r", rectStruct),
					types.NewVar(token.NoPos, nil, "src", srcIface),
					types.NewVar(token.NoPos, nil, "sp", pointStruct)),
				nil, false)),
	}, nil)
	drawerIface.Complete()
	drawerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Drawer", nil),
		drawerIface, nil)
	scope.Insert(drawerType.Obj())

	// color.Palette stand-in: []color.Color
	paletteSlice := types.NewSlice(colorIface)

	// Quantizer interface { Quantize(p color.Palette, m image.Image) color.Palette }
	quantizerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Quantize",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", paletteSlice),
					types.NewVar(token.NoPos, nil, "m", srcIface)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", paletteSlice)),
				false)),
	}, nil)
	quantizerIface.Complete()
	quantizerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Quantizer", nil),
		quantizerIface, nil)
	scope.Insert(quantizerType.Obj())

	// var FloydSteinberg Drawer
	scope.Insert(types.NewVar(token.NoPos, pkg, "FloydSteinberg", drawerType))

	// func Draw(dst Image, r Rectangle, src image.Image, sp Point, op Op)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Draw",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", imgType),
				types.NewVar(token.NoPos, pkg, "r", rectStruct),
				types.NewVar(token.NoPos, pkg, "src", srcIface),
				types.NewVar(token.NoPos, pkg, "sp", pointStruct),
				types.NewVar(token.NoPos, pkg, "op", opType)),
			nil, false)))

	// func DrawMask(dst Image, r Rectangle, src image.Image, sp Point, mask image.Image, mp Point, op Op)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DrawMask",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", imgType),
				types.NewVar(token.NoPos, pkg, "r", rectStruct),
				types.NewVar(token.NoPos, pkg, "src", srcIface),
				types.NewVar(token.NoPos, pkg, "sp", pointStruct),
				types.NewVar(token.NoPos, pkg, "mask", srcIface),
				types.NewVar(token.NoPos, pkg, "mp", pointStruct),
				types.NewVar(token.NoPos, pkg, "op", opType)),
			nil, false)))

	// RGBA64Image interface — extends draw.Image with RGBA64At
	// color.RGBA64 stand-in struct
	rgba64Struct := types.NewStruct([]*types.Var{
		types.NewVar(token.NoPos, nil, "R", types.Typ[types.Uint16]),
		types.NewVar(token.NoPos, nil, "G", types.Typ[types.Uint16]),
		types.NewVar(token.NoPos, nil, "B", types.Typ[types.Uint16]),
		types.NewVar(token.NoPos, nil, "A", types.Typ[types.Uint16]),
	}, nil)

	rgba64ImgIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelIface)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectStruct)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIface)),
				false)),
		types.NewFunc(token.NoPos, nil, "Set",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "c", colorIface)),
				nil, false)),
		types.NewFunc(token.NoPos, nil, "SetRGBA64",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "c", rgba64Struct)),
				nil, false)),
		types.NewFunc(token.NoPos, nil, "RGBA64At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rgba64Struct)),
				false)),
	}, nil)
	rgba64ImgIface.Complete()
	rgba64ImgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RGBA64Image", nil),
		rgba64ImgIface, nil)
	scope.Insert(rgba64ImgType.Obj())

	// Op.Draw(dst Image, r image.Rectangle, src image.Image, sp image.Point)
	opType.AddMethod(types.NewFunc(token.NoPos, pkg, "Draw",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "op", opType),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", imgType),
				types.NewVar(token.NoPos, nil, "r", rectStruct),
				types.NewVar(token.NoPos, nil, "src", srcIface),
				types.NewVar(token.NoPos, nil, "sp", pointStruct)),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildImageGIFPackage() *types.Package {
	pkg := types.NewPackage("image/gif", "gif")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
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

	// io.Writer interface
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

	// image.Image stand-in interface { ColorModel(); Bounds(); At() }
	colorIfaceGIF := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIfaceGIF.Complete()
	colorModelGIF := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Convert",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorIfaceGIF)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfaceGIF)),
				false)),
	}, nil)
	colorModelGIF.Complete()
	rectStructGIF := types.NewStruct([]*types.Var{
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
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelGIF)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectStructGIF)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfaceGIF)),
				false)),
	}, nil)
	imageIface.Complete()

	// type Options struct { NumColors int, Quantizer, Drawer }
	optionsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "NumColors", types.Typ[types.Int], false),
	}, nil)
	optionsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Options", nil),
		optionsStruct, nil)
	scope.Insert(optionsType.Obj())

	// type GIF struct
	gifStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Image", types.NewSlice(imageIface), false),
		types.NewField(token.NoPos, pkg, "Delay", types.NewSlice(types.Typ[types.Int]), false),
		types.NewField(token.NoPos, pkg, "LoopCount", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Disposal", types.NewSlice(types.Typ[types.Byte]), false),
		types.NewField(token.NoPos, pkg, "BackgroundIndex", types.Typ[types.Byte], false),
	}, nil)
	gifType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "GIF", nil),
		gifStruct, nil)
	scope.Insert(gifType.Obj())
	gifPtr := types.NewPointer(gifType)

	// func Decode(r io.Reader) (image.Image, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DecodeAll(r io.Reader) (*GIF, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeAll",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", gifPtr),
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

	// func Encode(w io.Writer, m image.Image, o *Options) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "m", imageIface),
				types.NewVar(token.NoPos, pkg, "o", types.NewPointer(optionsType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func EncodeAll(w io.Writer, g *GIF) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EncodeAll",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "g", gifPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Disposal constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "DisposalNone", types.Typ[types.Byte], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DisposalBackground", types.Typ[types.Byte], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DisposalPrevious", types.Typ[types.Byte], constant.MakeInt64(3)))

	pkg.MarkComplete()
	return pkg
}

func buildExpvarPackage() *types.Package {
	pkg := types.NewPackage("expvar", "expvar")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// Var interface { String() string }
	varIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	varIface.Complete()
	varType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Var", nil),
		varIface, nil)
	scope.Insert(varType.Obj())

	// Int type (struct) with methods: Value, String, Add, Set
	intTypeName := types.NewTypeName(token.NoPos, pkg, "Int", nil)
	intNamed := types.NewNamed(intTypeName, types.NewStruct(nil, nil), nil)
	intPtr := types.NewPointer(intNamed)
	intRecv := types.NewVar(token.NoPos, pkg, "", intPtr)
	intNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)))
	intNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	intNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Int64])),
			nil, false)))
	intNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.Int64])),
			nil, false)))
	scope.Insert(intTypeName)

	// Float type (struct) with methods: Value, String, Add, Set
	floatTypeName := types.NewTypeName(token.NoPos, pkg, "Float", nil)
	floatNamed := types.NewNamed(floatTypeName, types.NewStruct(nil, nil), nil)
	floatPtr := types.NewPointer(floatNamed)
	floatRecv := types.NewVar(token.NoPos, pkg, "", floatPtr)
	floatNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])), false)))
	floatNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	floatNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Float64])),
			nil, false)))
	floatNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.Float64])),
			nil, false)))
	scope.Insert(floatTypeName)

	// String type (named struct) with methods: Value, String, Set
	stringTypeName := types.NewTypeName(token.NoPos, pkg, "String", nil)
	stringNamed := types.NewNamed(stringTypeName, types.NewStruct(nil, nil), nil)
	stringPtr := types.NewPointer(stringNamed)
	stringRecv := types.NewVar(token.NoPos, pkg, "", stringPtr)
	stringNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(stringRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	stringNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(stringRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	stringNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(stringRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			nil, false)))
	scope.Insert(stringTypeName)

	// KeyValue struct
	kvStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Key", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", varType, false),
	}, nil)
	kvType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "KeyValue", nil),
		kvStruct, nil)
	scope.Insert(kvType.Obj())

	// callback func(KeyValue) used by Do and Map.Do
	doFuncSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "kv", kvType)),
		nil, false)

	// Map type (struct) with methods: String, Init, Get, Set, Add, AddFloat, Delete, Do
	mapTypeName := types.NewTypeName(token.NoPos, pkg, "Map", nil)
	mapNamed := types.NewNamed(mapTypeName, types.NewStruct(nil, nil), nil)
	mapPtr := types.NewPointer(mapNamed)
	mapRecv := types.NewVar(token.NoPos, pkg, "", mapPtr)
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(mapRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(mapRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", mapPtr)), false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(mapRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varType)), false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(mapRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "av", varType)),
			nil, false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(mapRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Int64])),
			nil, false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "AddFloat",
		types.NewSignatureType(mapRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Float64])),
			nil, false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Delete",
		types.NewSignatureType(mapRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			nil, false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Do",
		types.NewSignatureType(mapRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f", doFuncSig)),
			nil, false)))
	scope.Insert(mapTypeName)

	// Func type: func() any, with String() method
	funcTypeName := types.NewTypeName(token.NoPos, pkg, "Func", nil)
	funcUnderlying := types.NewSignatureType(nil, nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
		false)
	funcNamed := types.NewNamed(funcTypeName, funcUnderlying, nil)
	funcRecv := types.NewVar(token.NoPos, pkg, "", funcNamed)
	funcNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(funcRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)))
	funcNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(funcRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(funcTypeName)

	// func NewInt(name string) *Int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewInt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func NewFloat(name string) *Float
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFloat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", floatPtr)),
			false)))

	// func NewString(name string) *String
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", stringPtr)),
			false)))

	// func NewMap(name string) *Map
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewMap",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", mapPtr)),
			false)))

	// func Get(name string) Var
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", varType)),
			false)))

	// func Publish(name string, v Var)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Publish",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "v", varType)),
			nil, false)))

	// func Do(f func(KeyValue))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Do",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f", doFuncSig)),
			nil, false)))

	// func Handler() http.Handler
	headerMap := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))
	rwIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerMap)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "WriteHeader",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "statusCode", types.Typ[types.Int])),
				nil, false)),
	}, nil)
	rwIface.Complete()
	reqPtr := types.NewPointer(types.NewStruct(nil, nil))
	handlerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ServeHTTP",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "w", rwIface),
					types.NewVar(token.NoPos, nil, "r", reqPtr)),
				nil, false)),
	}, nil)
	handlerIface.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Handler",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handlerIface)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildLogSyslogPackage() *types.Package {
	pkg := types.NewPackage("log/syslog", "syslog")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())

	// func New(priority Priority, tag string) (*Writer, error) — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "priority", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "tag", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(writerType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type Priority int
	priorityType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Priority", nil),
		types.Typ[types.Int], nil)
	scope.Insert(priorityType.Obj())

	// Priority constants - severity
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_EMERG", priorityType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_ALERT", priorityType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_CRIT", priorityType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_ERR", priorityType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_WARNING", priorityType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_NOTICE", priorityType, constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_INFO", priorityType, constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_DEBUG", priorityType, constant.MakeInt64(7)))

	// Priority constants - facility
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_KERN", priorityType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_USER", priorityType, constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_MAIL", priorityType, constant.MakeInt64(16)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_DAEMON", priorityType, constant.MakeInt64(24)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_AUTH", priorityType, constant.MakeInt64(32)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_SYSLOG", priorityType, constant.MakeInt64(40)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_LOCAL0", priorityType, constant.MakeInt64(128)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_LOCAL7", priorityType, constant.MakeInt64(184)))

	// func Dial(network, raddr string, priority Priority, tag string) (*Writer, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "raddr", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "priority", priorityType),
				types.NewVar(token.NoPos, pkg, "tag", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(writerType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Writer methods
	writerPtr := types.NewPointer(writerType)

	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	for _, name := range []string{"Emerg", "Alert", "Crit", "Err", "Warning", "Notice", "Info", "Debug"} {
		writerType.AddMethod(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
				nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "m", types.Typ[types.String])),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
				false)))
	}

	pkg.MarkComplete()
	return pkg
}

func buildIndexSuffixarrayPackage() *types.Package {
	pkg := types.NewPackage("index/suffixarray", "suffixarray")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type Index struct (opaque)
	indexType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Index", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(indexType.Obj())
	indexPtr := types.NewPointer(indexType)
	indexRecv := types.NewVar(token.NoPos, nil, "x", indexPtr)

	// func New(data []byte) *Index
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", indexPtr)),
			false)))

	// Index.Bytes() int
	indexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(indexRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// Index.Lookup(s []byte, n int) []int
	indexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(indexRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "s", byteSlice),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Int]))), false)))

	// Index.FindAllIndex(r *regexp.Regexp, n int) [][]int
	// *regexp.Regexp stand-in as opaque struct pointer
	regexpPtr := types.NewPointer(types.NewStruct(nil, nil))
	indexType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindAllIndex",
		types.NewSignatureType(indexRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", regexpPtr),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.NewSlice(types.Typ[types.Int])))), false)))

	// io.Reader interface for Index.Read
	ioReaderSA := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderSA.Complete()

	// io.Writer interface for Index.Write
	ioWriterSA := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterSA.Complete()

	// Index.Read/Write
	indexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(indexRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", ioReaderSA)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	indexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(indexRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", ioWriterSA)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoPrinterPackage() *types.Package {
	pkg := types.NewPackage("go/printer", "printer")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anyType := types.Universe.Lookup("any").Type()

	// type Mode uint
	modeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Mode", nil), types.Typ[types.Uint], nil)
	scope.Insert(modeType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "RawFormat", modeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TabIndent", modeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "UseSpaces", modeType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SourcePos", modeType, constant.MakeInt64(8)))

	// type Config struct { Mode Mode; Tabwidth int; Indent int }
	configStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Mode", modeType, false),
		types.NewField(token.NoPos, pkg, "Tabwidth", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Indent", types.Typ[types.Int], false),
	}, nil)
	configType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Config", nil), configStruct, nil)
	scope.Insert(configType.Obj())
	configPtr := types.NewPointer(configType)

	// io.Writer for Fprint output
	byteSlicePr := types.NewSlice(types.Typ[types.Byte])
	ioWriterPr := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlicePr)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterPr.Complete()

	// *token.FileSet stand-in
	fsetPtrPr := types.NewPointer(types.NewStruct(nil, nil))

	// Config.Fprint(output io.Writer, fset *token.FileSet, node any) error
	configType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fprint",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "cfg", configPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "output", ioWriterPr),
				types.NewVar(token.NoPos, nil, "fset", fsetPtrPr),
				types.NewVar(token.NoPos, nil, "node", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func Fprint(output io.Writer, fset *token.FileSet, node any) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fprint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "output", ioWriterPr),
				types.NewVar(token.NoPos, pkg, "fset", fsetPtrPr),
				types.NewVar(token.NoPos, pkg, "node", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type CommentedNode struct { Node any; Comments []*ast.CommentGroup }
	// *ast.CommentGroup stand-in as opaque pointer
	commentGroupPtr := types.NewPointer(types.NewStruct(nil, nil))
	commentedNodeStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Node", anyType, false),
		types.NewField(token.NoPos, pkg, "Comments", types.NewSlice(commentGroupPtr), false),
	}, nil)
	commentedNodeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CommentedNode", nil), commentedNodeStruct, nil)
	scope.Insert(commentedNodeType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildGoBuildPackage() *types.Package {
	pkg := types.NewPackage("go/build", "build")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Package struct
	buildPkgStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dir", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "ImportComment", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Doc", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "ImportPath", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Root", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "SrcRoot", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "PkgRoot", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "BinDir", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Goroot", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "PkgObj", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "GoFiles", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "CgoFiles", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "IgnoredGoFiles", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "TestGoFiles", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "XTestGoFiles", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Imports", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "TestImports", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "XTestImports", types.NewSlice(types.Typ[types.String]), false),
	}, nil)
	buildPkgType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Package", nil), buildPkgStruct, nil)
	scope.Insert(buildPkgType.Obj())

	// type Context struct
	contextStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "GOARCH", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "GOOS", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "GOROOT", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "GOPATH", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "CgoEnabled", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Compiler", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "BuildTags", types.NewSlice(types.Typ[types.String]), false),
	}, nil)
	contextType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Context", nil), contextStruct, nil)
	scope.Insert(contextType.Obj())
	contextPtr := types.NewPointer(contextType)
	contextRecv := types.NewVar(token.NoPos, nil, "ctxt", contextPtr)

	// var Default Context
	scope.Insert(types.NewVar(token.NoPos, pkg, "Default", contextType))

	// Context.ImportDir(dir string, mode ImportMode) (*Package, error)
	importModeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ImportMode", nil), types.Typ[types.Uint], nil)
	scope.Insert(importModeType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "FindOnly", importModeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AllowBinary", importModeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ImportComment", importModeType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "IgnoreVendor", importModeType, constant.MakeInt64(8)))

	contextType.AddMethod(types.NewFunc(token.NoPos, pkg, "Import",
		types.NewSignatureType(contextRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "srcDir", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "mode", importModeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewPointer(buildPkgType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	contextType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportDir",
		types.NewSignatureType(contextRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "mode", importModeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewPointer(buildPkgType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func Import(path, srcDir string, mode ImportMode) (*Package, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Import",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "srcDir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", importModeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(buildPkgType)),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func ImportDir(dir string, mode ImportMode) (*Package, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ImportDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", importModeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(buildPkgType)),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// type NoGoError struct { Dir string }
	noGoErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dir", types.Typ[types.String], false),
	}, nil)
	noGoErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "NoGoError", nil), noGoErrStruct, nil)
	noGoErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(noGoErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(noGoErrType.Obj())

	// type MultiplePackageError struct
	multiPkgErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dir", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Packages", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Files", types.NewSlice(types.Typ[types.String]), false),
	}, nil)
	multiPkgErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "MultiplePackageError", nil), multiPkgErrStruct, nil)
	multiPkgErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(multiPkgErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(multiPkgErrType.Obj())

	// func IsLocalImport(path string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsLocalImport",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoTypesPackage() *types.Package {
	pkg := types.NewPackage("go/types", "types")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Type interface { Underlying() Type; String() string } — self-referential
	typeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Type", nil), types.NewInterfaceType(nil, nil), nil)
	typeIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Underlying",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	typeIface.Complete()
	typeType.SetUnderlying(typeIface)
	scope.Insert(typeType.Obj())

	// type Object interface { Name() string; Type() Type; Pos() token.Pos; Id() string; Parent() *Scope; Exported() bool; Pkg() *Package; String() string }
	objectIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Type",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)),
		types.NewFunc(token.NoPos, pkg, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "Id",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Exported",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	objectIface.Complete()
	objectType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Object", nil), objectIface, nil)
	scope.Insert(objectType.Obj())

	// type Package struct (opaque)
	pkgType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Package", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(pkgType.Obj())
	pkgPtr := types.NewPointer(pkgType)
	pkgRecv := types.NewVar(token.NoPos, nil, "pkg", pkgPtr)
	pkgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Path",
		types.NewSignatureType(pkgRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	pkgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(pkgRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	// *Scope opaque stand-in
	scopePtr := types.NewPointer(types.NewStruct(nil, nil))
	pkgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Scope",
		types.NewSignatureType(pkgRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtr)), false)))
	pkgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Imports",
		types.NewSignatureType(pkgRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(pkgPtr))), false)))
	pkgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Complete",
		types.NewSignatureType(pkgRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	pkgType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(pkgRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// ast.Expr stand-in interface (Pos/End methods)
	astExprIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, nil, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
	}, nil)
	astExprIface.Complete()

	// TypeAndValue struct stand-in { Mode int; Type Type; Value constant.Value }
	typeAndValueStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Type", typeType, false),
	}, nil)
	typeAndValueType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TypeAndValue", nil), typeAndValueStruct, nil)
	scope.Insert(typeAndValueType.Obj())

	// *ast.Ident opaque pointer for Defs/Uses map keys
	astIdentPtr := types.NewPointer(types.NewStruct(nil, nil))

	// type Info struct
	infoStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Types", types.NewMap(astExprIface, typeAndValueType), false),
		types.NewField(token.NoPos, pkg, "Defs", types.NewMap(astIdentPtr, objectType), false),
		types.NewField(token.NoPos, pkg, "Uses", types.NewMap(astIdentPtr, objectType), false),
	}, nil)
	infoType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Info", nil), infoStruct, nil)
	scope.Insert(infoType.Obj())

	// Importer interface { Import(path string) (*Package, error) }
	importerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Import",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "path", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", pkgPtr),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	importerIface.Complete()
	importerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Importer", nil), importerIface, nil)
	scope.Insert(importerType.Obj())

	// *token.FileSet and *ast.File stand-ins
	fsetPtrTypes := types.NewPointer(types.NewStruct(nil, nil))
	astFilePtr := types.NewPointer(types.NewStruct(nil, nil))

	// type Config struct
	configStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "GoVersion", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Error", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "err", errType)), nil, false), false),
		types.NewField(token.NoPos, pkg, "Importer", importerType, false),
	}, nil)
	configType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Config", nil), configStruct, nil)
	scope.Insert(configType.Obj())
	configPtr := types.NewPointer(configType)
	configType.AddMethod(types.NewFunc(token.NoPos, pkg, "Check",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "conf", configPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "fset", fsetPtrTypes),
				types.NewVar(token.NoPos, nil, "files", types.NewSlice(astFilePtr)),
				types.NewVar(token.NoPos, nil, "info", types.NewPointer(infoType))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", pkgPtr),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// type Sizes interface { Alignof(T Type) int64; Offsetsof(fields []*Var) []int64; Sizeof(T Type) int64 }
	sizesIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Alignof",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "T", typeType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, pkg, "Sizeof",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "T", typeType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
	}, nil)
	sizesIface.Complete()
	sizesType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Sizes", nil), sizesIface, nil)
	scope.Insert(sizesType.Obj())

	// func SizesFor(compiler, arch string) Sizes
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SizesFor",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "compiler", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "arch", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", sizesType)), false)))

	// type Error struct { Fset *token.FileSet; Pos token.Pos; Msg string; Soft bool }
	typesErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Fset", fsetPtrTypes, false),
		types.NewField(token.NoPos, pkg, "Pos", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Msg", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Soft", types.Typ[types.Bool], false),
	}, nil)
	typesErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Error", nil), typesErrStruct, nil)
	typesErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "err", typesErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(typesErrType.Obj())

	// Importer already defined above

	// func ExprString(x ast.Expr) string — use ast.Expr stand-in
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ExprString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", astExprIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))

	// --- Scope type ---
	// type Scope struct (with proper methods)
	scopeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Scope", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(scopeType.Obj())
	scopePtrT := types.NewPointer(scopeType)
	scopeRecv := types.NewVar(token.NoPos, nil, "s", scopePtrT)
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Names",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String]))), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumChildren",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Child",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", objectType)), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Insert",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "obj", objectType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", objectType)), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pos",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "End",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Contains",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pos", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Innermost",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pos", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteTo",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "w", types.NewInterfaceType([]*types.Func{
					types.NewFunc(token.NoPos, nil, "Write",
						types.NewSignatureType(nil, nil, nil,
							types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
							types.NewTuple(
								types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
								types.NewVar(token.NoPos, nil, "err", errType)),
							false)),
				}, nil)),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "recurse", types.Typ[types.Bool])),
			nil, false)))

	// --- Concrete Object subtypes (implement Object interface) ---
	posType := types.Typ[types.Int] // token.Pos stand-in

	// type Var struct (opaque - satisfies Object)
	varType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Var", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(varType.Obj())
	varPtr := types.NewPointer(varType)
	varRecv := types.NewVar(token.NoPos, nil, "v", varPtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		varType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(varRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	varType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(varRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	varType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(varRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))
	varType.AddMethod(types.NewFunc(token.NoPos, pkg, "Anonymous",
		types.NewSignatureType(varRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	varType.AddMethod(types.NewFunc(token.NoPos, pkg, "Embedded",
		types.NewSignatureType(varRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	varType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsField",
		types.NewSignatureType(varRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	varType.AddMethod(types.NewFunc(token.NoPos, pkg, "Origin",
		types.NewSignatureType(varRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varPtr)), false)))

	// type Const struct (opaque - satisfies Object)
	constType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Const", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(constType.Obj())
	constPtr := types.NewPointer(constType)
	constRecv := types.NewVar(token.NoPos, nil, "c", constPtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		constType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(constRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	constType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(constRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	constType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(constRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))
	// Val() constant.Value — simplify to any
	constType.AddMethod(types.NewFunc(token.NoPos, pkg, "Val",
		types.NewSignatureType(constRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)))

	// type Func struct (opaque - satisfies Object)
	funcType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Func", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(funcType.Obj())
	funcPtr := types.NewPointer(funcType)
	funcRecv := types.NewVar(token.NoPos, nil, "f", funcPtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
		{"FullName", types.Typ[types.String]},
	} {
		funcType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(funcRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	funcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(funcRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	funcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(funcRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))
	funcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Origin",
		types.NewSignatureType(funcRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", funcPtr)), false)))

	// type TypeName struct (opaque - satisfies Object)
	typeNameType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TypeName", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(typeNameType.Obj())
	typeNamePtr := types.NewPointer(typeNameType)
	typeNameRecv := types.NewVar(token.NoPos, nil, "t", typeNamePtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		typeNameType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(typeNameRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	typeNameType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(typeNameRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	typeNameType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(typeNameRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))
	typeNameType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsAlias",
		types.NewSignatureType(typeNameRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// type Label struct (opaque - satisfies Object)
	labelType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Label", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(labelType.Obj())
	labelPtr := types.NewPointer(labelType)
	labelRecv := types.NewVar(token.NoPos, nil, "l", labelPtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		labelType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(labelRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	labelType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(labelRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	labelType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(labelRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))

	// type PkgName struct (opaque - satisfies Object)
	pkgNameType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "PkgName", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(pkgNameType.Obj())
	pkgNamePtr := types.NewPointer(pkgNameType)
	pkgNameRecv := types.NewVar(token.NoPos, nil, "p", pkgNamePtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		pkgNameType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(pkgNameRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	pkgNameType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(pkgNameRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	pkgNameType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(pkgNameRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))
	pkgNameType.AddMethod(types.NewFunc(token.NoPos, pkg, "Imported",
		types.NewSignatureType(pkgNameRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))

	// type Builtin struct (opaque - satisfies Object)
	builtinType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Builtin", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(builtinType.Obj())
	builtinPtr := types.NewPointer(builtinType)
	builtinRecv := types.NewVar(token.NoPos, nil, "b", builtinPtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		builtinType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(builtinRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	builtinType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(builtinRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	builtinType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(builtinRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))

	// type Nil struct (opaque - satisfies Object)
	nilObjType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Nil", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(nilObjType.Obj())
	nilObjPtr := types.NewPointer(nilObjType)
	nilObjRecv := types.NewVar(token.NoPos, nil, "n", nilObjPtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		nilObjType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(nilObjRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	nilObjType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(nilObjRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	nilObjType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(nilObjRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))

	// --- Constructor functions for Object subtypes ---
	// func NewVar(pos token.Pos, pkg *Package, name string, typ Type) *Var
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewVar",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "typ", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varPtr)), false)))

	// func NewConst(pos token.Pos, pkg *Package, name string, typ Type, val constant.Value) *Const
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewConst",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "typ", typeType),
				types.NewVar(token.NoPos, nil, "val", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", constPtr)), false)))

	// func NewFunc(pos token.Pos, pkg *Package, name string, sig *Signature) *Func
	// *Signature stand-in
	sigPtr := types.NewPointer(types.NewStruct(nil, nil))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "sig", sigPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", funcPtr)), false)))

	// func NewTypeName(pos token.Pos, pkg *Package, name string, typ Type) *TypeName
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTypeName",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "typ", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeNamePtr)), false)))

	// func NewLabel(pos token.Pos, pkg *Package, name string) *Label
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewLabel",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", labelPtr)), false)))

	// func NewPkgName(pos token.Pos, pkg *Package, name string, imported *Package) *PkgName
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewPkgName",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "imported", pkgPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgNamePtr)), false)))

	// func NewField(pos token.Pos, pkg *Package, name string, typ Type, embedded bool) *Var
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewField",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "typ", typeType),
				types.NewVar(token.NoPos, nil, "embedded", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varPtr)), false)))

	// --- Concrete Type types ---

	// type Basic struct (opaque)
	basicType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Basic", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(basicType.Obj())
	basicPtr := types.NewPointer(basicType)
	basicRecv := types.NewVar(token.NoPos, nil, "b", basicPtr)
	basicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Kind",
		types.NewSignatureType(basicRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	basicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Info",
		types.NewSignatureType(basicRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	basicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(basicRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	basicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(basicRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	basicType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(basicRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Named struct (opaque)
	namedType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Named", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(namedType.Obj())
	namedPtr := types.NewPointer(namedType)
	namedRecv := types.NewVar(token.NoPos, nil, "n", namedPtr)
	namedType.AddMethod(types.NewFunc(token.NoPos, pkg, "Obj",
		types.NewSignatureType(namedRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeNamePtr)), false)))
	namedType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumMethods",
		types.NewSignatureType(namedRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	namedType.AddMethod(types.NewFunc(token.NoPos, pkg, "Method",
		types.NewSignatureType(namedRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", funcPtr)), false)))
	namedType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(namedRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	namedType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(namedRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Pointer struct (opaque)
	pointerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Pointer", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(pointerType.Obj())
	pointerPtr := types.NewPointer(pointerType)
	pointerRecv := types.NewVar(token.NoPos, nil, "p", pointerPtr)
	pointerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Elem",
		types.NewSignatureType(pointerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	pointerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(pointerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	pointerType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(pointerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Array struct (opaque)
	arrayType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Array", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(arrayType.Obj())
	arrayPtr := types.NewPointer(arrayType)
	arrayRecv := types.NewVar(token.NoPos, nil, "a", arrayPtr)
	arrayType.AddMethod(types.NewFunc(token.NoPos, pkg, "Elem",
		types.NewSignatureType(arrayRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	arrayType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(arrayRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)))
	arrayType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(arrayRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	arrayType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(arrayRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Slice struct (opaque)
	sliceType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Slice", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(sliceType.Obj())
	slicePtr := types.NewPointer(sliceType)
	sliceRecv := types.NewVar(token.NoPos, nil, "s", slicePtr)
	sliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Elem",
		types.NewSignatureType(sliceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	sliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(sliceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	sliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(sliceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Map struct (opaque)
	mapType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Map", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(mapType.Obj())
	mapPtr := types.NewPointer(mapType)
	mapRecv := types.NewVar(token.NoPos, nil, "m", mapPtr)
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "Key",
		types.NewSignatureType(mapRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "Elem",
		types.NewSignatureType(mapRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(mapRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(mapRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Chan struct (opaque)
	chanType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Chan", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(chanType.Obj())
	chanPtr := types.NewPointer(chanType)
	chanRecv := types.NewVar(token.NoPos, nil, "c", chanPtr)
	chanType.AddMethod(types.NewFunc(token.NoPos, pkg, "Dir",
		types.NewSignatureType(chanRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	chanType.AddMethod(types.NewFunc(token.NoPos, pkg, "Elem",
		types.NewSignatureType(chanRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	chanType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(chanRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	chanType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(chanRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type ChanDir int
	chanDirType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ChanDir", nil), types.Typ[types.Int], nil)
	scope.Insert(chanDirType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "SendRecv", chanDirType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SendOnly", chanDirType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RecvOnly", chanDirType, constant.MakeInt64(2)))

	// type Struct struct (opaque)
	structType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Struct", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(structType.Obj())
	structPtr := types.NewPointer(structType)
	structRecv := types.NewVar(token.NoPos, nil, "s", structPtr)
	structType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumFields",
		types.NewSignatureType(structRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	structType.AddMethod(types.NewFunc(token.NoPos, pkg, "Field",
		types.NewSignatureType(structRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varPtr)), false)))
	structType.AddMethod(types.NewFunc(token.NoPos, pkg, "Tag",
		types.NewSignatureType(structRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	structType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(structRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	structType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(structRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Signature struct (opaque)
	signatureType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Signature", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(signatureType.Obj())
	signaturePtr := types.NewPointer(signatureType)
	signatureRecv := types.NewVar(token.NoPos, nil, "s", signaturePtr)
	// type Tuple struct (opaque)
	tupleType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Tuple", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(tupleType.Obj())
	tuplePtr := types.NewPointer(tupleType)
	tupleRecv := types.NewVar(token.NoPos, nil, "t", tuplePtr)
	tupleType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(tupleRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	tupleType.AddMethod(types.NewFunc(token.NoPos, pkg, "At",
		types.NewSignatureType(tupleRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varPtr)), false)))

	signatureType.AddMethod(types.NewFunc(token.NoPos, pkg, "Recv",
		types.NewSignatureType(signatureRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varPtr)), false)))
	signatureType.AddMethod(types.NewFunc(token.NoPos, pkg, "Params",
		types.NewSignatureType(signatureRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", tuplePtr)), false)))
	signatureType.AddMethod(types.NewFunc(token.NoPos, pkg, "Results",
		types.NewSignatureType(signatureRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", tuplePtr)), false)))
	signatureType.AddMethod(types.NewFunc(token.NoPos, pkg, "Variadic",
		types.NewSignatureType(signatureRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	signatureType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(signatureRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	signatureType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(signatureRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Interface struct (opaque)
	ifaceType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Interface", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(ifaceType.Obj())
	ifacePtr := types.NewPointer(ifaceType)
	ifaceRecv := types.NewVar(token.NoPos, nil, "i", ifacePtr)
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumMethods",
		types.NewSignatureType(ifaceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Method",
		types.NewSignatureType(ifaceRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", funcPtr)), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumEmbeddeds",
		types.NewSignatureType(ifaceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "EmbeddedType",
		types.NewSignatureType(ifaceRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Empty",
		types.NewSignatureType(ifaceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Complete",
		types.NewSignatureType(ifaceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ifacePtr)), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(ifaceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(ifaceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// --- Type assertion functions ---

	// func Implements(V Type, T *Interface) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Implements",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "V", typeType),
				types.NewVar(token.NoPos, nil, "T", ifacePtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func AssignableTo(V, T Type) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AssignableTo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "V", typeType),
				types.NewVar(token.NoPos, nil, "T", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func ConvertibleTo(V, T Type) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ConvertibleTo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "V", typeType),
				types.NewVar(token.NoPos, nil, "T", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func Identical(x, y Type) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Identical",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", typeType),
				types.NewVar(token.NoPos, nil, "y", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func IdenticalIgnoreTags(x, y Type) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IdenticalIgnoreTags",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", typeType),
				types.NewVar(token.NoPos, nil, "y", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func Comparable(T Type) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Comparable",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "T", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func Default(typ Type) Type
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Default",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "typ", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))

	// --- Type constructor functions ---

	// func NewArray(elem Type, len int64) *Array
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewArray",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "elem", typeType),
				types.NewVar(token.NoPos, nil, "len", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", arrayPtr)), false)))

	// func NewSlice(elem Type) *Slice
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewSlice",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "elem", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", slicePtr)), false)))

	// func NewMap(key, elem Type) *Map
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewMap",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", typeType),
				types.NewVar(token.NoPos, nil, "elem", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", mapPtr)), false)))

	// func NewChan(dir ChanDir, elem Type) *Chan
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewChan",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dir", chanDirType),
				types.NewVar(token.NoPos, nil, "elem", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", chanPtr)), false)))

	// func NewPointer(elem Type) *Pointer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewPointer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "elem", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pointerPtr)), false)))

	// func NewStruct(fields []*Var, tags []string) *Struct
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewStruct",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fields", types.NewSlice(varPtr)),
				types.NewVar(token.NoPos, nil, "tags", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", structPtr)), false)))

	// func NewTuple(x ...*Var) *Tuple
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTuple",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewSlice(varPtr))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", tuplePtr)), true)))

	// func NewSignature(recv *Var, params, results *Tuple, variadic bool) *Signature
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewSignature",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "recv", varPtr),
				types.NewVar(token.NoPos, nil, "params", tuplePtr),
				types.NewVar(token.NoPos, nil, "results", tuplePtr),
				types.NewVar(token.NoPos, nil, "variadic", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", signaturePtr)), false)))

	// func NewSignatureType(recv *Var, recvTypeParams, typeParams []*TypeParam, params, results *Tuple, variadic bool) *Signature
	typeParamSlice := types.NewSlice(types.NewPointer(types.NewStruct(nil, nil)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewSignatureType",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "recv", varPtr),
				types.NewVar(token.NoPos, nil, "recvTypeParams", typeParamSlice),
				types.NewVar(token.NoPos, nil, "typeParams", typeParamSlice),
				types.NewVar(token.NoPos, nil, "params", tuplePtr),
				types.NewVar(token.NoPos, nil, "results", tuplePtr),
				types.NewVar(token.NoPos, nil, "variadic", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", signaturePtr)), false)))

	// func NewInterfaceType(methods []*Func, embeddeds []Type) *Interface
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewInterfaceType",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "methods", types.NewSlice(funcPtr)),
				types.NewVar(token.NoPos, nil, "embeddeds", types.NewSlice(typeType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ifacePtr)), false)))

	// func NewNamed(obj *TypeName, underlying Type, methods []*Func) *Named
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewNamed",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "obj", typeNamePtr),
				types.NewVar(token.NoPos, nil, "underlying", typeType),
				types.NewVar(token.NoPos, nil, "methods", types.NewSlice(funcPtr))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", namedPtr)), false)))

	// func NewPackage(path, name string) *Package
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewPackage",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))

	// func NewScope(parent *Scope, pos, end token.Pos, comment string) *Scope
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewScope",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "parent", scopePtrT),
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "end", posType),
				types.NewVar(token.NoPos, nil, "comment", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))

	// --- Type utility functions ---

	// func ObjectString(obj Object, qf Qualifier) string
	// type Qualifier = func(*Package) string
	qualifierType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ObjectString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "obj", objectType),
				types.NewVar(token.NoPos, nil, "qf", qualifierType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// func TypeString(typ Type, qf Qualifier) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TypeString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "typ", typeType),
				types.NewVar(token.NoPos, nil, "qf", qualifierType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// func SelectionString(s *Selection, qf Qualifier) string — *Selection opaque
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SelectionString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "s", types.NewPointer(types.NewStruct(nil, nil))),
				types.NewVar(token.NoPos, nil, "qf", qualifierType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// func RelativeTo(pkg *Package) Qualifier
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RelativeTo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pkg", pkgPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", qualifierType)), false)))

	// func WriteType(buf *bytes.Buffer, typ Type, qf Qualifier) — buf simplified to io.Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteType",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "buf", types.NewPointer(types.NewStruct(nil, nil))),
				types.NewVar(token.NoPos, nil, "typ", typeType),
				types.NewVar(token.NoPos, nil, "qf", qualifierType)),
			nil, false)))

	// func WriteSignature(buf *bytes.Buffer, sig *Signature, qf Qualifier)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteSignature",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "buf", types.NewPointer(types.NewStruct(nil, nil))),
				types.NewVar(token.NoPos, nil, "sig", signaturePtr),
				types.NewVar(token.NoPos, nil, "qf", qualifierType)),
			nil, false)))

	// func Id(pkg *Package, name string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Id",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// func LookupFieldOrMethod(T Type, addressable bool, pkg *Package, name string) (obj Object, index []int, indirect bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupFieldOrMethod",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "T", typeType),
				types.NewVar(token.NoPos, nil, "addressable", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "obj", objectType),
				types.NewVar(token.NoPos, nil, "index", types.NewSlice(types.Typ[types.Int])),
				types.NewVar(token.NoPos, nil, "indirect", types.Typ[types.Bool])), false)))

	// func MissingMethod(V Type, T *Interface, static bool) (method *Func, wrongType bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MissingMethod",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "V", typeType),
				types.NewVar(token.NoPos, nil, "T", ifacePtr),
				types.NewVar(token.NoPos, nil, "static", types.Typ[types.Bool])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "method", funcPtr),
				types.NewVar(token.NoPos, nil, "wrongType", types.Typ[types.Bool])), false)))

	// type Selection struct (opaque)
	selectionType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Selection", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(selectionType.Obj())
	selPtr := types.NewPointer(selectionType)
	selRecv := types.NewVar(token.NoPos, nil, "s", selPtr)
	// type SelectionKind int
	selKindType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SelectionKind", nil), types.Typ[types.Int], nil)
	scope.Insert(selKindType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "FieldVal", selKindType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodVal", selKindType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodExpr", selKindType, constant.MakeInt64(2)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Kind",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", selKindType)), false)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Recv",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Obj",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", objectType)), false)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Type",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Int]))), false)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Indirect",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// Add Selections and Scopes and Instances to Info struct - update it
	// Info.Selections map[*ast.SelectorExpr]*Selection  -- we already have Types, Defs, Uses
	// Info.Scopes map[ast.Node]*Scope
	// Info.Implicits map[ast.Node]Object
	// These are already covered by the opaque pattern - for now the existing Info fields suffice

	// type TypeAndValue — add Mode and Value fields (currently only has Type)
	// TypeAndValue.IsVoid, IsType, IsBuiltin, IsValue, IsNil, IsAddressable, IsAssignable, HasOk
	tavRecv := types.NewVar(token.NoPos, nil, "tv", typeAndValueType)
	for _, m := range []string{"IsVoid", "IsType", "IsBuiltin", "IsValue", "IsNil", "IsAddressable", "IsAssignable", "HasOk"} {
		typeAndValueType.AddMethod(types.NewFunc(token.NoPos, pkg, m,
			types.NewSignatureType(tavRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	}

	pkg.MarkComplete()
	return pkg
}

func buildNetHTTPTestPackage() *types.Package {
	pkg := types.NewPackage("net/http/httptest", "httptest")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// http.Handler interface with ServeHTTP(ResponseWriter, *Request)
	// http.ResponseWriter interface { Header(); Write(); WriteHeader() }
	headerMapHT := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))
	rwIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerMapHT)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "WriteHeader",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "statusCode", types.Typ[types.Int])),
				nil, false)),
	}, nil)
	rwIface.Complete()
	reqPtrHandler := types.NewPointer(types.NewStruct(nil, nil)) // simplified *Request
	handlerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ServeHTTP",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "w", rwIface),
					types.NewVar(token.NoPos, nil, "r", reqPtrHandler)),
				nil, false)),
	}, nil)
	handlerIface.Complete()

	// net.Listener interface with Accept, Close, Addr
	netAddrIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Network",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
	}, nil)
	netAddrIface.Complete()
	// net.Conn interface for Accept return
	netConnIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
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
	netConnIface.Complete()
	listenerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Accept",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", netConnIface),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Addr",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", netAddrIface)),
				false)),
	}, nil)
	listenerIface.Complete()

	// *tls.Config (opaque)
	tlsConfigStruct := types.NewStruct(nil, nil)
	tlsConfigPtr := types.NewPointer(tlsConfigStruct)

	// *http.Server (opaque)
	httpServerStruct := types.NewStruct(nil, nil)
	httpServerPtr := types.NewPointer(httpServerStruct)

	// *http.Client (opaque)
	httpClientStruct := types.NewStruct(nil, nil)
	httpClientPtr := types.NewPointer(httpClientStruct)

	// *x509.Certificate (opaque)
	certStruct := types.NewStruct(nil, nil)
	certPtr := types.NewPointer(certStruct)

	// *http.Response (opaque)
	responseStruct := types.NewStruct(nil, nil)
	responsePtr := types.NewPointer(responseStruct)

	// *http.Request (opaque)
	requestStruct := types.NewStruct(nil, nil)
	requestPtr := types.NewPointer(requestStruct)

	// http.Header type (map[string][]string)
	headerType := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))

	// io.Reader interface
	byteSliceHTTPUtil := types.NewSlice(types.Typ[types.Byte])
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceHTTPUtil)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// *bytes.Buffer
	bufferStruct := types.NewStruct(nil, nil)
	bufferPtr := types.NewPointer(bufferStruct)

	// type Server struct
	serverStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "URL", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Listener", listenerIface, false),
		types.NewField(token.NoPos, pkg, "EnableHTTP2", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "TLS", tlsConfigPtr, false),
		types.NewField(token.NoPos, pkg, "Config", httpServerPtr, false),
	}, nil)
	serverType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Server", nil),
		serverStruct, nil)
	scope.Insert(serverType.Obj())
	serverPtr := types.NewPointer(serverType)

	// func NewServer(handler http.Handler) *Server
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewServer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "handler", handlerIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", serverPtr)),
			false)))

	// func NewTLSServer(handler http.Handler) *Server
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTLSServer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "handler", handlerIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", serverPtr)),
			false)))

	// func NewUnstartedServer(handler http.Handler) *Server
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewUnstartedServer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "handler", handlerIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", serverPtr)),
			false)))

	// Server methods
	srvRecv := types.NewVar(token.NoPos, nil, "s", serverPtr)
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(srvRecv, nil, nil, nil, nil, false)))

	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "CloseClientConnections",
		types.NewSignatureType(srvRecv, nil, nil, nil, nil, false)))

	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Start",
		types.NewSignatureType(srvRecv, nil, nil, nil, nil, false)))

	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "StartTLS",
		types.NewSignatureType(srvRecv, nil, nil, nil, nil, false)))

	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Client",
		types.NewSignatureType(srvRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", httpClientPtr)),
			false)))

	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Certificate",
		types.NewSignatureType(srvRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", certPtr)),
			false)))

	// type ResponseRecorder struct
	recorderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Code", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "HeaderMap", headerType, false),
		types.NewField(token.NoPos, pkg, "Body", bufferPtr, false),
		types.NewField(token.NoPos, pkg, "Flushed", types.Typ[types.Bool], false),
	}, nil)
	recorderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ResponseRecorder", nil),
		recorderStruct, nil)
	scope.Insert(recorderType.Obj())
	recorderPtr := types.NewPointer(recorderType)

	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRecorder",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", recorderPtr)),
			false)))

	// ResponseRecorder methods
	rwRecv := types.NewVar(token.NoPos, nil, "rw", recorderPtr)
	recorderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Header",
		types.NewSignatureType(rwRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", headerType)),
			false)))

	recorderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(rwRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "buf", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	recorderType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteString",
		types.NewSignatureType(rwRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "str", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	recorderType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteHeader",
		types.NewSignatureType(rwRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "code", types.Typ[types.Int])),
			nil, false)))

	recorderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(rwRecv, nil, nil, nil, nil, false)))

	recorderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Result",
		types.NewSignatureType(rwRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", responsePtr)),
			false)))

	// func NewRequest(method, target string, body io.Reader) *http.Request
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRequest",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "method", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "target", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "body", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", requestPtr)),
			false)))

	// NewRequestWithContext(ctx context.Context, method, target string, body io.Reader) *http.Request
	ctxIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Deadline",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "deadline", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
				false)),
		types.NewFunc(token.NoPos, nil, "Done",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewChan(types.RecvOnly, types.NewStruct(nil, nil)))),
				false)),
		types.NewFunc(token.NoPos, nil, "Err",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Value",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.NewInterfaceType(nil, nil))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
				false)),
	}, nil)
	ctxIface.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRequestWithContext",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIface),
				types.NewVar(token.NoPos, pkg, "method", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "target", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "body", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", requestPtr)),
			false)))

	// DefaultRemoteAddr constant
	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultRemoteAddr",
		types.Typ[types.String], constant.MakeString("1.2.3.4")))

	pkg.MarkComplete()
	return pkg
}

func buildTestingFstestPackage() *types.Package {
	pkg := types.NewPackage("testing/fstest", "fstest")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type MapFile struct
	mapFileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Data", types.NewSlice(types.Typ[types.Byte]), false),
		types.NewField(token.NoPos, pkg, "Mode", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "ModTime", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Sys", types.NewInterfaceType(nil, nil), false),
	}, nil)
	mapFileType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "MapFile", nil),
		mapFileStruct, nil)
	scope.Insert(mapFileType.Obj())

	// type MapFS map[string]*MapFile
	mapFSType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "MapFS", nil),
		types.NewMap(types.Typ[types.String], types.NewPointer(mapFileType)), nil)
	scope.Insert(mapFSType.Obj())

	// fs.FileMode stand-in
	fileModeFS := types.Typ[types.Uint32]
	anyFS := types.NewInterfaceType(nil, nil)
	anyFS.Complete()

	// fs.FileInfo interface { Name() string; Size() int64; Mode() FileMode; ModTime() int64; IsDir() bool; Sys() any }
	fileInfoIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, nil, "Mode",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", fileModeFS)), false)),
		types.NewFunc(token.NoPos, nil, "ModTime",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, nil, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Sys",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyFS)), false)),
	}, nil)
	fileInfoIface.Complete()

	// fs.DirEntry interface { Name() string; IsDir() bool; Type() FileMode; Info() (FileInfo, error) }
	dirEntryIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Type",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", fileModeFS)), false)),
		types.NewFunc(token.NoPos, nil, "Info",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fileInfoIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	dirEntryIface.Complete()

	// fs.File interface { Stat() (FileInfo, error); Read([]byte) (int, error); Close() error }
	fsFileIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Stat",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fileInfoIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	fsFileIface.Complete()

	// fs.FS interface { Open(name string) (File, error) }
	fsIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fsFileIface),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	fsIface.Complete()

	// MapFS.Open(name string) (fs.File, error)
	mapFSType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "fsys", mapFSType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", fsFileIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// MapFS.ReadFile(name string) ([]byte, error)
	mapFSType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadFile",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "fsys", mapFSType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// MapFS.Stat(name string) (fs.FileInfo, error)
	mapFSType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stat",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "fsys", mapFSType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", fileInfoIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// MapFS.ReadDir(name string) ([]fs.DirEntry, error)
	mapFSType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadDir",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "fsys", mapFSType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(dirEntryIface)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// MapFS.Sub(dir string) (fs.FS, error)
	mapFSType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sub",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "fsys", mapFSType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", fsIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func TestFS(fsys fs.FS, expected ...string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TestFS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fsys", fsIface),
				types.NewVar(token.NoPos, pkg, "expected", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	pkg.MarkComplete()
	return pkg
}

func buildTestingIotestPackage() *types.Package {
	pkg := types.NewPackage("testing/iotest", "iotest")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
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

	// io.Writer interface
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

	// func ErrReader(err error) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ErrReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// func TestReader(r io.Reader, content []byte) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TestReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", ioReader),
				types.NewVar(token.NoPos, pkg, "content", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func HalfReader(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HalfReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// func DataErrReader(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DataErrReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// func OneByteReader(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OneByteReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// func TimeoutReader(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TimeoutReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// func TruncateWriter(w io.Writer, n int64) io.Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TruncateWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioWriter)),
			false)))

	// func NewReadLogger(prefix string, r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReadLogger",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// func NewWriteLogger(prefix string, w io.Writer) io.Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriteLogger",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "w", ioWriter)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioWriter)),
			false)))

	// var ErrTimeout error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrTimeout", errType))

	pkg.MarkComplete()
	return pkg
}

// debug/* packages — minimal stubs

func buildDebugElfPackage() *types.Package {
	pkg := types.NewPackage("debug/elf", "elf")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// Type aliases for ELF header fields
	for _, name := range []string{"Class", "Data", "OSABI", "Type", "Machine"} {
		t := types.NewNamed(types.NewTypeName(token.NoPos, pkg, name, nil), types.Typ[types.Int], nil)
		t.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "i", t), nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
		scope.Insert(t.Obj())
	}

	// Section type enums
	sectionTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SectionType", nil), types.Typ[types.Uint32], nil)
	scope.Insert(sectionTypeType.Obj())
	sectionFlagType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SectionFlag", nil), types.Typ[types.Uint32], nil)
	scope.Insert(sectionFlagType.Obj())
	progTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ProgType", nil), types.Typ[types.Int], nil)
	scope.Insert(progTypeType.Obj())
	progFlagType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ProgFlag", nil), types.Typ[types.Uint32], nil)
	scope.Insert(progFlagType.Obj())
	symBindType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SymBind", nil), types.Typ[types.Int], nil)
	scope.Insert(symBindType.Obj())
	symTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SymType", nil), types.Typ[types.Int], nil)
	scope.Insert(symTypeType.Obj())
	symVisType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SymVis", nil), types.Typ[types.Int], nil)
	scope.Insert(symVisType.Obj())

	// type SectionHeader struct
	sectionHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Type", sectionTypeType, false),
		types.NewField(token.NoPos, pkg, "Flags", sectionFlagType, false),
		types.NewField(token.NoPos, pkg, "Addr", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Link", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Info", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Addralign", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Entsize", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "FileSize", types.Typ[types.Uint64], false),
	}, nil)
	sectionHeaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SectionHeader", nil), sectionHeaderStruct, nil)
	scope.Insert(sectionHeaderType.Obj())

	// type Section struct { SectionHeader; ... }
	sectionStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "SectionHeader", sectionHeaderType, true),
	}, nil)
	sectionType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Section", nil), sectionStruct, nil)
	scope.Insert(sectionType.Obj())
	sectionPtr := types.NewPointer(sectionType)
	sectionRecv := types.NewVar(token.NoPos, nil, "s", sectionPtr)
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Data",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice), types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Open returns io.ReadSeeker { Read([]byte) (int, error); Seek(int64, int) (int64, error) }
	ioReaderOpen := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Seek",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioReaderOpen.Complete()
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ioReaderOpen)), false)))

	// type Symbol struct
	symbolStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Info", types.Typ[types.Byte], false),
		types.NewField(token.NoPos, pkg, "Other", types.Typ[types.Byte], false),
		types.NewField(token.NoPos, pkg, "Section", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Library", types.Typ[types.String], false),
	}, nil)
	symbolType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Symbol", nil), symbolStruct, nil)
	scope.Insert(symbolType.Obj())

	// type Prog struct
	progHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Type", progTypeType, false),
		types.NewField(token.NoPos, pkg, "Flags", progFlagType, false),
		types.NewField(token.NoPos, pkg, "Off", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Vaddr", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Paddr", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Filesz", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Memsz", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Align", types.Typ[types.Uint64], false),
	}, nil)
	progHeaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ProgHeader", nil), progHeaderStruct, nil)
	scope.Insert(progHeaderType.Obj())

	progStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ProgHeader", progHeaderType, true),
	}, nil)
	progType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Prog", nil), progStruct, nil)
	scope.Insert(progType.Obj())

	// type FileHeader struct
	fileHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Class", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Data", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "OSABI", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "ABIVersion", types.Typ[types.Byte], false),
		types.NewField(token.NoPos, pkg, "Type", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Machine", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Entry", types.Typ[types.Uint64], false),
	}, nil)
	fileHeaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FileHeader", nil), fileHeaderStruct, nil)
	scope.Insert(fileHeaderType.Obj())

	// type File struct
	fileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "FileHeader", fileHeaderType, true),
		types.NewField(token.NoPos, pkg, "Sections", types.NewSlice(sectionPtr), false),
		types.NewField(token.NoPos, pkg, "Progs", types.NewSlice(types.NewPointer(progType)), false),
	}, nil)
	fileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "File", nil), fileStruct, nil)
	scope.Insert(fileType.Obj())
	filePtr := types.NewPointer(fileType)
	fileRecv := types.NewVar(token.NoPos, nil, "f", filePtr)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Section",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", sectionPtr)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Symbols",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(symbolType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "DynamicSymbols",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(symbolType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// type ImportedSymbol struct { Name, Version, Library string }
	importedSymStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Library", types.Typ[types.String], false),
	}, nil)
	importedSymType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ImportedSymbol", nil), importedSymStruct, nil)
	scope.Insert(importedSymType.Obj())

	// *dwarf.Data opaque pointer stand-in
	dwarfDataPtrElf := types.NewPointer(types.NewStruct(nil, nil))

	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportedSymbols",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(importedSymType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportedLibraries",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "DWARF",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", dwarfDataPtrElf),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func Open(name string) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.ReaderAt interface for NewFile
	readerAtIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSlice),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerAtIface.Complete()

	// func NewFile(r io.ReaderAt) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerAtIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Some ELF constants
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"ELFCLASS32", 1}, {"ELFCLASS64", 2},
		{"ELFDATA2LSB", 1}, {"ELFDATA2MSB", 2},
		{"ET_NONE", 0}, {"ET_REL", 1}, {"ET_EXEC", 2}, {"ET_DYN", 3}, {"ET_CORE", 4},
		{"EM_386", 3}, {"EM_ARM", 40}, {"EM_X86_64", 62}, {"EM_AARCH64", 183}, {"EM_RISCV", 243},
		{"SHT_NULL", 0}, {"SHT_PROGBITS", 1}, {"SHT_SYMTAB", 2}, {"SHT_STRTAB", 3},
		{"SHT_NOTE", 7}, {"SHT_NOBITS", 8}, {"SHT_DYNSYM", 11},
		{"SHF_WRITE", 1}, {"SHF_ALLOC", 2}, {"SHF_EXECINSTR", 4},
		{"PT_NULL", 0}, {"PT_LOAD", 1}, {"PT_DYNAMIC", 2}, {"PT_INTERP", 3}, {"PT_NOTE", 4},
		{"STB_LOCAL", 0}, {"STB_GLOBAL", 1}, {"STB_WEAK", 2},
		{"STT_NOTYPE", 0}, {"STT_OBJECT", 1}, {"STT_FUNC", 2}, {"STT_SECTION", 3}, {"STT_FILE", 4},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, types.Typ[types.Int], constant.MakeInt64(c.val)))
	}

	// FormatError
	formatErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FormatError", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Msg", types.Typ[types.String], false),
		}, nil), nil)
	formatErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(formatErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(formatErrType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildDebugDwarfPackage() *types.Package {
	pkg := types.NewPackage("debug/dwarf", "dwarf")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Tag uint32
	tagType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Tag", nil), types.Typ[types.Uint32], nil)
	scope.Insert(tagType.Obj())
	tagType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "t", tagType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Attr uint32
	attrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Attr", nil), types.Typ[types.Uint32], nil)
	scope.Insert(attrType.Obj())
	attrType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "a", attrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// Some common tag/attr constants
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"TagCompileUnit", 0x11}, {"TagSubprogram", 0x2e}, {"TagVariable", 0x34},
		{"TagFormalParameter", 0x05}, {"TagMember", 0x0d}, {"TagBaseType", 0x24},
		{"TagStructType", 0x13}, {"TagTypedef", 0x16}, {"TagPointerType", 0x0f},
		{"AttrName", 0x03}, {"AttrType", 0x49}, {"AttrByteSize", 0x0b},
		{"AttrLocation", 0x02}, {"AttrLowpc", 0x11}, {"AttrHighpc", 0x12},
		{"AttrLanguage", 0x13}, {"AttrCompDir", 0x1b},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, types.Typ[types.Int], constant.MakeInt64(c.val)))
	}

	// type Offset uint32
	offsetType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Offset", nil), types.Typ[types.Uint32], nil)
	scope.Insert(offsetType.Obj())

	// type Field struct { Attr Attr; Val interface{}; Class Class }
	fieldStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Attr", attrType, false),
		types.NewField(token.NoPos, pkg, "Val", types.NewInterfaceType(nil, nil), false),
		types.NewField(token.NoPos, pkg, "Class", types.Typ[types.Int], false),
	}, nil)
	fieldType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Field", nil), fieldStruct, nil)
	scope.Insert(fieldType.Obj())

	// type Entry struct
	entryStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Offset", offsetType, false),
		types.NewField(token.NoPos, pkg, "Tag", tagType, false),
		types.NewField(token.NoPos, pkg, "Children", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Field", types.NewSlice(fieldType), false),
	}, nil)
	entryType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Entry", nil), entryStruct, nil)
	scope.Insert(entryType.Obj())
	entryPtr := types.NewPointer(entryType)
	entryRecv := types.NewVar(token.NoPos, nil, "e", entryPtr)
	entryType.AddMethod(types.NewFunc(token.NoPos, pkg, "Val",
		types.NewSignatureType(entryRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "a", attrType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)))
	entryType.AddMethod(types.NewFunc(token.NoPos, pkg, "AttrField",
		types.NewSignatureType(entryRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "a", attrType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(fieldType))), false)))

	// type Reader struct (opaque)
	readerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Reader", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(readerType.Obj())
	readerPtr := types.NewPointer(readerType)
	readerRecv := types.NewVar(token.NoPos, nil, "r", readerPtr)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(readerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", entryPtr), types.NewVar(token.NoPos, nil, "", errType)), false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seek",
		types.NewSignatureType(readerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "off", offsetType)), nil, false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "SkipChildren",
		types.NewSignatureType(readerRecv, nil, nil, nil, nil, false)))

	// type LineReader struct (opaque)
	lineReaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "LineReader", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(lineReaderType.Obj())

	// type LineFile struct { Name string; Mtime uint64; Length int }
	lineFileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Mtime", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Length", types.Typ[types.Int], false),
	}, nil)
	lineFileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "LineFile", nil), lineFileStruct, nil)
	scope.Insert(lineFileType.Obj())

	// type LineEntry struct
	lineEntryStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Address", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "File", types.NewPointer(lineFileType), false),
		types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Column", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "IsStmt", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "EndSequence", types.Typ[types.Bool], false),
	}, nil)
	lineEntryType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "LineEntry", nil), lineEntryStruct, nil)
	scope.Insert(lineEntryType.Obj())

	lineReaderPtr := types.NewPointer(lineReaderType)
	lineReaderRecv := types.NewVar(token.NoPos, nil, "r", lineReaderPtr)
	lineReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(lineReaderRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "entry", types.NewPointer(lineEntryType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	lineReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(lineReaderRecv, nil, nil, nil, nil, false)))

	// type CommonType struct { ByteSize int64; Name string }
	commonTypeStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ByteSize", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
	}, nil)
	commonTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CommonType", nil), commonTypeStruct, nil)
	scope.Insert(commonTypeType.Obj())
	commonTypePtr := types.NewPointer(commonTypeType)

	// type Type interface { Common() *CommonType; String() string; Size() int64 }
	typeIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Common",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", commonTypePtr)), false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
	}, nil)
	typeIface.Complete()
	dwarfTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Type", nil), typeIface, nil)
	scope.Insert(dwarfTypeType.Obj())

	// type Data struct (opaque)
	dataType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Data", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(dataType.Obj())
	dataPtr := types.NewPointer(dataType)
	dataRecv := types.NewVar(token.NoPos, nil, "d", dataPtr)
	dataType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reader",
		types.NewSignatureType(dataRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", readerPtr)), false)))
	dataType.AddMethod(types.NewFunc(token.NoPos, pkg, "Type",
		types.NewSignatureType(dataRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "off", offsetType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", dwarfTypeType), types.NewVar(token.NoPos, nil, "", errType)), false)))
	dataType.AddMethod(types.NewFunc(token.NoPos, pkg, "LineReader",
		types.NewSignatureType(dataRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "cu", entryPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", lineReaderPtr), types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func New(abbrev, aranges, frame, info, line, pubnames, ranges, str []byte) (*Data, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "abbrev", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "aranges", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "frame", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "info", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "line", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "pubnames", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "ranges", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "str", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", dataPtr), types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildDebugPEPackage() *types.Package {
	pkg := types.NewPackage("debug/pe", "pe")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type FileHeader struct
	fileHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Machine", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "NumberOfSections", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "TimeDateStamp", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "PointerToSymbolTable", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "NumberOfSymbols", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "SizeOfOptionalHeader", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "Characteristics", types.Typ[types.Uint16], false),
	}, nil)
	fileHeaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FileHeader", nil), fileHeaderStruct, nil)
	scope.Insert(fileHeaderType.Obj())

	// type SectionHeader32 struct
	sectionHeader32Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.NewArray(types.Typ[types.Uint8], 8), false),
		types.NewField(token.NoPos, pkg, "VirtualSize", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "VirtualAddress", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "SizeOfRawData", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "PointerToRawData", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Characteristics", types.Typ[types.Uint32], false),
	}, nil)
	sectionHeader32Type := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SectionHeader32", nil), sectionHeader32Struct, nil)
	scope.Insert(sectionHeader32Type.Obj())

	// type Section struct
	sectionStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "VirtualSize", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "VirtualAddress", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Characteristics", types.Typ[types.Uint32], false),
	}, nil)
	sectionType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Section", nil), sectionStruct, nil)
	scope.Insert(sectionType.Obj())
	sectionPtr := types.NewPointer(sectionType)
	sectionRecv := types.NewVar(token.NoPos, nil, "s", sectionPtr)
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Data",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Open returns io.ReadSeeker { Read([]byte) (int, error); Seek(int64, int) (int64, error) }
	ioReaderOpen := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Seek",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioReaderOpen.Complete()
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ioReaderOpen)), false)))

	// type Symbol struct
	symbolStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "SectionNumber", types.Typ[types.Int16], false),
		types.NewField(token.NoPos, pkg, "Type", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "StorageClass", types.Typ[types.Uint8], false),
	}, nil)
	symbolType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Symbol", nil), symbolStruct, nil)
	scope.Insert(symbolType.Obj())

	// type File struct
	fileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "FileHeader", fileHeaderType, true),
		types.NewField(token.NoPos, pkg, "OptionalHeader", types.NewInterfaceType(nil, nil), false),
		types.NewField(token.NoPos, pkg, "Sections", types.NewSlice(sectionPtr), false),
		types.NewField(token.NoPos, pkg, "Symbols", types.NewSlice(types.NewPointer(symbolType)), false),
	}, nil)
	fileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "File", nil), fileStruct, nil)
	scope.Insert(fileType.Obj())
	filePtr := types.NewPointer(fileType)
	fileRecv := types.NewVar(token.NoPos, nil, "f", filePtr)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Section",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", sectionPtr)), false)))
	// *dwarf.Data opaque pointer stand-in
	dwarfDataPtrPE := types.NewPointer(types.NewStruct(nil, nil))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "DWARF",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", dwarfDataPtrPE),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportedSymbols",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportedLibraries",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func Open(name string) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.ReaderAt interface for NewFile
	byteSlicePE := types.NewSlice(types.Typ[types.Byte])
	readerAtIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSlicePE),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerAtIface.Complete()

	// func NewFile(r io.ReaderAt) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerAtIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Machine constants
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"IMAGE_FILE_MACHINE_UNKNOWN", 0}, {"IMAGE_FILE_MACHINE_AM33", 0x1d3},
		{"IMAGE_FILE_MACHINE_AMD64", 0x8664}, {"IMAGE_FILE_MACHINE_ARM", 0x1c0},
		{"IMAGE_FILE_MACHINE_ARM64", 0xaa64}, {"IMAGE_FILE_MACHINE_I386", 0x14c},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, types.Typ[types.Uint16], constant.MakeInt64(c.val)))
	}

	pkg.MarkComplete()
	return pkg
}

func buildDebugMachoPackage() *types.Package {
	pkg := types.NewPackage("debug/macho", "macho")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Cpu uint32
	cpuType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Cpu", nil), types.Typ[types.Uint32], nil)
	scope.Insert(cpuType.Obj())
	cpuType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "i", cpuType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"Cpu386", 7}, {"CpuAmd64", 0x01000007}, {"CpuArm", 12}, {"CpuArm64", 0x0100000c}, {"CpuPpc", 18}, {"CpuPpc64", 0x01000012},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, cpuType, constant.MakeInt64(c.val)))
	}

	// type Type uint32
	typeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Type", nil), types.Typ[types.Uint32], nil)
	scope.Insert(typeType.Obj())
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"TypeObj", 1}, {"TypeExec", 2}, {"TypeDylib", 6}, {"TypeBundle", 8},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, typeType, constant.MakeInt64(c.val)))
	}

	// type Section struct
	sectionStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Seg", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Addr", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Align", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Reloff", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Nreloc", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Flags", types.Typ[types.Uint32], false),
	}, nil)
	sectionType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Section", nil), sectionStruct, nil)
	scope.Insert(sectionType.Obj())
	sectionPtr := types.NewPointer(sectionType)
	sectionRecv := types.NewVar(token.NoPos, nil, "s", sectionPtr)
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Data",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Open returns io.ReadSeeker { Read([]byte) (int, error); Seek(int64, int) (int64, error) }
	ioReaderOpen := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Seek",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioReaderOpen.Complete()
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ioReaderOpen)), false)))

	// type Symbol struct
	symbolStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Type", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Sect", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Desc", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.Uint64], false),
	}, nil)
	symbolType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Symbol", nil), symbolStruct, nil)
	scope.Insert(symbolType.Obj())

	// type Segment struct
	segmentStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Addr", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Memsz", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Filesz", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Maxprot", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Prot", types.Typ[types.Uint32], false),
	}, nil)
	segmentType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Segment", nil), segmentStruct, nil)
	scope.Insert(segmentType.Obj())

	// type FileHeader struct
	fileHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Magic", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Cpu", cpuType, false),
		types.NewField(token.NoPos, pkg, "SubCpu", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Type", typeType, false),
		types.NewField(token.NoPos, pkg, "Flags", types.Typ[types.Uint32], false),
	}, nil)
	fileHeaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FileHeader", nil), fileHeaderStruct, nil)
	scope.Insert(fileHeaderType.Obj())

	// type Symtab struct { Syms []Symbol } (simplified)
	symtabStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Syms", types.NewSlice(symbolType), false),
	}, nil)
	symtabType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Symtab", nil), symtabStruct, nil)
	scope.Insert(symtabType.Obj())

	// Load interface { Raw() []byte }
	loadIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Raw",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte]))),
				false)),
	}, nil)
	loadIface.Complete()
	loadType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Load", nil), loadIface, nil)
	scope.Insert(loadType.Obj())

	// *dwarf.Data opaque pointer stand-in
	dwarfDataPtrMacho := types.NewPointer(types.NewStruct(nil, nil))

	// type File struct
	fileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "FileHeader", fileHeaderType, true),
		types.NewField(token.NoPos, pkg, "Sections", types.NewSlice(sectionPtr), false),
		types.NewField(token.NoPos, pkg, "Symtab", types.NewPointer(symtabType), false),
		types.NewField(token.NoPos, pkg, "Loads", types.NewSlice(loadType), false),
	}, nil)
	fileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "File", nil), fileStruct, nil)
	scope.Insert(fileType.Obj())
	filePtr := types.NewPointer(fileType)
	fileRecv := types.NewVar(token.NoPos, nil, "f", filePtr)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Section",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", sectionPtr)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Segment",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(segmentType))), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "DWARF",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", dwarfDataPtrMacho),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportedSymbols",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportedLibraries",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func Open(name string) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.ReaderAt interface for NewFile
	byteSliceMacho := types.NewSlice(types.Typ[types.Byte])
	readerAtMacho := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSliceMacho),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerAtMacho.Complete()

	// func NewFile(r io.ReaderAt) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerAtMacho)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Magic constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "Magic32", types.Typ[types.Uint32], constant.MakeUint64(0xfeedface)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Magic64", types.Typ[types.Uint32], constant.MakeUint64(0xfeedfacf)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MagicFat", types.Typ[types.Uint32], constant.MakeUint64(0xcafebabe)))

	pkg.MarkComplete()
	return pkg
}

func buildDebugGosymPackage() *types.Package {
	pkg := types.NewPackage("debug/gosym", "gosym")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Sym struct { Value uint64; Type byte; Name string; GoType uint64; Func *Func }
	// Forward declare Func
	funcType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Func", nil), types.NewStruct(nil, nil), nil)

	symStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Type", types.Typ[types.Byte], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "GoType", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Func", types.NewPointer(funcType), false),
	}, nil)
	symType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Sym", nil), symStruct, nil)
	scope.Insert(symType.Obj())

	// type Obj struct { Funcs []Func; Paths []Sym }
	objStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Funcs", types.NewSlice(funcType), false),
	}, nil)
	objType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Obj", nil), objStruct, nil)
	scope.Insert(objType.Obj())

	// Now set up Func struct properly
	funcStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Sym", symType, true),
		types.NewField(token.NoPos, pkg, "End", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Obj", types.NewPointer(objType), false),
	}, nil)
	funcType.SetUnderlying(funcStruct)
	scope.Insert(funcType.Obj())

	// type Table struct
	tableStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Syms", types.NewSlice(symType), false),
		types.NewField(token.NoPos, pkg, "Funcs", types.NewSlice(funcType), false),
		types.NewField(token.NoPos, pkg, "Files", types.NewMap(types.Typ[types.String], types.NewPointer(objType)), false),
		types.NewField(token.NoPos, pkg, "Objs", types.NewSlice(objType), false),
	}, nil)
	tableType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Table", nil), tableStruct, nil)
	scope.Insert(tableType.Obj())
	tablePtr := types.NewPointer(tableType)
	tableRecv := types.NewVar(token.NoPos, nil, "t", tablePtr)
	tableType.AddMethod(types.NewFunc(token.NoPos, pkg, "PCToFunc",
		types.NewSignatureType(tableRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pc", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(funcType))), false)))
	tableType.AddMethod(types.NewFunc(token.NoPos, pkg, "PCToLine",
		types.NewSignatureType(tableRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pc", types.Typ[types.Uint64])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", types.NewPointer(funcType))), false)))
	tableType.AddMethod(types.NewFunc(token.NoPos, pkg, "LineToPC",
		types.NewSignatureType(tableRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "file", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "line", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, nil, "", types.NewPointer(funcType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	tableType.AddMethod(types.NewFunc(token.NoPos, pkg, "LookupSym",
		types.NewSignatureType(tableRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(symType))), false)))
	tableType.AddMethod(types.NewFunc(token.NoPos, pkg, "LookupFunc",
		types.NewSignatureType(tableRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(funcType))), false)))

	// type LineTable struct (opaque)
	lineTableType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "LineTable", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(lineTableType.Obj())

	// func NewTable(symtab []byte, pcln *LineTable) (*Table, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTable",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "symtab", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "pcln", types.NewPointer(lineTableType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tablePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewLineTable(data []byte, text uint64) *LineTable
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewLineTable",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "text", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(lineTableType))),
			false)))

	// type UnknownFileError string
	unknownFileErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UnknownFileError", nil), types.Typ[types.String], nil)
	unknownFileErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownFileErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(unknownFileErrType.Obj())

	// type UnknownLineError struct
	unknownLineErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UnknownLineError", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "File", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
		}, nil), nil)
	unknownLineErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(unknownLineErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(unknownLineErrType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildDebugPlan9objPackage() *types.Package {
	pkg := types.NewPackage("debug/plan9obj", "plan9obj")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type FileHeader struct
	fileHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Magic", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Bss", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Entry", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "PtrSize", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "LoadAddress", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "HdrSize", types.Typ[types.Uint64], false),
	}, nil)
	fileHeaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FileHeader", nil), fileHeaderStruct, nil)
	scope.Insert(fileHeaderType.Obj())

	// type Section struct
	sectionStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Uint32], false),
	}, nil)
	sectionType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Section", nil), sectionStruct, nil)
	scope.Insert(sectionType.Obj())
	sectionPtr := types.NewPointer(sectionType)
	sectionRecv := types.NewVar(token.NoPos, nil, "s", sectionPtr)
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Data",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Open returns io.ReadSeeker { Read([]byte) (int, error); Seek(int64, int) (int64, error) }
	ioReaderOpen := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Seek",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioReaderOpen.Complete()
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ioReaderOpen)), false)))

	// type Sym struct
	symStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Type", types.Typ[types.Rune], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
	}, nil)
	symType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Sym", nil), symStruct, nil)
	scope.Insert(symType.Obj())

	// type File struct
	fileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "FileHeader", fileHeaderType, true),
		types.NewField(token.NoPos, pkg, "Sections", types.NewSlice(sectionPtr), false),
	}, nil)
	fileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "File", nil), fileStruct, nil)
	scope.Insert(fileType.Obj())
	filePtr := types.NewPointer(fileType)
	fileRecv := types.NewVar(token.NoPos, nil, "f", filePtr)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Section",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", sectionPtr)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Symbols",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(symType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func Open(name string) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.ReaderAt interface for NewFile
	byteSliceP9 := types.NewSlice(types.Typ[types.Byte])
	readerAtP9 := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSliceP9),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerAtP9.Complete()

	// func NewFile(r io.ReaderAt) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerAtP9)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Magic constants
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"Magic386", 0x01EB}, {"MagicAMD64", 0x8A97}, {"MagicARM", 0x0104},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, types.Typ[types.Uint32], constant.MakeInt64(c.val)))
	}

	pkg.MarkComplete()
	return pkg
}

func buildSyncErrgroupPackage() *types.Package {
	pkg := types.NewPackage("sync/errgroup", "errgroup")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Group struct
	groupType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Group", nil), types.NewStruct(nil, nil), nil)
	groupPtr := types.NewPointer(groupType)
	scope.Insert(groupType.Obj())

	groupRecv := types.NewVar(token.NoPos, pkg, "g", groupPtr)

	// func (g *Group) Go(f func() error)
	groupType.AddMethod(types.NewFunc(token.NoPos, pkg, "Go",
		types.NewSignatureType(groupRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
					false))),
			nil, false)))

	// func (g *Group) Wait() error
	groupType.AddMethod(types.NewFunc(token.NoPos, pkg, "Wait",
		types.NewSignatureType(groupRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (g *Group) SetLimit(n int)
	groupType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetLimit",
		types.NewSignatureType(groupRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			nil, false)))

	// func (g *Group) TryGo(f func() error) bool
	groupType.AddMethod(types.NewFunc(token.NoPos, pkg, "TryGo",
		types.NewSignatureType(groupRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
					false))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func WithContext(ctx context.Context) (*Group, context.Context)
	// context.Context stand-in { Deadline(); Done(); Err(); Value() }
	anyCtxEG := types.NewInterfaceType(nil, nil)
	anyCtxEG.Complete()
	ctxType := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Deadline",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "deadline", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
				false)),
		types.NewFunc(token.NoPos, nil, "Done",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "",
					types.NewChan(types.RecvOnly, types.NewStruct(nil, nil)))),
				false)),
		types.NewFunc(token.NoPos, nil, "Err",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Value",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyCtxEG)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyCtxEG)),
				false)),
	}, nil)
	ctxType.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithContext",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ctx", ctxType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", groupPtr),
				types.NewVar(token.NoPos, pkg, "", ctxType)),
			false)))

	pkg.MarkComplete()
	return pkg
}
