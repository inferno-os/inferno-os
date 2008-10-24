.TL
Inferno Ports: Hosted and Native
.AU
Vita Nuova
27 April 2005
Revised 22 January 2007
.PP
Inferno is a portable environment, encompassing operating system,
languages, virtual machine and the tools required to build it.
This section briefly summarises the state of the ports and compilers
included in this release.
Directory names are relative to the root of the Inferno release tree,
unless otherwise specified by the context.
.PP
All components are built using the program
.CW mk ,
based on `make'-like recipes found in the
.CW mkfile
in each source directory throughout the Inferno tree.
.CW Mk
is described by the manual page
.I mk (10.1)
in Volume 1; a more tutorial discussion, including
a summary of differences with Unix
.I make ,
can be found in
.I "Maintaining Files on Plan 9 with Mk"
by Hume and Flandera,
reprinted in this volume.
The source for
.CW mk
itself is included in
.CW utils/mk .
It is included ready-made in the full and source-only distributions, to make life easier.
It must be compiled manually only on the initial port to a new host environment;
instructions for that are given below.
.PP
.NH 1
The C compilers
.PP
An unusual property of the compiler suites used to compile native
Inferno is that there is no difference in configuration or content
between a `compiler' (compiling on the same system and processor type as the target)
and a `cross compiler' (compiling on a host that differs from the target),
even when the host operating systems are quite different.
Indeed, in their ancestral home, Plan 9, it is the default action to compile
instances of all compilers for all possible target architectures,
as a matter of course.
.PP
The main difference between this suite and the original Plan 9 suite is
that all Plan 9 C extensions have been eliminated from the compiler's own source,
allowing it to be compiled on environments that accurately support
ANSI C and a few necessary Posix functions.
.PP
The source for the compilers is found in subdirectories of
.CW utils .
The compilers are named as follows:
.RS
.IP \f50c\fP 8
MIPS compiler for 64-bit little-endian R4000 MIPS (or `\f5spim\fP')
.IP \f51c\fP
68000 compiler, usable with the Motorola Dragonball
.IP \f52c\fP
680x0 compiler for x >= 2
.IP \f55c\fP
ARM compiler
.IP \f56c\fP
AMD64
.IP \f58c\fP
Intel x86 compiler, for x>2
.IP \f5kc\fP
Sun SPARC compiler
.IP \f5qc\fP
PowerPC compiler
.IP \f5vc\fP
MIPS R[234]000 in 32-bit big-endian mode
.RE
.LP
The compilers share components, compiled into a library from
source in the directory
.CW utils/cc .
The corresponding assemblers and linkers are found in similarly
named directories:
.CW 2a
and
.CW 2l
are the assembler and linker for use with
.CW 2c
for instance.
Note that this suite is unusual in that the compilers and assemblers produce
a binary assembly language that is finally converted to machine code
by the linker.
The assembler is used only to write machine-language assist for the operating
system, or a run-time routines using instructions not accessible from C,
and is not used by the compiler.
See the paper ``Plan 9 C compilers'' by Ken Thompson,
reprinted in this volume.
.PP
With the exception of the 68000 compiler, all the compilers have been
used extensively to compile Inferno, and most have been used
to compile Plan 9 and all its applications; and we have found them solid.
The 68000 compiler was used to attempt a port of Inferno to the Motorola
Dragonball (in the Palm Pilot).
It is included here in case someone wishes to have another go.
We have no experience with it.
.PP
The ARM compiler
.CW 5c
supports the ARM (Strongarm, PXA) architecture;
the related compiler
.CW tc
generates ARM's Thumb instructions instead.
The output of both can be linked together by the ARM loader
.CW 5l
to achieve ARM-Thumb interworking.
.CW 5c
has been used to generate code for the StrongARM SA110 and SA1100
processors (the primary
targets for native Inferno for many years).
The code generated was greatly improved by Richard Miller.
The floating-point support is adequate for C programs: the compiler
generates ARM floating-point instructions, as implemented on the ARM7500 but
not on the Strongarm, where they must be emulated.
.PP
The PowerPC compiler supports the 32-bit PowerPC architecture only;
it does not support either the 64-bit extensions or the POWER compatibility instructions.
It has been used for production operating system work on the 405EP, 603, 70x, 821, 823, and 860.
On the embedded processors such as 405 and 8xx floating-point instructions must be emulated.
Instruction scheduling is not implemented; otherwise the code generated
is similar to that for the other load-store architectures.
The compiler makes little or no use of unusual PowerPC features such as the
counter register, several condition code registers, and multiply-accumulate
instructions, but they are sometimes
used by assembly language routines in the libraries.
The compiler does replace explicit comparisons by condition-setting instructions.
Its run-time conventions are more efficient than those of the PowerPC ABI.
.NH 1
Applications
.PP
Dis object files are portable across all variants of Inferno, hosted and native.
There need be only one copy of the Dis files to serve many different
versions of Inferno; they need not be rebuilt for each platform
and can be shared by different types of host.
Limbo insulates the programmer from all details of
the particular processor, including byte-ordering,
and consequently the applications themselves are portable.
.PP
The source for the applications is found in subdirectories of
.CW appl :
.CW appl/cmd
holds the source for most command line applications (that use no graphics);
.CW appl/wm
contains the source for most applications that run under
.I wm (1);
.CW appl/svc
contains the source for various system services and file servers;
.CW appl/mux ,
the source for the interactive television demo
.I mux (1);
.CW appl/charon ,
the source for the Charon web browser; and
.CW appl/acme
the source for Acme written in Limbo.
.PP
The
.CW mkfile
in each directory can currently only be used by an instance of
.CW mk
running
.I outside
the Inferno environment, under the host operating system.
This complicates its use with
.I acme (1),
normally requiring the use of the
.I os (1)
command.
In a few cases, there is a
.CW mashfile
that can be used by
.I mash-make (1)
to build a Limbo application from within Inferno (native or hosted).
A consistent approach to building applications both inside and outside
Inferno is being developed.
In any case, the resulting Dis files are portable once produced.
.NH 1
Hosted Inferno (emu)
.PP
There are currently four main variants of hosted Inferno: Plan 9, Unix (and clones), MacOS X and Windows.
The source is held in directory
.CW emu ,
with a subdirectory for each hosted platform:
.CW FreeBSD ,
.CW Irix ,
.CW Linux ,
.CW MacOSX ,
.CW NetBSD ,
.CW Nt
(for all Windows platforms, including the Internet Explorer plug-in),
.CW Plan9 ,
.CW Solaris ,
and so on.
Each platform directory has a
.CW mkfile
and one or more configuration files of the form described by
.I config (6).
An executable for a particular host type is built on that host type,
using the host's own command interpreter, not under Inferno.
Move to the
.CW emu
subdirectory appropriate to that host,
ensure the command interpreter's path variable includes
the directory containing the Inferno
.CW bin
directory for that host
(eg,
.CW /home/inferno/Solaris/sparc/bin ),
and run
.CW mk .
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
.NH 1
Native Inferno
.PP
As with the different versions of emu, once the native kernel is running, all applications
work straight away;
the same applications are used in native and emulated mode, subject to
suitable devices being available.
Because the portable compiler suite is used to compile native kernels,
and those compilers are automatically cross-compilers, all native Inferno
implementations can be built on any host platform.
Furthermore, the build procedures and resulting object files are the same.
.PP
Early ports in 1996 were made by Bell Labs to an internal device based on
the AMD 29000, an early ARM-based `network computer', and Intel-based PCs.
Between 1997 and 1999, Lucent concentrated mainly on the Strongarm platform
(SA1100), for various Digital/Intel development boards,
and especially several `web phones', including the Sword Webphone Reference Design.
It also undertook ports to other devices for experiment, or under contract.
.PP
Vita Nuova Limited also ported the system, both for its own purposes
and under contract to Lucent.
Targets included a small 386-based Internet device,
a set top Internet box using the PowerPC 603e,
a digital television set top box with a Strongarm SA110 and a Teralogic TL750 graphics chip,
the USR/3Com Edgeserver (in a chassis containing various types of line card),
various boards based on the PowerPC 823/821/860,
many different configurations of IBM PC,
and a Ziatech Pentium-based VME crate.
.PP
Distribution of most previous and existing ports is restricted by
the terms on which they were undertaken,
or because they were ports of older Inferno releases and not kept up to date.
We have included the following as examples in this distribution.
.SH
The StrongARM kernel
.PP
The source for the StrongARM kernels is split across several directories.
The directory
.CW os/sa1110
contains all code that is generally architecture-specific but platform-independent.
Other directories contain platform-specific code:
.CW os/cerf1110
for the Intrinsyc Cerfcube1110,
and
.CW os/ipaq1110
for the Compaq (as it then was) IPAQ H3650.
Earlier Webphone ports are tied to hardware that is not generally obtainable
and the ports to those
platforms included some software (notably modem software)
that cannot generally be distributed.
.PP
There is also a preliminary port to the ARM-based Intel XScale.
The code common to PXA implementations is in
.CW os/pxa .
The initial platform was the Intrinsyc Cerfboard 250; its code is in
.CW os/cerf250 .
A port to the Gumstix (see
.CW www.gumstix.com )
is in progress.
.PP
The platform's own bootstrap is used in all cases.
On the IPAQ, the Linux bootloader from Compaq (HP) Research must
be loaded onto the device first, following instructions given at
.CW www.handhelds.org .
See the
.CW README
file in each
.CW os
source directory for details.
.PP
Other ARM-based processors to which Inferno has been ported include
the ARM-7 evaluator kit (see
.CW os/ks32 ),
although its memory is tight,
and the TI925 including the TI OMAP.
The latter two ports were to proprietary TI925 implementations, and have not
been included, but there is a body of code common to all such platforms that
could be made available if that were useful.
.SH
The PowerPC kernel
.PP
The directory
.CW os/fads
contains the port of Inferno to the MPC8xx FADS development board.
It has been used with the MPC821, MPC823 and MPC860 processors.
It uses code common to MPC8xx processors, found in
.CW os/mpc .
The interface to the CPM is provided by
.CW cpm.c .
There are drivers for the real time clock,
flash devices (including a Flash Translation Layer driver),
and communications controllers in Ethernet,
UART, and IrDA mode
(see
.CW etherscc.c
and
.CW devuart.c ).
The IrDA has been used for Styx transport between a FADS board
and an IBM Thinkpad 560.
The file
.CW screen.c
drives an 8-bit per pixel LCD (TFT) display panel.
A sample interface to the on-chip video device of the MPC823 (only)
as wired on the FADS board using auxiliary chips can be found in
.CW devvid.c .
The York Electronics Centre developed a touch panel for us,
connected using SPI;
the driver is
.CW devtouch.c ,
and could be adapted for similar devices.
.PP
The bootstrap program for the FADS board is in
.CW os/boot/mpc ,
loosely derived from an older version of
.CW os/boot/pc .
It is initially converted to S records that are loaded into flash by MPC8BUG
from a PC, and thereafter the images of the boot and kernel images can
be updated using the flash devices provided by the system itself,
and the utility programs
.CW qconfig.b
and
.CW qflash.b
in
.CW appl/cmd/mpc .
.PP
Another port is to the Brightstar Engineering ip-Engine containing an MPC823
and an Altera FPGA.
See
.CW os/ipengine .
It uses common code from
.CW os/mpc .
The device driver that loads the FPGA is in
.CW devfpga.c ;
see
.I fpga (3)
for the interface and
.I fpgaload (8)
for a command to do it.
See the
.CW README
file for information on loading the kernel into the flash.
.PP
The most recent PowerPC port is to the IBM 405EP, and more specifically
to the Intrinsyc Cerfcube 405EP.
The source for that port is in
.CW os/cerf405 ;
lacking another 405EP platform for reference, the source code has not yet
been split into that common to all 405EP implementations and that specific
to the Cerfcube, although that would be easy to do.
.SH
The x86 kernel
.PP
The
.CW os/pc
directory contains the components for ports to 386, 486 and Pentium class machines.
The main difficulty is device support: in particular
only a limited set of Ethernet and graphics cards is supported.
We have used mainly the 3Com and Intel 82557 drivers.
A `generic' PC port is included that has a graphics driver that
should run on systems that provide a VESA BIOS mode.
.PP
We have a (slow) floating-point emulator for the 386 found in
.CW os/pc/fpi387.c ;
code to invoke it in trap can be provided on request.
.PP
The source for the PC bootstrap program
.CW 9load
is in
.CW os/boot/pc .
It is simply a copy of the current Plan 9 PC bootstrap program, with slight modifications
to allow it to be compiled on many host systems.
.SH
The Javastation 1 kernel
.PP
The directory
.CW os/js
has the first port
to the Sun Javastation 1.
It was done by Tad Hunt and Eric Van Hensbergen
in a matter of days to demonstrate Inferno at Java One in 1997.
It boots over the net using TFTP.
Javastations being a bit thin on the ground now,
it is unlikely to be directly usable unless you can find one second hand
(you might find a Javastation 2 coffee pot, but that is slightly different again).
That is a pity, because the machine was quite usable running Inferno and
Limbo applications, often surprising those used to the Java-based
offering on the same platform.
It is included as an example of a micro-SPARC port.
Beware that
.CW screen.c
has not yet been converted for Fourth Edition graphics
(partly because we no longer have a suitable device for testing).
.NH 1
Supporting tools
.PP
The
.CW utils
directory also contains ANSI C versions of other components of the
Plan 9 development suite,
such as
.CW nm ,
.CW ksize ,
.CW ar ,
and of course
the
.CW acid
debugger.
Most rely on
.CW libmach ,
a suite of functions forming a
library to handle the various object and executable files in one place.
.PP
Some other utilities give a portable
way to express some of the kernel build scripts:
.CW sed ,
.CW test ,
.CW rm ,
and
.CW mkdir .
On Plan 9,
.CW mk
and kernel build scripts use Plan 9's own shell,
.I rc .
On Unix systems, they use
.I sh .
On Windows, a version of Plan 9's
.I rc
has been ported to reduce the number of variants
to two, and keep the system self-contained; its source is in
.CW utils/rcsh 
and installs as
.CW rcsh.exe .
