implement Pcmcia;

#
# Copyright © 1995-2001 Lucent Technologies Inc.  All rights reserved.
# Revisions Copyright © 2001-2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
	print, fprint: import sys;

include "draw.m";

Pcmcia: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

End:	con 16rFF;

fd: ref Sys->FD;
stderr: ref Sys->FD;
pos := 0;

hex := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	if(args != nil)
		args = tl args;
	if(args != nil && hd args == "-x"){
		hex = 1;
		args = tl args;
	}

	file := "#y/pcm0attr";
	if(args != nil)
		file = hd args;

	fd = sys->open(file, Sys->OREAD);
	if(fd == nil)
		fatal(sys->sprint("can't open %s: %r", file));

	for(next := 0; next >= 0;)
		next = dtuple(next);
}

fatal(s: string)
{
	fprint(stderr, "pcmcia: %s\n", s);
	raise "fail:error";
}

readc(): int
{
	x := array[1] of byte;
	sys->seek(fd, big(2*pos), 0);
	pos++;
	rv := sys->read(fd, x, 1);
	if(rv != 1){
		if(rv < 0)
			sys->print("readc err: %r\n");
		return -1;
	}
	v := int x[0];
	if(hex)
		print("%2.2ux ", v);
	return v;
}

dtuple(next: int): int
{
	pos = next;
	if((ttype := readc()) < 0)
		return -1;
	if(ttype == End)
		return -1;
	if((link := readc()) < 0)
		return -1;
	case ttype {
	* =>	print("unknown tuple type #%2.2ux\n", ttype);
	16r01 =>	tdevice(ttype, link);
	16r15 =>	tvers1(ttype, link);
	16r17 =>	tdevice(ttype, link);
	16r1A =>	tcfig(ttype, link);
	16r1B =>	tentry(ttype, link);
	}
	if(link == End)
		next = -1;
	else
		next = next+2+link;
	return next;
}

speedtab := array[16] of {
0 => 0,
1 =>	250,
2 =>	200,
3 =>	150,
4 =>	100,
};

mantissa := array[16] of {
1 =>	10,
2 =>	12,
3 =>	13,
4 =>	15,
5 =>	20,
6 =>	25,
7 =>	30,
8 =>	35,
9 =>	40,
10=>	45,
11=>	50,
12=>	55,
13=>	60,
14=>	70,
15=>	80,
};

exponent := array[] of {
	1,
	10,
	100,
	1000,
	10000,
	100000,
	1000000,
	10000000,
};

typetab := array [256] of {
1=>	"Masked ROM",
2=>	"PROM",
3=>	"EPROM",
4=>	"EEPROM",
5=>	"FLASH",
6=>	"SRAM",
7=>	"DRAM",
16rD=>	"IO+MEM",
* => "Unknown",
};

getlong(size: int): int
{
	x := 0;
	for(i := 0; i < size; i++){
		if((c := readc()) < 0)
			break;
		x |= c<<(i*8);
	}
	return x;
}

tdevice(dtype: int, tlen: int)
{
	while(tlen > 0){
		if((id := readc()) < 0)
			return;
		tlen--;
		if(id == End)
			return;

		speed := id & 16r7;
		ns := 0;
		if(speed == 16r7){
			if((speed = readc()) < 0)
				return;
			tlen--;
			if(speed & 16r80){
				if((aespeed := readc()) < 0)
					return;
				ns = 0;
			} else
				ns = (mantissa[(speed>>3)&16rF]*exponent[speed&7])/10;
		} else
			ns = speedtab[speed];

		ttype := id>>4;
		if(ttype == 16rE){
			if((ttype = readc()) < 0)
				return;
			tlen--;
		}
		tname := typetab[ttype];
		if(tname == nil)
			tname = "unknown";

		if((size := readc()) < 0)
			return;
		tlen--;
		bytes := ((size>>3)+1) * 512 * (1<<(2*(size&16r7)));

		ttname := "attr device";
		if(dtype == 1)
			ttname = "device";
		print("%s %d bytes of %dns %s\n", ttname, bytes, ns, tname);
	}
}

tvers1(nil: int, tlen: int)
{
	if((major := readc()) < 0)
		return;
	tlen--;
	if((minor := readc()) < 0)
		return;
	tlen--;
	print("version %d.%d\n", major, minor);
	while(tlen > 0){
		s := "";
		while(tlen > 0){
			if((c := readc()) < 0)
				return;
			tlen--;
			if(c == 0)
				break;
			if(c == End){
				if(s != "")
					print("\t%s<missing null>\n", s);
				return;
			}
			s[len s] = c;
		}
		print("\t%s\n", s);
	}
}

tcfig(nil: int, nil: int)
{
	if((size := readc()) < 0)
		return;
	rasize := (size&16r3) + 1;
	rmsize := ((size>>2)&16rf) + 1;
	if((last := readc()) < 0)
		return;
	caddr := getlong(rasize);
	cregs := getlong(rmsize);

	print("configuration registers at");
	for(i := 0; i < 16; i++)
		if((1<<i) & cregs)
			print(" (%d) #%ux", i, caddr + i*2);
	print("\n");
}

intrname := array[16] of {
0 =>	"memory",
1 =>	"I/O",
4 =>	"Custom 0",
5 =>	"Custom 1",
6 =>	"Custom 2",
7 =>	"Custom 3",
* =>	"unknown"
};

vexp := array[8] of {
	1, 10, 100, 1000, 10000, 100000, 1000000, 10000000
};
vmant := array[16] of {
	10, 12, 13, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 70, 80, 90,
};

volt(name: string)
{
	if((c := readc()) < 0)
		return;
	exp := vexp[c&16r7];
	microv := vmant[(c>>3)&16rf]*exp;
	while(c & 16r80){
		if((c = readc()) < 0)
			return;
		case c {
		16r7d =>
			break;		# high impedence when sleeping
		16r7e or 16r7f =>
			microv = 0;	# no connection
		* =>
			exp /= 10;
			microv += exp*(c&16r7f);
		}
	}
	print(" V%s %duV", name, microv);
}

amps(name: string)
{
	if((c := readc()) < 0)
		return;
	amps := vexp[c&16r7]*vmant[(c>>3)&16rf];
	while(c & 16r80){
		if((c = readc()) < 0)
			return;
		if(c == 16r7d || c == 16r7e || c == 16r7f)
			amps = 0;
	}
	if(amps >= 1000000)
		print(" I%s %dmA", name, amps/100000);
	else if(amps >= 1000)
		print(" I%s %duA", name, amps/100);
	else
		print(" I%s %dnA", name, amps*10);
}

power(name: string)
{
	print("\t%s: ", name);
	if((feature := readc()) < 0)
		return;
	if(feature & 1)
		volt("nominal");
	if(feature & 2)
		volt("min");
	if(feature & 4)
		volt("max");
	if(feature & 8)
		amps("static");
	if(feature & 16r10)
		amps("avg");
	if(feature & 16r20)
		amps("peak");
	if(feature & 16r40)
		amps("powerdown");
	print("\n");
}

ttiming(name: string, scale: int)
{
	if((unscaled := readc()) < 0)
		return;
	scaled := (mantissa[(unscaled>>3)&16rf]*exponent[unscaled&7])/10;
	scaled = scaled * vexp[scale];
	print("\t%s %dns\n", name, scaled);
}

timing()
{
	if((c := readc()) < 0)
		return;
	i := c&16r3;
	if(i != 3)
		ttiming("max wait", i);
	i = (c>>2)&16r7;
	if(i != 7)
		ttiming("max ready/busy wait", i);
	i = (c>>5)&16r7;
	if(i != 7)
		ttiming("reserved wait", i);
}

range(asize: int, lsize: int)
{
	address := getlong(asize);
	alen := getlong(lsize);
	print("\t\t%ux - %ux\n", address, address+alen);
}

ioaccess := array[] of {
	0 => " no access",
	1 => " 8bit access only",
	2 => " 8bit or 16bit access",
	3 => " selectable 8bit or 8&16bit access",
};

iospace(c: int): int
{
	print("\tIO space %d address lines%s\n", c&16r1f, ioaccess[(c>>5)&3]);
	if((c & 16r80) == 0)
		return -1;

	if((c = readc()) < 0)
		return -1;

	for(i := (c&16rf)+1; i; i--)
		range((c>>4)&16r3, (c>>6)&16r3);
	return 0;
}

iospaces()
{
	if((c := readc()) < 0)
		return;
	iospace(c);
}

irq()
{
	if((c := readc()) < 0)
		return;
	irqs: int;
	if(c & 16r10){
		if((irq1 := readc()) < 0)
			return;
		if((irq2 := readc()) < 0)
			return;
		irqs = irq1|(irq2<<8);
	} else
		irqs = 1<<(c&16rf);
	level := "";
	if(c & 16r20)
		level = " level";
	pulse := "";
	if(c & 16r40)
		pulse = " pulse";
	shared := "";
	if(c & 16r80)
		shared = " shared";
	print("\tinterrupts%s%s%s", level, pulse, shared);
	for(i := 0; i < 16; i++)
		if(irqs & (1<<i))
			print(", %d", i);
	print("\n");
}

memspace(asize: int, lsize: int, host: int)
{
	alen := getlong(lsize)*256;
	address := getlong(asize)*256;
	if(host){
		haddress := getlong(asize)*256;
		print("\tmemory address range #%ux - #%ux hostaddr #%ux\n",
			address, address+alen, haddress);
	} else
		print("\tmemory address range #%ux - #%ux\n", address, address+alen);
}

misc()
{
}

tentry(nil: int, nil: int)
{
	if((c := readc()) < 0)
		return;
	def := "";
	if(c & 16r40)
		def = " (default)";
	print("configuration %d%s\n", c&16r3f, def);
	if(c & 16r80){
		if((i := readc()) < 0)
			return;
		tname := intrname[i & 16rf];
		if(tname == "")
			tname = sys->sprint("type %d", i & 16rf);
		attrib := "";
		if(i & 16r10)
			attrib += " Battery status active";
		if(i & 16r20)
			attrib += " Write Protect active";
		if(i & 16r40)
			attrib += " Ready/Busy active";
		if(i & 16r80)
			attrib += " Memory Wait required";
		print("\t%s device, %s\n", tname, attrib);
	}
	if((feature := readc()) < 0)
		return;
	case feature&16r3 {
	1 =>
		power("Vcc");
	2 =>
		power("Vcc");
		power("Vpp");
	3 =>
		power("Vcc");
		power("Vpp1");
		power("Vpp2");
	}
	if(feature&16r4)
		timing();
	if(feature&16r8)
		iospaces();
	if(feature&16r10)
		irq();
	case (feature>>5)&16r3 {
	1 =>
		memspace(0, 2, 0);
	2 =>
		memspace(2, 2, 0);
	3 =>
		if((c = readc()) < 0)
			return;
		for(i := 0; i <= (c&16r7); i++)
			memspace((c>>5)&16r3, (c>>3)&16r3, c&16r80);
		break;
	}
	if(feature&16r80)
		misc();
}
