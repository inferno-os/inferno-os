implement Cons;

# possibly useful bits from wm/sh

include "sys.m";
	sys: Sys;
	FileIO: import sys;

include "draw.m";

include "sh.m";

include "string.m";
	str: String;

include "arg.m";

Cons: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

BSW:		con 23;		# ^w bacspace word
BSL:		con 21;		# ^u backspace line
EOT:		con 4;		# ^d end of file
ESC:		con 27;		# hold mode

Rdreq: adt
{
	off:	int;
	nbytes:	int;
	fid:	int;
	rc:	chan of (array of byte, string);
};

rdreq: list of Rdreq;
rawon := 0;
rawinput := "";
partialread: array of byte;

events: list of string;
evrdreq: list of Rdreq;

init(ctxt: ref Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	arg := load Arg Arg->PATH;
	arg->init(args);
	arg->setusage("aux/cons [-ilxvn] [-c command] [file [args...]]");

	sys->pctl(Sys->FORKFD | Sys->FORKNS | Sys->NEWPGRP | Sys->FORKENV, nil);

	shargs: list of string;
	while ((opt := arg->opt()) != 0) {
		case opt {
		'c' =>
			shargs = arg->earg() :: "-c" :: shargs;
		'i' or 'l' or 'x' or 'v' or 'n' =>
			shargs = sys->sprint("-%c", opt) :: shargs;
		* =>
			arg->usage();
		}
	}
	args = arg->args();
	for (; shargs != nil; shargs = tl shargs)
		args = hd shargs :: args;

	ioc := chan of (int, ref FileIO, ref FileIO, string);
	spawn newsh(ctxt, ioc, args);

	(nil, file, filectl, consfile) := <-ioc;
	if(file == nil || filectl == nil || shctl == nil) {
		sys->fprint(sys->fildes(2), "cons: shell /dev/cons creation failed\n");
		return;
	}

	for(;;) alt {
	c := <-keys =>			# TO DO: input arriving from remote ...; echo, edit ...
		char := c[1];
		if(char == '\\')
			char = c[2];
		if(rawon){
			rawinput[len rawinput] = char;
			sendinput(t);
			break;
		}
		case char {
		* =>
			cmd(t, ".ft.t insert insert "+c);
		'\r' =>
			;	# TO DO
		'\n' or
		EOT =>
			cmd(t, ".ft.t insert insert "+c);
			sendinput(t);
		'\b' =>
			cmd(t, ".ft.t tkTextDelIns -c");
		'u'& 8r37 =>
			cmd(t, ".ft.t tkTextDelIns -l");
		'w'& 8r37 =>
			cmd(t, ".ft.t tkTextDelIns -w");
		}

	rdrpc := <-filectl.read =>
		if(rdrpc.rc != nil)
			rdrpc.rc <-= (nil, "permission denied");

	(nil, data, nil, wc) := <-filectl.write =>
		if(wc == nil) {
			# consctl closed - revert to cooked mode
			rawon = 0;
			continue;
		}
		(nc, cmdlst) := sys->tokenize(string data, " \n");
		if(nc == 1) {
			case hd cmdlst {
			"rawon" =>
				rawon = 1;
				rawinput = "";
				# discard previous input
				advance := string (len tk->cmd(t, ".ft.t get outpoint end") +1);
				cmd(t, ".ft.t mark set outpoint outpoint+" + advance + "chars");
				partialread = nil;
			"rawoff" =>
				rawon = 0;
				partialread = nil;
			"holdon" or "holdoff" =>
				;
			* =>
				wc <-= (0, "unknown control message");
				continue;
			}
			wc <-= (len data, nil);
			continue;
		}
		wc <-= (0, "unknown control message");

	rdrpc := <-file.read =>
		if(rdrpc.rc == nil) {
			(ok, nil) := sys->stat(consfile);
			if (ok < 0)
				return;
			continue;
		}
		append(rdrpc);
		sendinput(t);

	(nil, data, nil, wc) := <-file.write =>
		if(wc == nil) {
			(ok, nil) := sys->stat(consfile);
			if (ok < 0)
				return;
			continue;
		}
		# TO DO: data from cons; edit (eg, add \r) and forward to remote
		wc <-= (len data, nil);
		data = nil;
	}
}

RPCread: type (int, int, int, chan of (array of byte, string));

append(r: RPCread)
{
	t := r :: nil;
	while(rdreq != nil) {
		t = hd rdreq :: t;
		rdreq = tl rdreq;
	}
	rdreq = t;
}

sendinput(t: ref Tk->Toplevel)
{
	input: string;
	if(rawon)
		input = rawinput;
	else
		input = tk->cmd(t, ".ft.t get outpoint end");
	if(rdreq == nil || (input == nil && len partialread == 0))
		return;
	r := hd rdreq;
	(chars, bytes, partial) := triminput(r.nbytes, input, partialread);
	if(bytes == nil)
		return;	# no terminator yet
	rdreq = tl rdreq;

	alt {
	r.rc <-= (bytes, nil) =>
		# check that it really was sent
		alt {
		r.rc <-= (nil, nil) =>
			;
		* =>
			return;
		}
	* =>
		return;	# requester has disappeared; ignore his request and try another
	}
	if(rawon)
		rawinput = rawinput[chars:];
	else
		cmd(t, ".ft.t mark set outpoint outpoint+" + string chars + "chars");
	partialread = partial;
}

# read at most nr bytes from the input string, returning the number of characters
# consumed, the bytes to be read, and any remaining bytes from a partially
# read multibyte UTF character.
triminput(nr: int, input: string, partial: array of byte): (int, array of byte, array of byte)
{
	if(nr <= len partial)
		return (0, partial[0:nr], partial[nr:]);
	if(holding)
		return (0, nil, partial);

	# keep the array bounds within sensible limits
	if(nr > len input*Sys->UTFmax)
		nr = len input*Sys->UTFmax;
	buf := array[nr+Sys->UTFmax] of byte;
	t := len partial;
	buf[0:] = partial;

	hold := !rawon;
	i := 0;
	while(i < len input){
		c := input[i++];
		# special case for ^D - don't read the actual ^D character
		if(!rawon && c == EOT){
			hold = 0;
			break;
		}

		t += sys->char2byte(c, buf, t);
		if(c == '\n' && !rawon){
			hold = 0;
			break;
		}
		if(t >= nr)
			break;
	}
	if(hold){
		for(j := i; j < len input; j++){
			c := input[j];
			if(c == '\n' || c == EOT)
				break;
		}
		if(j == len input)
			return (0, nil, partial);
		# strip ^D when next read would read it, otherwise
		# we'll give premature EOF.
		if(i == j && input[i] == EOT)
			i++;
	}
	partial = nil;
	if(t > nr){
		partial = buf[nr:t];
		t = nr;
	}
	return (i, buf[0:t], partial);
}

newsh(ctxt: ref Context, ioc: chan of (int, ref FileIO, ref FileIO, string, ref FileIO), args: list of string)
{
	pid := sys->pctl(sys->NEWFD, nil);

	sh := load Command "/dis/sh.dis";
	if(sh == nil) {
		ioc <-= (0, nil, nil, nil);
		return;
	}

	tty := "cons."+string pid;

	sys->bind("#s","/chan",Sys->MBEFORE);
	fio := sys->file2chan("/chan", tty);
	fioctl := sys->file2chan("/chan", tty + "ctl");
	ioc <-= (pid, fio, fioctl, "/chan/"+tty);
	if(fio == nil || fioctl == nil)
		return;

	sys->bind("/chan/"+tty, "/dev/cons", sys->MREPL);
	sys->bind("/chan/"+tty+"ctl", "/dev/consctl", sys->MREPL);

	fd0 := sys->open("/dev/cons", Sys->OREAD|Sys->ORCLOSE);
	fd1 := sys->open("/dev/cons", Sys->OWRITE);
	fd2 := sys->open("/dev/cons", Sys->OWRITE);

	{
		sh->init(ctxt, "sh" :: "-n" :: args);
	}exception{
	"fail:*" =>
		exit;
	}
}
