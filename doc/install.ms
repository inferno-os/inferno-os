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
\l'1i'
.KE
..
\" step numbers
.nr ,s 0 1
.af ,s a
.am NH
.nr ,s 0 1
..
.de Sn		\" .Sn "step"
•\ Step \\n(H1\\n+(,s: \\$1
..
.de Ss
.P1
.B
.Sn "\\$1"
.P2
..
.TL
Installing the Inferno Software
.AU
Vita Nuova
.br
support@vitanuova.com
.br
12 June 2003
.SP 4
.LP
Inferno can run as either a native operating system, in the usual way, or as a
.I hosted
virtual operating system,
running as an application on another operating system.
This paper explains how to install Inferno from the distribution media
to a hosted environment and how to configure the system for
basic networking.
.LP
Inferno can run as a hosted virtual operating system on top of
Plan 9, Unix or Windows.
In this paper, the term
.I Unix
is used to cover all supported variants, currently FreeBSD, Linux, HP/UX, Irix and Solaris,
and the term
.I Windows
covers Microsoft Windows (98, Me, Nt, 2000, and XP).
(Windows 98 might first require installation of the Unicode layer update from Microsoft.)
.NH
Preparation
.LP
You should ensure at least 150 Mbytes of free space on the filesystem.
The installation program will copy files from the distribution CD to a
directory on the filesystem called the
.I inferno_root
directory.
You can choose the location of this directory.
If you are installing to a multiuser filesystem outside your control a subdirectory of your home
directory might be most sensible. If you plan to share the Inferno
system with other users then common choices for
.I inferno_root
are
.CW /usr/inferno
on Unix and Plan 9 systems, and
.CW c:\einferno
on Windows systems.
Where these appear in examples in this paper you should substitute
your own
.I inferno_root
directory.
.Ss "Choose the \fIinferno_root\fP directory."
Ensure that the user who will run the installation program has
appropriate filesystem permissions to create the
.I inferno_root
directory and
files and subdirectories beneath it.
.NH
Copying Files
.LP
On all platforms the files will be owned by the user doing the installation,
except for installation onto a FAT file system (eg, on Windows), where the files
appear to be owned by
.CW Everyone
because FAT does not record ownership.
.Ss "Insert the distribution CD into the CD drive."
On Unix and Plan 9,
mount the CD to a suitable location on the filesystem, call this location
.I cd_path .
On Windows, note the drive letter of the CD, call this drive letter
.I cd_drive .
The files will be copied by an Inferno hosted installation program which runs
directly from the CD.
The directory
.CW /install
on the CD contains an installation program for each supported platform \- a shell
script for Unix and Plan 9 and an executable for Windows.
The Plan 9 install script is called
.CW Plan9.rc
and determines the CPU type from the environment variable
.CW cputype .
The Unix install scripts all have names of the form
.CW \fIhost_os\fP-\fIhost_arch\fP.sh
where
.I host_os
will be one of:
.CW FreeBSD ,
.CW Linux ,
or
.CW Solaris
and
.I host_arch
will be one of:
.CW 386 ,
.CW mips ,
.CW power
or
.CW sparc .
Most platforms offer just the one obvious combination.
The Windows installation program is called
.CW setup.exe ;
it is used on all varieties of Windows.
The next step describes how to begin the installation by running the program
that corresponds to your host system.
.Ss "Run the installation script."
The installation program will copy files from the CD to the filesystem.
The Windows installation program will also create registry entries and add
an Inferno item to the Windows
.I start
menu.
On Plan 9, run
.P1
rc \fIcd_path\fP/install/Plan9.rc \fIinferno_root\fP
.P2
Where
.I inferno_root
is the path to the chosen Inferno root directory. The CPU architecture
will be inferred from the environment variable
.CW cputype .
On Unix, run
.P1
sh \fIcd_path\fP/install/\fIhost-os\fP-\fIhost_arch\fP.sh  \fIinferno_root\fP
.P2
Where
.I host_os
is the Unix variant name
.CW FreeBSD , (
.CW Irix ,
.CW Linux
or
.CW Solaris ).
.I host_arch
is the CPU type (eg,
.CW 386 ), 
and
.I inferno_root
is the path to the chosen Inferno directory.
On Windows, run
.P1
\fIcd_drive\f(CW:\einstall\esetup.exe
.P2
The Windows installation program will ask you to choose the location of the installation
directory on the hard disk.
.LP
On all platforms, a copy of Inferno
on the CD will install from various installation packages on the CD to the
.I inferno_root
subtree on the filesystem.
On any platform it installs support for all.
.LP
Inferno is now installed, but it needs to be configured
for your site.
The process acts as a quick tour of parts of the system.
The main tasks are to add local parameters to the network data base,
and to set up the authentication system.
If you are going to run Inferno standalone, for instance to experiment with Limbo
and the file serving interface,
most of what follows can be deferred indefinitely.
It is still worthwhile skimming through it, because the first few sections tell how
to start up Inferno with correct parameters (eg, root directory and graphics resolution).
(A configuration program that runs under the window system would be more convenient,
and fairly easy to do, but that has not yet been done.)
.NH
Running Inferno
.LP
Inferno host executables are all kept in a single directory corresponding
to the combination of host operating system and CPU architecture \- the Inferno
.CW bin
directory.
.P1
\fIinferno_root\fP/\fIhost_os\fP/\fIhost_arch\fP/bin
.P2
(On Windows the path might need
.CW \e
not
.CW /
of course.)
That directory can be added to the search path of the host system's command interpreter,
and that process will be described first, although as discussed later one can use a script
instead and that is sometimes more convenient.
(Of course, the script will still need to refer to that directory.)
.LP
.I "Plan 9:\ \ "
Plan 9 users should add a line to their
.CW lib/profile
file that binds this directory after their
.CW /bin
directory.
.P1
bind -a /usr/inferno/Plan9/$cputype/bin /bin
.P2
The bind is done after the existing
.I bin
directory to avoid hiding the existing Plan 9 compilers.
If, at a later stage, you build either the hosted or native Inferno kernels for ARM or StrongARM
you should ensure that the Inferno compilers are used rather than
the Plan 9 compilers, since they differ in the implementation of
floating-point instructions (the Plan 9 ARM suite uses a byte order that is more plausible
than the order ARM dictates but therefore wrong).
That difference is likely to be resolved at some point but it has not yet been done.
.LP
.I "Windows:\ \"
The
.I host_os
is always
.CW Nt
(even for Windows 98, 2000 or XP)
and
.I host_arch
is always
.CW 386
and the installation program will create an entry on the
.I "start menu"
to invoke Inferno.
For Unix systems or Windows systems in which Inferno will be started
from a command shell, the environment variable
.CW PATH
should be set to include the Inferno
.CW bin
directory.
For Windows 95 and Windows 98 this should be done in the
.CW \eautoexec.bat
file by adding a line like
.P1
PATH=c:\einferno\eNt\e386\ebin;%PATH%
.P2
You will need to reboot Windows to have the system reread the
.CW \eautoexec.bat
file.
For Windows NT and Windows 2000 modify the
.CW Path
environment variable through
.I "Control Panel -> System -> Environment" .
.LP
If you are using an MKS or Cygwin Unix-like shell environment,
you might instead set:
.P1
PATH="c:/inferno/Nt/386/bin;$PATH"
.P2
and export it if necessary.
.LP
.I "Unix:\ \"
For Unix  systems, for
.CW sh
derivatives, the environment variable
.CW PATH
should be set to include the Inferno
.CW bin
directory.
This might be done in your
.CW .profile
file by adding a line like
.P1
PATH="/usr/inferno/Linux/386/bin:$PATH"
.P2
Don't forget to ensure that
.CW PATH
is exported.
You may need to log out and back in again for the changes to take effect.
.KS
.Ss "Start Inferno."
Hosted inferno is run by invoking an executable called
.I emu .
.KE
On Windows, select the Inferno option from the
.I "start menu" .
This will invoke
.I emu
with appropriate arguments to find its files in
.I inferno_root .
If you need to change any of the options passed to
.I emu
when invoked from the
.I "start menu"
you need to do this by clicking the right mouse button
on the Windows task bar and choosing
.I "Properties -> Start Menu Programs -> Advanced"
to modify the shortcut used for Inferno.
For Unix and Plan 9, you will need to tell
.I emu
where to find the Inferno file tree by passing it the
.CW -r\fIrootpath\f(CW
command line option. For example
.P1
emu -r/usr/john/inferno
.P2
Without the
.CW -r
option it will look for the file tree in
.CW /usr/inferno
on Plan 9 and Unix and, when invoked from the command line on WIndows,
the default is
.CW \einferno
on the current drive.
(The Windows start menu by contrast has already been set to use the right directory by the installation software.)
.LP
When using graphics,
.I emu
will use a window with a resolution of 640 x 480 pixels by default. To use a larger resolution
you will need to pass
.I emu
an option
.CW -g\fIXsize\f(CWx\fIYsize\f(CW
on the command line. So, for example, to invoke
.I emu
as above but with a resolution of 1024 x 768 pixels the full command line
would be
.P1
emu -r/usr/john/inferno -g1024x768
.P2
When invoked in this way
.I emu
displays a command window running the Inferno shell
.CW /dis/sh.dis .
To avoid typing the command line options each time you invoke
.I emu
you can store them in the environment variable
.CW EMU
which is interrogated when
.I emu
is started and might as well be set along side the
.CW PATH
environment variable if the same configuration options are to be used on
each invocation.
.P1
set EMU="-rd:\eDocuments and Settings\ejohn\einferno -g1024x768"
.P2
for Windows.
.P1
EMU=(-r/usr/john/inferno -g1024x768)
.P2
for Plan 9, and
.P1
EMU="-r/usr/john/inferno -g1024x768"
.P2
for Unix.
An alternative to using the
.CW EMU
environment variable is to place the correct invocation in a
script file (or batch file, for Windows) and invoke that instead
of running
.I emu
directly.
It is important to note that for Windows the
.CW -r
option also serves to indicate both the drive and directory on to which the software
has been installed. Without a drive letter the system will assume the
current drive and will fail if the user changes to an alternative drive.
Once the environment variables or scripts are set up, as described above, invoking plain
.P1
emu
.P2
or the appropriate script file,
should result in it starting up Inferno's command interpreter
.I sh (1),
which prompts with a semicolon:
.P1
; 
.P2
You can add a further option
.CW -c1
to start up
.I emu
in a
mode in which the system compiles a module's
Dis operations to native machine instructions when a module
is loaded.
(See the
.I emu (1)
manual page.) 
In
.I compile
mode programs that do significant computation will run much faster.
Whether in compiled or interpreted mode you should now have a functional
hosted Inferno system.
When Inferno starts the initial
.CW /dis/sh.dis
it reads commands from the file
.CW /lib/sh/profile
before becoming interactive. See the manual pages for the shell
.I sh (1)
to learn more about tailoring the initial environment.
.LP
The semicolon is the default shell prompt. From this command window
you should be able to see the installed Inferno files and directories
.P1
lc /
.P2
The command
.I lc
presents the contents of its directory argument in columnar fashion to standard
output in the command window.
.P1
; lc /
FreeBSD/     Unixware/    icons/       libkern/     man/         prof/
Hp/          acme/        include/     libkeyring/  mkconfig     prog/
Inferno/     appl/        keydb/       libmath/     mkfile       services/
Irix/        asm/         legal/       libmemdraw/  mkfiles/     tmp/
LICENCE      chan/        lib/         libmemlayer/ mnt/         tools/
Linux/       dev/         lib9/        libtk/       module/      usr/
MacOSX/      dis/         libbio/      licencedb/   n/           utils/
NOTICE       doc/         libcrypt/    limbo/       net/         wrap/
Nt/          emu/         libdraw/     locale/      nvfs/
Plan9/       env/         libfreetype/ mail/        o/
Solaris/     fonts/       libinterp/   makemk.sh    os/
;
.P2
Only the files and directories in and below the
.I inferno_root
directory on the host filesystem are immediately visible to an Inferno process;
these files are made visible in the root of the Inferno file namespace.
If you wish to import or export files
from and to the host filesystem you will need to use tools on your
host to move them in or out of the Inferno visible portion of your host
filesystem (see the manual pages
.I os (1)
and
.I cmd (3)
for an interface to host commands).
(We plan to make such access direct, but the details are still being worked out.)
From this point onwards in this paper all file paths not qualified with
.I inferno_root
are assumed to be in the Inferno namespace.
Files created in the host filesystem will be created with the user id of
the user that started
.I emu
and on Unix systems with that user's group id.
.NH
Setting the site's time zone
.LP
Time zone settings are defined by
files in the directory
.CW /locale/timezone .
The setting affects only how the time is displayed; the internal representation does not vary.
For instance, the file
.CW /locale/GMT
defines Greenwich Mean Time,
.CW /locale/GB-Eire
defines time zones for Great Britain and the Irish Republic
(GMT and British Summer Time), and
.CW /locale/US_Eastern
defines United States
Eastern Standard Time and Eastern Daylight Time.
The time zone settings used by applications are read
(by
.I daytime (2))
from the file
.CW /locale/timezone ,
which is initially a copy of
.CW /locale/GB-Eire .
If displaying time as the time in London is adequate, you need change nothing.
To set a different time zone for the whole site,
copy the appropriate time zone file into
.CW /locale/timezone :
.P1
cp /locale/US_Eastern /locale/timezone
.P2
To set a different time zone for a user or window,
.I bind (1)
the file containing the time zone setting over
.CW /locale/timezone ,
either in the user's profile or in a name space description file:
.P1
bind /locale/US_Eastern /locale/timezone
.P2
.NH
Running the
Window Manager
.I wm
.LP
Graphical Inferno programs normally run under the window manager
.I wm (1).
Inferno has a simple editor,
.I wm/edit ,
that can be used to edit the inferno configuration files.
The `power environment' for editing and program development is
.I acme (1),
but rather that throwing you in at the deep end, we shall stick to
the simpler one for now.
If you already know Acme from
Plan 9, however, or perhaps Wily from Unix, feel free to use Inferno's
.I acme
instead of
.I edit .
.Ss "Start the window manager."
Invoke
.I wm
by typing
.P1
wm/wm
.P2
You should see a new window open with a blue-grey background and a small
.I "Vita Nuova"
logo in the bottom left hand corner. Click on the logo with mouse button 1
to reveal a small menu.
Selecting the 
.I Edit
entry will start
.I wm/edit .
In common with most
.I wm
programs the editor has three small buttons in a line at its top right hand corner.
Clicking on the X button, the rightmost button,
will close the program down. The leftmost of the three buttons will allow the window
to be resized \- after clicking it drag the window from a point near to either one of its
edges or one of its corners. The middle button will minimise the window, creating
an entry for it in the application bar along the bottom of the main
.I wm
window. You can restore a minimised window by clicking on its entry in the application bar.
The initial
.I wm
configuration is determined by the contents of the shell
script
.CW /lib/wmsetup
(see
.I toolbar (1)
and
.I sh (1)).
.Ss "Open a shell window."
Choose the
.I shell
option from the menu to open up a shell window. The configuration of Inferno
will be done from this shell window.
.NH
Manual Pages
.LP
Manual pages for all of the system commands are available from a shell
window. Use the
.I man
or
.I wm/man
commands. For example,
.P1
man wm
.P2
will give information about
.I wm .
And
.P1
man man
.P2
will give information about using
.I man .
.I Wm/man
makes use of the Tk text widget to produce slightly more
attractive output than the plain command
.I man .
Here, and in other Inferno documentation you will see references to manual page
entries of the form \fIcommand\f(CW(\fIsection\f(CW)\fR.
You can display the manual page for the command by running
.P1
man \fIcommand\fP
.P2
or
.P1
man \fIsection\fP \fIcommand\fP
.P2
if the manual page appears in more than one section.
.NH
Initial Namespace
.LP
The initial Inferno namespace is built
by placing the root device '#/' (see
.I root (3))
at the root of the namespace and binding
.nr ,i 0 1
.af ,i i
.IP  \n+(,i)
the host filesystem device '#U' (see
.I fs (3))
containing the
.I inferno_root
subtree of the host filesystem at the root of the Inferno filesystem,
.IP  \n+(,i)
the console device '#c' (see
.I cons (3))
in
.CW /dev ,
.IP  \n+(,i)
the prog device '#p' (see
.I prog (3))
onto
.CW /prog ,
.IP  \n+(,i)
the IP device '#I' (see
.I ip (3))
in
.CW /net ,
and
.IP  \n+(,i)
the environment device '#e' (see
.I env (3))
at
.CW /dev/env .
.rr ,i
.LP
You can see the sequence of commands required to construct the current namespace
by running
.P1
ns
.P2
.NH
Inferno's network
.LP
If you are just going to use Inferno for local Limbo programming, and not use its
networking interface, you can skip to the section ``Adding new users'' at the end of this document.
You can always come back to this step later.
.LP
To use IP networking, the IP device
.I ip (3)) (
must have been bound into
.CW /net .
Typing
.P1
ls -l /net
.P2
(see
.I ls (1))
should result in something like
.P1
--rw-rw-r-- I 0 network john 0 May 31 07:11 /net/arp
--rw-rw-r-- I 0 network john 0 May 31 07:11 /net/ndb
d-r-xr-xr-x I 0 network john 0 May 31 07:11 /net/tcp
d-r-xr-xr-x I 0 network john 0 May 31 07:11 /net/udp
.P2
There might be many more names on some systems.
.LP
A system running Inferno, whether native or hosted, can by agreement attach to any or all resources that
are in the name space of another Inferno system (or even its own).
That requires:
.IP •
the importing system must know where to find them
.IP •
the exporting system must agree to export them
.IP •
the two systems must authenticate the access (not all resources will be permitted to all systems or users)
.IP •
the conversation can be encrypted to keep it safe from prying eyes and interference
.LP
On an Inferno network, there is usually one secure machine that acts as authentication server.
All other systems variously play the rôles of server and client as required: any system can import some resources (or none)
and export others (or none), simultaneously, and differently in different name spaces.
In following sections, we shall write as though there were three distinct machines:
authentication server (signer); server (exporting resources); and client (importing resources).
With Inferno, you can achieve a similar effect on a single machine by starting up distinct
instances of
.I emu
instead.
That is the easiest way to become familiar with the process (and also avoids having to install
the system on several machines to start).
It is still worthwhile setting up a secured
authentication server later, especially if you are using Windows on a FAT file system
where the host system's file protections are limited.
.LP
We shall now configure Inferno to allow each of the functions listed above:
.IP •
change the network database to tell where to find local network resources
.IP •
set up the authentication system, specifically the authentication server or `signer'
.IP •
start network services (two distinct sets: one for the authentication services and the other for
all other network services)
.NH
Network database files
.LP
In both hosted and native modes, Inferno uses a collection of text files
of a particular form to store all details of network and service configuration.
When running hosted, Inferno typically gets most of its data from the host operating system,
and the database contains mainly Inferno-specific data.
.LP
The file
.CW /lib/ndb/local
is the root of the collection of network database files.
The format is defined by
.I ndb (6),
but essentially it is a collection of groups of attribute/value pairs of the form
\fIattribute\fP\f(CW=\fP\fIvalue\fP.
Attribute names and most values are case-sensitive.
.LP
Related attribute/value pairs are grouped into database `entries'.
An entry can span one or more
lines: the first line starts with a non-blank character,
and any subsequent lines in that entry start
with white space (blank or tab).
.NH 2
Site parameters
.LP
The version of
.CW /lib/ndb/local
at time of writing looks like this:
.P1
database=
	file=/lib/ndb/local
	file=/lib/ndb/dns
	file=/lib/ndb/inferno
	file=/lib/ndb/common

infernosite=
	#dnsdomain=your.domain.com
	#dns=1.2.3.4	# resolver
	SIGNER=your_Inferno_signer_here
	FILESERVER=your_Inferno_fileserver_here
	smtp=your_smtpserver_here
	pop3=your_pop3server_here
	registry=your_registry_server
.P2
The individual files forming the data base are listed in order in the
.CW database
entry.
They can be ignored for the moment.
The entry labelled
.CW infernosite=
defines a mapping from symbolic host names of the form
.CW $\fIservice\f(CW
to a host name, domain name, or a numeric Internet address.
For instance, an application that needs an authentication service
will refer to
.CW $SIGNER
and an Inferno naming service will translate that at run-time to the appropriate network name for
that environment.
Consequently,
the entries above need to be customised for a given site.
(The items that are commented out are not needed when the host's own DNS resolver is used instead
of Inferno's own
.I dns (8).)
For example, our
.CW infernosite
entry in the
.CW local
file might look something like this
.P1
infernosite=
	dnsdomain=vitanuova.com
	dns=200.1.1.11	# resolver
	SIGNER=doppio
	FILESERVER=doppio
	smtp=doppio
	pop3=doppio
	registry=doppio
.P2
where
.CW doppio
is the host name of a machine that is offering the given services to Inferno,
and
.CW 200.1.1.11
is the Internet address of a local DNS resolver.
.Ss "Enter defaults for your site"
.LP
The only important names initially are:
.IP \f(CWSIGNER\fP 20
the host or domain name, or address of the machine that will act as signer
.IP \f(CWregistry\fP
the name or address of a machine that provides the local dynamic service
.I registry (4)
.IP \f(CWFILESERVER\fP
the primary file server (actually needed only by clients with no storage of their own)
.LP
All others are used by specific applications such as
.I acme (1)
mail or
.I ftpfs (4).
.LP
If you are using a single machine for signer and server/client, put its name in those three entries.
.NH 2
Connection server
.I cs (8)
and name translation
.LP
The connection server
.I cs (8)
uses the network database
and other
data (such as that provided by the host system and
the Internet DNS servers) to translate symbolic network names and services into instructions
for connecting to a given service.
In hosted mode,
network and service names are passed through to the host for conversion to numeric IP
addresses and port numbers. If the host is unable to convert a service name
the connection server will attempt to convert the name using mappings
of service and protocol names to Internet port numbers
in the file
.CW /lib/ndb/inferno :
.P1
tcp=infgamelogin port=6660	# inferno games login service
tcp=styx port=6666	# main file service
tcp=mpeg port=6667	# mpeg stream
tcp=rstyx port=6668	# remote invocation
tcp=infdb port=6669	# database server
tcp=infweb port=6670	# inferno web server
tcp=infsigner port=6671	# inferno signing services
tcp=infcsigner port=6672	# inferno countersigner
tcp=inflogin port=6673	# inferno credential service
tcp=infsds port=6674	# software download
tcp=registry port=6675	# registry(4)
udp=virgil port=2202	# naming service
.P2
For the moment, leave that file as it is.
You will only need to modify this file if in future
you add new statically-configured services to Inferno.
(Services that come and go dynamically might use
.I registry (4)
instead, a registry manager that allows a service to be found
using a description of it.)
.NH
Configuring a Signer
.LP
Before an Inferno machine can authenticate establish a secure connection to an Inferno
service on another machine, each system needs to obtain a certificate from a common signer.†
We talk here as though there is only one `signer' per site but in fact there can be application- or
group-specific ones.
For instance, a version of the Inferno games server automatically starts its own signing service to
keep the identities and keys used for game service separate from those of the primary
system, allowing users to set up their own gaming groups without fuss.
.FS
.FA
†The authentication system will shortly expand to a rôle-based one allowing a chain of certificates to be used,
from several signers, with delegation etc.
.FE
To use authenticated connections for the primary
file services we need to set up a signer to generate
certificates for users (see
.I createsignerkey (8)
and
.I logind (8)).
.LP
Choose an Inferno machine to become the signer.
If this is the first or only
Inferno machine on your network then make this machine the signer.
(It is more realistic if you start up a separate copy of
.I emu
and leave it in `console' mode without starting the window system.)
You can always move the function elsewhere later.
.Ss "Empty the secret file of secrets."
The authentication server verifies a user's identity by checking that the user knows a shared secret.
(In fact the secret is not used directly, but instead a scrambled value that was derived from it.)
The file
.CW /keydb/keys
holds those secrets; it is encrypted using a secret password or phrase known only to the
manager of the authentication server.
Having just installed Inferno, the file
should exist and be readable only by you (or the user as which the authentication service will run).
On the signer machine, type
.P1
ls -l /keydb/keys
.P2
You should see something like:
.P1
--rw------- M 7772 yourname inf 0 Jun 12 03:08 /keydb/keys
.P2
You should see something like the above.
If the file does not exist or is not empty or has the wrong mode, use:
.P1
cp /dev/null /keydb/keys; chmod 600 /keydb/keys
.P2
to set it right.
.Ss "Generate a signer key."
Next on the signer machine, run
.P1
auth/createsignerkey \fIname\fP
.P2
In place of
.I name
enter the network name of the signer. A fully-qualified domain name of a
host or individual is fine.
This value will appear as the signer name in each
certificate generated by the signer.
.I Createsignerkey
creates public and private keys that are used by the signer when generating
certificates.
They are stored in
.CW /keydb/signerkey ;
check that it has permissions that limit access to the user that will run the
authentication services:
.P1
; ls -l /keydb/signerkey
--rw------- M 32685 secrets inf 1010 Jul 07  2000 /keydb/signerkey
.P2
Use
.I chmod (1)
to set the mode to read/write only for the owner if necessary:
.P1
chmod 600 /keydb/signerkey
.P2
.Ss "Start the authentication network services"
Still at the signer console, type
.P1
svc/auth
.P2
That script (see
.I svc (8))
will check that the
.CW /keydb/keys
and
.CW /keydb/signerkey
files exist, and then
start the program
.I keyfs (4),
which manages the
.CW keys
file.
It will prompt for the password (pass phrase) you wish to use to protect the
.CW keys
file, now and on subsequent runs:
.P1
; svc/auth
Key: 
Confirm key:
.P2
It prompts twice to confirm it.
If successfully confirmed, it will then
start the
network services used by Inferno to authenticate local and remote users and hosts.
(If confirmation fails, retry by running
.CW svc/auth
again.)
.LP
You can check that they are running by typing:
.P1
ps
.P2
which should show something like the following:
.P1
       1        1    john    release    74K Sh[$Sys]
       3        2    john        alt    15K Cs
      10        9    john       recv    25K Keyfs
      11        9    john    release    44K Styx[$Sys]
      12        9    john       recv    25K Keyfs
      14        1    john        alt     8K Listen
      16        1    john    release     8K Listen[$Sys]
      18        1    john        alt     9K Listen
      20        1    john    release     9K Listen[$Sys]
      22        1    john        alt     9K Listen
      24        1    john    release     9K Listen[$Sys]
      26        1    john        alt     8K Listen
      28        1    john    release     8K Listen[$Sys]
      29        1    john      ready    73K Ps[$Sys]
.P2
There should be
.CW Keyfs
and
.CW Listen
processes.
.Ss "Enter user names and secrets."
For each user to be authenticated by the signer run
.P1
auth/changelogin \fIusername\fP
.P2
You will be prompted to supply a secret (ie, password or pass phrase) and expiration date.
The expiration date will be used
as the maximum expiration date of authentication certificates granted to that user.
.I Changelogin
(see
.I changelogin (8))
accesses the name space generated by
.I keyfs (4),
which has just been started above by
.CW svc/auth .
A user can later change the stored secret using the
.I passwd (1)
command.
For the signer to generate a certificate there must be at least one entry in the
password file.
If you are not sure at this stage of the names of the users that you want to
authenticate then create an entry for the user
.CW inferno
and yourself.
.NH
Establishing a Secure Connection
.LP
To establish a secure connection between two Inferno machines, each needs to present a public key with
a certificate signed by a common signer.
We shall make two public/private key sets, one for the server and one for a client
(they differ only in where they are stored).
We shall do the server first, because the usual network services require
the server possess some keys before they can start.
We shall then start those services, and finally sort out the client.
.Ss "Start the connection service."
The server still needs to make contact with the signer, so we need to start the basic connection service
.I cs (8).
If you are using the same instance of
.I emu
in which you invoked
.CW svc/auth
above, you should skip this step.
To check, you should see a new file in the
.CW /net
directory called
.CW cs .
Run the command
.P1
ls /net
.P2
You should see at least the following names in the output:
.P1
/net/cs
/net/ndb
/net/tcp
/net/udp
.P2
Otherwise, type
.P1
ndb/cs
.P2
That starts
.I cs (8).
Try the
.CW "ls /net"
again to check that the
.CW cs
file has appeared.
.LP
.Ss "Generate a server key set."
On the server machine (or in the `server' window),
use
.I getauthinfo (8)
to obtain a certificate and save it in a file named
.CW default
by running
.P1
getauthinfo default
.P2
.I Getauthinfo
will prompt for the address of your signer (you can often
just use its host name or even
.CW localhost )
and for a remote username and password
combination.
.I Getauthinfo
will connect to the
.I inflogin
service on the signer and authenticate you against its user and password database,
.CW /keydb/keys ,
using the username and password that you entered above.
Answer
.CW yes
to the question that asks if you want to save the certificate in a file.
.I Getauthinfo
will save a certificate in the file
.CW /usr/\fIuser\f(CW/keyring/default
where
.I user
is the name in
.CW /dev/user .
.NH
Network Services
.LP
As mentioned above, in a full Inferno network
the authentication services will usually be run on a secured machine of their own (the signer),
and the ordinary network services such as file service are not run on a signer.
If you are, however, using one machine for all functions, you can get the right
effect by starting another instance of
.I emu ,
to act as an Inferno host that is not a signer.
This one will run the services of a primary file server
and the site
.I registry (4).
.LP
Commands described in
.I svc (8)
start listeners for various local network services.
(The commands are actually shell scripts.)
As we saw above,
.CW svc/auth
starts the services on a signer.
.LP
Here we shall start the usual set of services.
.KS
.Ss "Start the network listener services."
Type
.P1
svc/net
.P2
.KE
Various network services will (should!) now be running. To confirm this type
.P1
ps
.P2
which should show something like the following:
.P1
; ps
       1        1    inferno    release    74K Sh[$Sys]
       7        6    inferno        alt    15K Cs
      13        1    inferno       recv    15K Registry
      14        1    inferno    release    44K Styx[$Sys]
      15        1    inferno       recv    15K Registry
      17        1    inferno        alt     8K Listen
      19        1    inferno    release     8K Listen[$Sys]
      22        1    inferno        alt     8K Listen
      24        1    inferno    release     8K Listen[$Sys]
      25        1    inferno      ready    74K Ps[$Sys]
.P2
There should be a few
.CW Listen
processes and perhaps a
.CW Registry .
.LP
You can also try
.P1
netstat
.P2
.I Netstat
prints information about network connections. You should see
several lines of output, each one describing an announced TCP or UDP service.
Depending upon the contents of the network configuration files we included on the CD,
you might see output something like this:
.P1
tcp/1      Announced    inferno    200.1.1.89!6668      ::!0
tcp/2      Announced    inferno    200.1.1.89!6666      ::!0
tcp/3      Announced    inferno    200.1.1.89!6675      ::!0
.P2
Each line corresponds to a network connection:
the connection name, the name of the user running the server,
the address of the local end of the connection,
the address of the remote end of the connection,
and the connection status.
The connection name is actually the protocol and conversation directory
in
.CW /net .
The connection addresses are all of the form \fIhost\f(CW!\fIport\fR
for these IP based services, and the remote addresses are not filled in
because they all represent listening services that are in the
.CW Announced
state.
In this example the third line shows a TCP service listening on port 6675.
Examining
.CW /lib/ndb/inferno
with
.CW grep
(see
.I grep (1))
shows that the listener on port 6675 is the Inferno registry service
.P1
grep 6675 /lib/ndb/inferno
.P2
gives
.P1
tcp=registry port=6675	# default registry
.P2
.LP
Now the server is ready but we need a client.
.LP
Either use a third machine or (more likely at first) simply start another
.I emu
instance in a new window.
Start its connection server, again by typing
.P1
ndb/cs
.P2
The connection server is fundamental to the Inferno network.
Once networking is set up, when subsequently starting up
a client you should start
.I cs
before starting the window system.
Note that if you are running the Inferno instance as a server, or combined
server and client,
the
.CW svc/net
that starts the network services
automatically starts
.I cs ,
and you need not do so explicitly.
.LP
.Ss "Generate a client certificate."
Obtain a certificate for the client in the same way as on the server.
We shall obtain a certificate for use with a specific server
by storing
it in a file whose name exactly matches the network address of the server
.P1
getauthinfo tcp!\fIhostname\fP
.P2
Use the current machine's
.I hostname .
.I Getauthinfo
stores the certificate in the file
.CW /usr/\fIuser\fP/keyring/\fIkeyname\fP
where
.I user
is the name in
.CW /dev/user
and
.I keyname
is the argument given to
.I getauthinfo .
Again, 
answer
.CW yes
to the question that asks if you want to save the certificate in a file.
.LP
Now that both client and server have a certificate obtained from the same signer
it is possible to establish a secure connection between them.
Note that getting keys and certificates with
.I getauthinfo
is normally done just once (or at most once per server when the
.CW default
key is not used).
In short, all the work done up to now need not be repeated.
After this, provided the keys were saved to a keyring file,
as many authenticated connections can be made as desired
until the certificate expires (which by default is whenever the password entry
was set to expire).
Also note that the certificates for different machines can have
different signers, and one can even use different certificates for the same machine
when the remote user name is to differ
(the
.CW -f
option of
.I getauthinfo
can then be useful to force an appropriate keyring name).
.Ss "Make an authenticated connection."
The script
.CW svc/net
on the server started fundamental name services and also a Styx file service.
That can also be started separately using
.CW svc/styx .
In either case the namespace that is served
is the one in which the command was invoked.
Now you can test the service.
.LP
Confirm that
.CW /n/remote
is an empty directory by typing
.P1
lc /n/remote
.P2
You can now mount the server's name space
onto the client's directory
.CW /n/remote
by typing
.P1
mount  \fIserveraddr\fP /n/remote
.P2
Where
.I serveraddr
is the IP address of the server or a name that the host can resolve to the
IP address of the server.
Now
.P1
lc /n/remote
.P2
should reveal the files and directories in the namespace being served by the server.
Those files are now also visible in the namespace of your shell.
You will notice that these changes only affect the shell in which you ran the
.I mount
command \- other windows are unaffected.
You can create, remove or modify files and directories in and under
.CW /n/remote
much as you can any other file or directory in your namespace.
In fact, in general, a process does not need to know whether a file
actually resides locally or remotely.
You can unmount the mounted directory with
.I unmount .
Type
.P1
unmount /n/remote
.P2
You can confirm that it has gone by running
.P1
ls /n/remote
.P2
All connections made by Inferno are authenticated. The default connection
made by
.I mount
is authenticated but uses neither encryption nor secure digests.
You can pass an argument to
.I mount
to specify
a more secure connection:
its
.CW -C
option gives it a hashing and an encryption algorithm to be applied to
the connection.
.KS
.Ss "Make a secure authenticated connection."
For example,
.P1
mount  -C sha1/rc4_256 \fIserveraddr\fP /n/remote
.P2
makes an authenticated connection to the machine given by
.I serveraddr ,
then engages SHA1 hashing for message digesting and 256-bit RC4 for encryption.
.KE
It mounts the namespace served by
.I serveraddr 's
Styx service on the local Inferno directory
.CW /n/remote .
.NH
Adding new users
.LP
Every inferno process has an associated
.I "user name" .
At boot time the user name is set equal to your login name on the host
operating system.
The user name is used by
.I wm/logon
to select the home directory, and
by other programs like
.I mount
when it searches for certificates.
(It can also control permission for file access on the local system in native Inferno
and some hosted Inferno configurations.)
When you attach to a server on another
system the user name in the authenticating certificate can be used by
the remote file service to set the user name appropriately there.†
.FS
.FA
†The details are system-dependent and currently subject to change.
.FE
.LP
To create a new user, copy the directory
.CW /usr/inferno
into
\f(CW/usr/\fP\fIusername\fP.
If the user is to have access to services on the network,
make an authentication server entry using
.I changelogin (8).
The user can change the stored secret using
.I passwd (1),
if desired.
Having logged in for the first time, the user should generate
a default public/private key set using
.I getauthinfo (8).
(The authentication services must be running somewhere.)
.LP
The
.I wm
window manager program
.I wm/logon
allows a user to login to the local Inferno system as an Inferno
user (different from the host user name).
Its use is shown next.
.Ss "Re-start Inferno."
You should now close down any instances of
.I emu
that you are currently running.
The quickest way to do this is to
type
.I control-c
in the emu window in which you ran
.I wm/wm .
Start a new
.I emu ,
as before, by either running
.P1
emu
.P2
or by choosing the appropriate entry from your start menu on
Windows machines. This time, start network services
.P1
svc/net
.P2
and then run
.P1
wm/wm wm/logon
.P2
and log in as user
.I inferno .
When you log in,
.I wm/logon
will change directory to
.CW /usr/inferno
and then write the name
.CW inferno
to
.CW /dev/user .
If the file
.CW /usr/inferno/namespace
exists it will be used to construct a new namespace for the user
based on the commands that it contains (see
.I newns (2)).
.NH
What next
.LP
You should now have a fully functional Inferno system.
You will need to have a three button mouse to use
.I acme ,
.I wm ,
or
.I plumbing .
.LP
To learn more you could start with the manual pages for:
.I intro (1),
.I emu (1),
.I wm (1),
.I wm-misc (1),
.I sh (1),
.I acme (1),
and
.I limbo (1)
and also the papers in sections 1, 2 and 3
of Volume 2 of
.I "The Inferno Programmer's Manual" .
