// Package type stubs for crypto packages: crypto, crypto/sha256,
// crypto/sha512, crypto/sha1, crypto/md5, crypto/rand, crypto/hmac,
// crypto/aes, crypto/cipher, crypto/tls, crypto/x509, crypto/elliptic,
// crypto/ecdsa, crypto/rsa, crypto/ed25519, crypto/subtle, crypto/des,
// crypto/rc4, crypto/dsa, crypto/ecdh.
package compiler

import (
	"go/constant"
	"go/token"
	"go/types"
)

func init() {
	RegisterPackage("crypto/aes", buildCryptoAESPackage)
	RegisterPackage("crypto/cipher", buildCryptoCipherPackage)
	RegisterPackage("crypto/des", buildCryptoDESPackage)
	RegisterPackage("crypto/dsa", buildCryptoDSAPackage)
	RegisterPackage("crypto/ecdh", buildCryptoECDHPackage)
	RegisterPackage("crypto/ecdsa", buildCryptoECDSAPackage)
	RegisterPackage("crypto/ed25519", buildCryptoEd25519Package)
	RegisterPackage("crypto/elliptic", buildCryptoEllipticPackage)
	RegisterPackage("crypto/fips140", buildCryptoFIPS140Package)
	RegisterPackage("crypto/hkdf", buildCryptoHKDFPackage)
	RegisterPackage("crypto/hmac", buildCryptoHMACPackage)
	RegisterPackage("crypto/hpke", buildCryptoHPKEPackage)
	RegisterPackage("crypto/md5", buildCryptoMD5Package)
	RegisterPackage("crypto/mlkem", buildCryptoMLKEMPackage)
	RegisterPackage("crypto/pbkdf2", buildCryptoPBKDF2Package)
	RegisterPackage("crypto", buildCryptoPackage)
	RegisterPackage("crypto/rc4", buildCryptoRC4Package)
	RegisterPackage("crypto/rsa", buildCryptoRSAPackage)
	RegisterPackage("crypto/rand", buildCryptoRandPackage)
	RegisterPackage("crypto/sha1", buildCryptoSHA1Package)
	RegisterPackage("crypto/sha256", buildCryptoSHA256Package)
	RegisterPackage("crypto/sha3", buildCryptoSHA3Package)
	RegisterPackage("crypto/sha512", buildCryptoSHA512Package)
	RegisterPackage("crypto/subtle", buildCryptoSubtlePackage)
	RegisterPackage("crypto/tls", buildCryptoTLSPackage)
	RegisterPackage("crypto/x509", buildCryptoX509Package)
	RegisterPackage("crypto/x509/pkix", buildCryptoX509PkixPackage)
}

// buildCryptoAESPackage creates the type-checked crypto/aes package stub.
func buildCryptoAESPackage() *types.Package {
	pkg := types.NewPackage("crypto/aes", "aes")
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
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", keySizeErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(keySizeErrType.Obj())

	scope.Insert(types.NewConst(token.NoPos, pkg, "BlockSize", types.Typ[types.Int], constant.MakeInt64(16)))

	// func NewCipher(key []byte) (cipher.Block, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewCipher",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", cipherBlock),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildCryptoCipherPackage creates the type-checked crypto/cipher package stub.
func buildCryptoCipherPackage() *types.Package {
	pkg := types.NewPackage("crypto/cipher", "cipher")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// Block interface
	blockIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "Encrypt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", byteSlice),
					types.NewVar(token.NoPos, nil, "src", byteSlice)),
				nil, false)),
		types.NewFunc(token.NoPos, pkg, "Decrypt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", byteSlice),
					types.NewVar(token.NoPos, nil, "src", byteSlice)),
				nil, false)),
	}, nil)
	blockIface.Complete()
	blockType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Block", nil),
		blockIface, nil)
	scope.Insert(blockType.Obj())

	// Stream interface
	streamIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "XORKeyStream",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", byteSlice),
					types.NewVar(token.NoPos, nil, "src", byteSlice)),
				nil, false)),
	}, nil)
	streamIface.Complete()
	streamType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Stream", nil),
		streamIface, nil)
	scope.Insert(streamType.Obj())

	// AEAD interface
	aeadIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "NonceSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "Overhead",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "Seal",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", byteSlice),
					types.NewVar(token.NoPos, nil, "nonce", byteSlice),
					types.NewVar(token.NoPos, nil, "plaintext", byteSlice),
					types.NewVar(token.NoPos, nil, "additionalData", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)),
		types.NewFunc(token.NoPos, pkg, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", byteSlice),
					types.NewVar(token.NoPos, nil, "nonce", byteSlice),
					types.NewVar(token.NoPos, nil, "ciphertext", byteSlice),
					types.NewVar(token.NoPos, nil, "additionalData", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", byteSlice),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	aeadIface.Complete()
	aeadType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "AEAD", nil),
		aeadIface, nil)
	scope.Insert(aeadType.Obj())

	// BlockMode interface
	blockModeIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "CryptBlocks",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", byteSlice),
					types.NewVar(token.NoPos, nil, "src", byteSlice)),
				nil, false)),
	}, nil)
	blockModeIface.Complete()
	blockModeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "BlockMode", nil),
		blockModeIface, nil)
	scope.Insert(blockModeType.Obj())

	// func NewGCM(cipher Block) (AEAD, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewGCM",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "cipher", blockType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", aeadType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewCFBEncrypter(block Block, iv []byte) Stream
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewCFBEncrypter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "block", blockType),
				types.NewVar(token.NoPos, pkg, "iv", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", streamType)),
			false)))

	// func NewCFBDecrypter(block Block, iv []byte) Stream
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewCFBDecrypter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "block", blockType),
				types.NewVar(token.NoPos, pkg, "iv", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", streamType)),
			false)))

	// func NewCBCEncrypter(b Block, iv []byte) BlockMode
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewCBCEncrypter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", blockType),
				types.NewVar(token.NoPos, pkg, "iv", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", blockModeType)),
			false)))

	// func NewCBCDecrypter(b Block, iv []byte) BlockMode
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewCBCDecrypter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", blockType),
				types.NewVar(token.NoPos, pkg, "iv", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", blockModeType)),
			false)))

	// func NewCTR(block Block, iv []byte) Stream
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewCTR",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "block", blockType),
				types.NewVar(token.NoPos, pkg, "iv", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", streamType)),
			false)))

	// func NewOFB(b Block, iv []byte) Stream
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewOFB",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "b", blockType),
				types.NewVar(token.NoPos, pkg, "iv", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", streamType)),
			false)))

	// func NewGCMWithNonceSize(cipher Block, size int) (AEAD, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewGCMWithNonceSize",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "cipher", blockType),
				types.NewVar(token.NoPos, pkg, "size", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", aeadType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewGCMWithTagSize(cipher Block, tagSize int) (AEAD, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewGCMWithTagSize",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "cipher", blockType),
				types.NewVar(token.NoPos, pkg, "tagSize", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", aeadType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.Reader interface for StreamReader
	cipherIOReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	cipherIOReader.Complete()

	// io.Writer interface for StreamWriter
	cipherIOWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	cipherIOWriter.Complete()

	// type StreamReader struct { S Stream; R io.Reader }
	streamReaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "S", streamType, false),
		types.NewField(token.NoPos, pkg, "R", cipherIOReader, false),
	}, nil)
	streamReaderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "StreamReader", nil),
		streamReaderStruct, nil)
	scope.Insert(streamReaderType.Obj())
	streamReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", streamReaderType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "dst", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))

	// type StreamWriter struct { S Stream; W io.Writer; Err error }
	streamWriterStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "S", streamType, false),
		types.NewField(token.NoPos, pkg, "W", cipherIOWriter, false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	streamWriterType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "StreamWriter", nil),
		streamWriterStruct, nil)
	scope.Insert(streamWriterType.Obj())
	streamWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "w", streamWriterType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "src", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	streamWriterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "w", streamWriterType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

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

// buildCryptoECDSAPackage creates the type-checked crypto/ecdsa package stub.
func buildCryptoECDSAPackage() *types.Package {
	pkg := types.NewPackage("crypto/ecdsa", "ecdsa")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
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

	// *big.Int opaque pointer stand-in
	bigIntPtr := types.NewPointer(types.NewStruct(nil, nil))

	// *elliptic.CurveParams opaque pointer stand-in
	curveParamsPtr := types.NewPointer(types.NewStruct(nil, nil))

	// elliptic.Curve stand-in interface
	curveIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Params",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", curveParamsPtr)), false)),
		types.NewFunc(token.NoPos, nil, "IsOnCurve",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", bigIntPtr),
					types.NewVar(token.NoPos, nil, "y", bigIntPtr)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
	}, nil)
	curveIface.Complete()

	// type PublicKey struct { Curve elliptic.Curve; X, Y *big.Int }
	pubStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Curve", curveIface, false),
		types.NewField(token.NoPos, pkg, "X", bigIntPtr, false),
		types.NewField(token.NoPos, pkg, "Y", bigIntPtr, false),
	}, nil)
	pubType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PublicKey", nil),
		pubStruct, nil)
	scope.Insert(pubType.Obj())

	// type PrivateKey struct { PublicKey; D *big.Int }
	privStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "PublicKey", pubType, true), // embedded
		types.NewField(token.NoPos, pkg, "D", bigIntPtr, false),
	}, nil)
	privType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PrivateKey", nil),
		privStruct, nil)
	scope.Insert(privType.Obj())

	// func GenerateKey(c elliptic.Curve, rand io.Reader) (*PrivateKey, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GenerateKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", curveIface),
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(privType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	privPtr := types.NewPointer(privType)
	pubPtr := types.NewPointer(pubType)

	// *ecdh.PublicKey / *ecdh.PrivateKey opaque pointers for ECDH() returns
	ecdhPubPtr := types.NewPointer(types.NewStruct(nil, nil))
	ecdhPrivPtr := types.NewPointer(types.NewStruct(nil, nil))

	// crypto.SignerOpts stand-in (has HashFunc() crypto.Hash method)
	signerOptsIfaceECDSA := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "HashFunc",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	signerOptsIfaceECDSA.Complete()

	// PublicKey methods
	pubType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "pub", pubPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	pubType.AddMethod(types.NewFunc(token.NoPos, pkg, "ECDH",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "pub", pubPtr), nil, nil,
			nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", ecdhPubPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// PrivateKey methods
	privRecv := types.NewVar(token.NoPos, nil, "priv", privPtr)
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Public",
		types.NewSignatureType(privRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
			false)))
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sign",
		types.NewSignatureType(privRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "rand", ioReaderIface),
				types.NewVar(token.NoPos, nil, "digest", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "opts", signerOptsIfaceECDSA)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(privRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "ECDH",
		types.NewSignatureType(privRecv, nil, nil,
			nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", ecdhPrivPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Package-level functions
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SignASN1",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "priv", privPtr),
				types.NewVar(token.NoPos, pkg, "hash", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "VerifyASN1",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pub", pubPtr),
				types.NewVar(token.NoPos, pkg, "hash", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "sig", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// Legacy Sign function: func Sign(rand io.Reader, priv *PrivateKey, hash []byte) (r, s *big.Int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sign",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "priv", privPtr),
				types.NewVar(token.NoPos, pkg, "hash", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", bigIntPtr),
				types.NewVar(token.NoPos, pkg, "s", bigIntPtr),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// Legacy Verify function: func Verify(pub *PublicKey, hash []byte, r, s *big.Int) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Verify",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pub", pubPtr),
				types.NewVar(token.NoPos, pkg, "hash", byteSlice),
				types.NewVar(token.NoPos, pkg, "r", bigIntPtr),
				types.NewVar(token.NoPos, pkg, "s", bigIntPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// Go 1.25 encoding functions
	// func ParseRawPrivateKey(key []byte, curve elliptic.Curve) (*PrivateKey, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseRawPrivateKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", byteSlice),
				types.NewVar(token.NoPos, pkg, "curve", curveIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", privPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseUncompressedPublicKey(curve elliptic.Curve, key []byte) (*PublicKey, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseUncompressedPublicKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "curve", curveIface),
				types.NewVar(token.NoPos, pkg, "key", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", pubPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// (*PrivateKey).Bytes() []byte
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(privRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))

	// (*PublicKey).Bytes() []byte
	pubType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "pub", pubPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildCryptoEd25519Package creates the type-checked crypto/ed25519 package stub.
func buildCryptoEd25519Package() *types.Package {
	pkg := types.NewPackage("crypto/ed25519", "ed25519")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
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

	pubType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PublicKey", nil),
		types.NewSlice(types.Typ[types.Byte]), nil)
	scope.Insert(pubType.Obj())

	// PublicKey.Equal(x crypto.PublicKey) bool
	pubType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "pub", pubType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	privType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PrivateKey", nil),
		types.NewSlice(types.Typ[types.Byte]), nil)
	scope.Insert(privType.Obj())

	// func GenerateKey(rand io.Reader) (PublicKey, PrivateKey, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GenerateKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "rand", ioReaderIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", pubType),
				types.NewVar(token.NoPos, pkg, "", privType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sign",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "privateKey", privType),
				types.NewVar(token.NoPos, pkg, "message", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "Verify",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "publicKey", pubType),
				types.NewVar(token.NoPos, pkg, "message", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "sig", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// PrivateKey methods
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Public",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "priv", privType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
			false)))
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seed",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "priv", privType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))
	// crypto.SignerOpts stand-in (has HashFunc() crypto.Hash method)
	signerOptsIfaceEd := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "HashFunc",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	signerOptsIfaceEd.Complete()

	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sign",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "priv", privType), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "rand", ioReaderIface),
				types.NewVar(token.NoPos, nil, "message", byteSlice),
				types.NewVar(token.NoPos, nil, "opts", signerOptsIfaceEd)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "priv", privType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func NewKeyFromSeed(seed []byte) PrivateKey
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewKeyFromSeed",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seed", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", privType)),
			false)))

	// type Options struct { Hash crypto.Hash; Context string }
	edOptsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Hash", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Context", types.Typ[types.String], false),
	}, nil)
	edOptsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Options", nil),
		edOptsStruct, nil)
	scope.Insert(edOptsType.Obj())

	// Options.HashFunc() crypto.Hash
	edOptsType.AddMethod(types.NewFunc(token.NoPos, pkg, "HashFunc",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "o", types.NewPointer(edOptsType)), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// func VerifyWithOptions(publicKey PublicKey, message, sig []byte, opts *Options) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "VerifyWithOptions",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "publicKey", pubType),
				types.NewVar(token.NoPos, pkg, "message", byteSlice),
				types.NewVar(token.NoPos, pkg, "sig", byteSlice),
				types.NewVar(token.NoPos, pkg, "opts", types.NewPointer(edOptsType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	scope.Insert(types.NewConst(token.NoPos, pkg, "PublicKeySize", types.Typ[types.Int], constant.MakeInt64(32)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "PrivateKeySize", types.Typ[types.Int], constant.MakeInt64(64)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SignatureSize", types.Typ[types.Int], constant.MakeInt64(64)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SeedSize", types.Typ[types.Int], constant.MakeInt64(32)))

	pkg.MarkComplete()
	return pkg
}

// buildCryptoEllipticPackage creates the type-checked crypto/elliptic package stub.
func buildCryptoEllipticPackage() *types.Package {
	pkg := types.NewPackage("crypto/elliptic", "elliptic")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	bigIntType := types.NewPointer(types.NewStruct(nil, nil)) // *big.Int opaque pointer stand-in

	// io.Reader stand-in for rand parameter
	ioReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
	}, nil)
	ioReaderIface.Complete()

	// type Curve interface
	curveIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Params",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)),
		types.NewFunc(token.NoPos, pkg, "IsOnCurve",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", bigIntType),
					types.NewVar(token.NoPos, nil, "y", bigIntType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Add",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x1", bigIntType),
					types.NewVar(token.NoPos, nil, "y1", bigIntType),
					types.NewVar(token.NoPos, nil, "x2", bigIntType),
					types.NewVar(token.NoPos, nil, "y2", bigIntType)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", bigIntType),
					types.NewVar(token.NoPos, nil, "y", bigIntType)), false)),
		types.NewFunc(token.NoPos, pkg, "Double",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x1", bigIntType),
					types.NewVar(token.NoPos, nil, "y1", bigIntType)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", bigIntType),
					types.NewVar(token.NoPos, nil, "y", bigIntType)), false)),
		types.NewFunc(token.NoPos, pkg, "ScalarMult",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "Bx", bigIntType),
					types.NewVar(token.NoPos, nil, "By", bigIntType),
					types.NewVar(token.NoPos, nil, "k", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", bigIntType),
					types.NewVar(token.NoPos, nil, "y", bigIntType)), false)),
		types.NewFunc(token.NoPos, pkg, "ScalarBaseMult",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "k", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", bigIntType),
					types.NewVar(token.NoPos, nil, "y", bigIntType)), false)),
	}, nil)
	curveIface.Complete()
	curveType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Curve", nil), curveIface, nil)
	scope.Insert(curveType.Obj())

	// type CurveParams struct
	curveParamsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "P", bigIntType, false),
		types.NewField(token.NoPos, pkg, "N", bigIntType, false),
		types.NewField(token.NoPos, pkg, "B", bigIntType, false),
		types.NewField(token.NoPos, pkg, "Gx", bigIntType, false),
		types.NewField(token.NoPos, pkg, "Gy", bigIntType, false),
		types.NewField(token.NoPos, pkg, "BitSize", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
	}, nil)
	curveParamsType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CurveParams", nil), curveParamsStruct, nil)
	scope.Insert(curveParamsType.Obj())

	// func P256/P384/P521/P224() Curve
	for _, name := range []string{"P256", "P384", "P521", "P224"} {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", curveType)), false)))
	}

	// func GenerateKey(curve Curve, rand io.Reader) (priv []byte, x, y *big.Int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GenerateKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "curve", curveType),
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "priv", byteSlice),
				types.NewVar(token.NoPos, pkg, "x", bigIntType),
				types.NewVar(token.NoPos, pkg, "y", bigIntType),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func Marshal(curve Curve, x, y *big.Int) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Marshal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "curve", curveType),
				types.NewVar(token.NoPos, pkg, "x", bigIntType),
				types.NewVar(token.NoPos, pkg, "y", bigIntType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func MarshalCompressed(curve Curve, x, y *big.Int) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MarshalCompressed",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "curve", curveType),
				types.NewVar(token.NoPos, pkg, "x", bigIntType),
				types.NewVar(token.NoPos, pkg, "y", bigIntType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func Unmarshal(curve Curve, data []byte) (x, y *big.Int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unmarshal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "curve", curveType),
				types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", bigIntType),
				types.NewVar(token.NoPos, pkg, "y", bigIntType)),
			false)))

	// func UnmarshalCompressed(curve Curve, data []byte) (x, y *big.Int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UnmarshalCompressed",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "curve", curveType),
				types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", bigIntType),
				types.NewVar(token.NoPos, pkg, "y", bigIntType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

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

// buildCryptoHMACPackage creates the type-checked crypto/hmac package stub.
func buildCryptoHMACPackage() *types.Package {
	pkg := types.NewPackage("crypto/hmac", "hmac")
	scope := pkg.Scope()

	// hash.Hash interface
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()
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

	// func() hash.Hash — hash factory function type
	hashFactoryFn := types.NewSignatureType(nil, nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "", hashIface)),
		false)

	// func New(h func() hash.Hash, key []byte) hash.Hash
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", hashFactoryFn),
				types.NewVar(token.NoPos, pkg, "key", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)),
			false)))

	// func Equal(mac1, mac2 []byte) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "mac1", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "mac2", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

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

// buildCryptoMD5Package creates the type-checked crypto/md5 package stub.
func buildCryptoMD5Package() *types.Package {
	pkg := types.NewPackage("crypto/md5", "md5")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()

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

	// const Size = 16
	scope.Insert(types.NewConst(token.NoPos, pkg, "Size", types.Typ[types.Int],
		constant.MakeInt64(16)))

	// const BlockSize = 64
	scope.Insert(types.NewConst(token.NoPos, pkg, "BlockSize", types.Typ[types.Int],
		constant.MakeInt64(64)))

	// func Sum(data []byte) [16]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewArray(types.Typ[types.Byte], 16))),
			false)))

	// func New() hash.Hash
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)),
			false)))

	pkg.MarkComplete()
	return pkg
}

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

// buildCryptoRSAPackage creates the type-checked crypto/rsa package stub.
func buildCryptoRSAPackage() *types.Package {
	pkg := types.NewPackage("crypto/rsa", "rsa")
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

	// hash.Hash stand-in for EncryptOAEP/DecryptOAEP
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

	// type PublicKey struct { N *big.Int; E int }
	pubStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "N", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "E", types.Typ[types.Int], false),
	}, nil)
	pubType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PublicKey", nil),
		pubStruct, nil)
	scope.Insert(pubType.Obj())
	pubPtr := types.NewPointer(pubType)

	// PublicKey.Size() int
	pubType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "pub", pubPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	// PublicKey.Equal(x interface{}) bool
	pubType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "pub", pubPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// type CRTValue struct { Exp, Coeff, R *big.Int }
	crtValueStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Exp", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Coeff", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "R", types.Typ[types.Int], false),
	}, nil)
	crtValueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CRTValue", nil),
		crtValueStruct, nil)
	scope.Insert(crtValueType.Obj())

	// type PrecomputedValues struct { Dp, Dq, Qinv *big.Int; CRTValues []CRTValue }
	precompStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dp", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Dq", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Qinv", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "CRTValues", types.NewSlice(crtValueType), false),
	}, nil)
	precompType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PrecomputedValues", nil),
		precompStruct, nil)
	scope.Insert(precompType.Obj())

	// type PKCS1v15DecryptOptions struct { SessionKeyLen int }
	pkcs1v15DecOptStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "SessionKeyLen", types.Typ[types.Int], false),
	}, nil)
	pkcs1v15DecOptType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PKCS1v15DecryptOptions", nil),
		pkcs1v15DecOptStruct, nil)
	scope.Insert(pkcs1v15DecOptType.Obj())

	// type PrivateKey struct { PublicKey; D *big.Int; Primes []*big.Int; Precomputed PrecomputedValues }
	privStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "PublicKey", pubType, false),
		types.NewField(token.NoPos, pkg, "D", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Primes", types.NewSlice(types.NewPointer(types.Typ[types.Int])), false),
		types.NewField(token.NoPos, pkg, "Precomputed", precompType, false),
	}, nil)
	privType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PrivateKey", nil),
		privStruct, nil)
	scope.Insert(privType.Obj())
	privPtr := types.NewPointer(privType)

	// PrivateKey methods
	privRecv := types.NewVar(token.NoPos, nil, "priv", privPtr)
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Public",
		types.NewSignatureType(privRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
			false)))
	// crypto.SignerOpts stand-in (has HashFunc() crypto.Hash method)
	signerOptsIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "HashFunc",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	signerOptsIface.Complete()

	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sign",
		types.NewSignatureType(privRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "rand", ioReaderIface),
				types.NewVar(token.NoPos, nil, "digest", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "opts", signerOptsIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Validate",
		types.NewSignatureType(privRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	// PrivateKey.Decrypt(rand io.Reader, ciphertext []byte, opts crypto.DecrypterOpts) ([]byte, error)
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Decrypt",
		types.NewSignatureType(privRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "rand", ioReaderIface),
				types.NewVar(token.NoPos, nil, "ciphertext", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "opts", types.NewInterfaceType(nil, nil))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	// PrivateKey.Precompute()
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Precompute",
		types.NewSignatureType(privRecv, nil, nil, nil, nil, false)))
	// PrivateKey.Equal(x crypto.PrivateKey) bool
	privType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(privRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// type PSSOptions struct
	pssOptsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "SaltLength", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Hash", types.Typ[types.Int], false),
	}, nil)
	pssOptsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PSSOptions", nil),
		pssOptsStruct, nil)
	scope.Insert(pssOptsType.Obj())

	// type OAEPOptions struct
	oaepOptsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Hash", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Label", types.NewSlice(types.Typ[types.Byte]), false),
	}, nil)
	oaepOptsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "OAEPOptions", nil),
		oaepOptsStruct, nil)
	scope.Insert(oaepOptsType.Obj())

	// PSSOptions.HashFunc() crypto.Hash method
	pssOptsType.AddMethod(types.NewFunc(token.NoPos, pkg, "HashFunc",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "opts", types.NewPointer(pssOptsType)), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// PSSSaltLengthAuto and PSSSaltLengthEqualsHash constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "PSSSaltLengthAuto", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "PSSSaltLengthEqualsHash", types.Typ[types.Int], constant.MakeInt64(-1)))

	// Error variables
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrDecryption", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrVerification", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrMessageTooLong", errType))

	// func GenerateKey(random io.Reader, bits int) (*PrivateKey, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GenerateKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "random", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "bits", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", privPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func SignPKCS1v15(rand io.Reader, priv *PrivateKey, hash crypto.Hash, hashed []byte) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SignPKCS1v15",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "priv", privPtr),
				types.NewVar(token.NoPos, pkg, "hash", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "hashed", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func VerifyPKCS1v15(pub *PublicKey, hash crypto.Hash, hashed []byte, sig []byte) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "VerifyPKCS1v15",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pub", pubPtr),
				types.NewVar(token.NoPos, pkg, "hash", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "hashed", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "sig", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func SignPSS(rand io.Reader, priv *PrivateKey, hash crypto.Hash, digest []byte, opts *PSSOptions) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SignPSS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "priv", privPtr),
				types.NewVar(token.NoPos, pkg, "hash", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "digest", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "opts", types.NewPointer(pssOptsType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func VerifyPSS(pub *PublicKey, hash crypto.Hash, digest []byte, sig []byte, opts *PSSOptions) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "VerifyPSS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pub", pubPtr),
				types.NewVar(token.NoPos, pkg, "hash", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "digest", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "sig", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "opts", types.NewPointer(pssOptsType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func EncryptOAEP(hash hash.Hash, random io.Reader, pub *PublicKey, msg []byte, label []byte) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EncryptOAEP",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "hash", hashHashIface),
				types.NewVar(token.NoPos, pkg, "random", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "pub", pubPtr),
				types.NewVar(token.NoPos, pkg, "msg", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "label", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DecryptOAEP(hash hash.Hash, random io.Reader, priv *PrivateKey, ciphertext []byte, label []byte) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecryptOAEP",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "hash", hashHashIface),
				types.NewVar(token.NoPos, pkg, "random", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "priv", privPtr),
				types.NewVar(token.NoPos, pkg, "ciphertext", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "label", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func EncryptPKCS1v15(rand io.Reader, pub *PublicKey, msg []byte) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EncryptPKCS1v15",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "pub", pubPtr),
				types.NewVar(token.NoPos, pkg, "msg", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DecryptPKCS1v15(rand io.Reader, priv *PrivateKey, ciphertext []byte) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecryptPKCS1v15",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "priv", privPtr),
				types.NewVar(token.NoPos, pkg, "ciphertext", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DecryptPKCS1v15SessionKey(rand io.Reader, priv *PrivateKey, ciphertext []byte, key []byte) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecryptPKCS1v15SessionKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "priv", privPtr),
				types.NewVar(token.NoPos, pkg, "ciphertext", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "key", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func GenerateMultiPrimeKey(random io.Reader, nprimes int, bits int) (*PrivateKey, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GenerateMultiPrimeKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "random", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "nprimes", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "bits", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", privPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildCryptoRandPackage creates the type-checked crypto/rand package stub.
func buildCryptoRandPackage() *types.Package {
	pkg := types.NewPackage("crypto/rand", "rand")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface for Reader var and function params
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

	// var Reader io.Reader
	scope.Insert(types.NewVar(token.NoPos, pkg, "Reader", ioReaderIface))

	// func Read(b []byte) (n int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// *big.Int stand-in (opaque pointer)
	bigIntStruct := types.NewStruct(nil, nil)
	bigIntType := types.NewNamed(types.NewTypeName(token.NoPos, nil, "bigInt", nil), bigIntStruct, nil)
	bigIntPtr := types.NewPointer(bigIntType)

	// func Int(rand io.Reader, max *big.Int) (*big.Int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "max", bigIntPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", bigIntPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Prime(rand io.Reader, bits int) (*big.Int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Prime",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "bits", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", bigIntPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Text() string (Go 1.24+)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Text",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	pkg.MarkComplete()
	return pkg
}

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

// buildCryptoSHA256Package creates the type-checked crypto/sha256 package stub.
func buildCryptoSHA256Package() *types.Package {
	pkg := types.NewPackage("crypto/sha256", "sha256")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()

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

	// const Size = 32
	scope.Insert(types.NewConst(token.NoPos, pkg, "Size", types.Typ[types.Int],
		constant.MakeInt64(32)))

	// const Size224 = 28
	scope.Insert(types.NewConst(token.NoPos, pkg, "Size224", types.Typ[types.Int],
		constant.MakeInt64(28)))

	// const BlockSize = 64
	scope.Insert(types.NewConst(token.NoPos, pkg, "BlockSize", types.Typ[types.Int],
		constant.MakeInt64(64)))

	// func Sum256(data []byte) [32]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum256",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewArray(types.Typ[types.Byte], 32))),
			false)))

	// func Sum224(data []byte) [28]byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sum224",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewArray(types.Typ[types.Byte], 28))),
			false)))

	// func New() hash.Hash
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)),
			false)))

	// func New224() hash.Hash
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New224",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)),
			false)))

	pkg.MarkComplete()
	return pkg
}

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

// buildCryptoTLSPackage creates the type-checked crypto/tls package stub.
func buildCryptoTLSPackage() *types.Package {
	pkg := types.NewPackage("crypto/tls", "tls")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Certificate struct { Certificate [][]byte; PrivateKey interface{}; ... }
	tlsCertStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Certificate", types.NewSlice(types.NewSlice(types.Typ[types.Byte])), false),
		types.NewField(token.NoPos, pkg, "PrivateKey", types.NewInterfaceType(nil, nil), false),
		types.NewField(token.NoPos, pkg, "Leaf", types.NewPointer(types.NewStruct(nil, nil)), false),
	}, nil)
	tlsCertType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Certificate", nil),
		tlsCertStruct, nil)
	scope.Insert(tlsCertType.Obj())

	// type CurveID uint16
	curveIDType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CurveID", nil),
		types.Typ[types.Uint16], nil)
	scope.Insert(curveIDType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "CurveP256", curveIDType, constant.MakeInt64(23)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "CurveP384", curveIDType, constant.MakeInt64(24)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "CurveP521", curveIDType, constant.MakeInt64(25)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "X25519", curveIDType, constant.MakeInt64(29)))

	// type ClientAuthType int
	clientAuthType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ClientAuthType", nil),
		types.Typ[types.Int], nil)
	scope.Insert(clientAuthType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "NoClientCert", clientAuthType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RequestClientCert", clientAuthType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RequireAnyClientCert", clientAuthType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "VerifyClientCertIfGiven", clientAuthType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RequireAndVerifyClientCert", clientAuthType, constant.MakeInt64(4)))

	// *x509.CertPool opaque stand-in
	certPoolPtr := types.NewPointer(types.NewStruct(nil, nil))

	// net.Conn stand-in (Read, Write, Close) - needed by ClientHelloInfo, Conn, Listener, Server/Client
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	netConnIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	netConnIface.Complete()

	netAddrIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Network",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	netAddrIface.Complete()

	// type ClientHelloInfo struct
	clientHelloInfoStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ServerName", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "CipherSuites", types.NewSlice(types.Typ[types.Uint16]), false),
		types.NewField(token.NoPos, pkg, "SupportedVersions", types.NewSlice(types.Typ[types.Uint16]), false),
		types.NewField(token.NoPos, pkg, "SupportedProtos", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "SupportedCurves", types.NewSlice(curveIDType), false),
		types.NewField(token.NoPos, pkg, "Conn", netConnIface, false),
	}, nil)
	clientHelloInfoType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ClientHelloInfo", nil), clientHelloInfoStruct, nil)
	scope.Insert(clientHelloInfoType.Obj())
	clientHelloInfoPtr := types.NewPointer(clientHelloInfoType)

	// type CertificateRequestInfo struct
	certReqInfoStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.Uint16], false),
	}, nil)
	certReqInfoType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CertificateRequestInfo", nil), certReqInfoStruct, nil)
	scope.Insert(certReqInfoType.Obj())
	certReqInfoPtr := types.NewPointer(certReqInfoType)

	// type Config struct
	configStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Certificates", types.NewSlice(tlsCertType), false),
		types.NewField(token.NoPos, pkg, "GetCertificate", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "hello", clientHelloInfoPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewPointer(tlsCertType)),
				types.NewVar(token.NoPos, nil, "", errType)),
			false), false),
		types.NewField(token.NoPos, pkg, "GetClientCertificate", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "info", certReqInfoPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewPointer(tlsCertType)),
				types.NewVar(token.NoPos, nil, "", errType)),
			false), false),
		types.NewField(token.NoPos, pkg, "RootCAs", certPoolPtr, false),
		types.NewField(token.NoPos, pkg, "ClientCAs", certPoolPtr, false),
		types.NewField(token.NoPos, pkg, "InsecureSkipVerify", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "MinVersion", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "MaxVersion", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "ServerName", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "NextProtos", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "ClientAuth", clientAuthType, false),
		types.NewField(token.NoPos, pkg, "CipherSuites", types.NewSlice(types.Typ[types.Uint16]), false),
		types.NewField(token.NoPos, pkg, "CurvePreferences", types.NewSlice(curveIDType), false),
		types.NewField(token.NoPos, pkg, "SessionTicketsDisabled", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Renegotiation", types.Typ[types.Int], false),
	}, nil)
	configType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Config", nil),
		configStruct, nil)
	scope.Insert(configType.Obj())
	configPtr := types.NewPointer(configType)

	// Config.Clone() *Config
	configType.AddMethod(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", configPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", configPtr)),
			false)))

	// type ConnectionState struct
	x509CertPtr := types.NewPointer(types.NewStruct(nil, nil))
	connStateStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "HandshakeComplete", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "DidResume", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "CipherSuite", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "ServerName", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "NegotiatedProtocol", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "PeerCertificates", types.NewSlice(x509CertPtr), false),
		types.NewField(token.NoPos, pkg, "VerifiedChains", types.NewSlice(types.NewSlice(x509CertPtr)), false),
		types.NewField(token.NoPos, pkg, "OCSPResponse", types.NewSlice(types.Typ[types.Byte]), false),
	}, nil)
	connStateType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ConnectionState", nil),
		connStateStruct, nil)
	scope.Insert(connStateType.Obj())

	// context.Context stand-in (needed for Conn.HandshakeContext and Dialer.DialContext)
	anyTLSCtx := types.NewInterfaceType(nil, nil)
	anyTLSCtx.Complete()
	ctxIfaceTLS := types.NewInterfaceType([]*types.Func{
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
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyTLSCtx)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyTLSCtx)),
				false)),
	}, nil)
	ctxIfaceTLS.Complete()

	// type Conn struct
	connStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "fd", types.Typ[types.Int], false),
	}, nil)
	connType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Conn", nil),
		connStruct, nil)
	scope.Insert(connType.Obj())
	connPtr := types.NewPointer(connType)

	// Conn methods
	connRecv := types.NewVar(token.NoPos, nil, "c", connPtr)
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(connRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "Handshake",
		types.NewSignatureType(connRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "ConnectionState",
		types.NewSignatureType(connRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", connStateType)),
			false)))
	// Conn.HandshakeContext(ctx context.Context) error
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "HandshakeContext",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", ctxIfaceTLS)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	// Conn.NetConn() net.Conn
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "NetConn",
		types.NewSignatureType(connRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", netConnIface)),
			false)))
	// Conn.VerifyHostname(host string) error
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "VerifyHostname",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "host", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	// Conn.OCSPResponse() []byte
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "OCSPResponse",
		types.NewSignatureType(connRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func Dial(network, addr string, config *Config) (*Conn, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "addr", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "config", configPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", connPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// *net.Dialer opaque pointer stand-in
	netDialerPtrTLS := types.NewPointer(types.NewStruct(nil, nil))

	// func DialWithDialer(dialer *net.Dialer, network, addr string, config *Config) (*Conn, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DialWithDialer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dialer", netDialerPtrTLS),
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "addr", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "config", configPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", connPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func LoadX509KeyPair(certFile, keyFile string) (Certificate, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LoadX509KeyPair",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "certFile", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "keyFile", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tlsCertType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func X509KeyPair(certPEMBlock, keyPEMBlock []byte) (Certificate, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "X509KeyPair",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "certPEMBlock", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "keyPEMBlock", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tlsCertType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// net.Listener stand-in (Accept, Close, Addr) - uses netConnIface/netAddrIface from above
	listenerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Accept",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", netConnIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Addr",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", netAddrIface)), false)),
	}, nil)
	listenerIface.Complete()

	// func NewListener(inner net.Listener, config *Config) net.Listener
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewListener",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "inner", listenerIface),
				types.NewVar(token.NoPos, pkg, "config", configPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", listenerIface)),
			false)))

	// func Listen(network, laddr string, config *Config) (net.Listener, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Listen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "laddr", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "config", configPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", listenerIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Version constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "VersionTLS10", types.Typ[types.Uint16], constant.MakeInt64(0x0301)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "VersionTLS11", types.Typ[types.Uint16], constant.MakeInt64(0x0302)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "VersionTLS12", types.Typ[types.Uint16], constant.MakeInt64(0x0303)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "VersionTLS13", types.Typ[types.Uint16], constant.MakeInt64(0x0304)))

	// VersionSSL30 deprecated but still referenced
	scope.Insert(types.NewConst(token.NoPos, pkg, "VersionSSL30", types.Typ[types.Uint16], constant.MakeInt64(0x0300)))

	// Cipher suite constants
	cipherSuiteType := types.Typ[types.Uint16]
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"TLS_RSA_WITH_AES_128_CBC_SHA", 0x002f},
		{"TLS_RSA_WITH_AES_256_CBC_SHA", 0x0035},
		{"TLS_RSA_WITH_AES_128_GCM_SHA256", 0x009c},
		{"TLS_RSA_WITH_AES_256_GCM_SHA384", 0x009d},
		{"TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA", 0xc009},
		{"TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA", 0xc00a},
		{"TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA", 0xc013},
		{"TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA", 0xc014},
		{"TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", 0xc02b},
		{"TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384", 0xc02c},
		{"TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", 0xc02f},
		{"TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384", 0xc030},
		{"TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256", 0xcca8},
		{"TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256", 0xcca9},
		{"TLS_AES_128_GCM_SHA256", 0x1301},
		{"TLS_AES_256_GCM_SHA384", 0x1302},
		{"TLS_CHACHA20_POLY1305_SHA256", 0x1303},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, cipherSuiteType, constant.MakeInt64(c.val)))
	}

	// type CipherSuite struct
	cipherSuiteStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ID", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "SupportedVersions", types.NewSlice(types.Typ[types.Uint16]), false),
		types.NewField(token.NoPos, pkg, "Insecure", types.Typ[types.Bool], false),
	}, nil)
	cipherSuiteStructType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CipherSuite", nil), cipherSuiteStruct, nil)
	scope.Insert(cipherSuiteStructType.Obj())

	// func CipherSuites() []*CipherSuite
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CipherSuites",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.NewPointer(cipherSuiteStructType)))),
			false)))

	// func InsecureCipherSuites() []*CipherSuite
	scope.Insert(types.NewFunc(token.NoPos, pkg, "InsecureCipherSuites",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.NewPointer(cipherSuiteStructType)))),
			false)))

	// Conn.SetDeadline, Conn.SetReadDeadline, Conn.SetWriteDeadline
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetDeadline",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetReadDeadline",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetWriteDeadline",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "CloseWrite",
		types.NewSignatureType(connRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "LocalAddr",
		types.NewSignatureType(connRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", netAddrIface)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "RemoteAddr",
		types.NewSignatureType(connRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", netAddrIface)),
			false)))

	// Config additional fields added as methods
	configType.AddMethod(types.NewFunc(token.NoPos, pkg, "BuildNameToCertificate",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", configPtr), nil, nil, nil, nil, false)))

	// func Server(conn net.Conn, config *Config) *Conn
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Server",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "conn", netConnIface),
				types.NewVar(token.NoPos, pkg, "config", configPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", connPtr)),
			false)))

	// func Client(conn net.Conn, config *Config) *Conn
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Client",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "conn", netConnIface),
				types.NewVar(token.NoPos, pkg, "config", configPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", connPtr)),
			false)))

	// type Dialer struct { NetDialer *net.Dialer; Config *Config }
	dialerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "NetDialer", netDialerPtrTLS, false),
		types.NewField(token.NoPos, pkg, "Config", configPtr, false),
	}, nil)
	dialerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Dialer", nil), dialerStruct, nil)
	scope.Insert(dialerType.Obj())
	dialerPtr := types.NewPointer(dialerType)
	dialerType.AddMethod(types.NewFunc(token.NoPos, pkg, "DialContext",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "d", dialerPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxIfaceTLS),
				types.NewVar(token.NoPos, nil, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "addr", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", connPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// type RenegotiationSupport int
	renegotType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "RenegotiationSupport", nil), types.Typ[types.Int], nil)
	scope.Insert(renegotType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "RenegotiateNever", renegotType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RenegotiateOnceAsClient", renegotType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RenegotiateFreelyAsClient", renegotType, constant.MakeInt64(2)))

	// Dialer.Dial(network, addr string) (*Conn, error)
	dialerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Dial",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "d", dialerPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "addr", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", connPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// type AlertError uint8
	alertErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "AlertError", nil), types.Typ[types.Uint8], nil)
	scope.Insert(alertErrType.Obj())
	alertErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", alertErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type RecordHeaderError struct { Msg string; RecordHeader [5]byte; Conn net.Conn }
	recHeaderErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Msg", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "RecordHeader", types.NewArray(types.Typ[types.Byte], 5), false),
		types.NewField(token.NoPos, pkg, "Conn", netConnIface, false),
	}, nil)
	recHeaderErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "RecordHeaderError", nil), recHeaderErrStruct, nil)
	scope.Insert(recHeaderErrType.Obj())
	recHeaderErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", recHeaderErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type CertificateVerificationError struct { UnverifiedCertificates []*x509.Certificate; Err error }
	certVerifyErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "UnverifiedCertificates", types.NewSlice(x509CertPtr), false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	certVerifyErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CertificateVerificationError", nil), certVerifyErrStruct, nil)
	scope.Insert(certVerifyErrType.Obj())
	certVerifyErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", certVerifyErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	certVerifyErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", certVerifyErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func CipherSuiteName(id uint16) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CipherSuiteName",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "id", types.Typ[types.Uint16])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func VersionName(version uint16) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "VersionName",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "version", types.Typ[types.Uint16])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// type SignatureScheme uint16
	sigSchemeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SignatureScheme", nil), types.Typ[types.Uint16], nil)
	scope.Insert(sigSchemeType.Obj())
	sigSchemeType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "s", sigSchemeType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	for _, ss := range []struct {
		name string
		val  int64
	}{
		{"PKCS1WithSHA256", 0x0401},
		{"PKCS1WithSHA384", 0x0501},
		{"PKCS1WithSHA512", 0x0601},
		{"PSSWithSHA256", 0x0804},
		{"PSSWithSHA384", 0x0805},
		{"PSSWithSHA512", 0x0806},
		{"ECDSAWithP256AndSHA256", 0x0403},
		{"ECDSAWithP384AndSHA384", 0x0503},
		{"ECDSAWithP521AndSHA512", 0x0603},
		{"Ed25519", 0x0807},
		{"PKCS1WithSHA1", 0x0201},
		{"ECDSAWithSHA1", 0x0203},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, ss.name, sigSchemeType, constant.MakeInt64(ss.val)))
	}

	// ConnectionState.ExportKeyingMaterial(label string, context []byte, length int) ([]byte, error)
	connStateType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExportKeyingMaterial",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "cs", types.NewPointer(connStateType)), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "label", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "context", byteSlice),
				types.NewVar(token.NoPos, nil, "length", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// type ClientSessionState struct (opaque)
	cssStruct := types.NewStruct(nil, nil)
	cssType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ClientSessionState", nil), cssStruct, nil)
	scope.Insert(cssType.Obj())
	cssPtr := types.NewPointer(cssType)

	// type ClientSessionCache interface { Get(sessionKey string) (*ClientSessionState, bool); Put(sessionKey string, cs *ClientSessionState) }
	cscIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Get",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "sessionKey", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", cssPtr),
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
				false)),
		types.NewFunc(token.NoPos, pkg, "Put",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "sessionKey", types.Typ[types.String]),
					types.NewVar(token.NoPos, nil, "cs", cssPtr)),
				nil, false)),
	}, nil)
	cscIface.Complete()
	cscType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ClientSessionCache", nil), cscIface, nil)
	scope.Insert(cscType.Obj())

	// func NewLRUClientSessionCache(capacity int) ClientSessionCache
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewLRUClientSessionCache",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "capacity", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", cscType)),
			false)))

	// Conn.ConnectionState().TLSUnique []byte — add to ConnectionState
	// (already defined as struct, but add the field info via comment — we can't add fields post-hoc)

	// Suppress unused variables
	_ = x509CertPtr
	_ = certPoolPtr
	_ = netDialerPtrTLS
	_ = listenerIface
	_ = renegotType
	_ = sigSchemeType
	_ = cssPtr

	pkg.MarkComplete()
	return pkg
}

// buildCryptoX509Package creates the type-checked crypto/x509 package stub.
func buildCryptoX509Package() *types.Package {
	pkg := types.NewPackage("crypto/x509", "x509")
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

	// type KeyUsage int
	keyUsageType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "KeyUsage", nil),
		types.Typ[types.Int], nil)
	scope.Insert(keyUsageType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "KeyUsageDigitalSignature", keyUsageType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KeyUsageContentCommitment", keyUsageType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KeyUsageKeyEncipherment", keyUsageType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KeyUsageCertSign", keyUsageType, constant.MakeInt64(32)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KeyUsageCRLSign", keyUsageType, constant.MakeInt64(64)))

	// type ExtKeyUsage int
	extKeyUsageType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ExtKeyUsage", nil),
		types.Typ[types.Int], nil)
	scope.Insert(extKeyUsageType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "ExtKeyUsageAny", extKeyUsageType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ExtKeyUsageServerAuth", extKeyUsageType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ExtKeyUsageClientAuth", extKeyUsageType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ExtKeyUsageCodeSigning", extKeyUsageType, constant.MakeInt64(3)))

	// type SignatureAlgorithm int
	sigAlgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SignatureAlgorithm", nil),
		types.Typ[types.Int], nil)
	scope.Insert(sigAlgType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA256WithRSA", sigAlgType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA384WithRSA", sigAlgType, constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA512WithRSA", sigAlgType, constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ECDSAWithSHA256", sigAlgType, constant.MakeInt64(7)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ECDSAWithSHA384", sigAlgType, constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ECDSAWithSHA512", sigAlgType, constant.MakeInt64(9)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "PureEd25519", sigAlgType, constant.MakeInt64(16)))

	// type PublicKeyAlgorithm int
	pubKeyAlgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PublicKeyAlgorithm", nil),
		types.Typ[types.Int], nil)
	scope.Insert(pubKeyAlgType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "RSA", pubKeyAlgType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DSA", pubKeyAlgType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ECDSA", pubKeyAlgType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Ed25519", pubKeyAlgType, constant.MakeInt64(4)))

	// pkix.Name stand-in struct (CommonName, Organization, etc.)
	pkixNameStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "CommonName", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Organization", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "OrganizationalUnit", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Country", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Province", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Locality", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "SerialNumber", types.Typ[types.String], false),
	}, nil)

	certStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Raw", types.NewSlice(types.Typ[types.Byte]), false),
		types.NewField(token.NoPos, pkg, "RawTBSCertificate", types.NewSlice(types.Typ[types.Byte]), false),
		types.NewField(token.NoPos, pkg, "RawSubjectPublicKeyInfo", types.NewSlice(types.Typ[types.Byte]), false),
		types.NewField(token.NoPos, pkg, "RawSubject", types.NewSlice(types.Typ[types.Byte]), false),
		types.NewField(token.NoPos, pkg, "RawIssuer", types.NewSlice(types.Typ[types.Byte]), false),
		types.NewField(token.NoPos, pkg, "Signature", types.NewSlice(types.Typ[types.Byte]), false),
		types.NewField(token.NoPos, pkg, "Subject", pkixNameStruct, false),
		types.NewField(token.NoPos, pkg, "Issuer", pkixNameStruct, false),
		types.NewField(token.NoPos, pkg, "NotBefore", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "NotAfter", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "KeyUsage", keyUsageType, false),
		types.NewField(token.NoPos, pkg, "ExtKeyUsage", types.NewSlice(extKeyUsageType), false),
		types.NewField(token.NoPos, pkg, "IsCA", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "BasicConstraintsValid", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "MaxPathLen", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "MaxPathLenZero", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "DNSNames", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "EmailAddresses", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "IPAddresses", types.NewSlice(types.NewSlice(types.Typ[types.Byte])), false),
		types.NewField(token.NoPos, pkg, "SerialNumber", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "SignatureAlgorithm", sigAlgType, false),
		types.NewField(token.NoPos, pkg, "PublicKeyAlgorithm", pubKeyAlgType, false),
		types.NewField(token.NoPos, pkg, "PublicKey", types.NewInterfaceType(nil, nil), false),
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "OCSPServer", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "IssuingCertificateURL", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "CRLDistributionPoints", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "PermittedDNSDomains", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "SubjectKeyId", types.NewSlice(types.Typ[types.Byte]), false),
		types.NewField(token.NoPos, pkg, "AuthorityKeyId", types.NewSlice(types.Typ[types.Byte]), false),
	}, nil)
	certType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Certificate", nil),
		certStruct, nil)
	scope.Insert(certType.Obj())
	certPtr := types.NewPointer(certType)

	// CertPool — defined before VerifyOptions so Roots/Intermediates can use it
	poolStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	poolType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CertPool", nil),
		poolStruct, nil)
	scope.Insert(poolType.Obj())
	poolPtr := types.NewPointer(poolType)

	// CertPool methods
	poolRecv := types.NewVar(token.NoPos, nil, "s", poolPtr)
	poolType.AddMethod(types.NewFunc(token.NoPos, pkg, "AppendCertsFromPEM",
		types.NewSignatureType(poolRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "pemCerts", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	poolType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddCert",
		types.NewSignatureType(poolRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "cert", certPtr)),
			nil, false)))
	poolType.AddMethod(types.NewFunc(token.NoPos, pkg, "Subjects",
		types.NewSignatureType(poolRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.NewSlice(types.Typ[types.Byte])))),
			false)))
	poolType.AddMethod(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(poolRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", poolPtr)),
			false)))
	poolType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(poolRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "other", poolPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func NewCertPool() *CertPool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewCertPool",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", poolPtr)),
			false)))

	// type VerifyOptions struct
	verifyOptsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "DNSName", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Roots", poolPtr, false),
		types.NewField(token.NoPos, pkg, "Intermediates", poolPtr, false),
		types.NewField(token.NoPos, pkg, "CurrentTime", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "KeyUsages", types.NewSlice(extKeyUsageType), false),
		types.NewField(token.NoPos, pkg, "MaxConstraintComparisions", types.Typ[types.Int], false),
	}, nil)
	verifyOptsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "VerifyOptions", nil),
		verifyOptsStruct, nil)
	scope.Insert(verifyOptsType.Obj())

	// Certificate methods
	certRecv := types.NewVar(token.NoPos, nil, "c", certPtr)
	certType.AddMethod(types.NewFunc(token.NoPos, pkg, "Verify",
		types.NewSignatureType(certRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "opts", verifyOptsType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.NewSlice(certPtr))),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	certType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(certRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "other", certPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseCertificate",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "asn1Data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", certPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseCertificates(asn1Data []byte) ([]*Certificate, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseCertificates",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "asn1Data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(certPtr)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// *rsa.PrivateKey opaque pointer for ParsePKCS1/MarshalPKCS1
	rsaPrivKeyPtr := types.NewPointer(types.NewStruct(nil, nil))

	// func ParsePKCS1PrivateKey(der []byte) (*rsa.PrivateKey, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParsePKCS1PrivateKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "der", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", rsaPrivKeyPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParsePKCS1PublicKey(der []byte) (*rsa.PublicKey, error)
	rsaPubKeyPtr := types.NewPointer(types.NewStruct(nil, nil))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParsePKCS1PublicKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "der", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", rsaPubKeyPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func MarshalPKCS1PublicKey(key *rsa.PublicKey) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MarshalPKCS1PublicKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", rsaPubKeyPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func ParsePKCS8PrivateKey(der []byte) (interface{}, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParsePKCS8PrivateKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "der", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParsePKIXPublicKey(derBytes []byte) (interface{}, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParsePKIXPublicKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "derBytes", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func MarshalPKIXPublicKey(pub interface{}) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MarshalPKIXPublicKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "pub", types.NewInterfaceType(nil, nil))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "SystemCertPool",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", poolPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type CertificateInvalidError struct
	certInvalidErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Cert", certPtr, false),
		types.NewField(token.NoPos, pkg, "Reason", types.Typ[types.Int], false),
	}, nil)
	certInvalidErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CertificateInvalidError", nil),
		certInvalidErrStruct, nil)
	certInvalidErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", certInvalidErrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(certInvalidErrType.Obj())

	// type UnknownAuthorityError struct
	unknownAuthErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Cert", certPtr, false),
	}, nil)
	unknownAuthErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnknownAuthorityError", nil),
		unknownAuthErrStruct, nil)
	unknownAuthErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownAuthErrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unknownAuthErrType.Obj())

	// type CertificateRequest struct
	certReqStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Raw", byteSlice, false),
		types.NewField(token.NoPos, pkg, "RawSubject", byteSlice, false),
		types.NewField(token.NoPos, pkg, "Subject", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "DNSNames", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "EmailAddresses", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "SignatureAlgorithm", sigAlgType, false),
		types.NewField(token.NoPos, pkg, "PublicKeyAlgorithm", pubKeyAlgType, false),
		types.NewField(token.NoPos, pkg, "PublicKey", types.NewInterfaceType(nil, nil), false),
	}, nil)
	certReqType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CertificateRequest", nil), certReqStruct, nil)
	scope.Insert(certReqType.Obj())

	// func CreateCertificate(rand io.Reader, template *Certificate, parent *Certificate, pub any, priv any) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CreateCertificate",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "template", certPtr),
				types.NewVar(token.NoPos, pkg, "parent", certPtr),
				types.NewVar(token.NoPos, pkg, "pub", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "priv", types.NewInterfaceType(nil, nil))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func CreateCertificateRequest(rand io.Reader, template *CertificateRequest, priv any) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CreateCertificateRequest",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "template", types.NewPointer(certReqType)),
				types.NewVar(token.NoPos, pkg, "priv", types.NewInterfaceType(nil, nil))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseCertificateRequest(asn1Data []byte) (*CertificateRequest, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseCertificateRequest",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "asn1Data", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(certReqType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func MarshalPKCS1PrivateKey(key *rsa.PrivateKey) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MarshalPKCS1PrivateKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", rsaPrivKeyPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSlice)),
			false)))

	// func MarshalPKCS8PrivateKey(key interface{}) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MarshalPKCS8PrivateKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", types.NewInterfaceType(nil, nil))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func MarshalECPrivateKey(key interface{}) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MarshalECPrivateKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", types.NewInterfaceType(nil, nil))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseECPrivateKey(der []byte) (interface{}, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseECPrivateKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "der", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Additional Certificate methods
	certType.AddMethod(types.NewFunc(token.NoPos, pkg, "CheckSignatureFrom",
		types.NewSignatureType(certRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "parent", certPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	certType.AddMethod(types.NewFunc(token.NoPos, pkg, "CheckSignature",
		types.NewSignatureType(certRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "algo", sigAlgType),
				types.NewVar(token.NoPos, nil, "signed", byteSlice),
				types.NewVar(token.NoPos, nil, "signature", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	certType.AddMethod(types.NewFunc(token.NoPos, pkg, "VerifyHostname",
		types.NewSignatureType(certRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "h", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Additional KeyUsage constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "KeyUsageDataEncipherment", keyUsageType, constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KeyUsageKeyAgreement", keyUsageType, constant.MakeInt64(16)))

	// Additional ExtKeyUsage constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "ExtKeyUsageEmailProtection", extKeyUsageType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ExtKeyUsageTimeStamping", extKeyUsageType, constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ExtKeyUsageOCSPSigning", extKeyUsageType, constant.MakeInt64(9)))

	// type RevocationListEntry struct
	rlEntryStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "SerialNumber", types.NewPointer(types.NewStruct(nil, nil)), false), // *big.Int opaque
		types.NewField(token.NoPos, pkg, "RevocationTime", types.Typ[types.Int64], false),                   // time.Time
		types.NewField(token.NoPos, pkg, "ReasonCode", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Extensions", types.NewSlice(types.NewStruct(nil, nil)), false), // []pkix.Extension opaque
		types.NewField(token.NoPos, pkg, "ExtraExtensions", types.NewSlice(types.NewStruct(nil, nil)), false),
	}, nil)
	rlEntryType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "RevocationListEntry", nil), rlEntryStruct, nil)
	scope.Insert(rlEntryType.Obj())

	// type RevocationList struct
	rlStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Raw", byteSlice, false),
		types.NewField(token.NoPos, pkg, "RawIssuer", byteSlice, false),
		types.NewField(token.NoPos, pkg, "Issuer", types.NewStruct(nil, nil), false), // pkix.Name opaque
		types.NewField(token.NoPos, pkg, "AuthorityKeyId", byteSlice, false),
		types.NewField(token.NoPos, pkg, "SignatureAlgorithm", sigAlgType, false),
		types.NewField(token.NoPos, pkg, "Signature", byteSlice, false),
		types.NewField(token.NoPos, pkg, "RevokedCertificateEntries", types.NewSlice(rlEntryType), false),
		types.NewField(token.NoPos, pkg, "Number", types.NewPointer(types.NewStruct(nil, nil)), false), // *big.Int
		types.NewField(token.NoPos, pkg, "ThisUpdate", types.Typ[types.Int64], false),                  // time.Time
		types.NewField(token.NoPos, pkg, "NextUpdate", types.Typ[types.Int64], false),                  // time.Time
		types.NewField(token.NoPos, pkg, "Extensions", types.NewSlice(types.NewStruct(nil, nil)), false),
		types.NewField(token.NoPos, pkg, "ExtraExtensions", types.NewSlice(types.NewStruct(nil, nil)), false),
	}, nil)
	rlType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "RevocationList", nil), rlStruct, nil)
	scope.Insert(rlType.Obj())
	rlPtr := types.NewPointer(rlType)
	rlRecv := types.NewVar(token.NoPos, nil, "rl", rlPtr)
	rlType.AddMethod(types.NewFunc(token.NoPos, pkg, "CheckSignatureFrom",
		types.NewSignatureType(rlRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "parent", certPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func ParseRevocationList(der []byte) (*RevocationList, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseRevocationList",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "der", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", rlPtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func CreateRevocationList(rand io.Reader, template *RevocationList, issuer *Certificate, priv crypto.Signer) ([]byte, error)
	// crypto.Signer stand-in
	signerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Public",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)),
		types.NewFunc(token.NoPos, nil, "Sign",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "rand", ioReaderIface),
					types.NewVar(token.NoPos, nil, "digest", byteSlice),
					types.NewVar(token.NoPos, nil, "opts", types.NewInterfaceType(nil, nil))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", byteSlice),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	signerIface.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CreateRevocationList",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rand", ioReaderIface),
				types.NewVar(token.NoPos, pkg, "template", rlPtr),
				types.NewVar(token.NoPos, pkg, "issuer", certPtr),
				types.NewVar(token.NoPos, pkg, "priv", signerIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// Error types
	// type HostnameError struct { Certificate *Certificate; Host string }
	hostnameErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Certificate", certPtr, false),
		types.NewField(token.NoPos, pkg, "Host", types.Typ[types.String], false),
	}, nil)
	hostnameErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "HostnameError", nil), hostnameErrStruct, nil)
	scope.Insert(hostnameErrType.Obj())
	hostnameErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "h", hostnameErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type UnknownAuthorityError struct { Cert *Certificate }
	uaErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Cert", certPtr, false),
	}, nil)
	uaErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UnknownAuthorityError", nil), uaErrStruct, nil)
	scope.Insert(uaErrType.Obj())
	uaErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", uaErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type CertificateInvalidError struct { Cert *Certificate; Reason InvalidReason }
	invalidReasonType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "InvalidReason", nil), types.Typ[types.Int], nil)
	scope.Insert(invalidReasonType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "NotAuthorizedToSign", invalidReasonType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Expired", invalidReasonType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "CANotAuthorizedForThisName", invalidReasonType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TooManyIntermediates", invalidReasonType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "IncompatibleUsage", invalidReasonType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NameMismatch", invalidReasonType, constant.MakeInt64(7)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NameConstraintsWithoutSANs", invalidReasonType, constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "UnconstrainedName", invalidReasonType, constant.MakeInt64(9)))

	// (CertificateInvalidError already defined above with Reason field)

	// var ErrUnsupportedAlgorithm error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrUnsupportedAlgorithm", errType))

	// var IncorrectPasswordError error
	scope.Insert(types.NewVar(token.NoPos, pkg, "IncorrectPasswordError", errType))

	// type InsecureAlgorithmError
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrInsecureAlgorithm", errType))

	// Additional SignatureAlgorithm constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "UnknownSignatureAlgorithm", sigAlgType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MD2WithRSA", sigAlgType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MD5WithRSA", sigAlgType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA1WithRSA", sigAlgType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA256WithRSAPSS", sigAlgType, constant.MakeInt64(13)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA384WithRSAPSS", sigAlgType, constant.MakeInt64(14)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SHA512WithRSAPSS", sigAlgType, constant.MakeInt64(15)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ECDSAWithSHA1", sigAlgType, constant.MakeInt64(10)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Ed25519", sigAlgType, constant.MakeInt64(16)))

	// Additional KeyUsage constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "KeyUsageEncipherOnly", keyUsageType, constant.MakeInt64(128)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KeyUsageDecipherOnly", keyUsageType, constant.MakeInt64(256)))

	// type SystemRootsError struct { Err error }
	sysRootsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	sysRootsType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SystemRootsError", nil), sysRootsStruct, nil)
	sysRootsType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "", sysRootsType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	sysRootsType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "", sysRootsType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	scope.Insert(sysRootsType.Obj())

	// type UnhandledCriticalExtension struct{}
	uhceType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UnhandledCriticalExtension", nil),
		types.NewStruct(nil, nil), nil)
	uhceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "", uhceType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(uhceType.Obj())

	// type ConstraintViolationError struct{}
	cveType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ConstraintViolationError", nil),
		types.NewStruct(nil, nil), nil)
	cveType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "", cveType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(cveType.Obj())

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
