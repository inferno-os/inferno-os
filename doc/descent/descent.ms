.de EX
.nr x \\$1v
\\!h0c n \\nx 0
..
.de FG		\" start figure caption: .FG filename.ps verticalsize
.KF
.BP \\$1 \\$2
.sp .5v
.EX \\$2v
.ps -1
.vs -1
..
.de fg		\" end figure caption (yes, it is clumsy)
.ps
.vs
.br
.KE
..
.TL
A Descent into Limbo
.AU
Brian W. Kernighan
.AI
bwk@bell-labs.com
.br
Revised April 2005 by Vita Nuova
.AB
.DS B
.ps -2
.vs -1
``If, reader, you are slow now to believe
What I shall tell, that is no cause for wonder,
For I who saw it hardly can accept it.''
.ft R
	Dante Alighieri, \fIInferno\fP, Canto XXV.
.ps +2
.vs +1
.DE
.LP
Limbo is a new programming language, designed by
Sean Dorward, Phil Winterbottom, and Rob Pike.
Limbo borrows from, among other things,
C (expression syntax and control flow),
Pascal (declarations), 
Winterbottom's Alef (abstract data types and channels),
and Hoare's CSP and Pike's Newsqueak (processes).
Limbo is strongly typed, provides automatic garbage collection,
supports only very restricted pointers,
and compiles into machine-independent byte code for execution on
a virtual machine.
.LP
This paper is a brief introduction to Limbo.
Since Limbo is an integral part of the Inferno system,
the examples here illustrate not only
the language but also a certain amount about how to write
programs to run within Inferno.
.AE
.NH 1
Introduction
.LP
This document is a quick look at the basics
of Limbo; it is not a replacement for the reference manual.
The first section is a short overview of
concepts and constructs;
subsequent sections illustrate the language with examples.
Although Limbo is intended to be used in Inferno,
which emphasizes networking and graphical interfaces,
the discussion here begins with standard text-manipulation
examples, since they require less background to understand.
.SH
Modules:
.LP
A Limbo program is a set of modules that cooperate
to perform a task.
In source form, a module consists of a
.CW "module" 
declaration that specifies the public interface \- the functions,
abstract data types,
and constants that the module makes visible to other modules \-
and an implementation that provides the actual code.
By convention, the module declaration is usually placed in a separate
.CW ".m" 
file so it can be included by other modules,
and the implementation is stored in a
.CW ".b" 
file.
Modules may have multiple implementations,
each in a separate implementation file.
.LP
Modules are always loaded dynamically, at run time: the Limbo
.CW "load" 
operator fetches the code and performs run-time type checking.
Once a module has been loaded, its functions can be called.
Several instances of the same module type can be in use at once,
with possibly different implementations.
.LP
Limbo is strongly typed; programs are checked at compile time,
and further when modules are loaded.
The Limbo compiler compiles each source file into a
machine-independent byte-coded 
.CW ".dis" 
file that can be loaded at run time.
.SH
Functions and variables:
.LP
Functions are associated with specific modules, either directly or
as members of abstract data types within a module.
Functions are visible outside their module only
if they are part of the module interface.
If the target module is loaded, specific names
can be used in a qualified form like
.CW "sys->print" 
or without the qualifier if imported with an explicit
.CW "import" 
statement.
.LP
Besides normal block structure within functions,
variables may have global scope within a module;
module data can be accessed via the module pointer.
.SH
Data:
.LP
The numeric types are:
.RS
.TS
lf(CW) lf(R)w(3i) .
byte	unsigned, 8 bits
int	signed, 32 bits
big	signed, 64 bits
real	IEEE long float, 64 bits
.TE
.RE
The size and signedness of integral types are
as specified above, and will be the same everywhere.
Character constants are enclosed in single quotes
and may use escapes like
.CW "'\en'" 
or
.CW "'\eudddd'" ,
but the characters themselves
are in Unicode and have type
.CW "int" .
There is no enumeration type, but there is a
.CW "con" 
declaration that creates a named constant, and a special
.CW "iota"
operation that can be used to generate unique values.
.LP
Limbo also provides
Unicode strings,
arrays of arbitrary types,
lists of arbitrary types,
tuples (in effect, unnamed structures with unnamed members of arbitrary types),
abstract data types or adt's (in effect, named structures with function
members as well as data members),
reference types (in effect, restricted pointers that can point only to adt objects),
and 
typed channels (for passing objects between processes).
.LP
A channel is a mechanism for synchronized communication.
It provides a place for one process to send or receive
an object of a specific type;
the attempt to send or receive blocks until a matching receive or send
is attempted by another process.
The 
.CW "alt" 
statement selects randomly but fairly among channels
that are ready to read or write.
The
.CW "spawn" 
statement creates a new process that,
except for its stack, shares memory with other processes.
Processes are pre-emptively scheduled by the Inferno kernel.
(Inferno processes are sometimes called ``threads'' in
other operating systems.)
.LP
Limbo performs automatic garbage collection, so there is no
need to free dynamically created objects.
Objects are deleted and their resources freed when
the last reference to them goes away.
This release of resources happens immediately
(``instant free'') for non-cyclic structures;
release of cyclic data structures might be delayed but will happen eventually.
(The language allows the programmer to ensure a given structure is non-cyclic
when required.)
.SH
Operators and expressions:
.LP
Limbo provides many of C's operators,
but not the
.CW "?:" 
or
`comma' (sequential execution) operators.
Pointers, or `references', created with
.CW "ref" ,
are restricted compared to C: they can only refer to adt values on the heap.
There is no
.CW "&" 
(address of) operator, nor is address arithmetic possible.
Arrays are also reference types, however,
and since
array slicing is supported, that replaces
many of C's pointer constructions.
.LP
There are no implicit coercions between types,
and only a handful of explicit casts.
The numeric types
.CW "byte" ,
.CW "int" ,
etc., can be used to convert a numeric expression, as in
.P1
nl := byte 10;
.P2
and
.CW "string" 
can be used as a unary operator to convert any numeric expression
to a string (in
.CW "%g" 
format) and to convert an array of bytes in UTF-8 format to a Limbo
.CW string
value.
In the other direction, the cast
.CW "array of byte"
converts a string to its UTF-8 representation in an array of bytes.
.SH
Statements:
.LP
Statements and control flow in Limbo are similar to those in C.
A statement is an expression followed by a semicolon,
or a sequence of statements enclosed in braces.
The similar control flow statements are
.P1
if (\fIexpr\fP) \fIstat\fP
if (\fIexpr\fP) \fIstat\fP else \fIstat\fP
while (\fIexpr\fP) \fIstat\fP
for (\fIexpr\fP; \fIexpr\fP; \fIexpr\fP) \fIstat\fP
do \fIstat\fP while (\fIexpr\fP) ;
return \fIexpr\fP ;
exit ;
.P2
The
.CW "exit" 
statement terminates a process and frees its resources.
There is also a 
.CW "case" 
statement analogous to C's
.CW "switch" ,
but it differs in that it also supports string and range tests,
and more critically, control flow does not ``flow through'' one arm of the case to another
but stops without requiring an explicit
.CW break
(in that respect it is closer to Pascal's
.CW case
statement, hence the change of name).
A
.CW "break" 
or
.CW "continue" 
followed by a label
causes a break out of, or the next iteration of, the enclosing
construct that is labeled with the same label.
.LP
Comments begin with
.CW "#" 
and extend to the end of the line.
There is no preprocessor, but an
.CW "include" 
statement can be used to include source code, usually module declaration files.
.SH
Libraries:
.LP
Limbo has an extensive and growing set of standard libraries,
each implemented as a module.
A handful of these
(notably
.CW "Sys" ,
.CW "Draw" ,
and
.CW "Tk" )
are included in the Inferno kernel because they will be
needed to support almost any Limbo program.
Among the others are
.CW "Bufio" ,
a buffered I/O package based on Plan 9's Bio;
.CW "Regex" ,
for regular expressions;
and
.CW "Math" ,
for mathematical functions.
Some of the examples that follow provide the sort
of functionality that might be a suitable module.
.NH 1
Examples
.LP
The examples in this section are each complete, in the sense that they
will run as presented; I have tried to avoid code fragments
that merely illustrate syntax.
.NH 2
Hello, World
.LP
The first example is the traditional ``hello, world'',
in the file
.CW "hello.b" :
.P1
implement Hello;

include "sys.m";
	sys: Sys;
include "draw.m";

Hello: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->print("hello, world\en");
}
.P2
An implementation file implements a single module,
named in the
.CW "implement" 
declaration at the top of the file.
The two 
.CW "include" 
lines copy interface definitions from two other modules,
.CW "Sys" 
(which describes a variety of system functions like
.CW "print" ),
and
.CW "Draw" 
(which describes a variety of graphics types and functions,
only one of which,
.CW "Context" ,
is used here).
.LP
The 
.CW "module" 
declaration defines the external interface that this module
presents to the rest of the world.
In this case, it's a single function named
.CW "init" .
Since this module is to be called from a command interpreter
(shell), by convention its 
.CW "init" 
function takes two arguments,
the graphical context
and a list of strings, the command-line arguments,
though neither is used here.
This is like
.CW "main" 
in a C program.
Essentially all of the other examples begin with this standard code.
Commands are unusual, though, in that a command's module declaration
appears in the same file as its implementation.
.LP
Most modules have a more extensive set of declarations; for example, 
.CW "draw.m" 
is 298 lines of constants, function prototypes, and
type declarations for graphics types like
.CW "Point" 
and 
.CW "Rect" ,
and
.CW "sys.m" 
is 160 lines of declarations for functions like
.CW "open" ,
.CW "read" ,
and
.CW "print" .
Most module declarations are therefore stored in separate files,
conventionally suffixed with
.CW ".m" ,
so they can be included in other modules.
The system library module declaration files are collected in the
.CW module
directory at the root of the Inferno source tree.
Modules that are components of a single program are typically
stored in that program's source directory.
.LP
The last few lines of
.CW "hello.b" 
are the implementation of the
.CW "init" 
function, which loads the
.CW "Sys" 
module, then calls its 
.CW "print" 
function.
By convention, each module declaration includes a pathname constant
that points to the code for the module; this is the second parameter
.CW "Sys->PATH" 
of the
.CW "load" 
statement.
Note that the
.CW Draw
module is not loaded because none of its functions is used, but
it is included to define the type
.CW Draw->Context .
.SH
Compiling and Running Limbo Programs
.LP
With this much of the language described,
we can compile and run this program.
On Unix or Windows, the command
.P1
$ limbo -g hello.b
.P2
creates
.CW "hello.dis" ,
a byte-coded version of the program for the Dis
virtual machine.
The
.CW "-g" 
argument adds a symbol table, useful for subsequent debugging.
(Another common option is
.CW -w ,
which causes the compiler to produce helpful warnings about possible errors.)
The program can then be run as
.CW "hello" 
in Inferno; this shows execution under the Inferno emulator
on a Unix system:
.P1
$ limbo -g hello.b
$ emu
; /usr/bwk/hello
hello, world
; 
.P2
From within Inferno, it's also possible to run a
program by selecting it from a menu.
In any case, as the program runs, it loads as necessary other modules that it uses.
.NH 2
A Graphical "Hello World"
.LP
The following module creates and displays a window containing only
a button with the label ``hello, world'' as shown in the screen shot in Figure 1.
.P1
implement Hello2;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;

Hello2: module
{
        init:   fn(ctxt: ref Draw->Context, args: list of string);
};

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;

	tkclient->init();

	(t, nil) := tkclient->toplevel(ctxt, "", "Hello", Tkclient->Plain);

	tk->cmd(t, "button .b -text {hello, world}");
	tk->cmd(t, "pack .b");
	tk->cmd(t, "update");

	tkclient->onscreen(t, nil);

	sys->sleep(10000);	# wait 10 seconds
}
.P2
.FG "f1.ps" 3i
.ce
.I "Figure 1.  `Hello, world' button."
.fg
This is not very exciting, but it illustrates the absolute
minimum required to get a picture on the screen.
The
.CW "Tk" 
module is modeled closely after John Ousterhout's Tk interface toolkit,
but Limbo is used as the programming language instead of Tcl.
The Inferno version
is similar in functionality to the original Tk
but it does not support any Tcl constructs,
such as variables, procedures, or expression evaluation,
since all processing is done using Limbo.
There are ten functions in the
.CW "Tk" 
interface, only one of which
is used here:
.CW "cmd" ,
which executes a command string.
(It is the most commonly used
.CW Tk
function.)
.LP
Tk itself displays graphics and handles mouse and keyboard interaction
within a window.
There can however be many different windows on a display.
A separate window manager,
.CW wm ,
multiplexes control of input and output among those windows.
The module
.CW Tkclient
provides the interface between the window manager and Tk.
Its function
.CW "toplevel" ,
used above,
makes a top-level window and returns a reference to it, for subsequent use by Tk.
The contents of the window are prepared by calls to
.CW tk->cmd
before the window is finally displayed by the call to
.CW onscreen .
(The second parameter to
.CW onscreen ,
a string,
controls the position and style of window;
here we take the default by making that
.CW nil .)
.LP
Note that
.CW Tkclient
must also be explicitly initialized by calling its
.CW init
function after loading.
This is a common convention, although some modules do
not require it (typically those built in
to the system, such as
.CW Sys
or
.CW Tk ).
.LP
The
.CW "sleep" 
delays exit for 10 seconds so the button can be seen.
If you try to interact with the window, for instance by pressing the button,
you will see no response.
That is because the program has not done what is required to receive mouse or keyboard input in the window.
In a real application, some action would also be bound to pressing the button.
Such actions are handled by setting up a connection (a `channel') from
the Tk module to one's own code, and processing the
messages (`events') that appear on this channel.
The Tk module and its interface to the window manager
is explained in more detail later,
as are a couple of other constructions,
after we have introduced processes and channels.
.NH 2
Echo
.LP
The next example,
.CW "echo" ,
prints its command-line arguments.
Declarations are the same as in the first 
example, and have been omitted.
.P1
# declarations omitted...

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	args = tl args;		# skip over program name
	for (s := ""; args != nil; args = tl args)
		s += " " + hd args;
	if (s != "")		# something was stored in s
		sys->print("%s\en", s[1:]);
}
.P2
The arguments are stored in a 
.CW "list" .
Lists may be of any type;
.CW "args" 
is a
.CW "list" 
.CW "of" 
.CW "string" .
There are three list operators:
.CW "hd" 
and
.CW "tl" 
return the head and tail of a list, and
.CW "::" 
adds a new element to the head.
In this example, the
.CW "for" 
loop walks along the
.CW "args" 
list until the end,
printing the head element
.CW "hd args" ), (
then advancing
.CW "args = tl args" ). (
.LP
The value
.CW "nil" 
is the ``undefined'' or ``explicitly empty'' value
for non-numeric types.
.LP
The operator
.CW ":=" 
combines the declaration of a variable and assignment of a value to it.
The type of the variable on the left of
.CW ":=" 
is the type
of the expression on the right.
Thus, the expression
.P1
s := ""
.P2
in the 
.CW "for" 
statement
declares a string
.CW "s" 
and initializes it to empty;
if after the loop,
.CW "s" 
is not empty,
something has been written in it.
By the way, there is no distinction between the values
.CW "nil" 
and
\f5""\fP
for strings.
.LP
The
.CW "+" 
and
.CW "+=" 
operators concatenate strings.
The expression
.CW "s[1:]" 
is a
.I slice
of the string
.CW "s" 
that starts at index 1
(the second character of the string) and goes
to the end; this excludes the unwanted
blank at the beginning of
.CW "s" .
.NH 2
Word Count
.LP
The word count program
.CW "wc" 
reads its standard input
and counts the number of lines, words, and characters.
Declarations have again been omitted.
.P1
# declarations omitted...

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	buf := array[1] of byte;

	stdin := sys->fildes(0);

	OUT: con 0;
	IN: con 1;

	state := OUT;
	nl := 0; nw := 0; nc := 0;
	for (;;) {
		n := sys->read(stdin, buf, 1);
		if (n <= 0)
			break;
		c := int buf[0];
		nc++;
		if (c == '\en')
			nl++;
		if (c == ' ' || c == '\et' || c == '\en')
			state = OUT;
		else if (state == OUT) {
			state = IN;
			nw++;
		}
	}
	sys->print("%d %d %d\en", nl, nw, nc);
}
.P2
.LP
This program contains several instances of the
.CW ":=" 
operator.
For example, the line
.P1
	nl := 0; nw := 0; nc := 0;
.P2
declares three integer variables
and assigns zero to each.
.LP
A Limbo program starts with three open files for standard
input, standard output, and standard error, as in Unix.
The line
.P1
	stdin := sys->fildes(0);
.P2
declares a variable
.CW "stdin" 
and assigns the corresponding file descriptor to it.
The type of
.CW "stdin" 
is whatever the type of
.CW "sys->fildes(0)" 
is, and it's possible to get by without
ever knowing the name of that type.
(We will return to this shortly.)
.NE 3v
.LP
The lines
.P1
        OUT: con 0;
        IN: con 1;
.P2
declare two integer constants with values zero and one.
There is no
.CW "enum" 
type in Limbo; the
.CW "con" 
declaration is the closest equivalent.
When the values are arbitrary, a different form is normally used:
.P1
	OUT, IN: con iota;
.P2
The operator
.CW "iota" ,
when used in
.CW con
declarations will produce the sequence of values 0, 1, ....,
one value in turn for each name declared in the same declaration.
It can appear in more complex expressions:
.P1
	M1, M2, M4, M8: con 1 << iota;
	N1, N3, N5, N7: con (2*iota)+1;
.P2
The first example generates a set of bitmask values; the second generates a
sequence of odd numbers.
.LP
Given the declarations of
.CW "IN" 
and
.CW "OUT" ,
the line
.P1
	state := OUT;
.P2
declares 
.CW "state" 
to be an integer with initial value zero.
.LP
The line
.P1
        buf := array[1] of byte;
.P2
declares 
.CW "buf" 
to be a one-element array of 
.CW "byte" s.
Arrays are indexed from zero, so
.CW "buf[0]" 
is the only element.
Arrays in Limbo are dynamic, so this array is created at
the point of the declaration.
An alternative would be to declare the array and
create it in separate statements:
.P1
	buf : array of byte;	# no size at declaration

	buf = array[1] of byte;	# size needed at creation
.P2
.LP
Limbo does no automatic coercions between types,
so an explicit coercion is required to convert the
single byte read from 
.CW "stdin" 
into an
.CW "int" 
that can be used in subsequent comparisons with
.CW "int" 's;
this is done by the line
.P1
	c := int buf[0];
.P2
which declares
.CW "c" 
and assigns the integer value of the input byte to it.
.NH 2
Word Count Version 2
.LP
The word count program above tacitly assumes that its input is
in the ASCII subset of Unicode, since it reads
input one byte at a time instead of one Unicode character
at a time.
If the input contains any multi-byte Unicode characters,
this code is plain wrong.
The assignment to 
.CW "c" 
is a specific example: the integer value of the first byte
of a multi-byte Unicode character is not the character.
.LP
There are several ways to address this shortcoming.
Among the possibilities are
rewriting to use the
.CW "Bufio" 
module, which does string I/O,
or checking each input byte sequence to see if it is
a multi-byte character.
The second version of word counting uses 
.CW "Bufio" .
This example will also illustrate rules for accessing objects
within modules.
.P1
# declarations omitted...

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->fprint(sys->fildes(2), "wc: can't load %s: %r\en", Bufio->PATH);
		raise "fail:load";
	}

	stdin := sys->fildes(0);
	iob := bufio->fopen(stdin, bufio->OREAD);
	if (iob == nil) {
		sys->fprint(sys->fildes(2), "wc: can't open stdin: %r\en");
		raise "fail:open";
	}

	OUT, IN: con iota;

	state := OUT;
	nl := big 0; nw := big 0; nc := big 0;
	for (;;) {
		c := iob.getc();
		if (c == Bufio->EOF)
			break;
		nc++;
		if (c == '\en')
			nl++;
		if (c == ' ' || c == '\et' || c == '\en')
			state = OUT;
		else if (state == OUT) {
			state = IN;
			nw++;
		}
	}
	sys->print("%bd %bd %bd\en", nl, nw, nc);
}
.P2
The lines
.P1
include "bufio.m";
	bufio: Bufio;
.P2
include the declarations from
.CW "bufio.m" 
and declare a variable
.CW "bufio" 
that will serve as a handle when we load an implementation of the
.CW "Bufio" 
module.
(The use of a module's type in lower case as the name of a loaded instance is a common convention in Limbo programs.)
With this handle, we can
refer to the functions and types
the module defines, which are in the file
.CW "/usr/inferno/module/bufio.m"
(the full name might be different on your system).
Parts of this declaration are shown here:
.P1
Bufio: module	# edited to fit your screen
{
	PATH:	con "/dis/bufio.dis";
	EOF:	con -1;
	Iobuf: adt {
		fd:	ref Sys->FD;	# the file
		buffer:	array of byte;	# the buffer
					# other variables omitted
		getc:	fn(b: self ref Iobuf) : int;
		gets:	fn(b: self ref Iobuf, sep: int) : string;
		close:	fn(b: self ref Iobuf);
	};
	open:	fn(name: string, mode: int) : ref Iobuf;
	fopen:	fn(fd: ref Sys->FD, mode: int) : ref Iobuf;
};
.P2
.LP
The
.CW "bufio" 
module defines 
.CW "open" 
and
.CW "fopen" 
functions that return references to an
.CW "Iobuf" ;
this is much like a
.CW "FILE*" 
in the C standard I/O library.
A reference is necessary so that all uses
refer to the same entity, the object maintained by the module.
.LP
Given the name of a module (e.g., 
.CW "Bufio" ),
how do we refer to its contents?
It is always possible to use fully-qualified names,
and the
.CW "import" 
statement permits certain abbreviations.
We must also distinguish between the name of the module itself
and a specific implementation returned by
.CW "load" ,
such as
.CW "bufio" .
.LP
The fully-qualified name of a type or constant from a module
is
.P1
\fIModulename\fP->\fIname\fP
.P2
as in
.CW "Bufio->Iobuf" 
or
.CW "Bufio->EOF" .
To refer to members of an adt or functions or variables from a module, however,
it is necessary to use a module value instead of a module name:
although the interface
is always the same, the implementations of different instances
of a module will be different, and we must refer to a specific
implementation.
A fully-qualified name is
.P1
\fImoduleval\fP->\fIfunctionname\fP
\fImoduleval\fP->\fIvariablename\fP
\fImoduleval\fP->\fIadtname\fP.\fImembername\fP
.P2
where adt members can be variables or functions.
Thus:
.P1
iob: ref bufio->Iobuf;
...
bufio->open(...)
bufio->iob.getc()
bufio->iob.fd
.P2
It is also legal to refer to module types, constants, and variables
with a module handle, as in
.CW "bufio->EOF" .
.LP
An
.CW "import" 
statement makes a specific list of names from
a module accessible without need for a fully-qualified name.
Each name must be imported explicitly, and adt member names
can not be imported.
Thus, the line
.P1
Iobuf: import bufio;
.P2
imports the adt name
.CW "Iobuf" ,
which means that functions within that adt (like
.CW "getc)" 
can be used
without module qualification, i.e., without
.CW "bufio->" .
(It is still necessary to say
.CW "iob.getc()"
for reasons given below.)
In all cases, imported names must be unique.
.LP
The second parameter of
.CW "load" 
is a string giving the location of the module implementation,
typically a
.CW ".dis" 
file.
(The string need not be static.)
Some modules are part of the system;
these have location names that begin with
.CW "$" 
but are otherwise the same for users.
By convention, modules include a constant called
.CW "PATH" 
that points to their default location.
.LP
The call to
.CW "bufio->fopen" 
attaches the I/O buffer to the already open file
.CW "stdin" ;
this is rather like
.CW "freopen" 
in
.CW "stdio" .
.LP
The function
.CW "iob.getc" 
returns the next Unicode character,
or
.CW "bufio->EOF" 
if end of file was encountered.
.LP
A close look at the calls to
.CW "sys->print" 
shows a new format conversion character,
.CW "%r" ,
for which there is no corresponding argument in the
expression list.
The value of
.CW "%r" 
is the text of the most recent system error message.
.LP
Several other small changes were made as realistic examples:
it keeps the counts as
.CW big
to cope with larger files (hence the use of
.CW %bd
as the output format);
it prints diagnostics on the standard error stream,
.CW sys->fildes(2) ,
using
.CW sys->fprint ,
a variant of
.CW sys->print
that takes an explicit file descriptor;
and it returns an error status to its caller (typically the shell) by
raising an exception.
.NH 2
An Associative Array Module
.LP
This section describes a module that implements a conventional
associative array (a hash table
pointing to chained lists of name-value strings).
This module is meant to be part of a larger program,
not a standalone program like the previous examples.
.LP
The 
.CW "Hashtab" 
module stores a name-value pair as a tuple of
.CW "(string," 
.CW "string)" .
A tuple is a type consisting of an ordered collection
of objects, each with its own type.
The hash table implementation uses several different tuples.
.LP
The hash table module defines a type to hold the
data, using an
.CW "adt" 
declaration.
An adt defines a type and optionally a set of functions 
that manipulate an object of that type.
Since it provides only the ability to group variables and functions, 
it is like a really slimmed-down version of a C++ class,
or a slightly fancier C
.CW "struct" .
In particular, an adt does not provide information hiding
(all member names are visible if the adt itself is visible),
does not support inheritance,
and has no constructors, destructors or overloaded method names.
It is different from C or C++, however: when an adt is declared by a
.CW module
declaration, the adt's implementation (the bodies of its functions)
will be defined by the module's implementation, and there can be more than one.
To create an instance of an adt,
.P1
\fIadtvar\fP := \fIadtname\fP(\fIlist of values for all members, in order\fP);
\fIadtvar\fP := ref \fIadtname\fP(\fIlist of values for all members, in order\fP);
.P2
Technically these are casts, from tuple to adt;
that is, the adt is created from a tuple that
specifies all of its members in order.
.LP
The 
.CW "Hashtab" 
module contains an
.CW "adt" 
declaration for a type
.CW "Table" ;
the operations are a function
.CW "alloc" 
for initial allocation
(in effect a constructor),
a hash function, and methods to add and look up elements by name.
Here is the module declaration, which is contained in file
.CW "hashtab.m" :
.nr dT 4
.nr dP \n(dP+1
.P1
Hashtab: module
{
	PATH:	con "/usr/bwk/hashtab.dis";  # temporary name

	Table: adt {
		tab: array of list of (string, string);

		alloc: fn(n: int) : ref Table;

		hash: fn(ht: self ref Table, name: string) : int;
		add: fn(ht: self ref Table, name: string, val: string);
		lookup: fn(ht: self ref Table, name: string) : (int, string);
	};
};
.P2
.nr dT 8
.nr dP \n(dP-1
The implementation is in file
.CW "hashtab.b" :
.P1
implement Hashtab;

include "hashtab.m";

Table.alloc(n: int) : ref Table
{
	return ref Table(array[n] of list of (string,string));
}

Table.hash(ht: self ref Table, s: string) : int
{
	h := 0;
	for (i := 0; i < len s; i++)
		h = (h << 1) ^ int s[i];
	h %= len ht.tab;
	if (h < 0)
		h += len ht.tab;
	return h;
}

Table.add(ht: self ref Table, name: string, val: string)
{
	h := ht.hash(name);
	for (p := ht.tab[h]; p != nil; p = tl p) {
		(tname, nil) := hd p;
		if (tname == name) {
			# illegal: hd p = (tname, val);
			return;
		}
	}
	ht.tab[h] = (name, val) :: ht.tab[h];
}

Table.lookup(ht: self ref Table, name: string) : (int, string)
{
	h := ht.hash(name);
	for (p := ht.tab[h]; p != nil; p = tl p) {
		(tname, tval) := hd p;
		if (tname == name)
			return (1, tval);
	}
	return (0, "");
}

.P2
This is intentionally simple-minded, to focus on the language
rather than efficiency or flexibility.
The function
.CW "Table.alloc" 
creates and returns a 
.CW "Table" 
with a specified size and an array of elements,
each of which is a list of
.CW "(string," 
.CW "string)" .
.LP
The
.CW "hash" 
function is trivial; the only interesting point
is the
.CW "len" 
operator, which returns the number of items in a string, array or list.
For a string, 
.CW "len" 
.CW "s" 
is the number of Unicode characters.
.LP
The
.CW "self" 
declaration says that the first
argument of every call of this function is implicit, and refers to the
value itself; this argument does not appear in the actual parameter list at any call site.
.CW "Self" 
is similar to
.CW "this" 
in C++.
.LP
The 
.CW "lookup" 
function searches down the appropriate list for
an instance of the
.CW "name" 
argument.
If a match is found, 
.CW "lookup" 
returns a tuple consisting of 1 and the value field;
if no match is found, it returns a tuple of 0 and an empty string.
These return types match the function return type,
.CW "(int," 
.CW "string)" .
.LP
The line
.P1
	(tname, tval) := hd p;
.P2
shows a tuple on the left side of a declaration-assignment.
This splits the pair of strings referred to by
.CW "hd" 
.CW "p" 
into components and assigns them to the newly declared variables
.CW "tname" 
and 
.CW "tval" .
.LP
The
.CW "add" 
function is similar;
it searches the right list for an instance of
the name.
If none is found,
.P1
	ht.tab[h] = (name, val) :: ht.tab[h];
.P2
combines the name and value into a tuple, then uses
.CW "::" 
to stick it on the front of the proper list.
.LP
The line
.P1
	(tname, nil) := hd p;
.P2
in the loop body is a less obvious use of a tuple.
In this case, only the first component, the name,
is assigned, to a variable
.CW "tname" 
that is declared here.
The other component is ``assigned'' to 
.CW "nil" ,
which causes it to be ignored.
.LP
The line
.P1
	# illegal: hd p = (tname, val);
.P2
is commented out because it's illegal:
Limbo does not permit the assignment of a new name-value
to a list element;
list elements are immutable.
.LP
To create a new 
.CW "Table" ,
add some values, then retrieve one, we can write:
.P1
	nvtab = Table.alloc(101);	# make a Table

	nvtab.add("Rob", "Pike");
	nvtab.add("Howard", "Trickey");
	(p, phil) := nvtab.lookup("Phil");
	(q, sean) := nvtab.lookup("Sean");
.P2
Note that the
.CW "ref" 
.CW "Table" 
argument does not appear in these calls;
the
.CW "self" 
mechanism renders it unnecessary.
Remember that a module using
.CW Table
must
.CW import
it from some instance of
.CW Hashtab ,
or qualify all references to it by a module value.
.NH 2
An AWK-like Input Module
.LP
This example presents a simple module based on Awk's input mechanism:
it reads input a line at a time from a list of of files,
splits each line into an array of
.CW "NF+1" 
strings (the original input line and the individual fields), and
sets
.CW "NF" ,
.CW "NR" ,
and
.CW "FILENAME" .
It comes in the usual two parts, a module:
.P1
.nr dP \n(dP+1
.nr dT 4
Awk: module
{
	PATH:		con "/usr/bwk/awk.dis";

	init:		fn(args: list of string);
	getline:	fn() : array of string;
	NR:		fn() : int;
	NF:		fn() : int;
	FILENAME:	fn() : string;
};
.P2
.nr dP \n(dP-1
.nr dT 8
and an implementation:
.nr dP \n(dP+1
.nr dT 4
.P1
implement Awk;

include "sys.m";
	sys:	Sys;
include "bufio.m";
	bufio: Bufio;
Iobuf: import bufio;
	iobuf:	ref Iobuf;

include "awk.m";

_NR:		int;
_NF:		int;
_FILENAME:	string;
args:		list of string;

.P3
init(av: list of string)
{
	args = tl av;
	if (len args == 0)	# no args => stdin
		args = "-" :: nil;

	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
}

.P3
getline() : array of string
{
	t := array[100] of string;
	fl: list of string;

  top:
	while (args != nil) {
		if (_FILENAME == nil) {	# advance to next file
			_FILENAME = hd args;
			if (_FILENAME == "-")
				iobuf = bufio->fopen(sys->fildes(0), bufio->OREAD);
			else
				iobuf = bufio->open(_FILENAME, bufio->OREAD);
			if (iobuf == nil) {
				sys->fprint(sys->fildes(2), "can't open %s: %r\en", _FILENAME);
				args = nil;
				return nil;
			}
		}

.P3
		s := iobuf.gets('\en');
		if (s == nil) {
			iobuf.close();
			_FILENAME = nil;
			args = tl args;
			continue top;
		}

.P3
		t[0] = s[0:len s - 1];
		_NR++;
		(_NF, fl) = sys->tokenize(t[0], " \et\en\er");
		for (i := 1; fl != nil; fl = tl fl)
			t[i++] = hd fl;
		return t[0:i];
	}
	return nil;
}

NR() : int  { return _NR; }
NF() : int  { return _NF; }
FILENAME() : string { return _FILENAME; }
.P2
.nr dT 8
.nr dP \n(dP-1
Since 
.CW "NR" ,
.CW "NF" 
and
.CW "FILENAME" 
should not be modified by users, they
are accessed as functions; the actual variables have
related names like
.CW "_NF" .
It would also be possible to make them ordinary variables
in the 
.CW "Awk" 
module, and refer to them via a module value (i.e.,
.CW awk->NR ).
.LP
The 
.CW "tokenize" 
function in the line
.P1
	(_NF, fl) = sys->tokenize(t[0], " \et\en\er");
.P2
breaks the argument string
.CW "t[0]" 
into tokens, as separated by the characters of the second argument.
It returns a tuple consisting of a length and a list
of tokens.
Note that this module has an
.CW "init" 
function that must be called explicitly before
any of its other functions are called.
.NH 2
A Simple Formatter
.LP
This program is a simple-minded text formatter, modeled after
.CW "fmt" ,
that tests the Awk module:
.P1
implement Fmt;

include "sys.m";
	sys: Sys;
include "draw.m";

Fmt: module
{
	init:	fn(nil: ref Draw->Context, args: list of string);
};

include "awk.m";
	awk: Awk;
	getline, NF: import awk;

out:	array of string;
nout:	int;
length: int;
linelen := 65;

.P3
init(nil: ref Draw->Context, args: list of string)
{
	t: array of string;
	out = array[100] of string;

	sys = load Sys Sys->PATH;
	awk = load Awk Awk->PATH;
	if (awk == nil) {
		sys->fprint(sys->fildes(2), "fmt: can't load %s: %r\en",
			Awk->PATH);
		raise "fail:load";
	}
	awk->init(args);

	nout = 0;
	length = 0;
	while ((t = getline()) != nil) {
		nf := NF();
		if (nf == 0) {
			printline();
			sys->print("\en");
		} else for (i := 1; i <= nf; i++) {
			if (length + len t[i] > linelen)
				printline();
			out[nout++] = t[i];
			length += len t[i] + 1;
		}
	}
	printline();
}
.P3
printline()
{
	if (nout == 0)
		return;
	for (i := 0; i < nout-1; i++)
		sys->print("%s ", out[i]);
	sys->print("%s\en", out[i]);
	nout = 0;
	length = 0;
}
.P2
The functions
.CW "getline" 
and
.CW "NF" 
have been imported so their names need no qualification.
It is more usual Limbo style to use explicit references such as
.CW sys->read
or
.CW Bufio->EOF
for clarity, and import only adts (and perhaps commonly used constants).
.NH 2
Channels and Communications
.LP
Another approach to a formatter is to use one process to fetch words and 
pass them to another process that formats and prints them.
This is easily done with a channel, as in this
alternative version:
.P1
# declarations omitted...

WORD, BREAK, EOF: con iota;
wds: chan of (int, string);

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;

	stdin := sys->fildes(0);
	iob = bufio->fopen(stdin, bufio->OREAD);

	wds = chan of (int, string);
	spawn getword(wds);
	putword(wds);
}

.P3
getword(wds: chan of (int, string))
{
	while ((s := iob.gets('\en')) != nil) {
		(n, fl) := sys->tokenize(s, " \et\en");
		if (n == 0)
			wds <-= (BREAK, "");
		else for ( ; fl != nil; fl = tl fl)
			wds <-= (WORD, hd fl);
	}
	wds <-= (EOF, "");
}

.P3
putword(wds: chan of (int, string))
{
	for (length := 0;;) {
		(wd, s) := <-wds;
		case wd {
		BREAK =>
			sys->print("\en\en");
			length = 0;
		WORD =>
			if (length + len s > 65) {
				sys->print("\en");
				length = 0;
			}
			sys->print("%s ", s);
			length += len s + 1;
		EOF =>
			sys->print("\en");
			exit;
		}
	}
}
.P2
This omits declarations and error checking in the interest
of brevity.
.LP
The channel passes a tuple of
.CW "int" , (
.CW "string" );
the
.CW "int" 
indicates what kind of string is present \-
a real word, a break caused by an empty input line,
or
.CW "EOF" .
.LP
The
.CW "spawn" 
statement creates a separate process by calling the specified function;
except for its own stack,
this process shares memory with the process that spawned it.
Any synchronization between processes is handled by channels.
.LP
The operator
.CW "<-=" 
sends an expression to a channel;
the operator
.CW "<-" 
receives from a channel.
(Receive is combined here with
.CW ":="
to receive a tuple, and assign its elements to newly-declared variables.)
In this example, 
.CW "getword" 
and
.CW "putword" 
alternate, because each input word
is sent immediately on the shared channel,
and no subsequent word is processed until the previous one has been
received and printed.
.LP
The 
.CW "case" 
statement consists of a list of case values,
which must be string or numeric constants, followed by
.CW "=>" 
and associated code.
The value 
.CW "*" 
(not used here) labels the default.
Multiple labels can be used, separated by the
.CW "or" 
operator,
and ranges of values can appear delimited by
.CW "to" ,
as in
.P1
	'a' to 'z' or 'A' to 'Z' =>
.P2
Remember that control does not flow from one case arm to the next, unlike C,
thus no
.CW break
statements appear.
.NH 2
Tk and Interface Construction
.LP
Inferno supports a rather complete implementation of
the Tk interface toolkit developed by John Ousterhout.
In other environments, Tk is normally accessed from
Tcl programs, although there are also versions for Perl,
Scheme and other languages that call Ousterhout's C code.
The Inferno Tk was implemented from scratch, and is meant to be called
from Limbo programs.
As we saw earlier,
there is a module declaration
.CW "tk.m" 
and a kernel module 
.CW "Tk" .
.LP
The
.CW "Tk" 
module provides all the widgets of the original Tk
with almost all their options,
the 
.CW "pack" 
command for geometry management,
and the
.CW "bind" 
command for attaching code to user actions.
It also provides a
.CW grid
command to simplify the common case of objects arranged in a matrix or grid.
In this implementation
.CW "Tk" 
commands are
written as strings and presented to one function,
.CW "tk->cmd" ;
Limbo calls this function and captures
its return value, which is the string that the Tk command produces.
For example, widget creation commands like
.CW "button" 
return the widget name, so this will be the string
returned by
.CW "tk->cmd" .
.LP
There is one unconventional aspect:
the use of channels to send data and events from the interface
into the Limbo program.
To create a widget, as we saw earlier, one writes
.P1
tk->cmd("button .b -text {Push me} -command {send cmd .bpush}");
.P2
to create a button
.CW ".b" 
and attach a command to be executed when the button is pushed.
That command sends
the (arbitrary) string
.CW ".bpush" 
on the channel named
.CW "cmd" .
The Limbo code that reads from this channel will look
for the string
.CW ".bpush" 
and act accordingly.
The function
.CW "tk->namechan" 
establishes a correspondence between a Limbo channel value
and a channel named as a string in the Tk module.
When an event occurs in a Tk widget with a
.CW "-command" 
option,
.CW "send" 
causes the string to be sent on the channel and the Limbo code
can act on it.
The program will often use a
.CW "case" 
to process the strings that might appear on the channel,
particularly when the same channel is used for several widgets.
.LP
We observed earlier that
.CW Tk
provides a user interface for an application's window,
but there might be many windows on the screen.
Normally, a graphical application is meant to run under
the window manager
.CW "wm" 
as a window that can be managed,
reshaped, etc.
This is done by calling functions in the module
.CW "Tkclient" ,
which provides the interface between
.CW Tk
and
.CW wm .
.LP
Several functions must be called to create a window,
put it on the screen, and start giving it input.
We have already seen
.CW Tkclient 's
.CW toplevel
for window creation and
.CW onscreen
to give a window space on the screen.
Input arrives from several sources:
from the mouse and keyboard, from the
higher-level Tk widgets such as buttons,
and from the window manager itself.
In Limbo, each input source is represented by a channel, either given to the program
by the window manager, or associated with one by
.CW namechan ,
as above.
.LP
This is all illustrated in the complete program below, which
implements a trivial version of Etch-a-Sketch, shown in action in Figure 2.
.FG "f3.ps" 4.8i
.ce
.I "Figure 2. Etch-a-Sketch display."
.fg
.nr dT 4
.nr dP \n(dP+1
.P1
implement Etch;

include "sys.m";
	sys: Sys;
include "draw.m";
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;

Etch: module
{
        init:   fn(ctxt: ref Draw->Context, args: list of string);
};
.P3
init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;

	tkclient->init();

	(t, winctl) := tkclient->toplevel(ctxt, nil, "Etch", Tkclient->Appl);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");
	tk->cmd(t, "canvas .c -height 400 -width 600 -background white");
	tk->cmd(t, "frame .f");
	tk->cmd(t, "button .f.c -text {Clear} -command {send cmd clear}");
	tk->cmd(t, "button .f.d -text {Done} -command {send cmd quit}");
	tk->cmd(t, "pack .f.c .f.d -side left -fill x -expand 1");
	tk->cmd(t, "pack .c .f -side top -fill x");
	tk->cmd(t, "bind .c <ButtonPress-1> {send cmd b1down %x %y}");
	tk->cmd(t, "bind .c <Button-1-Motion> {send cmd b1motion %x %y}");
	tk->cmd(t, "update");

	tkclient->startinput(t, "ptr" :: "kbd" :: nil);
	tkclient->onscreen(t, nil);

	lastx, lasty: int;
	for (;;) {
		alt {
	    	s := <-cmd =>
			(nil, cmdstr) := sys->tokenize(s, " \et\en");
			case hd cmdstr {
			"quit" =>
				exit;
			"clear" =>
				tk->cmd(t, ".c delete all; update");
			"b1down" =>
				lastx = int hd tl cmdstr;
				lasty = int hd tl tl cmdstr;
				cstr := sys->sprint(".c create line %d %d %d %d -width 2",
					lastx, lasty, lastx, lasty);
				tk->cmd(t, cstr);
			"b1motion" =>
				x := int hd tl cmdstr;
				y := int hd tl tl cmdstr;
				cstr := sys->sprint(".c create line %d %d %d %d -width 2",
					lastx, lasty, x, y);
				tk->cmd(t, cstr);
				lastx = x; lasty = y;
			}

		p := <-t.ctxt.ptr =>
			tk->pointer(t, *p);

		c := <-t.ctxt.kbd =>
			tk->keyboard(t, c);

		ctl := <-winctl or
		ctl = <-t.ctxt.ctl or
		ctl = <-t.wreq =>
			tkclient->wmctl(t, ctl);
 		}
		tk->cmd(t, "update");
	}
}
.P2
.nr dT 8
.nr dP \n(dP-1
.LP
The function
.CW "toplevel" 
returns a tuple containing the
.CW Tk->Toplevel
for the new window and a channel upon which the
window manager will send messages for events such as
hitting the exit button.
An earlier example assigned the channel value to
.CW nil ,
discarding it; here it is assigned the name
.CW winctl .
The parameters to
.CW toplevel
includes a graphics context
.CW ctxt
where the window will be created,
a configuration string (simply
.CW nil
here),
the program name (which appears in the window's ``title bar'' if it has one),
and a value
.CW Tkclient->Appl
that denotes a style of window suitable for most applications.
Note that
.CW ctxt
was one of the arguments to
.CW init .
(We do not use the argument list for
.CW init ,
and so declare it as
.CW nil ).
.LP
The program creates a canvas for drawing,
a button to clear the canvas, and a button to quit.
The sequence of calls to
.CW "tk->cmd" 
creates the picture and sets up the bindings.
The buttons are created with a
.CW -command
to send a suitable string on channel
.CW cmd ,
and two
.CW bind
commands make the same channel the target
for messages about mouse button presses and movement in the canvas.
Note the
.CW %x
and
.CW %y
parameters in the latter case to include the mouse's coordinates in the string.
.LP
The window manager sends keyboard and mouse input
to the currently selected window using two more channels
.CW t.ctxt.kbd
and
.CW t.ctxt.ptr .
A further channel
.CW t.wreq
is used by the
.CW Tk
module itself to request changes to the window displaying
.CW Toplevel
.CW t .
.LP
Now there are many channels watching events:
one for the buttons and canvas created by the drawing program
itself, one for the mouse,
and three for window management.
We use an
.CW "alt" 
statement to select from events on any of those channels.
The expression
.P1
s := <-cmd
.P2
declares a variable 
.CW "s" 
of the type carried by the channel
.CW "cmd" ,
i.e., a
.CW "string" ;
when a string is received on the channel, the assignment is executed,
and the subsequent
.CW case
decodes the message.
The channel
.CW t.ctxt.ptr
carries references to
.CW Draw->Pointer
values, which give the state and position of the pointing device
(mouse or stylus).
They are handed as received to
.CW tk->pointer
for processing by Tk.
Similarly, Unicode characters from the keyboard are given to Tk using
.CW tk->keyboard .
Internally, Tk hands those values on to the various widgets for processing, possibly
resulting in messages being sent on one of the other channels.
Finally, a value received from any of the
.CW "winctl" ,
.CW t.ctxt.ctl
or
.CW t.wreq
channels is passed back to
.CW Tkclient 's
.CW "wmctl" 
function to be handled there.
.LP
As another example,
here is the startup code for an implementation of
Othello, adapted from a Java version
by Muffy Barkocy, Arthur van Hoff, and Ben Fry.
.nr dT 4
.nr dP \n(dP+1
.P1
init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;

	sys->pctl(Sys->NEWPGRP, nil);

	tkclient->init();
.P3
	(t, winctl) := tkclient->toplevel(ctxt, nil, "Othello", Tkclient->Appl);
.P3
	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");
	tk->cmd(t, "canvas .c -height 400 -width 400 -background green");
	tk->cmd(t, "frame .f");
	tk->cmd(t, "label .f.l -text {Othello?} -background white");
	tk->cmd(t, "button .f.c -text {Reset} -command {send cmd Reset}");
	tk->cmd(t, "button .f.d -text {Quit} -command {send cmd Quit}");
	tk->cmd(t, "pack .f.l .f.c .f.d -side left -fill x -expand 1");
	tk->cmd(t, "pack .c .f -side top -fill x");
	tk->cmd(t, "bind .c <ButtonRelease-1> {send cmd B1up %x %y}");

	for (i := 1; i < 9; i++)
	for (j := 1; j < 9; j++) {
		coord := sys->sprint("%d %d %d %d",
			SQ*i, SQ*j, SQ*(i+1), SQ*(j+1));
		tk->cmd(t, ".c create rectangle " + coord +
			" -outline black -width 2");
	}
	tk->cmd(t, "update");
	lasterror(t, "init");
	tkclient->startinput(t, "ptr" :: "kbd" :: nil);
	tkclient->onscreen(t, nil);

	board = array[10] of {* => array[10] of int};
	score = array[10] of {* => array[10] of int};
	reinit();
.P3
	for (;;) {
		alt {
		s := <- cmd =>
			(n, l) := sys->tokenize(s, " \et");
			case hd l {
			"Quit" =>
				exit;
			"Reset" =>
				reinit();
			"B1up" =>
				x := int hd tl l;
				y := int hd tl tl l;
				mouseUp(int x, int y);
			}

		p := <-t.ctxt.ptr =>
			tk->pointer(t, *p);

		c := <-t.ctxt.kbd =>
			tk->keyboard(t, c);

		ctl := <-winctl or
		ctl = <-t.ctxt.ctl or
		ctl = <-t.wreq =>
			tkclient->wmctl(t, ctl);
 		}
	}
}
.P2
.nr dP \n(dP-1
.nr dT 4
.FG "f2.ps" 4.8i
.ce
.I "Figure 3. Screen shot of Inferno display showing Othello window."
.fg
.LP
If some call to the
.CW "Tk" 
module results in an error,
an error string is made available in a pseudo-variable
.CW "lasterror" 
maintained by
.CW "Tk" .
When this variable is read, it is reset.
The function 
.CW "lasterror" 
shows how to test and print this variable:
.P1
lasterror(t: ref Tk->Toplevel, where: string)
{
	s := tk->cmd(t, "variable lasterror");
	if (s != nil)
		sys->print("%s: tk error %s\en", where, s);
}
.P2
In general, the Inferno implementation of
.CW "Tk" 
does not provide variables except for a few special ones like this.
The most common instance is a variable that links
a set of radiobuttons.
.NH 2
Acknowledgements
.LP
I am very grateful to
Steven Breitstein,
Ken Clarkson,
Sean Dorward,
Eric Grosse,
Doug McIlroy,
Rob Pike,
Jon Riecke,
Dennis Ritchie,
Howard Trickey,
Phil Winterbottom,
and
Margaret Wright
for explaining mysteries of Limbo and Inferno
and for valuable suggestions on this paper.
