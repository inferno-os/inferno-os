implement Filter;

include "sys.m";

include "filter.m";

End: con byte 8r300;
Esc: con byte 8r333;
Eend: con byte 8r334;	# encoded End byte
Eesc: con byte 8r335;	# encoded Esc byte

init()
{
}

start(param: string): chan of ref Rq
{
	req := chan of ref Rq;
	if(param == "encode")
		spawn encode(req);
	else
		spawn decode(req);
	return req;
}

encode(reqs: chan of ref Rq)
{
	sys := load Sys Sys->PATH;
	reqs <-= ref Rq.Start(sys->pctl(0, nil));
	buf := array[8192] of byte;
	rc := chan of int;
	do{
		reqs <-= ref Rq.Fill(buf, rc);
		if((n := <-rc) <= 0){
			if(n == 0)
				reqs <-= ref Rq.Finished(nil);
			break;
		}
		b := array[2*n + 2] of byte;	# optimise time not space
		o := 1;
		b[0] = End;
		for(i := 0; i < n; i++){
			if((c := buf[i]) == End || c == Esc){
				b[o++] = Esc;
				c = byte (Eend + (c& byte 1));
			}
			b[o++] = c;
		}
		b[o++] = End;
		if(o != len b)
			b = b[0:o];
		reqs <-= ref Rq.Result(b, rc);
	}while(<-rc != -1);
}

Slipesc, Slipend: con (1<<8) + iota;
Slipsize: con 1006;	# rfc's suggestion

slipin(c: byte, esc: int): int
{
	if(esc == Slipesc){	# last byte was Esc
		if(c == Eend)
			c = End;
		else if(c == Eesc)
			c = Esc;
	}else{
		if(c == Esc)
			return Slipesc;
		if(c == End)
			return Slipend;
	}
	return int c;
}

decode(reqs: chan of ref Rq)
{
	sys := load Sys Sys->PATH;
	reqs <-= ref Rq.Start(sys->pctl(0, nil));
	buf := array[8192] of byte;
	b := array[Slipsize] of byte;
	rc := chan of int;
	c := 0;
	o := 0;
	for(;;){
		reqs <-= ref Rq.Fill(buf, rc);
		if((n := <-rc) <= 0){
			if(n < 0)
				exit;
			break;
		}
		for(i := 0; i < n; i++){
			c = slipin(buf[i], c);
			if(c == Slipend){
				if(o != 0){
					reqs <-= ref Rq.Result(b[0:o], rc);
					if(<-rc == -1)
						exit;
					b = array[Slipsize] of byte;
					o = 0;
				}
			}else if(c != Slipesc){
				if(o >= len b){
					t := array[3*len b/2] of byte;
					t[0:] = b;
					b = t;
				}
				b[o++] = byte c;
			}
		}
	}
	# partial block discarded
	reqs <-= ref Rq.Finished(nil);
}
