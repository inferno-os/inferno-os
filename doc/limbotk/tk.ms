.nr dT 4
.nr P1 .2i
.de EX
.nr x \\$1v
\\!h0c n \\nx 0
..
.nr Pd \n(PD
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
.de Tk		\" Tk option name and option
.CW \\$1
.I \\$2 \\$3
..
.de Tc		\" Tk command string
.IP "\\f(CW\\$1\\fP \\$2" \w'\f(CWburble\fP'u
.br
..
.de Kp		\" Keypress
.IP "\\f(CW\\$1\\fP" \w'\f(CWKeypress\fP'u
.br
..
.de d0		\" no gap between paragraphs
.nr PD 0
..
.de d1		\" restore gap
.nr PD \n(Pd
..
.ds Op "\fR[\fP\fIoptions ...\fP\fR]\fP
.TL
An Overview of Limbo/Tk
.AU
.I "Lucent Technologies Inc."
.br
Revised June 2000 by Vita Nuova
.SH
Overview
.LP
Limbo/Tk is a concise and powerful way to construct graphical user interfaces without directly using the Draw module primitives.
Standard interfaces can quickly be created from collections of menus, buttons, and other widgets that are part of Limbo/Tk's visual toolkit.
It is modelled on Ousterhout's Tk 4.0 [1,2], commonly deployed
with the scripting language Tcl as `Tcl/Tk'.
Although inspired by Tk 4.0, Inferno's Tk implementation is new, and unrelated to Ousterhout's.
It is intended to be used with the new programming language Limbo, not Tcl.
Limbo/Tk applications make
extensive use of Limbo's concurrent programming constructions and data structures,
and that is reflected in the interface.
Section 9 of Volume 1 of the
.I "Inferno Programmer's Manual"
provides a detailed reference for Limbo/Tk.
This paper provides an overview of its use in some simple staged examples, and
concludes with
a summary of the differences between the Limbo/Tk implementation and Tk 4.0.
In the rest of this paper, `Tk' refers to Limbo/Tk, and `Tk 4.0' refers to Ousterhout's
original implementation.
.NH 1
The Limbo/Tk environment
.LP
Limbo applications access Tk by means of a built-in module,
.CW "$Tk" .
The standard distribution also includes the window manager
.CW "wm"
and the Limbo module
.CW Wmlib .
Unlike
.CW Tk ,
.CW Wmlib
is not built-in but implemented in Limbo by
.CW /appl/lib/wmlib.b .
It simplifies and standardises the construction of windowed applications;
it also contains some graphical devices such as tabbed notebooks not provided
directly by Limbo/Tk.
The essentials of both
.CW Tk
and
.CW Wmlib
are discussed here.
.LP
Programmers usually need only three functions from the
.CW Tk
module:
.IP •
.CW toplevel
.br
Creates a graphical window \- a Tk `top level' widget \-
that can be used to build a Limbo/Tk application.
The function returns a reference to an adt
.CW "\%Tk->Toplevel"
adt that represents the window in subsequent Tk operations.
.IP •
.CW cmd
.br
Creates and arranges graphic objects within the toplevel window by processing Limbo/Tk command strings.
The interface to Tk is primarily the passing of strings between
the application and Tk
of the toolkit using
.CW cmd .
Each call to
.CW cmd
returns a string representing the result of the Tk command;
a string starting with
.CW ! ' `
diagnoses an error.
.IP •
.CW namechan
.br
Gives a name within Tk (in the scope of a given window) to a Limbo
.CW "chan of string"
that Tk commands can use to send data to a Limbo program.
.LP
Other functions in the module have more specialised uses that will not be discussed here.
For instance,
.CW "mouse"
and
.CW "keyboard"
are used by a window manager to send mouse and keyboard events
to the Tk implementation for distribution to applications.
.LP
Even
.CW toplevel
is not commonly used in the window manager environment:
a function
.CW Wmlib->titlebar
provides the usual interface to
.CW toplevel .
The low-level interface will be described first, for completeness,
then the normal case using
.CW titlebar .
.NH 1
Basic Limbo/Tk
.LP
This section shows a simple Tk application that uses only the fundamental Tk functions.
.NH 2
Preliminaries
.LP
The example assumes that the
.CW "Tk"
module is loaded as
.CW "tk" :
.P1
include "tk.m";
	tk:	Tk;
	...
init(ctxt: ref Draw->Context, nil: list of string)
{
	tk =  load Tk Tk->PATH;
	...
}
.P2
.NH 2
Creating a toplevel
.LP
The following fragment makes the Limbo identifier
.CW "top"
refer to a new
.CW "ref Tk->Toplevel"
for use in later Tk commands:
.P1
	top := tk->toplevel(ctxt.screen, "-x 150 -y 150");
.P2
The upper left corner of this window will be at point (150, 150), where (0,0) is the upper left corner of the screen;
.I x
coordinates increase from left to right, and
.I y
coordinates increase from top to bottom.
.LP
In general,
.CW "Tk->toplevel"
takes a screen argument and a string containing further options, and it returns a reference to a top-level Limbo/Tk widget on the given screen.
The options argument contains
.Tk -option value
pairs, such as
.CW "-relief raised" .
As well as the generic options,
.CW "toplevel"
accepts the options
.Tk -x int
and
.Tk -y int
to specify the upper left corner of the toplevel widget, where (0,0) is the top left corner of the screen,
and
.Tk -debug bool
to cause a trace of all Tk commands to be printed,
if the boolean value is true.
.NH 2
Creating a named channel to Tk
.LP
The following fragment creates a
.CW "chan of string"
called
.CW "c" ,
then associates the name
.CW "cmdchan"
within Tk with the Limbo channel
.CW "c" :
.P1
	c := chan of string;
	tk->namechan(top, c, "cmdchan");
.P2
The named channel
.CW "cmdchan"
can now be used in a special Tk
.CW send
command
to send strings to be processed by a Limbo program, typically notifying it of an event.
Note that the Limbo identifer name need not match the name given to Tk,
although it is invariably easier to follow the code if the two are the same.
.NH 2
Defining and positioning widgets
.LP
The following fragment uses
.CW "tk->cmd"
to define four widgets: two buttons, a label, and an entry widget. The widgets are positioned in their parent window (in this case the toplevel window
.CW "top" )
using the Tk command
.CW "pack" :
.P1
.ps -1
.vs -1
	\fI# define widgets\fP
	tk->cmd(top, "button .b1 -text Exit -command {send cmdchan exit}");
	tk->cmd(top, "button .b2 -text Send -command {send cmdchan send}");
	tk->cmd(top, "label .l -text {Name: }");
	tk->cmd(top, "entry .e");

	\fI# bind newline character in entry widget to command\fP
	tk->cmd(top, "bind .e <Key-\en> {send cmdchan send}");

	\fI# pack widgets\fP
	tk->cmd(top, "pack .b1 .b2 .l .e -side left; update");
.ps +1
.vs +1
.P2
This particular pack command packs the widgets named
.CW ".b1" ,
.CW ".b2" ,
.CW ".l" ,
and
.CW ".e"
into the
.CW "top"
window beginning at the left side. The
.CW "update"
command forces Tk to update the screen right away. The result is shown in Figure 1.
.FG "f1.ps" 0.21i
.ce
.I "Figure 1. Two buttons, a label and an entry widget."
.fg
.LP
Entering a newline (`return' or `enter' key)\-the character
.CW \en ' `
in Limbo\-
in the entry box results in the execution of the Tk command
.CW "{send cmdchan send}" ,
because of the binding set by
.CW "bind .e <Key-\en>"
previously executed by
.CW tk->cmd .
The
.CW "bind"
command is often used to bind specific widget events (including key presses, mouse button presses, and mouse motion) to Tk
.CW send
commands.
.NH 2
Processing widget events
.LP
This next fragment defines what will happen when a user selects either the
.CW "Exit"
or the
.CW "Send"
buttons. The
.CW "Exit"
behaviour is simple: the program ends. If a user touches
.CW Send ,
the program executes
.CW "tk->cmd"
to get whatever text is in the entry widget
.CW ".e"
then prints it to standard output.
.P1
	for(;;) {
		s := <- c;
		case s {
		"exit" =>
			return;

		"send" =>
			sys->print("name was: %s\en", tk->cmd(top, ".e get"));
		}
	}
.P2
.NH 1
Example - using Tk and Wmlib
.LP
This section uses both Tk and Wmlib to create a simple window manager application with a titlebar, including resize and exit buttons.
This is the usual way to create new windows.
.NH 1
Preamble
.LP
The example assumes that the
.CW "Tk"
module is loaded as before, as module variable
.CW "tk" ,
but furthermore that the
.CW "Wmlib"
module is also loaded, as
.CW "wmlib" :
.P1
include "tk.m";
	tk:	Tk;
include "wmlib.m";
	wmlib: Wmlib;
	...
	tk =  load Tk  Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	wmlib->init();
.P2
Note that
.CW wmlib->init
is called once to initialise the
.CW wmlib
module just loaded, before any other functions are called.
.LP
In window manager applications the
.CW Tk->toplevel
function is not normally used directly.
Instead, a window manager interface is used to create both
the top level widget and a channel to receive events from the window manager.
The
.CW titlebar
function has the signature:
.ps -1
.vs -1
.P1
	titlebar(scr: Draw->Screen, tkargs: string, title: string, buts: int):
		(ref Tk->Toplevel, chan of string);
.P2
.vs +1
.ps +1
The
.CW Screen
is the one on which the window is to be created, normally the
one passed in the
.CW Context
parameter to a program's
.CW init
function.
The
.I tkargs
parameter can control the position and appearance of the window,
but is best left nil (or the empty string) to use the window manager's
defaults (see
.I wmlib (2)
for details otherwise),
including automatic placement.
The
.I title
string gives the title that appears in the title bar.
Finally,
.I buts
is a bit set that selects the buttons to appear.
The value
.CW Wmlib->Appl
gives the usual resize and hide buttons;
the exit (delete) button always appears.
The following is used in the example:
.P1
	(top, titlechan) := wmlib->titlebar(ctxt.screen, nil,
					"Text Browser", Wmlib->Appl);
.P2
Note that
.CW titlebar
returns a tuple.
The first element is a reference to the Tk top level widget
for use in later Tk commands.
The second element of the tuple
is a Limbo channel of type
.CW "chan of string"
that passes window manager events to the application.
.LP
The channel
.CW "titlechan"
is used by
.CW "wmlib"
to send messages, but it is normally necessary
to create a channel to Tk to receive events from widgets the application creates:
.P1
	cmdchan := chan of string;
	tk->namechan(top, cmdchan, "cmdchan");
.P2
.NH 2
Defining and positioning widgets
.LP
The function
.CW "Wmlib->tkcmds"
takes two arguments, a
.CW "ref Tk->Toplevel"
that identifies a top level window,
and an
.CW "array of string" .
Each element of the array is a Tk command acceptable to
.CW "Tk->cmd" ;
.CW Wmlib->tkcmds
simply applies it
to each element of the array.
.LP
Most of the following fragment consists of Tk command strings that are members of the array of strings
.CW "tk_config" .
The comments describe the widgets being created. Not all widgets and menu items in this example are functional.
The last line executes the array of commands using
.CW "wmlib->tkcmds" :
.nr dP +1
.nr dV +1p
.P1
	tk_config := array[] of {

	\fI# define menubar frame, widget frame, text frame\fP
	"frame .mbar -relief groove -bd 2",
	"frame .w",
	"frame .text",

	\fI# define and pack menus\fP
	"menubutton .file -text File -menu .file.m",
	"menubutton .edit -text Edit -menu .edit.m",
	"menubutton .help -text Help -menu .help.m",

	"menu .file.m",
	".file.m add command -label Send -command {send cmdchan send}",
	".file.m add command -label Exit -command {send cmdchan exit}",
	"menu .edit.m",
	".edit.m add command -label Cut",

	"menu .help.m",
	".help.m add command -label Index -underline 0",

	"pack .file .edit -side left -in .mbar; update",
	"pack .help -side right -in .mbar",
.P3

	\fI# define and pack buttons and text entry box (for file name)\fP
	"button .b1 -text Send -command {send cmdchan send}",
	"button .b2 -text Open -command {send cmdchan open}",
	"label .l -text {Name: }",

	"entry .e",
	"bind .e <Key-\en> {send cmdchan open}",

	"pack .b1 .b2 .l .e -side left -in .w",
.P3

	\fI# define and pack text panel and its scrollbar\fP
	"text .t -yscrollcommand {.scroll set} -bg white",
	"scrollbar .scroll -command {.t yview}",
	"pack .scroll -side left -fill y -in .text",
	"pack .t -side right -in .text -expand 1 -fill both",

	\fI# pack frames\fP
	"pack .text -side bottom -fill both -expand 1",
	"pack .mbar .w -fill x; update",
	"pack propagate . 0",
	};

	\fI# run the Tk commands\fP
	wmlib->tkcmds(top, tk_config);
.P2
.nr dP -1
.nr dV -1p
The result of executing these Tk commands is shown in Figure 2.
.LP
The arrays defining Tk widgets are sometimes made global to a module
when they can sensibly be used by several functions.
It is also common to use small Limbo functions to replicate
similar widgets by building Tk commands from the value of parameters,
using Limbo string concatenation
or
.CW sys->sprint .
.FG "f2.ps" 2.16i
.ce
.I "Figure 2. A Wm application with a menu bar, a tool bar, and a text window."
.fg
.LP
.NH 2
Processing widget events
.LP
This fragment uses an
.CW "alt"
block to wait for strings to arrive from either
.CW "titlechan"
or
.CW "cmdchan" .
.LP
When a string is received on
.CW "titlechan" ,
the
.CW "case"
statement either handles it directly (as with
.CW exit )
or passes it to
.CW "wmlib->titlectl"
for normal handling by the window manager.
.LP
When a string is received on
.CW cmdchan ,
the program acts accordingly: it writes the text in the entry widget to standard output
.CW send ); (
calls
.CW "do_open"
to open the file name currently in the entry box
.CW open ); (
or returns from the processing loop
.CW exit ). (
.P1
	for(;;) {
		alt {
		s := <-titlechan =>	\fI# message from title bar buttons\fP
			case s {
			"exit" =>
				return;
			* =>
				wmlib->titlectl(top,s);
			}

		com := <-cmdchan =>	\fI# message from widgets created above\fP
			case com {
			"send" =>
				sys->print("name was: %s\en", tk->cmd(top, ".e get"));
			"open" =>
				do_open(top, tk->cmd(top, ".e get"));
			"exit" =>
				return;
			}
		}
	}
.P2
Although this example uses a Tk text entry widget,
.CW Wmlib
provides a function
.CW filename
that pops up a graphical device that allows a user to
select a file by typing a name, browsing the file system, or a mixture of both.
See
.I wmlib (2)
for details.
.NH 2
Putting text into the text widget
.LP
The
.CW "do_open"
function below uses
the buffered I/O module
.CW Bufio
to read lines from the file named in the entry widget and add them to the text currently in the text widget
.CW ".t" .
.P1
do_open(top: ref Tk->Toplevel, file: string)
{
	iofd := bufio->open(file, Bufio->OREAD);
	if(iofd == nil){
		wmlib->dialog(top, "error -fg red", "Open file",
			sys->sprint("%s: %r", file), 0, "Ok"::nil);
		return;
	}

	tk->cmd(top, ".t delete 1.0 end");
	tk->cmd(top, "cursor -bitmap cursor.wait");

	for(;;){
		line := iofd.gets('\en');
		if(line == nil)
			break;
		tk->cmd(top, ".t insert end '" + line);
	}
	tk->cmd(top, "cursor -default");
}
.P2
If the file cannot be opened,
.CW do_open
calls
.CW wmlib->dialog
to pop up a diagnostic message panel, rather than (say) printing a message to standard
error,
and returns.
If the file was opened,
.CW do_open
deletes the current
contents of the frame, and reads the
file into it, inserts one line at a time.
Tk allows the data inserted to contain embedded newlines, and
a more efficient implementation could read blocks
of data from the file and insert them, but some care is required.
A text file in Inferno contains Unicode characters in UTF-encoding, and the
bytes of a single character might be split across separate reads.
.CW Iobuf.gets
by contrast is guaranteed to reassemble complete Unicode characters from
the buffered input stream.
A program using
.CW Iobuf.read
(or
.CW Sys->read )
to fetch blocks of data would typically use
.CW Sys->utfbytes
to find maximal sequences of UTF-encoded characters
and insert large chunks of text at once.
See the function
.CW loadtfile
in
.CW /appl/wm/edit.b
for example.
.NH 1
Limbo/Tk command syntax
.LP
Once a toplevel widget has been built, an application calls
.CW "tk->cmd"
to issue commands to Tk and receive results.
This section describes in more detail the contents of the string argument
that conveys the commands.
.NH 2
Command strings
.LP
The command string may contain one or more commands, separated by semicolons. A semicolon is not a command separator when it is nested in braces
.CW "{}" ) (
or brackets
.CW "[]" ), (
or it is escaped by a backslash (\e).
.LP
Each command is divided into
.I "words" :
sequences of characters separated by one or more blanks or tabs,
subject to the following quoting rules:
.IP
.br
A word beginning with an opening brace
.CW { ) (
continues until the balancing closing brace
.CW } ) (
is reached.
The outer brace characters are stripped.
A backslash
.CW \e ) (
can be used to escape a brace, preventing special interpretation.
.IP
.br
A word beginning with an opening bracket
.CW [ ) (
continues until the balancing closing bracket
.CW ] ) (
is reached. The enclosed string is then evaluated as if it were a command string, and the resulting value is used as the contents of the word.
.IP
.br
At any point in the command string a single quote (\f5'\fP) causes the rest of the string to be treated as one word.
.LP
Single commands are executed in order until they are all done or an error is encountered. By convention, an error is signalled by a return value starting with an exclamation mark. The return value from
.CW "cmd"
is the return value of the first error-producing command or else the return value of the final single command.
.LP
To execute a single command, the first word is examined. It can be one of the following:
.IP \(bu
One of the following widget creating commands:
.RS
.TS
lf(CW) lf(CW) .
button	menu
canvas	menubutton
checkbutton	radiobutton
entry	scale
frame	scrollbar
label	text
listbox
.TE
The second word of each of these commands is the name of the widget to be created. The remaining words are option/value pairs.
.RE
.IP \(bu
A widget name (beginning with a dot
.CW . ') `
that corresponds to an existing widget. The second word gives the name of a particular widget subcommand and the remaining words are arguments for the subcommand.
.IP \(bu
A
.CW "pack" ,
.CW "bind" ,
.CW "focus" ,
.CW "grab" ,
.CW "put" ,
.CW "destroy" ,
.CW "image" ,
or
.CW "update"
command.
These commands manipulate existing widgets or control Tk.
Most are the same as documented for Tk 4.0.
The
.CW "bind"
command is significantly different, and the
.CW "image"
command is more limited.
.IP \(bu
The
.CW " send "
command,
which sends a string to a Limbo process.
The second word is the Tk name of a Limbo channel (previously registered with
.CW "namechan" ),
and the rest of the command is sent as a single string along the channel.
.IP \(bu
The
.CW "variable"
command.
Limbo/Tk generally does not provide the variables of Tcl/Tk; radio buttons are an exception. The
.CW "variable"
command takes the name of a variable defined in a radio button as the second word, and the value of the variable is the result of the command. Furthermore, there is one predefined variable whose value can be retrieved this way: the
.CW "lasterror"
variable is set every time a Tk command returns an error. The value is the offending command (possibly truncated) followed by the error return value. The
.CW "lasterror"
variable is cleared whenever it is retrieved using the variable command. This allows several
Tk commands to be executed without checking error returns each time. A call to the
.CW "variable"
command with
.CW "lasterror"
at strategic points can make sure that an unexpected error has not occurred.
.IP \(bu
The
.CW "cursor"
command. This command takes a number of option/value pairs to control the appearance and placement of the cursor. Available options are:
.Tk -x int
and
.Tk -y int ,
to change the cursor position to align its hotpoint at the given point (in screen coordinates);
.Tk -bitmap filename
or
.Tk -image imagename
to change the appearance of the cursor; and
.CW -default
to change back to the default appearance of the cursor.
.LP
Because the language accepted by the
.CW "cmd"
function has no user-defined functions, no control flow and very few variables, almost all applications need to have some of their logic in Limbo programs.
The modern concurrency constructions provided by Limbo \-
processes, channels, send/receive operators and
.CW alt \-
replace unstructured interrupts (`call backs'), often used by
other graphics systems, by structured control flow.
(The Inferno shell does provide support, however, for rapid prototyping using Tk
and a scripting language: see the manual pages for
.I sh-tk (1)
and
.I wish (1)
in Volume 1.)
.NH 2
Widget options
.LP
In Tk, all widget creation commands, and all
.CW "cget"
widget commands accept a common set of generic options in addition to widget-specific options.
Except as noted otherwise, the meanings are the same as they are in Tk 4.0. The allowable forms of things like
.I "color" ,
.I "dist" ,
and
.I "font"
are slightly different in Limbo/Tk.
See
.I types (9)
in Volume 1
for precise definitions.
The generic options are as follows:
.DS
.fi
.Tk -activebackground color
.br
.Tk -activeforeground color
.br
.Tk -actwidth dist
.br
.Tk -actheight dist
.DE
.QS
Note:
the
.CW -actwidth
and
.CW -actheight
variables are overridden by the
packer, but are useful as arguments to
.CW cget
to retrieve the actual
width and height (inside the border) of a widget after packing.
.QE
.DS
.fi
.Tk -background color
(or
.Tk -bg color )
.br
.Tk -borderwidth dist
(or
.Tk -bd dist )
.br
.Tk -font font
.br
.Tk -foreground color
(or
.Tk -fg color )
.br
.Tk -height dist
.br
.Tk -padx dist
.br
.Tk -pady dist
.br
.Tk -relief relief
.br
.Tk -state normal ,
.Tk -state active ,
or
.Tk -state disabled
.DE
.QS
Note:
.CW -state
is only relevant for some widgets (for example,
entry widgets).
.QE
.DS
.fi
.Tk -selectbackground color
.br
.Tk -selectborderwidth dist
.br
.Tk -selectcolor color
.DE
.QS
Note:
.CW -selectcolor
is the colour of the box in selection menu
items.
.QE
.DS
.fi
.Tk -selectforeground colour
.br
.Tk -width dist
.DE
In general, the manual page for each widget in section 9 of Volume 1 tells which of the
generic Tk options the widget accepts.
.LP
The
.I "dist"
parameters are lengths, expressed in the following form:
an optional minus sign, then one or more decimal digits (with possible embedded decimal point), then an optional units specifier.
The unit specifiers are the following:
.IP
.TS
lf(CW) lf(R)w(3i) .
c	centimetres
m	millimetres
i	inches
p	points
h	height of widget's font (*)
w	T{
width of `\f(CW0\fP' character in widget's font (*)
T}
.TE
.LP
The ones marked (*) are specific to Limbo/Tk.
.LP
Tcl/Tk 4.0 widgets do not uniformly take
.CW "-width"
and
.CW "-height"
options; instead, each widget may take either or both, and the interpretation
of a number lacking a unit specifier varies from widget to widget. For example, in Tk 4.0
.CW "-width 25"
means 25 characters to an entry widget, but 25 pixels to a canvas widget. In Limbo/Tk, all widgets may specify width and height, and bare numbers always mean screen pixels.
.LP
A
.I "colour"
parameter can be a colour name or an RGB value.
Only a few names are known:
.IP
.TS
lf(CW) lf(CW) lf(CW) lf(CW) lf(CW) .
aqua	fuchsia	maroon	purple	yellow
black	gray	navy	red
blue	green	olive	teal
darkblue	lime	orange	white
.TE
.LP
For RGB values, either
.CW "#" \fIrgb\fP
or
.CW "#" \fIrrggbb\fP
can be used, where
.I r ,
.I rr ,
etc.
are hexadecimal values for the corresponding colour components.
.LP
A
.I "font"
parameter gives the full path name of an Inferno font file; for example,
.CW "/fonts/pelm/unicode.9.font" .
.LP
A
.I bitmap
parameter is not used by any of the generic options, but is worth mentioning here.
Unlike Tk 4.0, a
.I bitmap
in Limbo/Tk is not restricted to a 1-bit deep bitmap to be coloured with foreground and background.
Instead, it can be a full-colour image (`pixmap' in X11 terminology),
which is displayed as is. If
.I "bitmap"
begins with a
.CW @ ', `
the remaining characters should be the path name of an Inferno image file. If
.I "bitmap"
begins with the character
.CW < ', `
the remaining characters must be a decimal integer giving a file descriptor number of an open file from which the bitmap can be loaded. Otherwise,
.I bitmap
should be the name of a bitmap file in the directory
.CW "/icons/tk" .
.NE 1i
.SH
Options not supported in Limbo/Tk
.LP
The following options provided by Tk 4.0 are not supported by any Limbo/Tk widget:
.P1
-cursor                  -insertofftime       -wraplength
-disabledforeground      -insertontime
-exportselection         -insertwidth
-geometry                -repeatdelay
-highlightbackground     -repeatinterval
-highlightcolor          -setgrid
-highlightthickness      -takefocus
-insertbackground        -textvariable
-insertborderwidth       -troughcolor
.P2
.NH 1
Limbo/Tk commands
.LP
This section lists all the commands documented in the Tk 4.0 man pages, giving the differences between the behaviour specified in those man pages and the behaviour implemented in Limbo/Tk.
Some common Tcl commands are listed as well.
Bear in mind that some Tk 4.0 options are unsupported, as noted above.
.Tc "bell" "[\f(CW-displayof \fP\fIwindow\fP]"
Not implemented.
.Tc "bind" "\fIwidget\fP <\fIevent-event-...-event\fP> \fIcommand\fP"
.d0
.Tc "bind" "\fIwidget\fP <\fIevent-event-...-event\fP> + \fIcommand\fP"
.d1
The bind command is perhaps the command that differs most from Tk 4.0.
In general, only a subset of its functionality is implemented. One difference is that
.I widget
must be the name of an existing widget.
The notion of a widget class is completely absent in Limbo/Tk.
Event sequence specifications are also more restricted. A sequence is either a single character (rune), meaning a
.CW "KeyPress"
of that character, or a sequence of
.I "events"
in angle brackets.
.I "Events"
are separated by blanks or minus signs.
See
.I bind (9)
for a complete discussion.
.Tc "bindtags" "\fIwindow\fP [\fItaglist\fP]"
Not implemented.
.Tc button "\fIpathname\fP \*(Op"
As in Tk 4.0 (but note difference in units for
.CW "-height"
and
.CW "-width" ).
.Tc canvas "\fIpathname\fP \*(Op"
The Postscript subcommand is not implemented.
.Tc checkbutton "\fIpathname\fP \*(Op"
Unimplemented options:
.CW "-indicatoron" ,
.CW "-offvalue" ,
.CW "-onvalue" ,
and
.CW "-selectimage" .
The
.CW flash
subcommand is not implemented.
.Tc clipboard \fIoperation\fP [\fIarg ...\fP]"
Not implemented.
.Tc "\fIpathname\fP configure [" "option ...\f5]\f1"
Configure options for widget
.I pathname .
Widget-specific; see the manual entry for the widget in
section 9 of Volume 1.
.Tc destroy "[\fIwindow ...\fP]"
As in Tk 4.0, but
note that
.CW "destroy ." ' `
is rarely needed because top level windows are automatically
destroyed by the Inferno garbage collector immediately when the last reference vanishes.
.Tc entry "\fIpathname\fP \*(Op"
The
.CW scan
subcommand is not implemented. Some key bindings are not implemented when there is currently no way to type those keys to Inferno (for example,
.CW "Home" ).
Note difference in units for
.CW "-height"
and
.CW "-width" .
.Tc "event" \fIoperation\fP [\fIarg ...\fP]"
Not implemented: normally replaced by Tk
.CW send
or Limbo channel send operation within the application.
.Tc focus \fIwindow\fP
The focus model in Inferno is different. Only one widget has the keyboard focus at a given time. Limbo/Tk does not maintain a private keyboard focus for each toplevel tree and automatically move the focus there whenever the tree is entered. (Canvas and text widgets, however, do maintain a private keyboard focus.)
The Limbo/Tk
.CW "focus"
command moves the keyboard focus to the given
.I window .
By default, the first press of the primary button in an
.CW "entry" ,
.CW "listbox"
or
.CW "text"
widget causes the focus to be moved to that widget. Just entering a menu widget gives it the focus.
The
.CW "-displayof" ,
.CW "-force"
and
.CW "-lastfor"
options are not implemented.
.Tc frame "\fIpathname\fP \*(Op"
Unimplemented options:
.CW "class" ,
.CW "colormap" ,
and
.CW "visual" .
.Tc grab "\fIwindow\fP"
.d0
.Tc grab "\fIoption\fP [\fIarg ...\fP]"
.d1
Limbo/Tk implements only global grabs, so the
.CW "-global"
option is not recognised. The
.CW "grab current"
command is not implemented. The
.CW "grab"
command is not recognised as a synonym for
.CW "grab set" .
.Tc "grid" "\fIoperation\fP [\fIarg ...\fP]"
Not implemented.
.Tc "image create bitmap" "[\fIname\fP] [\fIoptions\fP]"
.d0
.Tc image "\fIoption\fP [\fIarg arg ...\fP]"
.d1
Only bitmap image types are implemented, but, as documented under
.CW "bitmap" ,
Inferno `bitmaps' are not just 1-bit deep;
they encompass both bitmaps and `photo' (colour) images
as provided by Tk/4.0.
Limbo/Tk does not, however, recognise the wide variety of graphics formats that Tk 4.0 does.
Instead, only Inferno's own format is supported internally, and external programs
are provided to convert between that and other formats such as JPEG.
The file descriptor syntax for specifying bitmaps is useful when an external program writes the bitmap to a file descriptor.
If a maskfile is given, it may also have a depth greater than 1 bit; the meaning is that if a pixel of the mask is non-zero then the corresponding pixel of the image should be drawn.
(But see the handling of bitmaps used as stipples in
.I canvas (9).)
The
.CW -data
and
.CW -maskdata
options are not implemented.
.Tc label "\fIpathname\fP \*(Op"
Unimplemented options:
.CW "-justify"
and
.CW "-wraplength" .
Note difference in units for
.CW "-height"
and
.CW "-width" .
.Tc listbox "\fIpathname\fP \*(Op"
The
.CW "bbox"
and
.CW "scan"
subcommands are not implemented. Note difference in units for
.CW "-height"
and
.CW "-width" .
.Tc lower \fIwindow\fP
The
.CW "belowThis"
optional parameter is not recognised.
.Tc menu "\fIpathname\fP \*(Op"
Unimplemented options:
.CW "-postcommand" ,
.CW "-tearoff" ,
.CW "-tearoff"
command, and
.CW "-transient" .
In the
.CW add
subcommand, the
.CW "-accelerator" ,
.CW "-indicatoron" ,
and
.CW "-selectimage"
options are not implemented. In the
.CW "index"
subcommand, the
.CW "last"
and
.CW "pattern"
index forms are not implemented. The
.CW "configure"
and
.CW "entrycget"
subcommands are not implemented.
.Tc menubutton "\fIpathname\fP \*(Op"
Unimplemented options:
.CW "-indicatoron" ,
.CW "-justify" ,
and
.CW "-wraplength" .
.Tc "message" "\fIpathname\fP \*(Op"
Not implemented (subsumed by
.CW "label" ).
.Tc "option" "\fIoperation\fP [\fIarg ...\fP]"
Not implemented. There is no option database.
.Tc pack "\fIoption arg ...\fP"
.d0
.Tc pack "\fIslave\fP ...\*(Op"
.Tc "pack configure" "\fIslave\fP ... \*(Op"
.Tc "pack forget" "\fIslave\fP ..."
.Tc "pack propagate" "\fImaster\fP [0 | 1]"
.Tc "pack slaves" "\fImaster\fP"
.d1
The
.CW "info"
subcommand is not implemented.
.Tc place "\fIoperation\fP [\fIarg ...\fP]"
Not implemented.
.Tc radiobutton "\fIpathname\fP \*(Op"
Unimplemented options:
.CW "-indicatoron" ,
.CW "-justify" ,
.CW "-selectimage" ,
and
.CW -wraplength .
The
.CW "flash"
subcommand is not implemented.
.Tc raise \fIwindow\fP
The
.CW "aboveThis"
optional parameter is not recognised.
.Tc scale "\fIpathname\fP \*(Op"
Unimplemented options:
.CW "-digits "
and
.CW "-variable" .
.Tc scrollbar "\fIpathname\fP \*(Op"
The old syntax of
.CW "set"
and
.CW "get"
is not supported.
.Tc "selection"
Not implemented.
.Tc send "\fIchanname string\fP"
Rather than sending data to a different application, the
.CW "send"
command sends a given
.I string
down the Limbo channel associated with
.I channame ,
as set by
.CW namechan .
.Tc text "\fIpathname\fP \*(Op"
The
.CW "dump"
subcommand is not implemented. The
.CW "-regexp"
mode of the
.CW "search"
subcommand is not implemented.
.Tc tk "\fIoperation\fP [\fIarg ...\fP]"
Not implemented.
.Tc "tkerror"
Not implemented.
.Tc "tkwait" "\fIoperation name\fP"
Not implemented.
.Tc "toplevel" "\fIpathname\fP [\fIoption value\fP...]"
There is no
.CW "toplevel"
Tk command implemented by the
.CW "cmd"
function; instead, the Tk module entry point
.CW "toplevel"
is used to make toplevel widgets (windows)
as described above.
.Tc update
In Tcl/Tk,
.CW update
is a Tcl command that invokes the `event handler loop'.
In Limbo/Tk,
it flushes any pending updates to the screen.
The optional
.CW "idletasks"
argument is not recognised.
.Tc "winfo" "\fIoperation\fP [\fIarg ...\fP]"
Not implemented. Much of the information that
.CW "winfo"
would return can be got by applying
.CW "cget"
to each widget.
.Tc "wm" "\fIoperation window\fP [\fIarg ...\fP]"
Not implemented.
.NH 2
References
.IP 1.
John K Ousterhout,
.I "Tcl and the Tk Toolkit" ,
Addison-Wesley Publishing Company, Reading, Massachusetts, 1994.
.IP 2.
Paul Raines and Jeff Trantor,
.I "Tcl/Tk in a Nutshell" ,
O'Reilly, Sebastopol, California, 1999.
.IP 3.
B W Kernighan,
``Descent into Limbo'',
elsewhere in this volume.
.IP 4.
See
.I draw-intro (2),
.I tk (2)
and
.I wmlib (2)
in
.I "The Inferno Programmer's Manual",
Volume 1.
