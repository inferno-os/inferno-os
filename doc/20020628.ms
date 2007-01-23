.TL
Inferno 3rd Edition \- 28 June 2002 Update
.br
Release Notes
.AI
Vita Nuova
support@vitanuova.com
.br
28 June 2002
.SP 4
.NH 1
Base for update
.LP
This set of updates applies to the 18 June 2001 base.
The installed software must therefore be that of 18 June 2001, whether installed directly,
or the result of updating the original July 2000 release with update packages to the
18 June 2001 level.
This set of updates can be applied, however, whether or not the previous update
of 3 October 2001 was installed; this package includes all those changes too.
.NH 1
Contents
.LP
This update offers the following, compared to the 3 October 2001 release.
.LP
The following sections provide short
summaries of the more interesting or important changes.
There are many more minor or cosmetic changes.
.SH
.I "New commands and modules"
.IP \(bu
.I Fc (1)
is a floating-point calculator.
.IP \(bu
A new page
.I man (6)
describes the formatting commands used in manual pages.
.IP \(bu
Support for system-level memory monitoring has been made available
as an optional component of
.CW emu ,
with the interface provided by a new driver
.CW /emu/devmem.c .
It is not compiled in by default,
since it is relatively intrusive.
Details of how to enable it will be provided with the applications that use it.
.IP \(bu
.I Strings (1)
extracts strings from a file.
.IP \(bu
.CW 9export
(see
.I export (4))
serves a name space to a 9P client (mainly useful for
interacting with Third Edition Plan 9 systems at the moment).
.IP \(bu
.CW cdfs ,
which was described by
.I dossrv (4)
but not actually shipped is now included.
.IP \(bu
.CW csquery ,
described in
.I cs (8),
queries the connection service and prints the result.
.IP \(bu
.CW newer ,
described by
.I ftest (1),
is a shell predicate that compares the modification times on two files.
.IP \(bu
.I Print (2)
is a new module that provides an interface to directly-driven printers.
.SH
.I "Repairs and changes"
.IP \(bu
.CW cp
has been reworked extensively; amongst other things, it can now safely traverse
arbitrary name spaces without becoming confused by
complex mounts.
.IP \(bu
.I Listen (1)
and
.CW dial
both accept a
.CW -A
option to cause it to authenticate a connection.
.IP \(bu
.I Diff (1)
compares binary files and also does not quit (during recursive diffs) when it finds
a file it cannot open.
.IP \(bu
.I Ls (1)
implements the
.CW -u
and
.CW -t
sorting operations properly.
A new
.CW -e
option prints the time as a decimal integer (seconds since the system Epoch).
.IP \(bu
.I Sh
regards all of `../', `./', and `#' at the front of a command name as a request to use the name as-is.
.IP \(bu
.I Tail
has been changed to avoid some boundary cases.
.IP \(bu
.I Touch
uses standard argument processing and returns an error exit status if it fails.
.IP \(bu
.I Zeros
accepts new options
.CW -r
to generate random bytes
and
.CW -v
to produce blocks with a given value.
.IP \(bu
The network games software in
.CW /appl/games
uses port 6660 for its signer, not the standard Inferno signer's port.
.IP \(bu
.I Charon :
disguises itself as Mozilla to satisfy agent-name probes; retries fetches on error; supports multiple windows;
detects HTML vs plain text correctly; has many Javascript fixes, including fixing a day one bug
in operator precedence (!).
In general, it
has undergone extensive changes,
particularly to the cookies and Javascript implementation.
It also insists that it be run under the window manager
.I wm (1).
It can be set to plumb schemes that it does not implement internally.
.IP \(bu
The installation software now uses the numeric time as-is to name output packages;
the temporary fix introduced in Ocotober of converting  leading
.CW 10
to
.CW A
has been removed.
.IP \(bu
.CW /appl/lib/dis.b
prints offsets from
.CW MP
correctly (it previously printed them
as offsets from
.CW FP ).
.IP \(bu
.CW /appl/lib/parseman.b
accounts for enough extra
.I troff
commands to display
.I man (6)
correctly.
.IP \(bu
.CW /appl/lib/profile.b
binds
.CW #P
only if needed.
.IP \(bu
.CW /appl/lib/translate.b
.I translate (2)) (
now computes the right hash value.
.IP \(bu
Several run-time checks that were missing or incomplete for array access and slicing have been added.
.IP \(bu
.CW lib/isrv
no longer starts a new shell.
.IP \(bu
.I Wm-ftree (1)
has several new options:
.CW -E ,
.CW -p
and
.CW -d .
.IP \(bu
.CW wm/rt
now correctly updates stack size (if set).
.IP \(bu
.I Xd (1)
correctly implements
.CW -r
to suppress repeated lines.
.IP \(bu
.I gettar (1)
documents the
.B lstar
output format
.IP \(bu
.I man (6)
describes the manual page documentation format
.SH
.I "Interface changes and extensions"
.IP \(bu
.I Security-password (2)
provides a new entry
.CW setpwfile
to allow the default name
.CW /keydb/password
to be changed.
.IP \(bu
.I Dossrv (4)
has changed extensively, to support rename and long names in FAT format correctly.
It uses a smaller number of IO buffers.
.IP \(bu
.I Createsignerkey (8)
has a completely different invocation, documented in that manual page,
with a conventional option structure replacing a rather idiosyncratic chain
of optional arguments.
The old syntax is temporarily secretly still supported, but only
for the benefit of any shell scripts that might so use it; if you have any,
please change them to use the new syntax before the old usage finally vanishes in a later release.
.IP \(bu
.I Sum (1)
documents the new
.CW sha1sum
command.
.IP \(bu
.I Bufio (2)
returns an error if a seek fails rather than stopping the process(!).
.IP \(bu
.CW /lib/convcs
has several more character sets:
.CW koi8-r ,
.CW windows-1250
and
.CW windows-1252 .
.IP \(bu
.I Keyring-sha (2)
documents two new functions,
.CW hmac_sha1
and
.CW hmac_md5 ,
which are keyed versions of the corresponding secure hashing functions,
as defined by RFC2104.
The new definitions are in
.CW /module/keyring.m .
.IP \(bu
.I Keyring-getstring (2)
makes it clear that it does not
.I provide
delimited I/O but rather
.I requires
it (eg, as provided by
.I ssl (3))
for successful operation.
.IP \(bu
.I Security-ssl (2)
no longer requires
.CW #D
to be bound into the name space (since it can only be used locally in any case).
Consequently,
.CW bind
calls have been removed from several modules that used SSL.
.IP \(bu
.CW /appl/lib/crypt/ssl3.b
has several critical bug fixes, allowing secure connections to work correctly in Charon;
an important bug fix was also made to
.CW /appl/lib/crypt/x509.b .
.IP \(bu
.I Imageremap
has been changed to allow concurrent use.
.IP \(bu
.I Translate (6)
and
.CW /appl/lib/translate.b
have changed as required to put the locale-specific dictionaries in directory
\f(CW/locale/\fP\fIlocale\f(CW/dict\fP;
the directory for a chosen
.I locale
is then normally bound onto
.CW /locale/dict ,
where
.CW translate
looks by default.
.IP \(bu
The documentation for
.I button (9)
no longer claims that
.CW -padx
and
.CW -pady
are supported options for that widget.
.IP \(bu
.CW sys.m
has some new constants defined for use by a later Styx revision.
.SH
.I "Tk changes and extensions"
.IP \(bu
The canvas code provides extensions to Tk:
.CW "grab set tag" ,
.CW "grab release tag" ,
and
.CW "grab ifunset tag" .
See
.I canvas (9)
for details.
.IP \(bu
Also in canvases, object-specific hit tests have been added, rather than using a bounding box
in most cases.
.IP \(bu
Borderwidth defaults to zero in the entry widget.
.IP \(bu
Tk multiplexes the cursor amongst top-level windows.
.IP \(bu
Text and other items selected use foreground/background colours
.SH
.I "Limbo compiler"
.IP \(bu
Constant tuple and adt values can be used as values in
.CW con
constant declarations.
.IP \(bu
In an array value, the use of reference values for different
.CW pick
alternatives of the same adt no longer draws a diagnostic
but causes the array value to be an array of
.CW ref
to the adt, not a particular pick alternative.
.IP \(bu
The C language stub declarations support
.CW pick
adts.
.IP \(bu
The alignment of
.CW big
and
.CW real
is now correct in C stubs.
.IP \(bu
The string escape
.CW \ef
is form-feed (to simplify translation of C programs).
.SH
.I "Compilers and utilities"
.IP \(bu
.I Iar 's
source directory has been renamed from
.CW ar
to
.CW iar .
.IP \(bu
.CW mk
understands the long-name table in Windows' archive files, preventing
spurious out-of-date status and other confusing results in builds.
.IP \(bu
.CW sqz
and
.CW zqs
can compress larger ARM and PowerPC executables.
.IP \(bu
.CW kprof
uses a table now provided by
.CW /dev/kprof
to provide profiling results to the resolution selected by a given platform.
.SH
.I "Hosted and Native Inferno"
.LP
Changes common to hosted and native kernels:
.IP \(bu
The
.CW HOSTMODEL
and
.CW TARGMODEL
for Plan 9 are now
.CW Plan9
not, rather confusingly,
.CW Inferno .
A good few source files have been renamed accordingly.
.IP \(bu
The memory allocation functions have been modified slightly to support the addition of
memory monitoring and profiling.
Some functions have also been added to the C library supporting
.I emu
and the kernels,
with an eye to starting the revision of Styx, based on the current 9P2000.
Consequently, the
include file
.CW lib9.h
for all platforms has been modified:
to add new functions such as
.CW setmalloctag ;
to make the types of parameters to the
.CW malloc
calls uniform (and reflect the documentation, as it happens),
so that sizes are always unsigned;
to change the type of a parameter to
.CW strchr
and
.CW strrchr
from
.CW char
to
.CW int ;
to remove obsolete definitions such as
.CW UMFILE
and
.CW UMDIR ;
and to add new functions for use inside the kernels.
Several new functions are strictly for internal use
(and thus might change in future), and
they have not been added to section 10.
One exception is the new function
.CW tokenize ,
documented in
.I getfields (10.2)
and used by
.I parsecmd (10.2).
.I Getfields
replaces the function called
.CW parsefields ,
which has been removed, and all calls to it changed to use
.CW getfields .
The higher aim of some of these otherwise fussy changes is
to work towards making Inferno and Plan 9 drivers interchangeable
(as best we can).
.IP \(bu
To help decouple authentication methods from identity setting, two new files
.CW caphash
and
.CW capuse
have been added to
.CW #c
(a temporary location for them), supported by code in
.CW auth.c
.CW /os/port/auth.c ). (
Their use will soon replace the
.CW setid
functionality of
.I keyring-auth .
They will not be documented until then.
.IP \(bu
.CW /emu/exception.c
and
.CW /os/port/exception.c
no longer trap the use of the
.CW exit
statement (by accident of implementation).
.CW \(bu
.CW /emu/dis.c
and
.CW /os/port/dis.c
do not leave a process in Broken state when it
receives an exception because a kernel memory allocation failed.
.IP \(bu
The JIT compilation of case statements has fixed a day one bug
that caused a degenerate form of
.CW case
(with only a default arm) to be compiled incorrectly.
.IP \(bu
The 386 JIT will allow rescheduling, and the scheduling is finer grained on the ARM.
.IP \(bu
ARM code generation produces correct code for some list accesses that were previously wrong
(the Dis operator HEADM)
.IP \(bu
.I Emu
has the following changes specific to it:
.RS
.IP \-
The mouse event queue in
.CW devcon.c
is now a circular queue without locks as in the native kernel;
this prevents a scheduling problem under Linux.
.IP \-
The
.CW READSTR
constant defined by the native kernels is now also defined by
.CW emu .
.IP \-
The function previously called
.CW rendezvous
is now called
.CW erendezvous
to avoid a type clash with a library function on Plan 9
(its `rendezvous' function takes an unsigned long as first parameter, not
.CW void* ).
.CW lib9.h
has changed accordingly where required.
.IP \-
.CW devcon.c
acquires
.CW caphash
and
.CW capuse .
.IP \-
A new file
.CW auth.c
must be included in every build.
.IP \-
Several drivers in
.CW emu
have been changed to use
.RS
.P1
	switch((ulong)c->qid.path ...)
.P2
.RE
to force 32-bit operations to be used when
.CW path
eventually becomes 64 bits.
.IP \-
Also in
.CW emu
the function
.CW oserrstr
now takes a buffer length, rather than assuming
.CW ERRLEN .
.IP \-
Obsolete code for time and directory mode conversions (!) has been removed from
.CW os-*.c .
.IP \-
Obsolete code for `daemonize' has been removed from
.CW os-*.c
and
.CW lib9 .
.RE
.IP \(bu
For the native kernels:
.RS
.IP \-
.CW /os/port/devprof.c
has been added but is not yet supported (it is not configured in to any kernel,
so no existing kernels are affected by its presence).
.IP \-
.CW /os/port/devcons.c
has
.CW caphash
and
.CW capuse
.IP \-
Every kernel configuration file must now include
.CW auth
in the
.CW port
section to include
.CW /os/port/auth.c .
.RE
...#.bp
...#.NH 1
...#Description by source file
...#.LP
...#.TS
...#lf(CW)w(2.5i) lf(R)w(4i) .
...#/appl/charon	T{
...#plumbs schemes that aren't built-in, if on an authorised list
...#.br
...#retries on error (but not POST)
...#.br
...#identifies itself as Mozilla to pass agent-name tests.
...#.br
...#bug fix: doesn't loop (exhausting memory) if a file ends with bad data.
...#.br
...#private version of Url
...#.br
...#CCI removed
...#.br
...#charon_code and charon_guiwm removed
...#.br
...#multiple windows
...#.br
...#detects HTML vs text correctly
...#.br
...#separate layout and gui display
...#.br
...#T}
...#/appl/cmd/diff.b	T{
...#compare binary files as documented
...#.br
...#don't quit if files can't be opened
...#.br
...#T}
...#/appl/cmd/strings.b	T{
...#new command
...#.br
...#T}
...#/appl/cmd/sh	T{
...#../ / ./ and # starting a (command) name all cause it to be treated as absolute
...#.br
...#T}
...#/appl/lib/auth.b	T{
...#allow nobody even if setid is 0 provided it appears in the algorithm list
...#.br
...#don't bind #D
...#.br
...#T}
...#/appl/lib/createsignerkey.b	T{
...#arguments
...#.br
...#don't bother with random
...#.br
...#error status
...#.br
...#T}
...#.TE
...#.TS
...#lf(CW)w(2.5i) lf(R)w(4i) .
...#/appl/lib/crypt/ssl3.b	T{
...#delete session id on alert
...#.br
...#T}
...#/appl/lib/ecmascript	T{
...#correct precedence for operators
...#.br
...#delete HTML comments
...#.br
...#T}
...#/appl/lib/isrv.b	T{
...#don't start a new shell
...#.br
...#T}
...#/appl/lib/login.b	T{
...#don't bind #D
...#.br
...#T}
...#/appl/lib/logind.b	T{
...#don't bind #D
...#.br
...#don't load (unused) Random
...#.br
...#minor internal changes.
...#.br
...#T}
...#/appl/lib/profile.b	T{
...#memory profiling
...#.br
...#T}
...#/appl/lib/srv.b	T{
...#be sure to FORKFD so file descriptors don't accumulate in parent
...#.br
...#T}
...#/appl/lib/ssl.b	T{
...#don't require #D to be bound since it can only be used locally
...#.br
...#T}
...#/appl/lib/usb/*	T{
...#see TI925 release
...#.br
...#T}
...#/appl/lib/wmlib.b	T{
...#calculate correct size of file browser (eg when full screen)
...#.br
...#don't mess with the cursor
...#.br
...#T}
...#/appl/minicharon	T{
...#moan if no window manager
...#.br
...#don't trap if module not yet loaded
...#.br
...#T}
...#/appl/wm/bounce.b
...#/appl/wm/man.b
...#/appl/wm/mand.b
...#/appl/wm/polyhedra.b
...#/appl/wm/wm.b	T{
...#correct window size in full screen mode
...#.br
...#T}
...#/appl/wm/reversi.b	T{
...#use fittoscreen(0)
...#.br
...#T}
...#/appl/wm/polyhedra.b	T{
...#sys->sleep(0) to yield
...#.br
...#T}
...#/man/2/security-ssl	T{
...#bind not required
...#.br
...#conventions documented accurately
...#.br
...#T}
...#/man/2/keyring-getstring	T{
...#makes it clear that it doesn't PROVIDE delimited i/o, but EXPECTS it (eg, via ssl(3))
...#.br
...#T}
...#.TE
...#.TS
...#lf(CW)w(2.5i) lf(R)w(4i) .
...#/crypt/jacobi.c	T{
...#add missing return statement
...#.br
...#T}
...#/emu/alloc.c	T{
...#changes for monitoring
...#.br
...#long for size throughout
...#.br
...#poolrealloc, now used by malloc
...#.br
...#poolmsize
...#.br
...#malloc and realloc tagging data with pc of allocation
...#.br
...#ud -> lud etc
...#.br
...#T}
...#/emu/chan.c	T{
...#space isn't frog, experimentally
...#.br
...#T}
...#/emu/dat.h	T{
...#READSTR definition
...#.br
...#Rept definition (will change)
...#.br
...#add BusyGC
...#.br
...#remove support for %N
...#.br
...#T}
...#/emu	T{
...#oserrstr takes buffer size (consequential changes throughout)
...#.br
...#no %N
...#.br
...#Plan 9's HOSTMODEL -> Plan9 not Inferno (!)
...#.br
...#msize -> hmsize in some cases
...#.br
...#rendezvous -> erendezvous
...#.br
...#T}
...#/emu/devcon.c	T{
...#no %N, Nconv
...#.br
...#remove debugging memout file
...#.br
...#use of (ulong)c->qid.path ...
...#.br
...#remove logmsg calls
...#.br
...#T}
...#/emu/devprof.c	T{
...#memory profiling
...#.br
...#T}
...#/emu/devprog.c	T{
...#msize -> hmsize because malloc and heap addresses are different
...#.br
...#T}
...#/emu/dis.c	T{
...#instrument garbage collections
...#.br
...#force periodic garbage collection passes when not idle (BusyGC)
...#.br
...#T}
...#/emu/discall.c	T{
...#tag QLock structures with owner
...#.br
...#T}
...#/emu/fns.h	T{
...#oserrstr definition
...#.br
...#obsolete gsleep defn removed
...#.br
...#T}
...#/emu/main.c	T{
...#obsolete gsleep defn removed
...#.br
...#T}
...#.TE
...#.TS
...#lf(CW)w(2.5i) lf(R)w(4i) .
...#/emu/os-*	T{
...#dflag becomes simply don't enable graphics terminal (ie, save/restore tty state)
...#.br
...#daemonize calls removed [do it from outside]
...#.br
...#rendezvous -> erendezvous
...#.br
...#some files had obsolete timeconv and dirmodconv code, now removed
...#.br
...#T}
...#/emu/proc.c	T{
...#provisional rpt code (will change, will move)
...#.br
...#T}
...#/emu/vlrt-Nt.c	T{
...#use dat.h not local definitions
...#.br
...#T}
...#/include/interp.h	T{
...#force HEAP_ALIGN to provide extra cell in heap header for heap profiling
...#.br
...#new functions: heapmonitor, hmsize
...#.br
...#utfnlen removed  (local to interp/runt.c)
...#.br
...#T}
...#/include/pool.h	T{
...#sizes are now unsigned
...#.br
...#poolcompact defn, new poolmsize, poolrealloc
...#.br
...#T}
...#/include/tk.h	T{
...#extra state to control cursor
...#.br
...#T}
...#/interp/comp-386.c	T{
...#implement and enable interpreter rescheduling when JIT enabled
...#.br
...#T}
...#/interp/comp-arm.c
...#/interp/comp-thumb.c	T{
...#change arm rescheduling check to be similar to 386
...#.br
...#T}
...#/interp/gc.c	T{
...#instrument garbage collector
...#.br
...#add heapmonitor hook for devmem.c
...#.br
...#T}
...#/interp/heap.c	T{
...#define heapmonitor hook (default: nil)
...#.br
...#call it at appropriate places
...#.br
...#change // to /* comment
...#.br
...#add hmsize to account for alloc.c changes
...#.br
...#T}
...#/interp/keyring.c	T{
...#ensure keyring i/o functions return "failure" as intended (improves diagnostic of login/logind)
...#.br
...#T}
...#/interp/math.c	T{
...#min -> minimum (to avoid clash with C macro)
...#.br
...#T}
...#/interp/runt.c	T{
...#check for nil arrays in utf functions, and negative offsets
...#.br
...#T}
...#.TE
...#.TS
...#lf(CW)w(2.5i) lf(R)w(4i) .
...#/interp/string.c	T{
...#msize -> hmsize
...#.br
...#T}
...#/interp/tk.c	T{
...#cursor switching between apps
...#.br
...#T}
...#/interp/validstk.c	T{
...#msize -> hmsize
...#.br
...#T}
...#/interp/xec.c	T{
...#check that slice offset isn't negative
...#.br
...#T}
...#/kern	T{
...#new function utfecpy, added to directory and mkfile
...#.br
...#strchr, strrchr argument -> int not char
...#.br
...#T}
...#/kfs	T{
...#replace DEBUG by KFSDEBUG
...#.br
...#remove obsolete malloc definition
...#.br
...#ensure HFILES includes emu dat.h and fns.h
...#.br
...#T}
...#/lib9/errstr-*	T{
...#add support for buffer limit to oserrstr
...#.br
...#T}
...#/lib9	T{
...#exits argument shouldn't be const
...#.br
...#add utfecpy
...#.br
...#remove log-* and logging stuff from print.c
...#.br
...#remove printcol from doprint.c
...#.br
...#T}
...#/man/1/gettar	T{
...#document lstar's format
...#.br
...#T}
...#/man/*	T{
...#extraneous/incorrect cross-references corrected
...#.br
...#T}
...#/usr/inferno/mkfile	T{
...#-Inferno -> -Plan9 for several things
...#.br
...#(because of HOSTMODEL/TARGMODEL change)
...#.br
...#mkfile-Plan9-* TARGMODEL -> Plan9 not Inferno
...#.br
...#T}
...#/os/ip/ip.c	T{
...#adjust length after options stripped
...#.br
...#T}
...#/os/ip/kernel.h	T{
...#strrchr char -> int
...#.br
...#T}
...#/os/port/alloc.c	T{
...#int -> ulong in sizes
...#.br
...#same memory allocation conventions as /emu/alloc.c (re sizing, quanta)
...#.br
...#strip last aspects of audit
...#.br
...#other changes similar to /emu/alloc.c
...#.br
...#T}
...#/appl/acme	T{
...#raise an non-nil exception, not empty string
...#.br
...#T}
...#/appl/charon	T{
...#error when no window manager running
...#.br
...#cookies code being added/improved
...#.br
...#java script fixes/enhancements
...#.br
...#T}
...#/appl/cmd/install/install.b	global is default now
...#/appl/cmd/install/wrap.b	extra package name check
...#/appl/cmd/sh	code tidy up
...#/appl/ebook	ongoing changes
...#/appl/lib/dis.b	offset from fp to mp fix
...#/appl/lib/dividers.b	extra bind command to fix dividers issue
...#/appl/lib/ecmascript.b	T{
...#parsing of '/' improved (division or start of
...#regular expression)
...#.br
...#T}
...#/appl/lib/parseman.b	extra troff commands accounted for
...#/appl/lib/profile.b	bind of #P only if needed
...#/appl/lib/translate.b	hash code fix
...#/appl/wm/c4.b	evaluation function improvement
...#/appl/wm/pen.b	namechan() call moved to fix bug
...#/appl/wm/polyhedra.b	cosmetic changes
...#/appl/wm/readmail.b	slight code improvements
...#/appl/wm/sendmail.b	ditto
...#/man/1/ebook	text improvements
...#/man/1/sh-std	ditto
...#/man/1/sum	sha1sum added
...#/man/2/keyring	hmac_sha1, hmac_md5 added
...#/man/3/kprof	slight rewrite
...#/man/4/export	9export added
...#/man/6/translate	new BUGS section comment
...#/man/9/button	padx, pady removed
...#/man/9/canvas	added grab commands
...#/module/keyring.m	added hmac routines
...#/module/sys.m	added DM* constants for future use
...#/emu/devcon.c	T{
...#caphash and capuse files added for future
...#development
...#.br
...#T}
...#/emu/dis.c	added Enomem check to broken progs
...#/emu/exception.c	added couple of extra string checks
...#/emu/exportfs.c	T{
...#nexterror() replaced by return to give
...#better error recovery
...#.br
...#T}
...#/emu/os-Nt.c	prints on console when ran out of kernel processes
...#image/bezier.c	getbezsplinepts() added
...#interp/comp-arm.c	headm bug fix, removed dodgy code
...#interp/comp-power.c	removed dodgy code
...#interp/comp-thumb.c	headm bug fix, removed dodgy code
...#interp/keyring.c	T{
...#generalization of certain keyring functions
...#.br
...#addition of hmac routines
...#.br
...#T}
...#interp/tk.c	tkcursorcmd() removed temporarily
...#/os/ip/devip.c	ipremove() replaced by devremove()
...#/os/ip/ip.c	fragoff now a ulong
...#/os/ip/tcp.c	extra safety checks
...#/os/port/devcons.c	caphash and capuse files added
...#/os/port/devkprof.c	general improvements
...#/os/port/dis.c	Enomem check on broken progs
...#/os/port/exception.c	added couple of extra string checks
...#/os/port/exportfs.c	T{
...#nexterror() replaced by return to give
...#better error recovery
...#.br
...#check against correct file offset when reading directories
...#.br
...#T}
...#/os/port/utils.c	parsefields(), stroll() removed
...#/tk/canvs.c	T{
...#extensions to tk: grab set tag, grab release tag,
...#.br
...#grab ifunset tag
...#.br
...#T}
...#/tk/ctext.c	T{
...#text widget tag highlight fix
...#text widget tag index fix
...#.br
...#T}
...#/tk/entry.c	borderwidth default to 0 in entry widget
...#/tk/menus.c	menu button release fix (off by the borderwidth bug)
...#/tk/scrol.c	T{
...#scrollbar selection fixes (off by 1 bugs)
...#.br
...#autorepeat code added but disabled
...#.br
...#T}
...#/tk/utils.c	tkinsidepoly() function
...#/tk/xdata.c	unused globals removed
...#/tk/*	T{
...#draw methods take extra parameter
...#.br
...#hit methods added
...#.br
...#tkcfirsttag(), tkclasttag() fixes
...#.br
...#tkrunpack() argument type change
...#.br
...#T}
...#.TE
