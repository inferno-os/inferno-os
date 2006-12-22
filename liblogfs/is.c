#include "lib9.h"
#include "logfs.h"
#include "fcall.h"
#include "local.h"

char *logfsisgroupnonename = "none";

char *
logfsisnew(LogfsIdentityStore **isp)
{
	LogfsIdentityStore *is;
	char *errmsg;

	is = logfsrealloc(nil, sizeof(*is));
	if(is == nil) {
	memerror:
		logfsisfree(&is);
		return Enomem;
	}
	errmsg = logfsustnew(&is->ids);
	if(errmsg)
		goto memerror;
	errmsg = logfsgroupmapnew(&is->groupmap, &is->unamemap);
	if(errmsg)
		goto memerror;
	logfsisgroupnonename = logfsustadd(is->ids, logfsisgroupnonename);
	*isp = is;
	return nil;
}

void
logfsisfree(LogfsIdentityStore **isp)
{
	LogfsIdentityStore *is = *isp;
	if(is) {
		logfsustfree(&is->ids);
		logfsgroupmapfree(&is->groupmap);
		logfsunamemapfree(&is->unamemap);
		logfsfreemem(is);
		*isp = nil;
	}
}

char *
logfsisgroupcreate(LogfsIdentityStore *is, char *groupname, char *groupid)
{
	Group *group;
	Uname *uname;

	if(strcmp(groupname, logfsisgroupnonename) == 0 || groupname[0] == '(')
		return "group name reserved";
	groupname = logfsisustadd(is, groupname);
	groupid = logfsisustadd(is, groupid);
	if(groupname == nil || groupid == nil)
		return Enomem;
	return logfsgroupmapnewentry(is->groupmap, is->unamemap, groupid, groupname, &group, &uname);
}

static Group *
findgroupfromuname(LogfsIdentityStore *is, char *groupname)
{
	Uname *u = logfsunamemapfindentry(is->unamemap, groupname);
	if(u == nil)
		return nil;
	return u->g;
}

char *
logfsisgrouprename(LogfsIdentityStore *is, char *oldgroupname, char *newgroupname)
{
	Group *og, *ng;
	oldgroupname = logfsisustadd(is, oldgroupname);
	if(oldgroupname == nil)
		return Enomem;
	og =findgroupfromuname(is, oldgroupname);
	if(og == nil)
		return Enonexist;
	newgroupname = logfsisustadd(is, newgroupname);
	if(newgroupname == nil)
		return Enomem;
	ng = findgroupfromuname(is, newgroupname);
	if(ng != nil)
		return Eexist;
	og->uname = newgroupname;
	return nil;
}

char *
logfsisgroupsetleader(LogfsIdentityStore *is, char *groupname, char *leadername)
{
	Group *g, *lg;
	groupname = logfsisustadd(is, groupname);
	if(groupname == nil)
		return Enomem;
	g = findgroupfromuname(is, groupname);
	if(g == nil)
		return Enonexist;
	if(leadername && leadername[0]) {
		leadername = logfsisustadd(is, leadername);
		if(leadername == nil)
			return Enomem;
		lg = findgroupfromuname(is, leadername);
		if(lg == nil)
			return Enonexist;
		if(!logfsgroupsetismember(g->members, lg))
			return "not a member of the group";
		g->leader = lg;
	}
	else
		g->leader = nil;
	return nil;
}

char *
logfsisgroupaddmember(LogfsIdentityStore *is, char *groupname, char *membername)
{
	Group *g, *mg;
	groupname = logfsisustadd(is, groupname);
	if(groupname == nil)
		return Enomem;
	g =findgroupfromuname(is, groupname);
	if(g == nil)
		return Enonexist;
	membername = logfsisustadd(is, membername);
	if(membername == nil)
		return Enomem;
	mg = findgroupfromuname(is, membername);
	if(mg == nil)
		return Enonexist;
	if(!logfsgroupsetadd(g->members, mg))
		return Enomem;
	return nil;
}

char *
logfsisgroupremovemember(LogfsIdentityStore *is, char *groupname, char *nonmembername)
{
	Group *g, *nonmg;
	groupname = logfsisustadd(is, groupname);
	if(groupname == nil)
		return Enomem;
	g =findgroupfromuname(is, groupname);
	if(g == nil)
		return Enonexist;
	nonmembername = logfsisustadd(is, nonmembername);
	if(nonmembername == nil)
		return Enomem;
	nonmg = findgroupfromuname(is, nonmembername);
	if(nonmg == nil)
		return Enonexist;
	if(!logfsgroupsetremove(g->members, nonmg))
		return Enonexist;
	if(g->leader == nonmg)
		g->leader = nil;
	return nil;
}

typedef struct DS {
	char *printbuf;
	long printbufsize;
	void *buf;
	ulong offset;
	long n;
	ulong printoffset;
	int printn;
	int comma;
} DS;

static int
printmember(void *magic, Group *member)
{
	DS *ds = magic;
	if(ds->comma) {
		if(ds->printn < ds->printbufsize)
			ds->printbuf[ds->printn++] = ',';
	}
	else
		ds->comma = 1;
	ds->printn += snprint(ds->printbuf + ds->printn, ds->printbufsize - ds->printn, "%s", member->uname);
	return 1;
}

static int
printgroup(void *magic, Group *g)
{
	DS *ds = magic;
	ds->printn = snprint(ds->printbuf, ds->printbufsize, "%s:%s:%s:",
		g->uid, g->uname, g->leader ? g->leader->uname : "");
	/* do members */
	ds->comma = 0;
	logfsgroupsetwalk(g->members, printmember, ds);
	if(ds->printn < ds->printbufsize)
		ds->printbuf[ds->printn++] = '\n';
	/*
	 * copy the appropriate part of the buffer
	 */
	if(ds->printoffset < ds->offset + ds->n && ds->printoffset + ds->printn > ds->offset) {
		char *printbuf = ds->printbuf;
		uchar *buf = ds->buf;
		long trim = ds->offset - ds->printoffset;
		if(trim >= 0) {
			printbuf += trim;
			ds->printn -= trim;
		}
		else
			buf -= trim;
		if(ds->printoffset + ds->printn > ds->offset + ds->n)
			ds->printn = ds->offset + ds->n - ds->printoffset;
		memcpy(buf, printbuf, ds->printn);
	}
	/*
	 * advance print position
	 */
	ds->printoffset += ds->printn;
	/*
	 * stop if exceeding the buffer
	 */
	if(ds->printoffset >= ds->offset + ds->n)
		return 0;
	return 1;
}

char *
logfsisusersread(LogfsIdentityStore *is, void *buf, long n, ulong offset, long *nr)
{
	DS ds;
	ds.buf = buf;
	ds.n = n;
	ds.printoffset = 0;
	ds.offset = offset;
	ds.printbufsize = 1024;
	ds.printbuf = logfsrealloc(nil, ds.printbufsize);
	if(ds.printbuf == nil)
		return Enomem;
	logfsmapwalk(is->groupmap, (LOGFSMAPWALKFN *)printgroup, &ds);
	*nr = ds.printoffset - ds.offset;
	logfsfreemem(ds.printbuf);
	return nil;
}

int
logfsisgroupunameismember(LogfsIdentityStore *is, Group *g, char *uname)
{
	Group *ug;
	if(g == nil)
		return 0;
	if(g->uname == uname)
		return 1;
	ug = logfsisfindgroupfromname(is, uname);
	if(ug == nil)
		return 0;
	return logfsgroupsetismember(g->members, ug);
}

int
logfsisgroupuidismember(LogfsIdentityStore *is, Group *g, char *uid)
{
	Group *ug;
	if(g == nil)
		return 0;
	if(g->uid == uid)
		return 1;
	ug = logfsisfindgroupfromid(is, uid);
	if(ug == nil)
		return 0;
	return logfsgroupsetismember(g->members, ug);
}

int
logfsisgroupuidisleader(LogfsIdentityStore *is, Group *g, char *id)
{
	if(g->leader)
		return g->leader->uid == id;
	return logfsisgroupuidismember(is, g, id);
}

Group *
logfsisfindgroupfromname(LogfsIdentityStore *is, char *name)
{
	Uname *u;
	u = logfsunamemapfindentry(is->unamemap, name);
	if(u == nil)
		return nil;
	return u->g;
}

char *
logfsisfindidfromname(LogfsIdentityStore *is, char *name)
{
	char *id;
	id = logfsunamemapfinduid(is->unamemap, name);
	if(id == nil)
		return logfsisgroupnonename;
	return id;
}

char *
logfsisfindnamefromid(LogfsIdentityStore *is, char *id)
{
	Group *g;
	g = logfsgroupmapfindentry(is->groupmap, id);
	if(g == nil)
		return nil;
	return g->uname;
}
