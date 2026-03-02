package dis

// TypeDesc represents a Dis type descriptor.
// Type descriptors tell the garbage collector which word-aligned offsets
// in a data structure contain pointers.
type TypeDesc struct {
	ID   int    // Type descriptor ID (index in module's type table)
	Size int    // Size of the described type in bytes
	Map  []byte // Pointer bitmap: each bit covers IBY2WD bytes; high bit first
}

// NewTypeDesc creates a type descriptor with the given ID and byte size.
// The pointer bitmap is initially empty (no pointers).
func NewTypeDesc(id, size int) TypeDesc {
	nwords := (size + IBY2WD - 1) / IBY2WD
	nbytes := (nwords + 7) / 8
	return TypeDesc{
		ID:   id,
		Size: size,
		Map:  make([]byte, nbytes),
	}
}

// SetPointer marks the word at the given byte offset as containing a pointer.
// The offset must be word-aligned (multiple of IBY2WD).
func (td *TypeDesc) SetPointer(byteOffset int) {
	wordIndex := byteOffset / IBY2WD
	byteIdx := wordIndex / 8
	bitIdx := uint(7 - wordIndex%8) // High bit first
	if byteIdx >= len(td.Map) {
		// Extend the map if needed
		newMap := make([]byte, byteIdx+1)
		copy(newMap, td.Map)
		td.Map = newMap
	}
	td.Map[byteIdx] |= 1 << bitIdx
}

// HasPointer returns true if the word at the given byte offset is marked as a pointer.
func (td *TypeDesc) HasPointer(byteOffset int) bool {
	wordIndex := byteOffset / IBY2WD
	byteIdx := wordIndex / 8
	bitIdx := uint(7 - wordIndex%8)
	if byteIdx >= len(td.Map) {
		return false
	}
	return td.Map[byteIdx]&(1<<bitIdx) != 0
}

// NMap returns the number of bytes in the pointer bitmap.
func (td *TypeDesc) NMap() int {
	return len(td.Map)
}

// TrimMap removes trailing zero bytes from the pointer bitmap.
func (td *TypeDesc) TrimMap() {
	n := len(td.Map)
	for n > 0 && td.Map[n-1] == 0 {
		n--
	}
	td.Map = td.Map[:n]
}
