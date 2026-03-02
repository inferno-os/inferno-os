package compiler

import "github.com/NERVsystems/infernode/tools/godis/dis"

// Frame tracks the layout of a function's stack frame.
// In Dis, each function has a fixed-size frame allocated on the stack.
// The frame contains:
//   - Header registers: REGLINK, REGFRAME, REGMOD, REGTYP, REGRET (5 * IBY2WD)
//   - Scratch temporaries: STemp, RTemp, DTemp (3 * IBY2WD)
//   - Local variables and temporaries
//   - Space for callee arguments
type Frame struct {
	slots   []FrameSlot // allocated slots
	nextOff int32       // next available byte offset
	maxOff  int32       // high water mark (total frame size)
	ptrSlots map[int32]bool // byte offsets that contain pointers
}

// FrameSlot represents a single allocated slot in the frame.
type FrameSlot struct {
	Name   string
	Offset int32
	Size   int32
	IsPtr  bool // true if this slot holds a pointer (for GC)
}

// NewFrame creates a new frame layout.
// Local variables start at MaxTemp (offset 64 on 64-bit).
func NewFrame() *Frame {
	return &Frame{
		nextOff:  int32(dis.MaxTemp),
		maxOff:   int32(dis.MaxTemp),
		ptrSlots: make(map[int32]bool),
	}
}

// AllocWord allocates a word-sized (IBY2WD) non-pointer slot.
func (f *Frame) AllocWord(name string) int32 {
	return f.alloc(name, int32(dis.IBY2WD), false)
}

// AllocPointer allocates a word-sized pointer slot (for strings, refs, arrays, etc.).
func (f *Frame) AllocPointer(name string) int32 {
	return f.alloc(name, int32(dis.IBY2WD), true)
}

// AllocReal allocates an 8-byte real (float64) slot.
func (f *Frame) AllocReal(name string) int32 {
	return f.alloc(name, 8, false)
}

// AllocTemp allocates an unnamed temporary slot.
func (f *Frame) AllocTemp(isPtr bool) int32 {
	if isPtr {
		return f.alloc("", int32(dis.IBY2WD), true)
	}
	return f.alloc("", int32(dis.IBY2WD), false)
}

func (f *Frame) alloc(name string, size int32, isPtr bool) int32 {
	// Align to word boundary for pointer types
	if isPtr && f.nextOff%int32(dis.IBY2WD) != 0 {
		f.nextOff = (f.nextOff + int32(dis.IBY2WD) - 1) &^ (int32(dis.IBY2WD) - 1)
	}

	offset := f.nextOff
	f.slots = append(f.slots, FrameSlot{
		Name:   name,
		Offset: offset,
		Size:   size,
		IsPtr:  isPtr,
	})
	if isPtr {
		f.ptrSlots[offset] = true
	}
	f.nextOff += size
	if f.nextOff > f.maxOff {
		f.maxOff = f.nextOff
	}
	return offset
}

// Size returns the total frame size in bytes (aligned up to word boundary).
func (f *Frame) Size() int32 {
	aligned := (f.maxOff + int32(dis.IBY2WD) - 1) &^ (int32(dis.IBY2WD) - 1)
	return aligned
}

// TypeDesc generates a Dis type descriptor for this frame.
func (f *Frame) TypeDesc(id int) dis.TypeDesc {
	td := dis.NewTypeDesc(id, int(f.Size()))

	// NOTE: Do NOT mark frame header registers (REGLINK, REGFRAME, REGMOD,
	// REGTYP, REGRET) as pointers. The VM manages these internally during GC
	// via the Frame struct. The type map only covers user-allocated slots
	// starting at MaxTemp.

	// Mark user-allocated pointer slots
	for off := range f.ptrSlots {
		td.SetPointer(int(off))
	}

	return td
}

// ModuleData tracks the layout of the module data segment (MP).
type ModuleData struct {
	nextOff  int32
	ptrSlots map[int32]bool
}

// NewModuleData creates a new module data layout.
func NewModuleData() *ModuleData {
	return &ModuleData{
		ptrSlots: make(map[int32]bool),
	}
}

// AllocPointer allocates a pointer slot in the module data.
func (md *ModuleData) AllocPointer(name string) int32 {
	offset := md.nextOff
	md.ptrSlots[offset] = true
	md.nextOff += int32(dis.IBY2WD)
	return offset
}

// AllocWord allocates a non-pointer word in the module data.
func (md *ModuleData) AllocWord(name string) int32 {
	offset := md.nextOff
	md.nextOff += int32(dis.IBY2WD)
	return offset
}

// Size returns the total module data size in bytes.
func (md *ModuleData) Size() int32 {
	aligned := (md.nextOff + int32(dis.IBY2WD) - 1) &^ (int32(dis.IBY2WD) - 1)
	if aligned == 0 {
		return int32(dis.IBY2WD) // minimum size
	}
	return aligned
}

// TypeDesc generates a type descriptor for the module data.
func (md *ModuleData) TypeDesc(id int) dis.TypeDesc {
	td := dis.NewTypeDesc(id, int(md.Size()))
	for off := range md.ptrSlots {
		td.SetPointer(int(off))
	}
	return td
}
