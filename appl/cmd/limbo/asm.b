asmentry(e: ref Decl)
{
	if(e == nil)
		return;
	bout.puts("\tentry\t"+string e.pc.pc+", "+string e.desc.id+"\n");
}

asmmod(m: ref Decl)
{
	bout.puts("\tmodule\t");
	bout.puts(m.sym.name);
	bout.putc('\n');
	for(m = m.ty.tof.ids; m != nil; m = m.next){
		case m.store{
		Dglobal =>
			bout.puts("\tlink\t-1,-1,0x"+hex(sign(m), 0)+",\".mp\"\n");
		Dfn =>
			bout.puts("\tlink\t"+string m.desc.id+","+string m.pc.pc+",0x"+string hex(sign(m), 0)+",\"");
			if(m.dot.ty.kind == Tadt)
				bout.puts(m.dot.sym.name+".");
			bout.puts(m.sym.name+"\"\n");
		}
	}
}

asmpath()
{
	bout.puts("\tsource\t\"" + srcpath() + "\"\n");
}

asmdesc(d: ref Desc)
{
	for(; d != nil; d = d.next){
		bout.puts("\tdesc\t$"+string d.id+","+string d.size+",\"");
		e := d.nmap;
		m := d.map;
		for(i := 0; i < e; i++)
			bout.puts(hex(int m[i], 2));
		bout.puts("\"\n");
	}
}

asmvar(size: int, d: ref Decl)
{
	bout.puts("\tvar\t@mp," + string size + "\n");

	for(; d != nil; d = d.next)
		if(d.store == Dglobal && d.init != nil)
			asminitializer(d.offset, d.init);
}

asmldt(size: int, d: ref Decl)
{
	bout.puts("\tldts\t@ldt," + string size + "\n");
	
	for(; d != nil; d = d.next)
		if(d.store == Dglobal && d.init != nil)
			asminitializer(d.offset, d.init);
}

asminitializer(offset: int, n: ref Node)
{
	wild: ref Node;
	c: ref Case;
	lab: Label;
	id: ref Decl;
	i, e: int;

	case n.ty.kind{
	Tbyte =>
		bout.puts("\tbyte\t@mp+"+string offset+","+string(int n.c.val & 16rff)+"\n");
	Tint or
	Tfix =>
		bout.puts("\tword\t@mp+"+string offset+","+string(int n.c.val)+"\n");
	Tbig =>
		bout.puts("\tlong\t@mp+"+string offset+","+string n.c.val+" # "+string bhex(n.c.val, 16)+"\n");
	Tstring =>
		asmstring(offset, n.decl.sym);
	Treal =>
		fs := "";
		ba := array[8] of byte;
		export_real(ba, array[] of {n.c.rval});
		for(i = 0; i < 8; i++)
			fs += hex(int ba[i], 2);
		bout.puts("\treal\t@mp+"+string offset+","+string n.c.rval+" # "+fs+"\n");
	Tadt or
	Tadtpick or
	Ttuple =>
		id = n.ty.ids;
		for(n = n.left; n != nil; n = n.right){
			asminitializer(offset + id.offset, n.left);
			id = id.next;
		}
	Tcase =>
		c = n.ty.cse;
		bout.puts("\tword\t@mp+"+string offset+","+string c.nlab);
		for(i = 0; i < c.nlab; i++){
			lab = c.labs[i];
			bout.puts(","+string(int lab.start.c.val)+","+string(int lab.stop.c.val+1)+","+string(lab.inst.pc));
		}
		if(c.iwild != nil)
			bout.puts(","+string c.iwild.pc+"\n");
		else
			bout.puts(",-1\n");
	Tcasel =>
		c = n.ty.cse;
		bout.puts("\tword\t@mp+"+string offset+","+string c.nlab);
		for(i = 0; i < c.nlab; i++){
			lab = c.labs[i];
			bout.puts(","+string(lab.start.c.val)+","+string(lab.stop.c.val+big 1)+","+string(lab.inst.pc));
		}
		if(c.iwild != nil)
			bout.puts(","+string c.iwild.pc+"\n");
		else
			bout.puts(",-1\n");
	Tcasec =>
		c = n.ty.cse;
		bout.puts("\tword\t@mp+"+string offset+","+string c.nlab+"\n");
		offset += IBY2WD;
		for(i = 0; i < c.nlab; i++){
			lab = c.labs[i];
			asmstring(offset, lab.start.decl.sym);
			offset += IBY2WD;
			if(lab.stop != lab.start)
				asmstring(offset, lab.stop.decl.sym);
			offset += IBY2WD;
			bout.puts("\tword\t@mp+"+string offset+","+string lab.inst.pc+"\n");
			offset += IBY2WD;
		}
		if(c.iwild != nil)
			bout.puts("\tword\t@mp+"+string offset+","+string c.iwild.pc+"\n");
		else
			bout.puts("\tword\t@mp+"+string offset+",-1\n");
	Tgoto =>
		c = n.ty.cse;
		bout.puts("\tword\t@mp+"+string offset);
		bout.puts(","+string(n.ty.size/IBY2WD-1));
		for(i = 0; i < c.nlab; i++)
			bout.puts(","+string c.labs[i].inst.pc);
		if(c.iwild != nil)
			bout.puts(","+string c.iwild.pc);
		bout.puts("\n");
	Tany =>
		break;
	Tarray =>
		bout.puts("\tarray\t@mp+"+string offset+",$"+string n.ty.tof.decl.desc.id+","+string int n.left.c.val+"\n");
		if(n.right == nil)
			break;
		bout.puts("\tindir\t@mp+"+string offset+",0\n");
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
					asminitializer(esz * last, wild);
			}
			last = e;
			e = int c.labs[i].stop.c.val;
			elem := c.labs[i].node.right;
			for(; last <= e; last++)
				asminitializer(esz * last, elem);
		}
		if(wild != nil)
			for(e = int n.left.c.val; last < e; last++)
				asminitializer(esz * last, wild);
		bout.puts("\tapop\n");
	Tiface =>
		if(LDT)
			bout.puts("\tword\t@ldt+"+string offset+","+string int n.c.val+"\n");
		else
			bout.puts("\tword\t@mp+"+string offset+","+string int n.c.val+"\n");
		offset += IBY2WD;
		for(id = n.decl.ty.ids; id != nil; id = id.next){
			offset = align(offset, IBY2WD);
			if(LDT)
				bout.puts("\text\t@ldt+"+string offset+",0x"+string hex(sign(id), 0)+",\"");
			else
				bout.puts("\text\t@mp+"+string offset+",0x"+string hex(sign(id), 0)+",\"");
			dotlen := 0;
			idlen := len array of byte id.sym.name + 1;
			if(id.dot.ty.kind == Tadt){
				dotlen = len array of byte id.dot.sym.name + 1;
				bout.puts(id.dot.sym.name+".");
			}
			bout.puts(id.sym.name+"\"\n");
			offset += idlen + dotlen + IBY2WD;
		}
	* =>
		fatal("can't asm global "+nodeconv(n));
	}
}

asmexc(es: ref Except)
{
	e: ref Except;

	n := 0;
	for(e = es; e != nil; e = e.next)
		n++;
	bout.puts("\texceptions\t" + string n + "\n");
	for(e = es; e != nil; e = e.next){
		if(!int e.p1.reach && !int e.p2.reach)
			continue;
		c := e.c;
		o := e.d.offset;
		if(e.desc != nil)
			id := e.desc.id;
		else
			id = -1;
		bout.puts("\texception\t" + string getpc(e.p1) + ", " + string getpc(e.p2) + ", " + string o + ", " + string id + ", " + string c.nlab + ", " + string e.ne + "\n");
		for(i := 0; i < c.nlab; i++){
			lab := c.labs[i];
			d := lab.start.decl;
			if(lab.start.ty.kind == Texception)
				d = d.init.decl;
			bout.puts("\texctab\t\"" + d.sym.name + "\", " + string lab.inst.pc + "\n");
		}
		if(c.iwild == nil)
			bout.puts("\texctab\t" + "*" + ", " + string -1 + "\n");
		else
			bout.puts("\texctab\t" + "*" + ", " + string c.iwild.pc + "\n");
	}
}

asmstring(offset: int, sym: ref Sym)
{
	bout.puts("\tstring\t@mp+"+string offset+",\"");
	s := sym.name;
	for(i := 0; i < len s; i++){
		c := s[i];
		if(c == '\n')
			bout.puts("\\n");
		else if(c == '\u0000')
			bout.puts("\\z");
		else if(c == '"')
			bout.puts("\\\"");
		else if(c == '\\')
			bout.puts("\\\\");
		else
			bout.putc(c);
	}
	bout.puts("\"\n");
}

asminst(in: ref Inst)
{
	for(; in != nil; in = in.next){
		if(in.op == INOOP)
			continue;
		if(in.pc % 10 == 0){
			bout.putc('#');
			bout.puts(string in.pc);
			bout.putc('\n');
		}
		bout.puts(instconv(in));
		bout.putc('\n');
	}
}
