implement Tftp;

include "sys.m";
	sys: Sys;

include "tftp.m";

Maxretry: con 5;	# retries per block
Maxblock: con 512;	# protocol's usual maximum data block size
Tftphdrlen: con 4;
Read, Write, Data, Ack, Error: con 1+iota;	# tftp opcode

progress: int;

put2(buf: array of byte, o: int, val: int)
{
	buf[o] = byte (val >> 8);
	buf[o+1] = byte val;
}

get2(buf: array of byte, o: int): int
{
	return (int buf[o] << 8) | int buf[o+1];
}

kill(pid: int)
{
	fd := sys->open("#p/" + string pid + "/ctl", sys->OWRITE);
	if(fd == nil)
		return;

	msg := array of byte "kill";
	sys->write(fd, msg, len msg);
}

timeoutproc(c: chan of int, howlong: int)
{
	c <-= sys->pctl(0, nil);
	sys->sleep(howlong);
	c <-= 1;
}

tpid := -1;

timeoutcancel()
{
	if(tpid >= 0) {
		kill(tpid);
		tpid = -1;
	}
}

timeoutstart(howlong: int): chan of int
{
	timeoutcancel();
	tc := chan of int;
	spawn timeoutproc(tc, howlong);
	tpid = <-tc;
	return tc;
}

init(p: int)
{
	sys = load Sys Sys->PATH;
	progress = p;
}

reader(pidc: chan of int, fd: ref Sys->FD, bc: chan of array of byte)
{
	pid := sys->pctl(0, nil);
	pidc <-= pid;
	buf := array[Tftphdrlen + Maxblock] of byte;
	for(;;){
		n := sys->read(fd, buf, len buf);
		bc <-= buf[0 : n];
	}
}

receive(host: string, filename: string, fd: ref Sys->FD): string
{
	rbuf: array of byte;
	
	(ok, conn) := sys->dial("udp!" + host + "!69", nil);
	if(ok < 0) 
		return sys->sprint("can't dial %s: %r", host);
	buf := array[Tftphdrlen + Maxblock] of byte;
	i := 0;
	put2(buf, i, Read);
	i += 2;
	a := array of byte filename;
	buf[i:] = a;
	i += len a;
	buf[i++] = byte 0;
	mode := array of byte "binary";
	buf[i:] = mode;
	i += len mode;
	buf[i++] = byte 0;
	pidc := chan of int;
	bc := chan of array of byte;
	spawn reader(pidc, conn.dfd, bc);
	tftppid := <-pidc;
	lastblock := 0;
	for(;;) {
	  Retry:
		for(count := 0;; count++) {
			if(count >= Maxretry){
				kill(tftppid);
				return sys->sprint("tftp timeout");
			}

			# (re)send request/ack
			if(sys->write(conn.dfd, buf, i) < 0) {
				kill(tftppid);
				return sys->sprint( "error writing %s/data: %r", conn.dir);
			}
	
			# wait for next block
			mtc := timeoutstart(3000);
			for(;;){
				alt {
				<-mtc =>
					if(progress)
						sys->print("T");
					continue Retry;
				rbuf = <-bc =>
					if(len rbuf < Tftphdrlen)
						break;
					op := get2(rbuf, 0);
					case op {
					Data =>
						block := get2(rbuf, 2);
						if(block == lastblock + 1) {
							timeoutcancel();
							break Retry;
						}else if(progress)
							sys->print("S");
					Error =>
						timeoutcancel();
						kill(tftppid);
						return sys->sprint("server error %d: %s", get2(rbuf, 2), string rbuf[4:]);
					* =>
						timeoutcancel();
						kill(tftppid);
						return sys->sprint("phase error op=%d", op);
					}
				}
			}
		}
		n := len rbuf;
		# copy the data somewhere
		if(sys->write(fd, rbuf[Tftphdrlen:], n - Tftphdrlen) < 0) {
			kill(tftppid);
			return sys->sprint("writing destination: %r");
		}
		lastblock++;
		if(progress && lastblock % 25 == 0)
			sys->print(".");
		if(n < Maxblock + Tftphdrlen) {
			if(progress)
				sys->print("\n");
			break;
		}

		# send an ack
		put2(buf, 0, Ack);
		put2(buf, 2, lastblock);
	}
	kill(tftppid);
	return nil;
}
