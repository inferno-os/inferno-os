package compiler

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/NERVsystems/infernode/tools/godis/dis"
)

func TestCompileHelloWorld(t *testing.T) {
	src := []byte(`package main

func main() {
	println("hello, infernode")
}
`)
	c := New()
	m, err := c.CompileFile("hello.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Verify module structure
	if m.Name != "Hello" {
		t.Errorf("name = %q, want %q", m.Name, "Hello")
	}
	if m.Magic != dis.XMAGIC {
		t.Errorf("magic = %d, want %d", m.Magic, dis.XMAGIC)
	}
	if m.RuntimeFlags != dis.HASLDT {
		t.Errorf("flags = 0x%x, want 0x%x", m.RuntimeFlags, dis.HASLDT)
	}

	// Must have instructions
	if len(m.Instructions) < 5 {
		t.Errorf("instructions = %d, want >= 5", len(m.Instructions))
	}

	// First instruction must be LOAD (loading the Sys module)
	if m.Instructions[0].Op != dis.ILOAD {
		t.Errorf("inst[0].op = %s, want load", m.Instructions[0].Op)
	}

	// Last instruction must be RET
	last := m.Instructions[len(m.Instructions)-1]
	if last.Op != dis.IRET {
		t.Errorf("last inst = %s, want ret", last.Op)
	}

	// Must have at least 2 type descriptors (MP + init frame)
	if len(m.TypeDescs) < 2 {
		t.Errorf("type descs = %d, want >= 2", len(m.TypeDescs))
	}

	// Must have the init link with correct signature
	if len(m.Links) != 1 {
		t.Fatalf("links = %d, want 1", len(m.Links))
	}
	if m.Links[0].Name != "init" {
		t.Errorf("link name = %q, want %q", m.Links[0].Name, "init")
	}
	if m.Links[0].Sig != 0x4244b354 {
		t.Errorf("link sig = 0x%x, want 0x4244b354", m.Links[0].Sig)
	}

	// Must have LDT with print import
	if len(m.LDT) != 1 || len(m.LDT[0]) == 0 {
		t.Fatalf("LDT entries: got %v, want 1 entry with imports", len(m.LDT))
	}
	found := false
	for _, imp := range m.LDT[0] {
		if imp.Name == "print" {
			found = true
			if imp.Sig != 0xac849033 {
				t.Errorf("print sig = 0x%x, want 0xac849033", imp.Sig)
			}
		}
	}
	if !found {
		t.Error("LDT missing print import")
	}

	// Must have data section with the hello string
	foundStr := false
	for _, d := range m.Data {
		if d.Kind == dis.DEFS && d.Str == "hello, infernode" {
			foundStr = true
		}
	}
	if !foundStr {
		t.Error("data section missing 'hello, infernode' string")
	}

	// Must round-trip encode/decode
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	m2, err := dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	reencoded, err := m2.EncodeToBytes()
	if err != nil {
		t.Fatalf("re-encode: %v", err)
	}
	if len(encoded) != len(reencoded) {
		t.Errorf("round-trip size: %d -> %d", len(encoded), len(reencoded))
	}
	for i := range encoded {
		if encoded[i] != reencoded[i] {
			t.Errorf("round-trip mismatch at byte %d: 0x%02x != 0x%02x", i, encoded[i], reencoded[i])
			break
		}
	}

	t.Logf("compiled %d instructions, %d type descs, %d data items, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(m.Data), len(encoded))
}

func TestCompileArithmetic(t *testing.T) {
	src := []byte(`package main

func main() {
	x := 40
	y := 2
	println(x + y)
}
`)
	c := New()
	m, err := c.CompileFile("arith.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	if len(m.Instructions) < 5 {
		t.Errorf("too few instructions: %d", len(m.Instructions))
	}

	// Verify it encodes correctly
	_, err = m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}

	t.Logf("compiled %d instructions, %d type descs", len(m.Instructions), len(m.TypeDescs))
}

func TestCompileLocalFunctionCall(t *testing.T) {
	src := []byte(`package main

func add(a, b int) int {
	return a + b
}

func main() {
	result := add(40, 2)
	println(result)
}
`)
	c := New()
	m, err := c.CompileFile("funcall.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have type descriptors for MP + main frame + add frame + call-site TDs
	if len(m.TypeDescs) < 3 {
		t.Errorf("type descs = %d, want >= 3 (MP + main + add)", len(m.TypeDescs))
	}

	// Must have IFRAME and CALL instructions for the local call
	hasFrame := false
	hasCall := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.IFRAME {
			hasFrame = true
		}
		if inst.Op == dis.ICALL {
			hasCall = true
		}
	}
	if !hasFrame {
		t.Error("missing IFRAME instruction for local call")
	}
	if !hasCall {
		t.Error("missing CALL instruction for local call")
	}

	// The add function must have a RET that writes through REGRET
	// Look for movw ... 0(32(fp)) pattern (indirect write to REGRET)
	hasReturnWrite := false
	for _, inst := range m.Instructions {
		if (inst.Op == dis.IMOVW || inst.Op == dis.IMOVP) && inst.Dst.IsIndirect() {
			if inst.Dst.Val == 32 && inst.Dst.Ind == 0 {
				hasReturnWrite = true
			}
		}
	}
	if !hasReturnWrite {
		t.Error("add() missing return value write through REGRET (0(32(fp)))")
	}

	// Must round-trip
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	m2, err := dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	reencoded, err := m2.EncodeToBytes()
	if err != nil {
		t.Fatalf("re-encode: %v", err)
	}
	if len(encoded) != len(reencoded) {
		t.Errorf("round-trip size: %d -> %d", len(encoded), len(reencoded))
	}

	// Print instruction listing for debugging
	for i, inst := range m.Instructions {
		t.Logf("  [%3d] %s", i, inst.String())
	}
	for i, td := range m.TypeDescs {
		t.Logf("  td[%d]: id=%d size=%d map=%v", i, td.ID, td.Size, td.Map)
	}

	t.Logf("compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileVoidFunctionCall(t *testing.T) {
	src := []byte(`package main

func greet(name string) {
	println("hello", name)
}

func main() {
	greet("world")
}
`)
	c := New()
	m, err := c.CompileFile("greet.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must compile without errors and have instructions
	if len(m.Instructions) < 5 {
		t.Errorf("too few instructions: %d", len(m.Instructions))
	}

	// Must have CALL for calling greet
	hasCall := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.ICALL {
			hasCall = true
		}
	}
	if !hasCall {
		t.Error("missing CALL instruction for greet()")
	}

	// Must round-trip
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	t.Logf("compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompilePhiElimination(t *testing.T) {
	// This program has a phi node: x gets different values depending on the branch.
	// The phi elimination must insert MOVs in each predecessor block.
	src := []byte(`package main

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func main() {
	println(abs(-7))
	println(abs(3))
}
`)
	c := New()
	m, err := c.CompileFile("phi.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must compile and encode correctly
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	// Print instruction listing for debugging
	for i, inst := range m.Instructions {
		t.Logf("  [%3d] %s", i, inst.String())
	}

	t.Logf("compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileConditionalValue(t *testing.T) {
	// Tests proper phi elimination where a variable gets different values
	// from different control flow paths
	src := []byte(`package main

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func main() {
	println(max(10, 20))
}
`)
	c := New()
	m, err := c.CompileFile("max.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	t.Logf("compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileForLoop(t *testing.T) {
	src := []byte(`package main

func loop(n int) int {
	sum := 0
	i := 0
	for i < n {
		sum = sum + i
		i = i + 1
	}
	return sum
}

func main() {
	println(loop(5))
	println(loop(10))
}
`)
	c := New()
	m, err := c.CompileFile("loop.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	t.Logf("compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileStringOperations(t *testing.T) {
	src := []byte(`package main

func classify(s string) int {
	if s == "hello" {
		return 1
	}
	if s == "world" {
		return 2
	}
	return 0
}

func longer(a, b string) string {
	if len(a) > len(b) {
		return a
	}
	return b
}

func main() {
	println(classify("hello"))
	println(classify("world"))
	println(classify("other"))
	println(longer("hi", "hello"))
}
`)
	c := New()
	m, err := c.CompileFile("strings.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have BEQC for string comparison
	hasBeqc := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.IBEQC {
			hasBeqc = true
		}
	}
	if !hasBeqc {
		t.Error("missing BEQC instruction for string comparison")
	}

	// Must have LENC for len()
	hasLenc := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.ILENC {
			hasLenc = true
		}
	}
	if !hasLenc {
		t.Error("missing LENC instruction for string len()")
	}

	// Must round-trip
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	t.Logf("compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileStringConcatenation(t *testing.T) {
	src := []byte(`package main

func greet(first, last string) string {
	return first + " " + last
}

func main() {
	msg := greet("hello", "world")
	println(msg)
}
`)
	c := New()
	m, err := c.CompileFile("strcat.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have ADDC for string concatenation
	addcCount := 0
	for _, inst := range m.Instructions {
		if inst.Op == dis.IADDC {
			addcCount++
		}
	}
	if addcCount < 2 {
		t.Errorf("ADDC count = %d, want >= 2 (two concatenations)", addcCount)
	}

	// Must round-trip
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	t.Logf("compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileMultipleFunctionCalls(t *testing.T) {
	src := []byte(`package main

func double(x int) int {
	return x + x
}

func square(x int) int {
	return x * x
}

func main() {
	a := double(5)
	b := square(3)
	println(a + b)
}
`)
	c := New()
	m, err := c.CompileFile("multi.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have at least 4 type descriptors: MP + main + double + square
	if len(m.TypeDescs) < 4 {
		t.Errorf("type descs = %d, want >= 4", len(m.TypeDescs))
	}

	// Must have 2 CALL instructions (for double and square)
	callCount := 0
	for _, inst := range m.Instructions {
		if inst.Op == dis.ICALL {
			callCount++
		}
	}
	if callCount != 2 {
		t.Errorf("CALL count = %d, want 2", callCount)
	}

	// Must round-trip
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	t.Logf("compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileGlobalVariable(t *testing.T) {
	src := []byte(`package main

var counter int

func increment() {
	counter = counter + 1
}

func main() {
	increment()
	increment()
	increment()
	println(counter)
}
`)
	c := New()
	m, err := c.CompileFile("global.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have LEA instructions for loading global addresses from MP
	leaCount := 0
	for _, inst := range m.Instructions {
		if inst.Op == dis.ILEA {
			leaCount++
		}
	}
	if leaCount < 1 {
		t.Error("missing LEA instruction for global variable access")
	}

	// Global storage should be in module data (MP), increasing data size
	if m.DataSize < 24 {
		t.Errorf("data size = %d, want >= 24 (must include global storage)", m.DataSize)
	}

	// Must round-trip
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	t.Logf("compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileStructFieldAccess(t *testing.T) {
	src := []byte(`package main

type Point struct {
	X int
	Y int
}

func main() {
	var p Point
	p.X = 3
	p.Y = 4
	println(p.X + p.Y)
}
`)
	c := New()
	m, err := c.CompileFile("point.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have LEA for struct field addresses
	leaCount := 0
	for _, inst := range m.Instructions {
		if inst.Op == dis.ILEA {
			leaCount++
		}
	}
	if leaCount < 3 {
		t.Errorf("LEA count = %d, want >= 3 (alloc base + 2 field accesses minimum)", leaCount)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("struct: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileStructByValue(t *testing.T) {
	src := []byte(`package main

type Rect struct {
	X      int
	Y      int
	Width  int
	Height int
}

func area(r Rect) int {
	return r.Width * r.Height
}

func main() {
	var r Rect
	r.X = 10
	r.Y = 20
	r.Width = 30
	r.Height = 40
	println(area(r))
}
`)
	c := New()
	m, err := c.CompileFile("rect.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have CALL for area()
	hasCall := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.ICALL {
			hasCall = true
		}
	}
	if !hasCall {
		t.Error("missing CALL instruction for area()")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("struct-by-value: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileHeapAllocation(t *testing.T) {
	src := []byte(`package main

type Point struct {
	X int
	Y int
}

func newPoint(x, y int) *Point {
	return &Point{X: x, Y: y}
}

func main() {
	p := newPoint(3, 4)
	println(p.X + p.Y)
}
`)
	c := New()
	m, err := c.CompileFile("heap.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have INEW for heap allocation
	hasNew := false
	// Must have CALL for newPoint
	hasCall := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.INEW {
			hasNew = true
		}
		if inst.Op == dis.ICALL {
			hasCall = true
		}
	}
	if !hasNew {
		t.Error("missing NEW instruction for heap allocation")
	}
	if !hasCall {
		t.Error("missing CALL instruction for newPoint()")
	}

	// Must have a heap type descriptor (size 16 for Point{X int, Y int})
	foundHeapTD := false
	for _, td := range m.TypeDescs {
		if td.Size == 16 {
			foundHeapTD = true
		}
	}
	if !foundHeapTD {
		t.Error("missing 16-byte type descriptor for heap Point")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("heap-alloc: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileSliceOperations(t *testing.T) {
	src := []byte(`package main

func sum(nums []int) int {
	total := 0
	for i := 0; i < len(nums); i++ {
		total += nums[i]
	}
	return total
}

func main() {
	a := []int{10, 20, 30}
	println(sum(a))
	println(len(a))
}
`)
	c := New()
	m, err := c.CompileFile("slice.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have NEWA for array creation
	hasNewa := false
	// Must have INDW for slice indexing
	hasIndw := false
	// Must have LENA for len()
	hasLena := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.INEWA {
			hasNewa = true
		}
		if inst.Op == dis.IINDW {
			hasIndw = true
		}
		if inst.Op == dis.ILENA {
			hasLena = true
		}
	}
	if !hasNewa {
		t.Error("missing NEWA instruction for slice creation")
	}
	if !hasIndw {
		t.Error("missing INDW instruction for slice indexing")
	}
	if !hasLena {
		t.Error("missing LENA instruction for len()")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("slice: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileMultipleReturnValues(t *testing.T) {
	src := []byte(`package main

func divmod(a, b int) (int, int) {
	return a / b, a % b
}

func main() {
	q, r := divmod(17, 5)
	println(q)
	println(r)
}
`)
	c := New()
	m, err := c.CompileFile("multiret.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// divmod should write two values through REGRET
	// Check that we have DIVW and MODW in divmod
	hasDivw := false
	hasModw := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.IDIVW {
			hasDivw = true
		}
		if inst.Op == dis.IMODW {
			hasModw = true
		}
	}
	if !hasDivw {
		t.Error("missing DIVW instruction")
	}
	if !hasModw {
		t.Error("missing MODW instruction")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("multiret: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileMethodCalls(t *testing.T) {
	src := []byte(`package main

type Counter struct {
	value int
}

func (c *Counter) Inc() {
	c.value++
}

func (c *Counter) Get() int {
	return c.value
}

func main() {
	c := &Counter{value: 0}
	c.Inc()
	c.Inc()
	c.Inc()
	println(c.Get())
}
`)
	c := New()
	m, err := c.CompileFile("method.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have at least 4 type descriptors: MP + main + Get + Inc
	if len(m.TypeDescs) < 4 {
		t.Errorf("type descs = %d, want >= 4 (MP + main + Get + Inc)", len(m.TypeDescs))
	}

	// Must have 4 CALL instructions (3x Inc + 1x Get)
	callCount := 0
	for _, inst := range m.Instructions {
		if inst.Op == dis.ICALL {
			callCount++
		}
	}
	if callCount != 4 {
		t.Errorf("CALL count = %d, want 4 (3x Inc + 1x Get)", callCount)
	}

	// Must have INEW for heap-allocated Counter
	hasNew := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.INEW {
			hasNew = true
		}
	}
	if !hasNew {
		t.Error("missing NEW instruction for Counter allocation")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("method: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileSysModuleCalls(t *testing.T) {
	src := []byte(`package main

import "inferno/sys"

func main() {
	fd := sys.Fildes(1)
	sys.Fprint(fd, "hello\n")
	t1 := sys.Millisec()
	sys.Sleep(10)
	t2 := sys.Millisec()
	println(t2 - t1)
}
`)
	c := New()
	m, err := c.CompileFile("syscall.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have MFRAME + MCALL pairs for sys module calls
	mframeCount := 0
	mcallCount := 0
	iframeCount := 0
	for _, inst := range m.Instructions {
		if inst.Op == dis.IMFRAME {
			mframeCount++
		}
		if inst.Op == dis.IMCALL {
			mcallCount++
		}
		if inst.Op == dis.IFRAME {
			iframeCount++
		}
	}
	// fildes + sleep + millisec*2 = 4 MFRAME calls
	// fprint = 1 IFRAME call (varargs)
	if mframeCount < 4 {
		t.Errorf("MFRAME count = %d, want >= 4 (fildes + sleep + 2x millisec)", mframeCount)
	}
	if iframeCount < 1 {
		t.Errorf("IFRAME count = %d, want >= 1 (fprint is varargs)", iframeCount)
	}
	if mcallCount < 5 {
		t.Errorf("MCALL count = %d, want >= 5 (fildes + fprint + millisec + sleep + millisec)", mcallCount)
	}

	// LDT must have entries for fildes, fprint, sleep, millisec (plus print)
	if len(m.LDT) != 1 {
		t.Fatalf("LDT entries = %d, want 1", len(m.LDT))
	}
	foundNames := make(map[string]bool)
	for _, imp := range m.LDT[0] {
		foundNames[imp.Name] = true
	}
	for _, name := range []string{"print", "fildes", "fprint", "sleep", "millisec"} {
		if !foundNames[name] {
			t.Errorf("LDT missing %q import", name)
		}
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("syscall: compiled %d instructions, %d type descs, %d LDT imports, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(m.LDT[0]), len(encoded))
}

func TestCompileByteArrays(t *testing.T) {
	src := []byte(`package main

func main() {
	buf := []byte{72, 101, 108, 108, 111}
	sum := 0
	for i := 0; i < len(buf); i++ {
		sum = sum + int(buf[i])
	}
	println(sum)
}
`)
	c := New()
	m, err := c.CompileFile("bytes.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have INDB for byte indexing
	hasIndb := false
	// Must have CVTBW for byte→word conversion
	hasCvtbw := false
	// Must have CVTWB for word→byte store
	hasCvtwb := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.IINDB {
			hasIndb = true
		}
		if inst.Op == dis.ICVTBW {
			hasCvtbw = true
		}
		if inst.Op == dis.ICVTWB {
			hasCvtwb = true
		}
	}
	if !hasIndb {
		t.Error("missing INDB instruction for byte indexing")
	}
	if !hasCvtbw {
		t.Error("missing CVTBW instruction for byte→word conversion")
	}
	if !hasCvtwb {
		t.Error("missing CVTWB instruction for word→byte store")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("bytes: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileGoroutines(t *testing.T) {
	src := []byte(`package main

func worker(id int) {
	println(id)
}

func main() {
	go worker(1)
	go worker(2)
	println("done")
}
`)
	c := New()
	m, err := c.CompileFile("goroutine.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have SPAWN instructions
	spawnCount := 0
	for _, inst := range m.Instructions {
		if inst.Op == dis.ISPAWN {
			spawnCount++
		}
	}
	if spawnCount != 2 {
		t.Errorf("SPAWN count = %d, want 2", spawnCount)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("goroutine: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileChannels(t *testing.T) {
	src := []byte(`package main

func worker(ch chan int) {
	ch <- 42
}

func main() {
	ch := make(chan int)
	go worker(ch)
	v := <-ch
	println(v)
}
`)
	c := New()
	m, err := c.CompileFile("channel.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Verify NEWCW, SEND, RECV instructions are present
	var hasNewcw, hasSend, hasRecv bool
	for _, inst := range m.Instructions {
		switch inst.Op {
		case dis.INEWCW:
			hasNewcw = true
		case dis.ISEND:
			hasSend = true
		case dis.IRECV:
			hasRecv = true
		}
	}
	if !hasNewcw {
		t.Error("expected NEWCW instruction")
	}
	if !hasSend {
		t.Error("expected SEND instruction")
	}
	if !hasRecv {
		t.Error("expected RECV instruction")
	}

	// Verify encode/decode round-trip
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("channel: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileSelect(t *testing.T) {
	src := []byte(`package main

func sender1(ch chan int) { ch <- 10 }
func sender2(ch chan int) { ch <- 20 }

func main() {
	ch1 := make(chan int)
	ch2 := make(chan int)
	go sender1(ch1)
	go sender2(ch2)
	select {
	case v := <-ch1:
		println(v)
	case v := <-ch2:
		println(v)
	}
}
`)
	c := New()
	m, err := c.CompileFile("selectrecv.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Verify ALT instruction is present
	var hasAlt bool
	for _, inst := range m.Instructions {
		if inst.Op == dis.IALT {
			hasAlt = true
		}
	}
	if !hasAlt {
		t.Error("expected ALT instruction")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("select: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileAppend(t *testing.T) {
	src := []byte(`package main

func main() {
	s := make([]int, 0)
	s = append(s, 10)
	s = append(s, 20)
	s = append(s, 30)
	println(len(s))
	println(s[0])
	println(s[1])
	println(s[2])
}
`)
	c := New()
	m, err := c.CompileFile("append.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have SLICELA for slice concatenation
	slicelaCount := 0
	// Must have NEWA for new array allocation
	newaCount := 0
	// Must have LENA for getting slice lengths
	lenaCount := 0
	for _, inst := range m.Instructions {
		if inst.Op == dis.ISLICELA {
			slicelaCount++
		}
		if inst.Op == dis.INEWA {
			newaCount++
		}
		if inst.Op == dis.ILENA {
			lenaCount++
		}
	}
	// Each append(s, elem) creates a temp slice + concatenates = 2 SLICELA per append
	if slicelaCount < 6 {
		t.Errorf("SLICELA count = %d, want >= 6 (2 per append x 3 appends)", slicelaCount)
	}
	if newaCount < 3 {
		t.Errorf("NEWA count = %d, want >= 3 (one per append)", newaCount)
	}
	if lenaCount < 6 {
		t.Errorf("LENA count = %d, want >= 6 (2 per append for old+new lengths)", lenaCount)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("append: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileStringConversion(t *testing.T) {
	src := []byte(`package main

func main() {
	s := "hello"
	b := []byte(s)
	println(len(b))
	s2 := string(b)
	println(s2)
}
`)
	c := New()
	m, err := c.CompileFile("strconv.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have CVTCA for string→[]byte
	hasCvtca := false
	// Must have CVTAC for []byte→string
	hasCvtac := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.ICVTCA {
			hasCvtca = true
		}
		if inst.Op == dis.ICVTAC {
			hasCvtac = true
		}
	}
	if !hasCvtca {
		t.Error("missing CVTCA instruction for string→[]byte")
	}
	if !hasCvtac {
		t.Error("missing CVTAC instruction for []byte→string")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("strconv: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileClosure(t *testing.T) {
	src := []byte(`package main

func makeAdder(x int) func(int) int {
	return func(y int) int {
		return x + y
	}
}

func main() {
	add5 := makeAdder(5)
	println(add5(10))
	println(add5(20))
}
`)
	c := New()
	m, err := c.CompileFile("closure.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have NEW for closure struct allocation
	hasNew := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.INEW {
			hasNew = true
		}
	}
	if !hasNew {
		t.Error("missing NEW instruction for closure struct")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("closure: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileMap(t *testing.T) {
	src := []byte(`package main

func main() {
	m := make(map[string]int)
	m["hello"] = 10
	m["world"] = 20
	v1 := m["hello"]
	v2 := m["world"]
	println(v1, v2)
	m["hello"] = 30
	v3 := m["hello"]
	println(v3)
	v4, ok := m["missing"]
	println(v4, ok)
	delete(m, "hello")
	v5 := m["hello"]
	println(v5)
}
`)
	c := New()
	m, err := c.CompileFile("maps.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Count key map opcodes: NEW (map struct), NEWA (arrays), INDW (indexing),
	// BEQC (string key comparison), SLICELA (array copy)
	var newCount, newaCount, indwCount, beqcCount, slicelaCount int
	for _, inst := range m.Instructions {
		switch inst.Op {
		case dis.INEW:
			newCount++
		case dis.INEWA:
			newaCount++
		case dis.IINDW:
			indwCount++
		case dis.IBEQC:
			beqcCount++
		case dis.ISLICELA:
			slicelaCount++
		}
	}

	if newCount < 1 {
		t.Error("expected at least 1 NEW (map struct)")
	}
	if newaCount < 6 {
		t.Errorf("expected at least 6 NEWA (key+val arrays per insert), got %d", newaCount)
	}
	if beqcCount < 3 {
		t.Errorf("expected at least 3 BEQC (string key comparisons for updates+lookups), got %d", beqcCount)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("maps: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileSliceSubSlice(t *testing.T) {
	src := []byte(`package main

func main() {
	s := make([]int, 0)
	s = append(s, 10)
	s = append(s, 20)
	s = append(s, 30)
	s = append(s, 40)
	t := s[1:3]
	println(len(t))
	println(t[0])
	println(t[1])
	u := s[:2]
	println(len(u))
	v := s[2:]
	println(len(v))
}
`)
	c := New()
	m, err := c.CompileFile("subslice.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have SLICEA instructions for sub-slicing
	var sliceaCount int
	for _, inst := range m.Instructions {
		if inst.Op == dis.ISLICEA {
			sliceaCount++
		}
	}
	if sliceaCount < 3 {
		t.Errorf("expected >= 3 SLICEA instructions, got %d", sliceaCount)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("subslice: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileStringIndex(t *testing.T) {
	src := []byte(`package main

func main() {
	s := "hello"
	println(s[0])
	println(s[4])
	t := s[1:4]
	println(t)
	u := s[:3]
	println(u)
}
`)
	c := New()
	m, err := c.CompileFile("stridx.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have INDC instructions for string indexing
	var indcCount, slicecCount int
	for _, inst := range m.Instructions {
		if inst.Op == dis.IINDC {
			indcCount++
		}
		if inst.Op == dis.ISLICEC {
			slicecCount++
		}
	}
	if indcCount < 2 {
		t.Errorf("expected >= 2 INDC instructions, got %d", indcCount)
	}
	if slicecCount < 2 {
		t.Errorf("expected >= 2 SLICEC instructions, got %d", slicecCount)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("stridx: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileCopyCap(t *testing.T) {
	src := []byte(`package main

func main() {
	s := make([]int, 0)
	s = append(s, 1)
	s = append(s, 2)
	s = append(s, 3)
	println(cap(s))
	dst := make([]int, 5)
	n := copy(dst, s)
	println(n)
	println(dst[0])
}
`)
	c := New()
	m, err := c.CompileFile("copycap.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have LENA for cap and SLICEA for copy's sub-slicing
	var lenaCount, sliceaCount int
	for _, inst := range m.Instructions {
		if inst.Op == dis.ILENA {
			lenaCount++
		}
		if inst.Op == dis.ISLICEA {
			sliceaCount++
		}
	}
	if lenaCount < 2 {
		t.Errorf("expected >= 2 LENA instructions (cap + copy lens), got %d", lenaCount)
	}
	if sliceaCount < 1 {
		t.Errorf("expected >= 1 SLICEA instruction (copy sub-slice), got %d", sliceaCount)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("copycap: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileMapRange(t *testing.T) {
	src := []byte(`package main

func main() {
	m := make(map[int]int)
	m[1] = 10
	m[2] = 20
	sum := 0
	for _, v := range m {
		sum = sum + v
	}
	println(sum)
}
`)
	c := New()
	m, err := c.CompileFile("maprange.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have LENA (for loading count via map struct access) and branching
	var lenaCount int
	for _, inst := range m.Instructions {
		if inst.Op == dis.ILENA {
			lenaCount++
		}
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("maprange: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileStringRange(t *testing.T) {
	src := []byte(`package main

func main() {
	s := "hi"
	sum := 0
	for _, c := range s {
		sum = sum + int(c)
	}
	println(sum)
}
`)
	c := New()
	m, err := c.CompileFile("strrange.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have INDC for character access and LENC for length
	var indcCount, lencCount int
	for _, inst := range m.Instructions {
		if inst.Op == dis.IINDC {
			indcCount++
		}
		if inst.Op == dis.ILENC {
			lencCount++
		}
	}
	if indcCount < 1 {
		t.Errorf("expected >= 1 INDC instructions, got %d", indcCount)
	}
	if lencCount < 1 {
		t.Errorf("expected >= 1 LENC instructions, got %d", lencCount)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("strrange: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileDefer(t *testing.T) {
	src := []byte(`package main

func greet(s string) {
	println(s)
}

func main() {
	defer greet("third")
	defer greet("second")
	defer greet("first")
	println("hello")
}
`)
	c := New()
	m, err := c.CompileFile("defer.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// 4 CALL instructions: 3 deferred greet() + 1 regular greet (the one being deferred)
	// Actually: main has 3 deferred calls (emitted at RunDefers) and the block also prints.
	// The deferred calls use ICALL. Count them.
	var callCount int
	for _, inst := range m.Instructions {
		if inst.Op == dis.ICALL {
			callCount++
		}
	}
	if callCount < 3 {
		t.Errorf("expected at least 3 CALL instructions (deferred calls), got %d", callCount)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("defer: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileStrconv(t *testing.T) {
	src := []byte(`package main

import "strconv"

func main() {
	s := strconv.Itoa(42)
	println(s)
	n, _ := strconv.Atoi("123")
	println(n)
}
`)
	c := New()
	m, err := c.CompileFile("strconv.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have CVTWC (int→string) for Itoa
	var cvtwcCount int
	var cvtcwCount int
	for _, inst := range m.Instructions {
		if inst.Op == dis.ICVTWC {
			cvtwcCount++
		}
		if inst.Op == dis.ICVTCW {
			cvtcwCount++
		}
	}
	if cvtwcCount < 1 {
		t.Errorf("expected >= 1 CVTWC (Itoa), got %d", cvtwcCount)
	}
	if cvtcwCount < 1 {
		t.Errorf("expected >= 1 CVTCW (Atoi), got %d", cvtcwCount)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("strconv: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileRuneToString(t *testing.T) {
	src := []byte(`package main

func toChar(n int) string {
	return string(rune(n))
}

func main() {
	println(toChar(65))
	println(toChar(104))
}
`)
	c := New()
	m, err := c.CompileFile("rune2str.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have INSC instruction (rune→string conversion)
	// toChar is a single function compiled once, so only 1 INSC
	var inscCount int
	for _, inst := range m.Instructions {
		if inst.Op == dis.IINSC {
			inscCount++
		}
	}
	if inscCount < 1 {
		t.Errorf("expected >= 1 INSC (rune→string), got %d", inscCount)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("rune2str: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileTypeAssert(t *testing.T) {
	src := []byte(`package main

func asInt(x interface{}) int {
	return x.(int)
}

func tryString(x interface{}) (string, bool) {
	s, ok := x.(string)
	return s, ok
}

func main() {
	println(asInt(42))
	s, ok := tryString("hello")
	if ok {
		println(s)
	}
}
`)
	c := New()
	m, err := c.CompileFile("typeassert.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must compile and round-trip
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("typeassert: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileInterface(t *testing.T) {
	src := []byte(`package main

type Stringer interface {
	String() string
}

type MyInt struct {
	val int
}

func (m MyInt) String() string {
	return "myint"
}

func printIt(s Stringer) {
	println(s.String())
}

func main() {
	x := MyInt{val: 42}
	printIt(x)
}
`)
	c := New()
	m, err := c.CompileFile("iface.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must compile and round-trip
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("interface: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileMultiIface(t *testing.T) {
	src := []byte(`package main

type Shape interface {
	Area() int
}

type Rect struct{ w, h int }
type Circle struct{ r int }

func (r Rect) Area() int   { return r.w * r.h }
func (c Circle) Area() int { return c.r * c.r * 3 }

func printArea(s Shape) {
	println(s.Area())
}

func main() {
	printArea(Rect{3, 4})
	printArea(Circle{5})
}
`)
	c := New()
	m, err := c.CompileFile("multi_iface.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must compile and round-trip
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	// Check for BEQW instructions (dispatch chain)
	beqwCount := 0
	for _, inst := range m.Instructions {
		if inst.Op == dis.IBEQW {
			beqwCount++
		}
	}
	if beqwCount == 0 {
		t.Error("expected BEQW instructions for multi-impl dispatch, found none")
	}

	t.Logf("multi_iface: compiled %d instructions, %d type descs, %d bytes, %d BEQWs",
		len(m.Instructions), len(m.TypeDescs), len(encoded), beqwCount)
}

func TestCompileFmtSprintf(t *testing.T) {
	src := `package main

import "fmt"

func main() {
	x := 42
	s1 := fmt.Sprintf("%d", x)
	println(s1)

	name := "world"
	s2 := fmt.Sprintf("hello %s", name)
	println(s2)

	s3 := fmt.Sprintf("no verbs here")
	println(s3)

	age := 30
	s4 := fmt.Sprintf("%s is %d", name, age)
	println(s4)

	fmt.Println("hello", x)
}
`
	c := New()
	m, err := c.CompileFile("fmtsprintf.go", []byte(src))
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Check for CVTWC (int→string)
	hasCVTWC := false
	// Check for ADDC (string concat)
	hasADDC := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.ICVTWC {
			hasCVTWC = true
		}
		if inst.Op == dis.IADDC {
			hasADDC = true
		}
	}
	if !hasCVTWC {
		t.Error("expected CVTWC instruction for Sprintf with int verb")
	}
	if !hasADDC {
		t.Error("expected ADDC instruction for Sprintf with string concat")
	}

	// Must round-trip
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("fmtsprintf: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileErrorBasic(t *testing.T) {
	src := []byte(`package main

import "errors"

func divide(a, b int) (int, error) {
	if b == 0 {
		return 0, errors.New("division by zero")
	}
	return a / b, nil
}

func main() {
	result, err := divide(10, 2)
	if err != nil {
		println(err.Error())
	} else {
		println(result)
	}

	_, err2 := divide(5, 0)
	if err2 != nil {
		println(err2.Error())
	}
}
`)
	c := New()
	m, err := c.CompileFile("error_basic.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have BEQW (or BNEW) for nil interface check dispatching on tag
	hasBranch := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.IBEQW || inst.Op == dis.IBNEW {
			hasBranch = true
			break
		}
	}
	if !hasBranch {
		t.Error("expected BEQW or BNEW instruction for error nil check / dispatch")
	}

	// Must round-trip encode/decode
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	m2, err := dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	reencoded, err := m2.EncodeToBytes()
	if err != nil {
		t.Fatalf("re-encode: %v", err)
	}
	if len(encoded) != len(reencoded) {
		t.Errorf("round-trip size: %d -> %d", len(encoded), len(reencoded))
	}

	t.Logf("error_basic: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileTypeSwitch(t *testing.T) {
	src := []byte(`package main

func describe(x interface{}) {
	switch v := x.(type) {
	case int:
		println("int:", v)
	case string:
		println("string:", v)
	default:
		println("unknown")
	}
}

func main() {
	describe(42)
	describe("hello")
}
`)
	c := New()
	m, err := c.CompileFile("typeswitch.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must round-trip encode/decode
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	t.Logf("typeswitch: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileNilCheck(t *testing.T) {
	src := []byte(`package main

func check(x interface{}) {
	if x == nil {
		println("nil")
	} else {
		println("not nil")
	}
}

func main() {
	check(nil)
	check(42)
}
`)
	c := New()
	m, err := c.CompileFile("nil_check.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have BEQW for comparing interface tag with 0 (nil check)
	hasBeqw := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.IBEQW {
			hasBeqw = true
			break
		}
	}
	if !hasBeqw {
		t.Error("expected BEQW instruction for nil interface check")
	}

	// Must round-trip encode/decode
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}

	t.Logf("nil_check: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompilePanicRecover(t *testing.T) {
	src := []byte(`package main

func safeDivide(a, b int) int {
	defer func() {
		if r := recover(); r != nil {
			println("recovered")
		}
	}()
	return a / b
}

func main() {
	println(safeDivide(10, 2))
	println(safeDivide(10, 0))
}
`)
	c := New()
	m, err := c.CompileFile("panic_recover.go", src)
	if err != nil {
		t.Fatalf("compile errors: %v", err)
	}

	// Must have HASEXCEPT flag
	if m.RuntimeFlags&dis.HASEXCEPT == 0 {
		t.Error("expected HASEXCEPT flag for program with recover")
	}

	// Must have at least one handler
	if len(m.Handlers) == 0 {
		t.Fatal("expected at least one exception handler")
	}
	h := m.Handlers[0]
	if h.WildPC < 0 {
		t.Error("expected valid wildcard PC in handler")
	}
	if h.EOffset <= 0 {
		t.Error("expected positive eoff in handler")
	}

	// Must have a zero-divide check (BNEW + RAISE pattern)
	hasRaise := false
	for _, inst := range m.Instructions {
		if inst.Op == dis.IRAISE {
			hasRaise = true
			break
		}
	}
	if !hasRaise {
		t.Error("expected IRAISE instruction for zero-divide check")
	}

	// Must round-trip encode/decode
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	m2, err := dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}
	if len(m2.Handlers) != len(m.Handlers) {
		t.Errorf("handler count mismatch: got %d, want %d", len(m2.Handlers), len(m.Handlers))
	}

	t.Logf("panic_recover: compiled %d instructions, %d handlers, %d bytes",
		len(m.Instructions), len(m.Handlers), len(encoded))
}

func TestCompileStrconvErr(t *testing.T) {
	src := []byte(`package main

import "strconv"

func main() {
	n, err := strconv.Atoi("123")
	if err != nil {
		println("error!")
	} else {
		println(n)
		println("no error")
	}

	_, err2 := strconv.Atoi("abc")
	if err2 != nil {
		println("error!")
	} else {
		println("no error 2")
	}
}
`)
	c := New()
	m, err := c.CompileFile("strconv_err.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Nil error interface must use 2 MOVW $0 (tag=0, val=0), not MOVW $-1.
	// Count MOVW instructions with immediate 0 and -1.
	var movw0Count int
	var movwNeg1Count int
	for _, inst := range m.Instructions {
		if inst.Op == dis.IMOVW {
			if inst.Src.Mode == dis.AIMM && inst.Src.Val == 0 {
				movw0Count++
			}
			if inst.Src.Mode == dis.AIMM && inst.Src.Val == -1 {
				movwNeg1Count++
			}
		}
	}
	// Each Atoi produces 2 MOVW $0 for nil error (tag+val), so expect >= 4
	if movw0Count < 4 {
		t.Errorf("expected >= 4 MOVW $0 (nil error tags+vals), got %d", movw0Count)
	}
	// No MOVW $-1 should remain for nil error
	if movwNeg1Count > 0 {
		t.Errorf("unexpected MOVW $-1: got %d (nil error should use 0, not -1)", movwNeg1Count)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("strconv_err: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileFloatBasic(t *testing.T) {
	src := []byte(`package main

func main() {
	x := 3.0
	y := 2.0
	println(x + y)
	println(x * y)
	n := int(x)
	println(n)
	seven := 7
	f := float64(seven)
	println(f)
}
`)
	c := New()
	m, err := c.CompileFile("float_basic.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have ADDF for float addition
	hasAddf := false
	// Must have MULF for float multiplication
	hasMulf := false
	// Must have CVTFW for float→int
	hasCvtfw := false
	// Must have CVTWF for int→float
	hasCvtwf := false
	// Must have MOVF for float constants
	hasMovf := false
	for _, inst := range m.Instructions {
		switch inst.Op {
		case dis.IADDF:
			hasAddf = true
		case dis.IMULF:
			hasMulf = true
		case dis.ICVTFW:
			hasCvtfw = true
		case dis.ICVTWF:
			hasCvtwf = true
		case dis.IMOVF:
			hasMovf = true
		}
	}
	if !hasAddf {
		t.Error("missing ADDF instruction for float addition")
	}
	if !hasMulf {
		t.Error("missing MULF instruction for float multiplication")
	}
	if !hasCvtfw {
		t.Error("missing CVTFW instruction for float→int conversion")
	}
	if !hasCvtwf {
		t.Error("missing CVTWF instruction for int→float conversion")
	}
	if !hasMovf {
		t.Error("missing MOVF instruction for float constants")
	}

	// Must have DEFF in data section
	hasDeff := false
	for _, d := range m.Data {
		if d.Kind == dis.DEFF {
			hasDeff = true
		}
	}
	if !hasDeff {
		t.Error("data section missing DEFF (float constant)")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("float_basic: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileStringsPkg(t *testing.T) {
	src := []byte(`package main

import "strings"

func main() {
	s := "hello world"
	if strings.Contains(s, "world") {
		println("contains")
	}
	if strings.HasPrefix(s, "hello") {
		println("prefix")
	}
	if strings.HasSuffix(s, "world") {
		println("suffix")
	}
	idx := strings.Index(s, "world")
	println(idx)
}
`)
	c := New()
	m, err := c.CompileFile("strings_pkg.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have SLICEC for string slicing and BEQC for comparison
	hasSlicec := false
	hasBeqc := false
	hasLenc := false
	for _, inst := range m.Instructions {
		switch inst.Op {
		case dis.ISLICEC:
			hasSlicec = true
		case dis.IBEQC:
			hasBeqc = true
		case dis.ILENC:
			hasLenc = true
		}
	}
	if !hasSlicec {
		t.Error("missing SLICEC instruction")
	}
	if !hasBeqc {
		t.Error("missing BEQC instruction")
	}
	if !hasLenc {
		t.Error("missing LENC instruction")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("strings_pkg: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileMathPkg(t *testing.T) {
	src := []byte(`package main

import "math"

func main() {
	x := math.Abs(-5.0)
	println(x)
	y := math.Abs(3.0)
	println(y)
}
`)
	c := New()
	m, err := c.CompileFile("math_pkg.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have NEGF for abs implementation and BGEF for branch
	hasNegf := false
	hasBgef := false
	for _, inst := range m.Instructions {
		switch inst.Op {
		case dis.INEGF:
			hasNegf = true
		case dis.IBGEF:
			hasBgef = true
		}
	}
	if !hasNegf {
		t.Error("missing NEGF instruction for math.Abs")
	}
	if !hasBgef {
		t.Error("missing BGEF instruction for math.Abs")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("math_pkg: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileHexFmt(t *testing.T) {
	src := []byte(`package main

import "fmt"

func main() {
	s := fmt.Sprintf("%x", 255)
	println(s)
	s2 := fmt.Sprintf("%x", 0)
	println(s2)
}
`)
	c := New()
	m, err := c.CompileFile("hex_fmt.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have ANDW and SHRW for hex digit extraction, SLICEC for lookup table
	hasAndw := false
	hasShrw := false
	hasSlicec := false
	for _, inst := range m.Instructions {
		switch inst.Op {
		case dis.IANDW:
			hasAndw = true
		case dis.ISHRW:
			hasShrw = true
		case dis.ISLICEC:
			hasSlicec = true
		}
	}
	if !hasAndw {
		t.Error("missing ANDW instruction for hex digit extraction")
	}
	if !hasShrw {
		t.Error("missing SHRW instruction for hex shift")
	}
	if !hasSlicec {
		t.Error("missing SLICEC instruction for hex digit lookup")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("hex_fmt: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileInsertionSort(t *testing.T) {
	src := []byte(`package main

func insertionSort(a []int) {
	for i := 1; i < len(a); i++ {
		key := a[i]
		j := i - 1
		for j >= 0 && a[j] > key {
			a[j+1] = a[j]
			j = j - 1
		}
		a[j+1] = key
	}
}

func main() {
	a := []int{5, 3, 8, 1, 9, 2, 7, 4, 6}
	insertionSort(a)
	for i := 0; i < len(a); i++ {
		println(a[i])
	}
}
`)
	c := New()
	m, err := c.CompileFile("isort.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have INDW for array indexing and CALL for insertionSort
	hasIndw := false
	hasCall := false
	for _, inst := range m.Instructions {
		switch inst.Op {
		case dis.IINDW:
			hasIndw = true
		case dis.ICALL:
			hasCall = true
		}
	}
	if !hasIndw {
		t.Error("missing INDW for array indexing")
	}
	if !hasCall {
		t.Error("missing CALL for insertionSort")
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("isort: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

func TestCompileSprintfVerbs(t *testing.T) {
	src := []byte(`package main

import "fmt"

func main() {
	s := fmt.Sprintf("char: %c", 65)
	println(s)

	s2 := fmt.Sprintf("hex: %x", 255)
	println(s2)

	s3 := fmt.Sprintf("%c%c%c", 72, 105, 33)
	println(s3)
}
`)
	c := New()
	m, err := c.CompileFile("sprintf_verbs.go", src)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	// Must have INSC for %c verb (rune→string)
	var inscCount int
	for _, inst := range m.Instructions {
		if inst.Op == dis.IINSC {
			inscCount++
		}
	}
	// %c should produce INSC — 4+ total (1 in first Sprintf, 3 in third, plus hex uses INSC)
	if inscCount < 4 {
		t.Errorf("expected >= 4 INSC (%cc verb + hex), got %d", '%', inscCount)
	}

	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	_, err = dis.Decode(encoded)
	if err != nil {
		t.Fatalf("decode round-trip: %v", err)
	}

	t.Logf("sprintf_verbs: compiled %d instructions, %d type descs, %d bytes",
		len(m.Instructions), len(m.TypeDescs), len(encoded))
}

// findEmu locates the emu binary relative to the test directory.
// Returns empty string if not found.
func findEmu() string {
	// From tools/godis/compiler/, emu is at ../../../emu/Linux/o.emu
	candidates := []string{
		"../../../emu/Linux/o.emu",
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			abs, _ := filepath.Abs(c)
			return abs
		}
	}
	return ""
}

// findRoot locates the Inferno root directory (for emu -r).
func findRoot() string {
	// From tools/godis/compiler/, root is ../../../
	abs, err := filepath.Abs("../../..")
	if err != nil {
		return ""
	}
	return abs
}

// compileGo compiles a .go file from testdata and returns the path to the .dis file.
func compileGo(t *testing.T, goFile string) string {
	t.Helper()
	src, err := os.ReadFile(goFile)
	if err != nil {
		t.Fatalf("read %s: %v", goFile, err)
	}
	c := New()
	m, err := c.CompileFile(filepath.Base(goFile), src)
	if err != nil {
		t.Fatalf("compile %s: %v", goFile, err)
	}
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode %s: %v", goFile, err)
	}
	// Write .dis next to the .go file (in testdata/)
	disPath := strings.TrimSuffix(goFile, ".go") + ".dis"
	if err := os.WriteFile(disPath, encoded, 0644); err != nil {
		t.Fatalf("write %s: %v", disPath, err)
	}
	t.Cleanup(func() { os.Remove(disPath) })
	return disPath
}

// compileGoDir compiles all .go files in a directory (multi-file or multi-package)
// and returns the path to the .dis file.
func compileGoDir(t *testing.T, dir string) string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("readdir %s: %v", dir, err)
	}
	var filenames []string
	var sources [][]byte
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".go") {
			continue
		}
		filePath := filepath.Join(dir, entry.Name())
		src, err := os.ReadFile(filePath)
		if err != nil {
			t.Fatalf("read %s: %v", filePath, err)
		}
		filenames = append(filenames, entry.Name())
		sources = append(sources, src)
	}
	if len(filenames) == 0 {
		t.Fatalf("no .go files in %s", dir)
	}
	c := New()
	c.BaseDir = dir
	m, err := c.CompileFiles(filenames, sources)
	if err != nil {
		t.Fatalf("compile %s: %v", dir, err)
	}
	encoded, err := m.EncodeToBytes()
	if err != nil {
		t.Fatalf("encode %s: %v", dir, err)
	}
	disPath := filepath.Join(dir, "main.dis")
	if err := os.WriteFile(disPath, encoded, 0644); err != nil {
		t.Fatalf("write %s: %v", disPath, err)
	}
	t.Cleanup(func() { os.Remove(disPath) })
	return disPath
}

// runEmu executes a .dis file on the Inferno emulator and returns stdout.
func runEmu(t *testing.T, emuPath, rootDir, disPath string, timeout time.Duration) string {
	t.Helper()
	// Convert disPath to Inferno-absolute path (relative to root)
	rel, err := filepath.Rel(rootDir, disPath)
	if err != nil {
		t.Fatalf("rel path: %v", err)
	}
	infernoPath := "/" + filepath.ToSlash(rel)

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, emuPath, "-r"+rootDir, "-c0", infernoPath)
	cmd.Dir = rootDir
	out, err := cmd.Output()
	// emu doesn't exit cleanly — it hangs and gets killed by timeout.
	// That's expected. We only care about stdout collected before the kill.
	if ctx.Err() == context.DeadlineExceeded {
		// Expected: emu was killed after timeout. Output is valid.
		return string(out)
	}
	if err != nil {
		// If it exited on its own (unexpected), still return what we got
		return string(out)
	}
	return string(out)
}

func TestE2EPrograms(t *testing.T) {
	emuPath := findEmu()
	if emuPath == "" {
		t.Skip("emu binary not found")
	}
	rootDir := findRoot()
	if rootDir == "" {
		t.Skip("cannot find Inferno root")
	}

	// Expected outputs verified by running on emu manually.
	// Programs with non-deterministic output (goroutines, map iteration) are excluded.
	tests := []struct {
		file     string
		expected string
	}{
		{"hello.go", "hello, infernode\n"},
		{"ifelse.go", "1\n-1\n-1\n"},
		{"loop.go", "10\n45\n"},
		{"gcd.go", "6\n"},
		{"abs.go", "7\n3\n"},
		{"funcall.go", "42\n"},
		{"greet.go", "hello world\n"},
		{"max.go", "20\n"},
		{"multiret.go", "3\n2\n"},
		{"method.go", "3\n"},
		{"point.go", "7\n"},
		{"rect.go", "1200\n"},
		{"slice.go", "60\n3\n"},
		{"heap.go", "7\n"},
		{"global.go", "3\n"},
		{"multi.go", "19\n"},
		{"strcat.go", "hello world\n"},
		{"strings.go", "1\n2\n0\nhello\n"},
		{"switch.go", "10\n20\n30\n0\n"},
		{"comprehensive.go", "42\n7\n55\n6\ndone\n"},
		{"array.go", "60\n"},
		{"error_basic.go", "5\ndivision by zero\n"},
		{"iface.go", "rect\n12\n"},
		{"strconv.go", "42\n123\nA\n"},
		{"fmtsprintf.go", "42\nhello world\nno verbs here\nhi world!\nage: 30 years\nworld is 30\nfrom Println\ncount: 42\n"},
		{"multi_iface.go", "12\n75\n"},
		{"nil_check.go", "nil\nnot nil\n"},
		{"typeassert.go", "42\nhello\n"},
		{"typeswitch.go", "int: 42\nstring: hello\n"},
		{"closure.go", "15\n25\n"},
		{"defer.go", "hello\nfirst\nsecond\nthird\n"},
		{"dynarray.go", "30\n100\n"},
		{"append.go", "3\n10\n20\n30\n"},
		{"copy_cap.go", "3\n3\n1\n2\n3\n2\n1\n2\n"},
		{"panic_recover.go", "5\nrecovered\n0\n"},
		{"bytes.go", "500\n5\n"},
		{"string_ops.go", "104\n111\n119\nhello\nworld\nhello\n"},
		{"slice_subslice.go", "2\n20\n30\n2\n10\n20\n2\n30\n40\n"},
		{"maps.go", "10 20\n30\n0 false\n0\n"},
		{"range.go", "60\n"},
		{"strconv_err.go", "123\nno error\nno error 2\n"},
		{"sprintf_verbs.go", "char: A\nhex: ff\nHi!\n"},
		{"channel.go", "42\n"},
		{"channel2.go", "60\n"},
		{"chanchan.go", "ping\n"},
		{"goroutine.go", "1\n2\n3\n"},
		{"float_basic.go", "5\n6\n3\n7\n"},
		{"strings_pkg.go", "contains\nprefix\nsuffix\n6\n-1\n"},
		{"math_pkg.go", "5\n3\n"},
		{"hex_fmt.go", "ff\n0\n10\nval: ab\n"},
		{"isort.go", "1\n2\n3\n4\n5\n6\n7\n8\n9\n"},
		{"nil_ptr.go", "nil\nnot nil\n"},
		{"qsort.go", "1\n2\n3\n4\n5\n6\n7\n8\n9\n"},
		{"sieve.go", "2\n3\n5\n7\n11\n13\n17\n19\n23\n29\n31\n37\n41\n43\n47\n"},
		{"linkedlist.go", "5\n4\n3\n2\n1\n"},
		{"bst.go", "1\n3\n4\n5\n6\n7\n8\n"},
		{"pipeline.go", "285\n"},
		{"calc.go", "14\n7\n26\n"},
		{"strtransform.go", "hello\nHELLO\nworld\nababab\nxxbxx\none, two, three\n"},
		{"wordcount.go", "the 3\nfox 1\nand 2\ndog 1\ncat 1\n"},
		{"math_sqrt.go", "2\n3\n3\n7\n"},
		{"goroutine_anon.go", "42\n"},
		{"buffered_chan.go", "10\n20\n30\n"},
		{"chan_close.go", "6\n"},
		{"chan_close_send_panic.go", "caught\n"},
		{"embed.go", "3\n4\n10\n"},
		{"slice_range.go", "63\n"},
		{"bool_slice.go", "5\nset\n"},
		{"named_return.go", "3\nok\n0\nzero\n"},
		{"multi_assign.go", "2\n1\n60\n"},
		{"const_iota.go", "0\n1\n2\n3\n"},
		{"chan_direction.go", "42\n"},
		{"method_value.go", "15\n17\n"},  // method values (statically resolved closures)
		{"waitgroup.go", "60\n"},
		{"cap_chan.go", "5\n0\n"},
		{"init_func.go", "42\n"},
		{"chan_range.go", "60\n"},
		{"func_param.go", "15\n17\n"},
		{"higher_order.go", "12\n18\n"},
		{"nested_struct.go", "12\n"},
		{"struct_slice.go", "21\n"},
		{"subword.go", "44\n-106\n255\n-42\n4464\n"},
		{"defer_builtin.go", "10\n20\n30\n-1\n"},
		{"select_mixed.go", "10\n30\n"},
		{"close_unblock.go", "0\n"},

		// Tier 1+2 fixes
		{"unsigned_cmp.go", "a<b\nb>a\na<=a\na>=a\na!=b\n"},
		{"field_extract.go", "10\n20\n30\n"},
		{"printf.go", "hello world\nnum=42\n3+4=7\n"},
		{"sys_create.go", "5\n0\n"},
		{"panic_int.go", "recovered\n"},
		{"defer_args.go", "20\n10\n"},

		// Tier 3 fixes
		{"minmax.go", "3\n10\n3\n10\n5\n-1\n1\n"},
		{"clear_builtin.go", "3\n0\n0\n0\n0\n3\n"},
		{"time_basic.go", "ok\n"},
		{"str_range.go", "2\n0\n1\n2\n"},
		{"map_commaok.go", "10\ntrue\n0\nfalse\n"},

		// Tier 4 fixes
		{"fmt_verbs.go", "true\nfalse\n\"hello\"\n1010\n10\n00042\n"},
		{"fmt_pad.go", "   42\n00042\n"},
		{"formatint.go", "ff\n1010\n10\n0\n"},
		{"sort_ints.go", "1\n2\n3\n4\n5\ntrue\n"},
		{"rune_conv.go", "5\nHello\n"},
		{"defer_close.go", "42\n"},
		{"time_sub.go", "ok\n"},
		{"sync_mutex.go", "30\n"},
		// Tier 5: real-world readiness
		{"seldef.go", "42\nempty\n"},
		{"append1.go", "4\n4\n"},
		{"nilslice.go", "0\n1\n1\n"},
		{"variadic_user.go", "6\n30\n"},
		{"strslice.go", "hello\nworld\n3\n"},
		{"switchstr.go", "vowel\nconsonant\n"},
		{"goclosure.go", "30\n"},
		{"nested_fn.go", "8\n"},
		{"select_default.go", "42\ndefault2\nsent\nfull2\n"},
		{"nil_map.go", "0\n"},
		{"multi_append.go", "5\n0\n10\n20\n30\n40\n"},
		{"str_build.go", "10\nababababab\n"},
		{"map_count.go", "2\n"},
		{"ptr_method.go", "3\n"},
		{"sprintf_multi.go", "Alice is 30 years old\n"},
		{"for_control.go", "18\n"},
		{"fizzbuzz.go", "1\n2\nFizz\n4\nBuzz\nFizz\n7\n8\nFizz\nBuzz\n11\nFizz\n13\n14\nFizzBuzz\n"},
		{"fibonacci.go", "0\n1\n1\n2\n3\n5\n8\n13\n21\n34\n"},
		{"stack.go", "3\n30\n20\n1\n"},
		{"closure_counter.go", "1\n2\n3\n"},
		{"reverse.go", "5\n4\n3\n2\n1\n"},
		{"producer_consumer.go", "30\n"},
		{"err_handle.go", "5\ndivision by zero\n123\n"},
		{"iface_sort.go", "Alice\nBoston\n"},
		{"map_string.go", "3\n2\n1\n"},
		{"swap.go", "2\n1\n30\n10\n"},
		{"string_index.go", "true\ntrue\n6\nABC\nHELLO WORLD\n"},

		// Tier 6: named types, embedding, type switches, closures
		{"tier6_1.go", "212\n"},
		{"tier6_2.go", "Hi Alice\nAlice\n30\n"},
		{"tier6_3.go", "hello\n"},
		{"tier6_4.go", "dog says woof\nnot a dog, says meow\n"},
		{"tier6_5.go", "21\n"},
		{"tier6_6.go", "hello world\n"},
		{"tier6_7.go", "15\n"},
		{"tier6_8.go", "42\n0\n"},
		// tier6_9.go: uses WaitGroup + goroutine close pattern, hangs due to concurrency limitation
		{"tier6_10.go", "15\n"},
		{"tier6_11.go", "int\nstring\n"},
		{"tier6_12.go", "Alice\nNYC\n10001\n"},
		{"tier6_13.go", "a\nb\nc\n"},
		{"tier6_14.go", "3\n\n0\ndiv by zero\n"},
		{"tier6_15.go", "0 apple\n1 banana\n2 cherry\n"},
		{"tier6_16.go", "15\n255\n240\n4080\n15\n"},
		{"tier6_17.go", "deferred: 2\n2\n"},
		{"tier6_18.go", "42\n"},

		// Additional coverage: string range, map range, sys module
		{"strrange.go", "532\n"},
		{"map_range.go", "6\n330\n"},
		{"sysprint.go", "hello from fprint\n"},
		{"syswrite.go", "Hello\n"},
		{"sysio.go", "writing to stdout\nwriting to stderr\n"},
		{"systime.go", "sleep ok\n"},
		// selectrecv.go: non-deterministic goroutine ordering

		// Language completeness: &^, goto, labeled break/continue, fallthrough, type aliases, struct embedding, channel commaOk
		{"bitclear.go", "240\n4\n"},
		{"goto_basic.go", "5\n"},
		{"labeled_brk.go", "6\n10\n"},
		{"fallthru.go", "-1\n30\n20\n99\n"},
		{"type_alias_basic.go", "30\n"},
		{"struct_embed_basic.go", "10\n20\n"},
		{"chan_recv_commaok.go", "42\ntrue\n0\nfalse\n"},
		{"three_idx_slice.go", "2\n2\n3\n"},
	}

	for _, tt := range tests {
		t.Run(tt.file, func(t *testing.T) {
			goPath, err := filepath.Abs(filepath.Join("..", "testdata", tt.file))
			if err != nil {
				t.Fatal(err)
			}
			if _, err := os.Stat(goPath); err != nil {
				t.Skipf("testdata file not found: %s", goPath)
			}
			disPath := compileGo(t, goPath)
			output := runEmu(t, emuPath, rootDir, disPath, 5*time.Second)
			if output != tt.expected {
				t.Errorf("output mismatch:\n  got:  %q\n  want: %q", output, tt.expected)
			}
		})
	}
}

func TestE2EMultiPackage(t *testing.T) {
	emuPath := findEmu()
	if emuPath == "" {
		t.Skip("emu binary not found")
	}
	rootDir := findRoot()
	if rootDir == "" {
		t.Skip("cannot find Inferno root")
	}

	tests := []struct {
		dir      string
		expected string
	}{
		{"multifile", "42\n"},
		{"multipkg", "7\n"},
		{"chain", "11\n"},
		{"sharedtype", "7\n"},
	}

	for _, tt := range tests {
		t.Run(tt.dir, func(t *testing.T) {
			dir, err := filepath.Abs(filepath.Join("..", "testdata", tt.dir))
			if err != nil {
				t.Fatal(err)
			}
			if _, err := os.Stat(dir); err != nil {
				t.Skipf("testdata dir not found: %s", dir)
			}
			disPath := compileGoDir(t, dir)
			output := runEmu(t, emuPath, rootDir, disPath, 5*time.Second)
			if output != tt.expected {
				t.Errorf("output mismatch:\n  got:  %q\n  want: %q", output, tt.expected)
			}
		})
	}
}
