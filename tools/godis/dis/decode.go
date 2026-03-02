package dis

import (
	"encoding/binary"
	"fmt"
	"math"
)

// Decode parses a Dis module from binary data.
// This implements the inverse of Encode and matches libinterp/load.c parsemod().
func Decode(data []byte) (*Module, error) {
	r := &reader{data: data, pos: 0}
	m := &Module{}

	// Header
	magic, err := r.operand()
	if err != nil {
		return nil, fmt.Errorf("magic: %w", err)
	}
	m.Magic = magic

	if magic == SMAGIC {
		// Signed module: skip signature
		siglen, err := r.operand()
		if err != nil {
			return nil, fmt.Errorf("siglen: %w", err)
		}
		r.pos += int(siglen)
	} else if magic != XMAGIC {
		return nil, fmt.Errorf("bad magic: %d", magic)
	}

	m.RuntimeFlags, err = r.operand()
	if err != nil {
		return nil, fmt.Errorf("runtime flags: %w", err)
	}
	m.StackSize, err = r.operand()
	if err != nil {
		return nil, fmt.Errorf("stack size: %w", err)
	}

	isize, err := r.operand()
	if err != nil {
		return nil, fmt.Errorf("isize: %w", err)
	}
	dsize, err := r.operand()
	if err != nil {
		return nil, fmt.Errorf("dsize: %w", err)
	}
	m.DataSize = dsize

	hsize, err := r.operand()
	if err != nil {
		return nil, fmt.Errorf("hsize: %w", err)
	}
	lsize, err := r.operand()
	if err != nil {
		return nil, fmt.Errorf("lsize: %w", err)
	}
	m.EntryPC, err = r.operand()
	if err != nil {
		return nil, fmt.Errorf("entry pc: %w", err)
	}
	m.EntryType, err = r.operand()
	if err != nil {
		return nil, fmt.Errorf("entry type: %w", err)
	}

	// Instructions
	m.Instructions = make([]Inst, isize)
	for i := int32(0); i < isize; i++ {
		inst, err := r.readInst()
		if err != nil {
			return nil, fmt.Errorf("instruction %d: %w", i, err)
		}
		m.Instructions[i] = inst
	}

	// Type descriptors
	m.TypeDescs = make([]TypeDesc, hsize)
	for i := int32(0); i < hsize; i++ {
		td, err := r.readTypeDesc()
		if err != nil {
			return nil, fmt.Errorf("type desc %d: %w", i, err)
		}
		m.TypeDescs[i] = td
	}

	// Data section
	m.Data, err = r.readData()
	if err != nil {
		return nil, fmt.Errorf("data: %w", err)
	}

	// Module name
	m.Name, err = r.readString()
	if err != nil {
		return nil, fmt.Errorf("module name: %w", err)
	}

	// Links
	m.Links = make([]Link, lsize)
	for i := int32(0); i < lsize; i++ {
		l, err := r.readLink()
		if err != nil {
			return nil, fmt.Errorf("link %d: %w", i, err)
		}
		m.Links[i] = l
	}

	// LDT
	if m.RuntimeFlags&HASLDT != 0 {
		m.LDT, err = r.readLDT()
		if err != nil {
			return nil, fmt.Errorf("ldt: %w", err)
		}
	}

	// Exception handlers
	if m.RuntimeFlags&HASEXCEPT != 0 {
		m.Handlers, err = r.readHandlers()
		if err != nil {
			return nil, fmt.Errorf("handlers: %w", err)
		}
	}

	// Source path (trailing null-terminated string, not loaded by VM)
	if r.remaining() > 0 {
		m.SrcPath, err = r.readString()
		if err != nil {
			// Not fatal — source path is optional metadata
			m.SrcPath = ""
		}
	}

	return m, nil
}

// reader wraps a byte slice with a position cursor.
type reader struct {
	data []byte
	pos  int
}

func (r *reader) remaining() int {
	return len(r.data) - r.pos
}

func (r *reader) readByte() (byte, error) {
	if r.pos >= len(r.data) {
		return 0, fmt.Errorf("unexpected EOF at offset %d", r.pos)
	}
	b := r.data[r.pos]
	r.pos++
	return b, nil
}

func (r *reader) readBytes(n int) ([]byte, error) {
	if r.pos+n > len(r.data) {
		return nil, fmt.Errorf("unexpected EOF: need %d bytes at offset %d", n, r.pos)
	}
	b := make([]byte, n)
	copy(b, r.data[r.pos:r.pos+n])
	r.pos += n
	return b, nil
}

// operand decodes a variable-length signed integer.
// Matches libinterp/load.c operand().
func (r *reader) operand() (int32, error) {
	c, err := r.readByte()
	if err != nil {
		return 0, err
	}
	switch c & 0xC0 {
	case 0x00:
		return int32(c), nil
	case 0x40:
		return int32(c) | ^int32(0x7F), nil
	case 0x80:
		c2, err := r.readByte()
		if err != nil {
			return 0, err
		}
		v := int32(c)
		if c&0x20 != 0 {
			v |= ^int32(0x3F)
		} else {
			v &= 0x3F
		}
		return v<<8 | int32(c2), nil
	case 0xC0:
		c2, err := r.readByte()
		if err != nil {
			return 0, err
		}
		c3, err := r.readByte()
		if err != nil {
			return 0, err
		}
		c4, err := r.readByte()
		if err != nil {
			return 0, err
		}
		v := int32(c)
		if c&0x20 != 0 {
			v |= ^int32(0x3F)
		} else {
			v &= 0x3F
		}
		return v<<24 | int32(c2)<<16 | int32(c3)<<8 | int32(c4), nil
	}
	return 0, fmt.Errorf("invalid operand encoding")
}

// readWord reads a 4-byte big-endian unsigned value.
func (r *reader) readWord() (uint32, error) {
	b, err := r.readBytes(4)
	if err != nil {
		return 0, err
	}
	return binary.BigEndian.Uint32(b), nil
}

// readString reads a null-terminated string.
func (r *reader) readString() (string, error) {
	start := r.pos
	for r.pos < len(r.data) {
		if r.data[r.pos] == 0 {
			s := string(r.data[start:r.pos])
			r.pos++ // skip null terminator
			return s, nil
		}
		r.pos++
	}
	return "", fmt.Errorf("unterminated string at offset %d", start)
}

func (r *reader) readInst() (Inst, error) {
	var inst Inst

	op, err := r.readByte()
	if err != nil {
		return inst, err
	}
	inst.Op = Op(op)

	add, err := r.readByte()
	if err != nil {
		return inst, err
	}

	// Middle operand
	switch add & ARM {
	case AXIMM:
		inst.Mid.Mode = AIMM
		inst.Mid.Val, err = r.operand()
		if err != nil {
			return inst, fmt.Errorf("mid operand: %w", err)
		}
	case AXINF:
		inst.Mid.Mode = AFP
		inst.Mid.Val, err = r.operand()
		if err != nil {
			return inst, fmt.Errorf("mid operand: %w", err)
		}
	case AXINM:
		inst.Mid.Mode = AMP
		inst.Mid.Val, err = r.operand()
		if err != nil {
			return inst, fmt.Errorf("mid operand: %w", err)
		}
	default:
		inst.Mid = NoOperand
	}

	// Source operand
	srcMode := (add >> 3) & AMASK
	switch srcMode {
	case AFP, AMP, AIMM:
		inst.Src.Mode = srcMode
		inst.Src.Val, err = r.operand()
		if err != nil {
			return inst, fmt.Errorf("src operand: %w", err)
		}
	case AFP | AIND, AMP | AIND:
		inst.Src.Mode = srcMode
		inst.Src.Val, err = r.operand()
		if err != nil {
			return inst, fmt.Errorf("src ind first: %w", err)
		}
		inst.Src.Ind, err = r.operand()
		if err != nil {
			return inst, fmt.Errorf("src ind second: %w", err)
		}
	default:
		inst.Src = NoOperand
	}

	// Destination operand
	dstMode := add & AMASK
	switch dstMode {
	case AFP, AMP, AIMM:
		inst.Dst.Mode = dstMode
		inst.Dst.Val, err = r.operand()
		if err != nil {
			return inst, fmt.Errorf("dst operand: %w", err)
		}
	case AFP | AIND, AMP | AIND:
		inst.Dst.Mode = dstMode
		inst.Dst.Val, err = r.operand()
		if err != nil {
			return inst, fmt.Errorf("dst ind first: %w", err)
		}
		inst.Dst.Ind, err = r.operand()
		if err != nil {
			return inst, fmt.Errorf("dst ind second: %w", err)
		}
	default:
		inst.Dst = NoOperand
	}

	return inst, nil
}

func (r *reader) readTypeDesc() (TypeDesc, error) {
	id, err := r.operand()
	if err != nil {
		return TypeDesc{}, fmt.Errorf("id: %w", err)
	}
	size, err := r.operand()
	if err != nil {
		return TypeDesc{}, fmt.Errorf("size: %w", err)
	}
	nmap, err := r.operand()
	if err != nil {
		return TypeDesc{}, fmt.Errorf("nmap: %w", err)
	}
	mapBytes, err := r.readBytes(int(nmap))
	if err != nil {
		return TypeDesc{}, fmt.Errorf("map bytes: %w", err)
	}
	return TypeDesc{
		ID:   int(id),
		Size: int(size),
		Map:  mapBytes,
	}, nil
}

func (r *reader) readData() ([]DataItem, error) {
	var items []DataItem
	for {
		sm, err := r.readByte()
		if err != nil {
			return nil, err
		}
		if sm == 0 {
			break
		}

		kind := sm >> 4
		count := int32(sm & 0x0F)
		if count == 0 {
			count, err = r.operand()
			if err != nil {
				return nil, fmt.Errorf("data count: %w", err)
			}
		}

		offset, err := r.operand()
		if err != nil {
			return nil, fmt.Errorf("data offset: %w", err)
		}

		di := DataItem{Kind: kind, Offset: offset, Count: count}

		switch kind {
		case DEFB:
			di.Bytes, err = r.readBytes(int(count))
			if err != nil {
				return nil, fmt.Errorf("defb data: %w", err)
			}
		case DEFW:
			di.Words = make([]uint32, count)
			for i := int32(0); i < count; i++ {
				di.Words[i], err = r.readWord()
				if err != nil {
					return nil, fmt.Errorf("defw word %d: %w", i, err)
				}
			}
		case DEFL:
			di.Longs = make([]int64, count)
			for i := int32(0); i < count; i++ {
				hi, err := r.readWord()
				if err != nil {
					return nil, fmt.Errorf("defl hi %d: %w", i, err)
				}
				lo, err := r.readWord()
				if err != nil {
					return nil, fmt.Errorf("defl lo %d: %w", i, err)
				}
				di.Longs[i] = int64(hi)<<32 | int64(lo)
			}
		case DEFF:
			di.Reals = make([]float64, count)
			for i := int32(0); i < count; i++ {
				hi, err := r.readWord()
				if err != nil {
					return nil, fmt.Errorf("deff hi %d: %w", i, err)
				}
				lo, err := r.readWord()
				if err != nil {
					return nil, fmt.Errorf("deff lo %d: %w", i, err)
				}
				bits := uint64(hi)<<32 | uint64(lo)
				di.Reals[i] = math.Float64frombits(bits)
			}
		case DEFS:
			b, err := r.readBytes(int(count))
			if err != nil {
				return nil, fmt.Errorf("defs data: %w", err)
			}
			di.Str = string(b)
		case DEFA:
			typeID, err := r.readWord()
			if err != nil {
				return nil, fmt.Errorf("defa type: %w", err)
			}
			length, err := r.readWord()
			if err != nil {
				return nil, fmt.Errorf("defa length: %w", err)
			}
			di.ArrayTypeID = int32(typeID)
			di.ArrayLen = int32(length)
		case DIND:
			off, err := r.readWord()
			if err != nil {
				return nil, fmt.Errorf("dind offset: %w", err)
			}
			idx, err := r.readWord()
			if err != nil {
				return nil, fmt.Errorf("dind index: %w", err)
			}
			di.Offset = int32(off)
			di.ArrayIndex = int32(idx)
		case DAPOP:
			// No additional data
		default:
			return nil, fmt.Errorf("unknown data kind %d", kind)
		}

		items = append(items, di)
	}
	return items, nil
}

func (r *reader) readLink() (Link, error) {
	pc, err := r.operand()
	if err != nil {
		return Link{}, fmt.Errorf("pc: %w", err)
	}
	descID, err := r.operand()
	if err != nil {
		return Link{}, fmt.Errorf("desc: %w", err)
	}
	sig, err := r.readWord()
	if err != nil {
		return Link{}, fmt.Errorf("sig: %w", err)
	}
	name, err := r.readString()
	if err != nil {
		return Link{}, fmt.Errorf("name: %w", err)
	}
	return Link{
		PC:     pc,
		DescID: descID,
		Sig:    sig,
		Name:   name,
	}, nil
}

func (r *reader) readLDT() ([][]Import, error) {
	nl, err := r.operand()
	if err != nil {
		return nil, err
	}
	ldt := make([][]Import, nl)
	for i := int32(0); i < nl; i++ {
		n, err := r.operand()
		if err != nil {
			return nil, err
		}
		imports := make([]Import, n)
		for j := int32(0); j < n; j++ {
			sig, err := r.readWord()
			if err != nil {
				return nil, err
			}
			name, err := r.readString()
			if err != nil {
				return nil, err
			}
			imports[j] = Import{Sig: sig, Name: name}
		}
		ldt[i] = imports
	}
	// Read terminator
	_, err = r.operand()
	if err != nil {
		return nil, err
	}
	return ldt, nil
}

func (r *reader) readHandlers() ([]Handler, error) {
	nh, err := r.operand()
	if err != nil {
		return nil, err
	}
	handlers := make([]Handler, nh)
	for i := int32(0); i < nh; i++ {
		h := &handlers[i]
		h.EOffset, err = r.operand()
		if err != nil {
			return nil, err
		}
		h.PC1, err = r.operand()
		if err != nil {
			return nil, err
		}
		h.PC2, err = r.operand()
		if err != nil {
			return nil, err
		}
		h.DescID, err = r.operand()
		if err != nil {
			return nil, err
		}
		packed, err := r.operand()
		if err != nil {
			return nil, err
		}
		h.NE = packed >> 16
		nlab := packed & 0xFFFF
		h.NEtab = nlab
		h.Etab = make([]Except, nlab)
		for j := int32(0); j < nlab; j++ {
			name, err := r.readString()
			if err != nil {
				return nil, err
			}
			pc, err := r.operand()
			if err != nil {
				return nil, err
			}
			h.Etab[j] = Except{Name: name, PC: pc}
		}
		h.WildPC, err = r.operand()
		if err != nil {
			return nil, err
		}
	}
	// Read terminator
	_, err = r.operand()
	if err != nil {
		return nil, err
	}
	return handlers, nil
}
