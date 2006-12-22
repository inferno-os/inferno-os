implement Editlog;

include "common.m";

sys: Sys;
utils: Utils;
buffm: Bufferm;
filem: Filem;
textm: Textm;
edit: Edit;

sprint, fprint: import sys;
FALSE, TRUE, BUFSIZE, Empty, Null, Delete, Insert, Replace, Filename, Astring: import Dat;
File: import filem;
Buffer: import buffm;
Text: import textm;
error, warning, stralloc, strfree: import utils;
editerror: import edit;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	utils = mods.utils;
	buffm = mods.bufferm;
	filem = mods.filem;
	textm = mods.textm;
	edit = mods.edit;
}

Wsequence := "warning: changes out of sequence\n";
warned := FALSE;

#
# Log of changes made by editing commands.  Three reasons for this:
# 1) We want addresses in commands to apply to old file, not file-in-change.
# 2) It's difficult to track changes correctly as things move, e.g. ,x m$
# 3) This gives an opportunity to optimize by merging adjacent changes.
# It's a little bit like the Undo/Redo log in Files, but Point 3) argues for a
# separate implementation.  To do this well, we use Replace as well as
# Insert and Delete
#

Buflog: adt{
	typex: int;		# Replace, Filename
	q0: int;		# location of change (unused in f)
	nd: int;		# runes to delete
	nr: int;		# runes in string or file name
};

Buflogsize: con 7;
SHM : con 16rffff;

pack(b: Buflog) : string
{
	a := "0123456";
	a[0] = b.typex;
	a[1] = b.q0&SHM;
	a[2] = (b.q0>>16)&SHM;
	a[3] = b.nd&SHM;
	a[4] = (b.nd>>16)&SHM;
	a[5] = b.nr&SHM;
	a[6] = (b.nr>>16)&SHM;
	return a;
}

scopy(s1: ref Astring, m: int, s2: string, n: int, o: int)
{
	p := o-n;
	for(i := 0; i < p; i++)
		s1.s[m++] = s2[n++];
}

#
# Minstring shouldn't be very big or we will do lots of I/O for small changes.
# Maxstring is BUFSIZE so we can fbufalloc() once and not realloc elog.r.
#
Minstring: con 16;	# distance beneath which we merge changes
Maxstring: con BUFSIZE;	# maximum length of change we will merge into one

eloginit(f: ref File)
{
	if(f.elog.typex != Empty)
		return;
	f.elog.typex = Null;
	if(f.elogbuf == nil)
		f.elogbuf = buffm->newbuffer();
		# f.elogbuf = ref Buffer;
	if(f.elog.r == nil)
		f.elog.r = stralloc(BUFSIZE);
	f.elogbuf.reset();
}

elogclose(f: ref File)
{
	if(f.elogbuf != nil){
		f.elogbuf.close();
		f.elogbuf = nil;
	}
}

elogreset(f: ref File)
{
	f.elog.typex = Null;
	f.elog.nd = 0;
	f.elog.nr = 0;
}

elogterm(f: ref File)
{
	elogreset(f);
	if(f.elogbuf != nil)
		f.elogbuf.reset();
	f.elog.typex = Empty;
	if(f.elog.r != nil){
		strfree(f.elog.r);
		f.elog.r = nil;
	}
	warned = FALSE;
}

elogflush(f: ref File)
{
	b: Buflog;

	b.typex = f.elog.typex;
	b.q0 = f.elog.q0;
	b.nd = f.elog.nd;
	b.nr = f.elog.nr;
	case(f.elog.typex){
	* =>
		warning(nil, sprint("unknown elog type 0x%ux\n", f.elog.typex));
		break;
	Null =>
		break;
	Insert or
	Replace =>
		if(f.elog.nr > 0)
			f.elogbuf.insert(f.elogbuf.nc, f.elog.r.s, f.elog.nr);
		f.elogbuf.insert(f.elogbuf.nc, pack(b), Buflogsize);
		break;
	Delete =>
		f.elogbuf.insert(f.elogbuf.nc, pack(b), Buflogsize);
		break;
	}
	elogreset(f);
}

elogreplace(f: ref File, q0: int, q1: int, r: string, nr: int)
{
	gap: int;

	if(q0==q1 && nr==0)
		return;
	eloginit(f);
	if(f.elog.typex!=Null && q0<f.elog.q0){
		if(warned++ == 0)
			warning(nil, Wsequence);
		elogflush(f);
	}
	# try to merge with previous
	gap = q0 - (f.elog.q0+f.elog.nd);	# gap between previous and this
	if(f.elog.typex==Replace && f.elog.nr+gap+nr<Maxstring){
		if(gap < Minstring){
			if(gap > 0){
				f.buf.read(f.elog.q0+f.elog.nd, f.elog.r, f.elog.nr, gap);
				f.elog.nr += gap;
			}
			f.elog.nd += gap + q1-q0;
			scopy(f.elog.r, f.elog.nr, r, 0, nr);
			f.elog.nr += nr;
			return;
		}
	}
	elogflush(f);
	f.elog.typex = Replace;
	f.elog.q0 = q0;
	f.elog.nd = q1-q0;
	f.elog.nr = nr;
	if(nr > BUFSIZE)
		editerror(sprint("internal error: replacement string too large(%d)", nr));
	scopy(f.elog.r, 0, r, 0, nr);
}

eloginsert(f: ref File, q0: int, r: string, nr: int)
{
	n: int;

	if(nr == 0)
		return;
	eloginit(f);
	if(f.elog.typex!=Null && q0<f.elog.q0){
		if(warned++ == 0)
			warning(nil, Wsequence);
		elogflush(f);
	}
	# try to merge with previous
	if(f.elog.typex==Insert && q0==f.elog.q0 && f.elog.nr+nr<Maxstring){
		ofer := f.elog.r;
		f.elog.r = stralloc(f.elog.nr+nr);
		scopy(f.elog.r, 0, ofer.s, 0, f.elog.nr);
		scopy(f.elog.r, f.elog.nr, r, 0, nr);
		f.elog.nr += nr;
		strfree(ofer);
		return;
	}
	while(nr > 0){
		elogflush(f);
		f.elog.typex = Insert;
		f.elog.q0 = q0;
		n = nr;
		if(n > BUFSIZE)
			n = BUFSIZE;
		f.elog.nr = n;
		scopy(f.elog.r, 0, r, 0, n);
		r = r[n:];
		nr -= n;
	}
}

elogdelete(f: ref File, q0: int, q1: int)
{
	if(q0 == q1)
		return;
	eloginit(f);
	if(f.elog.typex!=Null && q0<f.elog.q0+f.elog.nd){
		if(warned++ == 0)
			warning(nil, Wsequence);
		elogflush(f);
	}
	#  try to merge with previous
	if(f.elog.typex==Delete && f.elog.q0+f.elog.nd==q0){
		f.elog.nd += q1-q0;
		return;
	}
	elogflush(f);
	f.elog.typex = Delete;
	f.elog.q0 = q0;
	f.elog.nd = q1-q0;
}

elogapply(f: ref File)
{
	b: Buflog;
	buf: ref Astring;
	i, n, up, mod : int;
	log: ref Buffer;

	elogflush(f);
	log = f.elogbuf;
	t := f.curtext;

	a := stralloc(Buflogsize);
	buf = stralloc(BUFSIZE);
	mod = FALSE;

	#
	# The edit commands have already updated the selection in t.q0, t.q1.
	# The text.insert and text.delete calls below will update it again, so save the
	# current setting and restore it at the end.
	#
	q0 := t.q0;
	q1 := t.q1;

	while(log.nc > 0){
		up = log.nc-Buflogsize;
		log.read(up, a, 0, Buflogsize);
		b.typex = a.s[0];
		b.q0 = a.s[1]|(a.s[2]<<16);
		b.nd = a.s[3]|(a.s[4]<<16);
		b.nr = a.s[5]|(a.s[6]<<16);
		case(b.typex){
		* =>
			error(sprint("elogapply: 0x%ux\n", b.typex));
			break;

		Replace =>
			if(!mod){
				mod = TRUE;
				f.mark();
			}
			# if(b.nd == b.nr && b.nr <= BUFSIZE){
			#	up -= b.nr;
			#	log.read(up, buf, 0, b.nr);
			#	t.replace(b.q0, b.q0+b.nd, buf.s, b.nr, TRUE, 0);
			#	break;
			# }
			t.delete(b.q0, b.q0+b.nd, TRUE);
			up -= b.nr;
			for(i=0; i<b.nr; i+=n){
				n = b.nr - i;
				if(n > BUFSIZE)
					n = BUFSIZE;
				log.read(up+i, buf, 0, n);
				t.insert(b.q0+i, buf.s, n, TRUE, 0);
			}
			# t.q0 = b.q0;
			# t.q1 = b.q0+b.nr;
			break;

		Delete =>
			if(!mod){
				mod = TRUE;
				f.mark();
			}
			t.delete(b.q0, b.q0+b.nd, TRUE);
			# t.q0 = b.q0;
			# t.q1 = b.q0;
			break;

		Insert =>
			if(!mod){
				mod = TRUE;
				f.mark();
			}
			up -= b.nr;
			for(i=0; i<b.nr; i+=n){
				n = b.nr - i;
				if(n > BUFSIZE)
					n = BUFSIZE;
				log.read(up+i, buf, 0, n);
				t.insert(b.q0+i, buf.s, n, TRUE, 0);
			}
			# t.q0 = b.q0;
			# t.q1 = b.q0+b.nr;
			break;

#		Filename =>
#			f.seq = u.seq;
#			f.unsetname(epsilon);
#			f.mod = u.mod;
#			up -= u.n;
#			if(u.n == 0)
#				f.name = nil;
#			else{
#				fn0 := stralloc(u.n);
#				delta.read(up, fn0, 0, u.n);
#				f.name = fn0.s;
#				strfree(fn0);
#			}
#			break;
#
		}
		log.delete(up, log.nc);
	}
	strfree(buf);
	strfree(a);
	elogterm(f);

	t.q0 = q0;
	t.q1 = q1;
	if(t.q1 > f.buf.nc)	# can't happen
		t.q1 = f.buf.nc;
}
