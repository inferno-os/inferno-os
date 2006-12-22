.FP palatino
.TL
Installing the Vita Nuova grid software
.AU
Vita Nuova
.br
5 May 2005
.NH 1
Package contents
.LP
The installation CD contains software for  both grid client and the server (scheduler),
in separate directories in the root directory of the CD:
.B client
and
.B server .
.NH 1
Client software
.LP
The grid client software will be installed on Windows NT4/2000/XP machines,
in the directory (folder)
.CW C:\eVNClient .
.IP 1.
On a Windows machine with the CD loaded,
use Windows Explorer (or equivalent) to move to the directory named
.CW \eclient\einstall
on the CD.
.IP 2.
Double-click
.CW setup.exe
in that directory.
It will display a new window that prompts for a destination directory.
The directory need not exist but if it does, it should be empty.
The default should be
.CW C:\eVNClient .
You can change the name if required (eg, because
.CW C:
lacks space), but
you will then need to edit several files, as discussed below,
and make appropriate changes to the instructions below.
Hit the
.SM ENTER
key to start installation.
The program will prompt for permission to create the directory if it does not already exist.
It will then populate it with all files required by the client.
.IP 3.
Move in Explorer to the directory
.CW C:\eVNClient\egrid\eslave .
Check that the file
.CW schedaddr
contains the right address for your scheduler machine.
If you changed the drive letter, you must also change the
four
.CW .bat
files in the directory to replace the
.CW C:
drive letter by the one you used.
.IP 4.
You can now add the grid client as a Windows service by running the appropriate
.CW .bat
file on the client.
Use
.RS
.IP
\f5install_service.bat\fP
for Windows 2000 and Windows XP
.IP \fIOR\fP
\f5install_service_nt4.bat\fP
for Windows NT4
.LP
Just double-clicking in Explorer on the chosen name should install the service.
.RE
.LP
Once installed as a service the client software will start automatically when
the client machine next boots.
You can start it manually using the Windows Services Manager in the usual way.
There are two
.CW .bat
files to remove the service (when desired): \f5remove_service.bat\fP
for 2000/XP and \f5remove_service_nt4.bat\fP for NT4.
.LP
The manual page
.I scheduler-intro (1)
in the PDF file
.CW \escheduler.pdf
on the CD gives more details on running and configuring the client software.
The manual page
.I scheduler-monitor (1)
in the same PDF file describes the use of the Client Monitor software.
.LP
On Windows machines you can remove the directory
.CW C:\eVNClient\eLinux
to reduce the space required on Windows clients.
.NH 1
Server software
.LP
The grid server software will be installed on Linux (Redhat 8 or 9), in the directory
.CW /grid/inferno ,
which should either not exist or be empty.
.LP
Linux will usually mount the CD at
.CW /mnt/cdrom .
.IP 1.
In a shell (`New Terminal') window, type the following command:
.P1
sh /mnt/cdrom/server/install/Linux-grid-386.sh
.P2
Assuming it has permission to do so, it will populate
.CW /grid/inferno
with the Inferno distribution, including the grid scheduler components.
.IP 2.
The file
.CW /mnt/cdrom/server/install/gridsched.sh
contains a Bourne shell script that can be copied to an appropriate
place on your system, or used as the basis for one of your own,
to simplify starting the scheduler.
In particular it sets the right bin directory in
.CW PATH
to find Inferno's
.I emu ,
and starts
.I emu
with the right parameters to find the
.CW /grid/inferno
directory and start the scheduler in the right environment.
.LP
Now check that
.CW /grid/inferno/grid/master/config
contains the right network address for your scheduler.
The manual pages
.I scheduler-intro (1)
and
.I scheduler (1)
in
.CW scheduler.pdf
on the CD give more details on invoking the scheduler in
different ways.
