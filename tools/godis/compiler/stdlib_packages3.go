package compiler

// stdlib_packages3.go — additional stdlib package type stubs.

import (
	"go/constant"
	"go/token"
	"go/types"
)

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

func buildCryptoDESPackage() *types.Package {
	pkg := types.NewPackage("crypto/des", "des")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// cipher.Block interface (local stand-in)
	cipherBlock := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, nil, "Encrypt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", byteSlice),
					types.NewVar(token.NoPos, nil, "src", byteSlice)),
				nil, false)),
		types.NewFunc(token.NoPos, nil, "Decrypt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", byteSlice),
					types.NewVar(token.NoPos, nil, "src", byteSlice)),
				nil, false)),
	}, nil)
	cipherBlock.Complete()

	// type KeySizeError int
	keySizeErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "KeySizeError", nil),
		types.Typ[types.Int], nil)
	keySizeErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", keySizeErrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(keySizeErrType.Obj())

	// const BlockSize = 8
	scope.Insert(types.NewConst(token.NoPos, pkg, "BlockSize", types.Typ[types.Int], constant.MakeInt64(8)))

	// func NewCipher(key []byte) (cipher.Block, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewCipher",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", cipherBlock),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewTripleDESCipher(key []byte) (cipher.Block, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTripleDESCipher",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", cipherBlock),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildCryptoRC4Package() *types.Package {
	pkg := types.NewPackage("crypto/rc4", "rc4")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type Cipher struct { ... }
	cipherStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "s", types.Typ[types.Int], false),
	}, nil)
	cipherType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Cipher", nil),
		cipherStruct, nil)
	scope.Insert(cipherType.Obj())
	cipherPtr := types.NewPointer(cipherType)

	// func NewCipher(key []byte) (*Cipher, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewCipher",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", cipherPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// (*Cipher).XORKeyStream(dst, src []byte)
	cipherType.AddMethod(types.NewFunc(token.NoPos, pkg, "XORKeyStream",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", cipherPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", byteSlice),
				types.NewVar(token.NoPos, nil, "src", byteSlice)),
			nil, false)))

	// (*Cipher).Reset()
	cipherType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", cipherPtr),
			nil, nil, nil, nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildSyscallPackage() *types.Package {
	pkg := types.NewPackage("syscall", "syscall")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()

	// type Errno uintptr — implements error
	errnoType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Errno", nil),
		types.Typ[types.Uintptr], nil)
	scope.Insert(errnoType.Obj())

	// type Signal int
	signalType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Signal", nil),
		types.Typ[types.Int], nil)
	scope.Insert(signalType.Obj())

	// Errno methods
	errnoRecv := types.NewVar(token.NoPos, nil, "e", errnoType)
	errnoType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(errnoRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	errnoType.AddMethod(types.NewFunc(token.NoPos, pkg, "Is",
		types.NewSignatureType(errnoRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "target", errType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	errnoType.AddMethod(types.NewFunc(token.NoPos, pkg, "Temporary",
		types.NewSignatureType(errnoRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	errnoType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(errnoRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// Signal methods
	sigRecv := types.NewVar(token.NoPos, nil, "s", signalType)
	signalType.AddMethod(types.NewFunc(token.NoPos, pkg, "Signal",
		types.NewSignatureType(sigRecv, nil, nil, nil, nil, false)))
	signalType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(sigRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Credential struct { Uid, Gid uint32; Groups []uint32; NoSetGroups bool }
	credentialStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Uid", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Gid", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Groups", types.NewSlice(types.Typ[types.Uint32]), false),
		types.NewField(token.NoPos, pkg, "NoSetGroups", types.Typ[types.Bool], false),
	}, nil)
	credentialType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Credential", nil),
		credentialStruct, nil)
	scope.Insert(credentialType.Obj())

	// type SysProcAttr struct { ... }
	sysProcAttrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Chroot", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Credential", types.NewPointer(credentialType), false),
		types.NewField(token.NoPos, pkg, "Ptrace", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Setsid", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Setpgid", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Setctty", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Noctty", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Ctty", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Foreground", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Pgid", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Pdeathsig", signalType, false),
		types.NewField(token.NoPos, pkg, "Cloneflags", types.Typ[types.Uintptr], false),
		types.NewField(token.NoPos, pkg, "UidMappings", types.NewSlice(types.NewStruct(nil, nil)), false),
		types.NewField(token.NoPos, pkg, "GidMappings", types.NewSlice(types.NewStruct(nil, nil)), false),
		types.NewField(token.NoPos, pkg, "GidMappingsEnableSetgroups", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "AmbientCaps", types.NewSlice(types.Typ[types.Uintptr]), false),
	}, nil)
	sysProcAttrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SysProcAttr", nil),
		sysProcAttrStruct, nil)
	scope.Insert(sysProcAttrType.Obj())

	// type WaitStatus uint32
	waitStatusType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WaitStatus", nil),
		types.Typ[types.Uint32], nil)
	scope.Insert(waitStatusType.Obj())
	wsRecv := types.NewVar(token.NoPos, nil, "w", waitStatusType)
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "Exited",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExitStatus",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "Signaled",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "Signal",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", signalType)), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stopped",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "StopSignal",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", signalType)), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "CoreDump",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "Continued",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "TrapCause",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// type Rusage struct (simplified)
	rusageStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Utime", types.NewStruct(nil, nil), false),
		types.NewField(token.NoPos, pkg, "Stime", types.NewStruct(nil, nil), false),
		types.NewField(token.NoPos, pkg, "Maxrss", types.Typ[types.Int64], false),
	}, nil)
	rusageType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Rusage", nil),
		rusageStruct, nil)
	scope.Insert(rusageType.Obj())

	// type ProcAttr struct
	procAttrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dir", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Env", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Files", types.NewSlice(types.Typ[types.Uintptr]), false),
		types.NewField(token.NoPos, pkg, "Sys", types.NewPointer(sysProcAttrType), false),
	}, nil)
	procAttrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ProcAttr", nil),
		procAttrStruct, nil)
	scope.Insert(procAttrType.Obj())

	// type SysProcIDMap struct { ContainerID, HostID, Size int }
	idmapStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ContainerID", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "HostID", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Int], false),
	}, nil)
	idmapType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SysProcIDMap", nil),
		idmapStruct, nil)
	scope.Insert(idmapType.Obj())

	// Error constants
	scope.Insert(types.NewVar(token.NoPos, pkg, "EINVAL", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENOENT", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EEXIST", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EPERM", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EACCES", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EAGAIN", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENOSYS", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENOTDIR", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EISDIR", errnoType))

	// Signal constants
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGINT", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGTERM", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGKILL", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGHUP", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGPIPE", signalType))

	// Constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_RDONLY", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_WRONLY", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_RDWR", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_CREAT", types.Typ[types.Int], constant.MakeInt64(0100)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_TRUNC", types.Typ[types.Int], constant.MakeInt64(01000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_APPEND", types.Typ[types.Int], constant.MakeInt64(02000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_EXCL", types.Typ[types.Int], constant.MakeInt64(0200)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_SYNC", types.Typ[types.Int], constant.MakeInt64(04010000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_NONBLOCK", types.Typ[types.Int], constant.MakeInt64(04000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_CLOEXEC", types.Typ[types.Int], constant.MakeInt64(02000000)))

	scope.Insert(types.NewConst(token.NoPos, pkg, "STDIN_FILENO", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "STDOUT_FILENO", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "STDERR_FILENO", types.Typ[types.Int], constant.MakeInt64(2)))

	// func Getenv(key string) (value string, found bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getenv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "found", types.Typ[types.Bool])),
			false)))

	// func Getpid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getpid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getuid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getgid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Exit(code int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Exit",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "code", types.Typ[types.Int])),
			nil, false)))

	// func Open(path string, mode int, perm uint32) (fd int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "perm", types.Typ[types.Uint32])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func Close(fd int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Read(fd int, p []byte) (n int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func Write(fd int, p []byte) (n int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// Additional error codes
	scope.Insert(types.NewVar(token.NoPos, pkg, "EBUSY", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENODEV", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENOMEM", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EFAULT", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EBADF", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ERANGE", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ECONNRESET", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ECONNREFUSED", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ECONNABORTED", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ETIMEDOUT", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EADDRINUSE", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EADDRNOTAVAIL", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENETUNREACH", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EPIPE", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENOTSOCK", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EINTR", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENFILE", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EMFILE", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EAFNOSUPPORT", errnoType))

	// Additional signal constants
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGQUIT", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGABRT", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGALRM", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGUSR1", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGUSR2", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGCHLD", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGCONT", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGSTOP", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGTSTP", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGTTIN", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGTTOU", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGURG", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGWINCH", signalType))

	// Socket constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "AF_UNIX", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AF_INET", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AF_INET6", types.Typ[types.Int], constant.MakeInt64(10)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SOCK_STREAM", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SOCK_DGRAM", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SOCK_RAW", types.Typ[types.Int], constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "IPPROTO_TCP", types.Typ[types.Int], constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "IPPROTO_UDP", types.Typ[types.Int], constant.MakeInt64(17)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SOL_SOCKET", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SO_REUSEADDR", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SO_KEEPALIVE", types.Typ[types.Int], constant.MakeInt64(9)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TCP_NODELAY", types.Typ[types.Int], constant.MakeInt64(1)))

	// File mode constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFMT", types.Typ[types.Uint32], constant.MakeInt64(0170000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFREG", types.Typ[types.Uint32], constant.MakeInt64(0100000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFDIR", types.Typ[types.Uint32], constant.MakeInt64(040000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFLNK", types.Typ[types.Uint32], constant.MakeInt64(0120000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFCHR", types.Typ[types.Uint32], constant.MakeInt64(020000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFBLK", types.Typ[types.Uint32], constant.MakeInt64(060000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFIFO", types.Typ[types.Uint32], constant.MakeInt64(010000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFSOCK", types.Typ[types.Uint32], constant.MakeInt64(0140000)))

	// Wait constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "WNOHANG", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "WUNTRACED", types.Typ[types.Int], constant.MakeInt64(2)))

	// type Stat_t struct (simplified)
	statStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dev", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Ino", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Mode", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Nlink", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Uid", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Gid", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Rdev", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Blksize", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Blocks", types.Typ[types.Int64], false),
	}, nil)
	statType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Stat_t", nil),
		statStruct, nil)
	scope.Insert(statType.Obj())

	// type Sockaddr interface
	sockaddrIface := types.NewInterfaceType(nil, nil)
	sockaddrIface.Complete()

	// type RawSockaddrAny struct
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "RawSockaddrAny",
		types.NewStruct(nil, nil)))

	// func Stat(path string, stat *Stat_t) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Stat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "stat", types.NewPointer(statType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Lstat(path string, stat *Stat_t) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lstat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "stat", types.NewPointer(statType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Fstat(fd int, stat *Stat_t) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fstat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "stat", types.NewPointer(statType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func Mkdir(path string, mode uint32) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Mkdir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Rmdir(path string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Rmdir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Unlink(path string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unlink",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Rename(oldpath, newpath string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Rename",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "oldpath", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "newpath", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Link(oldpath, newpath string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Link",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "oldpath", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "newpath", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Symlink(oldpath, newpath string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Symlink",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "oldpath", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "newpath", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Readlink(path string, buf []byte) (n int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Readlink",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "buf", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Chmod(path string, mode uint32) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chmod",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Chown(path string, uid, gid int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chown",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "uid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "gid", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Fchmod(fd int, mode uint32) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fchmod",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "mode", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Fchown(fd int, uid, gid int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fchown",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "uid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "gid", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Ftruncate(fd int, length int64) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Ftruncate",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "length", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Truncate(path string, length int64) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Truncate",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "length", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Seek(fd int, offset int64, whence int) (off int64, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Seek",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "offset", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "whence", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "off", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Dup(oldfd int) (fd int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "oldfd", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Dup2(oldfd, newfd int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dup2",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "oldfd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "newfd", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Pipe(p []int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pipe",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Int]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Socket(domain, typ, proto int) (fd int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Socket",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "domain", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "typ", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "proto", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Bind(fd int, sa Sockaddr) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Bind",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "sa", sockaddrIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Listen(s int, backlog int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Listen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "backlog", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Accept(fd int) (nfd int, sa Sockaddr, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Accept",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "nfd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "sa", sockaddrIface),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Connect(fd int, sa Sockaddr) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Connect",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "sa", sockaddrIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Setsockopt(fd, level, opt int, value unsafe.Pointer, vallen uintptr) error — simplified
	// func SetsockoptInt(fd, level, opt int, value int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetsockoptInt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "level", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "opt", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func GetsockoptInt(fd, level, opt int) (value int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GetsockoptInt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "level", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "opt", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Getwd() (dir string, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getwd",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Chdir(path string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chdir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Umask(mask int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Umask",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "mask", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	// func Kill(pid int, sig Signal) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Kill",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "sig", signalType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Wait4(pid int, wstatus *WaitStatus, options int, rusage *Rusage) (wpid int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Wait4",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "wstatus", types.NewPointer(waitStatusType)),
				types.NewVar(token.NoPos, pkg, "options", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "rusage", types.NewPointer(rusageType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "wpid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Geteuid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Geteuid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	// func Getegid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getegid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	// func Getppid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getppid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	// func Getgroups() ([]int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getgroups",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Int])),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Setenv(key, value string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Setenv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Unsetenv(key string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unsetenv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Clearenv()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Clearenv",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))
	// func Environ() []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Environ",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))), false)))
	// func Exec(argv0 string, argv []string, envv []string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Exec",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "argv0", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "argv", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "envv", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func ForkExec(argv0 string, argv []string, attr *ProcAttr) (pid int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ForkExec",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "argv0", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "argv", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "attr", types.NewPointer(procAttrType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func StartProcess(argv0 string, argv []string, attr *ProcAttr) (pid int, handle uintptr, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StartProcess",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "argv0", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "argv", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "attr", types.NewPointer(procAttrType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "handle", types.Typ[types.Uintptr]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))

	// type SyscallError struct { Syscall string; Err error }
	syscallErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Syscall", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	syscallErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SyscallError", nil),
		syscallErrStruct, nil)
	scope.Insert(syscallErrType.Obj())
	seRecv := types.NewVar(token.NoPos, nil, "e", types.NewPointer(syscallErrType))
	syscallErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(seRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	syscallErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(seRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	syscallErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(seRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func ByteSliceFromString(s string) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ByteSliceFromString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func BytePtrFromString(s string) (*byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BytePtrFromString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// type RawConn interface { Control; Read; Write }
	rawConnIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Control",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "fd", types.Typ[types.Uintptr])),
						nil, false))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "fd", types.Typ[types.Uintptr])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
						false))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Write",
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
	rawConnType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RawConn", nil),
		rawConnIface, nil)
	scope.Insert(rawConnType.Obj())

	// type Conn interface { SyscallConn() (RawConn, error) }
	connIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "SyscallConn",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", rawConnType),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	connIface.Complete()
	connType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Conn", nil),
		connIface, nil)
	scope.Insert(connType.Obj())

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

func buildMathCmplxPackage() *types.Package {
	pkg := types.NewPackage("math/cmplx", "cmplx")
	scope := pkg.Scope()

	c128 := types.Typ[types.Complex128]
	f64 := types.Typ[types.Float64]

	// Unary complex functions: complex128 → complex128
	for _, name := range []string{"Sqrt", "Exp", "Log", "Sin", "Cos", "Tan",
		"Asin", "Acos", "Atan", "Sinh", "Cosh", "Tanh",
		"Conj", "Log10", "Log2"} {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "x", c128)),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", c128)),
				false)))
	}

	// complex128 → float64
	for _, name := range []string{"Abs", "Phase"} {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "x", c128)),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", f64)),
				false)))
	}

	// func Polar(x complex128) (r, θ float64)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Polar",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", c128)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", f64),
				types.NewVar(token.NoPos, pkg, "theta", f64)),
			false)))

	// func Rect(r, θ float64) complex128
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Rect",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", f64),
				types.NewVar(token.NoPos, pkg, "theta", f64)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", c128)),
			false)))

	// func Pow(x, y complex128) complex128
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pow",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", c128),
				types.NewVar(token.NoPos, pkg, "y", c128)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", c128)),
			false)))

	// func Inf() complex128
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Inf",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", c128)),
			false)))

	// func NaN() complex128
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NaN",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", c128)),
			false)))

	// func IsNaN(x complex128) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsNaN",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", c128)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IsInf(x complex128) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsInf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", c128)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildNetSMTPPackage() *types.Package {
	pkg := types.NewPackage("net/smtp", "smtp")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()

	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type ServerInfo struct (forward declare for Auth interface)
	serverInfoStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "TLS", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Auth", types.NewSlice(types.Typ[types.String]), false),
	}, nil)
	serverInfoType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ServerInfo", nil),
		serverInfoStruct, nil)
	scope.Insert(serverInfoType.Obj())

	// type Auth interface { Start(server *ServerInfo) (proto string, toServer []byte, err error); Next(fromServer []byte, more bool) (toServer []byte, err error) }
	authIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Start",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "server", types.NewPointer(serverInfoType))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "proto", types.Typ[types.String]),
					types.NewVar(token.NoPos, nil, "toServer", byteSlice),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Next",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "fromServer", byteSlice),
					types.NewVar(token.NoPos, nil, "more", types.Typ[types.Bool])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "toServer", byteSlice),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	authIface.Complete()
	authType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Auth", nil),
		authIface, nil)
	scope.Insert(authType.Obj())

	// type Client struct { ... }
	clientStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	clientType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Client", nil),
		clientStruct, nil)
	scope.Insert(clientType.Obj())
	clientPtr := types.NewPointer(clientType)

	// func SendMail(addr string, a Auth, from string, to []string, msg []byte) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SendMail",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "a", authType),
				types.NewVar(token.NoPos, pkg, "from", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "to", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "msg", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func PlainAuth(identity, username, password, host string) Auth
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PlainAuth",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "identity", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "username", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "password", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "host", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", authType)),
			false)))

	// func CRAMMD5Auth(username, secret string) Auth
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CRAMMD5Auth",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "username", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "secret", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", authType)),
			false)))

	// func Dial(addr string) (*Client, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", clientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Client methods
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Mail",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "from", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Rcpt",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "to", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Quit",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (c *Client) Hello(localName string) error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Hello",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "localName", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (c *Client) Auth(a Auth) error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Auth",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "a", authType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// *tls.Config (opaque)
	tlsConfigStruct := types.NewStruct(nil, nil)
	tlsConfigPtr := types.NewPointer(tlsConfigStruct)

	// io.WriteCloser interface
	ioWriteCloser := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
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

	// net.Conn interface (Read/Write/Close)
	smtpByteSlice := types.NewSlice(types.Typ[types.Byte])
	netConn := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", smtpByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", smtpByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	netConn.Complete()

	// func (c *Client) StartTLS(config *tls.Config) error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "StartTLS",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "config", tlsConfigPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (c *Client) Data() (io.WriteCloser, error)
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Data",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", ioWriteCloser),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (c *Client) Extension(ext string) (bool, string)
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Extension",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "ext", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// func (c *Client) Reset() error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (c *Client) Noop() error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Noop",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (c *Client) Verify(addr string) error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Verify",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "addr", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func NewClient(conn net.Conn, host string) (*Client, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewClient",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "conn", netConn),
				types.NewVar(token.NoPos, pkg, "host", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", clientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// ServerInfo type is defined earlier (before Auth interface)

	pkg.MarkComplete()
	return pkg
}

func buildNetRPCPackage() *types.Package {
	pkg := types.NewPackage("net/rpc", "rpc")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()

	// type Client struct { ... }
	clientStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	clientType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Client", nil),
		clientStruct, nil)
	scope.Insert(clientType.Obj())
	clientPtr := types.NewPointer(clientType)

	// type Server struct { ... }
	serverStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	serverType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Server", nil),
		serverStruct, nil)
	scope.Insert(serverType.Obj())

	// var DefaultServer *Server
	scope.Insert(types.NewVar(token.NoPos, pkg, "DefaultServer", types.NewPointer(serverType)))
	// var ErrShutdown error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrShutdown", errType))

	anyType := types.NewInterfaceType(nil, nil)

	// func Dial(network, address string) (*Client, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", clientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DialHTTP(network, address string) (*Client, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DialHTTP",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", clientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewServer() *Server
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewServer",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(serverType))),
			false)))

	// func Register(rcvr any) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Register",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "rcvr", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Client.Call(serviceMethod string, args any, reply any) error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Call",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "client", clientPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "serviceMethod", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType),
				types.NewVar(token.NoPos, nil, "reply", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Client.Close() error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "client", clientPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// type Call struct
	callStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ServiceMethod", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Args", anyType, false),
		types.NewField(token.NoPos, pkg, "Reply", anyType, false),
		types.NewField(token.NoPos, pkg, "Error", errType, false),
	}, nil)
	callType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Call", nil),
		callStruct, nil)
	scope.Insert(callType.Obj())
	callPtr := types.NewPointer(callType)

	// Client.Go(serviceMethod string, args any, reply any, done chan *Call) *Call
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Go",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "client", clientPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "serviceMethod", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType),
				types.NewVar(token.NoPos, nil, "reply", anyType),
				types.NewVar(token.NoPos, nil, "done", types.NewChan(types.SendRecv, callPtr))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", callPtr)),
			false)))

	// func RegisterName(name string, rcvr any) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RegisterName",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "rcvr", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DialHTTPPath(network, address, path string) (*Client, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DialHTTPPath",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", clientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	serverPtr := types.NewPointer(serverType)

	// Server methods
	// func (s *Server) Register(rcvr any) error
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Register",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "server", serverPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "rcvr", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (s *Server) RegisterName(name string, rcvr any) error
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "RegisterName",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "server", serverPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "rcvr", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (s *Server) HandleHTTP(rpcPath, debugPath string)
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "HandleHTTP",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "server", serverPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "rpcPath", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "debugPath", types.Typ[types.String])),
			nil, false)))

	// func HandleHTTP() — package-level convenience
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HandleHTTP",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// net.Addr stand-in
	netAddrIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Network",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	netAddrIface.Complete()

	// net.Listener interface
	rpcByteSlice := types.NewSlice(types.Typ[types.Byte])
	netConnIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", rpcByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", rpcByteSlice)),
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

	// io.ReadWriteCloser interface
	rwcIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", rpcByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", rpcByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	rwcIface.Complete()

	// func Accept(lis net.Listener)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Accept",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "lis", listenerIface)),
			nil, false)))

	// func ServeConn(conn io.ReadWriteCloser)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ServeConn",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "conn", rwcIface)),
			nil, false)))

	// func (s *Server) Accept(lis net.Listener)
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Accept",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "server", serverPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "lis", listenerIface)),
			nil, false)))

	// func (s *Server) ServeConn(conn io.ReadWriteCloser)
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "ServeConn",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "server", serverPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "conn", rwcIface)),
			nil, false)))

	// type ServerError string
	serverErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ServerError", nil),
		types.Typ[types.String], nil)
	serverErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", serverErrType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(serverErrType.Obj())

	// const DefaultRPCPath, DefaultDebugPath
	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultRPCPath", types.Typ[types.String],
		constant.MakeString("/_goRPC_")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultDebugPath", types.Typ[types.String],
		constant.MakeString("/debug/rpc")))

	pkg.MarkComplete()
	return pkg
}

func buildTextTemplateParsePackage() *types.Package {
	pkg := types.NewPackage("text/template/parse", "parse")
	scope := pkg.Scope()

	// type NodeType int (defined before Node so it can be referenced)
	nodeTypeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NodeType", nil),
		types.Typ[types.Int], nil)
	scope.Insert(nodeTypeType.Obj())

	// NodeType constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "NodeText", nodeTypeType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NodeAction", nodeTypeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NodeList", nodeTypeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NodePipe", nodeTypeType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NodeTemplate", nodeTypeType, constant.MakeInt64(4)))

	// type Pos int
	posType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Pos", nil),
		types.Typ[types.Int], nil)
	scope.Insert(posType.Obj())

	// type Node interface { Type() NodeType; String() string; Position() Pos }
	nodeIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Type",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", nodeTypeType)), false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Position",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
	}, nil)
	nodeIface.Complete()
	nodeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Node", nil),
		nodeIface, nil)
	scope.Insert(nodeType.Obj())

	// type Tree struct { ... }
	treeStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Root", nodeType, false),
	}, nil)
	treeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Tree", nil),
		treeStruct, nil)
	scope.Insert(treeType.Obj())
	_ = treeType

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

func buildCryptoX509PkixPackage() *types.Package {
	pkg := types.NewPackage("crypto/x509/pkix", "pkix")
	scope := pkg.Scope()

	// Forward-declare AttributeTypeAndValue for Name.Names/ExtraNames fields
	atvTypeFwd := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "AttributeTypeAndValue", nil),
		types.NewStruct(nil, nil), nil) // set underlying later

	// type Name struct { ... }
	nameStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Country", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Organization", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "OrganizationalUnit", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Locality", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Province", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "StreetAddress", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "PostalCode", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "SerialNumber", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "CommonName", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Names", types.NewSlice(atvTypeFwd), false),
		types.NewField(token.NoPos, pkg, "ExtraNames", types.NewSlice(atvTypeFwd), false),
	}, nil)
	nameType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Name", nil),
		nameStruct, nil)
	scope.Insert(nameType.Obj())

	// Name.String() method
	nameType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "n", nameType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// type AlgorithmIdentifier struct { Algorithm asn1.ObjectIdentifier; Parameters asn1.RawValue }
	// asn1.ObjectIdentifier stand-in: []int
	oidType := types.NewSlice(types.Typ[types.Int])
	// asn1.RawValue stand-in: struct with Tag, Class, IsCompound, Bytes, FullBytes
	rawValueStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Tag", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Class", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "IsCompound", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Bytes", types.NewSlice(types.Typ[types.Byte]), false),
		types.NewField(token.NoPos, pkg, "FullBytes", types.NewSlice(types.Typ[types.Byte]), false),
	}, nil)

	algStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Algorithm", oidType, false),
		types.NewField(token.NoPos, pkg, "Parameters", rawValueStruct, false),
	}, nil)
	algType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "AlgorithmIdentifier", nil),
		algStruct, nil)
	scope.Insert(algType.Obj())

	// type Extension struct { Id asn1.ObjectIdentifier; Critical bool; Value []byte }
	extStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Id", oidType, false),
		types.NewField(token.NoPos, pkg, "Critical", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Value", types.NewSlice(types.Typ[types.Byte]), false),
	}, nil)
	extType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Extension", nil),
		extStruct, nil)
	scope.Insert(extType.Obj())

	// type AttributeTypeAndValue struct { Type asn1.ObjectIdentifier; Value any }
	anyTypePkix := types.NewInterfaceType(nil, nil)
	anyTypePkix.Complete()
	atvStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Type", oidType, false),
		types.NewField(token.NoPos, pkg, "Value", anyTypePkix, false),
	}, nil)
	atvTypeFwd.SetUnderlying(atvStruct) // complete the forward declaration
	atvType := atvTypeFwd
	scope.Insert(atvType.Obj())

	// type RelativeDistinguishedNameSET []AttributeTypeAndValue
	rdnSetType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RelativeDistinguishedNameSET", nil),
		types.NewSlice(atvType), nil)
	scope.Insert(rdnSetType.Obj())

	// type RDNSequence []RelativeDistinguishedNameSET
	rdnSeqType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RDNSequence", nil),
		types.NewSlice(rdnSetType), nil)
	scope.Insert(rdnSeqType.Obj())

	// RDNSequence.String() string
	rdnSeqType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rdnSeqType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// Name.FillFromRDNSequence(rdns *RDNSequence)
	nameType.AddMethod(types.NewFunc(token.NoPos, pkg, "FillFromRDNSequence",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "n", types.NewPointer(nameType)),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "rdns", types.NewPointer(rdnSeqType))),
			nil, false)))

	// Name.ToRDNSequence() RDNSequence
	nameType.AddMethod(types.NewFunc(token.NoPos, pkg, "ToRDNSequence",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "n", nameType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", rdnSeqType)),
			false)))

	// type AttributeTypeAndValueSET struct { Type asn1.ObjectIdentifier; Value [][]AttributeTypeAndValue }
	atvsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Type", oidType, false),
		types.NewField(token.NoPos, pkg, "Value", types.NewSlice(types.NewSlice(atvType)), false),
	}, nil)
	atvsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "AttributeTypeAndValueSET", nil),
		atvsStruct, nil)
	scope.Insert(atvsType.Obj())

	// type CertificateList struct
	certListStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "TBSCertList", types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Raw", rawValueStruct, false),
			types.NewField(token.NoPos, pkg, "Version", types.Typ[types.Int], false),
			types.NewField(token.NoPos, pkg, "Signature", algType, false),
			types.NewField(token.NoPos, pkg, "Issuer", rdnSeqType, false),
		}, nil), false),
		types.NewField(token.NoPos, pkg, "SignatureAlgorithm", algType, false),
		types.NewField(token.NoPos, pkg, "SignatureValue", types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Bytes", types.NewSlice(types.Typ[types.Byte]), false),
			types.NewField(token.NoPos, pkg, "BitLength", types.Typ[types.Int], false),
		}, nil), false),
	}, nil)
	certListType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CertificateList", nil),
		certListStruct, nil)
	scope.Insert(certListType.Obj())
	certListType.AddMethod(types.NewFunc(token.NoPos, pkg, "HasExpired",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "cl", types.NewPointer(certListType)), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "now", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// type RevokedCertificate struct
	revokedCertStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "SerialNumber", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "RevocationTime", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Extensions", types.NewSlice(extType), false),
	}, nil)
	revokedCertType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RevokedCertificate", nil),
		revokedCertStruct, nil)
	scope.Insert(revokedCertType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildCryptoDSAPackage() *types.Package {
	pkg := types.NewPackage("crypto/dsa", "dsa")
	scope := pkg.Scope()

	// type ParameterSizes int
	paramSizesType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ParameterSizes", nil),
		types.Typ[types.Int], nil)
	scope.Insert(paramSizesType.Obj())

	scope.Insert(types.NewConst(token.NoPos, pkg, "L1024N160", paramSizesType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "L2048N224", paramSizesType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "L2048N256", paramSizesType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "L3072N256", paramSizesType, constant.MakeInt64(3)))

	// type PublicKey struct { ... }
	pubStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Int], false),
	}, nil)
	pubType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PublicKey", nil),
		pubStruct, nil)
	scope.Insert(pubType.Obj())

	// type PrivateKey struct { ... }
	privStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "X", types.Typ[types.Int], false),
	}, nil)
	privType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PrivateKey", nil),
		privStruct, nil)
	scope.Insert(privType.Obj())

	// var ErrInvalidPublicKey error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrInvalidPublicKey",
		types.Universe.Lookup("error").Type()))

	pkg.MarkComplete()
	return pkg
}

func buildNetRPCJSONRPCPackage() *types.Package {
	pkg := types.NewPackage("net/rpc/jsonrpc", "jsonrpc")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()

	// func Dial(network, address string) (*rpc.Client, error) — simplified
	clientStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	clientType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Client", nil),
		clientStruct, nil)
	clientPtr := types.NewPointer(clientType)

	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", clientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildCryptoPackage() *types.Package {
	pkg := types.NewPackage("crypto", "crypto")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader stand-in for rand parameters
	ioReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
	}, nil)
	ioReaderIface.Complete()

	// hash.Hash stand-in (io.Writer + Sum/Reset/Size/BlockSize)
	hashHashIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Sum",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)),
		types.NewFunc(token.NoPos, nil, "Reset",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, nil, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
	}, nil)
	hashHashIface.Complete()

	// type Hash uint
	hashType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Hash", nil),
		types.Typ[types.Uint], nil)
	scope.Insert(hashType.Obj())

	scope.Insert(types.NewConst(token.NoPos, pkg, "MD4", hashType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MD5", hashType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA1", hashType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA224", hashType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA256", hashType, constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA384", hashType, constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA512", hashType, constant.MakeInt64(7)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA512_224", hashType, constant.MakeInt64(12)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA512_256", hashType, constant.MakeInt64(13)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MD5SHA1", hashType, constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA3_224", hashType, constant.MakeInt64(10)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA3_256", hashType, constant.MakeInt64(11)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA3_384", hashType, constant.MakeInt64(14)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA3_512", hashType, constant.MakeInt64(15)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BLAKE2s_256", hashType, constant.MakeInt64(16)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BLAKE2b_256", hashType, constant.MakeInt64(17)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BLAKE2b_512", hashType, constant.MakeInt64(19)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RIPEMD160", hashType, constant.MakeInt64(20)))

	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Available",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "h", hashType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "h", hashType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "HashFunc",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "h", hashType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", hashType)), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "BlockSize",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "h", hashType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "h", hashType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// BLAKE2b_384 constant
	scope.Insert(types.NewConst(token.NoPos, pkg, "BLAKE2b_384", hashType, constant.MakeInt64(18)))

	// func RegisterHash(h Hash, f func() hash.Hash)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RegisterHash",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", hashType),
				types.NewVar(token.NoPos, pkg, "f", types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", hashHashIface)), false))),
			nil, false)))

	// SignerOpts interface — defined first so Signer can reference it
	signerOptsIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "HashFunc",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", hashType)), false)),
	}, nil)
	signerOptsIface.Complete()
	signerOptsType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SignerOpts", nil), signerOptsIface, nil)
	scope.Insert(signerOptsType.Obj())

	// DecrypterOpts — just an empty interface (matches Go stdlib)
	decrypterOptsIface := types.NewInterfaceType(nil, nil)
	decrypterOptsIface.Complete()
	decrypterOptsType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "DecrypterOpts", nil), decrypterOptsIface, nil)
	scope.Insert(decrypterOptsType.Obj())

	// PublicKey is any
	pubKeyType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "PublicKey", nil), types.NewInterfaceType(nil, nil), nil)
	scope.Insert(pubKeyType.Obj())

	// PrivateKey is any
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "PrivateKey", types.NewInterfaceType(nil, nil)))

	// Signer interface
	signerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Public",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", pubKeyType)), false)),
		types.NewFunc(token.NoPos, pkg, "Sign",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "rand", ioReaderIface),
					types.NewVar(token.NoPos, nil, "digest", byteSlice),
					types.NewVar(token.NoPos, nil, "opts", signerOptsType)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", byteSlice),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	signerIface.Complete()
	signerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Signer", nil), signerIface, nil)
	scope.Insert(signerType.Obj())

	// Decrypter interface
	decrypterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Public",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", pubKeyType)), false)),
		types.NewFunc(token.NoPos, pkg, "Decrypt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "rand", ioReaderIface),
					types.NewVar(token.NoPos, nil, "msg", byteSlice),
					types.NewVar(token.NoPos, nil, "opts", decrypterOptsType)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", byteSlice),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	decrypterIface.Complete()
	decrypterType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Decrypter", nil), decrypterIface, nil)
	scope.Insert(decrypterType.Obj())

	// Hash.New() returns hash.Hash
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "h", hashType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", hashHashIface)), false)))

	// func RegisterHash(h Hash, f func() hash.Hash)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RegisterHash",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", hashType),
				types.NewVar(token.NoPos, pkg, "f",
					types.NewSignatureType(nil, nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "", hashHashIface)),
						false))),
			nil, false)))

	// type MessageSigner interface (Go 1.25+)
	msgSignerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "SignMessage",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "rand", ioReaderIface),
					types.NewVar(token.NoPos, nil, "message", byteSlice),
					types.NewVar(token.NoPos, nil, "opts", signerOptsType)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", byteSlice),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	msgSignerIface.Complete()
	msgSignerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "MessageSigner", nil), msgSignerIface, nil)
	scope.Insert(msgSignerType.Obj())

	// func SignMessage(signer Signer, rand io.Reader, message []byte, opts SignerOpts) ([]byte, error) (Go 1.25+)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SignMessage",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "signer", signerType),
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "message", byteSlice),
				types.NewVar(token.NoPos, pkg, "opts", signerOptsType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	_ = signerType
	_ = decrypterType
	_ = msgSignerType
	pkg.MarkComplete()
	return pkg
}

func buildHashAdler32Package() *types.Package {
	pkg := types.NewPackage("hash/adler32", "adler32")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// hash.Hash32 interface (embeds hash.Hash + Sum32)
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

	scope.Insert(types.NewConst(token.NoPos, pkg, "Size", types.Typ[types.Int], constant.MakeInt64(4)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Checksum",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])), false)))
	pkg.MarkComplete()
	return pkg
}

func buildHashCRC64Package() *types.Package {
	pkg := types.NewPackage("hash/crc64", "crc64")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// hash.Hash64 interface
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

	tableType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Table", nil),
		types.NewArray(types.Typ[types.Uint64], 256), nil)
	scope.Insert(tableType.Obj())
	tablePtr := types.NewPointer(tableType)

	scope.Insert(types.NewConst(token.NoPos, pkg, "Size", types.Typ[types.Int], constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ISO", types.Typ[types.Uint64], constant.MakeUint64(0xD800000000000000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ECMA", types.Typ[types.Uint64], constant.MakeUint64(0x42F0E1EBA9EA3693)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "tab", tablePtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeTable",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "poly", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tablePtr)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Checksum",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", byteSlice),
				types.NewVar(token.NoPos, pkg, "tab", tablePtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Update",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "crc", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "tab", tablePtr),
				types.NewVar(token.NoPos, pkg, "p", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])), false)))

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

func buildGoConstantPackage() *types.Package {
	pkg := types.NewPackage("go/constant", "constant")
	scope := pkg.Scope()
	kindType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Kind", nil), types.Typ[types.Int], nil)
	scope.Insert(kindType.Obj())
	for _, kv := range []struct {
		name string
		val  int64
	}{{"Unknown", 0}, {"Bool", 1}, {"String", 2}, {"Int", 3}, {"Float", 4}, {"Complex", 5}} {
		scope.Insert(types.NewConst(token.NoPos, pkg, kv.name, kindType, constant.MakeInt64(kv.val)))
	}
	valueIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Kind",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", kindType)), false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "ExactString",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	valueIface.Complete()
	valueType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Value", nil), valueIface, nil)
	scope.Insert(valueType.Obj())
	for _, name := range []string{"MakeBool"} {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Bool])),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))
	}
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeInt64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeFloat64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BoolVal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StringVal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int64Val",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "exact", types.Typ[types.Bool])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float64Val",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "exact", types.Typ[types.Bool])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x_", valueType),
				types.NewVar(token.NoPos, pkg, "op", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "y_", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))

	anyType := types.Universe.Lookup("any").Type()
	byteSliceConst := types.NewSlice(types.Typ[types.Byte])

	// func MakeUint64(x uint64) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeUint64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func MakeImag(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeImag",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func MakeUnknown() Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeUnknown",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Make(x any) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Make",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func MakeFromLiteral(lit string, tok token.Token, zero uint) Value
	// token.Token is int stand-in
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeFromLiteral",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "lit", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "tok", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "zero", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func MakeFromBytes(bytes []byte) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeFromBytes",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "bytes", byteSliceConst)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Val(x Value) any
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Val",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)), false)))

	// func Uint64Val(x Value) (uint64, bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint64Val",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "exact", types.Typ[types.Bool])), false)))

	// func Float32Val(x Value) (float32, bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float32Val",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float32]),
				types.NewVar(token.NoPos, pkg, "exact", types.Typ[types.Bool])), false)))

	// func Num(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Num",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Denom(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Denom",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Real(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Real",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Imag(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Imag",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Sign(x Value) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sign",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))

	// func BitLen(x Value) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BitLen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))

	// func Bytes(x Value) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSliceConst)), false)))

	// func ToInt(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToInt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func ToFloat(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToFloat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func ToComplex(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToComplex",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func BinaryOp(x_ Value, op token.Token, y_ Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BinaryOp",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x_", valueType),
				types.NewVar(token.NoPos, pkg, "op", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "y_", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func UnaryOp(op token.Token, y Value, prec uint) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UnaryOp",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "op", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "y", valueType),
				types.NewVar(token.NoPos, pkg, "prec", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Shift(x Value, op token.Token, s uint) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Shift",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", valueType),
				types.NewVar(token.NoPos, pkg, "op", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	pkg.MarkComplete()
	return pkg
}

func buildRuntimeTracePackage() *types.Package {
	pkg := types.NewPackage("runtime/trace", "trace")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	// context.Context interface { Deadline() (int64, bool); Done() <-chan struct{}; Err() error; Value(key any) any }
	anyCtx := types.NewInterfaceType(nil, nil)
	anyCtx.Complete()
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
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyCtx)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyCtx)),
				false)),
	}, nil)
	ctxType.Complete()
	byteSliceTrace := types.NewSlice(types.Typ[types.Byte])

	// io.Writer interface for Start
	ioWriterTrace := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceTrace)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterTrace.Complete()

	// func Start(w io.Writer) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Start",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterTrace)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func Stop()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Stop",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func IsEnabled() bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsEnabled",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))

	// type Task struct (opaque)
	taskType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Task", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(taskType.Obj())
	taskPtr := types.NewPointer(taskType)
	taskType.AddMethod(types.NewFunc(token.NoPos, pkg, "End",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "t", taskPtr), nil, nil, nil, nil, false)))

	// func NewTask(pctx context.Context, taskType string) (context.Context, *Task)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTask",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pctx", ctxType),
				types.NewVar(token.NoPos, pkg, "taskType", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ctxType),
				types.NewVar(token.NoPos, pkg, "", taskPtr)), false)))

	// type Region struct (opaque)
	regionType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Region", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(regionType.Obj())
	regionPtr := types.NewPointer(regionType)
	regionType.AddMethod(types.NewFunc(token.NoPos, pkg, "End",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", regionPtr), nil, nil, nil, nil, false)))

	// func StartRegion(ctx context.Context, regionType string) *Region
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StartRegion",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "regionType", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", regionPtr)), false)))

	// func WithRegion(ctx context.Context, regionType string, fn func())
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithRegion",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "regionType", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "fn", types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			nil, false)))

	// func Log(ctx context.Context, category, message string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Log",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "category", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "message", types.Typ[types.String])),
			nil, false)))

	// func Logf(ctx context.Context, category, format string, args ...interface{})
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Logf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "category", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(types.NewInterfaceType(nil, nil)))),
			nil, true)))

	pkg.MarkComplete()
	return pkg
}

func buildCryptoECDHPackage() *types.Package {
	pkg := types.NewPackage("crypto/ecdh", "ecdh")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	curveType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Curve", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(curveType.Obj())
	for _, name := range []string{"P256", "P384", "P521", "X25519"} {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", curveType)), false)))
	}
	privType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "PrivateKey", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(privType.Obj())
	privPtr := types.NewPointer(privType)
	pubType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "PublicKey", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(pubType.Obj())
	pubPtr := types.NewPointer(pubType)
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "PublicKey",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", privPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pubPtr)), false)))
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", privPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)))
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "ECDH",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", privPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "remote", pubPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice), types.NewVar(token.NoPos, nil, "", errType)), false)))
	pubType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", pubPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)))

	// PrivateKey: Curve, Equal, Public
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Curve",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", privPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", curveType)), false)))
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", privPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Public",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", privPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)))

	// PublicKey: Curve, Equal
	pubType.AddMethod(types.NewFunc(token.NoPos, pkg, "Curve",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", pubPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", curveType)), false)))
	pubType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", pubPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// io.Reader stand-in
	ioReaderECDH := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
	}, nil)
	ioReaderECDH.Complete()

	// func GenerateKey(curve Curve, rand io.Reader) (*PrivateKey, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GenerateKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "curve", curveType),
				types.NewVar(token.NoPos, pkg, "rand", ioReaderECDH)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", privPtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// Curve.GenerateKey(rand io.Reader) (*PrivateKey, error)
	curveType.AddMethod(types.NewFunc(token.NoPos, pkg, "GenerateKey",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", curveType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "rand", ioReaderECDH)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", privPtr),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// Curve.NewPublicKey(key []byte) (*PublicKey, error)
	curveType.AddMethod(types.NewFunc(token.NoPos, pkg, "NewPublicKey",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", curveType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", pubPtr),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// Curve.NewPrivateKey(key []byte) (*PrivateKey, error)
	curveType.AddMethod(types.NewFunc(token.NoPos, pkg, "NewPrivateKey",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", curveType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", privPtr),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoScannerPackage() *types.Package {
	pkg := types.NewPackage("go/scanner", "scanner")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Error struct { Pos token.Position; Msg string }
	errorStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Msg", types.Typ[types.String], false),
	}, nil)
	errorType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Error", nil), errorStruct, nil)
	scope.Insert(errorType.Obj())
	errorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", errorType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type ErrorList []*Error
	errorListType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ErrorList", nil),
		types.NewSlice(types.NewPointer(errorType)), nil)
	scope.Insert(errorListType.Obj())
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// ErrorHandler func type: func(pos token.Position, msg string)
	// token.Position stand-in as struct
	tokenPositionStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, nil, "Filename", types.Typ[types.String], false),
		types.NewField(token.NoPos, nil, "Offset", types.Typ[types.Int], false),
		types.NewField(token.NoPos, nil, "Line", types.Typ[types.Int], false),
		types.NewField(token.NoPos, nil, "Column", types.Typ[types.Int], false),
	}, nil)
	errorHandlerType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "pos", tokenPositionStruct),
			types.NewVar(token.NoPos, nil, "msg", types.Typ[types.String])),
		nil, false)

	// type ErrorHandler func(pos token.Position, msg string)
	ehNamed := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ErrorHandler", nil), errorHandlerType, nil)
	scope.Insert(ehNamed.Obj())

	// type Scanner struct { ErrorCount int; Mode Mode }
	scannerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ErrorCount", types.Typ[types.Int], false),
	}, nil)
	scannerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Scanner", nil), scannerStruct, nil)
	scope.Insert(scannerType.Obj())
	scannerPtr := types.NewPointer(scannerType)

	// type Mode uint
	modeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Mode", nil), types.Typ[types.Uint], nil)
	scope.Insert(modeType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanComments", modeType, constant.MakeInt64(1)))

	// *token.FileSet stand-in
	fsetPtrGS := types.NewPointer(types.NewStruct(nil, nil))
	// *token.File stand-in
	filePtrGS := types.NewPointer(types.NewStruct(nil, nil))

	// Scanner.Init(file *token.File, src []byte, err ErrorHandler, mode Mode)
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "s", scannerPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "file", filePtrGS),
				types.NewVar(token.NoPos, nil, "src", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "err", ehNamed),
				types.NewVar(token.NoPos, nil, "mode", modeType)),
			nil, false)))

	// token.Pos stand-in = int
	// token.Token stand-in = int
	// Scanner.Scan() (pos token.Pos, tok token.Token, lit string)
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Scan",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "s", scannerPtr), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "tok", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "lit", types.Typ[types.String])),
			false)))

	// ErrorList methods
	errorListPtr := types.NewPointer(errorListType)

	// ErrorList.Add(pos token.Position, msg string)
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", tokenPositionStruct),
				types.NewVar(token.NoPos, nil, "msg", types.Typ[types.String])),
			nil, false)))

	// ErrorList.Reset()
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListPtr), nil, nil, nil, nil, false)))

	// ErrorList.Sort()
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sort",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListType), nil, nil, nil, nil, false)))

	// ErrorList.Error() string (implements error)
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// ErrorList.Err() error
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Err",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// ErrorList.RemoveMultiples()
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "RemoveMultiples",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListPtr), nil, nil, nil, nil, false)))

	// ErrorList.Swap(i, j int) - sort.Interface
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListType), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
			nil, false)))

	// ErrorList.Less(i, j int) bool - sort.Interface
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Less",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListType), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func PrintError(w io.Writer, err error)
	byteSliceGS := types.NewSlice(types.Typ[types.Byte])
	ioWriterGS := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceGS)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterGS.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PrintError",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriterGS),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			nil, false)))

	_ = fsetPtrGS

	pkg.MarkComplete()
	return pkg
}

func buildMathRandV2Package() *types.Package {
	pkg := types.NewPackage("math/rand/v2", "rand")
	scope := pkg.Scope()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IntN",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int64",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int64N",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint32",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float32",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float32])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "N",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Shuffle",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "swap", types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
						types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])), nil, false))),
			nil, false)))

	// Additional global functions
	// func Int32() int32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int32",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])), false)))
	// func Int32N(n int32) int32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int32N",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])), false)))
	// func Uint() uint
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint])), false)))
	// func UintN(n uint) uint
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UintN",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint])), false)))
	// func Uint32N(n uint32) uint32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint32N",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])), false)))
	// func Uint64N(n uint64) uint64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint64N",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])), false)))
	// func ExpFloat64() float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ExpFloat64",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])), false)))
	// func NormFloat64() float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NormFloat64",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])), false)))
	// func Perm(n int) []int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Perm",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Int]))), false)))

	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()

	// Source interface
	sourceIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Uint64",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)),
	}, nil)
	sourceIface.Complete()
	sourceType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Source", nil),
		sourceIface, nil)
	scope.Insert(sourceType.Obj())

	// Rand type
	randStruct := types.NewStruct(nil, nil)
	randType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Rand", nil),
		randStruct, nil)
	scope.Insert(randType.Obj())
	randPtr := types.NewPointer(randType)
	rRecv := types.NewVar(token.NoPos, nil, "r", randPtr)

	// func New(src Source) *Rand
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "src", sourceType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", randPtr)), false)))

	// Rand methods
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "IntN",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int32",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int32])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int32N",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int32])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int64",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int64N",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "UintN",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint32",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint32N",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64N",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float32",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float32])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExpFloat64",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "NormFloat64",
		types.NewSignatureType(rRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Perm",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Int]))), false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Shuffle",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "swap", types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
						types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])), nil, false))),
			nil, false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "N",
		types.NewSignatureType(rRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// ChaCha8 type
	seedArray := types.NewArray(types.Typ[types.Byte], 32)
	chacha8Struct := types.NewStruct(nil, nil)
	chacha8Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ChaCha8", nil),
		chacha8Struct, nil)
	scope.Insert(chacha8Type.Obj())
	chacha8Ptr := types.NewPointer(chacha8Type)
	cRecv := types.NewVar(token.NoPos, nil, "c", chacha8Ptr)

	// func NewChaCha8(seed [32]byte) *ChaCha8
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewChaCha8",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seed", seedArray)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", chacha8Ptr)), false)))

	chacha8Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Seed",
		types.NewSignatureType(cRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "seed", seedArray)),
			nil, false)))
	chacha8Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(cRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))
	chacha8Type.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalBinary",
		types.NewSignatureType(cRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	chacha8Type.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalBinary",
		types.NewSignatureType(cRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	chacha8Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(cRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)), false)))

	// PCG type
	pcgStruct := types.NewStruct(nil, nil)
	pcgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PCG", nil),
		pcgStruct, nil)
	scope.Insert(pcgType.Obj())
	pcgPtr := types.NewPointer(pcgType)
	pRecv := types.NewVar(token.NoPos, nil, "p", pcgPtr)

	// func NewPCG(seed1, seed2 uint64) *PCG
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewPCG",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "seed1", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "seed2", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pcgPtr)), false)))

	pcgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seed",
		types.NewSignatureType(pRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "seed1", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, nil, "seed2", types.Typ[types.Uint64])),
			nil, false)))
	pcgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(pRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))
	pcgType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalBinary",
		types.NewSignatureType(pRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	pcgType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalBinary",
		types.NewSignatureType(pRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// Zipf type
	zipfStruct := types.NewStruct(nil, nil)
	zipfType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Zipf", nil),
		zipfStruct, nil)
	scope.Insert(zipfType.Obj())
	zipfPtr := types.NewPointer(zipfType)

	// func NewZipf(r *Rand, s float64, v float64, imax uint64) *Zipf
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewZipf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", randPtr),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "v", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "imax", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", zipfPtr)), false)))

	zipfType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "z", zipfPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))

	pkg.MarkComplete()
	return pkg
}

func buildDatabaseSQLDriverPackage() *types.Package {
	pkg := types.NewPackage("database/sql/driver", "driver")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anyType := types.NewInterfaceType(nil, nil)

	// type Value interface{}
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Value", anyType))

	// type NamedValue struct
	namedValueStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Ordinal", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Value", anyType, false),
	}, nil)
	namedValueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NamedValue", nil),
		namedValueStruct, nil)
	scope.Insert(namedValueType.Obj())

	// type IsolationLevel int
	isolationType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "IsolationLevel", nil),
		types.Typ[types.Int], nil)
	scope.Insert(isolationType.Obj())

	// type TxOptions struct
	txOptsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Isolation", isolationType, false),
		types.NewField(token.NoPos, pkg, "ReadOnly", types.Typ[types.Bool], false),
	}, nil)
	txOptsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "TxOptions", nil),
		txOptsStruct, nil)
	scope.Insert(txOptsType.Obj())

	valueSlice := types.NewSlice(anyType)
	stringSlice := types.NewSlice(types.Typ[types.String])

	// Result interface: LastInsertId() (int64, error); RowsAffected() (int64, error)
	resultIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "LastInsertId",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "RowsAffected",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	resultIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Result", resultIface))

	// Rows interface: Columns() []string; Close() error; Next(dest []Value) error
	rowsIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Columns",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", stringSlice)), false)),
		types.NewFunc(token.NoPos, pkg, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "Next",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "dest", valueSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	rowsIface.Complete()
	rowsType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Rows", nil), rowsIface, nil)
	scope.Insert(rowsType.Obj())

	// Stmt interface: Close() error; NumInput() int; Exec(args []Value) (Result, error); Query(args []Value) (Rows, error)
	stmtIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "NumInput",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "Exec",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "args", valueSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", resultIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "Query",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "args", valueSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", rowsType),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	stmtIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Stmt", stmtIface))

	// Tx interface: Commit() error; Rollback() error
	txIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Commit",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "Rollback",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	txIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Tx", txIface))

	// Conn interface: Prepare(query string) (Stmt, error); Close() error; Begin() (Tx, error)
	connIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Prepare",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "query", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", stmtIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "Begin",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", txIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	connIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Conn", connIface))

	// Driver interface: Open(name string) (Conn, error)
	driverIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", connIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	driverIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Driver", driverIface))

	// Valuer interface: Value() (Value, error)
	valuerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Value",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", anyType),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	valuerIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Valuer", valuerIface))

	// ValueConverter interface: ConvertValue(v any) (Value, error)
	valueConverterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ConvertValue",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "v", anyType)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", anyType),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	valueConverterIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "ValueConverter", valueConverterIface))

	// context.Context stand-in { Deadline(); Done(); Err(); Value() }
	anyCtxDB := types.NewInterfaceType(nil, nil)
	anyCtxDB.Complete()
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
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyCtxDB)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyCtxDB)),
				false)),
	}, nil)
	ctxType.Complete()
	namedValueSlice := types.NewSlice(types.NewPointer(namedValueType))
	for _, def := range []struct {
		name  string
		iface *types.Interface
	}{
		{"DriverContext", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "OpenConnector",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", anyType),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"ConnPrepareContext", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "PrepareContext",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "ctx", ctxType),
						types.NewVar(token.NoPos, nil, "query", types.Typ[types.String])),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", stmtIface),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"ConnBeginTx", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "BeginTx",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "ctx", ctxType),
						types.NewVar(token.NoPos, nil, "opts", txOptsType)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", txIface),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"Pinger", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "Ping",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", ctxType)),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"SessionResetter", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ResetSession",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", ctxType)),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"Validator", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "IsValid",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		}, nil)},
	} {
		def.iface.Complete()
		scope.Insert(types.NewTypeName(token.NoPos, pkg, def.name, def.iface))
	}

	// reflect.Type stand-in for RowsColumnTypeScanType
	reflectTypeIfaceDB := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	reflectTypeIfaceDB.Complete()

	// Extension interfaces with proper method signatures
	for _, def := range []struct {
		name  string
		iface *types.Interface
	}{
		{"StmtExecContext", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ExecContext",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "ctx", ctxType),
						types.NewVar(token.NoPos, nil, "args", namedValueSlice)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", resultIface),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"StmtQueryContext", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "QueryContext",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "ctx", ctxType),
						types.NewVar(token.NoPos, nil, "args", namedValueSlice)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", rowsType),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"RowsNextResultSet", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "HasNextResultSet",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
			types.NewFunc(token.NoPos, pkg, "NextResultSet",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"Execer", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "Exec",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "query", types.Typ[types.String]),
						types.NewVar(token.NoPos, nil, "args", valueSlice)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", resultIface),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"ExecerContext", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ExecContext",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "ctx", ctxType),
						types.NewVar(token.NoPos, nil, "query", types.Typ[types.String]),
						types.NewVar(token.NoPos, nil, "args", namedValueSlice)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", resultIface),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"Queryer", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "Query",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "query", types.Typ[types.String]),
						types.NewVar(token.NoPos, nil, "args", valueSlice)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", rowsType),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"QueryerContext", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "QueryContext",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "ctx", ctxType),
						types.NewVar(token.NoPos, nil, "query", types.Typ[types.String]),
						types.NewVar(token.NoPos, nil, "args", namedValueSlice)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", rowsType),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"Connector", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "Connect",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", ctxType)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", connIface),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
			types.NewFunc(token.NoPos, pkg, "Driver",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", driverIface)), false)),
		}, nil)},
		{"RowsColumnTypeScanType", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ColumnTypeScanType",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "index", types.Typ[types.Int])),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", reflectTypeIfaceDB)), false)),
		}, nil)},
		{"RowsColumnTypeDatabaseTypeName", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ColumnTypeDatabaseTypeName",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "index", types.Typ[types.Int])),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		}, nil)},
		{"RowsColumnTypeLength", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ColumnTypeLength",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "index", types.Typ[types.Int])),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "length", types.Typ[types.Int64]),
						types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])), false)),
		}, nil)},
		{"RowsColumnTypeNullable", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ColumnTypeNullable",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "index", types.Typ[types.Int])),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "nullable", types.Typ[types.Bool]),
						types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])), false)),
		}, nil)},
		{"RowsColumnTypePrecisionScale", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ColumnTypePrecisionScale",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "index", types.Typ[types.Int])),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "precision", types.Typ[types.Int64]),
						types.NewVar(token.NoPos, nil, "scale", types.Typ[types.Int64]),
						types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])), false)),
		}, nil)},
	} {
		def.iface.Complete()
		scope.Insert(types.NewTypeName(token.NoPos, pkg, def.name, def.iface))
	}
	_ = namedValueSlice

	// type NotNull, Null structs
	for _, name := range []string{"NotNull", "Null"} {
		s := types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Converter", anyType, false),
		}, nil)
		t := types.NewNamed(types.NewTypeName(token.NoPos, pkg, name, nil), s, nil)
		scope.Insert(t.Obj())
	}

	// var Int32, String, Bool, DefaultParameterConverter
	for _, name := range []string{"Int32", "String", "Bool", "DefaultParameterConverter"} {
		scope.Insert(types.NewVar(token.NoPos, pkg, name, anyType))
	}

	// var ErrSkip, ErrBadConn, ErrRemoveArgument error
	for _, name := range []string{"ErrSkip", "ErrBadConn", "ErrRemoveArgument"} {
		scope.Insert(types.NewVar(token.NoPos, pkg, name, errType))
	}

	// func IsScanValue(v Value) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsScanValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IsValue(v any) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoDocPackage() *types.Package {
	pkg := types.NewPackage("go/doc", "doc")
	scope := pkg.Scope()

	// type Package struct
	pkgStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "ImportPath", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Doc", types.Typ[types.String], false),
	}, nil)
	pkgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Package", nil),
		pkgStruct, nil)
	scope.Insert(pkgType.Obj())

	// type Type, Func, Value, Note structs
	for _, name := range []string{"Type", "Func", "Value", "Note"} {
		s := types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Doc", types.Typ[types.String], false),
		}, nil)
		t := types.NewNamed(types.NewTypeName(token.NoPos, pkg, name, nil), s, nil)
		scope.Insert(t.Obj())
	}

	// type Mode int
	modeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Mode", nil),
		types.Typ[types.Int], nil)
	scope.Insert(modeType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "AllDecls", modeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AllMethods", modeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "PreserveAST", modeType, constant.MakeInt64(4)))

	// func New(...) *Package — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pkg_", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "importPath", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", modeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(pkgType))),
			false)))

	// func Synopsis(text string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Synopsis",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ToHTML / ToText — no-op stubs
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToHTML",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "words", types.Typ[types.Int])),
			nil, false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToText",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "indent", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "preIndent", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "width", types.Typ[types.Int])),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// net/netip
// ============================================================

func buildNetNetipPackage() *types.Package {
	pkg := types.NewPackage("net/netip", "netip")
	scope := pkg.Scope()

	// type Addr struct { ... }
	addrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "hi", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "lo", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "z", types.Typ[types.Int], false),
	}, nil)
	addrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Addr", nil),
		addrStruct, nil)
	scope.Insert(addrType.Obj())

	// type AddrPort struct { ... }
	addrPortStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ip", addrType, false),
		types.NewField(token.NoPos, pkg, "port", types.Typ[types.Uint16], false),
	}, nil)
	addrPortType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "AddrPort", nil),
		addrPortStruct, nil)
	scope.Insert(addrPortType.Obj())

	// type Prefix struct { ... }
	prefixStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ip", addrType, false),
		types.NewField(token.NoPos, pkg, "bits", types.Typ[types.Int], false),
	}, nil)
	prefixType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Prefix", nil),
		prefixStruct, nil)
	scope.Insert(prefixType.Obj())

	errType := types.Universe.Lookup("error").Type()

	// Addr constructors
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddrFrom4",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", types.NewArray(types.Typ[types.Byte], 4))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddrFrom16",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", types.NewArray(types.Typ[types.Byte], 16))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddrFromSlice",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "slice", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", addrType),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MustParseAddr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseAddr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", addrType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IPv4Unspecified",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IPv6Unspecified",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IPv6LinkLocalAllNodes",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IPv6Loopback",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))

	// Addr methods
	addrMethods := []struct{ name string; ret *types.Tuple }{
		{"IsValid", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"Is4", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"Is6", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"Is4In6", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsLoopback", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsMulticast", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsPrivate", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsGlobalUnicast", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsLinkLocalUnicast", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsLinkLocalMulticast", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsInterfaceLocalMulticast", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsUnspecified", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"BitLen", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]))},
		{"Zone", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]))},
		{"String", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]))},
		{"StringExpanded", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]))},
	}
	for _, m := range addrMethods {
		addrType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
				nil, m.ret, false)))
	}
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "As4",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewArray(types.Typ[types.Byte], 4))),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "As16",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewArray(types.Typ[types.Byte], 16))),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "AsSlice",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unmap",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "WithZone",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "zone", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalBinary",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Prev",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Prefix",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", prefixType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ip2", addrType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Less",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ip2", addrType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// AddrPort constructors
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddrPortFrom",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ip", addrType),
				types.NewVar(token.NoPos, pkg, "port", types.Typ[types.Uint16])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrPortType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MustParseAddrPort",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrPortType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseAddrPort",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", addrPortType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// AddrPort methods
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "Addr",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrPortType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)), false)))
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "Port",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrPortType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint16])), false)))
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrPortType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrPortType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))

	// Prefix constructors
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PrefixFrom",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ip", addrType),
				types.NewVar(token.NoPos, pkg, "bits", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", prefixType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MustParsePrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", prefixType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParsePrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", prefixType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Prefix methods
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "Addr",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bits",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "Contains",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ip", addrType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "Overlaps",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "o", prefixType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "Masked",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", prefixType)), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsSingleIP",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))

	byteSlice := types.NewSlice(types.Typ[types.Byte])
	addrRecv := types.NewVar(token.NoPos, nil, "ip", addrType)
	addrPtrRecv := types.NewVar(token.NoPos, nil, "ip", types.NewPointer(addrType))
	addrPortRecv := types.NewVar(token.NoPos, nil, "p", addrPortType)
	addrPortPtrRecv := types.NewVar(token.NoPos, nil, "p", types.NewPointer(addrPortType))
	prefixRecv := types.NewVar(token.NoPos, nil, "p", prefixType)
	prefixPtrRecv := types.NewVar(token.NoPos, nil, "p", types.NewPointer(prefixType))

	// func IPv6LinkLocalAllRouters() Addr
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IPv6LinkLocalAllRouters",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)), false)))

	// Addr.UnmarshalText(text []byte) error
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(addrPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "text", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Addr.UnmarshalBinary(b []byte) error
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalBinary",
		types.NewSignatureType(addrPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Addr.AppendTo(b []byte) []byte
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "AppendTo",
		types.NewSignatureType(addrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)))

	// AddrPort.MarshalText() ([]byte, error)
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(addrPortRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// AddrPort.MarshalBinary() ([]byte, error)
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalBinary",
		types.NewSignatureType(addrPortRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// AddrPort.UnmarshalText(text []byte) error
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(addrPortPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "text", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// AddrPort.UnmarshalBinary(b []byte) error
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalBinary",
		types.NewSignatureType(addrPortPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// AddrPort.AppendTo(b []byte) []byte
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "AppendTo",
		types.NewSignatureType(addrPortRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)))
	// AddrPort.Compare(p2 AddrPort) int
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(addrPortRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p2", addrPortType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// Prefix.MarshalText() ([]byte, error)
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(prefixRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Prefix.MarshalBinary() ([]byte, error)
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalBinary",
		types.NewSignatureType(prefixRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Prefix.UnmarshalText(text []byte) error
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(prefixPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "text", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Prefix.UnmarshalBinary(b []byte) error
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalBinary",
		types.NewSignatureType(prefixPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Prefix.AppendTo(b []byte) []byte
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "AppendTo",
		types.NewSignatureType(prefixRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// iter
// ============================================================

func buildIterPackage() *types.Package {
	pkg := types.NewPackage("iter", "iter")
	scope := pkg.Scope()

	// type Seq[V any] func(yield func(V) bool) — simplified as func(func(int) bool)
	seqType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Seq", nil),
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "yield",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
					types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
					false))),
			nil, false), nil)
	scope.Insert(seqType.Obj())

	// type Seq2[K, V any] func(yield func(K, V) bool) — simplified as func(func(int, int) bool)
	seq2Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Seq2", nil),
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "yield",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
						types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
					types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
					false))),
			nil, false), nil)
	scope.Insert(seq2Type.Obj())

	// func Pull[V any](seq Seq[V]) (next func() (V, bool), stop func()) — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pull",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seq", seqType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "next",
					types.NewSignatureType(nil, nil, nil, nil,
						types.NewTuple(
							types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
							types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
						false)),
				types.NewVar(token.NoPos, pkg, "stop",
					types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			false)))

	// func Pull2[K, V any](seq Seq2[K, V]) (next func() (K, V, bool), stop func()) — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pull2",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seq", seq2Type)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "next",
					types.NewSignatureType(nil, nil, nil, nil,
						types.NewTuple(
							types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
							types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
							types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
						false)),
				types.NewVar(token.NoPos, pkg, "stop",
					types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// unique
// ============================================================

func buildUniquePackage() *types.Package {
	pkg := types.NewPackage("unique", "unique")
	scope := pkg.Scope()

	// type Handle[T comparable] struct { ... } — simplified as struct with value
	handleStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "value", types.Typ[types.Int], false),
	}, nil)
	handleType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Handle", nil),
		handleStruct, nil)
	scope.Insert(handleType.Obj())

	// func Make[T comparable](value T) Handle[T] — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Make",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handleType)),
			false)))

	// Handle.Value() T
	handleType.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", handleType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// testing/quick
// ============================================================

func buildTestingQuickPackage() *types.Package {
	pkg := types.NewPackage("testing/quick", "quick")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Config struct { ... }
	configStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "MaxCount", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "MaxCountScale", types.Typ[types.Float64], false),
		types.NewField(token.NoPos, pkg, "Rand", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Values", types.Typ[types.Int], false),
	}, nil)
	configType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Config", nil),
		configStruct, nil)
	scope.Insert(configType.Obj())

	// type CheckError struct { ... }
	checkErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Count", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "In", types.NewSlice(types.NewInterfaceType(nil, nil)), false),
	}, nil)
	checkErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CheckError", nil),
		checkErrStruct, nil)
	scope.Insert(checkErrType.Obj())
	checkErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(checkErrType)), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))

	// type CheckEqualError struct { ... }
	checkEqErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "CheckError", checkErrType, true),
		types.NewField(token.NoPos, pkg, "Out1", types.NewSlice(types.NewInterfaceType(nil, nil)), false),
		types.NewField(token.NoPos, pkg, "Out2", types.NewSlice(types.NewInterfaceType(nil, nil)), false),
	}, nil)
	checkEqErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CheckEqualError", nil),
		checkEqErrStruct, nil)
	scope.Insert(checkEqErrType.Obj())
	checkEqErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(checkEqErrType)), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))

	// func Check(f any, config *Config) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Check",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "f", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "config", types.NewPointer(configType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func CheckEqual(f, g any, config *Config) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CheckEqual",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "f", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "g", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "config", types.NewPointer(configType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Value(t reflect.Type, rand *rand.Rand) (reflect.Value, bool) — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "t", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "rand", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// testing/slogtest
// ============================================================

func buildTestingSlogtestPackage() *types.Package {
	pkg := types.NewPackage("testing/slogtest", "slogtest")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// func Run(t *testing.T, newHandler func(*testing.T) slog.Handler, opts ...Option) — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Run",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "t", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "newHandler", types.Typ[types.Int])),
			nil, false)))

	// slog.Handler stand-in interface { Enabled(ctx, level); Handle(ctx, record); WithAttrs(attrs); WithGroup(name) }
	slogHandlerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Enabled",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "ctx", types.NewInterfaceType(nil, nil)),
					types.NewVar(token.NoPos, nil, "level", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
	}, nil)
	slogHandlerIface.Complete()

	// func TestHandler(h slog.Handler, results func() []map[string]any) error — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TestHandler",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", slogHandlerIface),
				types.NewVar(token.NoPos, pkg, "results", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// go/build/constraint
// ============================================================

func buildGoBuildConstraintPackage() *types.Package {
	pkg := types.NewPackage("go/build/constraint", "constraint")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Expr interface { Eval(ok func(tag string) bool) bool; String() string }
	exprIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Eval",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "ok",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "tag", types.Typ[types.String])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
						false))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
				false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
	}, nil)
	exprIface.Complete()
	exprType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Expr", nil),
		exprIface, nil)
	scope.Insert(exprType.Obj())

	// type TagExpr struct { Tag string }
	tagExprStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Tag", types.Typ[types.String], false),
	}, nil)
	tagExprType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "TagExpr", nil),
		tagExprStruct, nil)
	scope.Insert(tagExprType.Obj())

	// type NotExpr struct { X Expr }
	notExprStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "X", exprIface, false),
	}, nil)
	notExprType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NotExpr", nil),
		notExprStruct, nil)
	scope.Insert(notExprType.Obj())

	// type AndExpr struct { X, Y Expr }
	andExprStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "X", exprIface, false),
		types.NewField(token.NoPos, pkg, "Y", exprIface, false),
	}, nil)
	andExprType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "AndExpr", nil),
		andExprStruct, nil)
	scope.Insert(andExprType.Obj())

	// type OrExpr struct { X, Y Expr }
	orExprStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "X", exprIface, false),
		types.NewField(token.NoPos, pkg, "Y", exprIface, false),
	}, nil)
	orExprType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "OrExpr", nil),
		orExprStruct, nil)
	scope.Insert(orExprType.Obj())

	// type SyntaxError struct { ... }
	syntaxErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Err", types.Typ[types.String], false),
	}, nil)
	syntaxErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SyntaxError", nil),
		syntaxErrStruct, nil)
	scope.Insert(syntaxErrType.Obj())
	syntaxErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(syntaxErrType)), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))

	// func Parse(line string) (Expr, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "line", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", exprIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func IsGoBuild(line string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsGoBuild",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "line", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IsPlusBuild(line string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsPlusBuild",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "line", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func PlusBuildLines(x Expr) ([]string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PlusBuildLines",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", exprIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func GoVersion(x Expr) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GoVersion",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", exprIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// go/doc/comment
// ============================================================

func buildGoDocCommentPackage() *types.Package {
	pkg := types.NewPackage("go/doc/comment", "comment")
	scope := pkg.Scope()

	// type Doc struct { Content []Block; Links []*LinkDef }
	docStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Content", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Links", types.Typ[types.Int], false),
	}, nil)
	docType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Doc", nil),
		docStruct, nil)
	scope.Insert(docType.Obj())

	// type Parser struct { ... }
	parserStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Words", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "LookupPackage", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "LookupSym", types.Typ[types.Int], false),
	}, nil)
	parserType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Parser", nil),
		parserStruct, nil)
	scope.Insert(parserType.Obj())

	// Parser.Parse(text string) *Doc
	parserType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(parserType)), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(docType))),
			false)))

	// type Printer struct { ... }
	printerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "DocLinkURL", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "DocLinkBaseURL", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "HeadingLevel", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "HeadingID", types.Typ[types.Int], false),
	}, nil)
	printerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Printer", nil),
		printerStruct, nil)
	scope.Insert(printerType.Obj())

	// Printer methods
	for _, m := range []string{"HTML", "Markdown", "Text", "Comment"} {
		printerType.AddMethod(types.NewFunc(token.NoPos, pkg, m,
			types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(printerType)), nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "d", types.NewPointer(docType))),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
				false)))
	}

	// type LinkDef, DocLink, etc.
	linkDefStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Text", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "URL", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Used", types.Typ[types.Bool], false),
	}, nil)
	linkDefType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "LinkDef", nil),
		linkDefStruct, nil)
	scope.Insert(linkDefType.Obj())

	// DefaultLookupPackage
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DefaultLookupPackage",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// go/importer
// ============================================================

func buildGoImporterPackage() *types.Package {
	pkg := types.NewPackage("go/importer", "importer")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// types.Importer stand-in interface { Import(path string) (*types.Package, error) }
	// *types.Package simplified as opaque struct pointer
	typesPkgPtr := types.NewPointer(types.NewStruct(nil, nil))
	importerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Import",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "path", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", typesPkgPtr),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	importerIface.Complete()

	// *token.FileSet stand-in
	fsetPtrImp := types.NewPointer(types.NewStruct(nil, nil))

	// func Default() types.Importer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Default",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", importerIface)),
			false)))

	// func For(compiler string, lookup Lookup) types.Importer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "For",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "compiler", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "lookup", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", importerIface)),
			false)))

	// func ForCompiler(fset *token.FileSet, compiler string, lookup Lookup) types.Importer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ForCompiler",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fset", fsetPtrImp),
				types.NewVar(token.NoPos, pkg, "compiler", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "lookup", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", importerIface)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// mime/quotedprintable
// ============================================================

func buildMimeQuotedprintablePackage() *types.Package {
	pkg := types.NewPackage("mime/quotedprintable", "quotedprintable")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSliceQP := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
	ioReaderQP := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceQP)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderQP.Complete()

	// io.Writer interface
	ioWriterQP := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceQP)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterQP.Complete()

	// type Reader struct { ... }
	readerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	readerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		readerStruct, nil)
	scope.Insert(readerType.Obj())

	// func NewReader(r io.Reader) *Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReaderQP)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(readerType))),
			false)))

	// Reader.Read(p []byte) (int, error)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(readerType)), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type Writer struct { Binary bool }
	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Binary", types.Typ[types.Bool], false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())

	// func NewWriter(w io.Writer) *Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterQP)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(writerType))),
			false)))

	// Writer.Write(p []byte) (int, error)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(writerType)), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", byteSliceQP)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Writer.Close() error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(writerType)), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// net/http/httptrace
// ============================================================

func buildNetHTTPHttptracePackage() *types.Package {
	pkg := types.NewPackage("net/http/httptrace", "httptrace")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()

	// Define info structs first so ClientTrace callbacks can reference them

	// net.Conn stand-in for GotConnInfo
	byteSliceHT := types.NewSlice(types.Typ[types.Byte])
	netConnIfaceHT := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceHT)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceHT)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	netConnIfaceHT.Complete()

	// type GotConnInfo struct { ... }
	gotConnInfoStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Conn", netConnIfaceHT, false),
		types.NewField(token.NoPos, pkg, "Reused", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "WasIdle", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "IdleTime", types.Typ[types.Int64], false),
	}, nil)
	gotConnInfoType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "GotConnInfo", nil),
		gotConnInfoStruct, nil)
	scope.Insert(gotConnInfoType.Obj())

	// type DNSStartInfo struct { Host string }
	dnsStartStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Host", types.Typ[types.String], false),
	}, nil)
	dnsStartType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "DNSStartInfo", nil),
		dnsStartStruct, nil)
	scope.Insert(dnsStartType.Obj())

	// type DNSDoneInfo struct { Addrs []net.IPAddr; Err error }
	// net.IPAddr simplified as struct { IP string }
	ipAddrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "IP", types.Typ[types.String], false),
	}, nil)
	dnsDoneStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Addrs", types.NewSlice(ipAddrStruct), false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
		types.NewField(token.NoPos, pkg, "Coalesced", types.Typ[types.Bool], false),
	}, nil)
	dnsDoneType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "DNSDoneInfo", nil),
		dnsDoneStruct, nil)
	scope.Insert(dnsDoneType.Obj())

	// type WroteRequestInfo struct { Err error }
	wroteReqStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	wroteReqType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WroteRequestInfo", nil),
		wroteReqStruct, nil)
	scope.Insert(wroteReqType.Obj())

	// tls.ConnectionState simplified stand-in
	tlsConnStateStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "HandshakeComplete", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "ServerName", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "NegotiatedProtocol", types.Typ[types.String], false),
	}, nil)

	// Callback function signatures for ClientTrace
	// func(hostPort string)
	hostPortFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "hostPort", types.Typ[types.String])),
		nil, false)
	// func()
	voidFn := types.NewSignatureType(nil, nil, nil, nil, nil, false)
	// func(err error)
	errFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "err", errType)),
		nil, false)
	// func(network, addr string)
	netAddrFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "network", types.Typ[types.String]),
			types.NewVar(token.NoPos, nil, "addr", types.Typ[types.String])),
		nil, false)
	// func(network, addr string, err error)
	netAddrErrFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "network", types.Typ[types.String]),
			types.NewVar(token.NoPos, nil, "addr", types.Typ[types.String]),
			types.NewVar(token.NoPos, nil, "err", errType)),
		nil, false)
	// func(GotConnInfo)
	gotConnFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "info", gotConnInfoType)),
		nil, false)
	// func(code int, header http.Header) error — Got1xxResponse callback
	got1xxFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "code", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "header", types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String])))),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
		false)
	// func(DNSStartInfo)
	dnsStartFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "info", dnsStartType)),
		nil, false)
	// func(DNSDoneInfo)
	dnsDoneFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "info", dnsDoneType)),
		nil, false)
	// func(tls.ConnectionState, error)
	tlsDoneFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "state", tlsConnStateStruct),
			types.NewVar(token.NoPos, nil, "err", errType)),
		nil, false)
	// func(WroteRequestInfo)
	wroteReqFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "info", wroteReqType)),
		nil, false)

	// type ClientTrace struct { ... }
	clientTraceStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "GetConn", hostPortFn, false),
		types.NewField(token.NoPos, pkg, "GotConn", gotConnFn, false),
		types.NewField(token.NoPos, pkg, "PutIdleConn", errFn, false),
		types.NewField(token.NoPos, pkg, "GotFirstResponseByte", voidFn, false),
		types.NewField(token.NoPos, pkg, "Got100Continue", voidFn, false),
		types.NewField(token.NoPos, pkg, "Got1xxResponse", got1xxFn, false),
		types.NewField(token.NoPos, pkg, "DNSStart", dnsStartFn, false),
		types.NewField(token.NoPos, pkg, "DNSDone", dnsDoneFn, false),
		types.NewField(token.NoPos, pkg, "ConnectStart", netAddrFn, false),
		types.NewField(token.NoPos, pkg, "ConnectDone", netAddrErrFn, false),
		types.NewField(token.NoPos, pkg, "TLSHandshakeStart", voidFn, false),
		types.NewField(token.NoPos, pkg, "TLSHandshakeDone", tlsDoneFn, false),
		types.NewField(token.NoPos, pkg, "WroteHeaderField", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.NewSlice(types.Typ[types.String]))),
			nil, false), false),
		types.NewField(token.NoPos, pkg, "WroteHeaders", voidFn, false),
		types.NewField(token.NoPos, pkg, "Wait100Continue", voidFn, false),
		types.NewField(token.NoPos, pkg, "WroteRequest", wroteReqFn, false),
	}, nil)
	clientTraceType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ClientTrace", nil),
		clientTraceStruct, nil)
	scope.Insert(clientTraceType.Obj())

	// context.Context stand-in for WithClientTrace/ContextClientTrace
	anyHTCtx := types.NewInterfaceType(nil, nil)
	anyHTCtx.Complete()
	ctxIfaceHT := types.NewInterfaceType([]*types.Func{
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
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyHTCtx)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyHTCtx)),
				false)),
	}, nil)
	ctxIfaceHT.Complete()

	// func WithClientTrace(ctx context.Context, trace *ClientTrace) context.Context
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithClientTrace",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIfaceHT),
				types.NewVar(token.NoPos, pkg, "trace", types.NewPointer(clientTraceType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ctxIfaceHT)),
			false)))

	// func ContextClientTrace(ctx context.Context) *ClientTrace
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ContextClientTrace",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ctx", ctxIfaceHT)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(clientTraceType))),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// net/http/cgi
// ============================================================

func buildNetHTTPCgiPackage() *types.Package {
	pkg := types.NewPackage("net/http/cgi", "cgi")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// *log.Logger (opaque)
	loggerStruct := types.NewStruct(nil, nil)
	loggerPtr := types.NewPointer(loggerStruct)

	// http.ResponseWriter interface { Header(); Write(); WriteHeader() }
	headerMapCGI := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))
	responseWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerMapCGI)),
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
	responseWriter.Complete()

	// io.Writer interface for Stderr field
	ioWriterCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterCGI.Complete()

	// *http.Request (opaque)
	requestStruct := types.NewStruct(nil, nil)
	requestPtr := types.NewPointer(requestStruct)

	// type Handler struct { ... }
	handlerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Root", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Dir", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Env", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "InheritEnv", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Logger", loggerPtr, false),
		types.NewField(token.NoPos, pkg, "Args", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Stderr", ioWriterCGI, false),
	}, nil)
	handlerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Handler", nil),
		handlerStruct, nil)
	scope.Insert(handlerType.Obj())

	// Handler.ServeHTTP(rw http.ResponseWriter, req *http.Request)
	handlerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ServeHTTP",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(handlerType)), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rw", responseWriter),
				types.NewVar(token.NoPos, pkg, "req", requestPtr)),
			nil, false)))

	// func Request() (*http.Request, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Request",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", requestPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func RequestFromMap(params map[string]string) (*http.Request, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RequestFromMap",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "params",
				types.NewMap(types.Typ[types.String], types.Typ[types.String]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", requestPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Serve(handler http.Handler) error — simplified
	// http.Handler with ServeHTTP method
	rwIfaceCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerMapCGI)),
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
	rwIfaceCGI.Complete()
	reqPtrCGI := types.NewPointer(types.NewStruct(nil, nil))
	httpHandlerCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ServeHTTP",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "w", rwIfaceCGI),
					types.NewVar(token.NoPos, nil, "r", reqPtrCGI)),
				nil, false)),
	}, nil)
	httpHandlerCGI.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Serve",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "handler", httpHandlerCGI)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// net/http/fcgi
// ============================================================

func buildNetHTTPFcgiPackage() *types.Package {
	pkg := types.NewPackage("net/http/fcgi", "fcgi")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// var ErrRequestAborted, ErrConnClosed
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrRequestAborted", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrConnClosed", errType))

	// net.Listener interface
	byteSliceFCGI := types.NewSlice(types.Typ[types.Byte])
	netConnFCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceFCGI)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceFCGI)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	netConnFCGI.Complete()
	netAddrFCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Network",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
	}, nil)
	netAddrFCGI.Complete()
	listenerFCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Accept",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", netConnFCGI),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Addr",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", netAddrFCGI)),
				false)),
	}, nil)
	listenerFCGI.Complete()
	// http.Handler interface
	// http.ResponseWriter { Header(); Write(); WriteHeader() }
	headerMapFCGI := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))
	rwIfaceFCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerMapFCGI)),
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
	rwIfaceFCGI.Complete()
	reqPtrFCGI := types.NewPointer(types.NewStruct(nil, nil))
	httpHandlerFCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ServeHTTP",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "w", rwIfaceFCGI),
					types.NewVar(token.NoPos, nil, "r", reqPtrFCGI)),
				nil, false)),
	}, nil)
	httpHandlerFCGI.Complete()
	// func Serve(l net.Listener, handler http.Handler) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Serve",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "l", listenerFCGI),
				types.NewVar(token.NoPos, pkg, "handler", httpHandlerFCGI)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// *http.Request (opaque)
	requestStruct := types.NewStruct(nil, nil)
	requestPtr := types.NewPointer(requestStruct)

	// func ProcessEnv(r *http.Request) map[string]string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ProcessEnv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", requestPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "",
				types.NewMap(types.Typ[types.String], types.Typ[types.String]))),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// image/color/palette
// ============================================================

func buildImageColorPalettePackage() *types.Package {
	pkg := types.NewPackage("image/color/palette", "palette")
	scope := pkg.Scope()

	// color.Color interface { RGBA() (r, g, b, a uint32) }
	colorIfacePal := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIfacePal.Complete()

	// Palette type = []color.Color
	paletteType := types.NewSlice(colorIfacePal)

	// var Plan9 []color.Color
	scope.Insert(types.NewVar(token.NoPos, pkg, "Plan9", paletteType))
	// var WebSafe []color.Color
	scope.Insert(types.NewVar(token.NoPos, pkg, "WebSafe", paletteType))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// runtime/metrics
// ============================================================

func buildRuntimeMetricsPackage() *types.Package {
	pkg := types.NewPackage("runtime/metrics", "metrics")
	scope := pkg.Scope()

	// type Description struct { ... }
	descStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Description", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Kind", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Cumulative", types.Typ[types.Bool], false),
	}, nil)
	descType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Description", nil),
		descStruct, nil)
	scope.Insert(descType.Obj())

	// type ValueKind int
	valueKindType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ValueKind", nil),
		types.Typ[types.Int], nil)
	scope.Insert(valueKindType.Obj())

	// ValueKind constants
	for i, name := range []string{"KindBad", "KindUint64", "KindFloat64", "KindFloat64Histogram"} {
		scope.Insert(types.NewConst(token.NoPos, pkg, name, valueKindType, constant.MakeInt64(int64(i))))
	}

	// type Value struct { ... }
	valueStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "kind", valueKindType, false),
		types.NewField(token.NoPos, pkg, "scalar", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "pointer", types.Typ[types.Int], false),
	}, nil)
	valueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Value", nil),
		valueStruct, nil)
	scope.Insert(valueType.Obj())

	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Kind",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", valueType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueKindType)), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", valueType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", valueType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64Histogram",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", valueType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))

	// type Float64Histogram struct { ... }
	histStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Counts", types.NewSlice(types.Typ[types.Uint64]), false),
		types.NewField(token.NoPos, pkg, "Buckets", types.NewSlice(types.Typ[types.Float64]), false),
	}, nil)
	histType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Float64Histogram", nil),
		histStruct, nil)
	scope.Insert(histType.Obj())

	// type Sample struct { Name string; Value Value }
	sampleStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", valueType, false),
	}, nil)
	sampleType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Sample", nil),
		sampleStruct, nil)
	scope.Insert(sampleType.Obj())

	// func All() []Description
	scope.Insert(types.NewFunc(token.NoPos, pkg, "All",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(descType))),
			false)))

	// func Read(m []Sample)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "m", types.NewSlice(sampleType))),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// runtime/coverage
// ============================================================

func buildRuntimeCoveragePackage() *types.Package {
	pkg := types.NewPackage("runtime/coverage", "coverage")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSliceCov := types.NewSlice(types.Typ[types.Byte])

	// io.Writer interface
	ioWriterCov := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceCov)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterCov.Complete()

	// func WriteCountersDir(dir string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteCountersDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func WriteCounters(w io.Writer) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteCounters",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterCov)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func WriteMetaDir(dir string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteMetaDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func WriteMeta(w io.Writer) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteMeta",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterCov)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ClearCounters() error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ClearCounters",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// plugin
// ============================================================

func buildPluginPackage() *types.Package {
	pkg := types.NewPackage("plugin", "plugin")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Plugin struct { ... }
	pluginStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	pluginType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Plugin", nil),
		pluginStruct, nil)
	scope.Insert(pluginType.Obj())

	// func Open(path string) (*Plugin, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(pluginType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Plugin.Lookup(symName string) (Symbol, error)
	symbolType := types.NewInterfaceType(nil, nil)
	symbolType.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Symbol", symbolType))

	pluginType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(pluginType)), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "symName", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", symbolType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// time/tzdata — embedded timezone database (import for side effect)
// ============================================================

func buildTimeTzdataPackage() *types.Package {
	pkg := types.NewPackage("time/tzdata", "tzdata")
	// This package is imported for its side effect of embedding timezone data.
	// No exported functions or types.
	pkg.MarkComplete()
	return pkg
}

// ============================================================
// structs — struct layout control markers (Go 1.24+)
// ============================================================

func buildStructsPackage() *types.Package {
	pkg := types.NewPackage("structs", "structs")
	scope := pkg.Scope()

	// type HostLayout struct{}
	hostLayoutType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "HostLayout", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(hostLayoutType.Obj())

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// testing/synctest — concurrent testing support (Go 1.25)
// ============================================================

func buildTestingSynctestPackage() *types.Package {
	pkg := types.NewPackage("testing/synctest", "synctest")
	scope := pkg.Scope()

	// func Test(f func()) — runs f in an isolated bubble
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Test",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			nil, false)))

	// func Wait() — waits for goroutines in bubble to block
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Wait",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// go/version — Go version string operations (Go 1.22)
// ============================================================

func buildGoVersionPackage() *types.Package {
	pkg := types.NewPackage("go/version", "version")
	scope := pkg.Scope()

	// func Compare(x, y string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func IsValid(x string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Lang(x string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lang",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// crypto/sha3 — SHA-3 hash functions (Go 1.24)
// ============================================================

func buildCryptoSHA3Package() *types.Package {
	pkg := types.NewPackage("crypto/sha3", "sha3")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()

	// hash.Hash stand-in interface
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

	// type SHA3 struct — opaque
	sha3Struct := types.NewStruct(nil, nil)
	sha3Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SHA3", nil),
		sha3Struct, nil)
	scope.Insert(sha3Type.Obj())

	sha3Ptr := types.NewPointer(sha3Type)
	sha3Recv := types.NewVar(token.NoPos, pkg, "", sha3Ptr)

	// SHA3 methods: Write, Sum, Reset, Size, BlockSize, MarshalBinary, AppendBinary
	sha3Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(sha3Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	sha3Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Sum",
		types.NewSignatureType(sha3Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))
	sha3Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(sha3Recv, nil, nil, nil, nil, false)))
	sha3Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(sha3Recv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	sha3Type.AddMethod(types.NewFunc(token.NoPos, pkg, "BlockSize",
		types.NewSignatureType(sha3Recv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// type SHAKE struct — opaque
	shakeStruct := types.NewStruct(nil, nil)
	shakeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SHAKE", nil),
		shakeStruct, nil)
	scope.Insert(shakeType.Obj())

	shakePtr := types.NewPointer(shakeType)
	shakeRecv := types.NewVar(token.NoPos, pkg, "", shakePtr)

	// SHAKE methods: Write, Read, Reset, BlockSize
	shakeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(shakeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	shakeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(shakeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	shakeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(shakeRecv, nil, nil, nil, nil, false)))
	shakeType.AddMethod(types.NewFunc(token.NoPos, pkg, "BlockSize",
		types.NewSignatureType(shakeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func New224() *SHA3
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New224",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", sha3Ptr)),
			false)))

	// func New256() *SHA3
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New256",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", sha3Ptr)),
			false)))

	// func New384() *SHA3
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New384",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", sha3Ptr)),
			false)))

	// func New512() *SHA3
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New512",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", sha3Ptr)),
			false)))

	// func NewSHAKE128() *SHAKE
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewSHAKE128",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", shakePtr)),
			false)))

	// func NewSHAKE256() *SHAKE
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewSHAKE256",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", shakePtr)),
			false)))

	// func NewCSHAKE128(N, S []byte) *SHAKE
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewCSHAKE128",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "N", byteSlice),
				types.NewVar(token.NoPos, pkg, "S", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", shakePtr)),
			false)))

	// func NewCSHAKE256(N, S []byte) *SHAKE
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewCSHAKE256",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "N", byteSlice),
				types.NewVar(token.NoPos, pkg, "S", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", shakePtr)),
			false)))

	// func Sum224(data []byte) [28]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum224",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewArray(types.Typ[types.Byte], 28))),
			false)))

	// func Sum256(data []byte) [32]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum256",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewArray(types.Typ[types.Byte], 32))),
			false)))

	// func Sum384(data []byte) [48]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum384",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewArray(types.Typ[types.Byte], 48))),
			false)))

	// func Sum512(data []byte) [64]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum512",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewArray(types.Typ[types.Byte], 64))),
			false)))

	// func SumSHAKE128(data []byte, length int) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SumSHAKE128",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", byteSlice),
				types.NewVar(token.NoPos, pkg, "length", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func SumSHAKE256(data []byte, length int) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SumSHAKE256",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", byteSlice),
				types.NewVar(token.NoPos, pkg, "length", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// crypto/hkdf — HMAC-based Extract-and-Expand Key Derivation (Go 1.24)
// ============================================================

func buildCryptoHKDFPackage() *types.Package {
	pkg := types.NewPackage("crypto/hkdf", "hkdf")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()

	// hash.Hash stand-in interface
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

	// hash function type: func() hash.Hash
	hashFuncType := types.NewSignatureType(nil, nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "", hashIface)),
		false)

	// func Extract(h func() hash.Hash, secret, salt []byte) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Extract",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", hashFuncType),
				types.NewVar(token.NoPos, pkg, "secret", byteSlice),
				types.NewVar(token.NoPos, pkg, "salt", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Expand(h func() hash.Hash, pseudorandomKey []byte, info string, keyLength int) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Expand",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", hashFuncType),
				types.NewVar(token.NoPos, pkg, "pseudorandomKey", byteSlice),
				types.NewVar(token.NoPos, pkg, "info", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "keyLength", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Key(h func() hash.Hash, secret, salt []byte, info string, keyLength int) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Key",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", hashFuncType),
				types.NewVar(token.NoPos, pkg, "secret", byteSlice),
				types.NewVar(token.NoPos, pkg, "salt", byteSlice),
				types.NewVar(token.NoPos, pkg, "info", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "keyLength", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// crypto/pbkdf2 — Password-Based Key Derivation Function 2 (Go 1.24)
// ============================================================

func buildCryptoPBKDF2Package() *types.Package {
	pkg := types.NewPackage("crypto/pbkdf2", "pbkdf2")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()

	// hash.Hash stand-in interface
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

	// hash function type: func() hash.Hash
	hashFuncType := types.NewSignatureType(nil, nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "", hashIface)),
		false)

	// func Key(h func() hash.Hash, password string, salt []byte, iter, keyLength int) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Key",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", hashFuncType),
				types.NewVar(token.NoPos, pkg, "password", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "salt", byteSlice),
				types.NewVar(token.NoPos, pkg, "iter", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "keyLength", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// crypto/mlkem — ML-KEM post-quantum key encapsulation (Go 1.24)
// ============================================================

func buildCryptoMLKEMPackage() *types.Package {
	pkg := types.NewPackage("crypto/mlkem", "mlkem")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()

	// constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "SharedKeySize", types.Typ[types.Int],
		constant.MakeInt64(32)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "CiphertextSize768", types.Typ[types.Int],
		constant.MakeInt64(1088)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "EncapsulationKeySize768", types.Typ[types.Int],
		constant.MakeInt64(1184)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "CiphertextSize1024", types.Typ[types.Int],
		constant.MakeInt64(1568)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "EncapsulationKeySize1024", types.Typ[types.Int],
		constant.MakeInt64(1568)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SeedSize", types.Typ[types.Int],
		constant.MakeInt64(64)))

	// type DecapsulationKey768 struct — opaque
	dk768Struct := types.NewStruct(nil, nil)
	dk768Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "DecapsulationKey768", nil),
		dk768Struct, nil)
	scope.Insert(dk768Type.Obj())
	dk768Ptr := types.NewPointer(dk768Type)
	dk768Recv := types.NewVar(token.NoPos, pkg, "", dk768Ptr)

	// type EncapsulationKey768 struct — opaque
	ek768Struct := types.NewStruct(nil, nil)
	ek768Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "EncapsulationKey768", nil),
		ek768Struct, nil)
	scope.Insert(ek768Type.Obj())
	ek768Ptr := types.NewPointer(ek768Type)
	ek768Recv := types.NewVar(token.NoPos, pkg, "", ek768Ptr)

	// type DecapsulationKey1024 struct — opaque
	dk1024Struct := types.NewStruct(nil, nil)
	dk1024Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "DecapsulationKey1024", nil),
		dk1024Struct, nil)
	scope.Insert(dk1024Type.Obj())
	dk1024Ptr := types.NewPointer(dk1024Type)
	dk1024Recv := types.NewVar(token.NoPos, pkg, "", dk1024Ptr)

	// type EncapsulationKey1024 struct — opaque
	ek1024Struct := types.NewStruct(nil, nil)
	ek1024Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "EncapsulationKey1024", nil),
		ek1024Struct, nil)
	scope.Insert(ek1024Type.Obj())
	ek1024Ptr := types.NewPointer(ek1024Type)
	ek1024Recv := types.NewVar(token.NoPos, pkg, "", ek1024Ptr)

	// func GenerateKey768() (*DecapsulationKey768, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GenerateKey768",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", dk768Ptr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func GenerateKey1024() (*DecapsulationKey1024, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GenerateKey1024",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", dk1024Ptr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewDecapsulationKey768(seed []byte) (*DecapsulationKey768, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewDecapsulationKey768",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seed", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", dk768Ptr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewDecapsulationKey1024(seed []byte) (*DecapsulationKey1024, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewDecapsulationKey1024",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seed", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", dk1024Ptr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewEncapsulationKey768(key []byte) (*EncapsulationKey768, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewEncapsulationKey768",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ek768Ptr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewEncapsulationKey1024(key []byte) (*EncapsulationKey1024, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewEncapsulationKey1024",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ek1024Ptr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// DecapsulationKey768 methods
	dk768Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(dk768Recv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))
	dk768Type.AddMethod(types.NewFunc(token.NoPos, pkg, "EncapsulationKey",
		types.NewSignatureType(dk768Recv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ek768Ptr)),
			false)))
	dk768Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Decapsulate",
		types.NewSignatureType(dk768Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ciphertext", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// DecapsulationKey1024 methods
	dk1024Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(dk1024Recv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))
	dk1024Type.AddMethod(types.NewFunc(token.NoPos, pkg, "EncapsulationKey",
		types.NewSignatureType(dk1024Recv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ek1024Ptr)),
			false)))
	dk1024Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Decapsulate",
		types.NewSignatureType(dk1024Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ciphertext", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// EncapsulationKey768 methods
	ek768Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(ek768Recv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))
	ek768Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Encapsulate",
		types.NewSignatureType(ek768Recv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "sharedKey", byteSlice),
				types.NewVar(token.NoPos, pkg, "ciphertext", byteSlice)),
			false)))

	// EncapsulationKey1024 methods
	ek1024Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(ek1024Recv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))
	ek1024Type.AddMethod(types.NewFunc(token.NoPos, pkg, "Encapsulate",
		types.NewSignatureType(ek1024Recv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "sharedKey", byteSlice),
				types.NewVar(token.NoPos, pkg, "ciphertext", byteSlice)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// weak — weak pointers (Go 1.24)
// ============================================================

func buildWeakPackage() *types.Package {
	pkg := types.NewPackage("weak", "weak")
	scope := pkg.Scope()

	// type Pointer struct — opaque (generic Pointer[T] simplified)
	ptrStruct := types.NewStruct(nil, nil)
	ptrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Pointer", nil),
		ptrStruct, nil)
	scope.Insert(ptrType.Obj())

	ptrRecv := types.NewVar(token.NoPos, pkg, "", ptrType)

	// Pointer.Value() unsafe.Pointer — simplified; real API returns *T
	unsafePtrType := types.Typ[types.UnsafePointer]
	ptrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(ptrRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", unsafePtrType)),
			false)))

	// func Make(ptr unsafe.Pointer) Pointer — simplified; real API is Make[T](*T)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Make",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ptr", unsafePtrType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ptrType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// crypto/fips140 — FIPS 140-3 compliance support (Go 1.24)
// ============================================================

func buildCryptoFIPS140Package() *types.Package {
	pkg := types.NewPackage("crypto/fips140", "fips140")
	scope := pkg.Scope()

	// func Enabled() bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Enabled",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// crypto/hpke — Hybrid Public Key Encryption (Go 1.25)
// ============================================================

func buildCryptoHPKEPackage() *types.Package {
	pkg := types.NewPackage("crypto/hpke", "hpke")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()

	// KEM, KDF, AEAD identifier constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "DHKEM_X25519_HKDF_SHA256", types.Typ[types.Uint16],
		constant.MakeUint64(0x0020)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KDF_HKDF_SHA256", types.Typ[types.Uint16],
		constant.MakeUint64(0x0001)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AEAD_AES_128_GCM", types.Typ[types.Uint16],
		constant.MakeUint64(0x0001)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AEAD_AES_256_GCM", types.Typ[types.Uint16],
		constant.MakeUint64(0x0002)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AEAD_ChaCha20Poly1305", types.Typ[types.Uint16],
		constant.MakeUint64(0x0003)))

	// type Sender struct — opaque
	senderStruct := types.NewStruct(nil, nil)
	senderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Sender", nil),
		senderStruct, nil)
	scope.Insert(senderType.Obj())
	senderPtr := types.NewPointer(senderType)
	senderRecv := types.NewVar(token.NoPos, pkg, "", senderPtr)

	// type Recipient struct — opaque
	recipientStruct := types.NewStruct(nil, nil)
	recipientType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Recipient", nil),
		recipientStruct, nil)
	scope.Insert(recipientType.Obj())
	recipientPtr := types.NewPointer(recipientType)
	recipientRecv := types.NewVar(token.NoPos, pkg, "", recipientPtr)

	// Sender.Seal(aad, plaintext []byte) ([]byte, error)
	senderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seal",
		types.NewSignatureType(senderRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "aad", byteSlice),
				types.NewVar(token.NoPos, pkg, "plaintext", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Recipient.Open(aad, ciphertext []byte) ([]byte, error)
	recipientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(recipientRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "aad", byteSlice),
				types.NewVar(token.NoPos, pkg, "ciphertext", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func SetupSender — simplified with opaque ecdh key type
	ecdhPrivKeyPtr := types.NewPointer(types.NewStruct(nil, nil))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetupSender",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "kem", types.Typ[types.Uint16]),
				types.NewVar(token.NoPos, pkg, "kdf", types.Typ[types.Uint16]),
				types.NewVar(token.NoPos, pkg, "aead", types.Typ[types.Uint16]),
				types.NewVar(token.NoPos, pkg, "recipientKey", byteSlice),
				types.NewVar(token.NoPos, pkg, "info", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "encapsulatedKey", byteSlice),
				types.NewVar(token.NoPos, pkg, "sender", senderPtr),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func SetupRecipient — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetupRecipient",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "kem", types.Typ[types.Uint16]),
				types.NewVar(token.NoPos, pkg, "kdf", types.Typ[types.Uint16]),
				types.NewVar(token.NoPos, pkg, "aead", types.Typ[types.Uint16]),
				types.NewVar(token.NoPos, pkg, "privateKey", ecdhPrivKeyPtr),
				types.NewVar(token.NoPos, pkg, "info", byteSlice),
				types.NewVar(token.NoPos, pkg, "encapsulatedKey", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", recipientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseKey(kem uint16, privateKeyBytes []byte) — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "kem", types.Typ[types.Uint16]),
				types.NewVar(token.NoPos, pkg, "privateKeyBytes", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ecdhPrivKeyPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// encoding/json/v2 — JSON v2 API (Go 1.25+)
// ============================================================

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

// ============================================================
// encoding/json/jsontext — low-level JSON text processing (Go 1.25+)
// ============================================================

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

// ============================================================
// testing/cryptotest — crypto testing helpers (Go 1.24)
// ============================================================

func buildTestingCryptotestPackage() *types.Package {
	pkg := types.NewPackage("testing/cryptotest", "cryptotest")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()

	// testing.TB stand-in interface
	emptyIface := types.NewInterfaceType(nil, nil)
	emptyIface.Complete()
	tbIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Error",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "args",
					types.NewSlice(emptyIface))),
				nil, true)),
		types.NewFunc(token.NoPos, nil, "Fatal",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "args",
					types.NewSlice(emptyIface))),
				nil, true)),
		types.NewFunc(token.NoPos, nil, "Helper",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
	}, nil)
	tbIface.Complete()

	// hash.Hash stand-in interface
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

	// hash function type: func() hash.Hash
	hashFuncType := types.NewSignatureType(nil, nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "", hashIface)),
		false)

	// func TestHash(t testing.TB, newHash func() hash.Hash)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TestHash",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "t", tbIface),
				types.NewVar(token.NoPos, pkg, "newHash", hashFuncType)),
			nil, false)))

	// cipher.Block stand-in interface
	blockIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
		types.NewFunc(token.NoPos, nil, "Encrypt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", byteSlice),
					types.NewVar(token.NoPos, nil, "src", byteSlice)),
				nil, false)),
		types.NewFunc(token.NoPos, nil, "Decrypt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", byteSlice),
					types.NewVar(token.NoPos, nil, "src", byteSlice)),
				nil, false)),
	}, nil)
	blockIface.Complete()

	// block function type: func(key []byte) (cipher.Block, error)
	blockFuncType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "key", byteSlice)),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", blockIface),
			types.NewVar(token.NoPos, nil, "", errType)),
		false)

	// func TestBlock(t testing.TB, keySize int, newBlock func(key []byte) (cipher.Block, error))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TestBlock",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "t", tbIface),
				types.NewVar(token.NoPos, pkg, "keySize", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "newBlock", blockFuncType)),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// runtime/cgo — CGo handle support (Go 1.17+)
// ============================================================

func buildRuntimeCgoPackage() *types.Package {
	pkg := types.NewPackage("runtime/cgo", "cgo")
	scope := pkg.Scope()

	// type Handle uintptr
	handleType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Handle", nil),
		types.Typ[types.Uintptr], nil)
	scope.Insert(handleType.Obj())

	handleRecv := types.NewVar(token.NoPos, pkg, "", handleType)
	emptyIface := types.NewInterfaceType(nil, nil)
	emptyIface.Complete()

	// Handle.Value() any
	handleType.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(handleRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", emptyIface)),
			false)))

	// Handle.Delete()
	handleType.AddMethod(types.NewFunc(token.NoPos, pkg, "Delete",
		types.NewSignatureType(handleRecv, nil, nil, nil, nil, false)))

	// func NewHandle(v any) Handle
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewHandle",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", emptyIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handleType)),
			false)))

	// type Incomplete struct — incomplete C type marker
	incompleteStruct := types.NewStruct(nil, nil)
	incompleteType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Incomplete", nil),
		incompleteStruct, nil)
	scope.Insert(incompleteType.Obj())

	pkg.MarkComplete()
	return pkg
}

// ============================================================
// syscall/js — JavaScript interop for WASM (Go 1.11+)
// ============================================================

func buildSyscallJSPackage() *types.Package {
	pkg := types.NewPackage("syscall/js", "js")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	emptyIface := types.NewInterfaceType(nil, nil)
	emptyIface.Complete()

	// type Type int
	typeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Type", nil),
		types.Typ[types.Int], nil)
	scope.Insert(typeType.Obj())

	typeRecv := types.NewVar(token.NoPos, pkg, "", typeType)
	typeType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(typeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Type constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeUndefined", typeType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeNull", typeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeBoolean", typeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeNumber", typeType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeString", typeType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeSymbol", typeType, constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeObject", typeType, constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeFunction", typeType, constant.MakeInt64(7)))

	// type Value struct — opaque
	valueStruct := types.NewStruct(nil, nil)
	valueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Value", nil),
		valueStruct, nil)
	scope.Insert(valueType.Obj())

	valueRecv := types.NewVar(token.NoPos, pkg, "", valueType)
	anySlice := types.NewSlice(emptyIface)

	// Value methods
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bool",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Truthy",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsNull",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsUndefined",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsNaN",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Type",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", typeType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "x", emptyIface)),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Delete",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.Typ[types.String])),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetIndex",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "x", emptyIface)),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Length",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Call",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "m", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			true)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Invoke",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			true)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			true)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "InstanceOf",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "t", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// type Error struct { Value Value }
	errorStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Value", valueType, false),
	}, nil)
	errorType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Error", nil),
		errorStruct, nil)
	scope.Insert(errorType.Obj())

	errorPtrRecv := types.NewVar(token.NoPos, pkg, "", types.NewPointer(errorType))
	errorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(errorPtrRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// type ValueError struct — opaque
	valueErrorStruct := types.NewStruct(nil, nil)
	valueErrorType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ValueError", nil),
		valueErrorStruct, nil)
	scope.Insert(valueErrorType.Obj())

	valueErrorPtrRecv := types.NewVar(token.NoPos, pkg, "", types.NewPointer(valueErrorType))
	valueErrorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(valueErrorPtrRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// type Func struct — opaque
	funcStruct := types.NewStruct(nil, nil)
	funcType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Func", nil),
		funcStruct, nil)
	scope.Insert(funcType.Obj())

	funcRecv := types.NewVar(token.NoPos, pkg, "", funcType)
	funcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Release",
		types.NewSignatureType(funcRecv, nil, nil, nil, nil, false)))

	// func FuncOf(fn func(this Value, args []Value) any) Func
	valueSlice := types.NewSlice(valueType)
	fnType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "this", valueType),
			types.NewVar(token.NoPos, pkg, "args", valueSlice)),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", emptyIface)),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FuncOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fn", fnType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", funcType)),
			false)))

	// func Global() Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Global",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func Null() Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Null",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func Undefined() Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Undefined",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func ValueOf(x any) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ValueOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", emptyIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func CopyBytesToGo(dst []byte, src Value) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CopyBytesToGo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", byteSlice),
				types.NewVar(token.NoPos, pkg, "src", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func CopyBytesToJS(dst Value, src []byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CopyBytesToJS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", valueType),
				types.NewVar(token.NoPos, pkg, "src", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	pkg.MarkComplete()
	return pkg
}
