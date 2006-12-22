.TL
Inferno 3rd Edition \- June 2001 Revision
.br
Release Notes and Errata
.AI
Vita Nuova
support@vitanuova.com
.br
18 June 2001
.SP 4
.NH 1
Installation
.LP
If you have a previous version of Inferno installed, this one must not
be installed over it.
If you have a Lucent Inferno 2.3 release from 1999 or earlier, you
should make a completely new installation from this CD.
If you have installed the Vita Nuova `Binary and Limited Source' CD you
should also make a new installation from this CD.
If you have previously installed the Vita Nuova Full Source CD from July 2000,
see the section `Updating the July 2000 release' at the end of this document.
(You could also make a fresh installation in a new directory, or remove the old
release and install this one if there are no files you wish to keep.)
.LP
Follow the installation instructions in ``Installation of the Inferno Software''
at the end of Volume 2.
The printed copy has several mistakes:
.IP \(bu
Page 327 notes that on Unix
if the installation is done as user
.CW root 
but a user
.CW inferno
exists the files will be owned by
.CW inferno .
They are not.
Indeed, on Unix there is no reason to install the package as
the super-user
.CW root .
Do the installation as the user, perhaps
.CW inferno ,
that is to own the files.
.IP \(bu
It refers on page 327
to the Windows installation program as
.CW Nt-386.exe .
The correct name is used on the next
page in the actual instructions, namely
.CW \einstall\esetup.exe .
.IP \(bu
The Windows
.CW setup.exe
will offer to create the target installation directory if it does not exist.
On all other systems, you must first create the directory yourself.
.IP \(bu
Solaris and some other commercial Unix systems
do not read the `Joliet' format section of the CD,
which uses Unicode names, and
they
force the names in the non-Joliet portion on the CD to lower case, sometimes
with hyphens converted to underscores.
The installation script on Solaris is therefore
.CW install/solaris_sparc.sh .
The installation script itself works despite this.
Alternatively, if the CD is mounted with the option
.CW nomaplcase
the system will not force the names to lower case
and all names will appear as we intended
(see the Solaris manual entry for
.I mount_hsfs ).
Future CDs will use Rock Ridge format as well as Joliet to avoid the problem.
(We attempted that this time
but ran into trouble on Windows systems because of an error in the CD writing program.)
Linux and FreeBSD show the names we intended.
.LP
When installing on Windows NT or Windows 2000, the installation program determines
if the current user belongs to the
.CW Administrators
group.
If so, the Start Menu entry is created in the
.CW "All Users"
profile, otherwise it is created in the user's private profile.
On Windows 95 and Windows 98, if the user has a private profile the
Start Menu entry is created there,
otherwise it is created in the main system Start Menu.
Furthermore,
.CW setup.exe
looks for
.CW "Start Menu"
to install the shortcut, but that name is locale-dependent,
and thus the shortcut will not be installed correctly in non-English locales,
although Inferno itself will be installed successfully.
.LP
When the installation completes normally,
it prints ``installation complete'', but on some platforms it can then print
``Killed: ...'' followed by the command line used in the installation shell script.
Provided it has said ``installation complete'' and there were no errors noted
prior to that, the installation has succeeded.
The ``Killed'' message results from the installation software
running inside the Inferno environment having shut down that environment.
It does not mean that installation failed.
.LP
If an installation does fail, for instance by running out of space,
delete everything in the target directory before retrying the installation.
Also see the ``Known Problems'' section below.
.NH 1
CD Number
.LP
There is a set of six unique numbers on the back of the CD case.
You should keep the case or record the numbers:
they identify your subscription, and you will need them
to gain access to subscriber's services we provide electronically.
(They are randomly generated and usable in a 6/49 lottery!)
.NH 1
Hosted Operating System versions
.LP
The software was compiled on the operating system versions listed below.
UNIX systems show the output from
.CW "uname -a"
and the version of the C compiler,
if known.
See the section
.I "Known problems"
below for a list of known problems for any given release.
.TS
center;
lf(B) lf(R)w(4i) .
Windows Nt	Windows NT4.0 SP4
Linux	T{
Linux vespa 2.2.9-19mdk #1 Wed May 19 19:53:00 GMT 1999 i586 ...
.br
(gcc-2.91.66)
T}
Solaris	T{
SunOS pazzo 5.6 Generic_105181-03 sun4u sparc SUNW,Ultra-5_10
.br
(gcc 2.95)
T}
FreeBSD 4.x	T{
FreeBSD outside 4.0-RELEASE FreeBSD 4.0-RELEASE #0: ... i386
.br
(gcc 2.95.2)
T}
HP/UX	T{
HP-UX hpserv1 B.10.20 A 9000/715 2013314861 ...
.br
(c89)
T}
IRIX 5.3	T{
IRIX invece 5.3 11091812 IP22 mips
.br
(MIPS cc)
T}
Plan9/x86	Third Edition, updates to 5th June 2001
.TE
.LP
The Windows version has also been tested and
used extensively on the following variants:
.DS
.ft B
Windows '95
Windows '98
Windows Me
.ft R
.DE
We have also installed and run the system under Windows 2000, both
client and server, but there is a problem with the cursor under Windows 2000 client (see below).
.LP
Inferno source code is included for the following, but they have neither been
built nor tested:
.DS
.ft B
Plan 9 (mips, sparc, power)
Solaris/386
Unixware v 2.3
.ft R
.DE
.NH 1
Known problems
.LP
See
.CW www.vitanuova.com/inferno/
for current pointers to information about Inferno.
You should particularly check the Frequently Asked Questions at
.P1
www.vitanuova.com/inferno/faq.html
.P2
and the current Bugs list at
.P1
www.vitanuova.com/inferno/bugs.html
.P2
The Subscriber area will include online updates after 6 July 2001.
.LP
Now, the bad news:
.IP \(bu
The Windows NT installation program will create a Start Menu shortcut that invokes
.I emu
with a
.CW "-g800x600"
argument. The
.I emu
display will be incorrect if the screen width available is less than 800 pixels and is not a multiple
of four. The problem can be seen if the PC is configured with a resolution of 800x600 pixels
and the Microsoft Office shortcut bar is active. The simplest fix is to change the
.I emu
shortcut to use a
.CW "-g788x600"
argument instead.
.IP \(bu
As mentioned above, the Windows NT installation program looks only for
.CW "Start Menu"
not the locale-dependent name.
.IP \(bu
Changing the cursor image does not work under Windows 2000 Client;
this mainly affects
.I acme ,
which changes the cursor when rearranging or resizing frames.
.IP \(bu
The HP version of hosted Inferno was generated by HP/UX version B.10.20.
On the HP platform,
.CW emu
can currently only be run in interpreted mode; the compiled mode (ie,
.CW -c1
option)
will fault.
.IP \(bu
Some Inferno calls return error strings provided by Windows, without modification.
They can be obscure:
for instance, ``windows error 10049'' is produced by network calls
that attempt to use symbolic names when
.I cs (8)
has not been started.
.IP \(bu
On all systems, the mapping from Inferno names and permissions to the underlying
operating system's names and permissions needs more work, particularly on Windows.
Common problems include:
.RS
.IP \-
File names in the Inferno environment cannot be longer than 27 bytes.
.IP \-
.I Ftpfs
cannot access files with long names or names containing spaces.
.IP \-
The contents of
.CW /dev/user
on Windows will contain the Windows user name, which can contain spaces.
.IP \-
Files created inside the Inferno hierarchy by host system applications
can sometimes have odd permissions when accessed within Inferno.
.IP \-
Readonly files and open files cannot be removed under Windows.
.LP
In general, the mapping between Inferno users and groups and Windows/Nt users and groups
is systematic, as described  in
.I sys-stat (2):
.QS
.I Emu
attempts to maintain a limited but consistent map
between Inferno and NT worlds, specifically between Inferno
names and NT security IDs.
Special NT group `Everyone'
represents `other' for file permissions.  The Inferno uid is
the file owner under NT; the Inferno gid reported is the
first user in the file's ACL that is neither the owner nor
Everyone; failing that, the gid is the file's owner.
.QE
.LP
The effects of this mapping are sometimes peculiar: for instance, something that
is thought of as a user appears as the group name in
.I ls ,
and vice-versa.
Either the implementation or the mapping might need to be rethought.
.RE
.IP \(bu
.I bufio (2)
maintains an internal list of files open for output,
to support its little-used
.CW flush -all
operation.
Unfortunately, that means that if several processes
use the same Bufio module instance (the result of a single
.CW load )
concurrently for output to different files, they must separately interlock the open, create and close calls.
.IP \(bu
The file
.CW utils/5l/thumb.c
contains comments in the C++ style, which (reasonably enough) are not accepted by the
ANSI C compiler on the HP/UX system we used, and thus the current
.CW 5l
is not compiled for HP/UX; they will be changed to ANSI C comments by
one of the online updates.
.NH 1
Contents
.LP
This revision offers the following, compared to the July 2000 release.
.SH
.I "Repairs and changes"
.IP \(bu
Many bug fixes and improvements appear throughout.
Many commands have been revised to print usage and diagnostic consistently, and give reliable exit status for
.CW sh .
.IP \(bu
The shell
.CW sh
has repairs and several visible changes:
.I sh-expr (1)
implements a
.CW %
operator for remainder;
a new
.CW @
operator creates a sub-shell to execute a command, allowing the calling shell to be insulated
by
.CW pctl
(see
.I sh-std (1))
from changes to name space and environment;
environment variables are stored in printable form;
a newline is allowed after a caret;
and everyone's favourite change, the colon character
.CW : ' `
is no longer reserved in argument words
(allowing URLs to be given without quoting).
.IP \(bu
Inferno's Acme has been revised to match the version in Plan 9 (Third Edition).
In particular, the
.CW Edit
built-in has been added, allowing the use of structural regular expressions
and the
.CW sam
command language for efficient editing within
Acme,
replacing the
.CW /acme/edit
suite of commands.
The Acme panes have acquired a similar touch of colour.
.IP \(bu
Charon has also had many fixes and improvements, particularly to
Javascript extraction, frames and layout code.
Sometimes the `fix' requires making Charon mimic the interpretation of incorrect HTML
of other browsers.
The PNG image format is now supported.
Cookies are enabled by default (too many sites use them);
parsing and production of the cookie file has been repaired.
The progress bar is more compact.
Support for longer SSL keys is enabled by default.
.IP \(bu
The software installation commands
.CW install/*
have been extensively revised,
and documented by
.I archfs (4)
and
.I create (8).
They are based (though not entirely) on Russ Cox's update
package for Plan 9.
.IP \(bu
.I format (8)
can format an ordinary file, for instance to prepare flash partition
contents in a hosted environment for a native Inferno device.
.IP \(bu
.CW mount
allows the certificate file to be named directly.
.IP \(bu
.CW ns
correctly quotes the fields in its output.
.IP \(bu
.CW /services/server/config
no longer gives the unauthenticated
.CW nobody ') (`
option to
.I styx (8);
some unused entries have also been deleted.
.IP \(bu
.I srv (8)
passes all arguments to servers it spawns, including the command name.
It also ensures each server has its own process group, file descriptors
and name space.
.IP \(bu
.I stack (1)
has a new
.CW -p
option to add names to the source file search list.
.IP \(bu
.I deflate (2)
correctly detects end-of-file;
.I inflate (2)
correctly decodes the combined compressed code-length tables
.IP \(bu
Tk's handling of objects in canvases is better:
raise and lower work properly; stipple is implemented.
.IP \(bu
Tk now knows that a window pops up when resized, and adjusts
the z-order accordingly.
.IP \(bu
Tk's scroller always expands the fraction of a
.CW moveto
when it evaluates the scrolling command.
.SH
.I "New commands and modules"
.IP \(bu
.I ftpfs (4)
provides a way to make a remote FTP site visible in the Inferno name space
(it was documented in the printed manual but not previously included with the system).
.IP \(bu
.I listen (1)
provides a convenient way to listen for incoming calls to one or more Inferno services,
with optional use of
.I ssl (3)
for authentication and encryption.
This can replace the clumsy use of
.I srv (8).
.IP \(bu
.I dial
(see
.I listen (1))
is the complement of
.I listen ;
it dials a service, with optional authentication and encryption.
.IP \(bu
.I lockfs (4)
enforces multiple reader, exclusive writer access to the contents of a name space.
.IP \(bu
The device
.I prof (3)
serves a name space for controlling the profiling of Limbo modules,
and retrieving the resulting data.
The module
.I profile (2)
offers a convenient interface, relating the profiling data to the source code.
Finally,
.I prof (1)
is the command line interface to enable profiling and display the results.
.IP \(bu
.CW uuencode
and
.CW uudecode
interpret a format used to encode binary data printably on Usenet and in mail messages;
see
.I uuencode (1).
.IP \(bu
.I Read (1)
writes to standard output the result of a single
.I sys-read (2)
of a given number of bytes from standard input,
with optional seek offset.
(See
.I getlines
in
.I sh-std (1)
for a way to read a line from standard input.)
.IP \(bu
.I Tcs (1)
uses
.I convcs (2)
to offer character set conversion on files.
.IP \(bu
.I wm-misc (1)
mentions
.CW wm/mand ,
a browser for fractals,
and
.CW wm/polyhedra ,
a polyhedra viewer
.IP \(bu
.I cfg (2)
provides a module to read configuration files.
.IP \(bu
.I dividers (2)
provides user-draggable dividing lines to separate Tk widgets,
allowing screen space to be allocated to widgets by dragging a dividing line.
.IP \(bu
.I imagefile (2)
offers support for reading PNG image files
.SH
.I "Interface changes and extensions"
.IP \(bu
.CW Url
.CW /module/url.m ) (
now requires an
.CW init
function to be invoked before other functions in the module
.IP \(bu
.I convcs (2)
has changed its interface significantly (see the manual page);
it also offers support for UTF-7.
Even the module name has changed, to
.CW Convcs
(from
.CW ConvCS ).
.IP \(bu
.I plumber (8)
now returns an error to a message's sender if it cannot be plumbed,
as was previously documented;
it handles
.CW ^
correctly in regular expressions
.IP \(bu
.I readdir (2)
returns all file names in union directories
.IP \(bu
.I string (2)'s
quoting and unquoting functions are correct and more efficient
.IP \(bu
.I styxlib (2)
forces an internal process into a new empty name space to
allow detection of the last unmount of the served space by a file server
.IP \(bu
.I translate (2)
supports writing Unicode characters in hexadecimal using Limbo's \f5\eu\fP\fIXXXX\fP
syntax
.IP \(bu
.I workdir (2)
returns a better guess at the current directory on native Inferno
(hosted implementation will be supported in the next update)
.IP \(bu
.I cs (8)
keeps a cache of recent translations;
.I ipsrv (8)
uses UDP/IP by default, not TCP/IP, for domain name lookup
.IP \(bu
.I httpd (8)
can now be said to work as documented
.IP \(bu
.I wm-sh (1)
provides a new control file
.CW /chan/shctl
to allow it to be kept informed
of the current directory (and
.CW /lib/wmsetup
defines a Shell function to do that)
and to implement buttons below the title bar,
as with
.I mash-tk (1).
.IP \(bu
A collection of playing card images has been added in
.CW /icons/cards .
.IP \(bu
.CW /lib/wmsetup
defines a
.CW cd
function to keep
.CW wm/sh
informed of the current directory;
the
.CW Web
menu item is now called
.CW Charon ;
a new
.CW Manual
entry invokes
.I wm-man (1);
and the game
.CW Tetris
has been added to the
.CW Misc
submenu.
.IP \(bu
The manual pages
.I draw-font (2),
.I draw-image (2),
and
.I draw-screen (2)
now document
.CW display
and
.CW screen
members of various data structures.
.IP \(bu
.I security-auth (2)
and
.I security-login (2)
note that
.CW keyring.m
must be included.
.IP \(bu
In
.I sh (2),
the function
.CW exec
has been renamed
.CW run ,
to reflect more accurately what it does.
.IP \(bu
In
.I sys-pctl (2),
the type of the second parameter to
.CW Sys->pctl
is actually
.CW "list of int"
not
.CW "list of ref Sys->FD" .
.IP \(bu
.I ssl (3)
documents the new
.CW encalg
and
.CW hashalg
files, which list the supported algorithms.
.IP \(bu
.I canvas (9)
describes the new
.CW -winding
option
.IP \(bu
.CW /services/cs/services
lists the Software Download Server port
and removes others that are obsolete.
.IP \(bu
.CW /services/server/config
no longer gives the unauthenticated
.CW nobody ') (`
option to
.I styx (8);
some unused entries have also been deleted.
.SH
.I "Limbo compiler"
.IP \(bu
The Limbo compiler correctly clears reference values (eg,
.CW list ,
.CW ref
and
.CW array )
when they go out of scope when necessary (eg, in loops), causing the storage to be reclaimed,
and the values to be correctly
.CW nil
when the scope is next entered.
.IP \(bu
A bug that caused temporaries sometimes to be reused too early has been fixed.
.IP \(bu
The compile-time evaluation of floating-point
.CW >
does not calculate
.CW >=
instead.
.IP \(bu
A little context has been added to `syntax error' messages.
.SH
.I "Compilers and architectures"
.IP \(bu
The system now supports the Thumb variant of the ARM architecture,
including full interworking of Thumb code and 32-bit ARM code;
there is a Thumb JIT compiler for the virtual machine, and support for
Thumb mode in the disassembler and debugger.
The Thumb compiler is
.CW tc ;
the existing ARM linker
.CW 5l
links both ARM and Thumb code.
.IP \(bu
A bug in
.CW 5l
has been fixed that could very occasionally place a literal pool inside a case table.
.IP \(bu
The compilers find include files correctly under Nt.
.SH
.I "Hosted and Native Inferno"
.IP \(bu
.I Emu
has the following fixes and improvements:
.RS
.IP \-
support for logging of memory pool usage
.IP \-
FreeBSD support uses
.I rfork
not
.I pthreads .
.IP \-
Linux support no longer relies on being able to set the TSS register.
.IP \-
A memory leak when a kernel process exits has been fixed.
.IP \-
A start has been made on tidying up the audio support; the
.CW svp.c
file has gone and platforms that do not currently support audio
no longer must include a stub driver.
.IP \-
The Linux and
FreeBSD ports use an alternative implementation of Inferno graphics
under X11 that should allow the program to run under 16-bit graphics and higher.
.RE
.IP \(bu
For the native kernels only:
.RS
.IP \-
The native kernel implements Rob Pike's `lexical names' (as in Plan 9), which helps
provide more sensible data to
.I workdir (2).
The hosted Inferno implementation of lexical names will appear in a future update.
Note that
.CW /os/port/ns.c
no longer exists, and native kernel configuration files should no longer mention
.CW ns
in the
.CW port
section.
Drivers that serve a directory hierarchy might need to support the
.CW DEVDOTDOT
value for the table index in their
.CW devgen
function.
.IP \-
.CW os/ip/bootp.c
will correctly time out if there is no response.
.CW os/ip/ihbootp.c
will now work with an RFC1084 BOOTP server.
Note that both are likely to be replaced in future by
Limbo applications that do BOOTP and DHCP.
.IP \-
.CW os/pc/cga.c
provides a replacement for
.CW screen.c
for use when only a simple CGA console is needed or possible.
.IP \-
The file descriptor array is correctly freed when the file descriptor
group is closed, fixing a memory leak.
.IP \-
A few files that were left off the July 2000 CD have been included this time.
.IP \-
ARM/Thumb kernels have been implemented; those implementations
are not included in this update because the hardware is specialised but ask if you could use them.
.RE
.LP
The remaining points are common to both hosted and native Inferno:
.IP \(bu
A write on closed pipe does not produce an exception if the process has been killed.
.IP \(bu
.I Devbwrite
will not lose memory if an error is raised by the device driver (eg, interrupt).
.IP \(bu
.I ssl (3)
has
.CW encalg
and
.CW hashalg
files
.IP \(bu
.I Kfs (3)
offers
.CW readonly
and
.CW readwrite
commands, and an
.CW ro
(readonly)
option to the
.CW init
request.
.IP \(bu
.I Srv (3)
rejects attempts to create an unusable name containing a `/'.
.IP \(bu
The
.CW NODEVS
flag of
.I sys-pctl (2)
is correctly copied when the name space is duplicated.
.\" the following is only in the 386 version
.\" .IP \(bu
.\" .I Prog (3)
.\" can optionally give the correct Dis pc for the debugger even for compiled modules; if
.\" .CW cflag
.\" (or
.\" .CW -c
.\" option for
.\" .I emu )
.\" is 2 not 1, a mapping table is retained after JIT compilation.
.SH
.I "SA1100 native"
.IP \(bu
A new
.CW archether
function in
.CW arch*.c
(when required)
is invoked by
.CW devether.c
to discover the configuration of Ethernet devices.
.IP \(bu
.CW devuart.c
supports the use of XON/XOFF;
the first line of the
.CW stat
file gives the current UART settings;
it no longer panics if an overrun occurs;
and
.CW setlength
accesses the correct structures.
.IP \(bu
The CS8900 driver
.CW ether8900.c
is more general, supporting the I/O port interface as well as the memory interface.
.IP \(bu
Obsolete definitions have been removed from several include files
(eg,
.CW io.h )
and obsolete (typically #ifdef'd code) has been removed from source files.
.NH 1
IDEA™
.LP
The software includes an implementation of the IDEA encryption algorithm,
for non-commercial use.
IDEA was patented by Ascom-Tech AG (European patent EP 0 482 154 B1, US patent number
US005214703, and patent filed in Japan).
At time of writing, there was no licence fee required for noncommercial use.
If you intend to use IDEA encryption commercially with Inferno, you should consult
.CW http://www.it-sec.com/idea_lic_policy.html
for the current licensing policy of iT_SEC Systec Ltd, which currently holds the patents and trademark.
Note that IDEA is not required for
successful use of Inferno.
It is not by default enabled by
.I rstyxd (8),
and otherwise is used only by SSL3 (for the browser), in
.CW /appl/lib/crypt/ssl3.b ,
where it can be disabled.
.NH 1
Updating the July 2000 Full Source release
.LP
A set of update packages for the July 2000 release is provided in the directory
.CW /updates
on this June 2001 CD.
You should install the updates as the host operating system user who owns the Inferno files and directories
on your system.
You might like to take a backup copy of the existing tree, just in case.
Do the following to update the installation.
(Next time we hope to provide a more automated scheme.
You might check
.CW www.vitanuova.com/inferno/
to see if there are any more recent instructions.)
.IP 1.
Copy the directory
.CW updates
and its subdirectories from the CD to a directory
.CW updates
in the root of your existing Inferno hierarchy.
Make sure there is sufficient space in the file system holding that hierarchy.
If all platform files are copied and installed, about 45 Mbytes will be needed
to hold the compressed update packages in
.CW updates ,
with a further
35 Mbytes needed for an temporary uncompressed copy
of the largest package, and allow 10 Mbytes for new additional material, giving
90 Mbytes in all.
The
.CW updates
directory can be removed after installation.
.IP 2.
Start the existing Inferno
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
Change to the directory
.CW updates
and load the standard Inferno shell module:
.RS
.P1
cd /updates
load std
.P2
.RE
.NE 1i
.IP 4.
Unpack the updated installation software:
.RS
.P1
gunzip <install.tgz | {cd /; gettar}
.P2
.RE
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
You will see one warning:
.P1
skipping /dis/install/inst.dis: locally modified
.P2
because that file was updated by step 4.
You might see other warnings if you have modified any other files from the original release.
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
for (a in \fIplatform\fP/*) {install/inst -v -t $a}
.P2
.RE
.IP 7.
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
``Inferno Third Edition (18 Jun 2001)''.
