RAWON_STR := "*";

RAWON : con 0;
RAWOFF : con 1;

promptstring(prompt, def: string, mode: int): string
{
	if(mode == RAWON || def == nil || def == "")
		sys->fprint(stdout, "%s: ", prompt);
	else
		sys->fprint(stdout, "%s [%s]: ", prompt, def);
	(eof, resp) := readline(stdin, mode);
	if(eof)
		exit;
	if(resp == "")
		resp = def;
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
