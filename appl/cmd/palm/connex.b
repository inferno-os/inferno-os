implement Connex;

#
# temporary test program for palmsrv development
#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "palm.m";
	palm: Palm;
	Record: import palm;
	palmdb: Palmdb;
	DB, PDB, PRC: import palmdb;

include "desklink.m";
	desklink: Desklink;
	SysInfo: import desklink;

Connex: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	palm = load Palm Palm->PATH;
	if(palm == nil)
		error(sys->sprint("can't load %s: %r", palm->PATH));
	desklink = load Desklink Desklink->PATH1;
	if(desklink == nil)
		error(sys->sprint("can't load Desklink: %r"));

	palm->init();

	err: string;
	(palmdb, err) = desklink->connect("/chan/palmsrv");
	if(palmdb == nil)
		error(sys->sprint("can't init Desklink: %s", err));
	desklink->init(palm);
	sysinfo := desklink->ReadSysInfo();
	if(sysinfo == nil)
		error(sys->sprint("can't read sys Info: %r"));
	sys->print("ROM: %8.8ux locale: %8.8ux product: '%s'\n", sysinfo.romversion, sysinfo.locale, sysinfo.product);
	user := desklink->ReadUserInfo();
	if(user == nil)
		error(sys->sprint("can't read user info"));
	sys->print("userid: %d viewerid: %d lastsyncpc: %d succsync: %8.8ux lastsync: %8.8ux uname: '%s' password: %s\n",
		user.userid, user.viewerid, user.lastsyncpc, user.succsynctime, user.lastsynctime, user.username, ba(user.password));
	sys->print("Storage:\n");
	for(cno:=0;;){
		(cards, more, err) := desklink->ReadStorageInfo(cno);
		for(i:=0; i<len cards; i++){
			sys->print("%2d v=%d c=%d romsize=%d ramsize=%d ramfree=%d name='%s' maker='%s'\n",
				cards[i].cardno, cards[i].version, cards[i].creation, cards[i].romsize, cards[i].ramsize,
				cards[i].ramfree, cards[i].name, cards[i].maker);
			cno = cards[i].cardno+1;
		}
		if(!more)
			break;
	}
	sys->print("ROM DBs:\n");
	listdbs(Desklink->DBListROM);
	sys->print("RAM DBs:\n");
	listdbs(Desklink->DBListRAM);

	(db, ee) := DB.open("AddressDB", Palmdb->OREAD);
	if(db == nil){
		sys->print("error: AddressDB: %s\n", ee);
		exit;
	}
	pdb := db.records();
	if(pdb == nil){
		sys->print("error: AddressDB: %r\n");
		exit;
	}
	dumpfd := sys->create("dump", Sys->OWRITE, 8r600);
	for(i:=0; (r := pdb.read(i)) != nil; i++)
		sys->write(dumpfd, r.data, len r.data);
#	desklink->EndOfSync(Desklink->SyncNormal);
	desklink->hangup();
}

listdbs(sort: int)
{
	index := 0;
	for(;;){
		(dbs, more, e) := desklink->ReadDBList(0, sort, index);
		if(dbs == nil){
			if(e != nil)
				sys->print("ReadDBList: %s\n", e);
			break;
		}
		for(i := 0; i < len dbs; i++){
			sys->print("#%4.4ux '%s'\n", dbs[i].index, dbs[i].name);
			index = dbs[i].index+1;
		}
		if(!more)
			break;
	}
}

ba(a: array of byte): string
{
	s := "";
	for(i := 0; i < len a; i++)
		s += sys->sprint("%2.2ux", int a[i]);
	return s;
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "tconn: %s\n", s);
	fd := sys->open("/prog/"+string sys->pctl(0,nil)+"/ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
	raise "fail:error";
}
