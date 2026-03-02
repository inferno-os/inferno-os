implement JitTest;

include "sys.m";
	sys: Sys;
include "draw.m";

JitTest: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

passed := 0;
failed := 0;
total := 0;

check(name: string, got, expected: int)
{
	total++;
	if (got == expected) {
		passed++;
	} else {
		failed++;
		sys->print("FAIL: %s: got %d, expected %d\n", name, got, expected);
	}
}

checkbig(name: string, got, expected: big)
{
	total++;
	if (got == expected) {
		passed++;
	} else {
		failed++;
		sys->print("FAIL: %s: got %bd, expected %bd\n", name, got, expected);
	}
}

checkbyte(name: string, got, expected: byte)
{
	total++;
	if (int got == int expected) {
		passed++;
	} else {
		failed++;
		sys->print("FAIL: %s: got %d, expected %d\n", name, int got, int expected);
	}
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	sys->print("=== JIT Correctness Test Suite (Cross-Architecture) ===\n\n");

	test_word_arithmetic();
	test_word_bitwise();
	test_word_shifts();
	test_word_muldivmod();
	test_word_comparisons();
	test_byte_arithmetic();
	test_byte_comparisons();
	test_big_arithmetic();
	test_big_bitwise();
	test_big_shifts();
	test_big_comparisons();
	test_array_indexing();
	test_string_indexing();
	test_list_operations();
	test_function_calls();
	test_recursion();
	test_type_conversions();
	test_control_flow();
	test_move_operations();
	test_edge_cases();

	sys->print("\n=== Results: %d/%d passed", passed, total);
	if (failed > 0)
		sys->print(", %d FAILED", failed);
	sys->print(" ===\n");

	if (failed > 0) {
		sys->print("FAIL\n");
		raise "fail:tests failed";
	} else
		sys->print("PASS\n");
}

#
# Test 1: Word (int) arithmetic - JIT native ops: IADDW, ISUBW
#
test_word_arithmetic()
{
	sys->print("--- Word Arithmetic ---\n");

	# Basic add
	a := 100;
	b := 200;
	check("add basic", a + b, 300);

	# Add with negative
	check("add neg", a + (-50), 50);

	# Subtract
	check("sub basic", b - a, 100);
	check("sub neg result", a - b, -100);

	# Chain of operations
	c := a + b - 50;
	check("chain add-sub", c, 250);

	# Immediate operands
	x := 42;
	x = x + 8;
	check("add imm", x, 50);
	x = x - 25;
	check("sub imm", x, 25);

	# Zero operations
	check("add zero", a + 0, 100);
	check("sub zero", a - 0, 100);

	# Limbo int is 64-bit WORD on 64-bit platforms
	big_val := 16r7FFFFFFF;
	check("max 32", big_val, 2147483647);
	ov := big_val + 1;
	check("32bit+1 gt 0", ov > 0, 1);  # No overflow in 64-bit WORD

	sys->print("  word arithmetic: done\n");
}

#
# Test 2: Word bitwise - JIT native: IORW, IANDW, IXORW
#
test_word_bitwise()
{
	sys->print("--- Word Bitwise ---\n");

	a := 16rFF00;
	b := 16r0FF0;

	check("or", a | b, 16rFFF0);
	check("and", a & b, 16r0F00);
	check("xor", a ^ b, 16rF0F0);

	# XOR identity
	check("xor self", a ^ a, 0);

	# OR identity
	check("or zero", a | 0, a);

	# AND mask
	mask_val := int 16rDEADBEEF;
	check("and mask", mask_val & 16rFFFF, 16rBEEF);

	# All ones
	check("or all", -1 | 0, -1);
	check("and all", -1 & 16rFF, 16rFF);

	sys->print("  word bitwise: done\n");
}

#
# Test 3: Word shifts - JIT native: ISHLW, ISHRW
#
test_word_shifts()
{
	sys->print("--- Word Shifts ---\n");

	check("shl 1", 1 << 0, 1);
	check("shl 2", 1 << 1, 2);
	check("shl 4", 1 << 2, 4);
	check("shl 256", 1 << 8, 256);

	check("shr 1", 256 >> 8, 1);
	check("shr 2", 16 >> 1, 8);

	# Shift by variable amount
	n := 4;
	check("shl var", 1 << n, 16);
	check("shr var", 256 >> n, 16);

	# Arithmetic right shift (sign extension)
	check("shr neg", -16 >> 2, -4);

	sys->print("  word shifts: done\n");
}

#
# Test 4: Word mul/div/mod - JIT native: IMULW, IDIVW, IMODW
#
test_word_muldivmod()
{
	sys->print("--- Word Mul/Div/Mod ---\n");

	check("mul basic", 7 * 6, 42);
	check("mul neg", 7 * (-6), -42);
	check("mul neg neg", (-7) * (-6), 42);
	check("mul zero", 42 * 0, 0);
	check("mul one", 42 * 1, 42);

	check("div basic", 42 / 6, 7);
	check("div neg", -42 / 6, -7);
	check("div truncate", 7 / 2, 3);

	check("mod basic", 42 % 10, 2);
	check("mod neg", -42 % 10, -2);
	check("mod exact", 42 % 7, 0);

	# Large multiplication
	check("mul large", 10000 * 10000, 100000000);

	sys->print("  word mul/div/mod: done\n");
}

#
# Test 5: Word comparisons - JIT native: IBEQW, IBNEW, IBLTW, IBGTW, IBLEW, IBGEW
#
test_word_comparisons()
{
	sys->print("--- Word Comparisons ---\n");

	a := 10;
	b := 20;
	c := 10;

	# EQ
	r := 0;
	if (a == c) r = 1;
	check("eq true", r, 1);
	r = 0;
	if (a == b) r = 1;
	check("eq false", r, 0);

	# NE
	r = 0;
	if (a != b) r = 1;
	check("ne true", r, 1);
	r = 0;
	if (a != c) r = 1;
	check("ne false", r, 0);

	# LT
	r = 0;
	if (a < b) r = 1;
	check("lt true", r, 1);
	r = 0;
	if (b < a) r = 1;
	check("lt false", r, 0);

	# GT
	r = 0;
	if (b > a) r = 1;
	check("gt true", r, 1);

	# LE
	r = 0;
	if (a <= c) r = 1;
	check("le eq", r, 1);
	r = 0;
	if (a <= b) r = 1;
	check("le lt", r, 1);

	# GE
	r = 0;
	if (a >= c) r = 1;
	check("ge eq", r, 1);
	r = 0;
	if (b >= a) r = 1;
	check("ge gt", r, 1);

	# Negative comparisons
	r = 0;
	if (-5 < 5) r = 1;
	check("neg lt pos", r, 1);
	r = 0;
	if (5 > -5) r = 1;
	check("pos gt neg", r, 1);

	sys->print("  word comparisons: done\n");
}

#
# Test 6: Byte arithmetic - JIT native: IADDB, ISUBB, IORB, IANDB, IXORB
#
test_byte_arithmetic()
{
	sys->print("--- Byte Arithmetic ---\n");

	a := byte 100;
	b := byte 50;

	checkbyte("add", a + b, byte 150);
	checkbyte("sub", a - b, byte 50);
	checkbyte("or", byte 16rF0 | byte 16r0F, byte 16rFF);
	checkbyte("and", byte 16rFF & byte 16r0F, byte 16r0F);
	checkbyte("xor", byte 16rFF ^ byte 16rF0, byte 16r0F);

	# Byte wrap
	checkbyte("wrap add", byte 200 + byte 100, byte 44);  # 300 & 0xFF = 44
	checkbyte("wrap sub", byte 10 - byte 20, byte 246);   # underflow wraps

	sys->print("  byte arithmetic: done\n");
}

#
# Test 7: Byte comparisons - JIT native: IBEQB, IBNEB, IBLTB, IBGTB, IBLEB, IBGEB
#
test_byte_comparisons()
{
	sys->print("--- Byte Comparisons ---\n");

	a := byte 10;
	b := byte 20;
	c := byte 10;

	r := 0;
	if (a == c) r = 1;
	check("beq true", r, 1);

	r = 0;
	if (a != b) r = 1;
	check("bne true", r, 1);

	r = 0;
	if (a < b) r = 1;
	check("blt true", r, 1);

	r = 0;
	if (b > a) r = 1;
	check("bgt true", r, 1);

	r = 0;
	if (a <= c) r = 1;
	check("ble eq", r, 1);

	r = 0;
	if (a >= c) r = 1;
	check("bge eq", r, 1);

	sys->print("  byte comparisons: done\n");
}

#
# Test 8: Big (64-bit) arithmetic - JIT native: IADDL, ISUBL, IMOVL
#
test_big_arithmetic()
{
	sys->print("--- Big Arithmetic ---\n");

	a := big 1000000;
	b := big 2000000;

	checkbig("add", a + b, big 3000000);
	checkbig("sub", b - a, big 1000000);

	# Values that fit cleanly in big
	c := big 65536;
	d := c * c;  # 2^32 = 4294967296
	checkbig("mul big", d, big 16r100000000);
	checkbig("add large", d + big 1, big 16r100000001);
	sub_expected := c * c - big 1;  # computed: avoids big literal parsing issues
	checkbig("sub large", d - big 1, sub_expected);

	# Negative big
	checkbig("neg big", big 0 - big 42, big -42);

	sys->print("  big arithmetic: done\n");
}

#
# Test 9: Big bitwise - JIT native: IORL, IANDL, IXORL
#
test_big_bitwise()
{
	sys->print("--- Big Bitwise ---\n");

	a := big 16rFF00FF00;
	b := big 16r00FF00FF;

	checkbig("or", a | b, big 16rFFFFFFFF);
	checkbig("and", a & b, big 0);
	checkbig("xor", a ^ b, big 16rFFFFFFFF);

	# 64-bit values
	c := big 16rFF00000000000000;
	d := big 16r00FF000000000000;
	checkbig("or 64", c | d, big 16rFFFF000000000000);

	sys->print("  big bitwise: done\n");
}

#
# Test 10: Big shifts - JIT native: ISHLL, ISHRL
#
test_big_shifts()
{
	sys->print("--- Big Shifts ---\n");

	checkbig("shl 1", big 1 << 0, big 1);
	checkbig("shl 32", big 1 << 32, big 4294967296);
	checkbig("shl 63", big 1 << 63, big -9223372036854775808);

	checkbig("shr 1", big 256 >> 4, big 16);
	shr_val := big 1 << 32;
	checkbig("shr 32", shr_val >> 32, big 1);

	sys->print("  big shifts: done\n");
}

#
# Test 11: Big comparisons - JIT native: IBEQL, IBNEL, IBLTL, IBGTL, IBLEL, IBGEL
#
test_big_comparisons()
{
	sys->print("--- Big Comparisons ---\n");

	a := big 100;
	b := big 200;
	c := big 100;

	r := 0;
	if (a == c) r = 1;
	check("beql true", r, 1);

	r = 0;
	if (a != b) r = 1;
	check("bnel true", r, 1);

	r = 0;
	if (a < b) r = 1;
	check("bltl true", r, 1);

	r = 0;
	if (b > a) r = 1;
	check("bgtl true", r, 1);

	r = 0;
	if (a <= c) r = 1;
	check("blel eq", r, 1);

	r = 0;
	if (a >= c) r = 1;
	check("bgel eq", r, 1);

	# Large values
	big_a := big 16r100000000;
	big_b := big 16r200000000;
	r = 0;
	if (big_a < big_b) r = 1;
	check("bltl large", r, 1);

	# Negative
	r = 0;
	if (big -1 < big 1) r = 1;
	check("bltl neg", r, 1);

	sys->print("  big comparisons: done\n");
}

#
# Test 12: Array indexing - JIT native: IINDW, IINDB, IINDX, ILENA
#
test_array_indexing()
{
	sys->print("--- Array Indexing ---\n");

	# Int array
	arr := array[10] of int;
	for (i := 0; i < 10; i++)
		arr[i] = i * i;
	check("arr[0]", arr[0], 0);
	check("arr[1]", arr[1], 1);
	check("arr[5]", arr[5], 25);
	check("arr[9]", arr[9], 81);
	check("len arr", len arr, 10);

	# Byte array
	barr := array[5] of byte;
	for (i = 0; i < 5; i++)
		barr[i] = byte (i + 65);  # 'A', 'B', 'C', 'D', 'E'
	checkbyte("barr[0]", barr[0], byte 65);
	checkbyte("barr[4]", barr[4], byte 69);

	# Array modification in loop
	sum := 0;
	for (i = 0; i < 10; i++)
		sum += arr[i];
	check("arr sum", sum, 285);  # 0+1+4+9+16+25+36+49+64+81

	# Two-dimensional access pattern
	n := 4;
	grid := array[n*n] of int;
	for (i = 0; i < n; i++)
		for (j := 0; j < n; j++)
			grid[i*n + j] = i * 10 + j;
	check("grid[0,0]", grid[0], 0);
	check("grid[1,2]", grid[1*n + 2], 12);
	check("grid[3,3]", grid[3*n + 3], 33);

	sys->print("  array indexing: done\n");
}

#
# Test 13: String indexing - JIT native: IINDC, ILENC
#
test_string_indexing()
{
	sys->print("--- String Indexing ---\n");

	s := "Hello";
	check("len str", len s, 5);
	check("str[0]", s[0], 'H');
	check("str[4]", s[4], 'o');

	# Empty string
	e := "";
	check("len empty", len e, 0);

	sys->print("  string indexing: done\n");
}

#
# Test 14: List operations - JIT native: IHEADW, IHEADB, IHEADP, ITAIL, ILENL
#
test_list_operations()
{
	sys->print("--- List Operations ---\n");

	l := 1 :: 2 :: 3 :: nil;
	check("len list", len l, 3);
	check("head", hd l, 1);

	l = tl l;
	check("tl head", hd l, 2);
	check("tl len", len l, 2);

	l = tl l;
	check("tl tl head", hd l, 3);
	check("tl tl len", len l, 1);

	# Build list and sum
	nums := 10 :: 20 :: 30 :: 40 :: 50 :: nil;
	sum := 0;
	for (tmp := nums; tmp != nil; tmp = tl tmp)
		sum += hd tmp;
	check("list sum", sum, 150);

	sys->print("  list operations: done\n");
}

#
# Test 15: Function calls - JIT native: ICALL, IFRAME, IRET
#
test_function_calls()
{
	sys->print("--- Function Calls ---\n");

	check("simple call", add_func(3, 4), 7);
	check("nested call", add_func(add_func(1, 2), add_func(3, 4)), 10);
	check("call chain", mul3(2, 3, 4), 24);

	# Multiple args
	check("multi arg", sum5(1, 2, 3, 4, 5), 15);

	sys->print("  function calls: done\n");
}

add_func(a, b: int): int
{
	return a + b;
}

mul3(a, b, c: int): int
{
	return a * b * c;
}

sum5(a, b, c, d, e: int): int
{
	return a + b + c + d + e;
}

#
# Test 16: Recursion - tests JIT frame handling
#
test_recursion()
{
	sys->print("--- Recursion ---\n");

	check("fib(0)", fib(0), 0);
	check("fib(1)", fib(1), 1);
	check("fib(10)", fib(10), 55);
	check("fib(20)", fib(20), 6765);

	check("fact(0)", factorial(0), 1);
	check("fact(5)", factorial(5), 120);
	check("fact(10)", factorial(10), 3628800);

	# Deep recursion
	check("sum_to(100)", sum_to(100), 5050);
	check("sum_to(1000)", sum_to(1000), 500500);

	sys->print("  recursion: done\n");
}

fib(n: int): int
{
	if (n <= 1)
		return n;
	return fib(n-1) + fib(n-2);
}

factorial(n: int): int
{
	if (n <= 1)
		return 1;
	return n * factorial(n-1);
}

sum_to(n: int): int
{
	if (n <= 0)
		return 0;
	return n + sum_to(n-1);
}

#
# Test 17: Type conversions - JIT native: ICVTBW, ICVTWB, ICVTWL, ICVTLW
#
test_type_conversions()
{
	sys->print("--- Type Conversions ---\n");

	# byte -> int (CVTBW)
	b := byte 255;
	check("byte->int", int b, 255);
	b = byte 0;
	check("byte->int 0", int b, 0);

	# int -> byte (CVTWB)
	i := 65;
	checkbyte("int->byte", byte i, byte 65);
	i = 256;
	checkbyte("int->byte wrap", byte i, byte 0);
	i = 300;
	checkbyte("int->byte wrap2", byte i, byte 44);

	# int -> big (CVTWL)
	x := 42;
	bx := big x;
	checkbig("int->big", bx, big 42);
	x = -42;
	bx = big x;
	checkbig("int->big neg", bx, big -42);

	# big -> int (CVTLW)
	bl := big 12345;
	check("big->int", int bl, 12345);
	bl = big -12345;
	check("big->int neg", int bl, -12345);

	sys->print("  type conversions: done\n");
}

#
# Test 18: Control flow - JIT native: IJMP, ICASE, loops
#
test_control_flow()
{
	sys->print("--- Control Flow ---\n");

	# For loop
	sum := 0;
	for (i := 1; i <= 100; i++)
		sum += i;
	check("for loop", sum, 5050);

	# While loop
	n := 10;
	prod := 1;
	while (n > 0) {
		prod *= n;
		n--;
	}
	check("while loop", prod, 3628800);  # 10!

	# Nested loops
	count := 0;
	for (i = 0; i < 10; i++)
		for (j := 0; j < 10; j++)
			count++;
	check("nested loop", count, 100);

	# Case/switch
	check("case 1", case_test(1), 10);
	check("case 2", case_test(2), 20);
	check("case 3", case_test(3), 30);
	check("case default", case_test(99), -1);

	# Break from loop
	val := 0;
	for (i = 0; i < 100; i++) {
		if (i == 42) {
			val = i;
			break;
		}
	}
	check("break", val, 42);

	sys->print("  control flow: done\n");
}

case_test(n: int): int
{
	case n {
	1 => return 10;
	2 => return 20;
	3 => return 30;
	* => return -1;
	}
}

#
# Test 19: Move operations - JIT native: IMOVW, IMOVB, IMOVL, IMOVF, IMOVP
#
test_move_operations()
{
	sys->print("--- Move Operations ---\n");

	# MOVW
	a := 42;
	b := a;
	check("movw", b, 42);

	# MOVB
	ba := byte 99;
	bb := ba;
	checkbyte("movb", bb, byte 99);

	# MOVL
	la := big 123456789012345;
	lb := la;
	checkbig("movl", lb, big 123456789012345);

	# Multiple assignments
	x := 1;
	y := 2;
	z := 3;
	x = y;
	y = z;
	z = x;
	check("swap x", x, 2);
	check("swap y", y, 3);
	check("swap z", z, 2);

	sys->print("  move operations: done\n");
}

#
# Test 20: Edge cases - stress various JIT paths
#
test_edge_cases()
{
	sys->print("--- Edge Cases ---\n");

	# Powers of 2 (important for shift operations)
	p := 1;
	for (i := 0; i < 30; i++) {
		expected := 1;
		for (j := 0; j < i; j++)
			expected *= 2;
		check("pow2 " + string i, p, expected);
		p *= 2;
	}

	# Alternating operations
	x := 0;
	for (i = 0; i < 100; i++) {
		if (i % 2 == 0)
			x += i;
		else
			x -= i;
	}
	check("alternating", x, -50);

	# Mixed types in expressions
	ival := 42;
	bval := big ival;
	back := int bval;
	check("int->big->int", back, 42);

	# Array with computed indices
	arr := array[100] of int;
	for (i = 0; i < 100; i++)
		arr[i] = i;
	sum := 0;
	for (i = 99; i >= 0; i--)
		sum += arr[i];
	check("reverse sum", sum, 4950);

	# Deeply nested conditions
	val := deep_nest(5, 10, 15);
	check("deep nest", val, 30);

	sys->print("  edge cases: done\n");
}

deep_nest(a, b, c: int): int
{
	if (a > 0) {
		if (b > 0) {
			if (c > 0) {
				return a + b + c;
			}
			return a + b;
		}
		return a;
	}
	return 0;
}
