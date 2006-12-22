implement RcxFirmdl;

include "sys.m";
include "draw.m";
include "bufio.m";
include "rcxsend.m";

RcxFirmdl : module {
	init : fn (ctxt : ref Draw->Context, argv : list of string);
};

sys : Sys;
bufio : Bufio;
rcx : RcxSend;
me : int;

Iobuf : import bufio;

Image : adt {
	start : int;
	offset : int;
	length : int;
	data : array of byte;
};

DL_HDR : con 5;			# download packet hdr size
DL_DATA : con 16rc8;		# download packet payload size

init(nil : ref Draw->Context, argv : list of string)
{
	sys = load Sys Sys->PATH;
	me = sys->pctl(Sys->NEWPGRP, nil);

	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		error(sys->sprint("cannot load bufio module: %r"));
	rcx = load RcxSend "rcxsend.dis";
	if (rcx == nil)
		error(sys->sprint("cannot load rcx module: %r"));

	argv = tl argv;
	if (len argv != 2)
		error("usage: portnum file");

	portnum := int hd argv;
	file := hd tl argv;

	img := getimage(file);
	cksum := sum(img.data[0:img.length]);
	sys->print("length %.4x start %.4x \n", img.length, img.start);

	err := rcx->init(portnum, 1);
	if (err != nil)
		error(err);

	# delete firmware
	sys->print("delete firmware\n");
	reply : array of byte;
	rmfirm := array [] of {byte 16r65, byte 1, byte 3, byte 5, byte 7, byte 11};
	reply = rcx->send(rmfirm, len rmfirm, 1);
	if (reply == nil)
		error("delete firmware failed");
	chkreply(reply, array [] of {byte 16r92}, "delete firmware");

	# start download
	sys->print("start download\n");
	dlstart := array [] of {byte 16r75,
					byte (img.start & 16rff),
					byte ((img.start>>8) & 16rff),
					byte (cksum & 16rff),
					byte ((cksum>>8) & 16rff),
					byte 0,
	};
	reply = rcx->send(dlstart, len dlstart, 2);
	chkreply(reply,array [] of {byte 16r82, byte 0}, "start download");

	# send the image
	data := array [DL_HDR+DL_DATA+1] of byte;	# hdr + data + 1 byte cksum
	seqnum := 1;
	step := DL_DATA;
	for (i := 0; i < img.length; i += step) {
		data[0] = byte 16r45;
		if (seqnum & 1)
			# alternate ops have bit 4 set
			data[0] |= byte 16r08;
		if (i + step > img.length) {
			step = img.length - i;
			seqnum = 0;
		}
		sys->print(".");
		data[1] = byte (seqnum & 16rff);
		data[2] = byte ((seqnum >> 8) & 16rff);
		data[3] = byte (step & 16rff);
		data[4] = byte ((step >> 8) & 16rff);
		data[5:] = img.data[i:i+step];
		data[5+step] = byte (sum(img.data[i:i+step]) & 16rff);
		reply = rcx->send(data, DL_HDR+step+1, 2);
		chkreply(reply, array [] of {byte 16rb2, byte 0}, "tx data");
		seqnum++;
	}

	# unlock firmware
	sys->print("\nunlock firmware\n");
	ulfirm := array [] of {byte 16ra5, byte 'L', byte 'E', byte 'G', byte 'O', byte 174};
	reply = rcx->send(ulfirm, len ulfirm, 26);
	chkreply(reply, array [] of {byte 16r52}, "unlock firmware");
	sys->print("result: %s\n", string reply[1:]);

	# all done, tidy up
	killgrp(me);
}

chkreply(got, expect : array of byte, err : string)
{
	if (got == nil || len got < len expect)
		error(err + ": short reply");
	# RCX sometimes sets bit 3 of 'opcode' byte to prevent
	# headers with same opcode having exactly same value - mask out
	got[0] &= byte 16rf7;

	for (i := 0; i < len expect; i++)
		if (got[i] != expect[i]) {
			hexdump(got);
			error(sys->sprint("%s: reply mismatch at %d", err, i));
		}
}
	
error(msg : string)
{
	sys->print("%s\n", msg);
	killgrp(me);
	raise "fail:error" ;
}

killgrp(pid : int)
{
	pctl := sys->open("/prog/" + string pid + "/ctl", Sys->OWRITE);
	if (pctl != nil) {
		poison := array of byte "killgrp";
		sys->write(pctl, poison, len poison);
	}
}

sum(data : array of byte) : int
{
	t := 0;
	for (i := 0; i < len data; i++)
		t += int data[i];
	return t;
}

hexdump(data : array of byte)
{
	for (i := 0; i < len data; i++)
		sys->print("%.2x ", int data[i]);
	sys->print("\n");
}

IMGSTART : con 16r8000;
IMGLEN : con 16r4c00;
getimage(path : string) : ref Image
{
	img := ref Image (IMGSTART, IMGSTART, 0, array [IMGLEN] of {* => byte 0});
	iob := bufio->open(path, Sys->OREAD);
	if (iob == nil)
		error(sys->sprint("cannot open %s: %r", path));

	lnum := 0;
	while ((s := iob.gets('\n')) != nil) {
		lnum++;
		slen := len s;
		# trim trailing space
		while (slen > 0) {
			ch := s[slen -1];
			if (ch == ' ' || ch == '\r' || ch == '\n') {
				slen--;
				continue;
			}
			break;
		}
		# ignore blank lines
		if (slen == 0)
			continue;

		if (slen < 10)
			# STNNAAAACC
			error("short S-record: line " + string lnum);

		s = s[0:slen];
		t := s[1];
		if (s[0] != 'S' || t < '0' || t > '9')
			error("bad S-record format: line " + string lnum);

		data := hex2bytes(s[2:]);
		if (data == nil)
			error("bad chars in S-record:  line " + string lnum);

		count := int data[0];
		cksum := int data[len data - 1];
		if (count != len data -1)
			error("S-record length mis-match:  line " + string lnum);

		if (sum(data[0:len data -1]) & 16rff != 16rff)
			error("bad S-record checksum:  line " + string lnum);

		alen : int;
		case t {
		'0' =>
			# addr[2] mname[10] ver rev desc[18] cksum
			continue;
		'1' =>
			# 16-bit address, data
			alen = 2;
		'2' =>
			# 24-bit address, data
			alen = 3;
		'3' =>
			# 32-bit address, data
			alen = 4;
		'4' =>
			# extension record
			error("bad S-record type: line " + string lnum);
		'5' =>
			# data record count - ignore
			continue;
		'6' =>
			# unused - ignore
			continue;
		'7' =>
			img.start = wordval(data, 1, 4);
			continue;
		'8' =>
			img.start = wordval(data, 1, 3);
			continue;
		'9' =>
			img.start = wordval(data, 1, 2);
			continue;
		}
		addr := wordval(data, 1, alen) - img.offset;
		if (addr < 0 || addr > len img.data)
			error("S-record address out of range: line " + string lnum);
		img.data[addr:] = data[1+alen:1+count];
		img.length = max(img.length, addr + count -(alen +1));
	}
	iob.close();
	return img;
}

wordval(src : array of byte, s, l : int) : int
{
	r := 0;
	for (i := 0; i < l; i++) {
		r <<= 8;
		r += int src[s+i];
	}
	return r;
}

max(a, b : int) : int
{
	if (a > b)
		return a;
	return b;
}

hex2bytes(s : string) : array of byte
{
	slen := len s;
	if (slen & 1)
		# should be even
		return nil;
	data := array [slen/2] of byte;
	six := 0;
	dix := 0;
	while (six < slen) {
		d1 := hexdigit(s[six++]);
		d2 := hexdigit(s[six++]);
		if (d1 == -1 || d2 == -1)
			return nil;
		data[dix++] = byte ((d1 << 4) + d2);
	}
	return data;
}

hexdigit(h : int) : int
{
	if (h >= '0' && h <= '9')
		return h - '0';
	if (h >= 'A' && h <= 'F')
		return 10 + h - 'A';
	if (h >= 'a' && h <= 'f')
		return 10 + h - 'a';
	return -1;
}
