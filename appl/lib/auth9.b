implement Auth9;

#
# elements of Plan 9 authentication
#
# this is a near transliteration of Plan 9 source, subject to the Lucent Public License 1.02
#

include "sys.m";
	sys: Sys;

include "keyring.m";

include "auth9.m";

debug := 0;

init()
{
	sys = load Sys Sys->PATH;
}

setdebug(i: int)
{
	debug = i;
}

put2(a: array of byte, v: int)
{
	a[0] = byte v;
	a[1] = byte (v>>8);
}

get2(a: array of byte): int
{
	return (int a[1]<<8) | int a[0];
}

put4(a: array of byte, v: int)
{
	a[0] = byte v;
	a[1] = byte (v>>8);
	a[2] = byte (v>>16);
	a[3] = byte (v>>24);
}

get4(a: array of byte): int
{
	return (int a[3]<<24) | (int a[2]<<16) | (int a[1]<<8) | int a[0];
}

puts(a: array of byte, s: string, n: int)
{
	b := array of byte s;
	l := len b;
	if(l > n)
		b = b[0:n];
	a[0:] = b;
	for(; l < n; l++)
		a[l] = byte 0;
}

gets(a: array of byte, n: int): string
{
	for(i:=0; i<n; i++)
		if(a[i] == byte 0)
			break;
	return string a[0:i];
}

geta(a: array of byte, n: int): array of byte
{
	b := array[n] of byte;
	b[0:] = a[0:n];
	return b;
}

Authenticator.pack(f: self ref Authenticator, key: array of byte): array of byte
{
	p := array[AUTHENTLEN] of {* => byte 0};
	p[0] = byte f.num;
	p[1:] = f.chal;
	put4(p[1+CHALLEN:], f.id);
	if(key != nil)
		encrypt(key, p, len p);
	return p;
}

Authenticator.unpack(a: array of byte, key: array of byte): (int, ref Authenticator)
{
	if(key != nil)
		decrypt(key, a, AUTHENTLEN);
	f := ref Authenticator;
	f.num = int a[0];
	f.chal = geta(a[1:], CHALLEN);
	f.id = get4(a[1+CHALLEN:]);
	return (AUTHENTLEN, f);
}

Passwordreq.pack(f: self ref Passwordreq, key: array of byte): array of byte
{
	a := array[PASSREQLEN] of {* => byte 0};
	a[0] = byte f.num;
	a[1:] = f.old;
	a[1+ANAMELEN:] = f.new;
	a[1+2*ANAMELEN] = byte f.changesecret;
	a[1+2*ANAMELEN+1:] = f.secret;
	if(key != nil)
		encrypt(key, a, len a);
	return a;
}

Passwordreq.unpack(a: array of byte, key: array of byte): (int, ref Passwordreq)
{
	if(key != nil)
		decrypt(key, a, PASSREQLEN);
	f := ref Passwordreq;
	f.num = int a[0];
	f.old = geta(a[1:], ANAMELEN);
	f.old[ANAMELEN-1] = byte 0;
	f.new = geta(a[1+ANAMELEN:], ANAMELEN);
	f.new[ANAMELEN-1] = byte 0;
	f.changesecret = int a[1+2*ANAMELEN];
	f.secret = geta(a[1+2*ANAMELEN+1:], SECRETLEN);
	f.secret[SECRETLEN-1] = byte 0;
	return (PASSREQLEN, f);
}

Ticket.pack(f: self ref Ticket, key: array of byte): array of byte
{
	a := array[TICKETLEN] of {* => byte 0};
	a[0] = byte f.num;
	a[1:] = f.chal;
	puts(a[1+CHALLEN:], f.cuid, ANAMELEN);
	puts(a[1+CHALLEN+ANAMELEN:], f.suid, ANAMELEN);
	a[1+CHALLEN+2*ANAMELEN:] = f.key;
	if(key != nil)
		encrypt(key, a, len a);
	return a;
}

Ticket.unpack(a: array of byte, key: array of byte): (int, ref Ticket)
{
	if(key != nil)
		decrypt(key, a, TICKETLEN);
	f := ref Ticket;
	f.num = int a[0];
	f.chal = geta(a[1:], CHALLEN);
	f.cuid = gets(a[1+CHALLEN:], ANAMELEN);
	f.suid = gets(a[1+CHALLEN+ANAMELEN:], ANAMELEN);
	f.key = geta(a[1+CHALLEN+2*ANAMELEN:], DESKEYLEN);
	return (TICKETLEN, f);
}

Ticketreq.unpack(a: array of byte): (int, ref Ticketreq)
{
	f := ref Ticketreq;
	f.rtype = int a[0];
	f.authid = gets(a[1:], ANAMELEN);
	f.authdom = gets(a[1+ANAMELEN:], DOMLEN);
	f.chal = geta(a[1+ANAMELEN+DOMLEN:], CHALLEN);
	f.hostid = gets(a[1+ANAMELEN+DOMLEN+CHALLEN:], ANAMELEN);
	f.uid = gets(a[1+ANAMELEN+DOMLEN+CHALLEN+ANAMELEN:], ANAMELEN);
	return (TICKREQLEN, f);
}

Ticketreq.pack(f: self ref Ticketreq): array of byte
{
	a := array[TICKREQLEN] of {* => byte 0};
	a[0] = byte f.rtype;
	puts(a[1:], f.authid, ANAMELEN);
	puts(a[1+ANAMELEN:], f.authdom, DOMLEN);
	a[1+ANAMELEN+DOMLEN:] = f.chal;
	puts(a[1+ANAMELEN+DOMLEN+CHALLEN:], f.hostid, ANAMELEN);
	puts(a[1+ANAMELEN+DOMLEN+CHALLEN+ANAMELEN:], f.uid, ANAMELEN);
	return a;
}

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
	if(n < 8)
		return;
	kr := load Keyring Keyring->PATH;
	ds := kr->dessetup(des56to64(key), nil);
	n--;
	r := n % 7;
	n /= 7;
	j := 0;
	for(i := 0; i < n; i++){
		kr->desecb(ds, data[j:], 8, Keyring->Encrypt);
		j += 7;
	}
	if(r)
		kr->desecb(ds, data[j-7+r:], 8, Keyring->Encrypt);
}

decrypt(key: array of byte, data: array of byte, n: int)
{
	if(n < 8)
		return;
	kr := load Keyring Keyring->PATH;
	ds := kr->dessetup(des56to64(key), nil);
	n--;
	r := n % 7;
	n /= 7;
	j := n*7;
	if(r)
		kr->desecb(ds, data[j-7+r:], 8, Keyring->Decrypt);
	for(i := 0; i < n; i++){
		j -= 7;
		kr->desecb(ds, data[j:], 8, Keyring->Decrypt);
	}
}

readn(fd: ref Sys->FD, nb: int): array of byte
{
	buf:= array[nb] of byte;
	if(sys->readn(fd, buf, nb) != nb)
		return nil;
	return buf;
}

pbmsg: con "AS protocol botch";

_asgetticket(fd: ref Sys->FD, tr: ref Ticketreq, key: array of byte): (ref Ticket, array of byte)
{
	a := tr.pack();
	if(sys->write(fd, a, len a) < 0){
		sys->werrstr(pbmsg);
		return (nil, nil);
	}
	a = _asrdresp(fd, 2*TICKETLEN);
	if(a == nil)
		return (nil, nil);
	(nil, t) := Ticket.unpack(a, key);
	return (t, a[TICKETLEN:]);	# can't unpack both since the second uses server key
}

_asrdresp(fd: ref Sys->FD, n: int): array of byte
{
	b := array[1] of byte;
	if(sys->read(fd, b, 1) != 1){
		sys->werrstr(pbmsg);
		return nil;
	}

	buf: array of byte;
	case int b[0] {
	AuthOK =>
		buf = readn(fd, n);
	AuthOKvar =>
		b = readn(fd, 5);
		if(b == nil)
			break;
		n = int string b;
		if(n<= 0 || n > 4096)
			break;
		buf = readn(fd, n);
	AuthErr =>
		b = readn(fd, 64);
		if(b == nil)
			break;
		for(i:=0; i<len b && b[i] != byte 0; i++)
			;
		sys->werrstr(sys->sprint("remote: %s", string b[0:i]));
		return nil;
	* =>
		sys->werrstr(sys->sprint("%s: resp %d", pbmsg, int b[0]));
		return nil;
	}
	if(buf == nil)
		sys->werrstr(pbmsg);
	return buf;
}
