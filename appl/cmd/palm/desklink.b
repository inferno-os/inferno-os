implement Palmdb, Desklink;

#
# Palm Desk Link Protocol (DLP)
#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#
# Request and response formats were extracted from
# include/Core/System/DLCommon.h in the PalmOS SDK-5
#

include "sys.m";
	sys: Sys;

include "daytime.m";
	daytime: Daytime;
	Tm: import daytime;

include "palm.m";
	palm: Palm;
	DBInfo, Record, Resource, id2s, s2id, get2, put2, get4, put4, gets, argsize, packargs, unpackargs: import palm;

include "timers.m";

include "desklink.m";

Maxrecbytes: con 16rFFFF;

# operations defined by Palm

T_ReadUserInfo, T_WriteUserInfo, T_ReadSysInfo, T_GetSysDateTime,
T_SetSysDateTime, T_ReadStorageInfo, T_ReadDBList, T_OpenDB, T_CreateDB,
T_CloseDB, T_DeleteDB, T_ReadAppBlock, T_WriteAppBlock, T_ReadSortBlock,
T_WriteSortBlock, T_ReadNextModifiedRec, T_ReadRecord, T_WriteRecord,
T_DeleteRecord, T_ReadResource, T_WriteResource, T_DeleteResource,
T_CleanUpDatabase, T_ResetSyncFlags, T_CallApplication, T_ResetSystem,
T_AddSyncLogEntry, T_ReadOpenDBInfo, T_MoveCategory, T_ProcessRPC,
T_OpenConduit, T_EndOfSync, T_ResetDBIndex, T_ReadRecordIDList,
# DLP 1.1 functions
T_ReadNextRecInCategory, T_ReadNextModifiedRecInCategory,
T_ReadAppPreference, T_WriteAppPreference, T_ReadNetSyncInfo,
T_WriteNetSyncInfo, T_ReadFeature,
# DLP 1.2 functions
T_FindDB, T_SetDBInfo,
# DLP 1.3 functions
T_LoopBackTest, T_ExpSlotEnumerate, T_ExpCardPresent, T_ExpCardInfo: con 16r10+iota;
# then there's a group of VFS requests that we don't currently use

Response: con 16r80;

Maxname: con 32;

A1, A2: con Palm->ArgIDbase+iota;	# argument IDs have request-specific interpretation (most have only one ID)

Timeout: con 30;	# seconds time out used by Palm's headers
srvfd: ref Sys->FD;
selfdb: Palmdb;

errorlist := array [] of {
	"no error",
	"general Pilot system error",
	"unknown request",
	"out of dynamic memory on device",
	"invalid parameter",
	"not found",
	"no open databases",
	"database already open",
	"too many open databases",
	"database already exists",
	"cannot open database",
	"record previously deleted",
	"record busy",
	"operation not supported",
	"unexpected error (ErrUnused1)",
	"read only object",
	"not enough space",
	"size limit exceeded",
	"sync cancelled",
	"bad arg wrapper",
	"argument missing",
	"bad argument size",
};

Eshort: con "desklink protocol: response too short";

debug := 0;

connect(srvfile: string): (Palmdb, string)
{
	sys = load Sys Sys->PATH;
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		return (nil, sys->sprint("can't load %s: %r", Daytime->PATH));
	srvfd = sys->open(srvfile, Sys->ORDWR);
	if(srvfd == nil)
		return (nil, sys->sprint("can't open %s: %r", srvfile));
	selfdb = load Palmdb "$self";
	if(selfdb == nil)
		return (nil, sys->sprint("can't load self as Palmdb: %r"));
	return (selfdb, nil);
}

hangup(): int
{
	srvfd = nil;
	return 0;
}

#
# set the system error string
#
e(s: string): string
{
	if(s != nil){
		s = "palm: "+s;
		sys->werrstr(s);
	}
	return s;
}

#
# sent before each conduit is opened by the desktop,
# apparently to detect a pending cancel request (on the device)
#
OpenConduit(): int
{
	return nexec(T_OpenConduit, A1, nil);
}

#
# end of sync on desktop
#
EndOfSync(status: int): int
{
	req := array[2] of byte;
	put2(req, status);
	return nexec(T_EndOfSync, A1, req);
}

ReadSysInfo(): ref SysInfo
{
	if((reply := dexec(T_ReadSysInfo, A1, nil, 14)) == nil)
		return nil;
	s := ref SysInfo;
	s.romversion = get4(reply);
	s.locale = get4(reply[4:]);
	l := int reply[9];	# should be at most 4 apparently?
	s.product = gets(reply[10:10+l]);
	return s;
}

ReadSysInfoVer(): (int, int, int)
{
	req := array[4] of byte;
	put2(req, 1);	# major version
	put2(req, 2);	# minor version
	if((reply := dexec(T_ReadSysInfo, A2, req, 12)) == nil)
		return (0, 0, 0);
	return (get4(reply), get4(reply[4:]), get4(reply[8:]));
}

ReadUserInfo(): ref User
{
	if((reply := dexec(T_ReadUserInfo, 0, nil, 30)) == nil)
		return nil;
	u := ref User;
	u.userid = get4(reply);
	u.viewerid = get4(reply[4:]);
	u.lastsyncpc = get4(reply[8:]);
	u.succsynctime = getdate(reply[12:]);
	u.lastsynctime = getdate(reply[20:]);
	userlen := int reply[28];
	pwlen := int reply[29];
	u.username = gets(reply[30:30+userlen]);
	u.password = array[pwlen] of byte;
	u.password[0:] = reply[30+userlen:30+userlen+pwlen];
	return u;
}

WriteUserInfo(u: ref User, flags: int): int
{
	req := array[22+Maxname] of byte;
	put4(req, u.userid);
	put4(req[4:], u.viewerid);
	put4(req[8:], u.lastsyncpc);
	putdate(req[12:], u.lastsynctime);
	req[20] = byte flags;
	l := puts(req[22:], u.username);
	req[21] = byte l;
	return nexec(T_WriteUserInfo, A1, req[0:22+l]);
}

GetSysDateTime(): int
{
	if((reply := dexec(T_GetSysDateTime, A1, nil, 8)) == nil)
		return -1;
	return getdate(reply);
}

SetSysDateTime(time: int): int
{
	return nexec(T_SetSysDateTime, A1, putdate(array[8] of byte, time));
}

ReadStorageInfo(cardno: int): (array of ref CardInfo, int, string)
{
	req := array[2] of byte;
	req[0] = byte cardno;
	req[1] = byte 0;
	(reply, err) := rexec(T_ReadStorageInfo, A1, req, 30);
	if(reply == nil)
		return (nil, 0, err);
	nc := int reply[3];
	if(nc <= 0)
		return (nil, 0, nil);
	more := int reply[1] != 0;
	a := array[nc] of ref CardInfo;
	p := 4;
	for(i:=0; i<nc; i++){
		nb: int;
		(a[i], nb) = unpackcard(reply[p:]);
		p += nb;
	}
	return (a, more, nil);
}

unpackcard(a: array of byte): (ref CardInfo, int)
{
	nb := int a[0];	# total size of this card's info
	c := ref CardInfo;
	c.cardno = int a[1];
	c.version = get2(a[2:]);
	c.creation = getdate(a[4:]);
	c.romsize = get4(a[12:]);
	c.ramsize = get4(a[16:]);
	c.ramfree = get4(a[20:]);
	l1 := int a[24] + 26;
	l2 := int a[25];
	c.name = gets(a[26:l1]);
	c.maker = gets(a[l1:l1+l2]);
	return (c, nb);
}

ReadDBCount(cardno: int): (int, int)
{
	req := array[2] of byte;
	req[0] = byte cardno;
	req[1] = byte 0;
	if((reply := dexec(T_ReadStorageInfo, A2, req, 20)) == nil)
		return (-1, -1);
	return (get2(req[0:]), get2(req[2:]));
}

unpackdbinfo(a: array of byte): (ref DBInfo, int)
{
	size := int a[0];
	misc := int a[1];
	info := ref DBInfo;
	info.attr = get2(a[2:]);
	info.dtype = id2s(get4(a[4:]));
	info.creator = id2s(get4(a[8:]));
	info.version = get2(a[12:]);
	info.modno = get4(a[14:]);
	info.ctime = getdate(a[18:]);
	info.mtime = getdate(a[26:]);
	info.btime = getdate(a[34:]);
	info.index = get2(a[42:]);
	if(size > len a)
		size = len a;
	info.name = gets(a[44:size]);
	return (info, size);
}

ReadDBList(cardno: int, flags: int, start: int): (array of ref DBInfo, int, string)
{
	req := array[4] of byte;
	req[0] = byte (flags | DBListMultiple);
	req[1] = byte cardno;
	put2(req[2:], start);
	(reply, err) := rexec(T_ReadDBList, A1, req, 48);
	if(reply == nil || int reply[3] == 0)
		return (nil, 0, err);
	# lastindex[2] flags[1] actcount[1]
	#	flags is 16r80 => more to list
	more := (reply[2] & byte 16r80) != byte 0;
	dbs := array[int reply[3]] of ref DBInfo;
#sys->print("ndb=%d more=%d lastindex=#%4.4ux\n", len dbs, more, get2(reply));
	a := reply[4:];
	for(i := 0; i < len dbs; i++){
		(db, n) := unpackdbinfo(a);
		dbs[i] = db;
		a = a[n:];
	}
	return (dbs, more, nil);
}

matchdb(cardno: int, flag: int, start: int, dbname: string, dtype: string, creator: string): (ref DBInfo, int)
{
	for(;;){
		(dbs, more, err) := ReadDBList(cardno, flag, start);
		if(dbs == nil)
			break;
		for(i := 0; i < len dbs; i++){
			info := dbs[i];
			if((dbname == nil || info.name == dbname) &&
			   (dtype == nil || info.dtype == dtype) &&
			   (creator == nil || info.creator == creator))
				return (info, info.index);
			start = info.index+1;
		}
	}
	return (nil, 0);
}


FindDBInfo(cardno: int, start: int, dbname: string, dtype: string, creator: string): ref DBInfo
{
	if(start < 16r1000) {
		(info, i) := matchdb(cardno, 16r80, start, dbname, dtype, creator);
		if(info != nil)
			return info;
	}
	(info, i) := matchdb(cardno, 16r40, start&~16r1000, dbname, dtype, creator);
	if(info != nil)
		info.index |= 16r1000;
	return info;
}

DeleteDB(name: string): int
{
	(cardno, dbname) := parsedb(name);
	req := array[2+Maxname] of byte;
	req[0] = byte cardno;
	req[1] = byte 0;
	n := puts(req[2:], dbname);
	return nexec(T_DeleteDB, A1, req[0:2+n]);
}

ResetSystem(): int
{
	return nexec(T_ResetSystem, 0, nil);
}

CloseDB_All(): int
{
	return nexec(T_CloseDB, A2, nil);
}

AddSyncLogEntry(entry: string): int
{
	req := array[256] of byte;
	n := puts(req, entry);
	return nexec(T_AddSyncLogEntry, A1, req[0:n]);
}

#
# this implements a Palmdb->DB directly accessed using the desklink protocol
#

init(m: Palm): string
{
	palm = m;
	return nil;
}

#
# syntax is [cardno/]dbname
# where cardno defaults to 0
#
parsedb(name: string): (int, string)
{
	(nf, flds) := sys->tokenize(name, "/");
	if(nf > 1)
		return (int hd flds, hd tl flds);
	return (0, name);
}

DB.open(name: string, mode: int): (ref DB, string)
{
	(cardno, dbname) := parsedb(name);
	req := array[2+Maxname] of byte;
	req[0] = byte cardno;
	req[1] = byte mode;
	n := puts(req[2:], dbname);
	(reply, err) := rexec(T_OpenDB, A1, req[0:2+n], 1);
	if(reply == nil)
		return (nil, err);
	db := ref DB;
	db.x = int reply[0];
	inf := db.stat();
	if(inf == nil)
		return (nil, sys->sprint("can't get DBInfo: %r"));
	db.attr = inf.attr;	# mainly need to know whether it's Fresource or not
	return (db, nil);
}

DB.create(name: string, nil: int, nil: int, inf: ref DBInfo): (ref DB, string)
{
	(cardno, dbname) := parsedb(name);
	req := array[14+Maxname] of byte;
	put4(req, s2id(inf.creator));
	put4(req[4:], s2id(inf.dtype));
	req[8] = byte cardno;
	req[9] = byte 0;
	put2(req[10:], inf.attr);
	put2(req[12:], inf.version);
	n := puts(req[14:], dbname);
	(reply, err) := rexec(T_CreateDB, A1, req[0:14+n], 1);
	if(reply == nil)
		return (nil, err);
	db := ref DB;
	db.x = int reply[0];
	db.attr = inf.attr;
	return (db, nil);
}

DB.stat(db: self ref DB): ref DBInfo
{
	(reply, err) := rexec(T_FindDB, A2, array[] of {byte 16r80, byte db.x}, 54);
	if(err != nil)
		return nil;
	return unpackdbinfo(reply[10:]).t0;
}

DB.wstat(db: self ref DB, inf: ref DBInfo, flags: int)
{
	# TO DO
}

DB.close(db: self ref DB): string
{
	return rexec(T_CloseDB, A1, array[] of {byte db.x}, 0).t1;
}

DB.records(db: self ref DB): ref PDB
{
	if(db.attr & Palm->Fresource){
		sys->werrstr("not a database file");
		return nil;
	}
	return ref PDB(db);
}

DB.resources(db: self ref DB): ref PRC
{
	if((db.attr & Palm->Fresource) == 0){
		sys->werrstr("not a resource file");
		return nil;
	}
	return ref PRC(db);
}

DB.readidlist(db: self ref DB, sort: int): array of int
{
	req := array[6] of byte;
	req[0] = byte db.x;
	if(sort)
		req[1] = byte 16r80;
	else
		req[1] = byte 0;
	put2(req[2:], 0);
	put2(req[4:], -1);
	p := dexec(T_ReadRecordIDList, A1, req, 2);
	if(p == nil)
		return nil;
	ret := get2(p);
	ids := array[ret] of int;
	p = p[8:];
	for (i := 0; i < ret; p = p[4:])
		ids[i++] = get4(p);
	return ids;
}

DB.nentries(db: self ref DB): int
{
	if((reply := dexec(T_ReadOpenDBInfo, A1, array[] of {byte db.x}, 2)) == nil)
		return -1;
	return get2(reply);
}

DB.rdappinfo(db: self ref DB): (array of byte, string)
{
	req := array[6] of byte;
	req[0] = byte db.x;
	req[1] = byte 0;
	put2(req[2:], 0);	# offset
	put2(req[4:], -1);	# to end
	(reply, err) := rexec(T_ReadAppBlock, A1, req, 2);
	if(reply == nil)
		return (nil, err);
	if(get2(reply) < len reply-2)
		return (nil, "short reply");
	return (reply[2:], nil);
}

DB.wrappinfo(db: self ref DB, data: array of byte): string
{
	req := array[4 + len data] of byte;
	req[0] = byte db.x;
	req[1] = byte 0;
	put2(req[2:], len data);
	req[4:] = data;
	return rexec(T_WriteAppBlock, A1, req, 0).t1;
}

DB.rdsortinfo(db: self ref DB): (array of int, string)
{
	req := array[6] of byte;
	req[0] = byte db.x;
	req[1] = byte 0;
	put2(req[2:], 0);
	put2(req[4:], -1);
	(reply, err) := rexec(T_ReadSortBlock, A1, req, 2);
	if(reply == nil)
		return (nil, err);
	n := len reply;
	a := reply[2:n];
	n = (n-2)/2;
	s := array[n] of int;
	for(i := 0; i < n; i++)
		s[i] = get2(a[i*2:]);
	return (s, nil);
}

DB.wrsortinfo(db: self ref DB, s: array of int): string
{
	n := len s;
	req := array[4+2*n] of byte;
	req[0] = byte db.x;
	req[1] = byte 0;
	put2(req[2:], 2*n);
	for(i := 0; i < n; i++)
		put2(req[2+i*2:], s[i]);
	return rexec(T_WriteSortBlock, A1, req, 0).t1;
}

PDB.purge(db: self ref PDB): string
{
	return rexec(T_CleanUpDatabase, A1, array[] of {byte db.db.x}, 0).t1;
}

DB.resetsyncflags(db: self ref DB): string
{
	return rexec(T_ResetSyncFlags, A1, array[] of {byte db.x}, 0).t1;
}

#
# .pdb and other data base files
#

PDB.read(db: self ref PDB, index: int): ref Record
{
	req := array[8] of byte;
	req[0] = byte db.db.x;
	req[1] = byte 0;
	put2(req[2:], index);
	put2(req[4:], 0);	# offset
	put2(req[6:], Maxrecbytes);
	return unpackrec(dexec(T_ReadRecord, A2, req, 10)).t0;
}

PDB.readid(db: self ref PDB, id: int): (ref Record, int)
{
	req := array[10] of byte;
	req[0] = byte db.db.x;
	req[1] = byte 0;
	put4(req[2:], id);
	put2(req[6:], 0); # offset
	put2(req[8:], Maxrecbytes);
	return unpackrec(dexec(T_ReadRecord, A1, req, 10));
}

PDB.write(db: self ref PDB, r: ref Record): string
{
	req := array[8+len r.data] of byte;
	req[0] = byte db.db.x;
	req[1] = byte 0;
	put4(req[2:], r.id);
	req[6] = byte (r.attr & Palm->Rsecret);
	req[7] = byte r.cat;
	req[8:] = r.data;
	(reply, err) := rexec(T_WriteRecord, A1, req, 4);
	if(reply == nil)
		return err;
	if(r.id == 0)
		r.id = get4(reply);
	return nil;
}

PDB.movecat(db: self ref PDB, from: int, tox: int): string
{
	req := array[4] of byte;
	req[0] = byte db.db.x;
	req[1] = byte from;
	req[2] = byte tox;
	req[3] = byte 0;
	return rexec(T_MoveCategory, A1, req, 0).t1;
}

PDB.resetnext(db: self ref PDB): int
{
	return nexec(T_ResetDBIndex, A1, array[] of {byte db.db.x});
}

PDB.readnextmod(db: self ref PDB): (ref Record, int)
{
	return unpackrec(dexec(T_ReadNextModifiedRec, A1, array[] of {byte db.db.x}, 10));
}

PDB.delete(db: self ref PDB, id: int): string
{
	req := array[6] of byte;
	req[0] = byte db.db.x;
	req[1] = byte 0;
	put4(req[2:], id);
	return rexec(T_DeleteRecord, A1, req, 0).t1;
}

PDB.deletecat(db: self ref PDB, cat: int): string
{
	return rexec(T_DeleteRecord, A1, array[] of {byte db.db.x, byte 16r40, 2 to 6 => byte 0, 7=>byte cat}, 0).t1;
}

PDB.truncate(db: self ref PDB): string
{
	return rexec(T_DeleteRecord, A1, array[] of {byte db.db.x, byte 16r80, 2 to 7 => byte 0}, 0).t1;
}

#
# .prc resource files
#

PRC.write(db: self ref PRC, r: ref Resource): string
{
	req := array[8+len r.data] of byte;
	req[0] = byte db.db.x;
	req[1] = byte 0;
	put4(req[2:], r.name);
	put2(req[6:], r.id);
	put2(req[8:], len r.data);
	return rexec(T_WriteResource, A1, req, 0).t1;
}

PRC.delete(db: self ref PRC, name: int, id: int): string
{
	req := array[8] of byte;
	req[0] = byte db.db.x;
	req[1] = byte 0;
	put4(req[2:], name);
	put4(req[6:], id);
	return rexec(T_DeleteResource, A1, req, 0).t1;
}

PRC.readtype(db: self ref PRC, name: int, id: int): (ref Resource, int)
{
	req := array[12] of byte;
	req[0] = byte db.db.x;
	req[1] = byte 0;
	put4(req[2:], name);
	put2(req[6:], id);
	put2(req[8:], 0); # Offset into record
	put2(req[10:], Maxrecbytes);
	return unpackresource(dexec(T_ReadResource, A2, req, 10));
}

PRC.truncate(db: self ref PRC): string
{
	return rexec(T_DeleteResource, A1, array[] of {byte db.db.x, byte 16r80, 2 to 7 => byte 0}, 0).t1;
}

PRC.read(db: self ref PRC, index: int): ref Resource
{
	req := array[8] of byte;
	req[0] = byte db.db.x;
	req[1] = byte 0;
	put2(req[2:], index);
	put2(req[4:], 0);	# offset
	put2(req[6:], Maxrecbytes);
	return unpackresource(dexec(T_ReadResource, A1, req, 12)).t0;
}

#
# DL protocol
#
# request
#	id: byte	# operation
#	argc: byte	# arg count
#	args: byte[]
#
# response
#	id: byte	# cmd|16r80
#	argc: byte	# argc response arguments follow header
#	error: byte[2]	# error code
#	args: byte[]
#
# args wrapped by Palm->packargs etc.
#

#
# RPC exchange with device
#
rpc(req: array of byte): (array of (int, array of byte), string)
{
	if(sys->write(srvfd, req, len req) != len req)
		return (nil, sys->sprint("link: %r"));
	reply := array[65536] of byte;
	nb := sys->read(srvfd, reply, len reply);
	if(nb == 0)
		return (nil, "link: hangup");
	if(nb < 0)
		return (nil, sys->sprint("link: %r"));
	r := int reply[0];
	if((r & Response) == 0)
		return (nil, e(sys->sprint("received request #%2.2x not response", r)));
	if(r != (Response|int req[0]))
		return (nil, e(sys->sprint("wrong response #%x", r)));
	if(nb < 4)
		return (nil, e(Eshort));
	rc := get2(reply[2:]);
	if(rc != 0){
		if(rc < 0 || rc >= len errorlist)
			return (nil, e(sys->sprint("unknown error %d", rc)));
		return (nil, e(errorlist[rc]));
	}
	argc := int reply[1];	# count of following arguments
	if(argc == 0)
		return (nil, nil);
	return unpackargs(argc, reply[4:nb]);
}

rexec(cmd: int, argid: int, arg: array of byte, minlen: int): (array of byte, string)
{
	args: array of (int, array of byte);
	if(arg != nil)
		args = array[] of {(argid, arg)};
	req := array[2+argsize(args)] of byte;
	req[0] = byte cmd;
	req[1] = byte len args;
	packargs(req[2:], args);
	(replies, err) := rpc(req);
	if(replies == nil){
		if(err != nil)
			return (nil, err);
		if(minlen > 0)
			return (nil, e(Eshort));
		return (nil, nil);
	}
	(nil, reply) := replies[0];
	if(len reply < minlen)
		return (nil, e(Eshort));
	return (reply, nil);
}

dexec(cmd: int, argid: int, msg: array of byte, minlen: int): array of byte
{
	(reply, nil) := rexec(cmd, argid, msg, minlen);
	return reply;
}

nexec(cmd: int, argid: int, msg: array of byte): int
{
	(nil, err) := rexec(cmd, argid, msg, 0);
	if(err != nil)
		return -1;
	return 0;
}

unpackresource(a: array of byte): (ref Resource, int)
{
	nb := len a;
	if(nb < 10)
		return (nil, -1);
	size := get2(a[8:]);
	if(nb-10 < size)
		return (nil, -1);
	r := Resource.new(get4(a), get2(a[4:]), size);
	r.data[0:] = a[10:10+size];
	return (r, get2(a[6:]));
}

unpackrec(a: array of byte): (ref Record, int)
{
	nb := len a;
	if(nb < 10)
		return (nil, -1);
	size := get2(a[6:]);
	if(nb-10 < size)
		return (nil, -1);
	r := Record.new(get4(a), int a[8], int a[9], size);
	r.data[0:] = a[10:10+size];
	return (r, get2(a[4:]));
}

#
# pack string (must be Latin1) as zero-terminated array of byte
#
puts(a: array of byte, s: string): int
{
	for(i := 0; i < len s && i < len a-1; i++)
		a[i] = byte s[i];
	a[i++] = byte 0;
	return i;
}

#
# the conversion via local time might be wrong,
# since the computers might be in different time zones,
# but is hard to avoid
#

getdate(data: array of byte): int
{
	yr := (int data[0] << 8) | int data[1];
	if(yr == 0)
		return 0;	# unspecified
	t := ref Tm;
	t.sec = int data[6];
	t.min = int data[5];
	t.hour = int data[4];
	t.mday = int data[3];
	t.mon = int data[2] - 1;
	t.year = yr - 1900;
	t.wday = 0;
	t.yday = 0;
	return daytime->tm2epoch(t);
}

putdate(data: array of byte, time: int): array of byte
{
	t := daytime->local(time);
	y := t.year + 1900;
	if(time == 0)
		y = 0;	# `unchanged'
	data[7] = byte 0; # pad
	data[6] = byte t.sec;
	data[5] = byte t.min;
	data[4] = byte t.hour;
	data[3] = byte t.mday;
	data[2] = byte (t.mon + 1);
	data[0] = byte ((y >> 8) & 16rff);
	data[1] = byte (y & 16rff);
	return data;
}
