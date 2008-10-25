.\" this is an extract of port.ms: change that too if needed
.pl 9999
.SH
Installing hosted Inferno from source
.SH
Overview
.PP
Like the native kernels
.CW emu
relies on several auxiliary libraries (the source of which
it often shares with the native kernels).
Emu itself is built by the
.CW mkfile
in the
.CW emu
subdirectory containing the platform-specific source for the host platform.
Each library has its own
.CW mkfile ;
the various components are made in the right order by the
.CW mkfile
at the root of the Inferno tree.
The
.CW mkfile
for each platform will also invoke
.CW mk
recursively to make the appropriate libraries
for a given configuration.
.PP
The Unix emu variant generally is covered by `POSIX' (with common extensions)
but each Unix port has one file that differs considerably for each port,
namely \f5emu/\fP\fIplatform\fP\f5/os.c\fP, the differences
corresponding to the different ways under Unix of implementing kernel-scheduled
threads efficiently.
.PP
There are working emu versions
for
FreeBSD/386,
Irix/mips,
Linux/386,
NetBSD/386,
MacOSX/386,
MacOSX/power,
Plan 9,
Solaris/sparc,
and Windows (NT, 2000 and Explorer plug-in).
Each platform typically uses mechanisms specific to the host operating
system to implement Inferno's internal thread/process structure.
POSIX threads have often been found to be insufficient (poorly implemented)
on some platforms, and if so are avoided.
See
.CW kproc
in
.CW emu/*/os.c .
.PP
Source is included for ports to HP/UX (S800 architecture),
Solaris/386, and Unixware, in case someone wishes to take them up now,
but we have not determined their fitness.
.PP
The Plan 9 hosted implementation is unusual in that it supports
several processor types:
.CW 386 ,
.CW mips ,
.CW power
(Power PC)
and
.CW sparc .
Furthermore, all versions of
.CW emu
can be built on any processor type, in the usual way for Plan 9.
.PP
Otherwise, as distributed,
.CW emu
for a platform can only be built when running on that platform.
.PP
One unusual variant makes the whole of Inferno a plug-in for Microsoft's
Internet Explorer, giving the same environment for Inferno applications
running in an HTML page as is provided by hosted or native Inferno.
That is, there is not a distinct `applet' environment with special programming interfaces.
The source for the various plug-in components is found in
.CW /tools/plugin
and
.CW /usr/internet
within the Inferno tree; they use the version of
.I emu
defined by the configuration file
.CW /emu/Nt/ie .
.SH
Build steps
.PP
All the libraries and executables can be built in a tree containing only the source code.
To do that for a supported variant of hosted Inferno, on Unix or Plan 9, do the following
in the root of the Inferno tree:
.nr Ci 0 +1
.de Xx
.IP \\n+(Ci
..
.Xx
Edit
.CW mkconfig
to reflect your host environment,
specifically ROOT (which must be an absolute path name), SYSHOST and OBJTYPE.
The comments in the file should help you choose.
.Xx
Run
.CW makemk.sh
to rebuild the
.CW mk
command, which is used to build everything else.
.Xx
Set
.CW PATH
(or
.CW path
on Plan 9)
to include the
.CW bin
directory for the platform, which will now contain the
.CW mk
binary just built.
On Unix, export
.CW PATH .
.Xx
Then
.CW "mk nuke"
to remove any extraneous object files.
.Xx
Finally,
.CW "mk install"
to create and install the libraries,
.CW limbo
compiler,
.CW emu
for hosted Inferno, and auxiliary commands.
The rules do that in an order that ensures that the commands or libraries
needed by a later stage are built and installed first.
(Note that a plain
.CW mk
will not suffice, because it does not put the results in the search path.)
.LP
Doing something similar on Windows or Plan 9 currently requires the executable for
.CW mk
to be available in the search path,
since there is no equivalent of
.CW makemk.sh .
Otherwise the procedure is the same.
On Plan 9, of course, the host system's normal version of
.CW mk
should be adequate.
