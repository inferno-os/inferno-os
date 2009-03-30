# promptstring

RAWON_STR := "*";

RAWON : con 0;
RAWOFF : con 1;

promptstring(prompt, def: string, mode: int): string
{
	if(mode == RAWON || def == nil)
		sys->fprint(stdout, "%s: ", prompt);
	else
		sys->fprint(stdout, "%s [%s]: ", prompt, def);
	(eof, resp) := readline(stdin, mode);
	if(eof)
		exit;
	if(resp == nil)
		return def;
	return resp;
}

readline(fd: ref Sys->FD, mode: int): (int, string)
{
	i: int;
	eof: int;
	fdctl: ref Sys->FD;

	eof = 0;
	buf := array[128] of byte;
	tmp := array[128] of byte;
	
	if(mode == RAWON){
		fdctl = sys->open("/dev/consctl", sys->OWRITE);
		if(fdctl == nil || sys->write(fdctl,array of byte "rawon",5) != 5){
			sys->fprint(stderr, "unable to change console mode");
			return (1,nil);
		}
	}

	for(sofar := 0; sofar < 128; sofar += i){
		i = sys->read(fd, tmp, 128 - sofar);
		if(i <= 0){
			eof = 1;
			break;
		}
		if(tmp[i-1] == byte '\n'){
			for(j := 0; j < i-1; j++){
				buf[sofar+j] = tmp[j];
				if(mode == RAWON && RAWON_STR != nil)
				   sys->write(stdout,array of byte RAWON_STR,1);
			}
			sofar += j;
			if(mode == RAWON)
				sys->write(stdout,array of byte "\n",1);
			break;
		}
		else {
			for(j := 0; j < i; j++){
				buf[sofar+j] = tmp[j];
				if(mode == RAWON && RAWON_STR != nil)
				   sys->write(stdout,array of byte RAWON_STR,1);
			}
		}		
	}
	if(mode == RAWON)
		sys->write(fdctl,array of byte "rawoff",6);
	return (eof, string buf[0:sofar]);
}

# from keyfs

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
	sys->fprint(fd, "\n");
	if(r < 0)
		err = sys->sprint("can't read cons: %r");
	if(raw)
		sys->fprint(fdctl, "rawoff");
	if(err != nil)
		return (nil, err);
	return (string line[0:o], err);
}
