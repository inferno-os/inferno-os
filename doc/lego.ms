.TL
Styx-on-a-Brick
.AU
Chris Locke
.br
chris@vitanuova.com
.AI
Vita Nuova
.br
June 2000
.SH
Background
.LP
The aim of the Vita-Nuova ``styx-on-a-brick'' project was
to demonstrate the simplicity of the Styx protocol and the ease
with which a Styx `stub' can be implemented on tiny devices.
We also aimed to demonstrate the effectiveness of a protocol based approach
to resource management and sharing, whether the resource be a physical device
or a software service.
.LP
Adopting a protocol-centric view of resource and service management, as opposed to
a language-centric approach (as emphasised for instance by Jini™ with Java)
greatly eased the software burden on our tiny target device \-
implementing a simple protocol in firmware required much less work than trying to
implement a virtual machine.  We are confident that if we had adopted a language-centric
approach, we would not have completed the project within our aggressive space and implementation time constraints.†
.FS
.FA
†Indeed, we later discovered that in the application of Jini to load code into an RCX robot no part
of Jini was actually on the brick.
.FE
.LP
The project took 2 weeks from start to finish.
In this time the firmware was developed and all client software
was written: firmware download, IR-link protocol support,
clockface application and worldclock application.
Two people worked on the project, one full-time, the other (Nigel Roles) part-time.
.LP
The demo was then taken on a Press Conference tour of the US
and later appeared at the Usenix2000 Plan 9/Inferno BOF at the request
of Dennis Ritchie.
.LP
I should stress that the project was a demonstration of the ease of
supporting Styx on small devices \- it was not a demo of robotics!
(Indeed, the design of the IR-link protocol, Styx name space and the
services provided by the firmware would be considerably different for
serious robotics.)
.LP
The project used a standard Lego™ Mindstorms™ robotics kit \-
the ``Robotics Invention System''.  This consists of the RCX brick,
2 motors, 2 button sensors, a light sensor and a whole load of
lego pieces \- including wheels, gears and axles; which all adds up
to a whole load of fun!
.LP
The RCX brick is an Hitachi H8 microcontroller with 32K of RAM and
a 16K ROM BIOS.  The RCX provides 3 motor outputs and 3 sensor inputs.
Communication with the RCX is via IR.  An IR tower is supplied with the
``Robotics Invention System'' that connects to a PC via a serial port.
.SH
Acknowledgements
.LP
Before going any further I must acknowledge the work of Kekoa Proudfoot at
Stanford and Russ Nelson at Crynwr Software.
Without their valiant efforts we would not have been able to pursue this project.
Our work relied on the documents and librcx suite provided by Kekoa:
.P1
http://graphics.stanford.edu/~kekoa/rcx/
.P2
and on information from Russ Nelson's web site
.P1
http://www.crynwr.com/lego-robotics/
.P2
.SH
Files
.LP
The files in the
.CW legostyx.tar
file are shown in Table 1.
.KF
.TS
center;
lf(CW) lfR .
llp.h	Link level protocol constants
styx.c	The firmware implementation
styx.srec	The firmware image (S-record format)
styx_abp.srec	The firmware with the alternating bit part of the link protocol enabled
send.b	Test app \- sends RCX op codes to the brick
firmdl.b	Firmware download app
rcxsend.m	Util module header
rcxsend.b	Util module \- supports RCX ROM message format on serial link
timers.m	Timer module header
timers.b	Util module \- general purpose timers
legolink.b	Implements the link protocol via a limbo file2chan()
clockface.b	The controller app for our Clockface robot
.TE
.fi
.ce 10
.I "Table 1.\ "\c
Files in the Styx-on-a-Brick package
.ce 0
.KE
.SH
Project details
.NH 1
Firmware Download
.LP
The RCX brick comes supplied with Lego firmware to be downloaded into the RAM via
the IR link.  The ROM implements a monitor which provides for the firmware download,
as well as other 'op-codes'.
.LP
We wrote our own firmware in C using the GNU H8 compiler suite on a FreeBSD machine.
The code used Kekoa's
.CW librcx
library for interfacing to the RCX ROM routines.
(We should have liked to have done an H8 code generator for our own compiler suite,
but time did not permit this!)
The
.CW gnuh8
list is accessible via:
.P1
http://www.pcserv.demon.co.uk/
.P2
First up we had to write a Limbo application to communicate with the ROM, via
the IR tower in order that we could get our firmware downloaded onto the RCX.
This is the firmdl application.  Source files: 
.CW firmdl.b , 
.CW rcxsend.b
and 
.CW timers.b
.NH 1
Styx Comms Link
.LP
Having got a means of installing our firmware we needed a means of delivering
Styx messages to and from the Brick.
.LP
Styx makes certain demands of its transport media:
.TS
l l .
Reliable	messages must not get 'lost'
Ordered	messages must not get transposed
.TE
The RCX ROM provides a couple of functions for IR comms \- a routine to check
for message reception and a routine for message delivery.
The message reception routine receives the data of a RCX "Transfer Data"
message (RCX op-code 0x45)
.LP
We chose to use this facility as a means of delivering Styx messages to our Firmware
on the Brick.  But it did not provide the Transport properties that Styx requires.
To meet the Styx requirements we implemented a simple 'alternating bit' protocol whose
payload was the Styx messages themselves.  These Link protocol messages become the
payload of the RCX "Transfer Data" messages.
.LP
The IR link is very slow, the baud rate of the IR tower serial link is 2400
and the ROM message format requires that every byte of a message be doubled up with
its complement. (e.g. the byte 0x7e is transmitted as 0x7e, 0x81)
This is because of the simple way that the RCX ROM and hardware handle elimination
of the ambient IR signal level \- all message have the same number of 1s and 0s so
the ambient IR level can be negated by subtracting the average level.
All RCX messages are also prefixed by a header and suffixed with a checksum:
.P1
0x55 0xff 0x00 \fID1 ~D1 D2 ~D2 ... Dn ~Dn C ~C\fP
.P2
where 
.I D1
\&...
.I Dn
are the bytes in the message body and \fIC = D1+D2+ ... Dn\fP.
.LP
Therefore, the effective data rate is considerably less than 1200 baud.
.LP
We noted that many Styx messages, especially 
.CW Twstat
and 
.CW Rstat ,
contained a high
proportion of 0 byte values.†
.FS
.FA
The protocol has since been revised to reduce that.
.FE
Consequently, we decided to incorporate a 0-run-length
compression scheme in our simple link protocol.
.LP
Within the payload of the link messages:
.TS
l l .
0x88 0x00	represents 0x88
0x88 n	represents n + 2 0's
others	represent themselves
.TE
.LP
An additional burden is that communication with the Brick via the IR tower has to be strictly
synchronous.  The IR tower echoes back all data transmitted to it on the serial link
as well as any data received on the IR link.  Therefore the brick must not send IR data
while the PC is sending serial data to the tower.  In order to achieve this a 'ping-pong'
communication scheme must be employed.  The PC is the master, the brick is the slave.
The master sends a request and waits for the reply from the slave.
Only the master is allowed to start an exchange.
.LP
The problem with the master/slave style of communication is that a Styx Server
implements blocking requests, e.g. reads and writes, by simply not responding to the
request until the operation is completed.  This does not fit with the link protocol
requirement that the server (slave) always respond and the requirement that the brick
cannot instigate a data exchange.
The firmware could simply reply with an empty Link protocol message but it then has no
way of giving timely notification of the completion of a pending Styx request as it is not
allowed to start a link-protocol message exchange.
.LP
To get around the pending Styx reply problem, the link protocol header incorporates a flag
that the slave (brick) can set to indicate that it is holding outstanding requests and that the
master (PC) should continue to poll the slave in order to receive their replies in a timely
fashion.
.LP
The link protocol message format is as follows.
Request from Master (PC) to Slave (RCX):
.LP
.TS
l l .
0x45/4d	RCX Transfer Data op-code  (including RCX alternating bit)
0	LSB of "Data" block number
0	MSB of "Data" block number
*	LSB of "Data" payload length (lost to ROM firmware)
*	MSB of "Data" payload length (lost to ROM firmware) (n+2)
*	LSB of Link protocol payload length
*	MSB of Link protocol payload length (n+1)
*	Link protocol header
*[n-1]	Link protocol payload (0 or 1 Styx messages)
*	"Transfer Data" cksum (Last byte of Link protocol payload)
.TE
.LP
Note that the 0x45 ROM op-code ("Transfer Data") message incorporates a checksum byte at the
end, but the ROM doesn't bother to check it so we moved the last byte of the Link protocol
payload (or the link header if the payload is empty) into the checksum position of
the ROM message.
.LP
Reply from Slave to Master:
.LP
.TS
l l .
?	Junk from ROM
*	LSB of Link protocol payload length
*	MSB of Link protocol payload length (n+1)
*	Link protocol header
*[n]	Link protocol payload
.TE
.LP
The Link protocol header has the following flags:
.LP
.TS
l l .
bit 0	Alternating bit
bit 1	Poll immediate (requested by slave)
bit 2	Poll periodic (requested by slave)
bit 3	compressed (payload is 0-run-length compressed)
bits 4-7	reserved (should be 0)
.TE
.LP
The master flips the 
.I Alternating
.I bit
for every message that it successfully delivers.
If a slave reply is lost or corrupted the master will re-send the message using the same
alternating bit value.  The slave should not act on a repeated message but should
re-send it's last response.  The value of the alternating bit in the slave response
is the same as in the request from the master.
.LP
The 
.I Poll
.I immediate
bit indicates that the slave has more data to send to the master.
The master should immediately send another Link-protocol message, even if it has no
data to send, so as the slave can reply with its pending data.
.LP
The 
.I Poll
.I periodic
bit indicates that the slave has pending (blocked) requests that
it will reply to sometime in the future.  The master should periodically poll the
slave, even if the master has no data to send.  The polling period should be small
enough that reply latencies are acceptable.
.NH 1
The name space
.LP
We now have a means of getting Styx messages to and from the brick.
But what does the name space provided by the firmware on the brick look like?
.LP
We wanted a generic name space; one that reflected the functions of the brick, not
the model attached to it, so that the same firmware could be used with many
different robots.
.LP
The brick has 3 motor outputs and 3 sensor inputs.
The motors can be run forwards or reverse with 8 different power settings.
They can be stalled, also with 8 power levels, and they can be left 'floating'
[A stalled motor presents resistance to turning proportional to the stall power level]
.LP
There are 2 types of sensor \- buttons and light-sensors.
[You can also get a 'rotation sensor', but we had not got one in our kit!]
.LP
We decided on a name space comprised of 2 directories, 
.CW motor
and 
.CW sensor .
We didn't need to use subdirectories for our name space but it was easy, so we did!
.LP
The motor directory contains 4 files \- 
.CW 0 , 
.CW 1 , 
.CW 2
and 
.CW 012 .
The files 
.CW 0 , 
.CW 1
and 
.CW 2
represent the individual motor outputs and
accept command messages of the form
.I 'XP'
where 
.I X
is a direction and
.I P
is the power level.
.LP
.I X
can be one of
.TS
l l .
f	forward
r	reverse
s	stall
F	float
.TE
.LP
.I P
is a digit in the range
.CW '0..7'
.LP
The file 
.CW 012
takes messages of the form
.I 'XPXPXP'
enabling the state of all the motors to be modified with a single message.
The first 
.I XP
pair affects motor 0, the middle pair affects motor 1 and the
last pair affects motor 2.
.I XP
can be
.CW '--'
indicating that the state should remain the same as before.
.LP
.LP
The sensor directory contains three files 
.CW 0 , 
.CW 1
and 
.CW 2 ,
corresponding to the three sensor inputs on the brick.
.LP
Before a sensor file can be read it must be configured by writing a configuration
message to the file.  These message take the form
.I 'Tv*'
where
.I T
is the sensor type and 
.I v*
is a threshold value.
The idea of the threshold value is that reads of the sensor file wil block until
the threshold value has been achieved.
.LP
Reads of a sensor file return its current value.
When a sensor file is configured any pending reads of the sensor are
failed with the error message
.CW 'reset' .
.LP
The available sensor types are:
.LP
.TS
l l .
b	button
l	light sensor
.TE
.LP
The threshold value for a button sensor is a click count.
So the control message
.CW 'b0'
configures a sensor to be a button and subsequent reads
of the file will yield the current click count.
.br
The message
.CW 'b20'
will cause subsequent reads to block until the click count reaches
20 or more.
.LP
The threshold value for a light sensor is a raw sensor value qualified by
.CW '<'
or
.CW '>' .
.LP
The control message
.CW 'l>600'
configures the input to be a light sensor and subsequent
reads will block until the sensor value exceeds 600.
If the
.CW '<'
qualifier is used, reads block until the value drops below the threshold.
.SH
Using the Styx firmware
.NH 1
Download the firmware
.LP
Use the 
.CW firmdl
command to download the firmware to the brick
.P1
% firmdl 0 styx.srec
%
.P2
.LP
The first argument is the number of the inferno serial port (
.CW /dev/eia0
in this example).
The second argument is the file containing the firmware image in s-record format.
.LP
The firmdl app prints the response code from the ROM.
On successful download the ROM reports:
.P1
Just a bit off the block!
.P2
.LP
Once the firmware is downloaded it is immediately run.
The RCX display should be showing the 'running man' symbol.
If at any time the Styx firmware encounters an error, the 'running man'
is changed to a 'standing man' and the source code line number of the error
is displayed on the LCD.
The firmware doesn't stay resident: it monitors the on/off button and
restarts the ROM monitor when it is pressed.
.NH 1
Start the link protocol
.LP
.P1
% legolink 0
%
.P2
.LP
The legolink argument is the serial port over which to run the link protocol.
This will be the same as the first argument to the firmdl command.
.LP
Once started the legolink command creates the file 
.CW /net/legolink
in the Inferno
name space.  Any reads/writes of this file are the payload data of the link protocol.
.NH 1
Mount the brick name space
.LP
.P1
% mount -o -A /net/legolink /n/remote
.P2
.LP
The 
.CW -A
flag to mount prevents the command from trying to
do authentication
on the link before running the Styx protocol over it.
The
.CW -o
option uses an older version of Styx.
The second argument to mount is the the file over which the Styx protocol will be run.
Raw Styx messages are written to and read from this file.
The third argument is the directory on which to mount the name space presented by the
Styx server on the other end of the link \- the firmware on the Brick.
.NH 1
Explore the name space
.LP
.P1
% cd /n/remote
% ls
motor
sensor
% ls motor
motor/0
motor/1
motor/2
motor/012
% ls sensor
sensor/0
sensor/1
sensor/2
%
.P2
.LP
Attach a motor to the first output and a button sensor to the first input
and then try the following...
.LP
Start motor...
.P1
% cd motor
% echo -n f7 > 0
%
.P2
.LP
Reverse the motor...
.P1
% echo -n r7 > 0
%
.P2
.LP
Stop the motor (float)...
.P1
% echo -n F0 > 0
%
.P2
.LP	
Notice the need for the 
.CW -n
flag to echo.  The firmware is a bit touchy about
the format of the motor control messages \- they have to be 2 bytes long.
.LP
Run the motor for (a little more than) 5 seconds...
.P1
% echo -n r7 > 0; sleep 5; echo -n F0 > 0
%
.P2
.LP
It takes time on the slow link to open the file for the control message to
stop the motor.  It should be possible to reduce the delay by keeping the file open:
.P1
% {echo -n r7; sleep 5; echo -n F0} > 0
%
.P2
but the firmware only accepts command messages written to file offset 0.
.br
[Fixing this is left as an exercise for the reader!]
.LP
Ok, lets play with a sensor...
.P1
% cd /n/remote/sensor
% echo b0 > 0
% cat 0
0%
.P2
.LP
Note that the sensor file isn't as fussy about its message format as the motor file.
.LP
Click the button a few times and then try reading the sensor file again
.P1
% cat 0
4%
.P2
.LP
Let's try a blocking read on the sensor
.P1
% echo b5 > 0
% cat 0
\fR[click the button 5 times]\fP
5%
.P2
.LP
Ok, we're done playing \- unmount the brick name space
.P1
% cd
% ls /n/remote
/n/remote/motor
/n/remote/sensor
% unmount /n/remote
% ls /n/remote
%
.P2
.SH
The Clockface robot
.LP
So we have a means of controlling the brick via Styx.
We now needed to design a robot suitable for demonstrating the software.
.LP
The robot needed to be static; the IR link needs to maintain line-of-sight contact
between the IR tower and the brick.
The operation of the robot needed to be clearly visible to a group of people in a
conference room.
We also wanted a robot that we could layer services on top of each other to demonstrate
the versatility of Inferno name spaces.
.LP
We decided on a clock robot.  The robot is static; it doesn't move around the room!
The clockface would be visible and its operation obvious
to a group of people in a reasonably large room.
.LP
The clockface robot also allowed us to layer services:
.LP
Initially we just mount the Brick name space.
This name space represents the services of the brick \- nothing is known of the
robot model that is attached to the brick.
.LP
We then start the clockface service.  This knows how to use the name space of
the brick to control the motors and sensors of the clockface model.
The clockface service provides a 
.CW clockface
file which accepts
time values (e.g.
.CW '14:35' ),
the service then runs motors and reads sensors
to set the hands of the robot to the specified time.
.LP
On top of the clockface service we can run a world-clock service.
This periodically reads the system clock and writes time messages to the
.CW clockface
file resented by the clockface service.
The world-clock service also provides a configuration file so that the user
can set the time zone of the clock display.  Writing a time zone abbreviation into
the control file causes the world-clock service to write new time messages into
the 
.CW clockface
file to reflect the new time zone setting.
.LP
By using Inferno's ability to export a name space, any of the clock  services
could be running anywhere in the network.
The Lego brick could be attached to machine A.
Machine B could be running the legolink application using 
.CW /dev/eia0
imported from machine A.
Machine C could mount the 
.CW /net/legolink
file imported from machine B's
name space.
Machine D could then run the clockface service over the brick's name space
imported from machine C, etc. etc.
.LP
The source of the clockface service is 
.CW clockface.b .
.br
The source of the world-clock service is 
.CW worldclock.b .
.SH
Final Notes
.LP
The firmware could do with some more work on it, such as the overly strict
length restriction on motor control messages, or the fact that control messages
must be written at offset 0.
.LP
Please feel free to fix problems and make modifications.  I am more than happy
to discuss the software and answer any questions you may have.
.LP
Have Fun!
