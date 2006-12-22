implement Netkey;

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	keyring: Keyring;

Netkey: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

ANAMELEN: con 28;
DESKEYLEN: con 7;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;

	if(len args > 1){
		sys->fprint(sys->fildes(2), "usage: netkey\n");
		raise "fail:usage";
	}
	(pw, err) := readconsline("Password: ", 1);
	if(err != nil){
		sys->fprint(sys->fildes(2), "netkey: %s\n", err);
		raise "fail:error";
	}
	if(pw != nil)
		while((chal := readconsline("challenge: ", 0).t0) != nil)
			sys->print("response: %s\n", netcrypt(passtokey(pw), string int chal));
}

readconsline(prompt: string, raw: int): (string, string)
{
	fd := sys->open("/dev/cons", Sys->ORDWR);
	if(fd == nil)
		return (nil, sys->sprint("can't open cons: %r"));
	sys->fprint(fd, "%s", prompt);
	fdctl: ref Sys->FD;
	if(raw){
		fdctl = sys->open("/dev/consctl", sys->OWRITE);
		if(fdctl == nil || sys->fprint(fdctl, "rawon") < 0)
			return (nil, sys->sprint("can't open consctl: %r"));
	}
	line := array[256] of byte;
	o := 0;
	err: string;
	buf := array[1] of byte;
  Read:
	while((r := sys->read(fd, buf, len buf)) > 0){
		c := int buf[0];
		case c {
		16r7F =>
			err = "interrupt";
			break Read;
		'\b' =>
			if(o > 0)
				o--;
		'\n' or '\r' or 16r4 =>
			break Read;
		* =>
			if(o > len line){
				err = "line too long";
				break Read;
			}
			line[o++] = byte c;
		}
	}
	if(r < 0)
		err = sys->sprint("can't read cons: %r");
	if(raw){
		sys->fprint(fdctl, "rawoff");
		sys->fprint(fd, "\n");
	}
	if(err != nil)
		return (nil, err);
	return (string line[0:o], err);
}

#
# duplicates auth9 but keeps this self-contained
#

netcrypt(key: array of byte, chal: string): string
{
	buf := array[8] of {* => byte 0};
	a := array of byte chal;
	if(len a > 7)
		a = a[0:7];
	buf[0:] = a;
	encrypt(key, buf, len buf);
	return sys->sprint("%.2ux%.2ux%.2ux%.2ux", int buf[0], int buf[1], int buf[2], int buf[3]);
}

passtokey(p: string): array of byte
{
	a := array of byte p;
	n := len a;
	if(n >= ANAMELEN)
		n = ANAMELEN-1;
	buf := array[ANAMELEN] of {* => byte ' '};
	buf[0:] = a[0:n];
	buf[n] = byte 0;
	key := array[DESKEYLEN] of {* => byte 0};
	t := 0;
	for(;;){
		for(i := 0; i < DESKEYLEN; i++)
			key[i] = byte ((int buf[t+i] >> i) + (int buf[t+i+1] << (8 - (i+1))));
		if(n <= 8)
			return key;
		n -= 8;
		t += 8;
		if(n < 8){
			t -= 8 - n;
			n = 8;
		}
		encrypt(key, buf[t:], 8);
	}
}

parity := array[] of {
	byte 16r01, byte 16r02, byte 16r04, byte 16r07, byte 16r08, byte 16r0b, byte 16r0d, byte 16r0e, 
	byte 16r10, byte 16r13, byte 16r15, byte 16r16, byte 16r19, byte 16r1a, byte 16r1c, byte 16r1f, 
	byte 16r20, byte 16r23, byte 16r25, byte 16r26, byte 16r29, byte 16r2a, byte 16r2c, byte 16r2f, 
	byte 16r31, byte 16r32, byte 16r34, byte 16r37, byte 16r38, byte 16r3b, byte 16r3d, byte 16r3e, 
	byte 16r40, byte 16r43, byte 16r45, byte 16r46, byte 16r49, byte 16r4a, byte 16r4c, byte 16r4f, 
	byte 16r51, byte 16r52, byte 16r54, byte 16r57, byte 16r58, byte 16r5b, byte 16r5d, byte 16r5e, 
	byte 16r61, byte 16r62, byte 16r64, byte 16r67, byte 16r68, byte 16r6b, byte 16r6d, byte 16r6e, 
	byte 16r70, byte 16r73, byte 16r75, byte 16r76, byte 16r79, byte 16r7a, byte 16r7c, byte 16r7f, 
	byte 16r80, byte 16r83, byte 16r85, byte 16r86, byte 16r89, byte 16r8a, byte 16r8c, byte 16r8f, 
	byte 16r91, byte 16r92, byte 16r94, byte 16r97, byte 16r98, byte 16r9b, byte 16r9d, byte 16r9e, 
	byte 16ra1, byte 16ra2, byte 16ra4, byte 16ra7, byte 16ra8, byte 16rab, byte 16rad, byte 16rae, 
	byte 16rb0, byte 16rb3, byte 16rb5, byte 16rb6, byte 16rb9, byte 16rba, byte 16rbc, byte 16rbf, 
	byte 16rc1, byte 16rc2, byte 16rc4, byte 16rc7, byte 16rc8, byte 16rcb, byte 16rcd, byte 16rce, 
	byte 16rd0, byte 16rd3, byte 16rd5, byte 16rd6, byte 16rd9, byte 16rda, byte 16rdc, byte 16rdf, 
	byte 16re0, byte 16re3, byte 16re5, byte 16re6, byte 16re9, byte 16rea, byte 16rec, byte 16ref, 
	byte 16rf1, byte 16rf2, byte 16rf4, byte 16rf7, byte 16rf8, byte 16rfb, byte 16rfd, byte 16rfe,
};

des56to64(k56: array of byte): array of byte
{
	k64 := array[8] of byte;
	hi := (int k56[0]<<24)|(int k56[1]<<16)|(int k56[2]<<8)|int k56[3];
	lo := (int k56[4]<<24)|(int k56[5]<<16)|(int k56[6]<<8);

	k64[0] = parity[(hi>>25)&16r7f];
	k64[1] = parity[(hi>>18)&16r7f];
	k64[2] = parity[(hi>>11)&16r7f];
	k64[3] = parity[(hi>>4)&16r7f];
	k64[4] = parity[((hi<<3)|int ((big lo & big 16rFFFFFFFF)>>29))&16r7f];	# watch the sign extension
	k64[5] = parity[(lo>>22)&16r7f];
	k64[6] = parity[(lo>>15)&16r7f];
	k64[7] = parity[(lo>>8)&16r7f];
	return k64;
}

encrypt(key: array of byte, data: array of byte, n: int)
{
	ds := keyring->dessetup(des56to64(key), nil);
	keyring->desecb(ds, data, n, Keyring->Encrypt);
}
