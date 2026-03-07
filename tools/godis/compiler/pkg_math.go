// Package type stubs for math packages: math, math/bits, math/rand,
// math/rand/v2, math/big, math/cmplx.
package compiler

import (
	"go/constant"
	"go/token"
	"go/types"
)

func init() {
	RegisterPackage("math/big", buildMathBigPackage)
	RegisterPackage("math/bits", buildMathBitsPackage)
	RegisterPackage("math/cmplx", buildMathCmplxPackage)
	RegisterPackage("math", buildMathPackage)
	RegisterPackage("math/rand", buildMathRandPackage)
	RegisterPackage("math/rand/v2", buildMathRandV2Package)
}

// buildMathBigPackage creates the type-checked math/big package stub.
func buildMathBigPackage() *types.Package {
	pkg := types.NewPackage("math/big", "big")
	scope := pkg.Scope()

	// type Int struct { ... }
	intStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "val", types.Typ[types.Int64], false),
	}, nil)
	intType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Int", nil),
		intStruct, nil)
	scope.Insert(intType.Obj())
	intPtr := types.NewPointer(intType)

	// func NewInt(x int64) *Int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewInt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// type Float struct { ... }
	floatStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "val", types.Typ[types.Float64], false),
	}, nil)
	floatType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Float", nil),
		floatStruct, nil)
	scope.Insert(floatType.Obj())
	floatPtr := types.NewPointer(floatType)

	// func NewFloat(x float64) *Float
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFloat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", floatPtr)),
			false)))

	// type Rat struct {}
	ratStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "num", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "den", types.Typ[types.Int64], false),
	}, nil)
	ratType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Rat", nil),
		ratStruct, nil)
	scope.Insert(ratType.Obj())
	ratPtr := types.NewPointer(ratType)

	// func NewRat(a, b int64) *Rat
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "a", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ratPtr)),
			false)))

	// type Accuracy int8
	accuracyType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Accuracy", nil),
		types.Typ[types.Int8], nil)
	scope.Insert(accuracyType.Obj())

	// type RoundingMode byte
	roundingModeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RoundingMode", nil),
		types.Typ[types.Byte], nil)
	scope.Insert(roundingModeType.Obj())

	// Int methods
	intRecv := types.NewVar(token.NoPos, nil, "x", intPtr)

	// func (*Int) Add(x, y *Int) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", intPtr),
				types.NewVar(token.NoPos, pkg, "y", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func (*Int) Sub(x, y *Int) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sub",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", intPtr),
				types.NewVar(token.NoPos, pkg, "y", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func (*Int) Mul(x, y *Int) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Mul",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", intPtr),
				types.NewVar(token.NoPos, pkg, "y", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func (*Int) Div(x, y *Int) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Div",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", intPtr),
				types.NewVar(token.NoPos, pkg, "y", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func (*Int) Mod(x, y *Int) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Mod",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", intPtr),
				types.NewVar(token.NoPos, pkg, "y", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func (*Int) Cmp(y *Int) int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cmp",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "y", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func (*Int) Int64() int64
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int64",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))

	// func (*Int) SetInt64(x int64) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetInt64",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func (*Int) SetString(s string, base int) (*Int, bool)
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetString",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "base", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", intPtr),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func (*Int) String() string
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (*Int) Bytes() []byte
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func (*Int) SetBytes(buf []byte) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetBytes",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func (*Int) Sign() int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sign",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func (*Int) Abs(x *Int) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Abs",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func (*Int) Neg(x *Int) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Neg",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func (*Int) Set(x *Int) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func (*Int) IsInt64() bool
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsInt64",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func (*Int) CmpAbs(y *Int) int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "CmpAbs",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "y", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func (*Int) Float64() (float64, Accuracy)
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "", accuracyType)),
			false)))

	// func (*Int) BitLen() int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "BitLen",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func (*Int) Exp(x, y, m *Int) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Exp",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", intPtr),
				types.NewVar(token.NoPos, pkg, "y", intPtr),
				types.NewVar(token.NoPos, pkg, "m", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func (*Int) GCD(x, y, a, b *Int) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "GCD",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", intPtr),
				types.NewVar(token.NoPos, pkg, "y", intPtr),
				types.NewVar(token.NoPos, pkg, "a", intPtr),
				types.NewVar(token.NoPos, pkg, "b", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	errType := types.Universe.Lookup("error").Type()

	// Int two-arg helper: func (z *Int) Method(x, y *Int) *Int
	intTwoArg := func(name string) {
		intType.AddMethod(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(intRecv, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", intPtr),
					types.NewVar(token.NoPos, nil, "y", intPtr)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
				false)))
	}

	// func (*Int) Quo(x, y *Int) *Int
	intTwoArg("Quo")

	// func (*Int) Rem(x, y *Int) *Int
	intTwoArg("Rem")

	// func (*Int) DivMod(x, y, m *Int) (*Int, *Int)
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "DivMod",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", intPtr),
				types.NewVar(token.NoPos, nil, "y", intPtr),
				types.NewVar(token.NoPos, nil, "m", intPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", intPtr),
				types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))

	// func (*Int) QuoRem(x, y, r *Int) (*Int, *Int)
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "QuoRem",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", intPtr),
				types.NewVar(token.NoPos, nil, "y", intPtr),
				types.NewVar(token.NoPos, nil, "r", intPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", intPtr),
				types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))

	// func (*Int) ModInverse(g, n *Int) *Int
	intTwoArg("ModInverse")

	// func (*Int) ModSqrt(x, p *Int) *Int
	intTwoArg("ModSqrt")

	// Bitwise ops: Lsh, Rsh take uint shift amount
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lsh",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", intPtr),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Rsh",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", intPtr),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))

	// Bitwise ops with two *Int args
	intTwoArg("And")
	intTwoArg("Or")
	intTwoArg("Xor")
	intTwoArg("AndNot")

	// func (*Int) Not(x *Int) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Not",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))

	// func (*Int) Bit(i int) uint
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bit",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint])),
			false)))

	// func (*Int) SetBit(x *Int, i int, b uint) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetBit",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", intPtr),
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))

	// func (*Int) TrailingZeroBits() uint
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "TrailingZeroBits",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint])),
			false)))

	// func (*Int) Uint64() uint64
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])),
			false)))

	// func (*Int) IsUint64() bool
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsUint64",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func (*Int) SetUint64(x uint64) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetUint64",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))

	// func (*Int) FillBytes(buf []byte) []byte
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "FillBytes",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "buf", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func (*Int) Sqrt(x *Int) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sqrt",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))

	// func (*Int) Text(base int) string
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Text",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "base", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// func (*Int) Append(buf []byte, base int) []byte
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Append",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "base", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func (*Int) Format(s fmt.State, ch rune) — we can't reference fmt, just omit
	// func (*Int) Scan(s fmt.ScanState, ch rune) error — same

	// func (*Int) Bits() []Word (Word = uintptr)
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bits",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Uintptr]))),
			false)))

	// func (*Int) SetBits(abs []Word) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetBits",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "abs", types.NewSlice(types.Typ[types.Uintptr]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))

	// func (*Int) Rand(rng *rand.Rand, n *Int) *Int — rand.Rand as opaque
	randRngPtr := types.NewPointer(types.NewStruct(nil, nil))
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Rand",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "rng", randRngPtr),
				types.NewVar(token.NoPos, nil, "n", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))

	// func (*Int) ProbablyPrime(n int) bool
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "ProbablyPrime",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func (*Int) Binomial(n, k int64) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "Binomial",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "k", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))

	// func (*Int) MulRange(a, b int64) *Int
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "MulRange",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "a", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))

	// Serialization: MarshalJSON, UnmarshalJSON, MarshalText, UnmarshalText, GobEncode, GobDecode
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalJSON",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalJSON",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "text", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	intType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "text", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func Jacobi(x, y *Int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Jacobi",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", intPtr),
				types.NewVar(token.NoPos, pkg, "y", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// Float methods — similar patterns
	floatRecv := types.NewVar(token.NoPos, nil, "x", floatPtr)

	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", floatPtr),
				types.NewVar(token.NoPos, pkg, "y", floatPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", floatPtr)),
			false)))

	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sub",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", floatPtr),
				types.NewVar(token.NoPos, pkg, "y", floatPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", floatPtr)),
			false)))

	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Mul",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", floatPtr),
				types.NewVar(token.NoPos, pkg, "y", floatPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", floatPtr)),
			false)))

	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Quo",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", floatPtr),
				types.NewVar(token.NoPos, pkg, "y", floatPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", floatPtr)),
			false)))

	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cmp",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "y", floatPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "", accuracyType)),
			false)))

	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetFloat64",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", floatPtr)),
			false)))

	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetPrec",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "prec", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", floatPtr)),
			false)))

	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sign",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsInf",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsInt",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Signbit",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Copy",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", floatPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", floatPtr)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "MantExp",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "mant", floatPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetMantExp",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "mant", floatPtr),
				types.NewVar(token.NoPos, nil, "exp", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", floatPtr)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int64",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "", accuracyType)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, nil, "", accuracyType)),
			false)))

	// Additional Float methods
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sqrt",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", floatPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", floatPtr)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", floatPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", floatPtr)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetInt",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", floatPtr)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetRat",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", ratPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", floatPtr)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetMode",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "mode", roundingModeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", floatPtr)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Mode",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", roundingModeType)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Prec",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint])),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "MinPrec",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint])),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Acc",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", accuracyType)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Abs",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", floatPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", floatPtr)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Neg",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", floatPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", floatPtr)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float32",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Float32]),
				types.NewVar(token.NoPos, nil, "", accuracyType)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "z", intPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", intPtr),
				types.NewVar(token.NoPos, nil, "", accuracyType)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Rat",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "z", ratPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", ratPtr),
				types.NewVar(token.NoPos, nil, "", accuracyType)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetInf",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "signbit", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", floatPtr)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetInt64",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", floatPtr)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetUint64",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", floatPtr)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Text",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, nil, "prec", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Append",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "fmt", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, nil, "prec", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetString",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", floatPtr),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "base", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", floatPtr),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "text", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "GobEncode",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	floatType.AddMethod(types.NewFunc(token.NoPos, pkg, "GobDecode",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "buf", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func ParseFloat(s string, base int, prec uint, mode RoundingMode) (f *Float, b int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseFloat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "base", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "prec", types.Typ[types.Uint]),
				types.NewVar(token.NoPos, pkg, "mode", roundingModeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "f", floatPtr),
				types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// RoundingMode constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "ToNearestEven", roundingModeType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ToNearestAway", roundingModeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ToZero", roundingModeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AwayFromZero", roundingModeType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ToNegativeInf", roundingModeType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ToPositiveInf", roundingModeType, constant.MakeInt64(5)))

	// Accuracy constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "Below", accuracyType, constant.MakeInt64(-1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Exact", accuracyType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Above", accuracyType, constant.MakeInt64(1)))

	accuracyType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "i", accuracyType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	roundingModeType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "i", roundingModeType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// Rat methods
	ratRecv := types.NewVar(token.NoPos, nil, "x", ratPtr)

	// Helper for Rat two-arg methods: func (z *Rat) Method(x, y *Rat) *Rat
	ratTwoArg := func(name string) {
		ratType.AddMethod(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(ratRecv, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", ratPtr),
					types.NewVar(token.NoPos, nil, "y", ratPtr)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", ratPtr)),
				false)))
	}
	ratTwoArg("Add")
	ratTwoArg("Sub")
	ratTwoArg("Mul")
	ratTwoArg("Quo")

	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cmp",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "y", ratPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sign",
		types.NewSignatureType(ratRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsInt",
		types.NewSignatureType(ratRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "Num",
		types.NewSignatureType(ratRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "Denom",
		types.NewSignatureType(ratRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", intPtr)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float32",
		types.NewSignatureType(ratRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Float32]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(ratRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetInt",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ratPtr)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetFrac",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "a", intPtr),
				types.NewVar(token.NoPos, nil, "b", intPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ratPtr)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetFrac64",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "a", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ratPtr)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetInt64",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ratPtr)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetFloat64",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ratPtr)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetString",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", ratPtr),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", ratPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ratPtr)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "Inv",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", ratPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ratPtr)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "Neg",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", ratPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ratPtr)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "Abs",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", ratPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ratPtr)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(ratRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "RatString",
		types.NewSignatureType(ratRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "FloatString",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "prec", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(ratRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "text", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "GobEncode",
		types.NewSignatureType(ratRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	ratType.AddMethod(types.NewFunc(token.NoPos, pkg, "GobDecode",
		types.NewSignatureType(ratRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "buf", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Rat.Scan/Format/Copy intentionally omitted (depend on fmt)

	// type Word uintptr
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Word", types.Typ[types.Uintptr]))

	// type ErrNaN struct { msg string }
	errNaNStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "msg", types.Typ[types.String], false),
	}, nil)
	errNaNType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ErrNaN", nil),
		errNaNStruct, nil)
	errNaNType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "err", errNaNType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(errNaNType.Obj())

	// MaxBase constant
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxBase", types.Typ[types.Int], constant.MakeInt64(62)))

	// MaxExp, MinExp constants (for Float)
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxExp", types.Typ[types.Int32], constant.MakeInt64(2147483647)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MinExp", types.Typ[types.Int32], constant.MakeInt64(-2147483648)))

	// MaxPrec constant
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxPrec", types.Typ[types.Uint], constant.MakeUint64(4294967295)))

	pkg.MarkComplete()
	return pkg
}

func buildMathBitsPackage() *types.Package {
	pkg := types.NewPackage("math/bits", "bits")
	scope := pkg.Scope()

	uintInt := func(name string) {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Uint])),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
				false)))
	}
	uintInt("OnesCount")
	uintInt("LeadingZeros")
	uintInt("TrailingZeros")
	uintInt("Len")

	uint64Int := func(name string) {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Uint64])),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
				false)))
	}
	uint64Int("OnesCount64")
	uint64Int("LeadingZeros64")
	uint64Int("TrailingZeros64")
	uint64Int("Len64")

	// func RotateLeft(x uint, k int) uint
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RotateLeft",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Uint]),
				types.NewVar(token.NoPos, pkg, "k", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint])),
			false)))

	// func RotateLeft64(x uint64, k int) uint64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RotateLeft64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "k", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))

	// func ReverseBytes64(x uint64) uint64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReverseBytes64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))

	// func Reverse64(x uint64) uint64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Reverse64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))

	// Constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "UintSize", types.Typ[types.Int], constant.MakeInt64(64)))

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

// buildMathPackage creates the type-checked math package stub.
func buildMathPackage() *types.Package {
	pkg := types.NewPackage("math", "math")
	scope := pkg.Scope()

	// func Abs(x float64) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Abs",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Sqrt(x float64) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sqrt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Min(x, y float64) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Min",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Max(x, y float64) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Max",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	f64f64 := func(name string) {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
				false)))
	}
	f64f64("Floor")
	f64f64("Ceil")
	f64f64("Round")
	f64f64("Trunc")
	f64f64("Log")
	f64f64("Log2")
	f64f64("Log10")
	f64f64("Exp")
	f64f64("Sin")
	f64f64("Cos")
	f64f64("Tan")

	f64f64f64 := func(name string) {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64]),
					types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Float64])),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
				false)))
	}
	f64f64f64("Pow")
	f64f64f64("Mod")
	f64f64f64("Remainder")
	f64f64f64("Dim")
	f64f64f64("Copysign")
	f64f64f64("Atan2")
	f64f64f64("Hypot")
	f64f64f64("Nextafter")

	// func Nextafter32(x, y float32) float32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Nextafter32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float32]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Float32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float32])),
			false)))

	// More unary float64 → float64 functions
	f64f64("Asin")
	f64f64("Acos")
	f64f64("Atan")
	f64f64("Sinh")
	f64f64("Cosh")
	f64f64("Tanh")
	f64f64("Asinh")
	f64f64("Acosh")
	f64f64("Atanh")
	f64f64("Exp2")
	f64f64("Expm1")
	f64f64("Log1p")
	f64f64("Logb")
	f64f64("Cbrt")
	f64f64("Erf")
	f64f64("Erfc")
	f64f64("Erfcinv")
	f64f64("Erfinv")
	f64f64("Gamma")
	f64f64("J0")
	f64f64("J1")
	f64f64("Y0")
	f64f64("Y1")
	f64f64("RoundToEven")

	// func Pow10(n int) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pow10",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Ilogb(x float64) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Ilogb",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Ldexp(frac float64, exp int) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Ldexp",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "frac", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "exp", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Frexp(f float64) (frac float64, exp int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Frexp",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f", types.Typ[types.Float64])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "frac", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "exp", types.Typ[types.Int])),
			false)))

	// func Modf(f float64) (int float64, frac float64)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Modf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f", types.Typ[types.Float64])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "frac", types.Typ[types.Float64])),
			false)))

	// func Sincos(x float64) (sin, cos float64)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sincos",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "sin", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "cos", types.Typ[types.Float64])),
			false)))

	// func Lgamma(x float64) (lgamma float64, sign int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lgamma",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "lgamma", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "sign", types.Typ[types.Int])),
			false)))

	// func Jn(n int, x float64) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Jn",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Yn(n int, x float64) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Yn",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func FMA(x, y, z float64) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FMA",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "z", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Float32bits(f float32) uint32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float32bits",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f", types.Typ[types.Float32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])),
			false)))

	// func Float32frombits(b uint32) float32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float32frombits",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float32])),
			false)))

	// func Inf(sign int) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Inf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "sign", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func NaN() float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NaN",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func IsNaN(f float64) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsNaN",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IsInf(f float64, sign int) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsInf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "f", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "sign", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Signbit(x float64) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Signbit",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Float64bits(f float64) uint64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float64bits",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))

	// func Float64frombits(b uint64) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float64frombits",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// Constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "Pi", types.Typ[types.UntypedFloat], constant.MakeFloat64(3.141592653589793)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "E", types.Typ[types.UntypedFloat], constant.MakeFloat64(2.718281828459045)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Phi", types.Typ[types.UntypedFloat], constant.MakeFloat64(1.618033988749895)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Ln2", types.Typ[types.UntypedFloat], constant.MakeFloat64(0.6931471805599453)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Ln10", types.Typ[types.UntypedFloat], constant.MakeFloat64(2.302585092994046)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Log2E", types.Typ[types.UntypedFloat], constant.MakeFloat64(1.4426950408889634)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Log10E", types.Typ[types.UntypedFloat], constant.MakeFloat64(0.4342944819032518)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxFloat64", types.Typ[types.UntypedFloat], constant.MakeFloat64(1.7976931348623157e+308)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SmallestNonzeroFloat64", types.Typ[types.UntypedFloat], constant.MakeFloat64(5e-324)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxFloat32", types.Typ[types.UntypedFloat], constant.MakeFloat64(3.4028234663852886e+38)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SmallestNonzeroFloat32", types.Typ[types.UntypedFloat], constant.MakeFloat64(1.401298464324817e-45)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxInt", types.Typ[types.UntypedInt], constant.MakeInt64(9223372036854775807)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MinInt", types.Typ[types.UntypedInt], constant.MakeInt64(-9223372036854775808)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxInt8", types.Typ[types.UntypedInt], constant.MakeInt64(127)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MinInt8", types.Typ[types.UntypedInt], constant.MakeInt64(-128)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxInt16", types.Typ[types.UntypedInt], constant.MakeInt64(32767)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MinInt16", types.Typ[types.UntypedInt], constant.MakeInt64(-32768)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxInt32", types.Typ[types.UntypedInt], constant.MakeInt64(2147483647)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MinInt32", types.Typ[types.UntypedInt], constant.MakeInt64(-2147483648)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxInt64", types.Typ[types.UntypedInt], constant.MakeInt64(9223372036854775807)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxUint8", types.Typ[types.UntypedInt], constant.MakeInt64(255)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxUint16", types.Typ[types.UntypedInt], constant.MakeInt64(65535)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxUint32", types.Typ[types.UntypedInt], constant.MakeInt64(4294967295)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Sqrt2", types.Typ[types.UntypedFloat], constant.MakeFloat64(1.4142135623730951)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SqrtE", types.Typ[types.UntypedFloat], constant.MakeFloat64(1.6487212707001282)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SqrtPi", types.Typ[types.UntypedFloat], constant.MakeFloat64(1.7724538509055159)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SqrtPhi", types.Typ[types.UntypedFloat], constant.MakeFloat64(1.272019649514069)))

	pkg.MarkComplete()
	return pkg
}

func buildMathRandPackage() *types.Package {
	pkg := types.NewPackage("math/rand", "rand")
	scope := pkg.Scope()

	// type Source interface { Int63() int64; Seed(seed int64) }
	sourceIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Int63",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
				false)),
		types.NewFunc(token.NoPos, nil, "Seed",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "seed", types.Typ[types.Int64])),
				nil, false)),
	}, nil)
	sourceIface.Complete()
	sourceType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Source", nil),
		sourceIface, nil)
	scope.Insert(sourceType.Obj())

	// type Source64 interface { Source + Uint64() uint64 }
	source64Iface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Int63",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
				false)),
		types.NewFunc(token.NoPos, nil, "Seed",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "seed", types.Typ[types.Int64])),
				nil, false)),
		types.NewFunc(token.NoPos, nil, "Uint64",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])),
				false)),
	}, nil)
	source64Iface.Complete()
	source64Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Source64", nil),
		source64Iface, nil)
	scope.Insert(source64Type.Obj())

	// type Rand struct
	randStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "src", sourceIface, false),
	}, nil)
	randType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Rand", nil),
		randStruct, nil)
	scope.Insert(randType.Obj())
	randPtr := types.NewPointer(randType)

	// Rand methods
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Intn",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int31",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int32])),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int31n",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int32])),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int63",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int63n",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint32",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float32",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float32])),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "NormFloat64",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExpFloat64",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Perm",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Int]))),
			false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Shuffle",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "swap", types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
						types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
					nil, false))),
			nil, false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seed",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "seed", types.Typ[types.Int64])),
			nil, false)))
	randType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", randPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", types.Universe.Lookup("error").Type())),
			false)))

	// func New(src Source) *Rand
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "src", sourceIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", randPtr)),
			false)))

	// func NewSource(seed int64) Source
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewSource",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seed", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", sourceIface)),
			false)))

	// Package-level convenience functions (use default global Rand)

	// func Intn(n int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Intn",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Int() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Float64() float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Float32() float32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float32",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float32])),
			false)))

	// func Seed(seed int64)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Seed",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seed", types.Typ[types.Int64])),
			nil, false)))

	// func Int31() int32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int31",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))

	// func Int31n(n int32) int32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int31n",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))

	// func Int63() int64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int63",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))

	// func Int63n(n int64) int64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int63n",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))

	// func Uint32() uint32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint32",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])),
			false)))

	// func Uint64() uint64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))

	// func NormFloat64() float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NormFloat64",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func ExpFloat64() float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ExpFloat64",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Perm(n int) []int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Perm",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Int]))),
			false)))

	// func Shuffle(n int, swap func(i, j int))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Shuffle",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "swap", types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
						types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
					nil, false))),
			nil, false)))

	// func Read(p []byte) (n int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", types.Universe.Lookup("error").Type())),
			false)))

	// type Zipf struct
	zipfStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "r", randPtr, false),
	}, nil)
	zipfType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Zipf", nil),
		zipfStruct, nil)
	scope.Insert(zipfType.Obj())
	zipfPtr := types.NewPointer(zipfType)

	zipfType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "z", zipfPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])),
			false)))

	// func NewZipf(r *Rand, s float64, v float64, imax uint64) *Zipf
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewZipf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", randPtr),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "v", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "imax", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", zipfPtr)),
			false)))

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
