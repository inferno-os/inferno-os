package main

import (
	"fmt"
	"os"

	"github.com/NERVsystems/infernode/tools/godis/dis"
)

func main() {
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "read: %v\n", err)
		os.Exit(1)
	}
	m, err := dis.Decode(data)
	if err != nil {
		fmt.Printf("decode error: %v\n", err)
		return
	}
	fmt.Printf("name: %q\n", m.Name)
	fmt.Printf("magic: %d\n", m.Magic)
	fmt.Printf("rt flags: 0x%x (HASLDT=%v, HASEXCEPT=%v)\n",
		m.RuntimeFlags, m.RuntimeFlags&dis.HASLDT != 0, m.RuntimeFlags&dis.HASEXCEPT != 0)
	fmt.Printf("instructions: %d\n", len(m.Instructions))
	for i, inst := range m.Instructions {
		fmt.Printf("  [%3d] %s\n", i, inst.String())
	}
	fmt.Printf("type descs: %d\n", len(m.TypeDescs))
	for i, td := range m.TypeDescs {
		fmt.Printf("  td[%d]: id=%d size=%d map=%v\n", i, td.ID, td.Size, td.Map)
	}
	fmt.Printf("data size: %d\n", m.DataSize)
	fmt.Printf("links: %d\n", len(m.Links))
	for i, l := range m.Links {
		fmt.Printf("  link[%d]: pc=%d desc=%d sig=0x%x name=%q\n", i, l.PC, l.DescID, l.Sig, l.Name)
	}
	fmt.Printf("LDT entries: %d\n", len(m.LDT))
	for i, ldt := range m.LDT {
		fmt.Printf("  LDT[%d]: %d imports\n", i, len(ldt))
		for j, imp := range ldt {
			fmt.Printf("    import[%d]: sig=0x%x name=%q\n", j, imp.Sig, imp.Name)
		}
	}
	fmt.Printf("data items: %d\n", len(m.Data))
	for i, d := range m.Data {
		switch d.Kind {
		case dis.DEFS:
			fmt.Printf("  data[%d]: DEFS offset=%d %q\n", i, d.Offset, d.Str)
		case dis.DEFW:
			fmt.Printf("  data[%d]: DEFW offset=%d words=%v\n", i, d.Offset, d.Words)
		default:
			fmt.Printf("  data[%d]: kind=%d offset=%d\n", i, d.Kind, d.Offset)
		}
	}
	fmt.Printf("handlers: %d\n", len(m.Handlers))
	for i, h := range m.Handlers {
		fmt.Printf("  handler[%d]: eoff=%d pc1=%d pc2=%d descID=%d ne=%d wildPC=%d nlab=%d\n",
			i, h.EOffset, h.PC1, h.PC2, h.DescID, h.NE, h.WildPC, len(h.Etab))
	}
	fmt.Printf("file size: %d bytes\n", len(data))
	re, _ := m.EncodeToBytes()
	fmt.Printf("re-encoded: %d bytes\n", len(re))
}
