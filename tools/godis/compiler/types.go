package compiler

import (
	"go/types"

	"github.com/NERVsystems/infernode/tools/godis/dis"
)

// DisType describes how a Go type maps to the Dis VM.
type DisType struct {
	Size  int32 // Size in bytes
	IsPtr bool  // Whether this type is a pointer type for GC
}

// GoTypeToDis maps a Go type to its Dis representation.
func GoTypeToDis(t types.Type) DisType {
	t = t.Underlying()

	switch t := t.(type) {
	case *types.Basic:
		return basicTypeToDis(t)
	case *types.Pointer:
		return DisType{Size: int32(dis.IBY2WD), IsPtr: true}
	case *types.Slice:
		// Go slices → Dis Array* (pointer to heap-allocated array)
		return DisType{Size: int32(dis.IBY2WD), IsPtr: true}
	case *types.Array:
		// Fixed-size arrays: inline if small, or heap-allocated
		elemDis := GoTypeToDis(t.Elem())
		return DisType{Size: elemDis.Size * int32(t.Len()), IsPtr: false}
	case *types.Map:
		// Maps → pointer to runtime hash table
		return DisType{Size: int32(dis.IBY2WD), IsPtr: true}
	case *types.Chan:
		// Go channels → Dis channels (pointer)
		return DisType{Size: int32(dis.IBY2WD), IsPtr: true}
	case *types.Struct:
		return structTypeToDis(t)
	case *types.Interface:
		// Tagged interface: 2 consecutive WORDs.
		//   offset+0: type tag (int32 ID identifying the concrete type, 0 = nil)
		//   offset+8: value   (raw value or pointer to struct data)
		// Both slots are non-pointer (WORD) — same GC semantics as before.
		return DisType{Size: 2 * int32(dis.IBY2WD), IsPtr: false}
	case *types.Signature:
		// Function value = pointer
		return DisType{Size: int32(dis.IBY2WD), IsPtr: true}
	case *types.Named:
		return GoTypeToDis(t.Underlying())
	default:
		// Default to word-sized
		return DisType{Size: int32(dis.IBY2WD), IsPtr: false}
	}
}

func basicTypeToDis(t *types.Basic) DisType {
	switch t.Kind() {
	case types.Bool:
		return DisType{Size: int32(dis.IBY2WD), IsPtr: false}
	case types.Int, types.Int64, types.Uint, types.Uint64, types.Uintptr:
		return DisType{Size: int32(dis.IBY2WD), IsPtr: false}
	case types.Int8, types.Uint8:
		// Byte types are word-sized in frame slots for simplicity
		return DisType{Size: int32(dis.IBY2WD), IsPtr: false}
	case types.Int16, types.Uint16:
		return DisType{Size: int32(dis.IBY2WD), IsPtr: false}
	case types.Int32, types.Uint32:
		return DisType{Size: int32(dis.IBY2WD), IsPtr: false}
	case types.Float32:
		return DisType{Size: int32(dis.IBY2WD), IsPtr: false}
	case types.Float64:
		return DisType{Size: int32(dis.IBY2WD), IsPtr: false}
	case types.String:
		// Go strings → Dis String* (pointer, GC-tracked)
		return DisType{Size: int32(dis.IBY2WD), IsPtr: true}
	case types.Complex64, types.Complex128:
		// Complex numbers: 2 consecutive float64 slots (real, imag)
		return DisType{Size: 2 * int32(dis.IBY2WD), IsPtr: false}
	case types.UnsafePointer:
		return DisType{Size: int32(dis.IBY2WD), IsPtr: true}
	default:
		return DisType{Size: int32(dis.IBY2WD), IsPtr: false}
	}
}

func structTypeToDis(t *types.Struct) DisType {
	var size int32
	hasPtr := false
	for i := 0; i < t.NumFields(); i++ {
		f := GoTypeToDis(t.Field(i).Type())
		size += f.Size
		if f.IsPtr {
			hasPtr = true
		}
	}
	// Align to word boundary
	if size%int32(dis.IBY2WD) != 0 {
		size = (size + int32(dis.IBY2WD) - 1) &^ (int32(dis.IBY2WD) - 1)
	}
	return DisType{Size: size, IsPtr: hasPtr}
}

// IsComplexType returns true if the Go type is complex64 or complex128.
func IsComplexType(t types.Type) bool {
	t = t.Underlying()
	if basic, ok := t.(*types.Basic); ok {
		return basic.Kind() == types.Complex64 || basic.Kind() == types.Complex128
	}
	return false
}

// IsByteType returns true if the Go type is a byte (uint8) type.
// Used to select byte-sized Dis operations (INDB, CVTWB, CVTBW) vs word-sized ones.
func IsByteType(t types.Type) bool {
	t = t.Underlying()
	if basic, ok := t.(*types.Basic); ok {
		return basic.Kind() == types.Byte || basic.Kind() == types.Uint8
	}
	return false
}

// DisElementSize returns the element size in bytes for array storage.
// Unlike GoTypeToDis().Size which returns frame slot size (always >= 8),
// this returns the actual element size for Dis arrays: 1 for byte, 8 for word.
func DisElementSize(t types.Type) int {
	if IsByteType(t) {
		return 1
	}
	return int(GoTypeToDis(t).Size)
}

// IsWordOp returns the appropriate Dis opcode suffix for a Go basic type.
// Returns "w" for word-sized integers, "f" for floats, "l" for int64/big,
// "c" for strings.
func DisOpSuffix(t types.Type) string {
	t = t.Underlying()
	if basic, ok := t.(*types.Basic); ok {
		switch basic.Kind() {
		case types.Float32, types.Float64:
			return "f"
		case types.String:
			return "c"
		case types.Int64, types.Uint64:
			// On 64-bit Dis, WORD=LONG=8 bytes, so use "w" ops
			return "w"
		default:
			return "w"
		}
	}
	return "w"
}
