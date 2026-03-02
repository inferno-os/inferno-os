package dis

// DataItem represents a single data initialization item in the module data section.
type DataItem struct {
	Kind   byte   // DEFB, DEFW, DEFS, DEFF, DEFL, DEFA, DIND, DAPOP
	Offset int32  // Byte offset in the data segment
	Count  int32  // Number of items (for multi-valued kinds)
	Bytes  []byte // DEFB: raw bytes

	// DEFW: 4-byte big-endian words (loaded into WORD-sized slots)
	Words []uint32

	// DEFL: 8-byte big-endian values
	Longs []int64

	// DEFF: 8-byte IEEE754 doubles
	Reals []float64

	// DEFS: UTF string content
	Str string

	// DEFA: array type descriptor ID and length
	ArrayTypeID int32
	ArrayLen    int32

	// DIND: array index to set
	ArrayIndex int32
}

// DefBytes creates a DEFB data item.
func DefBytes(offset int32, b []byte) DataItem {
	return DataItem{Kind: DEFB, Offset: offset, Count: int32(len(b)), Bytes: b}
}

// DefWord creates a DEFW data item with a single word.
func DefWord(offset int32, val uint32) DataItem {
	return DataItem{Kind: DEFW, Offset: offset, Count: 1, Words: []uint32{val}}
}

// DefWords creates a DEFW data item with multiple words.
func DefWords(offset int32, vals []uint32) DataItem {
	return DataItem{Kind: DEFW, Offset: offset, Count: int32(len(vals)), Words: vals}
}

// DefString creates a DEFS data item.
func DefString(offset int32, s string) DataItem {
	return DataItem{Kind: DEFS, Offset: offset, Count: int32(len(s)), Str: s}
}

// DefReal creates a DEFF data item with a single real.
func DefReal(offset int32, val float64) DataItem {
	return DataItem{Kind: DEFF, Offset: offset, Count: 1, Reals: []float64{val}}
}

// DefLong creates a DEFL data item with a single big (int64).
func DefLong(offset int32, val int64) DataItem {
	return DataItem{Kind: DEFL, Offset: offset, Count: 1, Longs: []int64{val}}
}

// DefArray creates a DEFA data item.
func DefArray(offset int32, typeID, length int32) DataItem {
	return DataItem{Kind: DEFA, Offset: offset, Count: 1, ArrayTypeID: typeID, ArrayLen: length}
}

// DefInd creates a DIND data item (set array index).
func DefInd(offset int32, index int32) DataItem {
	return DataItem{Kind: DIND, Offset: offset, Count: 1, ArrayIndex: index}
}

// DefApop creates a DAPOP data item (restore address register).
func DefApop() DataItem {
	return DataItem{Kind: DAPOP, Offset: 0, Count: 1}
}
