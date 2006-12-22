implement Filem;

include "common.m";

sys : Sys;
dat : Dat;
utils : Utils;
buffm : Bufferm;
textm : Textm;
editlog: Editlog;

FALSE, TRUE, XXX, Delete, Insert, Filename, BUFSIZE, Astring : import Dat;
Buffer, newbuffer : import buffm;
Text : import textm;
error : import utils;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	dat = mods.dat;
	utils = mods.utils;
	buffm = mods.bufferm;
	textm = mods.textm;
	editlog = mods.editlog;
}

#
# Structure of Undo list:
# 	The Undo structure follows any associated data, so the list
#	can be read backwards: read the structure, then read whatever
#	data is associated (insert string, file name) and precedes it.
#	The structure includes the previous value of the modify bit
#	and a sequence number; successive Undo structures with the
#	same sequence number represent simultaneous changes.
#
 
Undo : adt
{
	typex : int;	# Delete, Insert, Filename 
	mod : int;		# modify bit 
	seq : int;		# sequence number 
	p0 : int;		# location of change (unused in f) 
	n : int;		# # runes in string or file name 
};

Undosize : con 8;
SHM : con 16rffff;

undotostr(t, m, s, p, n : int) : string
{
	a := "01234567";
	a[0] = t;
	a[1] = m;
	a[2] = s&SHM;
	a[3] = (s>>16)&SHM;
	a[4] = p&SHM;
	a[5] = (p>>16)&SHM;
	a[6] = n&SHM;
	a[7] = (n>>16)&SHM;
	return a;
}

strtoundo(s: string): Undo
{
	u: Undo;

	u.typex = s[0];
	u.mod = s[1];
	u.seq = s[2]|(s[3]<<16);
	u.p0 = s[4]|(s[5]<<16);
	u.n = s[6]|(s[7]<<16);
	return u;
}

nullfile : File;

File.addtext(f : self ref File, t : ref Text) : ref File
{
	if(f == nil) {
		f = ref nullfile;
		f.buf = newbuffer();
		f.delta = newbuffer();
		f.epsilon = newbuffer();
		f.ntext = 0;
		f.unread = TRUE;
	}
	oft := f.text;
	f.text = array[f.ntext+1] of ref Text;
	f.text[0:] = oft[0:f.ntext];
	oft = nil;
	f.text[f.ntext++] = t;
	f.curtext = t;
	return f;
}

File.deltext(f : self ref File, t : ref Text)
{
	i : int;

	for(i=0; i<f.ntext; i++)
		if(f.text[i] == t)
			break;
	if (i == f.ntext)
		error("can't find text in File.deltext");

	f.ntext--;
	if(f.ntext == 0){
		f.close();
		return;
	}
	f.text[i:] = f.text[i+1:f.ntext+1];
	if(f.curtext == t)
		f.curtext = f.text[0];
}

File.insert(f : self ref File, p0 : int, s : string, ns : int)
{
	if (p0 > f.buf.nc)
		error("bad assert in File.insert");
	if(f.seq > 0)
		f.uninsert(f.delta, p0, ns);
	f.buf.insert(p0, s, ns);
	if(ns)
		f.mod = TRUE;
}

File.uninsert(f : self ref File, delta : ref Buffer, p0 : int, ns : int)
{
	# undo an insertion by deleting 
	a := undotostr(Delete, f.mod, f.seq, p0, ns);
	delta.insert(delta.nc, a, Undosize);
}

File.delete(f : self ref File, p0 : int, p1 : int)
{
	if (p0>p1 || p0>f.buf.nc || p1>f.buf.nc)
		error("bad assert in File.delete");
	if(f.seq > 0)
		f.undelete(f.delta, p0, p1);
	f.buf.delete(p0, p1);
	if(p1 > p0)
		f.mod = TRUE;
}

File.undelete(f : self ref File, delta : ref Buffer, p0 : int, p1 : int)
{
	buf : ref Astring;
	i, n : int;

	# undo a deletion by inserting 
	a := undotostr(Insert, f.mod, f.seq, p0, p1-p0);
	m := p1-p0;
	if(m > BUFSIZE)
		m = BUFSIZE;
	buf = utils->stralloc(m);
	for(i=p0; i<p1; i+=n){
		n = p1 - i;
		if(n > BUFSIZE)
			n = BUFSIZE;
		f.buf.read(i, buf, 0, n);
		delta.insert(delta.nc, buf.s, n);
	}
	utils->strfree(buf);
	buf = nil;
	delta.insert(delta.nc, a, Undosize);
}

File.setname(f : self ref File, name : string, n : int)
{
	if(f.seq > 0)
		f.unsetname(f.delta);
	f.name = name[0:n];
	f.unread = TRUE;
}

File.unsetname(f : self ref File, delta : ref Buffer)
{
	# undo a file name change by restoring old name 
	a := undotostr(Filename, f.mod, f.seq, 0, len f.name);
	if(f.name != nil)
		delta.insert(delta.nc, f.name, len f.name);
	delta.insert(delta.nc, a, Undosize);
}

File.loadx(f : self ref File, p0 : int, fd : ref Sys->FD) : int
{
	if(f.seq > 0)
		error("undo in file.load unimplemented");
	return f.buf.loadx(p0, fd);
}

File.undo(f : self ref File, isundo : int, q0 : int, q1 : int) : (int, int)
{
	buf : ref Astring;
	i, j, n, up : int;
	stop : int;
	delta, epsilon : ref Buffer;
	u : Undo;

	a := utils->stralloc(Undosize);
	if(isundo){
		# undo; reverse delta onto epsilon, seq decreases 
		delta = f.delta;
		epsilon = f.epsilon;
		stop = f.seq;
	}else{
		# redo; reverse epsilon onto delta, seq increases 
		delta = f.epsilon;
		epsilon = f.delta;
		stop = 0;	# don't know yet 
	}

	buf = utils->stralloc(BUFSIZE);
	while(delta.nc > 0){
		up = delta.nc-Undosize;
		delta.read(up, a, 0, Undosize);
		u = strtoundo(a.s);
		if(isundo){
			if(u.seq < stop){
				f.seq = u.seq;
				utils->strfree(buf);
				utils->strfree(a);
				return (q0, q1);
			}
		}else{
			if(stop == 0)
				stop = u.seq;
			if(u.seq > stop){
				utils->strfree(buf);
				utils->strfree(a);
				return (q0, q1);
			}
		}
		case(u.typex){
		Delete =>
			f.seq = u.seq;
			f.undelete(epsilon, u.p0, u.p0+u.n);
			f.mod = u.mod;
			f.buf.delete(u.p0, u.p0+u.n);
			for(j=0; j<f.ntext; j++)
				f.text[j].delete(u.p0, u.p0+u.n, FALSE);
			q0 = u.p0;
			q1 = u.p0;
		Insert =>
			f.seq = u.seq;
			f.uninsert(epsilon, u.p0, u.n);
			f.mod = u.mod;
			up -= u.n;
			# buf = utils->stralloc(BUFSIZE);
			for(i=0; i<u.n; i+=n){
				n = u.n - i;
				if(n > BUFSIZE)
					n = BUFSIZE;
				delta.read(up+i, buf, 0, n);
				f.buf.insert(u.p0+i, buf.s, n);
				for(j=0; j<f.ntext; j++)
					f.text[j].insert(u.p0+i, buf.s, n, FALSE, 0);
			}
			# utils->strfree(buf);
			# buf = nil;
			q0 = u.p0;
			q1 = u.p0+u.n;
		Filename =>
			f.seq = u.seq;
			f.unsetname(epsilon);
			f.mod = u.mod;
			up -= u.n;
			f.name = nil;
			if(u.n == 0)
				f.name = nil;
			else {
				fn0 := utils->stralloc(u.n);
				delta.read(up, fn0, 0, u.n);
				f.name = fn0.s;
				utils->strfree(fn0);
				fn0 = nil;
			}
		* =>
			error(sys->sprint("undo: 0x%ux", u.typex));
			error("");
		}
		delta.delete(up, delta.nc);
	}
	utils->strfree(buf);
	utils->strfree(a);
	buf = nil;
	if(isundo)
		f.seq = 0;
	return (q0, q1);
}

File.reset(f : self ref File)
{
	f.delta.reset();
	f.epsilon.reset();
	f.seq = 0;
}

File.close(f : self ref File)
{
	f.name = nil;
	f.ntext = 0;
	f.text = nil;
	f.buf.close();
	f.delta.close();
	f.epsilon.close();
	editlog->elogclose(f);
	f = nil;
}

File.mark(f : self ref File)
{
	if(f.epsilon.nc)
		f.epsilon.delete(0, f.epsilon.nc);
	f.seq = dat->seq;
}

File.redoseq(f : self ref File): int
{
	u: Undo;
	delta: ref Buffer;

	delta = f.epsilon;
	if(delta.nc == 0)
		return ~0;
	buf := utils->stralloc(Undosize);
	delta.read(delta.nc-Undosize, buf, 0, Undosize);
	u = strtoundo(buf.s);
	utils->strfree(buf);
	return u.seq;
}