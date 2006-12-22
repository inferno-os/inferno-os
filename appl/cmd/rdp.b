implement Rdp;
include "sys.m";
	sys: Sys;
	print, sprint: import sys;
include "draw.m";
include "string.m";
	str: String;

df_port: con "/dev/eia0";
df_bps: con 38400;

Rdp: module
{
	init:	fn(nil: ref Draw->Context, arg: list of string);
};

dfd: ref sys->FD;
cfd: ref sys->FD;
ifd: ref sys->FD;
pifd: ref sys->FD;
p_isopen := 0;

R_R15: con 15;
R_PC: con 16;
R_CPSR: con 17;
R_SPSR: con 18;
NREG: con 19;

debug := 0;
nocr := 0;
tmode := 0;
# echar := 16r1c;		# ctrl-\
echar := 16r1d;		# ctrl-]  (because Tk grabs the ctrl-\ )

bint(x: int): array of byte
{
	b := array[4] of byte;
	b[0] = byte x;
	b[1] = byte (x>>8);
	b[2] = byte (x>>16);
	b[3] = byte (x>>24);
	return b;
}

intb(b: array of byte): int
{
	return int b[0] | (int b[1] << 8)
		| (int b[2] << 16) | (int b[3] << 24);
}


statusmsg(n: int): string
{
	m: string;
	case n {
	0 => 	m = nil;
	1 =>	m = "Reset";
	2 =>	m = "Undefined instruction";
	3 =>	m = "Software interrupt";
	4 =>	m = "Prefetch abort";
	5 =>	m = "Data abort";
	6 =>	m = "Address exception";
	7 =>	m = "IRQ";
	8 =>	m = "FIQ";
	9 =>	m = "Error";
	10 =>	m = "Branch Through 0";
	253 =>	m = "Insufficient privilege";
	254 =>	m = "Unimplemented message";
	255 =>	m = "Undefined message";
	* =>	m = sprint("Status %d", n);
	}
	return m;
}

sdc: chan of (array of byte, int);
scc: chan of int;

serinp()
{		
	b: array of byte = nil;
	save: array of byte = nil;
	x := 0;
	for(;;) {
		m := <- scc;
		if(m == 0) {
			save = b[0:x];
			continue;
		}
		b = nil;
		t: int;
		do {
			alt {
			m = <- scc =>
				if(m == 0) 
					print("<strange error>\n");
				b = nil;
			* =>
				;
			}
			if(b == nil) {
				if(m >= 0)
					t = m;
				else
					t = -m;
				x = 0;
				b = array[t] of byte;
			}
			if(save != nil) {
				r := len save;
				if(r > (t-x))
					r = t-x;
				b[x:] = save[0:r];
				save = save[r:];
				if(len save == 0)
					save = nil;
				x += r;
				continue;
			}
			r := sys->read(dfd, b[x:], t-x);
			if(r < 0)
				sdc <-= (array of byte sprint("fail:%r"), -1);
			if(r == 0) 
				sdc <-= (array of byte "fail:hangup", -1);
			if(debug) {
				if(r == 1)
					print("<%ux>", int b[x]);
				else
					print("<%ux,%ux...(%d)>", int b[x], int b[x+1], r);
			}
			x += r;
		} while(m >= 0 && x < t);
		sdc <-= (b, x);
	}
}


sreadn(n: int): array of byte
{
	b: array of byte;
	if(n == 0)
		return array[0] of byte;
	scc <-= n;
	(b, n) = <- sdc;
	if(n < 0)
		raise string b;
	return b[0:n];
}


# yes, it's kind of a hack...
fds := array[32] of ref Sys->FD;

oscmd()
{
	arg := array[4] of int;
	buf := array[4] of array of byte;
	b := sreadn(5);
	op := intb(b[:4]);
	argd := int b[4];
	for(i := 0; i<4; i++) {
		t := (argd >> (i*2))&3;
		case t {
		0 =>	;
		1 =>
			arg[i] = int sreadn(1)[0];
		2 =>
			arg[i] = intb(sreadn(4));
		3 =>
			c := int sreadn(1)[0];
			if(c < 255) {
				buf[i] = array[c] of byte;
				if(c <= 32) {
					buf[i][0:] = sreadn(c);
				} else 
					arg[i] = intb(sreadn(4));
			} else {
				b: array of byte;
				b = sreadn(8);
				c = intb(b[:4]);
				arg[i] = intb(b[4:8]);
				buf[i] = array[c] of byte;
			}
		}
	}
	for(i = 0; i<4; i++)
		if(buf[i] != nil && len buf[i] > 32) 
			rdi_read(arg[i], buf[i], len buf[i]);

	r := 0;
	case op {
	0 or 2 => ;
	* =>
		out("");
	}
	case op {
	0 =>
		if(debug)
			print("SWI_WriteC(%d)\n", arg[0]);
		out(string byte arg[0]);
	2 =>
		if(debug)
			print("SWI_Write0(<%d>)\n", len buf[0]);
		out(string buf[0]);
	4 =>
		if(debug)
			print("SWI_ReadC()\n");
		sys->read(ifd, b, 1);
		r = int b[0];
	16r66 =>
		fname := string buf[0];
		if(debug)
			print("SWI_Open(%s, %d)\n", fname, arg[1]);
		fd: ref Sys->FD;
		case arg[1] {
		0 or 1 =>
			fd = sys->open(fname, Sys->OREAD);
		2 or 3 =>
			fd = sys->open(fname, Sys->ORDWR);
		4 or 5 =>
			fd = sys->open(fname, Sys->OWRITE);
			if(fd == nil)
				fd = sys->create(fname, Sys->OWRITE, 8r666);
		6 or 7 =>
			fd = sys->open(fname, Sys->OWRITE|Sys->OTRUNC);
			if(fd == nil)
				fd = sys->create(fname, Sys->OWRITE, 8r666);
		8 or 9 =>
			fd = sys->open(fname, Sys->OWRITE);
			if(fd == nil)
				fd = sys->create(fname, Sys->OWRITE, 8r666);
			else
				sys->seek(fd, big 0, Sys->SEEKEND);
		10 or 11 =>
			fd = sys->open(fname, Sys->ORDWR);
			if(fd == nil)
				fd = sys->create(fname, Sys->ORDWR, 8r666);
			else
				sys->seek(fd, big 0, Sys->SEEKEND);
		}
		if(fd != nil) {
			r = fd.fd;
			if(r >= len fds) {
				print("<fd %d out of range 1-%d>\n", r, len fds);
				r = 0;
			} else 
				fds[r] = fd;
		} 
	16r68 =>
		if(debug)
			print("SWI_Close(%d)\n", arg[0]);
		if(arg[0] <= 0 || arg[0] >= len fds)
			r = -1;
		else {
			if(fds[arg[0]] != nil)
				fds[arg[0]] = nil;
			else
				r = -1;
		}
	16r69 =>
		if(debug)
			print("SWI_Write(%d, <%d>)\n", arg[0], len buf[1]);
		if(arg[0] <= 0 || arg[0] >= len fds)
			r = -1;
		else 
			r = sys->write(fds[arg[0]], buf[1], len buf[1]);
		r = arg[2]-r;
	16r6a =>
		if(debug)
			print("SWI_Read(%d, 0x%ux, %d)\n", arg[0], arg[1], arg[2]);
		if(arg[0] <= 0 || arg[0] >= len fds)
			r = -1;
		else {
			d := array[arg[2]] of byte;
			r = sys->read(fds[arg[0]], d, arg[2]);
			if(r > 0)
				rdi_write(d, arg[1], r);
		}
		r = arg[2]-r;
	16r6b =>
		if(debug)
			print("SWI_Seek(%d, %d)\n", arg[0], arg[1]);
		if(arg[0] <= 0 || arg[0] >= len fds)
			r = -1;
		else 
			r = int sys->seek(fds[arg[0]], big arg[1], 0);
	16r6c =>
		if(debug)
			print("SWI_Flen(%d)\n", arg[0]);
		if(arg[0] <= 0 || arg[0] >= len fds)
			r = -1;
		else {
			d: Sys->Dir;
			(r, d) = sys->fstat(fds[arg[0]]);
			if(r >= 0)
				r = int d.length;
		}
	16r6e =>
		if(debug)
			print("SWI_IsTTY(%d)\n", arg[0]);
		r = 0;	# how can we detect if it's a TTY?
	* =>
		print("unsupported: SWI 0x%ux\n", op);
	}
	b = array[6] of byte;
	b[0] = byte 16r13;
	if(debug)
		print("r0=%d\n", r);
	if(r >= 0 && r <= 16rff) {
		b[1] = byte 1;
		b[2] = byte r;
		sys->write(dfd, b, 3);
	} else {
		b[1] = byte 2;
		b[2:] = bint(r);
		sys->write(dfd, b, 6);
	}
}


terminal()
{
	b := array[1024] of byte;
	c := 3;	# num of invalid chars before resetting
	tmode = 1;
	for(;;) {
		n: int;
		b: array of byte;
		alt {
		scc <-= -8192 =>
			(b, n) = <- sdc;
		(b, n) = <- sdc =>
			;
		}
		if(n < 0) 
			raise string b;
		c -= out(string b[:n]);
		if(c < 0) {
			scc <-= 0;
			raise "rdp:tmode";
		}
		if(!tmode) {
			return;
		}
	}
}

getreply(n: int): (array of byte, int)
{
	loop: for(;;) {
		c := int sreadn(1)[0];
		case c {
		16r21 =>
			oscmd();
		16r7f =>
			raise "rdp:reset";
		16r5f =>
			break loop;
		* =>
			print("<%ux?>", c);
			scc <-= 0;
			raise "rdp:tmode";
		}
	}
	b := sreadn(n+1);
	s := int b[n];
	if(s != 0) {
		out("");
		print("[%s]\n", statusmsg(s));
	}
	return (b[:n], s);
}

outstr: string;
tpid: int;

timeout(t: int, c: chan of int)
{
	tpid = sys->pctl(0, nil);
	if(t > 0)
		sys->sleep(t);
	c <-= 0;
	tpid = 0;
}

bsc: chan of string;

bufout()
{
	buf := "";
	tc := chan of int;
	n: int;
	s: string;
	for(;;) {
		alt {
		n = <- tc =>
			print("%s", buf);
			buf = "";
		s = <- bsc =>
			#if(tpid) {
			#	kill(tpid);
			#	tpid = 0;
			#}
			if((len buf+len s) >= 1024) {
				print("%s", buf);
				buf = s;
			}
			if(s == "" || debug) {
				print("%s", buf);
				buf = "";
			} else {
				buf += s;
				if(tpid == 0) 
					spawn timeout(300, tc);
			}
		}
	}
}

out(s: string): int
{
	if(bsc == nil) {
		bsc = chan of string;
		spawn bufout();
	}
	c := 0;
	if(nocr || tmode) {
		n := "";
		for(i:=0; i<len s; i++) {
			if(!(nocr && s[i] == '\r'))
				n[len n] = s[i];
			if(s[i] >= 16r7f)
				c++;
		}
		bsc <-= n;
	} else
		bsc <-= s;
	return c;
}

reset(r: int)
{
	out("");
	if(debug)
		print("reset(%d)\n", r);
	p_isopen = 0;
	b := array of byte sprint("b9600");
	sys->write(cfd, b, len b);
	if(r) {
		b[0] = byte 127;
		sys->write(dfd, b, 1);
		print("<sending reset>");
	}
	ok := 0;
	s := "";
	for(;;) {
		n: int;
		b: array of byte;
		scc <-= -8192;
		(b, n) = <- sdc;
		if(n < 0) 
			raise string b;
		for(i := 0; i<n; i++) {
			if(b[i] == byte 127) {
				if(!ok)
					print("\n");
				ok = 1;
				s = "";
				continue;
			}
			if(b[i] == byte 0) {
				if(ok && i == n-1) {
					out(s);
					out("");
					return;
				} else {
					s = "";
					continue;
				}
			}
			if(b[i] < byte 127)
				s += string b[i:i+1];
			else
				ok = 0;
		}
	}
}

sa1100_reset()
{
	rdi_write(bint(1), int 16r90030000, 4);
}

setbps(bps: int)
{
	# for older Emu's using setserial hacks...
	if(bps > 38400)
		sys->write(cfd, array of byte "b38400", 6);

	out("");
	print("<bps=%d>\n", bps);
	b := array of byte sprint("b%d", bps);
	if(sys->write(cfd, b, len b) != len b) 
		print("setbps failed: %r\n");
}

rdi_open(bps: int)
{	
	if(debug)
		print("rdi_open(%d)\n", bps);
	b := array[7] of byte;
	usehack := 0;
	if(!p_isopen) {
		b[0] = byte 0;
		b[1] = byte (0 | (1<<1));
		b[2:] = bint(0);
		case bps {
		9600 => b[6] = byte 1;
		19200 => b[6] = byte 2;
		38400 => b[6] = byte 3;
		# 57600 => b[6] = byte 4;
		# 115200 => b[6] = byte 5;
		# 230400 => b[6] = byte 6;
		* =>
			b[6] = byte 1;
			usehack = 1;
		}
		sys->write(dfd, b, 7);
		getreply(0);
		p_isopen = 1;
		if(usehack)
			sa1100_setbps(bps);
		else
			setbps(bps);
	}
}

rdi_close()
{
	if(debug)
		print("rdi_close()\n");
	b := array[1] of byte;
	if(p_isopen) {
		b[0] = byte 1;
		sys->write(dfd, b, 1);
		getreply(0);
		p_isopen = 0;
	}
}

rdi_cpuread(reg: array of int, mask: int)
{
	if(debug)
		print("rdi_cpuread(..., 0x%ux)\n", mask);
	n := 0;
	for(i := 0; i<NREG; i++)
		if(mask&(1<<i))
			n += 4;
	b := array[6+n] of byte;
	b[0] = byte 4;
	b[1] = byte 255;	# current mode
	b[2:] = bint(mask);
	sys->write(dfd, b, 6);
	(b, nil) = getreply(n);
	n = 0;
	for(i = 0; i<NREG; i++)
		if(mask&(1<<i)) {
			reg[i] = intb(b[n:n+4]);
			n += 4;
		}
}

rdi_cpuwrite(reg: array of int, mask: int)
{
	if(debug)
		print("rdi_cpuwrite(..., 0x%ux)\n", mask);
	n := 0;
	for(i := 0; i<32; i++)
		if(mask&(1<<i))
			n += 4;
	b := array[6+n] of byte;
	b[0] = byte 5;
	b[1] = byte 255;	# current mode
	b[2:] = bint(mask);
	n = 6;
	for(i = 0; i<32; i++)
		if(mask&(1<<i)) {
			b[n:] = bint(reg[i]);
			n += 4;
		}
	sys->write(dfd, b, n);
	getreply(0);
}

dump(b: array of byte, n: int)
{
	for(i := 0; i<n; i++)
		print(" %d: %2.2ux\n", i, int b[i]);
}

rdi_read(addr: int, b: array of byte, n: int): int
{
	if(debug)
		print("rdi_read(0x%ux, ..., 0x%ux)\n", addr, n);
	if(n == 0)
		return 0;
	sb := array[9] of byte;
	sb[0] = byte 2;
	sb[1:] = bint(addr);
	sb[5:] = bint(n);
	sys->write(dfd, sb, 9);
	(b[0:], nil) = getreply(n);
	# if error, need to read count of bytes transferred
	return n;
}

rdi_write(b: array of byte, addr: int, n: int): int
{
	if(debug)
		print("rdi_write(..., 0x%ux, 0x%ux)\n", addr, n);
	if(n == 0)
		return 0;
	sb := array[9+n] of byte;
	sb[0] = byte 3;
	sb[1:] = bint(addr);
	sb[5:] = bint(n);
	sb[9:] = b[:n];
	sys->write(dfd, sb, 9);
	x := 0;
	while(n) {
		q := n;
		if(q > 8192)
			q = 8192;
		r := sys->write(dfd, b[x:], q);
		if(debug)
			print("rdi_write: r=%d ofs=%d n=%d\n", r, x, n);
		if(r < 0)
			raise "fail:hangup";
		x += r;
		n -= r;
	}
	getreply(0);
	return n;
}

rdi_execute()
{
	if(debug)
		print("rdi_execute()\n");
	sb := array[2] of byte;
	sb[0] = byte 16r10;
	sb[1] = byte 0;
	sys->write(dfd, sb, 2);
	getreply(0);
	out("");
}

rdi_info(n: int, arg: int)
{
	sb := array[9] of byte;
	sb[0] = byte 16r12;
	sb[1:] = bint(n);
	sb[5:] = bint(arg);
	sys->write(dfd, sb, 9);
	getreply(0);
}


regdump()
{
	out("");
	reg := array[NREG] of int;
	# rdi_cpuread(reg, 16rffff|(1<<R_PC)|(1<<R_CPSR)|(1<<R_SPSR));
	rdi_cpuread(reg, 16rffff|(1<<R_PC)|(1<<R_CPSR));
	for(i := 0; i < 16; i += 4)
		print("  r%-2d=%8.8ux  r%-2d=%8.8ux  r%-2d=%8.8ux  r%-2d=%8.8ux\n",
			i, reg[i], i+1, reg[i+1],
			i+2, reg[i+2], i+3, reg[i+3]);
	print("   pc=%8.8ux  psr=%8.8ux\n",
			reg[R_PC], reg[R_CPSR]);
}

printable(b: array of byte): string
{
	s := "";
	for(i := 0; i < len b; i++) 
		if(b[i] >= byte ' ' && b[i] <= byte 126)
			s += string b[i:i+1];
		else
			s += ".";
	return s;
}

examine(a: int, n: int)
{
	b := array[4] of byte;
	for(i := 0; i<n; i++) {
		rdi_read(a, b, 4);
		print("0x%8.8ux: 0x%8.8ux  \"%s\"\n", a, intb(b), printable(b));
		a += 4;
	}
}

atoi(s: string): int
{
	b := 10;
	if(len s < 1)
		return 0;
	if(s[0] == '0') {
		b = 8;
		s = s[1:];
		if(len s < 1)
			return 0;
		if(s[0] == 'x' || s[0] == 'X') {
			b = 16;
			s = s[1:];
		}
	}
	n: int;
	(n, nil) = str->toint(s, b);
	return n;
}

regnum(s: string): int
{
	if(len s < 2)
		return -1;
	if(s[0] == 'r' && s[1] >= '0' && s[1] <= '9') 
		return atoi(s[1:]);
	case s {
	"pc" => return R_PC;
	"cpsr" or "psr" => return R_CPSR;
	"spsr" => return R_SPSR;
	* => return -1;
	}
}

cmdhelp()
{
	print("	e <addr> [<count>]  - examine memory\n");
	print("	d <addr> [<value>...]  - deposit values in memory\n");
	print("	get <file> <addr>  - read file into memory at addr\n");
	print("	load <file>  - load AIF file and set the PC\n");
	print("	r  - print all registers\n");
	print("	<reg>=<val>  - set register value\n");
	print("	sb  - run builtin sboot (pc=0x40; g)\n");
	print("	reset - trigger SA1100 software reset\n");
	print("	bps <speed>  - change bps rate (SA1100 only)\n");
	print("	q  - quit\n");
}

cmdmode()
{
	b := array[1024] of byte;
	for(;;) {
		print("rdp: ");
		r := sys->read(ifd, b, len b);
		if(r < 0)
			raise sprint("fail:%r");
		if(r == 0 || (r == 1 && b[0] == byte 4))
			break;
		n: int;
		a: list of string;
		(n, a) = sys->tokenize(string b[0:r], " \t\n=");
		if(n < 1)
			continue;
		case hd a {
		"sb" =>
			sbmode();
			rdi_execute();
		"q" or "quit" =>
			return;
		"r" or "reg" =>
			regdump();
		"get" or "getfile" or "l" or "load" =>
			{
				if((hd a)[0] == 'l')
					aifload(hd tl a, -1);
				else
					aifload(hd tl a, atoi(hd tl tl a));
			}exception e{
			"fail:*" =>
				print("error: %s\n", e[5:]);
				continue;
			}
		"g" or "go" =>
			rdi_execute();
		"reset" =>
			sa1100_reset();
		"e" =>
			a = tl a;
			x := atoi(hd a);
			n = 1;
			a = tl a;
			if(a != nil)
				n = atoi(hd a);
			examine(x, n);
		"d" =>
			a = tl a;
			x := atoi(hd a);
			for(i := 2; i<n; i++) {
				a = tl a;
				rdi_write(bint(atoi(hd a)), x, 4);
				x += 4;
			}
		"info" =>
			a = tl a;
			rdi_info(16r180, atoi(hd a));
		"bps" =>
			sa1100_setbps(atoi(hd tl a));
		"help" or "?" =>
			cmdhelp();
		* =>
			if((rn := regnum(hd a)) > -1) {
				reg := array[NREG] of int;
				reg[rn] = atoi(hd tl a);
				rdi_cpuwrite(reg, 1<<rn);
			} else
				print("?\n");
		}
	}
}

sbmode()
{
	if(debug)
		print("sbmode()\n");
	reg := array[NREG] of int;
	reg[R_PC] = 16r40;
	rdi_cpuwrite(reg, 1<<R_PC);
}

sbmodeofs(ofs: int)
{
	if(debug)
		print("sbmode(0x%ux)\n", ofs);
	reg := array[NREG] of int;
	reg[0] = ofs;
	reg[R_PC] = 16r48;
	rdi_cpuwrite(reg, (1<<0)|(1<<R_PC));
}

inp: string = "";

help: con "(q)uit, (i)nt, (b)reak, !c(r), !(l)ine, !(t)erminal, (s<bps>), (.)cont, (!cmd)\n";

menu(fi: ref Sys->FD)
{
	w := israw;
	if(israw)
		raw(0);
mloop:	for(;;) {
		out("");
		print("rdp> ");
		b := array[256] of byte;
		r := sys->read(fi, b, len b);
		case int b[0] {
		'q' =>
			killgrp();
			exit;
		'i' =>
			b[0] = byte 16r18;
			sys->write(dfd, b[0:1], 1);
			break mloop;
		'b' =>
			sys->write(cfd, array of byte "k", 1);
			break mloop;
		'!' =>
			cmd := string b[1:r-1];
			print("!%s\n", cmd);
			# system(cmd)
			print("!\n");
			break mloop;
		'l' =>
			w = !w;
			break mloop;
		'r' =>
			nocr = !nocr;
			break mloop;
		'd' =>
			debug = !debug;
			break mloop;
		't' =>
			sys->write(pifd, array[] of { byte 4 }, 1);
			sdc <-= (array of byte "rdp:tmode", -1);
			break mloop;
		'.' =>
			break mloop;
		's' =>
			bps := atoi(string b[1:r-1]);
			setbps(bps);
		* =>
			print(help);
			continue;
		}
	} 
	if(israw != w)
		raw(w);
}


input()
{
	fi := sys->fildes(0);
	b := array[1024] of byte;
iloop: 	for(;;) {
		r := sys->read(fi, b, len b);
		if(r < 0) {
			print("stdin: %r");
			killgrp();
			exit;
		}
		for(i:=0; i<r; i++) {
			if(b[i] == byte echar) {
				menu(fi);
				continue iloop;
			}
		}
		if(r == 0) {
			b[0] = byte 4;	# ctrl-d
			r = 1;
		}
		if(tmode)
			sys->write(dfd, b, r);
		else
			sys->write(pifd, b, r);
	}
}

ccfd: ref Sys->FD;
israw := 0;

raw(on: int)
{
	if(ccfd == nil) {
		ccfd = sys->open("/dev/consctl", Sys->OWRITE);
		if(ccfd == nil) { 
			print("/dev/consctl: %r\n");
			return;
		}
	}
	if(on)
		sys->fprint(ccfd, "rawon");
	else
		sys->fprint(ccfd, "rawoff");
	israw = on;
}

killgrp()
{
	pid := sys->pctl(0, nil);
	f := "/prog/"+string pid+"/ctl";
	fd := sys->open(f, Sys->OWRITE);
	if(fd == nil)
		print("%s: %r\n", f);
	else
		sys->fprint(fd, "killgrp");
}

kill(pid: int)
{
	f := "/prog/"+string pid+"/ctl";
	fd := sys->open(f, Sys->OWRITE);
	if(fd == nil)
		print("%s: %r\n", f);
	else
		sys->fprint(fd, "kill");
}


# Code for switching to previously unsupported bps rates:

##define UTCR1	0x4
##define UTCR2	0x8
##define UTCR3	0xc
##define UTDR	0x14
##define UTSR0	0x1c
##define UTSR1	0x20
#
#TEXT _startup(SB), $-4
#	MOVW	$0x80000000,R2
#	ORR	$0x00050000,R2
#
#	MOVW	$0, R1
#	MOVW	R1, UTDR(R2)	/* send ack */
#
#wait:
#	MOVW	UTSR1(R2), R1
#	TST	$1, R1		/* TBY */
#	BNE	wait
#
#	MOVW	$0x90000000,R3
#	ORR	$0x00000010,R3
#	MOVW	(R4),R1
#	ADD	$0x5a000,R1	/* 100 ms */
#delay1:
#	MOVW	(R3),R1
#	SUB.S	$0x5a000, R1	/* 100 ms */
#	BLO	delay1
# 
#	MOVW	UTCR3(R2), R5	/* save utcr3 */
#	MOVW	$0, R1
#	MOVW	R1, UTCR3(R2)	/* disable xmt/rcv */
#
#	MOVW	R0, R1
#	AND	$0xff, R1
#	MOVW	R1, UTCR2(R2)
#	MOVW	R0 >> 8, R1
#	MOVW	R1, UTCR1(R2)
#
#	MOVW	$0xff, R1
#	MOVW	R1, UTSR0(R2)	/* clear sticky bits */
#
#	MOVW	$3, R1
#	MOVW	R1, UTCR3(R2)	/* enable xmt/rcv */
#
#	MOVW	$0, R0
#sync:	
#	MOVW	R0, UTDR(R2)	/* send sync char */
#syncwait:
#	MOVW	UTSR1(R2), R1 
#	TST	$1, R1		/* TBY */
#	BNE	syncwait
#	TST	$2, R1		/* RNE */
#	BEQ	sync
#	MOVW	UTDR(R2), R0
#	MOVW	R0, UTDR(R2)	/* echo rcvd char */
#
#	MOVW	$0xff, R1
#	MOVW	R1, UTSR0(R2)	/* clear sticky bits */
#	MOVW	R5, UTCR3(R2)	/* re-enable xmt/rcv and interrupts */
#
#	WORD	$0xef000011	/* exit */


bpscode := array[] of {
	16re3a22102, 16re3822805, 16re3a11000, 16re5821014,
	16re5921020, 16re3110001, big 16r1afffffc, 16re3a33209,
	16re3833010, 16re5941000, 16re2811a5a, 16re5931000,
	16re2511a5a, big 16r3afffffc, 16re592500c, 16re3a11000,
	16re582100c, 16re1a11000, 16re20110ff, 16re5821008,
	16re1a11420, 16re5821004, 16re3a110ff, 16re582101c,
	16re3a11003, 16re582100c, 16re3a00000, 16re5820014,
	16re5921020, 16re3110001, big 16r1afffffc, 16re3110002,
	big 16r0afffff9, 16re5920014, 16re5820014, 16re3a110ff,
	16re582101c, 16re582500c, 16ref000011,
};

sa1100_setbps(bps: int)
{
	print("<sa1100_setbps %d>", bps);
	nb := len bpscode*4;
	b := array[nb] of byte;
	for(i := 0; i < len bpscode; i++) 
		b[i*4:] = bint(int bpscode[i]);
	rdi_write(b, 16r8080, nb);
	reg := array[NREG] of int;
	d := (3686400/(bps*16))-1;
	reg[0] = d;
	reg[R_PC] = 16r8080;
	rdi_cpuwrite(reg, (1<<0)|(1<<R_PC));
	sb := array[2] of byte;
	sb[0] = byte 16r10;
	sb[1] = byte 0;
	sys->write(dfd, sb, 2);
	rb := sreadn(1);
	setbps(bps);
	do rb = sreadn(1);
	while(rb[0] != byte 0);
	sb[0] = byte 16rff;
	sys->write(dfd, sb, 1);
	do rb = sreadn(1);
	while(rb[0] != sb[0]);
	getreply(0);
}

aifload(fname: string, adr: int)
{
	out("");
	if(adr < 0)
		print("<aifload %s>\n", fname);
	fd := sys->open(fname, Sys->OREAD);
	if(fd == nil) 
		raise sprint("fail:%s:%r", fname);
	d: Sys->Dir;
	(nil, d) = sys->fstat(fd);
	b := array[int d.length] of byte;
	sys->read(fd, b, len b);
	if(adr < 0) {
		if(len b < 128)
			raise sprint("fail:%s:not aif", fname);
		tsize := intb(b[20:24]);
		dsize := intb(b[24:28]);
		bsize := intb(b[32:36]);
		tbase := intb(b[40:44]);
		dbase := intb(b[52:56]);
		print("%ux/%ux: %ux+%ux+%ux\n", tbase, dbase, tsize, dsize, bsize);
		rdi_write(b, tbase, tsize+dsize);
		reg := array[NREG] of int;
		reg[R_PC] = tbase+8;
		rdi_cpuwrite(reg, 1<<R_PC);
	} else
		rdi_write(b, adr, int d.length);
}


init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;

	sys->pctl(Sys->NEWPGRP, nil);

	port := df_port;
	bps := df_bps;
	usecmdmode := 0;
	ofs := -1;
	prog: string = nil;

	argv = tl argv;
	while(argv != nil) {
		a := hd argv;
		argv = tl argv;
		if(len a >= 2 && a[0] == '-')
			case a[1] {
			'c' =>
				usecmdmode = 1;
			'O' =>
				ofs = atoi(a[2:]);
			'd' =>
				debug = 1;
			'p' =>
				port = a[2:];
			's' =>
				bps = atoi(a[2:]);
			'r' =>
				nocr = 1;
			'l' =>
				raw(1);
			'e' =>
				if(a[2] == '^')
					echar = a[3]&16r1f;
				else
					echar = a[2];
			't' =>
				tmode = 1;
			'h' =>
				print("usage: rdp [-crdlht] [-e<c>] [-O<ofs>] [-p<port>] [-s<bps>] [prog]\n");
				return;
			* =>
				print("invalid option: %s\n", a);
				return;
			}
		else
			prog = a;
	}

	print("rdp 0.17 (port=%s, bps=%d)\n", port, bps);
	dfd = sys->open(port, Sys->ORDWR);
	if(dfd == nil) {
		sys->print("open %s failed: %r\n", port);
		return;
	}
	cfd = sys->open(port+"ctl", Sys->OWRITE);
	if(cfd == nil) 
		sys->print("warning: open %s failed: %r\n", port+"ctl");

	pfd := array[2] of ref Sys->FD;
	sys->pipe(pfd);
	ifd = pfd[1];
	pifd = pfd[0];
	(scc, sdc) = (chan of int, chan of (array of byte, int));
	spawn serinp();
	spawn input();
	r := 1;
	{
		if(tmode)
			terminal();
		reset(r);
		if(!p_isopen) {
			rdi_open(bps);
			rdi_info(16r180, (1<<0)|(1<<1)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<8));
		}
		# print("\n<connection established>\n");
		print("\n<contact has been made>\n");
		if(usecmdmode) {
			cmdmode();
		} else {
			if(prog != nil)
				aifload(prog, -1); 
			else if(ofs != -1)
				sbmodeofs(ofs);
			else
				sbmode();
			reg := array[NREG] of int;
			# rdi_cpuread(reg, (1<<R_PC)|(1<<R_CPSR));
			# print("<execute at %ux; cpsr=%ux>\n", reg[R_PC], reg[R_CPSR]);
			rdi_cpuread(reg, (1<<R_PC));
			print("<execute at %ux>\n", reg[R_PC]);
			rdi_execute();
		}
		rdi_close();

		# Warning: this will make Linux emu crash...
		killgrp();
	}exception e{
	"fail:*" =>
		if(israw)
			raw(0);
		killgrp();
		raise e;
	"rdp:*" =>
		out("");
		if(debug)
			print("<exception: %s>\n", e);
		case e {
		"rdp:error" =>	;
		"rdp:tmode" =>
			tmode = !tmode;
			if(tmode)
				print("<terminal mode>\n");
			else
				print("<rdp mode>\n");
		"rdp:reset" =>
			r = 0;
		* =>
			r = 1;
		}
	}
}

