.\"<-xtx-*> tbl changes.ms | troff -ms | lp -d stdout
.FP palatino
.ps 9
.nr PS 9
.vs 11
.nr VS 11
.nr dP 1
.nr dV 1p
.nr dT 4m
.nr XT 4
.TL
System and Interface Changes to Inferno
.AU
C H Forsyth
.br
Vita Nuova
.br
forsyth@vitanuova.com
.br
9 June 2003
.SH
Overview
.LP
This paper describes some of the changes made to Inferno
interfaces as they stood in the published Third Edition manuals,
to form the current Fourth Edition of the system,
and the broad effects on internal and external interfaces.
Changes include: extensions to the Limbo language;
new instructions in Dis and the virtual machine; extra content
in Dis object files; structure of the source tree; configuration of
.CW emu ;
replacement of the window system with changes to the client interface;
commands renamed, replaced, and removed;
revised support for network booting;
9P2000 becomes the basis for Styx;
a graphics model offering alpha-blended compositing and general pixel structure;
and improvements to Tk.
.NH 1
Limbo
.LP
Exceptions and fixed point have been added to the Limbo language.
They are described in more detail in separate notes by John Firth,
shortly to be available on the Vita Nuova web site
.CW www.vitanuova.com .
Channels can now be buffered.
A form of polymorphism is now available in Limbo.
.NH 2
Exceptions
.LP
Discussion of exceptions will be restricted here to implications for existing source code.
The most obvious changes are that
.CW Sys->rescue ,
.CW Sys->rescued ,
.CW Sys->unrescue
and
.CW Sys->raise
have vanished.
Instead the exception handling is expressed using constructions in the Limbo language.
Named exceptions can be declared and used (these are described in the note by Firth), and
they are declared as part of the type of functions that raise them.
There is also a general `failure' exception that effectively subsumes the old
.CW Sys->rescue
scheme, including run-time errors such as `out of memory' that can happen in almost any function.
Unlike named exceptions a `failure' exception can be raised or caught by any function,
and its value is a string.
The
.CW raise
statement raises an exception.
This is most obvious in commands that wish to produce an `exit status'.
Instead of
.P1
sys->raise("fail:usage");
.P2
one must now write
.P1
raise "fail:usage";
.P2
(That is one of the more common source changes required to Third Edition Limbo commands,
since that was the most common use of exceptions before.)
A block can have an
.CW exception
handler:
.P1
{
	a := array[128] of byte;
	dosomething(a);
} exception e {
"out of memory:*" =>
	sys->print("i need more space: %s\en", e);
"fail:*" =>
	sys->print("exit status: %s\en", e);
"*" =>
	sys->print("unexpected error: %s\en", e);
	raise;	# propagate it
}
.P2
If an exception is raised during the execution of the block (including functions it calls),
execution of the block is abandoned, and control transfers to the appropriate exception handler
(which is outside the block).
Because the compiler and run-time system know the scope of the exception,
values such as
.CW a
above are correctly reclaimed on exit from the faulty block.
Unhandled failures are propagated to callers; unhandled named exceptions (currently) become failures.
.LP
A process group can cause unhandled exceptions in any process in the group either to
propagate to all members of the group, or to be propagated to the process group leader
after destroying the other processes in the group.
This makes it easier to program recovery from exceptions within a group of concurrent processes.
For instance, if a process is expected to send to another on a channel, but fails unexpectedly instead
(eg, because memory was exhausted),
instead of leaving the intended recipient blocked on a receive operation, it can be sent
an exception to notify it of the failure of the other process, allowing it to take appropriate recovery action.
(This could sometimes be programmed using the
.CW wait
file of
.I prog (3),
but not always.)
.LP
Exception handling is intended for recovering from disaster.
We still think it is better Limbo style
to use tuples, channels and processes to make ordinary error handling explicit.
The few attempts to use failure exceptions to achieve `pretty' but peculiar control flow have had exactly the usual
effect of making the code hard to follow and error-prone.
.NH 2
Channels
.LP
Buffered channels have been added:
.P1
c := chan [N] of int;
.P2
where
.I N
is an integer value,
creates a channel that will allow up to
.I N
integer values to be sent to it without an intervening receive without blocking the sender.
If
.I N
is zero, the channel is unbuffered, equivalent to plain
.CW "chan of int" ,
and synchronises sender and receiver as before.
.LP
The restriction that a given channel value could not be sent to or received from in two
.CW alt
statements simultaneously has been removed.
.NH 2
Polymorphism
.LP
John Firth has implemented a form of parametric polymorphism in Limbo.
It too will be described in a separate note.
Currently we are still fussing over aspects of the constraint syntax
and some other implications of the most general form, and since some aspects are
therefore subject to change, including syntax, we have not yet published the details.
We think it is possible to use the following subset without having to change the code later:
.IP 1.
Function declarations can be parametrised by one or more type variables:
For example:
.RS
.P1
reverse[T](l: list of T): list of T
{
	rl: list of T;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}
.P2
Such a function can then be invoked on any compatible set of values.
The function invocation does not specify the type (the compiler does type unification on the parameters).
Thus the above can be used as:
.P1
l1: list of string;
l2: list of ref Item;
l3: list of list of string;
l1 = reverse(l1);
l2 = reverse(l2);
l3 = reverse(l3);
.P2
.RE
.IP 2.
ADTs can also be parametrised:
.P1
Tree: adt[T] {
	v: T;
	l, r: cyclic ref Tree[T];
};
.P2
allowing declaration of
.CW "Tree[ref Item]"
and
.CW "Tree[string]"
for instance.
.IP 3.
Values of the parametrised type can only be declared, assigned, passed as parameters, returned,
or sent down channels.
The only types that can be used as actual parameter types are reference types (ie,
.CW ref " ADT,"
.CW array ,
.CW chan ,
.CW list
and
.CW module ),
and
.CW string
(which is a value type but is implemented using a reference).
At some point we shall allow a function such as
.CW reverse
above to be invoked with any compatible type (not just reference types) but
that requires changes to Dis and the virtual machine not yet made.
.LP
The formal type parameters can be further constrained by listing a set
of operations that they must have (which currently implies the actual parameters
must be ADT types with compatible operations).
We are not completely happy with the current constraint syntax, and some other
aspects of the scheme, and so that
be described here later once we have settled it.
.NH 1
Dis and virtual machine
.LP
To make the Limbo changes and extensions some new operators were added to
the virtual machine.
(We also added a
.CW casel
operator to allow
.CW case
statements to work on
.CW big
values.)
Modules that have exception handlers also have a (new) exception table,
added to the Dis object format.
Furthermore, we moved the import table used by the
.CW load
operator out of the Dis data space into the object format
(which also makes it available for inspection by
.CW wm/rt
amongst others).
.LP
There is now an internal interface to set conditions under
which modules must be signed to be loaded, and to check a signature on a module.
Appropriate stubs are defined when module signing is not configured; if
.I sign (3)
is configured, however, it replaces them by ones that enforce its signing policy.
.NH 1
Window manager
.LP
The window manager
.I wm (1)
has been reimplemented by Roger Peppe.
It now multiplexes pointer and keyboard input to applications,
and manages windows on the display.
.I Tk (2)
no longer manages windows from inside the kernel.
In some ways the structure is closer to that of
.I mux (1)
and more specifically the design described in Rob Pike's paper ``A Concurrent Window System''.
It is possible to import and export window system environments between hosts.
.LP
This is one of the bigger causes of source file changes, although many of them
can be done by global substitutions (eg, using
.I acme (1)).
Appendix A gives details.
.CW Wmlib
is no longer the application's interface to the window system.
Instead that is done through a new
.CW Tkclient
module; see
.I tkclient (2).
(It uses a different
.CW Wmlib
as an auxiliary module,
and also uses a new
.CW Titlebar
module to allow the look of the window decoration to be changed more easily).
An application acquires a window by a call to
.CW Tkclient->toplevel ;
starts pointer or keyboard input if desired by calling
.CW Tkclient->startinput ;
and puts the window on screen (after sending it Tk configuration commands)
using
.CW Tkclient->onscreen .
Nothing appears on screen until that is called (which amongst other things avoids the resizing on start up that afflicted
the original scheme).
.CW Onscreen
gives it a connection to the window manager for pointer, keyboard and control input,
with a separate channel for each.
When it receives data from any of the channels
(typically using
.CW alt )
it must pass it to Tk using calls to appropriate
.CW Tkclient
functions.
.LP
The toolbar used by the old
.I wm
is now provided by a separate program
.CW wm/toolbar
(see
.I toolbar (1)),
and it is
.CW toolbar
that interprets the
.CW /lib/wmsetup
file.
.CW Wm
invokes
.CW wm/toolbar
by default so most users will see no difference, but it does make it easier to develop alternative interfaces.
More visible is that
.CW wm/logon
is now a
.I client
of the window manager, and must be invoked as follows:
.P1
wm/wm wm/logon
.P2
.LP
Applications need not even use
.I tk (2).
There is an interface for
.CW draw -only
clients,
.I wmclient (2).
.NH 1
Inferno source tree
.LP
The structure of the Inferno source tree has changed in the following ways.
.NH 2
Library source
.LP
The
.CW image
and
.CW memimage
directories have gone, replaced by
.CW libdraw
and
.CW libmemdraw .
The directories in the Inferno root that contain the source for libraries
now
always have names starting `\f5lib\f1':
.CW libcrypt ,
.CW libinterp ,
.CW libkeyring ,
.CW libmath ,
etc.
.NH 2
Emu source
.LP
The
.CW emu
directory now contains a subdirectory structure similar to the
.CW os
kernels, and uses a similar configuration file (parts list) to say what goes in
a given instance of
.CW emu .
This allows platform-dependent selection of drivers, libraries and even
.CW #/
(ie,
.I root (3))
contents to be done easily.
.LP
The top directory,
.CW /emu ,
contains:
.CW mkfile
that simply moves to the platform configured by
.CW /mkconfig ,
allowing builds in the Inferno root as before;
a subdirectory
.CW port
containing portable code (including some code shared by several platforms, such as
.CW devfs-posix.c );
and a subdirectory for each hosting platform, distinguished by an upper-case initial letter.
Current platforms include
.CW FreeBSD ,
.CW Irix ,
.CW Linux ,
.CW Nt
(for all Windows platforms after 95),
.CW Plan9 ,
.CW Solaris ,
and several others.
.NH 2
Emu configuration
.LP
Each platform-specific directory contains a configuration file with the
same structure and indeed similar contents to the ones used for the native kernel.
The default configuration file is called
.CW emu .
Another can be chosen, again in a similar way to the native kernel, by using
.P1
mk 'CONF=\fIcfile\fP'
.P2
where
.I cfile
is the name of the configuration file.
The name of the resulting executable file contains the configuration file name but depends on the platform:
it is \fIcfile\fP\f5.exe\fP on Windows, \f5o.\fP\fIcfile\fP on Unix systems, and \f58.\fP\fIcfile\fP on 386 Plan 9 systems.
The configuration file format and contents is documented for all types of kernels by
.I conf (10.6).
.NH 2
Tk source
.LP
The Tk implementation in
.CW libtk
has been made more modular.
It allows a significantly different `style' to be implemented,
and although that is by no means trivial to do, there is at least an interface to do it.
We hope to change various aspects of the standard style further, but that has not yet been done.
.NH 1
Commands and modules
.LP
There are new commands and library modules, others have become obsolete and been removed,
and a few existing ones have been given new names (typically when ones with similar function have been
collected together).
The biggest change has been to
.I wm (1),
which retains the same name but slightly different invocation and completely different
implementation,
as discussed above.
Here I shall simply note the bigger changes, rather than discuss new functionality.
.NH 2
Renamed commands
.LP
As part of a mild reorganisation of the
.CW /appl
and
.CW /dis
trees, we have moved commands out of
.CW /dis/lib
so that it now contains only library modules except for a few commands left
there temporarily for compatibility.
Commands themselves have sometimes been shuffled to subdirectories,
often copying seemingly better structure from Plan 9,
so that authentication commands are
.CW auth/ ...,
naming service commands are
.CW ndb/ ...,
and
IP-specific commands are
.CW ip/ "... ."
.LP
One noticeable change is that
.CW lib/cs
is now
.CW ndb/cs .
More dramatically, the command
.CW lib/srv
(ie,
.I srv (8))
has been replaced by
.I sh (1)
scripts, all described by
.I svc (8),
that contain appropriate calls to
.I listen (1)
after setting up any locally-desired environment.
.LP
Other commands have also moved:
.IP •
.CW lib/plumber
is now simply
.CW plumber
.IP •
.CW lib/bootp
and
.CW lib/tfptd
have become
.CW ip/bootpd
and
.CW ip/tftpd ,
documented in
.I bootpd (8)
.IP •
.CW lib/virgild
has become
.CW ip/virgild
(see
.I virgild (8))
.IP •
.CW lib/chatsrv ,
.CW lib/rdbgsrv
and
.CW cpuslave
have moved to
.CW auxi
(ie,
.CW /dis/auxi
and
.CW /appl/cmd/auxi)
.IP •
.CW csquery
has become
.CW ndb/csquery
.NH 2
New or newly-documented commands
.IP •
an authentication server (signer) can use
.I keyfs (4)
to store its keys securely in the encrypted file
.CW /keydb/keys
(instead of the unencrypted
.CW /keydb/password ),
and run
.I keysrv (4)
to offer secure change of password remotely.
They are typically started, with other signing services, by
.CW svc/auth
described in
.I svc (8).
.IP •
.CW /dis/auth
and
.CW /appl/cmd/auth
contain commands related to authentication;
they rely on
.I keyfs (4)
in most cases.
The older ones that use
.CW /keydb/passwd
are still in
.CW /dis/lib
and
.CW /appl/lib
during the transition
.IP •
.I dns (8)
has replaced the
.CW lib/ipsrv
implementation of
.I srv (2);
when used, it must be started before
.CW ndb/cs .
.I Srv (2)
has reverted to being a hosted-only interface to the hosting system's native
DNS resolver.
It is automatically used by
.I cs (8)
if it cannot find
.I dns (8),
and
.I dns (8)
will also use it if available before consulting the DNS network.
.IP •
.I chgrp (1),
.I cpuview (1),
.I grid (1),
.I 9660srv (4),
.I cpuslave (4),
.I dossrv (4),
.I keyfs (4),
.I keysrv (4),
.I nsslave (4),
.I palmsrv (4),
.I registry (4),
.I rioimport ,
.I styxchat (1),
.I styxlisten ,
.I wmexport ,
.I wmimport ,
and
.I uniq (1)
are new
.IP •
the multiplayer games software previously in
.CW /appl/games
has been replaced by a related but significantly different system in
.CW /appl/spree .
(Also see
.I spree (2)
for supporting modules.)
.IP •
.I Registry (4)
provides dynamic registration and location of services using sets of attributes/value pairs,
through a name space.
.I Registries (2)
provides a convenient Limbo interface for registration and query.
.NH 2
Commands removed
.IP •
.CW lib/csget
(see
.I cs (8)
for its replacement
.CW csquery )
.IP •
the undocumented and obsolete commands
.CW lib/isrv
and
.CW lib/istyxd
have been removed, since either the
.CW none
authentication protocol, or the
.CW -A
option to
.CW mount
can be used if no authentication is needed
.IP •
.CW lib/srv
has been replaced by
.I svc (8)
as mentioned above.
.IP •
.CW getenv
and
.CW setenv
have been removed since the Shell provides alternatives
.IP •
.CW wm/license
is no longer needed
.NH 2
New modules
.LP
There are library modules to support: registries and configuration files of attribute/value pairs;
Internet address parsing and manipulation; management of windows and subwindows (used by
.I wm (1)
itself); timers; Styx; Styx servers; exception handling; memory
and performance profiling; Freetype interface; parsing Palm databases; and navigating XML files (without reading them all into memory) and interpreting style sheets.
.NH 1
Styx
.LP
Styx was derived from the 9P protocol used by Plan 9 in 1995, with changes that reflected the requirements
of the Inferno project of the time, mainly by removing features that were thought too closely tied to the Plan 9
environment.
Some 9P messages were removed, particularly those
that incorporated details of the Plan 9 authentication methods;
Styx moved authentication outside the file service protocol.
Other changes eliminated file locking and append-only files.
Some restrictions that 9P imposed were retained, however, such as limiting file names to 27 bytes.
This last restriction is fine for synthetic network services, but
has been troublesome when trying to access Unix and Windows systems, amongst others.
.LP
A recent revision of 9P adds support for much longer file names
and takes the opportunity to improve other aspects of the protocol.
It also removes details of authentication algorithms from the protocol.
The Styx implementation now uses the new version of 9P as the default file service protocol.
(It is possible that for interoperation with older Inferno systems the system will be able to
interact with both old and new versions of Styx.)
.NH 2
Protocol changes
.LP
The messages
.CW Tauth
and
.CW Tversion
are new to Styx.
.CW Tversion
includes negotiation (at connection start) of the message size and protocol version;
it also introduces a new session.
.CW Tauth
obtains access to a special authentication file if the server requires
authentication within a Styx session.
.CW Tclone
has been replaced by a more elaborate form of
.CW Twalk
that allows zero to MAXWELEM (16) elements to be walked, perhaps to a new fid, in a single message,
returning a sequence of qid values in
.CW Rwalk .
(A clone is simply a walk of a fid to a new fid with zero elements.)
A walk of several elements can return partial results if the walk of the first element succeeds but
subsequent ones fail.
A partial walk leaves the state of the fids unchanged.
.CW Ropen
and
.CW Rcreate
return a suggested size for atomic I/O on the fid (0 means `not given').
All strings are variable length, and consequently
.CW Twstat
and
.CW Rstat
data is variable length and formatted differently.
Data returned from
.CW Tread
of a directory is similarly changed, because
directory entries are not fixed length.
.CW Tnop
has gone.
.LP
Tags remain 16-bit integers, but fids and counts
become 32-bit integers (mainly of interest to large systems),
and qids have a different structure.
Previously a qid was a pair of 32-bit integers, path and vers, where
path had the top bit set for a directory.
Now a qid is a triple: a 64-bit path, 32-bit vers, and 8-bit type.
The type is defined to be the top 8 bits of the file's mode.
The path does not have the top bit set for a directory, and indeed the
path value is not interpreted by the protocol.
There are now bits in the file mode for append-only and exclusive-use
files (new for Inferno), and for authentication files (new for both Plan 9 and Inferno).
The stat information includes the user name that last caused the file's mtime to be changed.
All strings in the protocol are variable length: file names, attach names, user names, and error text.
.LP
The message format on the wire is significantly different.
The message size is negotiated for a connection by
.CW Tversion ,
and messages can be large, allowing much more data to be sent in single
.CW Twrite
and
.CW Rread
messages.
The header includes a 32-bit message size, making it easy to find message boundaries without
parsing the contents.
Strings are
represented as a 16-bit size followed by the string's UTF-8 encoding (without zero byte).
R-messages do not carry a copy of the fid from the T-message.
Padding bytes have gone.
The order of some fields has changed of course to match message parameter changes.
.LP
Authentication of the connection itself, and optionally
establishing the keys for digesting and encryption,
is done before the protocol starts, in both Inferno and Plan 9.
Details will follow on the protocol for that, and Limbo interfaces.
For now, it can be assumed that the old authentication messages can still be used,
even after a more flexible protocol has been implemented.
.CW Tauth
can be used to authenticate particular accesses within such a session, but
implies trust by the server that the client system will not cheat its users.
(That trust is typically established by the connection level authentication which is needed
anyway for link encryption, and thus for single-user clients further authentication
seems extraneous in most cases.)
Most Inferno services that run as file servers within a system (eg,
.CW 9660srv )
will, like Plan 9's, reply to
.CW Tauth
with an
.CW Rerror
stating ``authentication not required''.
Access to them when exported is typically controlled as now by verifying the incoming connection.
.NH 2
Limbo interface changes
.LP
Because Limbo's interface to file service via
.CW Sys
and other modules uses Limbo
.CW string
for names, and that is inherently
variable length, there are no interface changes required for that aspect of the protocol change,
and consequently no source changes
(in contrast to the introduction of 9P2000 in C implementations).
Similarly the Inferno directory reading interfaces remain unchanged.
.LP
The `directory mode' bit previously called
.CW CHDIR
is now called
.CW DMDIR .
It is used
.I only
in
.CW Dir.mode .
.CW CHDIR
is no longer defined, partly because it was used both
in
.CW Dir.mode
and
.CW Qid.path ,
and the latter instances must change (discussed below).
There are bits (new to Inferno) for
.CW DMAPPEND
(append-only file),
.CW DMEXCL
(exclusive-use file),
and
.CW DMAUTH
(authentication file).
The protocol can return the user name of the user that caused
.CW mtime
to be changed on a file; that is now available as
.CW Dir.muid .
.LP
The structure of
.CW Qid
has changed.
Previously a Qid had a 32-bit
.CW path
and a 32-bit version number,
.CW vers .
The top bit
.CW CHDIR ) (
of
.CW path
was set iff the Qid was that of a directory.
The
.CW path
is now 64 bits (which is
.CW big
in Limbo and
.CW vlong
in the kernel), and there is no longer the convention that the top bit of
.CW path
must be 1 for a directory.
Instead, there is a new, separate
.CW type
field (called
.CW qtype
in Limbo)
that has the value of the top 8 bits of the file's mode.
Each bit \f5DM\fIx\f1 in
.CW Dir.mode ,
has got a corresponding bit \f5QT\fIx\f1
in
.CW Qid.qtype :
.CW QTDIR ,
.CW QTAPPEND ,
.CW QTEXCL
and
.CW QTAUTH .
The bit
.CW QTDIR
.I must
be set in the
.CW Qid.qtype
for a directory, and only then.
There is an extra constant
.CW QTFILE
that is defined to be zero, and is used for clarity when neither
.CW QTDIR
nor
.CW QTAUTH
is set.
.LP
In Styx file servers, changes are required to reflect the slightly different set of message types
and a few new parameters, but the main changes are:
handling zero or more name elements at once in
.CW Twalk
and
.CW Rwalk ;
changing
.CW CHDIR
to
.CW DMDIR
in
.CW Dir.mode
(easy);
the use of the new
.CW Qid.qtype
field
and
.CW QTDIR
instead of
.CW CHDIR
in
.CW Qid.path
(a little more effort);
and (typically) the insertion of casts to force
.CW Qid.path
to
.CW int
and thus ensure the use of 32-bit operations except where 64-bit paths really are needed
(hardly ever in synthetic file servers).
The new modules for use by file servers are discussed in the next section.
.LP
The revised definition of
.CW Twstat
in
.I stat (5),
and thus
.CW sys->wstat ,
provides for ``don't care'' values in
.CW Dir
that are tedious to provide directly; a new adt value
.CW Sys->nulldir
provides the right initial value for a
.CW Dir
which is then changed as needed for
.CW wstat .
.SH
.I "Examples"
.LP
Create a directory:
.P1
	\fIold:\f5
fd := sys->create(name, Sys->OREAD, Sys->CHDIR | 8r777);

	\fInew:\f5
fd := sys->create(name, Sys->OREAD, Sys->DMDIR | 8r777); # not CHDIR
.P2
.LP
Make Qids
for a file and a directory:
.P1
	\fIold:\f5
Qdir, Qdata: con iota;
qd := Sys->Qid(Sys->CHDIR | Qdir, 0);
qf := Sys->Qid(Qdata, 0);

	\fInew:\f5
Qdir, Qdata: con iota;
qd := Sys->Qid(big Qdir, 0, Sys->QTDIR);
qf := Sys->Qid(big Qdata, 0, Sys->QTFILE);
.P2
.LP
Test if a file is a directory:
.P1
	\fIold:\f5
isdir(d: Sys->Dir): int
{
	return (d.mode & Sys->CHDIR) != 0;
\fIOR:\f5
	return (d.qid.path & Sys->CHDIR) != 0;
}

	\fInew:\f5
isdir(d: Sys->Dir): int
{
	return (d.mode & Sys->DMDIR) != 0;
\fIOR:\f5
	return (d.qid.qtype & Sys->QTDIR) != 0;
}
.P2
.LP
If one wishes to have values
.CW big
only when required, one can write:
.P1
case int dir.qid.path {
Qdir =>
	...
Qdata =>
	...
Qctl =>
	...
}
.P2
Of course with the Dis change mentioned above,
.CW case
can now be applied to
.CW big
values, so it is no longer necessary to add the cast (as it once was).
Even so, 32-bit operations are faster when they suffice.
.NH 2
Styx protocol in Limbo: Styx and Styxservers
.LP
A new module
.CW Styx ,
defined by
.CW styx.m ,
provides access to the Styx protocol messages, as variants of pick adts
.CW Tmsg
and
.CW Rmsg .
(There was an old, undocumented
.CW Styx
module but this new interface is completely different.)
It is used by several file servers, such as
.CW dossrv ,
.CW cdfs ,
and the new
.CW logfs .
See the attached manual page.
There are several implementations with the same signature, covering different
combinations of old and new Inferno and old and new protocols, through
the same interface.
There are slight differences in the application code for old and new
systems because of the changed
type and structure of
.CW Qid .
The versions that talk the old protocol need to store some internal state,
and are intended only to meet compatibility requirements during the transition.
.LP
Many file service applications, however, serve a simple name space,
requiring more than can be done with
.CW file2chan ,
but wishing some help in handling the protocol details.
Two new modules
.CW Styxservers
and
.CW Nametree
are provided to make such applications easier to write.
They are closely related and thus both modules are defined by
.CW styxservers.m .
.LP
.CW Styxservers
provides help in handling fids and interpreting the Styx requests for navigating a
name space, and provides a reasonable set of default actions,
allowing the application to focus on implementing
read and write access to the files in the name space.
It uses
.CW Styx
to talk to the Styx client on a connection.
It interacts with the application through a channel interface and
the
.CW Navigator
adt to navigate an abstract
representation of the application's name space.
The module can be used on its own, with the application doing the work
of replying to those queries itself, or it can get extra help in the common cases from
.CW Nametree .
.CW Nametree
provides a
.CW Tree
adt and operations for the application to build an abstract representation of a name space
and maintain it dynamically quite simply, and it exports the channel interface used by
.CW Styxservers
for navigation, thus connecting the two, but leaving the application in complete
control of the name space contents viewed by Styx.
See the manual pages
.I styxservers (2)
and
.I styxservers-nametree (2),
attached.
The latter includes a short working example of combining the two modules.
.LP
The previous release of the system had a module
.CW Styxlib
that combined the functions of
.CW Styx
and
.CW Styxservers .
It remains for a time for transition, but newer applications should use either
.CW Styx
or
.CW Styxservers .
.LP
A new command
.I styxchat (8)
exchanges Styx messages with a server, reading a textual representation of T-messages
on standard input.
It can be helpful when testing a Styx server implementation.
(It was originally developed to test the
.CW Styx
module implementations in several configurations.)
See the attached manual page for details.
It also supports an option that allows it to act as a server,
printing T-messages as they are received from clients, and
reading R-messages in a textual form from standard input for replies.
.NH 2
Device driver changes
.LP
Most of the differences for most drivers are relatively minor
(in
.CW diff
terms).
.LP
Throughout the hosted and emulated kernels:
.IP \(bu
.CW Qid
now is the structure:
.RS
.P1
struct Qid {
    vlong   path;
    ulong   vers;
    uchar   type;
};
.P2
The
.CW type
field has values
.CW QTDIR ,
.CW QTFILE ,
.CW QTAPPEND ,
etc.
The test previously written
.P1
if(qid.path & CHDIR)
.P2
is now written
.P1
if(qid.type & QTDIR)
.P2
Because of that change, the various
.CW switch
statements in the drivers that previously read
.P1
switch(c->qid.path){
.P2
or
.P1
switch(c->qid.path & ~Sys->CHDIR){
.P2
now read
.P1
switch((ulong)c->qid.path){
.P2
to keep operations to 32 bits (except where otherwise required).
.RE
.IP \(bu
The first entry of a driver's
.CW Dirtab
.I must
be an entry for
\f5"."\fP,
if the driver uses
.CW devgen
to help implement
.I walk ,
.I stat ,
.I devdirread
or
.I open
operations.
.IP \(bu
Offsets passed to the driver's
.I read
and
.I write
entry points are
64-bit
.CW vlong ,
not 32-bit
.CW ulong .
.IP \(bu
The
.I stat
entry point has an extra buffer size parameter:
.RS
.P1
int \fIxyz\f5stat(Chan *c, uchar *dp, int n)
.P2
It also returns an integer: the size of the result.
.CW Devstat
accepts the extra parameter and returns an appropriate result:
.P1
static int
\fIxyz\f5stat(Chan *c, uchar *dp, int n)
{
	return devstat(c, dp, n, rtcdir, nelem(\fIxyz\f5dir), devgen);
}
.P2
.RE
.IP \(bu
The biggest change is to
.I walk .
It has the signature:
.RS
.P1
Walkqid *\fIxyz\f5walk(Chan *c, Chan *nc, char **names, int nname);
.P2
and it allows zero or more elements to be walked in a single call,
returning its result in a newly-allocated
.CW Walkqid
structure:
.P1
struct Walkqid {
	Chan*	clone;
	int	nqid;
	Qid	qid[1];
};
.P2
Note that the array
.CW Walkqid.qid
must actually hold up to
.I nname
Qids, and thus is allocated as follows:
.P1
wq = smalloc(sizeof(Walkqid)+(nname-1)*sizeof(Qid));
.P2
The driver must take care that the space is reclaimed if
.CW error
is called before its
.I walk
function returns, by using
.CW waserror
as required.
Fortunately,
.CW devwalk
looks after the details of
.I walk
and
.CW walkqid
for most drivers:
.P1
static Walkqid*	 
\fIxyz\f5walk(Chan* c, Chan *nc, char** name, int nname)
{
	return devwalk(c, nc, name, nname, \fIxyz\f5dir,
		nelem(\fIxyz\f5dir), devgen);
}
.P2
.RE
.IP \(bu
The
.I clone
entry point has gone, since cloning is seen by a driver as a particular form of call to its
.I walk
entry,
where the parameter values satisfy:
.RS
.P1
c != nc && nwname == 0
.P2
One difference is that a node can be cloned and walked in a single operation,
in other words
.CW nwname
can be non-zero,
and the incoming
.CW nc
is often nil and a new
.CW Chan
must be allocated.
Note that if the driver found it adequate to call
.CW devclone
previously, then
the new
.CW devwalk
will
generally look after it as well.
.CW Devclone
remains for use as a utility function for the few drivers that need to
clone a channel themselves,
in their
.I walk
operations or elsewhere.
.RE
.IP \(bu
The
.I detach
entry has been renamed
.I shutdown
(it was never the opposite of
.I attach ).
The stub
.CW devshutdown
can be used by devices that do not need it.
.LP
For drivers that serve a simple name space using the functions of
.CW dev.c
(described in
.I devattach (10.2)),
only a handful of simple changes are required.
Most are pointed out by the compilers as type clashes.
The main exception is the need for a
.CW Dirtab
to have its first entry be an entry for \f5"."\fP if the
.CW Dirtab
will be passed to
.CW devgen
via
.CW devwalk ,
.CW devstat
and
.CW devdirread .
.NH 1
Sys module changes
.LP
.NH 2
Sys: name change(s)
.LP
The name
.CW ERRLEN
has become
.CW ERRMAX
(since it is the limit to any error string, not its necessary length).
.CW NAMELEN
has been removed,
to allow each instance to be found (by compilation) and either removed
(where it was simply limiting the length of a file name), or replaced by
.CW NAMEMAX
where it was used as a buffer size to read in names such as
.CW /dev/sysname
or
.CW /dev/user .
.NH 2
Sys: file sizes
.LP
The Styx protocol has always supported 64-bit file sizes and file offsets.
The Inferno interface has not.
.CW Sys
has changed so that length and offset values become
.CW big ,
specifically:
file size
.CW Dir.length ,
the offset parameter to
.CW seek ,
and
.CW seek 's
result.
.LP
These and the Qid changes account for quite a few changes in
our own source tree.
Typically, applications did things like this:
.P1
	\fIold:\f5
buf := array[d.length] of byte;

sys->seek(fd, 0, Sys->SEEKSTART);
off := sys->seek(fd, 0, Sys->SEEKRELA);	rec := off + HDRLEN;
for(offset := 0; offset < d.length; offset += RECSIZE){
	sys->seek(fd, offset, Sys->SEEKSTART);
	...
}
.P2
The compiler now objects in each case because
.CW big
values are now appearing where
.CW int
is required, or conversely.
In some cases it is obvious that adding a cast is correct;
in others it is worth considering whether the calculation should indeed
be
.CW big
because file sizes for instance can in practice exceed the range of a
signed integer without too much trouble today, especially when the `file'
is a storage device.
The case that some people like and some dislike is:
.P1
if(sys->seek(fd, big offset, Sys->SEEKSTART) < big 0) ...
.P2
where the
.CW "big 0"
is needed because
.CW sys->seek
is
.CW big ,
and there are no `usual arithmetic conversions' as in C.
(Given the tangle that several languages have made of such conversions, perhaps
being strict is correct.)
.NH 2
Sys: export
.LP
.CW Sys->export
now has the signature:
.P1
export:	fn(c: ref Sys->FD, dir: string, flag: int): int;
.P2
allowing a directory
.I dir
other than \f5"/"\f1
to be exported.
It replaces the
.CW exportdir
function of (later) Third Edition.
.NH 2
Sys: Styx support
.LP
The revision of Styx has caused three calls to be added:
.P1
fauth:    fn(fd: ref Sys->FD, aname: string): ref Sys->FD;
fversion: fn(fd: ref Sys->FD, msize: int, version: string): (int, string);
iounit:   fn(fd: ref Sys->FD): int;
.P2
.CW Fversion
initialises a Styx session on connection
.I fd ,
sending the message size
.I msize
and protocol version string
.I version ;
it returns a tuple giving the message size and version returned by the Styx server.
It is rarely called directly; the
.CW mount
operation does it automatically on an uninitialised connection.
.LP
.CW Fauth
sends a Styx
.CW Tauth
message on connection
.I fd ,
and if successful, returns a file descriptor that
refers to an authentication file provided by the file server,
which may be read and written by
.CW Sys->read
and
.CW Sys->write
to implement the authentication protocol(s) supported by the server.
.CW Fauth
is needed only when the server requires authentication.
.LP
.CW Iounit
returns the `atomic IO unit' suggested for the file
.I fd
by its file server when it was opened.
.NH 2
Sys: mount
.LP
The
.CW mount
system call has acquired a second file descriptor parameter:
.P1
mount: fn(fd: ref Sys->FD, afd: ref Sys->FD, on: string,
          flags: int, spec: string): int;
.P2
.I Afd
is nil if the file server is known not to require authentication within a Styx session.
(The connection might itself have been authenticated previously, for instance,
and most file servers such as
.CW dossrv ,
.CW ftpfs
and
.CW dbfs
are invoked to provide services to an already-authenticated user, and therefore
do not require authentication within a session.)
If the server does require authentication,
.I afd
refers to a file descriptor returned by a previous
.CW fauth
on connection
.I fd ,
on which an authentication protocol has subsequently been executed as required by the file server connected to
.I fd .
.NH 2
Sys: other new system calls
.LP
There are two more new system calls:
.P1
fd2path: fn(fd: ref Sys->FD): string;
werrstr: fn(s: string): int;
.P2
.CW Fd2path
returns the path name under which the file descriptor
.I fd
was originally opened (if known).
One result is that
.I workdir (2)
produces reasonable results for the name of the current directory
in the presence of mounts and binds.
.LP
.CW Werrstr
sets the per-process system error string to
.I s ,
to allow a Limbo function to save and restore an error string over
other system calls, to present a similar interface
as the system calls on errors, or to annotate the error from a system call
for its own caller.
.NH 2
Sys: directory reading
.LP
The
.I sys-dirread (2)
system call's signature has changed:
.P1
dirread: fn(fd: ref Sys->FD): (int, array of Sys->Dir);
.P2
Previously it accepted an array of
.CW Dir
to fill and returned a count;
now it returns a tuple containing the count and the array of values read.
The change was needed because the representation of directory entries
is now variable length, and it is difficult to limit the number returned
(it is possible, but all the methods have disadvantages).
.CW Dirread
still reads a directory incrementally, requesting a block of directory entries
of reasonable size from the file server, and unpacking them into the returned array.
Use
.I readdir (2)
to read whole directories at once.
.NH 1
Bufio
.LP
There are several changes to
.CW Bufio :
.P1
Iobuf: adt {
	...
	seek:	fn(b: self ref Iobuf, n: big, where: int): big;
	offset:	fn(b: self ref Iobuf): big;
};
# flush: fn();	# deleted
.P2
The module-level function
.CW Bufio->flush
has been removed
(\fInot\fP
.CW Iobuf.flush ),
to allow concurrent use of a single
.CW Bufio
instance; applications must
.CW close
or
.CW flush
each output file explicitly.
.LP
As a result of the change to 64-bit offsets for
.CW Sys->seek ,
.CW Iobuf.seek
also accepts and returns
.CW big
offsets.
.CW Iobuf.offset
is new, and returns the current file offset in bytes, taking account of any buffering.
.LP
.CW Iobuf.flush
has been extended to flush any data buffered on input files.
.NH 1
Draw
.LP
The graphics model represented by the
.I draw (3)
device and the
.CW Draw
module is significantly different, including support for a range of pixel formats,
and compositing in the drawing operations.
Most source code that uses Images
directly will require some changes, but the scope of them is limited: needing only extra
or different parameter values to individual operations, not radical restructuring.
The following changes affect most non-Tk graphics application code:
.IP \(bu
Pixels in an
.CW Image
can now be more than 8 bits and have a more flexible structure
(eg, several colour channels, and an optional alpha channel, of up to 8 bits each).
To support that, the old
.CW ldepth
field has gone, replaced by a channel descriptor
.CW chans
of type
.CW Chans ,
which describes the pixel structure, and an integer
.CW depth
field, which gives the total pixel size (depth) in bits.
.IP \(bu
The colour parameters are now 32-bit RGBA values
(red, green, blue and alpha components, 8-bit each, and big-endian
only when an
.CW int ).
.IP \(bu
The graphics subsystem supports Porter-Duff compositing,
combining a destination image with a source image (within an optional matte)
according to a compositing operator.
The interpretation of the old `mask' Image parameter to
.CW draw
and
.CW gendraw
has changed.
Previously it provided a simple binary mask;
it now provides a `matte', and its
alpha channel shapes the source image and adds partial transparencies.
If the matte parameter is nil, the source image is used unmodified.
If it lacks an alpha channel, one is computed from the matte image colour channels.
The drawing operations
.CW draw ,
.CW gendraw ,
.CW line ,
.CW text ,
and so on,
have all got variants
.CW drawop ,
.CW gendrawop ,
.CW lineop ,
.CW textop ,
and so on,
each taking an extra final parameter that specifies a Porter-Duff
compositing operator from a set predefined by
.CW Draw :
.CW SoverD ,
.CW SinD ,
.CW DatopS ,
and so on.
In each case,
.CW S
refers to the source image (within a matte, if provided), and
.CW D
refers to the destination image.
Most of them are useful only when either or both source or destination images have got
alpha channels (or a matte is used to shape the source).
The old function names without the
.CW op
suffix use the most common compositing operation
.CW Draw->SoverD ,
drawing the source image over the destination,
taking account of the shaping of the source and destination images by their alpha channels,
with the source further shaped by the optional matte.
Thus
.CW Image.draw
continues to do the `obvious' thing.
.IP \(bu
There are new colour map conversion functions.
.LP
The
.CW Chans
adt is the following:
.P1
Chans: adt
{
	# interpret standard channel string
	mk:    fn(s: string): Chans;
	# standard printable form
	text:  fn(c: self Chans): string;
	# equality
	eq:    fn(c: self Chans, d: Chans): int;
	# bits per pixel
	depth: fn(c: self Chans): int;
};
.P2
Values are created by
.CW Chans.mk ,
which accepts a string that is a sequence of channel descriptors,
each being a letter representing a channel type followed by an integer giving the channel's size (depth, width) in bits.
The letters include:
.CW r ,
.CW g
and
.CW b
for red, green and blue;
.CW a
for alpha;
.CW k
(!) for greyscale; and
.CW x
for padding (``unspecified'', ``don't care'').
Thus
.CW Chans.mk("r8g8b8a8")
produces a descriptor for a 32-bit pixel with 8-bit colour and alpha components.
The same descriptor is used in the revised
.I image (6)
format, although the older image file format with ldepth only is still recognised.
Given a Chans value
.I c ,
\fIc\fP\f5.text()\fP returns such a descriptor for it as a string.
.LP
When
.CW newimage
previously was called with a specific value for
.CW ldepth ,
an appropriate
.CW Chans
value must replace it.
A few common variants are defined as constants of type
.CW Chans
in
.CW Draw .
(We extended the Limbo compiler last year to support the use of
.CW con
with adt and tuple constants with this use in mind.)
For example, the value
.CW Draw->CMAP8
is the descriptor for the 8-bit deep
.I rgbv
colour-mapped Image format previously used by Inferno.
The list of predefined channels includes:
.TS
center;
cfI cfI cfI cfI
n lf(CW) n lw(3i) .
Old ldepth	Name	Bit depth	Description
0	GREY1	1	single 1-bit deep greyscale channel
1	GREY2	2	single 2-bit deep greyscale
2	GREY4	4	single 4-bit deep greyscale
\-	GREY8	8	single 8-bit deep greyscale
3	CMAP8	8	single 8-bit deep \fIrgbv\f1 colour-mapped channel
\-	RGB15	15	three channels RGB: r5g5b5
\-	RGB16	16	three channels RGB: r5g6b5
\-	RGB24	24	three channels RGB: r8g8b8
\-	RGBA32	32	four channels: RGB and alpha: r8g8b8a8
.TE
.LP
The use of
.CW Chans
instead of
.CW ldepth
means that calls to
.CW Display.newimage
must be changed.
For instance:
.P1
\fI(old)\f5
buffer := display.newimage(r.inset(3), t.image.ldepth, 0, Draw->White);
.P2
becomes
.P1
\fI(new)\f5
buffer := display.newimage(r.inset(3), t.image.chans, 0, Draw->White);
.P2
There is an obvious difference: the
use of
.CW t.image.chans
instead of
.CW t.image.ldepth
to create a buffer Image with the same pixel structure as
.CW t .
There is, however, another difference.
The final colour parameter to
.CW newimage
is also different in structure: in the new graphics model, it is a 32-bit integer value giving RGBA
components,
not a colour map index, and the name
.CW Draw->White
has the value
.CW 16rFFFFFFFF
not
.CW 0 .
Because a symbolic name was used, however, the source need not change.
As another example,
.CW Draw->Palegreyblue
is
.CW "int 16r4993DDFF" .
Note the final
.CW FF
for the alpha component (creating a fully opaque colour).
When the top bit is set, the
.CW int
cast shown here is needed to force the otherwise
.CW big
value to 32 bits.
.LP
The values of colour components are now uniformly expressed as
intensity, so that a pixel with all zero colour components is black and
one with all colour components at maximum (all ones, full intensity)
is white.
The
.I rgbv
map has therefore been reversed.
Given a map index,
.CW Display.cmap2rgba
returns the 32-bit RGBA format used as a parameter in other calls.
All colour components are
.I linear
values, as required for compositing to work properly;
gamma correction is done as required by the display subsystem.
.LP
The colour components of a pixel with an alpha component are always
.I pre-multiplied
by the alpha value, following Porter and Duff, as further justified by Alvy Ray Smith and Jim Blinn.
``Thus a 50% red is
.CW 16r7F00007F
not
.CW 16rFF00007F .''
The function
.CW Draw->setalpha
does the computation.
.LP
Because of the changes to colours and the replacement of simple masks by mattes, the Images
.CW Display.ones
and
.CW Display.zeros
are no longer defined.
Instead, when they were intended to represent colours, the new Images
.CW Display.black
and
.CW Display.white
provide the obvious colours.
When
.CW ones
and
.CW zeros
were used as masks, the new predefined Images
.CW Display.opaque
and
.CW Display.transparent
are used instead as constant mattes, with alpha channels (fully opaque and fully transparent, respectively).
As noted above, where
.CW Display.ones
was used as a mask parameter in drawing operations, one can
simply specify a nil Image as a matte (`no matte') instead.
(That has been allowed for quite some time and is in use but might not be widely known.)
.LP
For example, Charon allocated a mask using:
.P1
dpicmask = display.newimage(pic.r, 0, 0, Draw->White);
.P2
which becomes
.P1
dpicmask = display.newimage(pic.r, Draw->GREY1, 0, Draw->Opaque);
.P2
where
.CW GREY1
is a constant value of the
.CW Chans
adt type, predefined by Draw, for Images that have a single 1-bit deep grey channel (ie, a bitmap).
(Note that to form a fully-opaque matte,
.CW Draw->Opaque
was used for clarity, not
.CW Draw->White ;
.CW Draw->Transparent
could also be used, as the basis for building a matte with transparency.)
.LP
A small if obscure change is that
.CW Display.newwindow
has a new parameter:
.P1
newwindow:	fn(screen: self ref Screen, r: Rect,
	backing: int, color: int): ref Image;
.P2
The
.I backing
parameter should usually be
.CW Draw->Refbackup ,
except for windows allocated on an image that already has got backing store
assigned, for instance because it is an image on a screen on an existing window image, in which case it should be
.CW Draw->Refnone ,
because the parent window already provides the backing.
.LP
As a small but helpful change, the adt
.CW Draw->Pointer
has a new element
.CW msec
that reports a
relative time stamp in milliseconds.
.LP
The
.CW Draw->Context
content is significantly different, for the benefit of the new
window system implementation.
.NH 1
Tk module
.LP
There is a new function in
.CW Tk :
.P1
quote:   fn(s: string): string;
.P2
.CW Quote
returns string
.I s
quoted according to Tk's `\f5{}\f1' quoting conventions.
It replaces
.CW Wmlib->tkquote .
.LP
There is a new widget type:
.I panel (9).
A panel instance can be packed and otherwise manipulated in the same way as any other Tk widget.
An image is associated with it by calling
.CW Tk->putimage
defined in
.I tk (2).
The associated images can be drawn on directly by the application, using all the operations provided by
.CW Draw .
The coordinates of the changed rectangle must be given to Tk
using the
.CW panel
widget command
.CW dirty ;
that part of the image will be redrawn if necessary at the next Tk
.CW update .
A panel has no default bindings.
See
.I panel (9)
for details.
.LP
For example,
.CW wm/coffee
now uses the following:
.P1
r := Rect((0, 0), (400, 300));
buffer := display.newimage(r, t.image.chans, 0, Draw->Black);
tk->cmd(t, "panel .f.p -bd 3 -relief flat");
tk->cmd(t, "pack .f.p -fill both -expand 1");
tk->cmd(t, "update");
org := buffer.r.min;
tk->putimage(t, ".f.p", buffer, nil);
.P2
When it has updated the
.CW buffer ,
it tells Tk:
.P1
tk->cmd(t, ".f.p dirty; update");
.P2
In this case the whole image is marked dirty, but
.CW dirty
can be given an optional rectangle parameter to restrict redrawing.
.LP
.CW Tk->putimage
and
.CW Tk->getimage
replace
.CW imageput
and
.CW imageget .
.NH 1
Selectfile, Tabs and Dialog
.LP
The functions
.CW filename ,
.CW mktabs
(and
.CW tabsctl ),
.CW dialog
and
.CW getstring
have been moved to separate new modules, to allow those aspects of the
user interface to be changed by replacing the implementations,
and to allow standard modules to be provided for picking colours (for instance).
.CW Selectfile
acquires
.CW filename ,
.CW Tabs
acquires the `tabs' Tk pseudo-widget, and
.CW Dialog
acquires
.CW dialog ,
which is renamed
.CW prompt ,
and
.CW getstring .
In cases where the functions took a
.CW Tk->Toplevel
as a parameter to specify a
.CW parent
window,
they now take a
.CW Draw->Context
and (parent)
.CW Image
parameter;
given a Toplevel
.CW t ,
use
.CW t.image .
See
.I dialog (2),
.I selectfile (2)
and
.I tabs (2).
.TL
Appendix A: Tk client conversion
.LP
.I Wm (1)
applications now have to feed their own pointer and keyboard
input to Tk. The window manager is now kept informed about the placement
of windows.
.LP
A Tk toplevel now holds a window manager context:
.P1
Wmcontext: adt
{
	kbd: 		chan of int;		# incoming characters from keyboard
	ptr: 		chan of ref Pointer;	# incoming stream of mouse positions
	ctl:		chan of string;		# commands from wm to application
	wctl:		chan of string;		# commands from application to wm
	images:	chan of ref Image;	# exchange of images
	connfd:	ref Sys->FD;		# connection control
	ctxt:		ref Context;
};
.P2
It contains some channels on which the window manager
sends information to the application, and a file
descriptor that can be used to write requests to the window
manager.
The channels used directly by the application are:
.RS
.IP \f(CWkbd\fP
characters typed by the user (pass them to
.CW Tk->pointer )
.IP \f(CWptr\fP
pointer events (pass them to
.CW Tk->keyboard )
.IP \f(CWctl\fP
application control requests.
Passing these to
.CW Tkclient->wmctl
will do the default action.
Requests starting with an exclamation mark
.CW ! ) (
can cause the application's image to change.
.RE
.LP
The toplevel also holds a channel
.CW wreq
on which it sends application
control requests; these have the same form as those
sent on
.CW Wmcontext.ctl ,
and can be forwarded to
.CW Tkclient->wmctl
in the same way.
.LP
Control requests currently understood by
.I wm (1)
are:
.RS
.IP "\f(CW!reshape \fItag\fP \fIreqid\fP \fIminx\fP \fIminy\fP \fImaxx\fP \fImaxy\fP [\fIhow\fP]\fR
.br
Reshape the window referenced by
.I tag ,
creating a new image if
.I tag
did not previously exist.
.I Reqid
is ignored.
.I How
can be one of:
.RS
.IP \f(CWplace\fP 15
.I Wm
attempts to find a suitable patch of screen real estate on which to place
the window; the size of the given rectangle
is taken to be the minimum size for that window.
.IP \f(CWexact\fP
Reshape to the exact rectangle requested.
This is the default if
.I how
is not given.
.IP \f(CWonscreen\fP
The given rectangle is adjusted so that it is no bigger than the available
screen space, and is entirely on screen.
.RE
.IP "\f(CWdelete \fItag\fP\fR
.br
Delete the image associated with
.I tag .
.IP "\f(CWraise\fP
.br
Raise the window
.IP "\f(CWlower\fP
.br
Lower the window
.IP "\f(CW!move \fItag\fP \fIreqid\fP \fIstartx\fP \fIstarty\fP\fR
.br
Request the user to move the window to a new place.
.I Startx
and
.I starty
are the coordinates of the pointer when the request was initiated.
.IP "\f(CW!size \fItag\fP\fR
.br
Request the user to resize the window.
.RE
.LP
To convert a typical Tk application, do the following.
.IP 1.
Use an editor to make the following changes:
.RS
.TS
cfI cfI
lf(CW) lf(CW) .
Old	New
Wmlib	Tkclient
wmlib	tkclient
tkclient->titlebar	tkclient->toplevel
tkclient->titlectl	tkclient->wmctl
tkclient->taskbar	tkclient->settitle
tk->imageput	tk->putimage
tk->imageget	tk->getimage
.TE
.RE
.IP 2.
Insert the following code at the top of the central
.CW alt
statement.
The names
.CW wmctl ' `
and
.CW top ` '
will need changing to the appropriate variables in the program:
.RS
.P1
s := <-top.ctxt.kbd =>
	tk->keyboard(top, s);
s := <-top.ctxt.ptr =>
	tk->pointer(top, *s);
s := <-top.ctxt.ctl or
s = <-top.wreq or
s = <-wmctl =>
	tkclient->wmctl(top, s);
.P2
.RE
.IP 3.
Add the following just after the Tk configuration code and
before the main processing starts:
.RS
.P1
tkclient->onscreen(top, nil);
tkclient->startinput(top, "kbd"::"ptr"::nil);
.P2
This is possibly the easiest part to forget.
.RE
.LP
Be careful of cases where a blocking function is called
from the main loop that relies on keyboard/mouse input.
The easiest solution can be to spawn a thread to handle the
keyboard and mouse independently.
