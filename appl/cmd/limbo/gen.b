	blocks:		int;			# nesting of blocks while generating code
	zinst:		Inst;
	firstinst:	ref Inst;
	lastinst:	ref Inst;

include "disoptab.m";

addrmode := array[int Rend] of
{
	int Rreg =>	Afp,
	int Rmreg =>	Amp,
	int Roff =>	Aoff,
	int Rnoff =>	Anoff,
	int Rdesc =>	Adesc,
	int Rdescp =>	Adesc,
	int Rconst =>	Aimm,
	int Radr =>	Afpind,
	int Rmadr =>	Ampind,
	int Rpc =>	Apc,
	int Rldt => Aldt,
	* =>		Aerr,
};

wtemp:		ref Decl;
bigtemp:	ref Decl;
ntemp:		int;
retnode:	ref Node;
nilnode:	ref Node;

blockstack:	array of int;
blockdep:	int;
nblocks:	int;
ntoz:	ref Node;

#znode:		Node;

genstart()
{
	d := mkdecl(nosrc, Dlocal, tint);
	d.sym = enter(".ret", 0);
	d.offset = IBY2WD * REGRET;

	retnode = ref znode;
	retnode.op = Oname;
	retnode.addable = Rreg;
	retnode.decl = d;
	retnode.ty = tint;

	zinst.op = INOP;
	zinst.sm = Anone;
	zinst.dm = Anone;
	zinst.mm = Anone;

	firstinst = ref zinst;
	lastinst = firstinst;

	nilnode = ref znode;
	nilnode.op = Oname;
	nilnode.addable = Rmreg;
	nilnode.decl = nildecl;
	nilnode.ty = nildecl.ty;

	blocks = -1;
	blockdep = 0;
	nblocks = 0;
}

#
# manage nested control flow blocks
#
pushblock(): int
{
	if(blockdep >= len blockstack){
		bs := array[blockdep + 32] of int;
		bs[0:] = blockstack;
		blockstack = bs;
	}
	blockstack[blockdep++] = blocks;
	return blocks = nblocks++;
}

repushblock(b: int)
{
	blockstack[blockdep++] = blocks;
	blocks = b;
}

popblock()
{
	blocks = blockstack[blockdep -= 1];
}

tinit()
{
	wtemp = nil;
	bigtemp = nil;
}

tdecls(): ref Decl
{
	for(d := wtemp; d != nil; d = d.next){
		if(d.tref != 1)
			fatal("temporary "+d.sym.name+" has "+string(d.tref-1)+" references");
	}

	for(d = bigtemp; d != nil; d = d.next){
		if(d.tref != 1)
			fatal("temporary "+d.sym.name+" has "+string(d.tref-1)+" references");
	}

	return appdecls(wtemp, bigtemp);
}

talloc(t: ref Type, nok: ref Node): ref Node
{
	ok, d: ref Decl;

	ok = nil;
	if(nok != nil)
		ok = nok.decl;
	if(ok == nil || ok.tref == 0 || tattr[ok.ty.kind].isbig != tattr[t.kind].isbig || ok.ty.align != t.align)
		ok = nil;
	n := ref znode;
	n.op = Oname;
	n.addable = Rreg;
	n.ty = t;
	if(tattr[t.kind].isbig){
		desc := mktdesc(t);
		if(ok != nil && ok.desc == desc){
			ok.tref++;
			ok.refs++;
			n.decl = ok;
			return n;
		}
		for(d = bigtemp; d != nil; d = d.next){
			if(d.tref == 1 && d.desc == desc && d.ty.align == t.align){
				d.tref++;
				d.refs++;
				n.decl = d;
				return n;
			}
		}
		d = mkdecl(nosrc, Dlocal, t);
		d.desc = desc;
		d.tref = 2;
		d.refs = 1;
		d.sym = enter(".b"+string ntemp++, 0);
		d.next = bigtemp;
		bigtemp = d;
		n.decl = d;
		return n;
	}
	if(ok != nil
	&& tattr[ok.ty.kind].isptr == tattr[t.kind].isptr
	&& ok.ty.size == t.size){
		ok.tref++;
		n.decl = ok;
		return n;
	}
	for(d = wtemp; d != nil; d = d.next){
		if(d.tref == 1
		&& tattr[d.ty.kind].isptr == tattr[t.kind].isptr
		&& d.ty.size == t.size
		&& d.ty.align == t.align){
			d.tref++;
			n.decl = d;
			return n;
		}
	}
	d = mkdecl(nosrc, Dlocal, t);
	d.tref = 2;
	d.refs = 1;
	d.sym = enter(".t"+string ntemp++, 0);
	d.next = wtemp;
	wtemp = d;
	n.decl = d;
	return n;
}

tfree(n: ref Node)
{
	if(n == nil || n.decl == nil)
		return;
	d := n.decl;
	if(d.tref == 0)
		return;

	if(d.tref == 1)
		fatal("double free of temporary " + d.sym.name);
	if (--d.tref == 1)
		zcom1(n, nil);

	#
	# nil out any pointers so we don't
	# hang onto references
	#
#
# costs ~7% in instruction count
#	if(d.tref != 1)
#		return;
#	if(!tattr[d.ty.kind].isbig){
#		if(tattr[d.ty.kind].isptr){	# or tmustzero()
#			nilnode.decl.refs++;
#			genmove(lastinst.src, Mas, d.ty, nilnode, n);
#		}
#	}else{
#		if(d.desc.nmap != 0){		# tmustzero() is better
#			zn := ref znode;
#			zn.op = Oname;
#			zn.addable = Rmreg;
#			zn.decl = globalztup(d.ty);
#			zn.ty = d.ty;
#			genmove(lastinst.src, Mas, d.ty, zn, n);
#		}
#	}
}

tfreelater(n: ref Node)
{
	if(n == nil || n.decl == nil)
		return;
	d := n.decl;
	if(d.tref == 0)
		return;

	if(d.tref == 1)
		fatal("double free of temporary " + d.sym.name);
	if (--d.tref == 1){
		nn := mkn(Oname, nil, nil);
		*nn = *n;
		nn.left = ntoz;
		ntoz = nn;
		d.tref++;
	}
}

tfreenow()
{
	nn: ref Node;

	for(n := ntoz; n != nil; n = nn){
		nn = n.left;
		n.left = nil;
		if(n.decl.tref != 2)
			fatal(sprint("bad free of temporary %s", n.decl.sym.name));
		--n.decl.tref;
		zcom1(n, nil);
	}
	ntoz = nil;
}

#
# realloc a temporary after it's been released
#
tacquire(n: ref Node): ref Node
{
	if(n == nil || n.decl == nil)
		return n;
	d := n.decl;
	if(d.tref == 0)
		return n;
	# if(d.tref != 1)
	#	fatal("tacquire ref != 1: "+string d.tref);
	d.tref++;
	return n;
}

trelease(n: ref Node)
{
	if(n == nil || n.decl == nil)
		return;
	d := n.decl;
	if(d.tref == 0)
		return;
	if(d.tref == 1)
		fatal("double release of temporary " + d.sym.name);
	d.tref--;
}

mkinst(): ref Inst
{
	in := lastinst.next;
	if(in == nil){
		in = ref zinst;
		lastinst.next = in;
	}
	lastinst = in;
	in.block = blocks;
	if(blocks < 0)
		fatal("mkinst no block");
	return in;
}

nextinst(): ref Inst
{
	in := lastinst.next;
	if(in != nil)
		return in;
	in = ref zinst;
	lastinst.next = in;
	return in;
}

#
# allocate a node for returning
#
retalloc(n, nn: ref Node): ref Node
{
	if(nn.ty == tnone)
		return nil;
	n = ref znode;
	n.op = Oind;
	n.addable = Radr;
	n.left = dupn(1, n.src, retnode);
	n.ty = nn.ty;
	return n;
}

genrawop(src: Src, op: int, s, m, d: ref Node): ref Inst
{
	in := mkinst();
	in.op = op;
	in.src = src;
	if(s != nil){
		in.s = genaddr(s);
		in.sm = addrmode[int s.addable];
	}
	if(m != nil){
		in.m = genaddr(m);
		in.mm = addrmode[int m.addable];
		if(in.mm == Ampind || in.mm == Afpind)
			fatal("illegal addressing mode in register "+nodeconv(m));
	}
	if(d != nil){
		in.d = genaddr(d);
		in.dm = addrmode[int d.addable];
	}
	return in;
}

genop(src: Src, op: int, s, m, d: ref Node): ref Inst
{
	iop := disoptab[op][opind[d.ty.kind]];
	if(iop == 0)
		fatal("can't deal with op "+opconv(op)+" on "+nodeconv(s)+" "+nodeconv(m)+" "+nodeconv(d)+" in genop");
	if(iop == IMULX || iop == IDIVX)
		return genfixop(src, iop, s, m, d);
	in := mkinst();
	in.op = iop;
	in.src = src;
	if(s != nil){
		in.s = genaddr(s);
		in.sm = addrmode[int s.addable];
	}
	if(m != nil){
		in.m = genaddr(m);
		in.mm = addrmode[int m.addable];
		if(in.mm == Ampind || in.mm == Afpind)
			fatal("illegal addressing mode in register "+nodeconv(m));
	}
	if(d != nil){
		in.d = genaddr(d);
		in.dm = addrmode[int d.addable];
	}
	return in;
}

genbra(src: Src, op: int, s, m: ref Node): ref Inst
{
	t := s.ty;
	if(t == tany)
		t = m.ty;
	iop := disoptab[op][opind[t.kind]];
	if(iop == 0)
		fatal("can't deal with op "+opconv(op)+" on "+nodeconv(s)+" "+nodeconv(m)+" in genbra");
	in := mkinst();
	in.op = iop;
	in.src = src;
	if(s != nil){
		in.s = genaddr(s);
		in.sm = addrmode[int s.addable];
	}
	if(m != nil){
		in.m = genaddr(m);
		in.mm = addrmode[int m.addable];
		if(in.mm == Ampind || in.mm == Afpind)
			fatal("illegal addressing mode in register "+nodeconv(m));
	}
	return in;
}

genchan(src: Src, sz: ref Node, mt: ref Type, d: ref Node): ref Inst
{
	reg: Addr;

	regm := Anone;
	reg.decl = nil;
	reg.reg = 0;
	reg.offset = 0;
	op := chantab[mt.kind];
	if(op == 0)
		fatal("can't deal with op "+string mt.kind+" in genchan");

	case mt.kind{
	Tadt or
	Tadtpick or
	Ttuple =>
		td := mktdesc(mt);
		if(td.nmap != 0){
			op++;		# sleazy
			usedesc(td);
			regm = Adesc;
			reg.decl = mt.decl;
		}else{
			regm = Aimm;
			reg.offset = mt.size;
		}
	}
	in := mkinst();
	in.op = op;
	in.src = src;
	in.s = reg;
	in.sm = regm;
	if(sz != nil){
		in.m = genaddr(sz);
		in.mm = addrmode[int sz.addable];
	}
	if(d != nil){
		in.d = genaddr(d);
		in.dm = addrmode[int d.addable];
	}
	return in;
}

genmove(src: Src, how: int, mt: ref Type, s, d: ref Node): ref Inst
{
	reg: Addr;

	regm := Anone;
	reg.decl = nil;
	reg.reg = 0;
	reg.offset = 0;
	op := movetab[how][mt.kind];
	if(op == 0)
		fatal("can't deal with op "+string how+" on "+nodeconv(s)+" "+nodeconv(d)+" in genmove");

	case mt.kind{
	Tadt or
	Tadtpick or
	Ttuple or
	Texception =>
		if(mt.size == 0 && how == Mas)
			return nil;
		td := mktdesc(mt);
		if(td.nmap != 0){
			op++;		# sleazy
			usedesc(td);
			regm = Adesc;
			reg.decl = mt.decl;
		}else{
			regm = Aimm;
			reg.offset = mt.size;
		}
	}
	in := mkinst();
	in.op = op;
	in.src = src;
	if(s != nil){
		in.s = genaddr(s);
		in.sm = addrmode[int s.addable];
	}
	in.m = reg;
	in.mm = regm;
	if(d != nil){
		in.d = genaddr(d);
		in.dm = addrmode[int d.addable];
	}
	if(s.addable == Rpc)
		in.op = IMOVPC;
	return in;
}

patch(b, dst: ref Inst)
{
	n: ref Inst;

	for(; b != nil; b = n){
		n = b.branch;
		b.branch = dst;
	}
}

getpc(i: ref Inst): int
{
	if(i.pc == 0 && i != firstinst && (firstinst.op != INOOP || i != firstinst.next)){
		do
			i = i.next;
		while(i != nil && i.pc == 0);
		if(i == nil || i.pc == 0)
			fatal("bad instruction in getpc");
	}
	return i.pc;
}

#
# follow all possible paths from n,
# marking reached code, compressing branches, and reclaiming unreached insts
#
reach(in: ref Inst)
{
	foldbranch(in);
	last := in;
	for(in = in.next; in != nil; in = in.next){
		if(in.reach == byte 0)
			last.next = in.next;
		else
			last = in;
	}
	lastinst = last;
}

foldbranch(in: ref Inst)
{
	while(in != nil && in.reach != byte 1){
		in.reach = byte 1;
		if(in.branch != nil)
			while(in.branch.op == IJMP){
				if(in == in.branch || in.branch == in.branch.branch)
					break;
				in.branch = in.branch.branch;
			}
		case in.op{
		IGOTO or
		ICASE or
		ICASEL or
		ICASEC or
		IEXC =>
			foldbranch(in.d.decl.ty.cse.iwild);
			lab := in.d.decl.ty.cse.labs;
			n := in.d.decl.ty.cse.nlab;
			for(i := 0; i < n; i++)
				foldbranch(lab[i].inst);
			if(in.op == IEXC)
				in.op = INOOP;
			return;
		IEXC0 =>
			foldbranch(in.branch);
			in.op = INOOP;
			break;
		IRET or
		IEXIT or
		IRAISE =>
			return;
		IJMP =>
			b := in.branch;
			case b.op{
			ICASE or
			ICASEL or
			ICASEC or
			IRET or
			IEXIT =>
				next := in.next;
				*in = *b;
				in.next = next;
				# b.reach = byte 1;
				continue;
			}
			foldbranch(in.branch);
			return;
		* =>
			if(in.branch != nil)
				foldbranch(in.branch);
		}

		in = in.next;
	}
}

#
# convert the addressable node into an operand
# see the comment for sumark
#
genaddr(n: ref Node): Addr
{
	a: Addr;

	a.reg = 0;
	a.offset = 0;
	a.decl = nil;
	case int n.addable{
	int Rreg =>
		if(n.decl != nil)
			a.decl = n.decl;
		else
			a = genaddr(n.left);
	int Rmreg =>
		if(n.decl != nil)
			a.decl = n.decl;
		else
			a = genaddr(n.left);
	int Rdesc =>
		a.decl = n.ty.decl;
	int Roff or
	int Rnoff =>
		a.decl = n.decl;
	int Rconst =>
		a.offset = int n.c.val;
	int Radr =>
		a = genaddr(n.left);
	int Rmadr =>
		a = genaddr(n.left);
	int Rareg or
	int Ramreg =>
		a = genaddr(n.left);
		if(n.op == Oadd)
			a.reg += int n.right.c.val;
	int Raadr or
	int Ramadr =>
		a = genaddr(n.left);
		if(n.op == Oadd)
			a.offset += int n.right.c.val;
	int Rldt =>
		a.decl = n.decl;
	int Rdescp or
	int Rpc =>
		a.decl = n.decl;
	* =>
		fatal("can't deal with "+nodeconv(n)+" in genaddr");
	}
	return a;
}

sameaddr(n, m: ref Node): int
{
	if(n.addable != m.addable)
		return 0;
	a := genaddr(n);
	b := genaddr(m);
	return a.offset == b.offset && a.reg == b.reg && a.decl == b.decl;
}

resolvedesc(mod: ref Decl, length: int, id: ref Decl): int
{
	last: ref Desc;

	g := gendesc(mod, length, id);
	g.used = 0;
	last = nil;
	for(d := descriptors; d != nil; d = d.next){
		if(!d.used){
			if(last != nil)
				last.next = d.next;
			else
				descriptors = d.next;
			continue;
		}
		last = d;
	}

	g.next = descriptors;
	descriptors = g;

	descid := 0;
	for(d = descriptors; d != nil; d = d.next)
		d.id = descid++;
	if(g.id != 0)
		fatal("bad global descriptor id");

	return descid;
}

resolvemod(m: ref Decl): int
{
	for(id := m.ty.ids; id != nil; id = id.next){
		case id.store{
		Dfn =>
			id.iface.pc = id.pc;
			id.iface.desc = id.desc;
		Dtype =>
			if(id.ty.kind != Tadt)
				break;
			for(d := id.ty.ids; d != nil; d = d.next){
				if(d.store == Dfn){
					d.iface.pc = d.pc;
					d.iface.desc = d.desc;
				}
			}
		}
	}
	# for addiface
	for(id = m.ty.tof.ids; id != nil; id = id.next){
		if(id.store == Dfn){
			if(id.pc == nil)
				id.pc = id.iface.pc;
			if(id.desc == nil)
				id.desc = id.iface.desc;
		}
	}
	return int m.ty.tof.decl.init.c.val;
}

#
# place the Tiface decs in another list
#
resolveldts(d: ref Decl): (ref Decl, ref Decl)
{
	d1, ld1, d2, ld2, n: ref Decl;

	d1 = d2 = nil;
	ld1 = ld2 = nil;
	for( ; d != nil; d = n){
		n = d.next;
		d.next = nil;
		if(d.ty.kind == Tiface){
			if(d2 == nil)
				d2 = d;
			else
				ld2.next = d;
			ld2 = d;
		}
		else{
			if(d1 == nil)
				d1 = d;
			else
				ld1.next = d;
			ld1 = d;
		}
	}
	return (d1, d2);
}

#
# fix up all pc's
# finalize all data offsets
# fix up instructions with offsets too large
#
resolvepcs(inst: ref Inst): int
{
	d: ref Decl;

	pc := 0;
	for(in := inst; in != nil; in = in.next){
		if(in.reach == byte 0 || in.op == INOP)
			fatal("unreachable pc: "+instconv(in));
		if(in.op == INOOP){
			in.pc = pc;
			continue;
		}
		d = in.s.decl;
		if(d != nil){
			if(in.sm == Adesc){
				if(d.desc != nil)
					in.s.offset = d.desc.id;
			}else
				in.s.reg += d.offset;
		}
		r := in.s.reg;
		off := in.s.offset;
		if((in.sm == Afpind || in.sm == Ampind)
		&& (r >= MaxReg || off >= MaxReg))
			fatal("big offset in "+instconv(in));

		d = in.m.decl;
		if(d != nil){
			if(in.mm == Adesc){
				if(d.desc != nil)
					in.m.offset = d.desc.id;
			}else
				in.m.reg += d.offset;
		}
		v := 0;
		case int in.mm{
		int Anone =>
			break;
		int Aimm or
		int Apc or
		int Adesc =>
			v = in.m.offset;
		int Aoff or
		int Anoff =>
			v = in.m.decl.iface.offset;
		int Afp or
		int Amp or
		int Aldt =>
			v = in.m.reg;
			if(v < 0)
				v = 16r8000;
		* =>
			fatal("can't deal with "+instconv(in)+"'s m mode");
		}
		if(v > 16r7fff || v < -16r8000){
			case in.op{
			IALT or
			IINDX =>
				rewritedestreg(in, IMOVW, RTemp);
			* =>
				op := IMOVW;
				if(isbyteinst[in.op])
					op = IMOVB;
				in = rewritesrcreg(in, op, RTemp, pc++);
			}
		}

		d = in.d.decl;
		if(d != nil){
			if(in.dm == Apc)
				in.d.offset = d.pc.pc;
			else
				in.d.reg += d.offset;
		}
		r = in.d.reg;
		off = in.d.offset;
		if((in.dm == Afpind || in.dm == Ampind)
		&& (r >= MaxReg || off >= MaxReg))
			fatal("big offset in "+instconv(in));

		in.pc = pc;
		pc++;
	}
	for(in = inst; in != nil; in = in.next){
		d = in.s.decl;
		if(d != nil && in.sm == Apc)
			in.s.offset = d.pc.pc;
		d = in.d.decl;
		if(d != nil && in.dm == Apc)
			in.d.offset = d.pc.pc;
		if(in.branch != nil){
			in.dm = Apc;
			in.d.offset = in.branch.pc;
		}
	}
	return pc;
}

#
# fixp up a big register constant uses as a source
# ugly: smashes the instruction
#
rewritesrcreg(in: ref Inst, op: int, treg: int, pc: int): ref Inst
{
	a := in.m;
	am := in.mm;
	in.mm = Afp;
	in.m.reg = treg;
	in.m.decl = nil;

	new := ref *in;

	*in = zinst;
	in.src = new.src;
	in.next = new;
	in.op = op;
	in.s = a;
	in.sm = am;
	in.dm = Afp;
	in.d.reg = treg;
	in.pc = pc;
	in.reach = byte 1;
	in.block = new.block;
	return new;
}

#
# fix up a big register constant by moving to the destination
# after the instruction completes
#
rewritedestreg(in: ref Inst, op: int, treg: int): ref Inst
{
	n := ref zinst;
	n.next = in.next;
	in.next = n;
	n.src = in.src;
	n.op = op;
	n.sm = Afp;
	n.s.reg = treg;
	n.d = in.m;
	n.dm = in.mm;
	n.reach = byte 1;
	n.block = in.block;

	in.mm = Afp;
	in.m.reg = treg;
	in.m.decl = nil;

	return n;
}

instconv(in: ref Inst): string
{
	if(in.op == INOP)
		return "nop";
	op := "";
	if(in.op >= 0 && in.op < 256)
		op = instname[in.op];
	if(op == nil)
		op = "?"+string in.op+"?";
	s := "\t" + op + "\t";
	comma := "";
	if(in.sm != Anone){
		s += addrconv(in.sm, in.s);
		comma = ",";
	}
	if(in.mm != Anone){
		s += comma;
		s += addrconv(in.mm, in.m);
		comma = ",";
	}
	if(in.dm != Anone){
		s += comma;
		s += addrconv(in.dm, in.d);
	}

	if(!asmsym)
		return s;

	if(in.s.decl != nil && in.sm == Adesc){
		s += "\t#";
		s += dotconv(in.s.decl);
	}
	if(0 && in.m.decl != nil){
		s += "\t#";
		s += dotconv(in.m.decl);
	}
	if(in.d.decl != nil && in.dm == Apc){
		s += "\t#";
		s += dotconv(in.d.decl);
	}
	s += "\t#";
	s += srcconv(in.src);
	return s;
}

addrconv(am: byte, a: Addr): string
{
	s := "";
	case int am{
	int Anone =>
		break;
	int Aimm or
	int Apc or
	int Adesc =>
		s = "$" + string a.offset;
	int Aoff =>
		s = "$" + string a.decl.iface.offset;
	int Anoff =>
		s = "-$" + string a.decl.iface.offset;
	int Afp =>
		s = string a.reg + "(fp)";
	int Afpind =>
		s = string a.offset + "(" + string a.reg + "(fp))";
	int Amp =>
		s = string a.reg + "(mp)";
	int Ampind =>
		s = string a.offset + "(" + string a.reg + "(mp))";
	int Aldt =>
		s = "$" + string a.reg;
	* =>
		s = string a.offset + "(" + string a.reg + "(?" + string am + "?))";
	}
	return s;
}

genstore(src: Src, n: ref Node, offset: int)
{
	de := mkdecl(nosrc, Dlocal, tint);
	de.sym = nil;
	de.offset = offset;

	d := ref znode;
	d.op = Oname;
	d.addable = Rreg;
	d.decl = de;
	d.ty = tint;
	genrawop(src, IMOVW, n, nil, d);
}

genfixop(src: Src, op: int, s, m, d: ref Node): ref Inst
{
	p, a: int;
	mm: ref Node;

	if(m == nil)
		mm = d;
	else
		mm = m;
	(op, p, a) = fixop(op, mm.ty, s.ty, d.ty);
	if(op == IMOVW){	# just zero d
		s = sumark(mkconst(src, big 0));
		return genrawop(src, op, s, nil, d);
	}
	if(op != IMULX && op != IDIVX)
		genstore(src, sumark(mkconst(src, big a)), STemp);
	genstore(src, sumark(mkconst(src, big p)), DTemp);
	i := genrawop(src, op, s, m, d);
	return i;
}

genfixcastop(src: Src, op: int, s, d: ref Node): ref Inst
{
	p, a: int;
	m: ref Node;

	(op, p, a) = fixop(op, s.ty, tint, d.ty);
	if(op == IMOVW){	# just zero d
		s = sumark(mkconst(src, big 0));
		return genrawop(src, op, s, nil, d);
	}
	m = sumark(mkconst(src, big p));
	if(op != ICVTXX)
		genstore(src, sumark(mkconst(src, big a)), STemp);
	return genrawop(src, op, s, m, d);
}
