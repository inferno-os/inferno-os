package dis

// Module represents a complete Dis module (.dis file).
type Module struct {
	// Header fields
	Name         string // Module name
	Magic        int32  // XMAGIC or SMAGIC
	RuntimeFlags int32  // MUSTCOMPILE, DONTCOMPILE, SHAREMP, HASLDT, HASEXCEPT, etc.
	StackSize    int32  // Recommended stack size in bytes

	// Code
	Instructions []Inst

	// Type descriptors
	TypeDescs []TypeDesc

	// Module data initialization
	DataSize int32      // Size of module data segment (must match TypeDescs[0].Size)
	Data     []DataItem // Data initialization items

	// Entry point
	EntryPC   int32 // Instruction index of entry function
	EntryType int32 // Type descriptor ID of entry function's frame

	// External linkage (exported functions)
	Links []Link

	// Link Descriptor Tables (imported modules)
	// Each element is a table of imports for one module.
	LDT [][]Import

	// Exception handlers
	Handlers []Handler

	// Source path (trailing metadata, not loaded by VM but emitted by compiler)
	SrcPath string
}

// Link represents an exported function or the module data (.mp) entry.
type Link struct {
	PC     int32  // Function entry PC (-1 for .mp)
	DescID int32  // Frame type descriptor ID (-1 for .mp)
	Sig    uint32 // MD5-based type signature
	Name   string // Function name (e.g., "init", "Foo.bar", ".mp")
}

// Import represents a single imported function from an external module.
type Import struct {
	Sig  uint32 // MD5-based type signature
	Name string // Function name
}

// Handler represents an exception handler for a code range.
type Handler struct {
	EOffset int32    // Exception data offset in frame
	PC1     int32    // Start PC of covered range
	PC2     int32    // End PC of covered range
	DescID  int32    // Type descriptor ID for exception data (-1 if none)
	NEtab   int32    // Number of named exceptions
	NE      int32    // Exception scope depth (packed as ne<<16 | nlab)
	Etab    []Except // Named exception entries
	WildPC  int32    // Wildcard (*) handler PC (-1 if none)
}

// Except represents a named exception handler entry.
type Except struct {
	Name string // Exception name
	PC   int32  // Handler PC
}

// NewModule creates a new unsigned module with sensible defaults.
func NewModule(name string) *Module {
	return &Module{
		Name:      name,
		Magic:     XMAGIC,
		StackSize: 64 * 1024, // 64KB default stack
	}
}

// AddTypeDesc adds a type descriptor and returns its ID.
func (m *Module) AddTypeDesc(td TypeDesc) int {
	id := len(m.TypeDescs)
	td.ID = id
	m.TypeDescs = append(m.TypeDescs, td)
	return id
}

// AddLink adds an external link entry.
func (m *Module) AddLink(l Link) {
	m.Links = append(m.Links, l)
}

// AddInst appends an instruction and returns its PC (index).
func (m *Module) AddInst(inst Inst) int32 {
	pc := int32(len(m.Instructions))
	m.Instructions = append(m.Instructions, inst)
	return pc
}
