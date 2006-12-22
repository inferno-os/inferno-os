.TL
Addendum to
.I "The Limbo Programming Language"
.AU
Vita Nuova
.br
30 March 2005
.NH 1
Introduction
.LP
This addendum provides a brief summary of several language changes to
Limbo since
.I "The Limbo Programming Language"
was last revised:
.RS
.IP •
buffered channels
.IP •
unrestricted \f5alt\f1
.IP •
function references
.IP •
exceptions
.IP •
exponentiation
.IP •
fixed-point types
.RE
.NH 1
Buffered channels
.LP
A buffered channel can now be declared:
.P1
c := chan[1] of int;
.P2
Here the buffer size is 1. A send on this channel will succeed immediately
if there is a receiver waiting or if the buffer is empty. A receive on this
channel will succeed immediately if there is a data item in the buffer. This allows us to
write a very simple locking mechanism:
.P1
acquire(c: chan of int)
{
	c <-= 0;
}

release(c: chan of int)
{
	<-c;
}

new(): chan of int
{
	return chan[1] of int;
}
.P2
The declaration
.P1
c := chan[0] of int;
.P2
is equivalent to 
.P1
	c := chan of int;
.P2
An attempt to create a channel with a negative buffer size will raise
an exception. An attempt to create a channel with a very large buffer
may result in an immediate memory exception if there is not enough
room for the buffer.
.NH 1
Unrestricted
.B alt
.LP
The implementation has changed to remove the restriction that only one process can be
waiting in an
.CW alt
to send or receive on a particular channel.
The busy exception never occurs now. Thus you can do
.P1
i()
{
	c := chan of int;
	c1 := chan of int;
	spawn p(c, c1);
	<-c;
	spawn p(c, c1);
	<-c;
	for(i := 0; i < 20; i++)
		c1 <-= i;
}

p(c: chan of int, c1: chan of int)
{
	c <-= 0;
	for(;;)
		alt{
			i := <-c1 =>
				;
		}
}
.P2
The two spawned processes can both wait on
.CW c1
without fuss.
Processes are queued on a strict FIFO basis so, in
the example above, the two processes receive on
.CW c1
alternately.
.NH 1
Function references
.LP
Function references may be declared as follows:
.P1
fp: ref fn(s1: string, s2: string): int;
.P2
Given the function
.P1
cmp(s1: string, s2: string): int
{
	if(s1 < s2)
		return -1;
	if(s1 > s2)
		return 1;
	return 0;
}
.P2
a reference to it can be created by assignment:
.P1
fp = cmp;
.P2
where the name can be qualified by an explicit module reference as usual:
.P1
fp = mod->cmp;
.P2
or it can be returned from a function:
.P1
Cmp: type ref fn(s1: string, s2: string): int;

rcmp(s1: string, s2: string): int
{
	return -cmp(s1, s2);
}

choose(i: int): Cmp
{
	if(i)
		return rcmp;
	return cmp;
}
.P2
(the declaration of the synonym
.CW Cmp
was done only for clarity).
They may be declared and passed as parameters:
.P1
sort(a: array of string, f: ref fn(s1, s2: string): int): array of string
{
	# ...
}
	# ...
b := sort(a, cmp);
c := sort(a, rcmp);
.P2
The function is called via the reference by
.P1
	r := fp("fred", "bloggs");
.P2
Otherwise function references behave just like any other reference type.
.NH 1
Exceptions
.LP
Both string exceptions and user defined exceptions are now provided.
The
.CW Sys
module interface to exceptions
has been removed and replaced by new language constructs in limbo.
.NH 2
String exceptions
.LP
Simple string exceptions can be raised as follows
.P1
raise \fIs\fP;
.P2
where
.I s
is any value of type string (it need not be constant).
.LP
Exception handlers may be attached to a block (or sequence of statements) :-
.P1
{
	foo();
	bar();
} exception e {
"a" or "b" =>
	sys->print("caught %s\en", e);
	raise;
"ab*" =>
	sys->print("caught %s\en", e);
	exit;
"abcd*" =>
	sys->print("caught %s\en", e);
	raise e;
"a*" =>
	sys->print("caught %s\en", e);
	raise "c";
"*" =>
	sys->print("caught %s\en", e);
}
LL:
.P2
.LP
Any exception occurring within the block (and in nested function calls within the block) can
potentially be caught by the exception handler. An exception is caught by a guard exactly
maching the exception string or by a guard
\f5\&"\fP\fIs\fP\f5*"\fP
where
.I s
is a prefix of the exception string.
The most specific match is used. Thus a raise of "a" will be caught by the first
guard and not by the fourth guard. A raise of "abcde" is caught by the third and not the second
or fourth. If a match is found, the sequence of statements following the guard are executed.
If not, the system searches for a handler at a higher level.
.LP
As shown above, the exception is available through the exception identifier (e in this case) if given following the exception keyword.
.LP
The exception is reraised using
.P1
raise;
.P2
or
.P1
raise e;
.P2
.LP
Both the block and the exception code will fall through to the statement labelled
LL unless, of course, they do an explicit exit, return or raise first.
.NH 2
User-defined exceptions
.LP
You can declare your own exceptions:
.P1
implement Fibonacci;

include "sys.m";
include "draw.m";

Fibonacci: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};
.P3

init(nil: ref Draw->Context, nil: list of string)
{
	sys := load Sys Sys->PATH;
	for(i := 0; ; i++){
		f := fibonacci(i);
		if(f < 0)
			break;
		sys->print("F(%d) = %d\en", i, f);
	}
}
.P3

FIB: exception(int, int);
.P3

fibonacci(n: int): int
{
	{
		fib(1, n, 1, 1);
	}exception e{
	FIB =>
		(x, nil) := e;
		return x;
	"*" =>
		sys->print("unexpected string exception %s raised\en", e);
	* =>
		sys->print("unexpected exception raised\en");
	}
	return 0;
}
.P3

fib(n: int, m: int, x: int, y: int) raises (FIB)
{
	if(n >= m)
		raise FIB(x, y);

	{
		fib(n+1, m, x, y);
	}exception e{
	FIB =>
		(x, y) = e;
		x = x+y;
		y = x-y;
		raise FIB(x, y);
	}
}
.P2
.LP
.CW FIB
is a declared exception that returns two integers. The values are supplied when raising the exception:
.P1
raise FIB(3, 4);
.P2
When caught the values can be recovered by treating the declared exception identifier
as if it were a tuple of 2 integers:
.P1
(x, y) = e;
.P2
In general each exception alternative treats the exception identifier appropriately : as a string
when the exception qualifier is a string, as the relevant tuple when the exception is declared.
.LP
If you do
.P1
"abcde" or FIB =>
	(x, y) = e;
	sys->print("%s\en", e);
.P2
you will get a compiler error as
.CW e 's
type is indeterminate within this alternative.
.LP
Reraising is the same as in the case of string exceptions.
.LP
Note also the difference between the string guard
\&\f5"*"\fP and the guard
.CW *
in
the function fibonacci.
The former will match any string exception, the latter any exception. If a
string exception does occur it matches the former as it is the most specific.
If an unexpected user defined
exception occurs it matches the latter.
.LP
The main difference between declared exceptions and string exceptions is
that the former must be caught by the immediate caller of a function that
raises them, otherwise they turn into a string exception whose name is derived
from that of the exception declaration.
.NH 2
The
.CW raises
clause
.LP
The definition of the function fib in the above example also lists the user defined exceptions it can raise via the use of a
.CW raises
clause. In this case there is just the one exception (\f5FIB\f1). These
clauses (if given) must be compatible between any declaration and definition of the function.
.LP
The compiler reports instances of functions which either raise some exception which
is not mentioned in their raises clause or does not raise some exception which is
mentioned in their raises clause. Currently the report is a warning.
.NH 1
Exponentiation
.LP
The exponentiation operator (written as
.CW ** )
is now part of the Limbo language.
Its precedence is above that of multiplication, division and modulus but below
that of the unary operators. It is right associative. Thus
.P1
3**4*2 = (3**4)*2 = 81*2 = 162
-3**4 = (-3)**4 = 81
2**3**2 = 2**(3**2) = 2**9 = 512
.P2
The type of the left operand must be
.CW int ,
.CW big
or
.CW real .
The type of the right operand must be
.CW int .
The type of the result is the type of the left operand.
.NH 1
Fixed point types
.LP
A declaration of the form
.P1
x: fixed(0.2, 12345.0);
.P2
declares
.CW x
to be a variable of a fixed point type. The scale of the type is
1/5 and the maximum absolute value of the type is 12345.0.
.LP
Similarly
.P1
x: fixed(0.125, 4096.0)
.P2
specifies a scale of 0.125 and a maximum absolute value of 4096.
This requires only 17 bits so the underlying type will be
.CW int
and the compiler
is free to allocate the remaining 15 bits to greater range or greater
accuracy. In fact the compiler always chooses the latter.
.LP
The maximum absolute value is optional :-
.P1
x: fixed(0.125);
.P2
is equivalent to
.P1
x: fixed(0.125, 2147483647.0 * 0.125);
.P2
and ensures the underlying type is exactly an int ie the compiler has
no scope to add any extra bits for more accuracy.
.LP
A binary fixed point type with 8 bits before the binary point and 24 after
might therefore be declared as
.P1
x: fixed(2.0**-24);
.P2
.LP
The scale must be static: its value known at compile time and
it must be positive and real; similarly for the maximum absolute
value when specified.
.LP
Currently the only underlying base type supported is
.CW int .
.LP
A shorthand for fixed point types is available through the use of
.CW type
declarations:
.P1
fpt: type fixed(2.0**-16);
.P2
We can then do
.P1
x, y, z: fpt;
zero: con fpt(0);

x = fpt(3.21);
y = fpt(4.678);
z = fpt(16r1234.5678);
z = -x;
z = x+y;
z = x-y;
z = x*y;
z = x/y;
sys->print("z=%f", real z);
.P2
There is no implicit numerical casting in Limbo so we have to use explicit
casts to initialize fixed point variables. Note the use of a base to
initialize
.CW z
using a new literal representation.
.LP
Given
.P1
fpt1: type fixed(0.12345);
x: fpt1;
fpt2: type fixed(0.1234);
y: fpt2;
fpt3: type fixed(0.123);
z: fpt3;
.P2
then
.P1
z = x*y;
.P2
is illegal. We must add casts and do
.P1
z = fpt3(x)*fpt3(y);
.P2
ie type equivalence between fixed point types requires equivalence of scale
(and of maximum absolute value when specified).
.LP
Fixed point types may be used where any other numerical type (byte, int, big, real) can be used. So you can compare them, have a list of them, have a channel of them, cast them to or from string and so on.
.LP
You cannot use complement(~), not(!), and(&), or(|), xor(^) or modulus(%) on them as fixed point types are basically a form of real type.
.NH 2
Accuracy
.LP
A fixed point value is a multiple of its scale. Given fixed point values X, Y and
Z of scale s, t and u respectively, we can write
.P1
X = sx
Y = ty
Z = uz
.P2
where x, y and z are integers.
.LP
For the multiplication Z = X*Y the accuracy achieved is given by
.P1
| z - (st/u)xy | < 1
.P2
and for the division Z = X/Y
.P1
| z - (s/(tu))x/y | < 1
.P2
That is, the result is always within the result scale of the correct real value.
.LP
This also applies when casting a fixed point type to another, casting an
integer to a fixed point type and casting a fixed point type to an integer. These
are all examples of the multiplication law with t = y = 1 since an
integer may be thought of as a fixed point type with a scale of 1.
