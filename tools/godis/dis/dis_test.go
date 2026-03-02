package dis

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestEncodeOperand(t *testing.T) {
	tests := []struct {
		val    int32
		nbytes int
	}{
		// 1-byte range: [-64, 63]
		{0, 1},
		{1, 1},
		{63, 1},
		{-1, 1},
		{-64, 1},

		// 2-byte range: [-8192, 8191]
		{64, 2},
		{-65, 2},
		{8191, 2},
		{-8192, 2},
		{100, 2},
		{-100, 2},

		// 4-byte range
		{8192, 4},
		{-8193, 4},
		{100000, 4},
		{-100000, 4},
		{0x1FFFFFFF, 4},  // max positive
		{-0x20000000, 4}, // min negative
	}

	for _, tt := range tests {
		var buf bytes.Buffer
		encodeOperand(&buf, tt.val)
		encoded := buf.Bytes()

		if len(encoded) != tt.nbytes {
			t.Errorf("encodeOperand(%d): got %d bytes, want %d", tt.val, len(encoded), tt.nbytes)
			continue
		}

		// Decode and verify round-trip
		r := &reader{data: encoded, pos: 0}
		decoded, err := r.operand()
		if err != nil {
			t.Errorf("decodeOperand(%d): %v", tt.val, err)
			continue
		}
		if decoded != tt.val {
			t.Errorf("round-trip operand %d: got %d", tt.val, decoded)
		}
	}
}

func TestEncodeWord(t *testing.T) {
	tests := []uint32{0, 1, 0xFF, 0xFFFF, 0xFFFFFF, 0xFFFFFFFF, 0xAC849033, 0xDEADBEEF}
	for _, val := range tests {
		var buf bytes.Buffer
		encodeWord(&buf, val)
		encoded := buf.Bytes()
		if len(encoded) != 4 {
			t.Errorf("encodeWord(0x%x): got %d bytes, want 4", val, len(encoded))
			continue
		}
		r := &reader{data: encoded, pos: 0}
		decoded, err := r.readWord()
		if err != nil {
			t.Errorf("readWord(0x%x): %v", val, err)
			continue
		}
		if decoded != val {
			t.Errorf("round-trip word 0x%x: got 0x%x", val, decoded)
		}
	}
}

func TestInstructionEncoding(t *testing.T) {
	tests := []struct {
		name string
		inst Inst
	}{
		{"nop", Inst0(INOP)},
		{"ret", Inst0(IRET)},
		{"exit", Inst0(IEXIT)},
		{"movw fp->fp", Inst2(IMOVW, FP(64), FP(72))},
		{"movw imm->fp", Inst2(IMOVW, Imm(42), FP(64))},
		{"addw 3-operand", NewInst(IADDW, FP(64), FP(72), FP(80))},
		{"jmp", Inst1(IJMP, Imm(10))},
		{"beqw", NewInst(IBEQW, FP(64), FP(72), Imm(5))},
		{"movp mp->fp", Inst2(IMOVP, MP(0), FP(64))},
		{"indirect src", Inst{Op: IMOVW, Src: FPInd(64, 8), Dst: FP(72)}},
		{"indirect dst", Inst{Op: IMOVW, Src: FP(64), Dst: FPInd(72, 8)}},
		{"large offset", Inst2(IMOVW, FP(10000), FP(20000))},
		{"negative offset", Inst2(IMOVW, Imm(-1), FP(64))},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var buf bytes.Buffer
			encodeInst(&buf, tt.inst)
			encoded := buf.Bytes()

			if len(encoded) < 2 {
				t.Fatalf("encoded instruction too short: %d bytes", len(encoded))
			}

			// Verify opcode
			if Op(encoded[0]) != tt.inst.Op {
				t.Errorf("opcode: got %d, want %d", encoded[0], tt.inst.Op)
			}

			// Round-trip
			r := &reader{data: encoded, pos: 0}
			decoded, err := r.readInst()
			if err != nil {
				t.Fatalf("decode: %v", err)
			}

			if decoded.Op != tt.inst.Op {
				t.Errorf("op: got %v, want %v", decoded.Op, tt.inst.Op)
			}
			if decoded.Src != tt.inst.Src {
				t.Errorf("src: got %v, want %v", decoded.Src, tt.inst.Src)
			}
			if decoded.Mid != tt.inst.Mid {
				t.Errorf("mid: got %v, want %v", decoded.Mid, tt.inst.Mid)
			}
			if decoded.Dst != tt.inst.Dst {
				t.Errorf("dst: got %v, want %v", decoded.Dst, tt.inst.Dst)
			}
		})
	}
}

func TestTypeDescPointerBitmap(t *testing.T) {
	// Frame with 2 words: word 0 is not a pointer, word 1 is a pointer
	td := NewTypeDesc(0, 16)
	td.SetPointer(8) // second word

	if td.HasPointer(0) {
		t.Error("word 0 should not be a pointer")
	}
	if !td.HasPointer(8) {
		t.Error("word 1 should be a pointer")
	}

	// Bitmap: bit 6 (second word, high bit first)
	// Byte 0: bit 7 = word 0, bit 6 = word 1
	if td.Map[0] != 0x40 {
		t.Errorf("bitmap: got 0x%02x, want 0x40", td.Map[0])
	}
}

func TestTypeDescMultiplePointers(t *testing.T) {
	// 5 words: pointers at 0, 8, 32
	td := NewTypeDesc(0, 40)
	td.SetPointer(0)
	td.SetPointer(8)
	td.SetPointer(32)

	// Byte 0: bit 7 (word 0) + bit 6 (word 1) + bit 3 (word 4) = 0xC8
	if td.Map[0] != 0xC8 {
		t.Errorf("bitmap: got 0x%02x, want 0xC8", td.Map[0])
	}
}

func TestModuleRoundTrip(t *testing.T) {
	m := NewModule("TestModule")

	// Type desc 0: module data (16 bytes, pointer at offset 0)
	mpType := NewTypeDesc(0, 16)
	mpType.SetPointer(0) // sys module reference
	m.AddTypeDesc(mpType)
	m.DataSize = 16

	// Type desc 1: init frame (72 bytes, no pointers beyond header)
	frameType := NewTypeDesc(1, 72)
	// Frame registers 0-4 contain pointers (lr, fp, mr, t, ret)
	frameType.SetPointer(0 * IBY2WD) // REGLINK
	frameType.SetPointer(1 * IBY2WD) // REGFRAME
	frameType.SetPointer(2 * IBY2WD) // REGMOD
	frameType.SetPointer(3 * IBY2WD) // REGTYP
	frameType.SetPointer(4 * IBY2WD) // REGRET
	m.AddTypeDesc(frameType)

	// Instructions: simple exit
	m.AddInst(Inst0(IEXIT))

	m.EntryPC = 0
	m.EntryType = 1

	// Links
	m.AddLink(Link{PC: -1, DescID: -1, Sig: 0x12345678, Name: ".mp"})
	m.AddLink(Link{PC: 0, DescID: 1, Sig: 0xABCDEF00, Name: "init"})

	// Encode
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}

	// Decode
	decoded, err := Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	// Verify
	if decoded.Name != m.Name {
		t.Errorf("name: got %q, want %q", decoded.Name, m.Name)
	}
	if decoded.Magic != m.Magic {
		t.Errorf("magic: got %d, want %d", decoded.Magic, m.Magic)
	}
	if decoded.StackSize != m.StackSize {
		t.Errorf("stack size: got %d, want %d", decoded.StackSize, m.StackSize)
	}
	if decoded.DataSize != m.DataSize {
		t.Errorf("data size: got %d, want %d", decoded.DataSize, m.DataSize)
	}
	if decoded.EntryPC != m.EntryPC {
		t.Errorf("entry pc: got %d, want %d", decoded.EntryPC, m.EntryPC)
	}
	if decoded.EntryType != m.EntryType {
		t.Errorf("entry type: got %d, want %d", decoded.EntryType, m.EntryType)
	}
	if len(decoded.Instructions) != len(m.Instructions) {
		t.Fatalf("instructions: got %d, want %d", len(decoded.Instructions), len(m.Instructions))
	}
	if decoded.Instructions[0].Op != IEXIT {
		t.Errorf("inst[0] op: got %v, want exit", decoded.Instructions[0].Op)
	}
	if len(decoded.TypeDescs) != len(m.TypeDescs) {
		t.Fatalf("type descs: got %d, want %d", len(decoded.TypeDescs), len(m.TypeDescs))
	}
	if len(decoded.Links) != len(m.Links) {
		t.Fatalf("links: got %d, want %d", len(decoded.Links), len(m.Links))
	}
	for i, l := range decoded.Links {
		if l.Name != m.Links[i].Name {
			t.Errorf("link[%d] name: got %q, want %q", i, l.Name, m.Links[i].Name)
		}
		if l.Sig != m.Links[i].Sig {
			t.Errorf("link[%d] sig: got 0x%x, want 0x%x", i, l.Sig, m.Links[i].Sig)
		}
	}

	// Re-encode and verify byte-identical
	reencoded, err := decoded.EncodeToBytes()
	if err != nil {
		t.Fatalf("re-encode: %v", err)
	}
	if !bytes.Equal(encoded, reencoded) {
		t.Errorf("re-encoded bytes differ: got %d bytes, want %d bytes", len(reencoded), len(encoded))
		// Show first difference
		for i := 0; i < len(encoded) && i < len(reencoded); i++ {
			if encoded[i] != reencoded[i] {
				t.Errorf("first difference at byte %d: got 0x%02x, want 0x%02x", i, reencoded[i], encoded[i])
				break
			}
		}
	}
}

func TestModuleWithData(t *testing.T) {
	m := NewModule("DataTest")

	// Type desc 0: module data with a string slot
	mpType := NewTypeDesc(0, 8)
	mpType.SetPointer(0) // string pointer
	m.AddTypeDesc(mpType)
	m.DataSize = 8

	// Type desc 1: frame
	frameType := NewTypeDesc(1, MaxTemp)
	m.AddTypeDesc(frameType)

	// Data: a string at offset 0
	m.Data = append(m.Data, DefString(0, "hello"))

	// Instructions
	m.AddInst(Inst0(IEXIT))
	m.EntryPC = 0
	m.EntryType = 1

	// Round-trip
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}

	decoded, err := Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	if len(decoded.Data) != 1 {
		t.Fatalf("data items: got %d, want 1", len(decoded.Data))
	}
	if decoded.Data[0].Kind != DEFS {
		t.Errorf("data kind: got %d, want DEFS(%d)", decoded.Data[0].Kind, DEFS)
	}
	if decoded.Data[0].Str != "hello" {
		t.Errorf("data string: got %q, want %q", decoded.Data[0].Str, "hello")
	}
}

func TestModuleWithLDT(t *testing.T) {
	m := NewModule("LDTTest")
	m.RuntimeFlags = HASLDT

	mpType := NewTypeDesc(0, 8)
	m.AddTypeDesc(mpType)
	m.DataSize = 8

	frameType := NewTypeDesc(1, MaxTemp)
	m.AddTypeDesc(frameType)

	m.AddInst(Inst0(IEXIT))
	m.EntryPC = 0
	m.EntryType = 1

	// LDT: one module with two function imports
	m.LDT = [][]Import{
		{
			{Sig: 0xAC849033, Name: "print"},
			{Sig: 0x1478F993, Name: "fildes"},
		},
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}

	decoded, err := Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	if len(decoded.LDT) != 1 {
		t.Fatalf("LDT entries: got %d, want 1", len(decoded.LDT))
	}
	if len(decoded.LDT[0]) != 2 {
		t.Fatalf("LDT[0] imports: got %d, want 2", len(decoded.LDT[0]))
	}
	if decoded.LDT[0][0].Name != "print" {
		t.Errorf("LDT[0][0] name: got %q, want %q", decoded.LDT[0][0].Name, "print")
	}
	if decoded.LDT[0][0].Sig != 0xAC849033 {
		t.Errorf("LDT[0][0] sig: got 0x%x, want 0xAC849033", decoded.LDT[0][0].Sig)
	}
}

func TestDecodeRealDisFiles(t *testing.T) {
	// Find and decode real .dis files from the Infernode dis/ directory
	disDir := filepath.Join("..", "..", "..", "dis")
	if _, err := os.Stat(disDir); os.IsNotExist(err) {
		t.Skip("dis/ directory not found")
	}

	// Test a few known simple .dis files
	testFiles := []string{"echo.dis", "cat.dis", "date.dis"}

	for _, name := range testFiles {
		path := filepath.Join(disDir, name)
		t.Run(name, func(t *testing.T) {
			data, err := os.ReadFile(path)
			if err != nil {
				t.Skipf("cannot read %s: %v", path, err)
				return
			}

			m, err := Decode(data)
			if err != nil {
				t.Fatalf("decode %s: %v", name, err)
			}

			// Basic sanity checks
			if m.Magic != XMAGIC && m.Magic != SMAGIC {
				t.Errorf("bad magic: %d", m.Magic)
			}
			if len(m.Instructions) == 0 {
				t.Error("no instructions")
			}
			if len(m.TypeDescs) == 0 {
				t.Error("no type descriptors")
			}
			if m.Name == "" {
				t.Error("empty module name")
			}

			t.Logf("module %q: %d instructions, %d types, %d links, data=%d bytes",
				m.Name, len(m.Instructions), len(m.TypeDescs), len(m.Links), m.DataSize)

			// Re-encode and verify byte-identical
			reencoded, err := m.EncodeToBytes()
			if err != nil {
				t.Fatalf("re-encode: %v", err)
			}

			if !bytes.Equal(data, reencoded) {
				t.Errorf("round-trip failed: original %d bytes, re-encoded %d bytes", len(data), len(reencoded))
				// Find first difference
				minLen := len(data)
				if len(reencoded) < minLen {
					minLen = len(reencoded)
				}
				for i := 0; i < minLen; i++ {
					if data[i] != reencoded[i] {
						t.Errorf("first difference at byte %d: original 0x%02x, re-encoded 0x%02x", i, data[i], reencoded[i])
						break
					}
				}
			}
		})
	}
}

func TestAddressByte(t *testing.T) {
	// Test address byte construction
	tests := []struct {
		name string
		inst Inst
		want byte
	}{
		// movw $42, 64(fp)  →  SRC=AIMM(2)<<3 | DST=AFP(1) | MID=AXNON(0)
		{"imm->fp", Inst2(IMOVW, Imm(42), FP(64)), 0x02<<3 | 0x01},
		// addw 64(fp), 72(fp), 80(fp)  →  SRC=AFP(1)<<3 | DST=AFP(1) | MID=AXINF(0x80)
		{"fp,fp,fp", NewInst(IADDW, FP(64), FP(72), FP(80)), 0x01<<3 | 0x01 | 0x80},
		// movw 0(mp), 64(fp)  →  SRC=AMP(0)<<3 | DST=AFP(1) | MID=AXNON(0)
		{"mp->fp", Inst2(IMOVW, MP(0), FP(64)), 0x00<<3 | 0x01},
		// ret  →  SRC=AXXX(3)<<3 | DST=AXXX(3) | MID=AXNON(0)
		{"no operands", Inst0(IRET), 0x03<<3 | 0x03},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.inst.AddressByte()
			if got != tt.want {
				t.Errorf("AddressByte: got 0x%02x, want 0x%02x", got, tt.want)
			}
		})
	}
}

func TestOpcodeString(t *testing.T) {
	if INOP.String() != "nop" {
		t.Errorf("INOP: got %q, want %q", INOP.String(), "nop")
	}
	if IADDW.String() != "addw" {
		t.Errorf("IADDW: got %q, want %q", IADDW.String(), "addw")
	}
	if ISELF.String() != "self" {
		t.Errorf("ISELF: got %q, want %q", ISELF.String(), "self")
	}
}
