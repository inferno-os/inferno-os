.TL
Inferno 3rd Edition \- 3 October 2001 Update
.br
Release Notes
.AI
Vita Nuova
support@vitanuova.com
.br
3 October 2001
.SP 4
.NH 1
Contents
.LP
This set of updates applies to the 18 June 2001 base.
The installed software must therefore be that of 18 June 2001, whether installed directly,
or the result of updating the original July 2000 release with update packages.
.LP
This update offers the following, compared to the June 2001 release.
.SH
.I "Repairs and changes"
.IP \(bu
Various minor bug fixes and improvements appear here and there.
They include corrected usage messages, status returned to the shell on error,
diagnosing failures to load library modules,
and use of the
.CW %r
format to improve diagnostics.
Many
.I wm
applications adjust their display to suit small screens (eg, on the Compaq iPAQ);
currently the applications do some of the work themselves but it will soon be automatic.
Other changes are listed below.
.IP \(bu
.I Date (1)
takes the options
.CW -u
(show UTC/GMT)
and
.CW -n
(print time as a number).
If given a number of seconds as its argument,
.I date
takes that as the time to convert.
.IP \(bu
.I Format (8)
supports tiny partitions.
.IP \(bu
.CW /appl/env.b
uses
.I env (2)
to access environment variables.
.IP \(bu
For packages created after Saturday 8 September 2001,
.CW install/create
converts the leading
.CW 10
to the letter
.CW A
so that the names of update files remain in sorted order.
.IP \(bu
.CW install/inst
takes a
.CW -c
option to cause it to carry on even if some files or directories cannot be made or updated.
(This option is intended for special applications and should not generally be used when applying system updates.)
.IP \(bu
.CW install/install
takes a
.CW -P
option that lists the packages to install.
The
.CW -g
option causes
.CW install
to install all available packages.
.IP \(bu
The installation software regards files that have had carriage returns inserted
before newlines as identical to the original files when deciding when files
have been modified locally.
.IP \(bu
The
.CW wm
applications now check the whole string received on the window
control channel returned by
.I wmlib (2)'s
.CW titlebar,
not just an initial letter;
in particular, they check for
.CW "exit"
not just
.CW 'e' .
.IP \(bu
.I Wm (1)
takes the option
.CW -s
to suppress the start menu.
.IP \(bu
.I Keyring-gensk (2)
and
.I createsignerkey (8)
provide experimental support for the RSA algorithm for signatures instead
of the default El-Gamal algorithm;
.CW /keyring/rsaalg.c
is new.
.IP \(bu
.CW /keyring/egalg.c
uses the correct structure for Public keys.
.IP \(bu
.I Listen (1)
has a new option
.CW -i
that takes a shell command for each listener to run to set up appropriate
context (eg, name space) before listening for incoming calls.
.IP \(bu
.I man (1)
allows non-numerics in section names.
.IP \(bu
.CW /appl/cmd/mkfile
now includes
.CW /mkfiles/mksubdirs
and has acquired the list of
.CW cmd
subdirectories from
.CW /appl/mkfile .
.IP \(bu
.I Puttar
gives warnings not fatal errors when files or directories cannot be found.
.IP \(bu
.I sh-expr (1)
implements the
.CW !=
operator.
.IP \(bu
.I Tail (1)
no longer gives an array bound error when a binary file does not end with a newline.
.IP \(bu
.CW tiny/sh
does not break when
.I filepat (2)
is not available.
.IP \(bu
.I Webgrab (1)
has several repairs to its HTTP protocol implementation, making it work with multi-homed servers.
.IP \(bu
.CW wm/sendmail
no longer fails to save messages when requested(!).
.IP \(bu
.I Arg (2)
allows re-use by ensuring that its globals are reinitialised by its
.CW init
function.
.IP \(bu
.I Bufio (2)
correctly implements relative seek.
.IP \(bu
.I Convcs (2)
provides several more character sets.
.IP \(bu
.I Cs (8)
does not complain if it is already running, suppressing a previously confusing diagnostic.
.IP \(bu
.CW lib/deflate
no longer fails on the output of some PC versions of
.I gzip .
.IP \(bu
.I Wmlib (2)
adapts a little better to different font and screen sizes (though more remains to be done);
on small screens, defined as those less than 480 pixels wide,
.I wm (1)
puts all windows at the screen origin by default.
.SH
.I "Interface changes and extensions"
.IP \(bu
.I Wm-deb (1)
has got a
.CW stack
button to bring up the stack window if it has previously been dismissed.
It also allows breakpoints to be set in modules that have not yet been loaded.
.IP \(bu
.CW wm/memory 's
display has been redesigned to be more informative.
.IP \(bu
.CW wm/tetris
allows the use of a stylus (or mouse) to guide the placement of pieces.
.IP \(bu
.CW wm/view
supports PNG format
.IP \(bu
.CW wm/view
has a new option
.CW -i
for use in
.I plumbing (6)
files, to cause it to listen for messages from the
.I plumber (8).
Existing plumbing files that invoke
.CW wm/view
will typically need to change to add that option for image viewing
using the plumber to work as expected.
.IP \(bu
.I Newns (2)
provides more general option parsing by using
.I arg (2),
and does error checking unless the
.CW -i
option is given to the
.I namespace (6)
commands.
Its internal
.CW mount
commandalso accepts the new options
.CW -k
.I keyfile
to select the source of the authentication key, and
.CW -C
.I alg
to select the encryption algorithm.
.IP \(bu
.I Plumber (8)
takes a
.CW -v
option to cause it to log the contents of messages (for debugging plumbing applications), and
also the option
.CW -c
.I wmchan
to select an alternative window manager channel instead of
.CW /chan/wm
when the
.CW -w
option is used.
.SH
.I "Tk changes and extensions"
.LP
Many of the Tk changes enforce rules and do more error-checking than before,
but there are several extensions and interface changes as well.
.IP \(bu
Tk applications must create the parent widget before its children.
Currently the check to enforce this rule has been suppressed, but it will be enabled in future.
.IP \(bu
Widget names are now checked for well-formedness: neither trailing dot nor double dot are allowed.
.IP \(bu
When text in a text widget is deleted, embedded windows in
that text are only deleted if they are descendents of the text
widget.
.IP \(bu
Text widget now redisplays correctly when an embedded window
is destroyed.
.IP \(bu
Text widget now checks for embedded windows in the text that have been destroyed since they were added to the text.
.IP \(bu
Widgets packed under a destroyed widget that are not
descendents of that widget are now removed correctly
from the packing hierarchy.
.IP \(bu
.CW -activebackground
now changes the border appropriately, same as
.CW -background .
.IP \(bu
.CW scrollbar
now returns currently activated part when
.CW activate
is called
with no arguments.
.IP \(bu
Only one part of a scrollbar may be active at any one time.
.IP \(bu
Tk can now distinguish between a null argument
.CW {}
and a missing argument.
.IP
Creating an embedded window in a text widget at index 1.0
no longer causes the packer to go into an infinite loop.
.IP \(bu
Changing the options on an embedded window in a text
widget caused an uninitialised pointer access.
.IP \(bu
Changing the window associated with an embedded window item
in text and canvas widgets previously did not disassociate the old window correctly.
.IP \(bu
Changing the window associated with an embedded window item
in a text widget did not set the widget's size appropriately.
.IP \(bu
The
.CW -baseline
alignment option for embedded windows in text widgets previously
did not calculate the line height correctly.
.IP \(bu
The
.CW -relief
setting for buttons is now restored after enter/leave or selection.
.IP \(bu
Buttons 4, 5 and 6 have been added (for the iPAQ).
.IP \(bu
Tk no longer crashes if the `grab' changes during the processing of a mouse event.
.IP \(bu
A new event
.CW <Destroy>
can be bound to a widget to receive notification when it is destroyed (eg, by the destruction of
a parent widget).
The
.CW <Configure>
event is propagated to slaves as well as the configured master.
These two changes make it easier to implement pseudo-widgets such as
.I dividers (2).
.IP \(bu
.CW -anchor
has been implemented for labels;
.CW -justify
should be implemented as documented.
.IP \(bu
Submenus are unmapped correctly.
.IP \(bu
Tk detects command loops (by limiting recursion depth).
.IP \(bu
.CW canvas
has a new boolean option
.CW -buffered
that controls whether the whole canvas, or just the visible region, is allocated an off-screen buffer image.
It defaults to just the visible area only.
.IP \(bu
.CW canvas
has new operations
.CW screenx
and
.CW screeny
to map canvas coordinates to screen coordinates.
.SH
.I "New commands and modules"
.IP \(bu
A collection of small and tiny playing card images have been added, in
.CW /icons/smallcards
and
.CW /icons/tinycards .
.IP \(bu
.CW install/wfind
lists the versions of a given file in a set of installation packages.
.IP \(bu
.I Touchcal (8)
provides touch-screen calibration; it runs both inside and outside the window
manager
.I wm (1).
Both internal and external interfaces are completely different from previous versions.
.IP \(bu
.I Wm-keyboard (1)
describes new commands
.CW wm/keyboard
and
.CW wm/pen
that provide soft keyboard and single-stroke gesture recognition for touch screen devices.
.IP \(bu
.I Gamesrv (4)
provides a file system interface for multi-player networked games;
.I gamesrv (2)
provides the interface for the game-specific engines loaded on demand by the game server.
.IP \(bu
.CW utils/awk
is a new directory containing the source for a version of
.I awk
for use in doing Inferno ports for systems that lack it (or a sufficiently recent version), including Windows.
It is not currently made automatically for any system.
It is covered by its own licence; see the
.CW README
and
.CW NOTICE
files in that directory.
.SH
.I "Limbo compiler"
.IP \(bu
The compiler now adds a source file name (relative to the Inferno root) to each Dis
file, to allow
.I debug (2)
and thus the debugger
.CW wm/deb
and other commands such as
.I profile (1)
and
.I stack (1)
to find source
and
.CW .sbl
files without prompting.
.IP \(bu
The initialisation of large arrays avoids deep recursion, preventing a trap on Nt
and a large stack on other platforms.
.IP \(bu
Overflow is avoided when sorting integers for case statements.
.SH
.I "Compilers and architectures"
.IP \(bu
The linker
.CW 5l
has a critical bug fix in 
.CW utils/5l/span.c
that fixes a bug in the flushing of literal pools.
.IP \(bu
.CW 5coff
has a small change to make the output conform to actual practice
not COFF documentation.
.SH
.I "Hosted and Native Inferno"
.IP \(bu
.I Emu
has the following fixes and improvements:
.RS
.IP \(bu
Trap handling on Windows now (we hope) does all that is required
to work on many versions, variants, updates and releases.
.IP \(bu
The cursor appears correctly under Windows 2000.
.IP \(bu
Windows
.I emu
passes page up, down scroll, pause, insert, delete and print
characters through to
.CW /dev/keyboard .
.IP \(bu
.CW styx.c
prevents bad Styx messages from causing trouble.
.IP \(bu
.CW devenv.c
returns
.CW "file exists"
if an attempt is made to create an existing name;
it implements
.CW ORCLOSE .
.IP \(bu
.CW devroot.c
makes directories mode 555 not 777.
.RE
.IP \(bu
For the native kernels only:
.RS
.IP \(bu
.I Env (3)
is now provided for native kernels.
To add it to a kernel, change the kernel configuration file as follows:
.RS
.IP 1.
Include the device driver
.CW env
in the
.CW dev
section.
.IP 2.
Include the support file
.CW env
in the
.CW port
section.
.IP 3.
Include the name
.CW /env
in the
.CW root
section.
.LP
To exclude it from a kernel, include the support file
.CW noenv
in the
.CW port
section.
You should only do this if you are trying to make a small highly specialised kernel;
general applications are likely to make more use of
.CW /env
now that it is there,
eventually to replace
.CW sysenv 
and to select locales.
.RE
.IP \(bu
Common floating-point emulator code has moved from platform-specific directories to
.CW /os/port/fpi.c
and
.CW /os/port/fpimem.c ,
with corresponding changes to configuration files and
.CW mkfiles .
.IP \(bu
The scheduling code in
.CW /os/port/proc.c
has changed to support wait-for-interrupt.
If no process can be scheduled, the platform-specific function
.CW "void idlehands(void)"
is called, with interrupts
.I off
(unlike the function of the same name in Plan 9).
On most platforms, it currently is an empty function defined by
.CW #define
in
.CW fns.h ,
and the scheduler effectively spins waiting for an interrupt to make a kernel process ready,
but on the iPAQ and a few other platforms it uses the hardware-specific
``wait for interrupt'' function, for power saving.
.IP \(bu
A new package
.CW ipaq
is available that populates
.CW /os/ipaq
with the preliminary Inferno port to the Compaq iPAQ.
.IP \(bu
.CW /os/ip
has incorporated bug fixes and improvements from Plan 9 to
keep the source code up to date:
.RS
.IP \-
.CW /net/ndb
has been added, to allow for future changes in IP configuration code
.IP \-
permissions are checked more carefully;
.CW wstat
is implemented
.IP \-
.CW Conv
structures are now unlocked on
.CW close
by
.CW devip.c
not by each protocol's implementation;
the
.CW car
lock for connect/announce no longer exists, because the conversation itself is locked
.IP \-
some missing
.CW waserror
calls have been added
.IP \-
ensure local port is unique across existing conversations
.IP \-
.CW tos
can be set for a converstation by a
.CW tos
control message, and is retained during routing
.IP \-
.CW qdiscard
in
.CW qio.c
returns the number of bytes discarded
.IP \-
protocol handlers
.CW esp.c ,
.CW gre.c ,
.CW icmp.c ,
.CW ip.c ,
.CW ipifc.c ,
.CW ipmux.c ,
.CW rudp.c
and
.CW tcp.c
have consequentially changed;
the TCP/IP implementation most extensively;
.CW il.c
and
.CW udp.c
have not yet been realigned with Plan 9
.IP \-
medium drivers use the structure-member initialisation extension of Plan 9 C,
to insulate driver source text from changes in the layout of the
.CW Medium
structure
.RE
.IP \(bu
The SA1100 UART driver now correctly pushes input up the stack when the FIFO empties.
.RE
.LP
The remaining points are common to both hosted and native Inferno:
.IP \(bu
.I Cons (3)
implements the file
.CW kprint
to capture Inferno console messages; and a file
.CW jit
that can be used to set the compile-on-the-fly option dynamically or read its current state.
.IP \(bu
There is a new kernel function:
.RS
.DS
.ft 5
char* seprint(char *buf, char *ebuf, char *fmt, ...);
.ft P
.DE
which puts a formatted result into
.CW buf
never writing beyond
.CW ebuf-1
(including the trailing null byte).
It returns the address of the next available byte in
.I buf .
.RE
.IP \(bu
.CW kfs 's
.CW Eexist
error has become
.CW Eexists
to remove a clash with the new
.CW Eexist
name in
.CW error.h
.IP \(bu
.CW exportfs.c
maintains offsets in exported directories correctly.
.IP \(bu
The undocumented
.CW devaudit.c
has been removed.
.IP \(bu
Some Limbo profiler bugs have been fixed.
.IP \(bu
A race for the use of a shared semaphore has been fixed in
.CW devprog.c .
.IP \(bu
.CW devprog.c
has a new debugging event:
.CW load
.I filename
corresponds to the execution of a Dis
.CW load
instruction.
.IP \(bu
.CW devdraw.c
implements
.CW readpixels
from a window
.NH 1
Updating the software
.LP
You should install the updates as the host operating system user who owns the Inferno files and directories
on your system.
You might like to take a backup copy of the existing tree, just in case.
Do the following to update the installation.
.IP 1.
Fetch the update archives required, namely
.CW inferno.tgz ,
.CW src.tgz ,
.CW utils.tgz
and any platform-specific packages required for your installation.
If you are running Windows, for instance, you will need
.CW Nt.tgz ;
if running Plan 9, you will need
.CW Plan9.tgz .
These are gzip'd tar files containing files starting with the directory
name
.CW updates/20011003 .
Unpack each in your Inferno root directory.
For instance, you can unpack
.CW inferno.tgz
using the Inferno commands:
.RS
.P1
cd /
gunzip <inferno.tgz | gettar
.P2
The following instructions assume they are visible in the Inferno hierarchy.
Make sure there is sufficient space in the file system holding that hierarchy.
Each archive can be removed after unpacking, and the
.CW updates
directory can be removed after installation.
.RE
.IP 2.
After unpacking the archives,
(re)start
the existing Inferno
.I emu ;
it will be quicker if you use the
.CW -c1
option to force compiled mode.
It is best to use only the Inferno console; do not start the window system, since
the updates will change files in the running system.
On the other hand, it is a good idea to make the window in the host
operating system a scrolling one, so that you can scroll back to
see any errors.
All following commands are run in the Inferno environment.
.IP 3.
Change to the directory containing the updates:
.RS
.P1
cd /updates/20011003
.P2
.RE
.NE 1i
.IP 4.
Updated installation software was included in
.CW inferno.tgz .
You must first unpack that installation software, as follows:
.RS
.P1
sh ./unpacktools
.P2
.RE
.NE 1i
.IP 5.
Update the installed Inferno, source and utility source directories
using the script
.CW applybase :
.RS
.P1
sh ./applybase
.P2
.LP
That script updates the
.CW inferno ,
.CW src
and
.CW utils
packages.
You might see warnings if you have modified any non-configuration files from the original release.
.RE
.IP 6.
Update one or more platform specific files for your platform(s).
The directories are named after the platforms:
.CW Solaris
for Solaris,
.CW Plan9
for Plan 9,
.CW Nt
for all Windows systems,
and so on.
For each
.I platform
that you run, do:
.RS
.P1
sh ./applyplat \fIplatform\fP
.P2
For instance, if you use Windows, run
.P1
sh ./applyplat Nt
.P2
The iPAQ distribution is installed the same way (it is just another platform):
.P1
sh ./applyplat ipaq
.P2
which populates
.CW /os/ipaq
in the Inferno tree.
.RE
.IP 6.
Quit
.I emu .
The new version of
.I emu
will be called
.CW emu.new
in the platform-specific directory
(eg,
.CW Solaris/sparc/bin/emu.new ).
Rename the old
.CW emu
file as
.CW emu.old ,
then rename the new
.CW emu.new
as
.CW emu
on Plan 9 and Unix systems,
or
.CW emu.exe
on Windows.
When run, it should announce itself as
``Inferno Third Edition (3 October 2001)''.
