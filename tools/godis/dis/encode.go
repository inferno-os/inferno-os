package dis

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"math"
)

// Encode writes the module to w in Dis binary format.
// The format matches libinterp/load.c parsemod() exactly.
func (m *Module) Encode(w io.Writer) error {
	var buf bytes.Buffer

	// Header: 9 operand-encoded values
	encodeOperand(&buf, m.Magic)
	encodeOperand(&buf, m.RuntimeFlags)
	encodeOperand(&buf, m.StackSize)
	encodeOperand(&buf, int32(len(m.Instructions)))
	encodeOperand(&buf, m.DataSize)
	encodeOperand(&buf, int32(len(m.TypeDescs)))
	encodeOperand(&buf, int32(len(m.Links)))
	encodeOperand(&buf, m.EntryPC)
	encodeOperand(&buf, m.EntryType)

	// Instructions
	for _, inst := range m.Instructions {
		encodeInst(&buf, inst)
	}

	// Type descriptors
	for _, td := range m.TypeDescs {
		encodeTypeDesc(&buf, td)
	}

	// Data section
	for _, di := range m.Data {
		encodeDataItem(&buf, di)
	}
	buf.WriteByte(0) // terminator

	// Module name (null-terminated)
	buf.WriteString(m.Name)
	buf.WriteByte(0)

	// Links
	for _, l := range m.Links {
		encodeOperand(&buf, l.PC)
		encodeOperand(&buf, l.DescID)
		encodeWord(&buf, l.Sig)
		buf.WriteString(l.Name)
		buf.WriteByte(0)
	}

	// LDT section (if HASLDT flag set)
	if m.RuntimeFlags&HASLDT != 0 {
		encodeOperand(&buf, int32(len(m.LDT)))
		for _, imports := range m.LDT {
			encodeOperand(&buf, int32(len(imports)))
			for _, imp := range imports {
				encodeWord(&buf, imp.Sig)
				buf.WriteString(imp.Name)
				buf.WriteByte(0)
			}
		}
		encodeOperand(&buf, 0) // terminator
	}

	// Exception handlers (if HASEXCEPT flag set)
	if m.RuntimeFlags&HASEXCEPT != 0 {
		encodeOperand(&buf, int32(len(m.Handlers)))
		for _, h := range m.Handlers {
			encodeOperand(&buf, h.EOffset)
			encodeOperand(&buf, h.PC1)
			encodeOperand(&buf, h.PC2)
			encodeOperand(&buf, h.DescID)
			packed := int32(len(h.Etab)) | (h.NE << 16)
			encodeOperand(&buf, packed)
			for _, e := range h.Etab {
				buf.WriteString(e.Name)
				buf.WriteByte(0)
				encodeOperand(&buf, e.PC)
			}
			encodeOperand(&buf, h.WildPC)
		}
		encodeOperand(&buf, 0) // terminator
	}

	// Source path (trailing metadata)
	if m.SrcPath != "" {
		buf.WriteString(m.SrcPath)
		buf.WriteByte(0)
	}

	_, err := w.Write(buf.Bytes())
	return err
}

// encodeOperand writes a variable-length encoded signed integer.
// Matches limbo/dis.c discon() and disbcon().
//
//	[-64, 63]         → 1 byte  (bits 7-6 = 00 or 01)
//	[-8192, 8191]     → 2 bytes (bits 7-6 = 10)
//	[-2^29, 2^29 - 1] → 4 bytes (bits 7-6 = 11)
func encodeOperand(buf *bytes.Buffer, val int32) {
	if val >= -64 && val <= 63 {
		buf.WriteByte(byte(val) &^ 0x80)
		return
	}
	if val >= -8192 && val <= 8191 {
		buf.WriteByte(byte(val>>8)&^0xC0 | 0x80)
		buf.WriteByte(byte(val))
		return
	}
	buf.WriteByte(byte(val>>24) | 0xC0)
	buf.WriteByte(byte(val >> 16))
	buf.WriteByte(byte(val >> 8))
	buf.WriteByte(byte(val))
}

// encodeWord writes a 4-byte big-endian unsigned value.
// Used for signatures in links and LDT entries.
func encodeWord(buf *bytes.Buffer, val uint32) {
	buf.WriteByte(byte(val >> 24))
	buf.WriteByte(byte(val >> 16))
	buf.WriteByte(byte(val >> 8))
	buf.WriteByte(byte(val))
}

// encodeInst writes a single instruction in binary format.
// Format: op_byte, add_byte, [mid_operand], [src_operand], [dst_operand]
func encodeInst(buf *bytes.Buffer, inst Inst) {
	buf.WriteByte(byte(inst.Op))
	buf.WriteByte(inst.AddressByte())

	// Middle operand
	if inst.Mid.MidMode() != AXNON {
		encodeOperand(buf, inst.Mid.Val)
	}

	// Source operand
	srcMode := inst.Src.SrcDstMode()
	switch srcMode {
	case AFP, AMP, AIMM:
		encodeOperand(buf, inst.Src.Val)
	case AFP | AIND, AMP | AIND:
		encodeOperand(buf, inst.Src.Val)
		encodeOperand(buf, inst.Src.Ind)
	}

	// Destination operand
	dstMode := inst.Dst.SrcDstMode()
	switch dstMode {
	case AFP, AMP, AIMM:
		encodeOperand(buf, inst.Dst.Val)
	case AFP | AIND, AMP | AIND:
		encodeOperand(buf, inst.Dst.Val)
		encodeOperand(buf, inst.Dst.Ind)
	}
}

// encodeTypeDesc writes a type descriptor.
// Format: operand(id), operand(size), operand(nmap), raw_bytes(map)
func encodeTypeDesc(buf *bytes.Buffer, td TypeDesc) {
	encodeOperand(buf, int32(td.ID))
	encodeOperand(buf, int32(td.Size))
	encodeOperand(buf, int32(len(td.Map)))
	buf.Write(td.Map)
}

// encodeDataItem writes a single data initialization item.
func encodeDataItem(buf *bytes.Buffer, di DataItem) {
	count := di.Count
	if count > 0 && count < DMAX {
		buf.WriteByte(di.Kind<<4 | byte(count))
	} else {
		buf.WriteByte(di.Kind << 4)
		encodeOperand(buf, count)
	}
	encodeOperand(buf, di.Offset)

	switch di.Kind {
	case DEFB:
		buf.Write(di.Bytes)
	case DEFW:
		for _, w := range di.Words {
			encodeWord(buf, w)
		}
	case DEFL:
		for _, l := range di.Longs {
			u := uint64(l)
			encodeWord(buf, uint32(u>>32))
			encodeWord(buf, uint32(u))
		}
	case DEFF:
		for _, r := range di.Reals {
			bits := math.Float64bits(r)
			encodeWord(buf, uint32(bits>>32))
			encodeWord(buf, uint32(bits))
		}
	case DEFS:
		buf.WriteString(di.Str)
	case DEFA:
		encodeWord(buf, uint32(di.ArrayTypeID))
		encodeWord(buf, uint32(di.ArrayLen))
	case DIND:
		encodeWord(buf, uint32(di.Offset))
		encodeWord(buf, uint32(di.ArrayIndex))
	case DAPOP:
		// No additional data
	}
}

// EncodeToBytes is a convenience that encodes the module to a byte slice.
func (m *Module) EncodeToBytes() ([]byte, error) {
	var buf bytes.Buffer
	if err := m.Encode(&buf); err != nil {
		return nil, fmt.Errorf("encode: %w", err)
	}
	return buf.Bytes(), nil
}

// canonicalDouble converts a float64 to the Dis canonical byte order.
// Dis always stores doubles in big-endian IEEE754 format regardless of
// the host byte order.
func canonicalDouble(f float64) [8]byte {
	bits := math.Float64bits(f)
	var b [8]byte
	binary.BigEndian.PutUint64(b[:], bits)
	return b
}
