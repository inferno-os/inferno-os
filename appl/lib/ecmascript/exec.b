exec(ex: ref Exec, code: ref Code): Completion
{
	ssp := ex.sp;

	r := estmt(ex, code, 0, code.npc);

	if(r.kind == CThrow)
		ex.sp = ssp;

	if(ssp != ex.sp)
		runtime(ex, InternalError, "internal error: exec stack not balanced");

	if(r.lab != nil)
		runtime(ex, InternalError, "internal error: label out of stack");
	return r;
}

estmt(ex: ref Exec, code: ref Code, pc, epc: int): Completion
{
	e: ref Ref;
	ev: ref Val;
	k, apc, pc2, apc2, pc3, apc3, c: int;
	lab: string;
	labs: list of string;

	osp := ex.sp;

{
	v : ref Val = nil;
	k1 := CNormal;
	while(pc < epc){
		v1 : ref Val = nil;

		labs = nil;
		op := int code.ops[pc++];
		while(op == Llabel){
			(pc, c) = getconst(code.ops, pc);
			labs = code.strs[c] :: labs;
			op = int code.ops[pc++];
		}
		if(debug['e'] > 1)
			print("estmt(pc %d, sp %d) %s\n", pc-1, ex.sp, tokname(op));
		case op {
		Lbreak =>
			return (CBreak, v, nil);
		Lcontinue =>
			return (CContinue, v, nil);
		Lbreaklab =>
			(pc, c) = getconst(code.ops, pc);
			return (CBreak, v, code.strs[c]);
		Lcontinuelab =>
			(pc, c) = getconst(code.ops, pc);
			return (CContinue, v, code.strs[c]);
		Lreturn =>
			(pc, v) = eexpval(ex, code, pc, code.npc);
			return (CReturn, v, nil);
		'{' =>
			(pc, apc) = getjmp(code.ops, pc);
			(k1, v1, lab) = estmt(ex, code, pc, apc);
			pc = apc;
		Lif =>
			(pc, apc) = getjmp(code.ops, pc);
			(pc, ev) = eexpval(ex, code, pc, apc);
			(pc, apc) = getjmp(code.ops, pc);
			(pc2, apc2) = getjmp(code.ops, apc);
			if(toBoolean(ex, ev) != false)
				(k1, v1, lab) = estmt(ex, code, pc, apc);
			else if(pc2 != apc2)
				(k1, v1, lab) = estmt(ex, code, pc2, apc2);
			pc = apc2;
		Lwhile =>
			(pc, apc) = getjmp(code.ops, pc);
			(pc2, apc2) = getjmp(code.ops, apc);
			for(;;){
				(nil, ev) = eexpval(ex, code, pc, apc);
				if(toBoolean(ex, ev) == false)
					break;
				(k, v1, lab) = estmt(ex, code, pc2, apc2);
				if(v1 != nil)
					v = v1;
				if(k == CBreak || k == CContinue){
					if(initlabs(lab, labs)){
						if(k == CBreak)
							break;
						else
							continue;
					}
					else
						return (k, v1, lab);
				}
				if(k == CReturn || k == CThrow)
					return (k, v1, nil);
			}
			pc = apc2;
		Ldo =>
			(pc, apc) = getjmp(code.ops, pc);
			(pc2, apc2) = getjmp(code.ops, apc);
			for(;;){
				(k, v1, lab) = estmt(ex, code,  pc, apc);
				if(v1 != nil)
					v = v1;
				if(k == CBreak || k == CContinue){
					if(initlabs(lab, labs)){
						if(k == CBreak)
							break;
						else
							continue;
					}
					else
						return (k, v1, lab);
				}
				if(k == CReturn || k == CThrow)
					return (k, v1, nil);
				(nil, ev) = eexpval(ex, code, pc2, apc2);
				if(toBoolean(ex, ev) == false)
					break;
			}
			pc = apc2;
		Lfor or
		Lforvar =>
			(pc, apc) = getjmp(code.ops, pc);
			(pc, nil) = eexpval(ex, code, pc, apc);
			(pc, apc) = getjmp(code.ops, pc);
			(pc2, apc2) = getjmp(code.ops, apc);
			(pc3, apc3) = getjmp(code.ops, apc2);
			for(;;){
				(nil, e) = eexp(ex, code, pc, apc);
				if(e != nil && toBoolean(ex, getValue(ex, e)) == false)
					break;
				(k, v1, lab) = estmt(ex, code, pc3, apc3);
				if(v1 != nil)
					v = v1;
				if(k == CBreak || k == CContinue){
					if(initlabs(lab, labs)){
						if(k == CBreak)
							break;
						else
							continue;
					}
					else
						return (k, v1, lab);
				}
				if(k == CReturn || k == CThrow)
					return (k, v1, nil);
				eexpval(ex, code, pc2, apc2);
			}
			pc = apc3;
		Lforin or
		Lforvarin =>
			(pc, apc) = getjmp(code.ops, pc);
			(pc2, apc2) = getjmp(code.ops, apc);
			(pc3, apc3) = getjmp(code.ops, apc2);
			if(op == Lforvarin){
				(nil, nil) = eexp(ex, code, pc, apc);
				# during for only evaluate the id, not the initializer
				apc = pc + 1;
			}
			(nil, ev) = eexpval(ex, code, pc2, apc2);
			bo := toObject(ex, ev);

			#
			# note this won't enumerate host properties
			#
			enum:
			for(o := bo; o != nil; o = o.prototype){
				if(o.host != nil && o.host != me)
					continue;
				for(i := 0; i < len o.props; i++){
					if(o.props[i] == nil
					|| (o.props[i].attr & DontEnum)
					|| propshadowed(bo, o, o.props[i].name))
						continue;
					(nil, e) = eexp(ex, code, pc, apc);
					putValue(ex, e, strval(o.props[i].name));
					(k, v1, lab) = estmt(ex, code, pc3, apc3);
					if(v1 != nil)
						v = v1;
					if(k == CBreak || k == CContinue){
						if(initlabs(lab, labs)){
							if(k == CBreak)
								break enum;
							else
								continue enum;
						}
						else
							return (k, v1, lab);
					}
					if(k == CReturn || k == CThrow)
						return (k, v1, nil);
				}
			}
			pc = apc3;
		Lwith =>
			(pc, apc) = getjmp(code.ops, pc);
			(pc, ev) = eexpval(ex, code, pc, apc);
			pushscope(ex, toObject(ex, ev));
			(pc, apc) = getjmp(code.ops, pc);
			(k1, v1, lab) = estmt(ex, code, pc, apc);
			popscope(ex);
			pc = apc;
		';' =>
			;
		Lvar =>
			(pc, apc) = getjmp(code.ops, pc);
			(pc, nil) = eexp(ex, code, pc, apc);
		Lswitch =>
			(pc, apc) = getjmp(code.ops, pc);
			(pc, ev) = eexpval(ex, code, pc, apc);
			(pc, apc) = getjmp(code.ops, pc);
			(k1, v1, lab) = ecaseblk(ex, code, ev, pc, apc, labs);
			pc = apc;
		Lthrow =>
			(pc, v) = eexpval(ex, code, pc, code.npc);
			ex.error = toString(ex, v);
			return (CThrow, v, nil);
		Lprint =>
			(pc, v1) = eexpval(ex, code, pc, code.npc);
			print("%s\n", toString(ex, v1));
		Ltry =>
			(pc, apc) = getjmp(code.ops, pc);
			(k1, v1, lab) = estmt(ex, code,  pc, apc);
			(kc, vc) := (k1, v1);
			(pc, apc) = getjmp(code.ops, apc);
			if(pc != apc){
				(pc, c) = getconst(code.ops, ++pc);
				if(k1 == CThrow){
					o := mkobj(ex.objproto, "Object");
					valinstant(o, DontDelete, code.strs[c], v1);
					pushscope(ex, o);
					(k1, v1, lab) = estmt(ex, code, pc, apc);
					popscope(ex);
					if(k1 != CNormal)
						(kc, vc) = (k1, v1);
				}
			}
			(pc, apc) = getjmp(code.ops, apc);
			if(pc != apc){
				(k, v, lab) = estmt(ex, code, pc, apc);
				if(k == CNormal)
					(k1, v1) = (kc, vc);
				else
					(k1, v1) = (k, v);
			}
			pc = apc;
		* =>
			(pc, e) = eexp(ex, code, pc-1, code.npc);
			if(e != nil)
				v1 = getValue(ex, e);
			if(debug['v'])
				print("%s\n", toString(ex, v1));
		}

		if(v1 != nil)
			v = v1;
		if(k1 == CBreak && lab != nil && inlabs(lab, labs))
			(k1, lab) = (CNormal, nil);
		if(k1 != CNormal)
			return (k1, v, lab);
	}
	return (CNormal, v, nil);
}
exception{
	"throw" =>
		ex.sp = osp;
		return (CThrow, ex.errval, nil);
}
}

ecaseblk(ex : ref Exec, code : ref Code, sv : ref Val, pc, epc : int, labs: list of string) : Completion
{	defpc, nextpc, clausepc, apc : int;
	ev : ref Val;
	lab: string;

	k := CNormal;
	v := undefined;
	matched := 0;

	(pc, defpc) = getjmp(code.ops, pc);
	clausepc = pc;
	(pc, nextpc) = getjmp(code.ops, pc);
	for (; pc <= epc; (clausepc, (pc, nextpc)) = (nextpc, getjmp(code.ops, nextpc))) {
		if (nextpc == epc) {
			if (matched || defpc == epc)
				break;
			# do the default
			matched = 1;
			nextpc = defpc;
			continue;
		}
		if (!matched && clausepc == defpc)
			# skip default case - still scanning guards
			continue;
		if (clausepc != defpc) {
			# only case clauses have guard exprs
			(pc, apc) = getjmp(code.ops, pc);
			if (matched)
				pc = apc;
			else {
				(pc, ev) = eexpval(ex, code, pc, apc);
				if (identical(sv, ev))
					matched = 1;
				else
					continue;
			}
		}
		(k, v, lab) = estmt(ex, code, pc, nextpc);
		if(k == CBreak && initlabs(lab, labs))
			return (CNormal, v, nil);
		if(k == CBreak || k == CContinue || k == CReturn || k == CThrow)
			return (k, v, lab);
	}
	return (k, v, lab);
}

identical(v1, v2 : ref Val) : int
{
	if (v1.ty != v2.ty)
		return 0;
	ret := 0;
	case v1.ty{
	TUndef or
	TNull =>
		ret = 1;
	TNum =>
		if(v1.num == v2.num)
			ret = 1;
	TBool =>
		if(v1 == v2)
			ret = 1;
	TStr =>
		if(v1.str == v2.str)
			ret = 1;
	TObj =>
		if(v1.obj == v2.obj)
			ret = 1;
	TRegExp =>
		if(v1.rev == v2.rev)
			ret = 1;
	}
	return ret;
}

eexpval(ex: ref Exec, code: ref Code, pc, epc: int): (int, ref Val)
{
	e: ref Ref;

	(pc, e) = eexp(ex, code, pc, epc);
	if(e == nil)
		v := undefined;
	else
		v = getValue(ex, e);
	return (pc, v);
}

eexp(ex: ref Exec, code: ref Code, pc, epc: int): (int, ref Ref)
{
	o, th: ref Obj;
	a1: ref Ref;
	v, v1, v2: ref Val;
	s: string;
	r1, r2: real;
	c, apc, i1, i2: int;

	savesp := ex.sp;
out:	while(pc < epc){
		op := int code.ops[pc++];
		if(debug['e'] > 1){
			case op{
			Lid or
			Lstr or
			Lregexp =>
				(nil, c) = getconst(code.ops, pc);
				print("eexp(pc %d, sp %d) %s '%s'\n", pc-1, ex.sp, tokname(op), code.strs[c]);
			Lnum =>
				(nil, c) = getconst(code.ops, pc);
				print("eexp(pc %d, sp %d) %s '%g'\n", pc-1, ex.sp, tokname(op), code.nums[c]);
			* =>
				print("eexp(pc %d, sp %d) %s\n", pc-1, ex.sp, tokname(op));
			}
		}
		case op{
		Lthis =>
			v1 = objval(ex.this);
		Lnum =>
			(pc, c) = getconst(code.ops, pc);
			v1 = numval(code.nums[c]);
		Lstr =>
			(pc, c) = getconst(code.ops, pc);
			v1 = strval(code.strs[c]);
		Lregexp =>
			(pc, c) = getconst(code.ops, pc);
			(p, f) := rsplit(code.strs[c]);
			o = nregexp(ex, nil, array[] of { strval(p), strval(f) });
			v1 = objval(o);
			# v1 = regexpval(p, f, 0);
		Lid =>
			(pc, c) = getconst(code.ops, pc);
			epush(ex, esprimid(ex, code.strs[c]));
			continue;
		Lnoval =>
			v1 = undefined;
		'.' =>
			a1 = epop(ex);
			v1 = epopval(ex);
			epush(ex, ref Ref(1, nil, toObject(ex, v1), a1.name));
			continue;
		'[' =>
			v2 = epopval(ex);
			v1 = epopval(ex);
			epush(ex, ref Ref(1, nil, toObject(ex, v1), toString(ex, v2)));
			continue;
		Lpostinc or
		Lpostdec =>
			a1 = epop(ex);
			r1 = toNumber(ex, getValue(ex, a1));
			v1 = numval(r1);
			if(op == Lpostinc)
				r1++;
			else
				r1--;
			putValue(ex, a1, numval(r1));
		Linc or
		Ldec or
		Lpreadd or
		Lpresub =>
			a1 = epop(ex);
			r1 = toNumber(ex, getValue(ex, a1));
			case op{
			Linc =>
				r1++;
			Ldec =>
				r1--;
			Lpresub =>
				r1 = -r1;
			}
			v1 = numval(r1);
			if(op == Linc || op == Ldec)
				putValue(ex, a1, v1);
		'~' =>
			v = epopval(ex);
			i1 = toInt32(ex, v);
			i1 = ~i1;
			v1 = numval(real i1);
		'!' =>
			v = epopval(ex);
			v1 = toBoolean(ex, v);
			if(v1 == true)
				v1 = false;
			else
				v1 = true;
		Ltypeof =>
			a1 = epop(ex);
			if(a1.isref && getBase(ex, a1) == nil)
				s = "undefined";
			else case (v1 = getValue(ex, a1)).ty{
			TUndef =>
				s = "undefined";
			TNull =>
				s = "object";
			TBool =>
				s = "boolean";
			TNum =>
				s = "number";
			TStr =>
				s = "string";
			TObj =>
				if(v1.obj.call != nil)
					s = "function";
				else
					s = "object";
			TRegExp =>
				s = "regexp";
			}
			v1 = strval(s);
		Ldelete =>
			a1 = epop(ex);
			o = getBase(ex, a1);
			s = getPropertyName(ex, a1);
			if(o != nil)
				esdelete(ex, o, s, 0);
			v1 = undefined;
		Lvoid =>
			epopval(ex);
			v = undefined;
		'*' or
		'/' or
		'%' or
		'-' =>
			v2 = epopval(ex);
			a1 = epop(ex);
			r1 = toNumber(ex, getValue(ex, a1));
			r2 = toNumber(ex, v2);
			case op{
			'*' =>
				r1 = r1 * r2;
			'/' =>
				r1 = r1 / r2;
			'%' =>
				r1 = fmod(r1, r2);
			'-' =>
				r1 = r1 - r2;
			}
			v1 = numval(r1);
		'+' =>
			v2 = epopval(ex);
			a1 = epop(ex);
			v1 = toPrimitive(ex, getValue(ex, a1), NoHint);
			v2 = toPrimitive(ex, v2, NoHint);
			if(v1.ty == TStr || v2.ty == TStr)
				v1 = strval(toString(ex, v1)+toString(ex, v2));
			else
				v1 = numval(toNumber(ex, v1)+toNumber(ex, v2));
		Llsh or
		Lrsh or
		Lrshu or
		'&' or
		'^' or
		'|' =>
			v2 = epopval(ex);
			a1 = epop(ex);
			i1 = toInt32(ex, getValue(ex, a1));
			i2 = toInt32(ex, v2);
			case op{
			Llsh =>
				i1 <<= i2 & 16r1f;
			Lrsh =>
				i1 >>= i2 & 16r1f;
			Lrshu =>
				i1 = int (((big i1) & 16rffffffff) >> (i2 & 16r1f));
			'&' =>
				i1 &= i2;
			'|' =>
				i1 |= i2;
			'^' =>
				i1 ^= i2;
			}
			v1 = numval(real i1);
		'=' or
		Las =>
			v1 = epopval(ex);
			a1 = epop(ex);
			putValue(ex, a1, v1);
		'<' or
		'>' or
		Lleq or
		Lgeq =>
			v2 = epopval(ex);
			v1 = epopval(ex);
			if(op == '>' || op == Lleq){
				v = v1;
				v1 = v2;
				v2 = v;
			}
			v1 = toPrimitive(ex, v1, TNum);
			v2 = toPrimitive(ex, v2, TNum);
			if(v1.ty == TStr && v2.ty == TStr){
				if(v1.str < v2.str)
					v1 = true;
				else
					v1 = false;
			}else{
				r1 = toNumber(ex, v1);
				r2 = toNumber(ex, v2);
				if(isnan(r1) || isnan(r2))
					v1 = undefined;
				else if(r1 < r2)
					v1 = true;
				else
					v1 = false;
			}
			if(op == Lgeq || op == Lleq){
				if(v1 == false)
					v1 = true;
				else
					v1 = false;
			}
		Lin =>
			v2 = epopval(ex);
			v1 = epopval(ex);
			if(v2.ty != TObj)
				runtime(ex, TypeError, "rhs of 'in' not an object");
			s = toString(ex, v1);
			v1 = eshasproperty(ex, v2.obj, s, 0);
		Linstanceof =>
			v2 = epopval(ex);
			v1 = epopval(ex);
			if(v2.ty != TObj)
				runtime(ex, TypeError, "rhs of 'instanceof' not an object");
			if(!isfuncobj(v2.obj))
				runtime(ex, TypeError, "rhs of 'instanceof' not a function");
			if(v1.ty != TObj)
				v1 = false;
			else{
				v2 = esget(ex, v2.obj, "prototype", 0);
				if(v2.ty != TObj)
					runtime(ex, TypeError, "prototype value not an object");
				o = v2.obj;
				for(p := v1.obj.prototype; p != nil; p = p.prototype){
					if(p == o){
						v1 = true;
						break;
					}
				}
				if(p == nil)
					v1 = false;
			}
		Leq or
		Lneq or
		Lseq or
		Lsne =>
			strict := op == Lseq || op == Lsne;
			v2 = epopval(ex);
			v1 = epopval(ex);
			v = false;
			while(v1.ty != v2.ty){
				if(strict)
					break;
				if(isnull(v1) && v2 == undefined
				|| v1 == undefined && isnull(v2))
					v1 = v2;
				else if(v1.ty == TNum && v2.ty == TStr)
					v2 = numval(toNumber(ex, v2));
				else if(v1.ty == TStr && v2.ty == TNum)
					v1 = numval(toNumber(ex, v1));
				else if(v1.ty == TBool)
					v1 = numval(toNumber(ex, v1));
				else if(v2.ty == TBool)
					v2 = numval(toNumber(ex, v2));
				else if(v2.ty == TObj && (v1.ty == TStr || v1.ty == TNum))
					v2 = toPrimitive(ex, v2, NoHint);
				else if(v1.ty == TObj && (v2.ty == TStr || v2.ty == TNum))
					v1 = toPrimitive(ex, v1, NoHint);
				else{
					v1 = true;
					v2 = false;
				}
			}
			if(v1.ty != v2.ty)
				v = false;
			else{
				case v1.ty{
				TUndef or
				TNull =>
					v = true;
				TNum =>
					if(v1.num == v2.num)
						v = true;
				TBool =>
					if(v1 == v2)
						v = true;
				TStr =>
					if(v1.str == v2.str)
						v = true;
				TObj =>
					if(v1.obj == v2.obj)
						v = true;
				TRegExp =>
					if(v1.rev.p == v2.rev.p && v1.rev.f == v2.rev.f)
						v = true;
				}
			}
			if(op == Lneq || op == Lsne){
				if(v == false)
					v = true;
				else
					v = false;
			}
			v1 = v;
		Landand =>
			v1 = epopval(ex);
			(pc, apc) = getjmp(code.ops, pc);
			if(toBoolean(ex, v1) != false){
				(pc, a1) = eexp(ex, code, pc, apc);
				v1 = getValue(ex, a1);
			}
			pc = apc;
		Loror =>
			v1 = epopval(ex);
			(pc, apc) = getjmp(code.ops, pc);
			if(toBoolean(ex, v1) != true){
				(pc, a1) = eexp(ex, code, pc, apc);
				v1 = getValue(ex, a1);
			}
			pc = apc;
		'?' =>
			v1 = epopval(ex);
			(pc, apc) = getjmp(code.ops, pc);
			v1 = toBoolean(ex, v1);
			if(v1 == true)
				(pc, a1) = eexp(ex, code, pc, apc);
			pc = apc;
			(pc, apc) = getjmp(code.ops, pc);
			if(v1 != true)
				(pc, a1) = eexp(ex, code, pc, apc);
			pc = apc;
			v1 = getValue(ex, a1);
		Lasop =>
			a1 = epop(ex);
			epush(ex, a1);
			v1 = getValue(ex, a1);
		Lgetval =>
			v1 = epopval(ex);
		',' =>
			v1 = epopval(ex);
			epop(ex);
			# a1's value already gotten by Lgetval
		'(' or
		')' =>
			continue;
		Larrinit =>
			o = narray(ex, nil, nil);
			(pc, c) = getconst(code.ops, pc);
			esput(ex, o, "length", numval(real c), 0);
			c = ex.sp-c;
			for(sp := c; sp < ex.sp; sp++){
				v = getValue(ex, ex.stack[sp]);
				if(v != undefined)
					esput(ex, o, string (sp-c), v, 0);
			}
			ex.sp = c;
			v1 = objval(o);
		Lobjinit =>
			o = nobj(ex, nil, nil);
			(pc, c) = getconst(code.ops, pc);
			c = ex.sp-2*c;
			for(sp := c; sp < ex.sp; sp += 2){
				v = getValue(ex, ex.stack[sp]);
				if(isnum(v) || isstr(v))
					p := toString(ex, v);
				else
					p = ex.stack[sp].name;
				v = getValue(ex, ex.stack[sp+1]);
				esput(ex, o, p, v, 0);
			}
			ex.sp = c;
			v1 = objval(o);
		Lcall or
		Lnewcall =>
			(pc, c) = getconst(code.ops, pc);
			args := array[c] of ref Val;
			c = ex.sp - c;
			for(sp := c; sp < ex.sp; sp++)
				args[sp-c] = getValue(ex, ex.stack[sp]);
			ex.sp = c;
			a1 = epop(ex);
			v = getValue(ex, a1);
			o = getobj(v);
			if(op == Lcall){
				if(o == nil || o.call == nil)
					runtime(ex, TypeError, "can only call function objects ("+a1.name+")");
				th = nil;
				if(a1.isref){
					th = getBase(ex, a1);
					if(th != nil && isactobj(th))
						th = nil;
				}

				# have to execute functions in the same context as they
				# were defined, but need to use current stack.
				if (o.call.ex == nil)
					a1 = escall(ex, v.obj, th, args, 0);
				else {
					fnex := ref *o.call.ex;
					fnex.stack = ex.stack;
					fnex.sp = ex.sp;
					fnex.scopechain = fnex.global :: nil;
					# drop ref to stack to avoid array duplication should stack grow
					ex.stack = nil;
					osp := ex.sp;
					# can get an exception here that corrupts ex etc.
#aardvark:=99;
#test:=99;
# zebra:=99;
					{
						a1 = escall(fnex, v.obj, th, args, 0);
					}
					exception e{
						"throw" =>
							# copy up error so as it gets reported properly
							ex.error = fnex.error;
							ex.errval = fnex.errval;
							ex.stack = fnex.stack;
							ex.sp = osp;
#							raise e;
							raise "throw";
					}
					# restore stack, sp is OK as escall() ensures that stack is balanced
					ex.stack = fnex.stack;
				}
			}else{
				if(o == nil || o.construct == nil)
					runtime(ex, TypeError, "new must be given a constructor object");
				a1 = valref(objval(esconstruct(ex, o, args)));
			}
			epush(ex, a1);
			args = nil;
			continue;
		Lnew =>
			v = epopval(ex);
			o = getobj(v);
			if(o == nil || o.construct == nil)
				runtime(ex, TypeError, "new must be given a constructor object");
			v1 = objval(esconstruct(ex, o, nil));
		Lfunction =>
			(pc, c) = getconst(code.ops, pc);
			v1 = objval(code.fexps[c]);
		';' =>
			break out;
		* =>
			fatal(ex, sprint("eexp: unknown op %s\n", tokname(op)));
		}
		epushval(ex, v1);
	}

	if(savesp == ex.sp)
		return (pc, nil);

	if(savesp != ex.sp-1)
		print("unbalanced stack in eexp: %d %d\n", savesp, ex.sp);
	return (pc, epop(ex));
}

epushval(ex: ref Exec, v: ref Val)
{
	epush(ex, valref(v));
}

epush(ex: ref Exec, r: ref Ref)
{
	if(ex.sp >= len ex.stack){
		st := array[2 * len ex.stack] of ref Ref;
		st[:] = ex.stack;
		ex.stack = st;
	}
	ex.stack[ex.sp++] = r;
}

epop(ex: ref Exec): ref Ref
{
	if(ex.sp == 0)
		fatal(ex, "popping too far off the estack\n");
	return ex.stack[--ex.sp];
}

epopval(ex: ref Exec): ref Val
{
	if(ex.sp == 0)
		fatal(ex, "popping too far off the estack\n");
	return getValue(ex, ex.stack[--ex.sp]);
}

inlabs(lab: string, labs: list of string): int
{
	for(l := labs; l != nil; l = tl l)
		if(hd l == lab)
			return 1;
	return 0;
}

initlabs(lab: string, labs: list of string): int
{
	return lab == nil || inlabs(lab, labs);
}
