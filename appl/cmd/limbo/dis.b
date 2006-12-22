
NAMELEN:	con 28;

cache:		array of byte;
ncached:	int;
ndatum:		int;
startoff:	int;
lastoff:	int;
lastkind:	int;

discon(val: int)
{
	if(val >= -64 && val <= 63){
		bout.putb(byte (val & ~16r80));
		return;
	}
	if(val >= -8192 && val <= 8191){
		bout.putb(byte ((val>>8) & ~16rC0 | 16r80));
		bout.putb(byte val);
		return;
	}
	if(val < 0 && ((val >> 29) & 7) != 7
	|| val > 0 && (val >> 29) != 0)
		fatal("overflow in constant 16r"+hex(val, 0));
	bout.putb(byte(val>>24 | 16rC0));
	bout.putb(byte(val>>16));
	bout.putb(byte(val>>8));
	bout.putb(byte val);
}

disword(w: int)
{
	bout.putb(byte(w >> 24));
	bout.putb(byte(w >> 16));
	bout.putb(byte(w >> 8));
	bout.putb(byte w);
}

disdata(kind, n: int)
{
	if(n < DMAX && n != 0)
		bout.putb(byte((kind << DBYTE) | n));
	else{
		bout.putb(byte kind << DBYTE);
		discon(n);
	}
}

dismod(m: ref Decl)
{
	fileoff := bout.seek(big 0, 1);
	name := array of byte m.sym.name;
	n := len name;
	if(n > NAMELEN-1)
		n = NAMELEN-1;
	bout.write(name, n);
	bout.putb(byte 0);
	for(m = m.ty.tof.ids; m != nil; m = m.next){
		case m.store{
		Dglobal =>
			discon(-1);
			discon(-1);
			disword(sign(m));
			bout.puts(".mp");
			bout.putb(byte 0);
		Dfn =>
			discon(m.pc.pc);
			discon(m.desc.id);
			disword(sign(m));
			if(m.dot.ty.kind == Tadt){
				bout.puts(m.dot.sym.name);
				bout.putb(byte '.');
			}
			bout.puts(m.sym.name);
			bout.putb(byte 0);
		* =>
			fatal("unknown kind in dismod: "+declconv(m));
		}
	}
	if(debug['s'])
		print("%bd linkage bytes start %bd\n", bout.seek(big 0, 1) - fileoff, fileoff);
}

dispath()
{
	sp := array of byte srcpath();
	bout.write(sp, len sp);
	bout.putb(byte 0);
}

disentry(e: ref Decl)
{
	if(e == nil){
		discon(-1);
		discon(-1);
		return;
	}
	discon(e.pc.pc);
	discon(e.desc.id);
}

disdesc(d: ref Desc)
{
	fileoff := bout.seek(big 0, 1);
	for(; d != nil; d = d.next){
		discon(d.id);
		discon(d.size);
		discon(d.nmap);
		bout.write(d.map, d.nmap);
	}
	if(debug['s'])
		print("%bd type descriptor bytes start %bd\n", bout.seek(big 0, 1) - fileoff, fileoff);
}

disvar(nil: int, ids: ref Decl)
{
	fileoff := bout.seek(big 0, 1);
	lastkind = -1;
	ncached = 0;
	ndatum = 0;

	for(d := ids; d != nil; d = d.next)
		if(d.store == Dglobal && d.init != nil)
			disdatum(d.offset, d.init);

	disflush(-1, -1, 0);

	bout.putb(byte 0);

	if(debug['s'])
		print("%bd data bytes start %bd\n", bout.seek(big 0, 1) - fileoff, fileoff);
}

disldt(size: int, ds: ref Decl)
{
	if(0){
		discon(size);
		disvar(size, ds);
		return;
	}

	m := 0;
	for(d := ds; d != nil; d = d.next)
		if(d.store == Dglobal && d.init != nil)
			m++;
	discon(m);
	n: ref Node;
	for(d = ds; d != nil; d = d.next){
		if(d.store == Dglobal && d.init != nil){
			n = d.init;
			if(n.ty.kind != Tiface)
				nerror(n, "disldt: not Tiface");
			discon(int n.c.val);
			for(id := n.decl.ty.ids; id != nil; id = id.next){
				disword(sign(id));
				if(id.dot.ty.kind == Tadt){
					s := array of byte id.dot.sym.name;
					bout.write(s, len s);
					bout.putb(byte '.');
				}
				s := array of byte id.sym.name;
				bout.write(s, len s);
				bout.putb(byte 0);
			}
		}
	}
	discon(0);
}

disdatum(offset: int, n: ref Node)
{
	c: ref Case;
	lab: Label;
	id: ref Decl;
	wild: ref Node;
	i, e: int;

	case n.ty.kind{
	Tbyte =>
		disbyte(offset, byte n.c.val);
	Tint or
	Tfix =>
		disint(offset, int n.c.val);
	Tbig =>
		disbig(offset, n.c.val);
	Tstring =>
		disstring(offset, n.decl.sym);
	Treal =>
		disreal(offset, n.c.rval);
	Tadt or
	Tadtpick or
	Ttuple =>
		id = n.ty.ids;
		for(n = n.left; n != nil; n = n.right){
			disdatum(offset + id.offset, n.left);
			id = id.next;
		}
	Tany =>
		break;
	Tcase =>
		c = n.ty.cse;
		disint(offset, c.nlab);
		offset += IBY2WD;
		for(i = 0; i < c.nlab; i++){
			lab = c.labs[i];
			disint(offset, int lab.start.c.val);
			offset += IBY2WD;
			disint(offset, int lab.stop.c.val+1);
			offset += IBY2WD;
			disint(offset, lab.inst.pc);
			offset += IBY2WD;
		}
		if(c.iwild != nil)
			disint(offset, c.iwild.pc);
		else
			disint(offset, -1);
	Tcasel =>
		c = n.ty.cse;
		disint(offset, c.nlab);
		offset += 2*IBY2WD;
		for(i = 0; i < c.nlab; i++){
			lab = c.labs[i];
			disbig(offset, lab.start.c.val);
			offset += IBY2LG;
			disbig(offset, lab.stop.c.val+big 1);
			offset += IBY2LG;
			disint(offset, lab.inst.pc);
			offset += 2*IBY2WD;
		}
		if(c.iwild != nil)
			disint(offset, c.iwild.pc);
		else
			disint(offset, -1);
	Tcasec =>
		c = n.ty.cse;
		disint(offset, c.nlab);
		offset += IBY2WD;
		for(i = 0; i < c.nlab; i++){
			lab = c.labs[i];
			disstring(offset, lab.start.decl.sym);
			offset += IBY2WD;
			if(lab.stop != lab.start)
				disstring(offset, lab.stop.decl.sym);
			offset += IBY2WD;
			disint(offset, lab.inst.pc);
			offset += IBY2WD;
		}
		if(c.iwild != nil)
			disint(offset, c.iwild.pc);
		else
			disint(offset, -1);
	Tgoto =>
		c = n.ty.cse;
		disint(offset, n.ty.size/IBY2WD-1);
		offset += IBY2WD;
		for(i = 0; i < c.nlab; i++){
			disint(offset, c.labs[i].inst.pc);
			offset += IBY2WD;
		}
		if(c.iwild != nil)
			disint(offset, c.iwild.pc);
	Tarray =>
		disflush(-1, -1, 0);
		disdata(DEFA, 1);		# 1 is ignored
		discon(offset);
		disword(n.ty.tof.decl.desc.id);
		disword(int n.left.c.val);

		if(n.right == nil)
			break;

		disdata(DIND, 1);		# 1 is ignored
		discon(offset);
		disword(0);

		c = n.right.ty.cse;
		wild = nil;
		if(c.wild != nil)
			wild = c.wild.right;
		last := 0;
		esz := n.ty.tof.size;
		for(i = 0; i < c.nlab; i++){
			e = int c.labs[i].start.c.val;
			if(wild != nil){
				for(; last < e; last++)
					disdatum(esz * last, wild);
			}
			last = e;
			e = int c.labs[i].stop.c.val;
			elem := c.labs[i].node.right;
			for(; last <= e; last++)
				disdatum(esz * last, elem);
		}
		if(wild != nil)
			for(e = int n.left.c.val; last < e; last++)
				disdatum(esz * last, wild);

		disflush(-1, -1, 0);
		disdata(DAPOP, 1);		# 1 is ignored
		discon(0);
	Tiface =>
		disint(offset, int n.c.val);
		offset += IBY2WD;
		for(id = n.decl.ty.ids; id != nil; id = id.next){
			offset = align(offset, IBY2WD);
			disint(offset, sign(id));
			offset += IBY2WD;

			name: array of byte;
			if(id.dot.ty.kind == Tadt){
				name = array of byte id.dot.sym.name;
				disbytes(offset, name);
				offset += len name;
				disbyte(offset, byte '.');
				offset++;
			}
			name = array of byte id.sym.name;
			disbytes(offset, name);
			offset += len name;
			disbyte(offset, byte 0);
			offset++;
		}
	* =>
		fatal("can't gen global "+nodeconv(n));
	}
}

disexc(es: ref Except)
{
	e: ref Except;

	n := 0;
	for(e = es; e != nil; e = e.next)
		if(int e.p1.reach || int e.p2.reach)
			n++;
	discon(n);
	for(e = es; e != nil; e = e.next){
		if(!int e.p1.reach && !int e.p2.reach)
			continue;
		c := e.c;
		discon(e.d.offset);
		discon(getpc(e.p1));
		discon(getpc(e.p2));
		if(e.desc != nil)
			discon(e.desc.id);
		else
			discon(-1);
		discon(c.nlab|(e.ne<<16));
		for(i := 0; i < c.nlab; i++){
			lab := c.labs[i];
			d := lab.start.decl;
			if(lab.start.ty.kind == Texception)
				d = d.init.decl;
			bout.puts(d.sym.name);
			bout.putb(byte 0);
			discon(lab.inst.pc);
		}
		if(c.iwild == nil)
			discon(-1);
		else
			discon(c.iwild.pc);
	}
	discon(0);
}

disbyte(off: int, v: byte)
{
	disflush(DEFB, off, 1);
	cache[ncached++] = v;
	ndatum++;
}

disbytes(off: int, v: array of byte)
{
	n := len v;
	disflush(DEFB, off, n);
	cache[ncached:] = v;
	ncached += n;
	ndatum += n;
}

disint(off, v: int)
{
	disflush(DEFW, off, IBY2WD);
	cache[ncached++] = byte(v >> 24);
	cache[ncached++] = byte(v >> 16);
	cache[ncached++] = byte(v >> 8);
	cache[ncached++] = byte(v);
	ndatum++;
}

disbig(off: int, v: big)
{
	disflush(DEFL, off, IBY2LG);
	iv := int(v >> 32);
	cache[ncached++] = byte(iv >> 24);
	cache[ncached++] = byte(iv >> 16);
	cache[ncached++] = byte(iv >> 8);
	cache[ncached++] = byte(iv);
	iv = int v;
	cache[ncached++] = byte(iv >> 24);
	cache[ncached++] = byte(iv >> 16);
	cache[ncached++] = byte(iv >> 8);
	cache[ncached++] = byte(iv);
	ndatum++;
}

disreal(off: int, v: real)
{
	disflush(DEFF, off, IBY2LG);
	export_real(cache[ncached:ncached+8], array[] of {v});
	ncached += IBY2LG;
	ndatum++;
}

disstring(offset: int, sym: ref Sym)
{
	disflush(-1, -1, 0);
	d := array of byte sym.name;
	disdata(DEFS, len d);
	discon(offset);
	bout.write(d, len d);
}

disflush(kind, off, size: int)
{
	if(kind != lastkind || off != lastoff){
		if(lastkind != -1 && ncached){
			disdata(lastkind, ndatum);
			discon(startoff);
			bout.write(cache, ncached);
		}
		startoff = off;
		lastkind = kind;
		ncached = 0;
		ndatum = 0;
	}
	lastoff = off + size;
	while(kind >= 0 && ncached + size >= len cache){
		c := array[ncached + 1024] of byte;
		c[0:] = cache;
		cache = c;
	}
}

dismode := array[int Aend] of
{
	int Aimm =>	byte AIMM,
	int Amp =>	byte AMP,
	int Ampind =>	byte(AMP|AIND),
	int Afp =>	byte AFP,
	int Afpind =>	byte(AFP|AIND),
	int Apc =>	byte AIMM,
	int Adesc =>	byte AIMM,
	int Aoff =>	byte AIMM,
	int Anoff =>	byte AIMM,
	int Aerr =>	byte AXXX,
	int Anone =>	byte AXXX,
	int Aldt =>	byte AIMM,
};

disregmode := array[int Aend] of
{
	int Aimm =>	byte AXIMM,
	int Amp =>	byte AXINM,
	int Ampind =>	byte AXNON,
	int Afp =>	byte AXINF,
	int Afpind =>	byte AXNON,
	int Apc =>	byte AXIMM,
	int Adesc =>	byte AXIMM,
	int Aoff =>	byte AXIMM,
	int Anoff =>	byte AXIMM,
	int Aerr =>	byte AXNON,
	int Anone =>	byte AXNON,
	int Aldt =>	byte AXIMM,
};

MAXCON: con 4;
MAXADDR: con 2*MAXCON;
MAXINST: con 3*MAXADDR+2;
NIBUF: con 1024;

ibuf:	array of byte;
nibuf:	int;

disinst(in: ref Inst)
{
	fileoff := bout.seek(big 0, 1);
	ibuf = array[NIBUF] of byte;
	nibuf = 0;
	for(; in != nil; in = in.next){
		if(in.op == INOOP)
			continue;
		if(nibuf >= NIBUF-MAXINST){
			bout.write(ibuf, nibuf);
			nibuf = 0;
		}
		ibuf[nibuf++] = byte in.op;
		o := dismode[int in.sm] << SRC;
		o |= dismode[int in.dm] << DST;
		o |= disregmode[int in.mm];
		ibuf[nibuf++] = o;
		if(in.mm != Anone)
			disaddr(in.mm, in.m);
		if(in.sm != Anone)
			disaddr(in.sm, in.s);
		if(in.dm != Anone)
			disaddr(in.dm, in.d);
	}
	if(nibuf > 0)
		bout.write(ibuf, nibuf);
	ibuf = nil;

	if(debug['s'])
		print("%bd instruction bytes start %bd\n", bout.seek(big 0, 1) - fileoff, fileoff);
}

disaddr(m: byte, a: Addr)
{
	val := 0;
	case int m{
	int Aimm or
	int Apc or
	int Adesc =>
		val = a.offset;
	int Aoff =>
		val = a.decl.iface.offset;
	int Anoff =>
		val = -(a.decl.iface.offset+1);
	int Afp or
	int Amp or
	int Aldt =>
		val = a.reg;
	int Afpind or
	int Ampind =>
		disbcon(a.reg);
		val = a.offset;
	}
	disbcon(val);
}

disbcon(val: int)
{
	if(val >= -64 && val <= 63){
		ibuf[nibuf++] = byte(val & ~16r80);
		return;
	}
	if(val >= -8192 && val <= 8191){
		ibuf[nibuf++] = byte(val>>8 & ~16rC0 | 16r80);
		ibuf[nibuf++] = byte val;
		return;
	}
	if(val < 0 && ((val >> 29) & 7) != 7
	|| val > 0 && (val >> 29) != 0)
		fatal("overflow in constant 16r"+hex(val, 0));
	ibuf[nibuf++] = byte(val>>24 | 16rC0);
	ibuf[nibuf++] = byte(val>>16);
	ibuf[nibuf++] = byte(val>>8);
	ibuf[nibuf++] = byte val;
}
