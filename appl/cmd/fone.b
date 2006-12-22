implement fone;

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
	stdout: ref Sys->FD;
	logfd:	ref Sys->FD;

include "draw.m";
	draw: Draw;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

include "sh.m";
	smtp: Command;

#include "keyring.m";

include "daytime.m";
	daytime: Daytime;

TIMEGRAN:	con 60000;
debug		:= 0;
logflag		:= 0;
logfile		:= "";		# name of log file
Nphones		:= 0;		# number of telephone sets configured
voicefile	:= "";		# name of serial port to DECTalk
voice:		ref sys->FD;
mailhost	:= "";

person: adt {
	mailaddr:	string;
	name:		string;		# name pronounced by the voice
	lineno:		string;		# 4 digit extension
	time:		string;
	orignum:	string;		# originating number
	origname:	string;		# originating name
	state:		int;
	flags:		int;
};

# states
ONHOOK:		con 0;
RING:		con 1;
DISPLAY:	con 2;
OFFHOOK:	con 3;

# flags
LOG:		con 1;
MAIL:		con 2;
ANNOUNCE:	con 4;

telset:	adt {
	devfile:	string;			# file name of interface to phone set
	apprfile:	string;
	apprtime:	int;			# time appearance file is read
	phonefd:	ref sys->FD;		# open FD for this set
	numappr:	int;			# number of appearances on this set
	people:		array of person;	# appearance data for this set
	version:	string;			# telephone set version
};

phone:= array[4] of telset;

months:= array[13] of { 0 => "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug","Sep", "Oct", "Nov", "Dec"};

fone: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string) {

	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	daytime = load Daytime Daytime->PATH;
	smtp = load Command "smtp.dis";
#	keyring := load Keyring Keyring->PATH;

	stdout = sys->fildes(1);
	logfd = stdout;
	stderr = sys->fildes(2);
	voicechan := chan of string;
	timechan := chan of string;

#
# set up name space.  According to tradition this is done
# outside of the program.  Needs to be here so debugging
# is not so tedious.
#
	if (sys->pctl(sys->FORKNS, nil) < 0) {
		sys->fprint(stderr, "pctl(FORKNS) failed: %r\n");
		exit;
	}
	if (sys->bind("#t", "/dev", sys->MAFTER) < 0) {
		sys->fprint(stderr, "bind #t failed: %r\n");
		exit;
	}
	if (sys->bind("#p", "/prog", sys->MAFTER) < 0) {
		sys->fprint(stderr, "bind #p failed: %r\n");
		exit;
	}

	if (sys->bind("#C", "/", sys->MAFTER) < 0) {
		sys->fprint(stderr, "bind #C failed: %r\n");
		exit;
	}

	argv = tl argv;
	while(argv != nil && len hd argv && (arg := hd argv)[0] == '-' && len arg > 1){
		case arg[1] {
		'd' =>
			debug = 1;
			logflag  = 1;
		}
		argv = tl argv;
	}
	configfile("fone.cfg");
#
# Sound Blaster using sbtalker and read
#
#	voice = SBsetup();
#
# DECtalk using second serial port
	voice = DTsetup(voicefile);

	sys->fprint(voice, "hello.\r");


	spawn timekeeper(timechan);
	for (phoneid := 0; phoneid < Nphones; phoneid++)
		spawn watchphone(phoneid, voicechan);
	for (;;) alt {
	mesg := <- voicechan =>
		sys->fprint(voice, "%s", mesg);
	tmesg := <- timechan =>
		case tmesg {
		"filecheck" =>
			for (i:=0; i<Nphones; i++) {
				(r, f) := sys->stat(phone[i].apprfile);
				if (r < 0) {
					sys->fprint(stderr, "cannot stat %s: %r\n", phone[i].apprfile);
					continue;
				}
				if (f.mtime > phone[i].apprtime)
					getcallapprinfo(i);
			}
		}
	}
}

#
# read in the configuration file which tells the program which
# files and devices to use.
#
configfile(cfgname: string): int {
	line, errstr: string;

	cfgfd := sys->open(cfgname, sys->OREAD);
	if (cfgfd == nil) {
		sys->fprint(stderr, "open %s failed, %r\n", cfgname);
		bye();
	}
	do {
		(line, errstr) = getline(cfgfd);
		if (errstr != nil) {
			sys->fprint(stderr, "error reading config file: %r\n");
			return -1;
		}
		if (line != nil) {
			(i, t) := sys->tokenize(line, ": \t\r\n");
			if ((hd t)[0] == '#') continue;
			case hd t {
			"logfile" =>
				if (i < 2) {
					sys->fprint(stderr, "no log file name found. %d\n", i);
					sys->fprint(stderr, "logfile:	 log_file_name\n");
					return -1;
				}
				t = tl t;
				logfile = hd t;
				if (logfile != nil) {
					if ((logfd = sys->open(logfile, sys->OWRITE)) == nil) {
						sys->fprint(stderr, "open log file %s failed\n", logfile);
						continue;
					}
					logflag = 1;
				}
			"mailhost" =>
				if (i < 2) {
					sys->fprint(stderr, "no mailhost found.");
					sys->fprint(stderr, "mailhost:	 host_name\n");
					return -1;
				}
				t = tl t;
				mailhost = hd t;
			"voice" =>
				if (i < 2) {
					sys->fprint(stderr, "no log file name found.");
					sys->fprint(stderr, "voice:	 serial_port\n");
					return -1;
				}
				t = tl t;
				voicefile = hd t;
			"phone" =>
				if (i < 3) {
					sys->fprint(stderr, "not enough fields for phone attendance line\n");
					sys->fprint(stderr, "attend:	 serial_port	phone_appearance_file_name\n");
					return -1;
				}
				t = tl t;
				phonefile := hd t;
				t = tl t;
				apprfile := hd t;
				phone[Nphones].devfile = phonefile;
				phone[Nphones].apprfile = apprfile;
				phone[Nphones].phonefd = sys->open(phonefile, sys->ORDWR);
				if (phone[Nphones].phonefd == nil) {
					sys->fprint(stderr, "open %s failed, %r\n", phonefile);
					return -1;
				}
				(numappr, version) := phoneinit(Nphones);
				if (numappr == 0) continue;
				phone[Nphones].numappr = numappr;
				phone[Nphones].people = array[numappr + 1] of person;
				phone[Nphones].version = version;
				if (debug) sys->fprint(stderr, "phone %d initialized\n", Nphones);
				getcallapprinfo(Nphones);
				++Nphones;
			* =>
				sys->fprint(stderr, "bad keyword <%s> in configuration file\n", hd t);
				return -1;
			}
		}
	} while (line != nil);
	return 0;
}

#
#
#
timekeeper(tchan: chan of string) {
	for(;;) {
		sys->sleep(TIMEGRAN);
		tchan <- = sys->sprint("filecheck");
	}
}

#
# monitor the status messages of the phone(s).
# look for ring indications and subsequent display data to send
# to users if they do not answer their phones.
# If display data is received and the phone is not answered,
# a mail message is sent.
#
watchphone(pindex: int, voicechan: chan of string) {
	buf, errbuf: string;

	do {
		(buf, errbuf) = getline(phone[pindex].phonefd);
		if (errbuf != nil) {
			sys->fprint(stderr, "%s\n", errbuf);
			return;
		}
		if (debug) sys->fprint(stderr, "phone %d: %s\n", pindex, buf);
		(resultcode, info) := str->splitl(buf, ":");
		if (resultcode == nil) continue;
		
		# get rid of colon
		info = info[1:];

		(i, t) := sys->tokenize(info, ",");
		appr := int hd t;
		t = tl t;
		--i;
		case resultcode {
		"RING" or "02" =>
			if ((phone[pindex].people[appr].flags & ANNOUNCE))
				voicechan <- = sys->sprint("phone call for, %s.\r", phone[pindex].people[appr].name);
			phone[pindex].people[appr].state = RING;
			phone[pindex].people[appr].time = "";
			phone[pindex].people[appr].orignum = "";
			phone[pindex].people[appr].origname = "";
		"DISPLAY" or "06" =>
			if (i <= 0) {
				sys->fprint(stderr, "not enough args for DISPLAY result code\n");
				continue;
			}
			displaydata := hd t;
			(displaytype, s) := str->toint(displaydata[0:2], 16);
			case displaytype {
			16r03 =>
				# originating number
				phone[pindex].people[appr].orignum = displaydata[2:];
			16r05 =>
				# originating name
				phone[pindex].people[appr].origname = displaydata[2:];
			16r0a =>
				correct24hr: int;

				# date and time
				if (displaydata[13:15] == "pm")
					correct24hr = 12;
				else
					correct24hr = 0;
#				hour := int displaydata[8:10] + correct24hr;
				phone[pindex].people[appr].time = sys->sprint("%s %2d %2d:%.2d", months[int displaydata[2:4]], int displaydata[5:7],  int displaydata[8:10] % 12 + correct24hr, int displaydata[11:13]);
				phone[pindex].people[appr].state = DISPLAY;
				if (logflag && (phone[pindex].people[appr].flags & LOG))
					sys->fprint(logfd, "%s: x%s %s (%s)\n", phone[pindex].people[appr].time, phone[pindex].people[appr].lineno, phone[pindex].people[appr].orignum, phone[pindex].people[appr].origname);
			}
		"SIGNAL" or "13" =>
			signalcode := hd t;
			t = tl t;
			--i;
			case signalcode {
			"4F" =>
				if (i <= 0) {
					if (phone[pindex].people[appr].state == DISPLAY) {
						phone[pindex].people[appr].state = OFFHOOK;
					}
					continue;
				}
				causecode := hd t;
				case causecode {
				"10" =>
					case phone[pindex].people[appr].state {
					DISPLAY =>
						if ((phone[pindex].people[appr].flags & MAIL) && phone[pindex].people[appr].mailaddr != "-") {
							mailmesg := sys->sprint("From: phoneca\nTo: %s\nSubject: Phone call from %s\n\n from: %s\n phone: %s\n time: %s\n", phone[pindex].people[appr].mailaddr, phone[pindex].people[appr].orignum, phone[pindex].people[appr].origname, phone[pindex].people[appr].orignum, phone[pindex].people[appr].time);

							spawn smtp->init(nil, "smtp" :: mailhost :: "phoneca" :: phone[pindex].people[appr].mailaddr :: mailmesg :: nil);
						}
					}
					phone[pindex].people[appr].state = ONHOOK;
				}
			}
		}
	} while(errbuf == nil);
}

usage() {
	sys->fprint(stderr, "usage: fone -d phone_dev\n");
	bye();
}

#
# wait for an OK from a particular phone, part of Hayes protocol
OK(phonefd: ref sys->FD): int {
	buf, err: string;

	do {
		(buf, err) = getline(phonefd);
		if (err != nil) {
			sys->fprint(stderr, "%s\n", err);
			return(0);
		}
		if (debug) sys->fprint(stderr, "%s\n", buf);
	} while (buf != "OK" && buf != "0");
	return(1);
}

bye() {
	exit;
}

phoneinit(pindex: int): (int, string) {
	buf, err: string;
	i: int;
	t: list of string;

	phonefd := phone[pindex].phonefd;
# E0=echo OFF, V0=verbal return codes ON/OFF, &D0=ignore DTR transition
	if (debug) sys->fprint(stderr, "initialize phone %d serial port...", pindex);
	sys->fprint(phonefd, "ATE0V1&D0\r");
	if (!OK(phonefd)) return (0, "cannot initialize phone");

# &&I=init phone, I3=report phone type
	if (debug) sys->fprint(stderr, "get phone version...");
	sys->fprint(phonefd, "AT&&II3\r");
	do {
		(buf, err) = getline(phonefd);
		if (err != nil) {
			sys->fprint(stderr, "%s\n", err);
			return (0, "cannot get phone version");
		}
		(i, t) = sys->tokenize(buf, " \n\r");
	} while (i != 4 || hd t != "03-");
	t = tl t;
	if (!OK(phonefd)) return (0, "cannot get phone version");
	version := hd t;
	if (debug) sys->fprint(stderr, "version <%s>\n", version);
	numappr := int version[2:4];

# %A0=3 channel assigned to control voice
	if (debug) sys->fprint(stderr, "control phone's voice channel...");
	sys->fprint(phonefd, "AT%%A0=3\r");
	if (!OK(phonefd)) return (0, "cannot control voice channel");
	return (numappr, version);
}

#
# get a line of text (up to a newline or carriage return)
# throw away initial newlines or carriage returns
#
getline(fd: ref sys->FD): (string, string) {
	c := array[1] of byte;
	s := "";
	i := 0;

	loop: while(i < 4096) {
		r := sys->read(fd, c, 1);
		if(r < 0)
			return (s, sys->sprint("%r"));
		if(r == 0)
			return (nil, nil);
		case int c[0] {
		'\r' or
		'\n' =>
			if(i != 0)
				break loop;
		* =>
			s[i++] = int c[0];
		}
	
	}
	return (s, nil);
}
#
# read in names and mail addresses for appearances on each phone
#
getcallapprinfo(pindex: int) {
	name : string;
	filename := phone[pindex].apprfile;

	if (debug) sys->fprint(stderr, "getting call appearance data from %s\n", filename);
	who := bufio->open(filename, sys->OREAD);
	if (who == nil) {
		sys->fprint(stderr, "open %s failed, %r\n", filename);
		bye();
	}
	phone[pindex].apprtime = daytime->now();
	while ((s := who.gets('\n')) != nil) {
		if ((array of byte(s))[0] == byte '#') continue;
		(i, t) := sys->tokenize(s, " \t\n\r");
		if(i < 5) {
			sys->fprint(stderr, "Error in %s.  The line was:\n%s\n", filename, s);
			continue;
		}
		appr := int hd t;
		t = tl t;
		phone[pindex].people[appr].lineno = hd t;
		t = tl t;
		flags := hd t;
		phone[pindex].people[appr].flags = 0;
		for (n:=0; n<len flags; n++) {
			case int (array of byte flags)[n] {
			'l' =>
				phone[pindex].people[appr].flags |= LOG;
			'm' =>
				phone[pindex].people[appr].flags |= MAIL;
			'a' =>
				phone[pindex].people[appr].flags |= ANNOUNCE;
			* =>
				sys->fprint(stderr, "unknown flag %c\n", int (array of byte flags)[n]);
			}
		}
		t = tl t;
		phone[pindex].people[appr].mailaddr = hd t;
		t = tl t;
		name = "";
		while(t != nil) {
			name += " " + hd t;
			t = tl t;
		}
		phone[pindex].people[appr].name = name;
#		if (debug) sys->fprint(stderr, "added user %s at %d\n", phone[pindex].people[appr].name, appr);
	}
}

#
# Setup connection to use READ.EXE command in SounBlaster software
#
SBsetup(): ref sys->FD {
	cmd := sys->open("/cmd/clone", sys->ORDWR);
	if (cmd == nil) {
		sys->fprint(stderr, "open %s failed, %r\n", "/cmd/clone");
		bye();
	}
	cmdno := array[32] of byte;
	if ((n:=sys->read(cmd, cmdno, 32)) <= 0) {
		sys->fprint(stderr, "read error: %r\n");
		bye();
	}
	cmddirname := "/cmd/" + string cmdno[0:n];

	if (debug) sys->fprint(stderr, "exec'ing command\n");
	if ((n=sys->fprint(cmd, "exec command")) < 0) {
		sys->fprint(stderr, "fprint of cmd failed:%r\n");
		bye();
	}

	cmddata := sys->open(cmddirname + "/data", sys->ORDWR);
	if (cmddata == nil) {
		sys->fprint(stderr, "open %s:%r\n", cmddirname + "/data");
		bye();
	}

	buf := array[128] of byte;
# sys->fprint(stderr, "sending sbtalker\n");
	if ((n=sys->fprint(cmddata, "sbtalker /dBLASTER\r")) < 0) {
		sys->fprint(stderr, "fprint of cmddata failed:%r\n");
		bye();
	}
	n = sys->read(cmddata, buf, 128);
	if (n < 0) {
		sys->fprint(stderr, "read /cmd/n/data failed:%r\n");
		bye();
	}
	sys->fprint(stderr, "%*s\n", n, string buf[0:n]);

# sys->fprint(stderr, "sending read\n");
	if ((n=sys->fprint(cmddata, "read\r")) < 0) {
		sys->fprint(stderr, "fprint of cmddata failed:%r\n");
		bye();
	}
	n = sys->read(cmddata, buf, 128);
	if (n < 0) {
		sys->fprint(stderr, "read /cmd/n/data failed:%r\n");
		bye();
	}
	sys->fprint(stderr, "%*s\n", n, string buf[0:n]);
	return cmddata;
}

#
# setup connection to DECTalk
#
DTsetup(voicedev: string): ref sys->FD {
	voicel := sys->open(voicedev, sys->ORDWR);
	if (voicel == nil) {
		sys->fprint(stderr, "open %s failed, %r\n", voicedev);
		bye();
	}
	voicectl := sys->open(voicedev+"ctl", sys->OWRITE);
	if (voicectl == nil) {
		sys->fprint(stderr, "open %s failed, %r\n", voicedev+"ctl");
		bye();
	}
	if (sys->fprint(voicectl, "B1200") != 5) {
		sys->fprint(stderr, "write %s failed, %r\n", voicedev+"ctl");
		bye();
	}
	return voicel;
}
