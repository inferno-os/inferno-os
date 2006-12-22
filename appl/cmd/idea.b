implement Idea;

#
# Copyright © 2002 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "keyring.m";
	keyring: Keyring;

Idea: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

decerr(s: string)
{
	sys->fprint(sys->fildes(2), "decrypt error: %s (wrong password ?)\n", s);
	exit;
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stdin := sys->fildes(0);
	stdout := sys->fildes(1);

	bufio = load Bufio Bufio->PATH;
	keyring = load Keyring Keyring->PATH;

	obuf := array[8] of byte;
	buf := array[8] of byte;
	key := array[16] of byte;

	argc := len argv;
	if((argc != 3 && argc != 4) || (hd tl argv != "-e" && hd tl argv != "-d") || len hd tl tl argv != 16){
		sys->fprint(sys->fildes(2), "usage: idea -[e | d] <16 char key> [inputfile]\n");
		exit;
	}
	dec := hd tl argv == "-d";
	if(argc == 4){
		s := hd tl tl tl argv;
		stdin = sys->open(s, Sys->OREAD);
		if(stdin == nil){
			sys->fprint(sys->fildes(2), "cannot open %s\n", s);
			exit;
		}
		if(dec){
			l := len s;
			if(s[l-3: l] != ".id"){
				sys->fprint(sys->fildes(2), "input file not a .id file\n");
				exit;
			}
			s = s[0: l-3];
		}
		else
			s += ".id";
		stdout = sys->create(s, Sys->OWRITE, 8r666);
		if(stdout == nil){
			sys->fprint(sys->fildes(2), "cannot create %s\n", s);
			exit;
		}
	}
	for(i := 0; i < 16; i++)
		key[i] = byte (hd tl tl argv)[i];
	is := keyring->ideasetup(key, nil);
	m := om := 0;
	bin := bufio->fopen(stdin, Bufio->OREAD);
	bout := bufio->fopen(stdout, Bufio->OWRITE);
	for(;;){
		n := bin.read(buf[m: ], 8-m);
		if(n <= 0)
			break;
		m += n;
		if(m == 8){
			keyring->ideaecb(is, buf, 8, dec);
			if(dec){	# leave last block around
				if(om > 0)
					bout.write(obuf, 8);
				obuf[0: ] = buf[0: 8];
				om = 8;
			}
			else
				bout.write(buf, 8);
			m = 0;
		}
	}
	if(dec){
		if(om != 8)
			decerr("no last block");
		if(m != 0)
			decerr("last block not 8 bytes long");
		m = int obuf[7];
		if(m < 0 || m > 7)
			decerr("bad modulus");
		for(i = m; i < 8-1; i++)
			if(obuf[i] != byte 0)
				decerr("byte not 0");
		bout.write(obuf, m);
	}
	else{
		for(i = m; i < 8; i++)
			buf[i] = byte 0;
		buf[7] = byte m;
		keyring->ideaecb(is, buf, 8, dec);
		bout.write(buf, 8);
	}
	bout.flush();
	bin.close();
	bout.close();
}	
