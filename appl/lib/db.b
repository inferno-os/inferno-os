implement DB;

include "sys.m";
	sys: Sys;

include "dial.m";

include "keyring.m";

include "security.m";

include "db.m";

RES_HEADER_SIZE: con 22;

open(addr, username, password, dbname: string): (ref DB_Handle, list of string)
{
	(fd, err) := connect(addr, "none");
	if(nil == fd)
		return (nil, err :: nil);
	return dbopen(fd, username, password, dbname);
}

connect(addr: string, alg: string): (ref Sys->FD, string)
{
	if (sys == nil)
		sys = load Sys Sys->PATH;

	dial := load Dial Dial->PATH;
	if(dial == nil)
		return (nil, sys->sprint("load %s: %r", Dial->PATH));

	addr = dial->netmkaddr(addr, "net", "6669");	# infdb

	conn := dial->dial(addr, nil);
	if(conn == nil)
		return (nil, sys->sprint("can't dial %s: %r", addr));

	(n, addrparts) := sys->tokenize(addr, "!");
	if(n >= 2)
		addr = hd addrparts + "!" + hd tl addrparts;	# ignore service for key search

	kr := load Keyring Keyring->PATH;

	user := user();
	kd := "/usr/" + user + "/keyring/";
	cert := kd + addr;
	if(sys->stat(cert).t0 < 0)
		cert = kd + "default";

	ai := kr->readauthinfo(cert);

	#
	# let auth->client handle nil ai
	# if(ai == nil){
	#	return (nil, sys->sprint("DB init: certificate for %s not found, use getauthinfo first", addr));
	# }
	#

	au := load Auth Auth->PATH;
	if(au == nil)
		return (nil, sys->sprint("DB init: can't load module Auth %r"));

	err := au->init();
	if(err != nil)
		return (nil, sys->sprint("DB init: can't initialize module Auth: %s", err));

	fd: ref Sys->FD;

	(fd, err) = au->client(alg, ai, conn.dfd);
	if(fd == nil)
		return (nil, sys->sprint("DB init: authentication failed: %s", err));

	return (fd, nil);
}

dbopen(fd: ref Sys->FD, username, password, dbname: string): (ref DB_Handle, list of string)
{
	dbh := ref DB_Handle;
	dbh.datafd = fd;
	dbh.lock = makelock();
	dbh.sqlstream = -1;
	logon := array of byte (username +"/"+ password +"/"+ dbname);
	(mtype, strm, rc, data) := sendReq(dbh, 'I', logon);
	if(mtype == 'h')
		return (nil, (sys->sprint("DB: couldn't initialize %s for %s", dbname, username) :: string data :: nil));
	dbh.sqlconn = int string data;

	(mtype, strm, rc, data) = sendReq(dbh, 'O', array of byte string dbh.sqlconn);
	if(mtype == 'h')
		return (nil, (sys->sprint("DB: couldn't open SQL connection") :: string data :: nil));
	dbh.sqlstream = int string data;
	return (dbh, nil);
}

DB_Handle.SQLOpen(oldh: self ref DB_Handle): (int, ref DB_Handle)
{
	dbh := ref *oldh;
	(mtype, nil, nil, data) := sendReq(dbh, 'O', array of byte string dbh.sqlconn);
	if(mtype == 'h')
		return (-1, nil);
	dbh.sqlstream = int string data;
	return (0, dbh);
}

DB_Handle.SQLClose(dbh: self ref DB_Handle): int
{
	(mtype, nil, nil, nil) := sendReq(dbh, 'K', array[0] of byte);
	if(mtype == 'h')
		return -1;
	dbh.sqlstream = -1;
	return 0;    
}

DB_Handle.SQL(dbh: self ref DB_Handle, command: string): (int, list of string)
{
	(mtype, nil, nil, data) := sendReq(dbh, 'W', array of byte command);
	if(mtype == 'h')
		return (-1, "Probable SQL format error" :: string data :: nil);
	return (0, nil);
}

DB_Handle.columns(dbh: self ref DB_Handle): int
{
	(mtype, nil, nil, data) := sendReq(dbh, 'C', array[0] of byte);
	if(mtype == 'h')
		return 0;
	return int string data;
}

DB_Handle.nextRow(dbh: self ref DB_Handle): int
{
	(mtype, nil, nil, data) := sendReq(dbh, 'N', array[0] of byte);
	if(mtype == 'h')
		return 0;
	return int string data;
}

DB_Handle.read(dbh: self ref DB_Handle, columnI: int): (int, array of byte)
{
	(mtype, nil, nil, data) := sendReq(dbh, 'R', array of byte string columnI);
	if(mtype == 'h')
		return (-1, data);
	return (len data, data);
}

DB_Handle.write(dbh: self ref DB_Handle, paramI: int, val: array of byte)
									: int
{
	outbuf := array[len val + 4] of byte;
	param := array of byte sys->sprint("%3d ", paramI);

	for(i := 0; i < 4; i++)
		outbuf[i] = param[i];
	outbuf[4:] = val;
	(mtype, nil, nil, nil) := sendReq(dbh, 'P', outbuf);
	if(mtype == 'h')
		return -1;
	return len val;
}
 
DB_Handle.columnTitle(handle: self ref DB_Handle, columnI: int): string
{
	(mtype, nil, nil, data) := sendReq(handle, 'T', array of byte string columnI);
	if(mtype == 'h')
		return nil;
	return string data;
}

DB_Handle.errmsg(dbh: self ref DB_Handle): string
{
	(nil, nil, nil, data) := sendReq(dbh, 'H', array[0] of byte);
	return string data;
}

sendReq(dbh: ref DB_Handle, mtype: int, data: array of byte) : (int, int, int, array of byte)
{
	lock(dbh);
	header := sys->sprint("%c1%11d %3d ", mtype, len data, dbh.sqlstream);
	if(sys->write(dbh.datafd, array of byte header, 18) != 18) {
		unlock(dbh);
		return ('h', dbh.sqlstream, 0, array of byte "header write failure");
	}
	if(sys->write(dbh.datafd, data, len data) != len data) {
		unlock(dbh);
		return ('h', dbh.sqlstream, 0, array of byte "data write failure");
	}
	if(sys->write(dbh.datafd, array of byte "\n", 1) != 1) {
		unlock(dbh);
		return ('h', dbh.sqlstream, 0, array of byte "header write failure");
	}
	hbuf := array[RES_HEADER_SIZE+3] of byte;
	if((n := sys->readn(dbh.datafd, hbuf, RES_HEADER_SIZE)) != RES_HEADER_SIZE) {
		unlock(dbh);
		if(n < 0)
			why := sys->aprint("read error: %r");
		else if(n == 0)
			why = sys->aprint("lost connection");
		else
			why = sys->aprint("read error: short read");
		return ('h', dbh.sqlstream, 0, why);
	}
	rheader := string hbuf[0:22];
	rtype := rheader[0];
	#	Probably should check version in header[1]
	datalen := int rheader[2:13];
	rstrm := int rheader[14:17];
	retcode := int rheader[18:21];
    
	databuf := array[datalen] of byte;
	# read in loop until get amount of data we want.  If there is a mismatch
	# here, we may hang with a lock on!

	nbytes: int;

	for(length := 0; length < datalen; length += nbytes) {
		nbytes = sys->read(dbh.datafd, databuf[length:], datalen-length);
		if(nbytes <= 0) {
		    break;
		}
	}
	nbytes = sys->read(dbh.datafd, hbuf, 1);	#  The final \n
	unlock(dbh);
	return (rtype, rstrm, retcode, databuf);
}

makelock(): chan of int
{
	return chan[1] of int;
}

lock(h: ref DB_Handle)
{
	h.lock <-= h.sqlstream;
}

unlock(h: ref DB_Handle)
{
	<-h.lock;
}

user(): string
{
	sys = load Sys Sys->PATH;
	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		return "";
	buf := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return "";
	return string buf[0:n];	
}
