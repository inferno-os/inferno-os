strhas(s: string, c: int): ref Val
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return true;
	return false;
}

rsplit(r: string): (string, string)
{
	esc := 0;
	i := 1;	# skip '/'
	for(;;){
		c := r[i++];
		if(!esc && c == '/')
			break;
		esc = !esc && c == '\\';
	}
	return (r[1: i-1], r[i: ]);
}
		
badflags(f: string): int
{
	g := i := m := 0;
	for(j := 0; j < len f; j++){
		case(f[j]){
			'g' =>
				g++;
			'i' =>
				i++;
			'm' =>
				m++;
			* =>
				return 1;
		}
	}
	return g > 1 || i > 1 || m > 1;
}

regexpvals(ex: ref Exec, v: ref Val, o: ref Ecmascript->Obj): (string, string, int)
{
	if(v != nil){
		if(v.ty == TRegExp)
			return (v.rev.p, v.rev.f, v.rev.i);
		o = v.obj;
	}
	p := toString(ex, esget(ex, o, "source", 0));
	f := "";
	if(toBoolean(ex, esget(ex, o, "global", 0)) == true)
		f += "g";
	if(toBoolean(ex, esget(ex, o, "ignoreCase", 0)) == true)
		f += "i";
	if(toBoolean(ex, esget(ex, o, "multiline", 0)) == true)
		f += "m";
	i := toInt32(ex, esget(ex, o, "lastIndex", 0));
	return (p, f, i);
}

nregexp(ex: ref Exec, nil: ref Ecmascript->Obj, args: array of ref Val): ref Ecmascript->Obj
{
	pat := biarg(args, 0);
	flags := biarg(args, 1);
	(p, f) := ("", "");
	if(isregexp(pat)){
		if(flags == undefined)
			(p, f, nil) = regexpvals(ex, pat, nil);
		else
			runtime(ex, TypeError, "flags defined");
	}
	else{
		if(pat == undefined)
			p = "";
		else
			p = toString(ex, pat);
		if(flags == undefined)
			f = "";
		else
			f = toString(ex, flags);
	}
	o := nobj(ex, nil, array[] of { regexpval(p, f, 0) });
	if(badflags(f))
		runtime(ex, SyntaxError, "bad regexp flags");
	regex = ex;
	(re, err) := compile(p, 1);
	if(re == nil || err != nil)
		runtime(ex, SyntaxError, "bad regexp pattern");
	o.re = re;
	return o;
}

cregexp(ex: ref Exec, f, nil: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	pat := biarg(args, 0);
	flags := biarg(args, 1);
	if(isregexp(pat) && flags == undefined)
		return pat;
	return objval(nregexp(ex, f, args));
}

cregexpprotoexec(ex: ref Exec, f, this: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	m: array of (int, int);

	regexpcheck(ex, this, f);
	s := toString(ex, biarg(args, 0));
	l := len s;
	i := toInt32(ex, esget(ex, this, "lastIndex", 0));
	e := 0;
	glob := esget(ex, this, "global", 0);
	multiline := esget(ex, this, "multiline", 0);
	ignorecase := esget(ex, this, "ignoreCase", 0);
	if(glob == false)
		i = 0;
	for(;;){
		if(i < 0 || i >= l){
			esput(ex, this, "lastIndex", numval(real 0), 0);
			return null;
		}
		regex = ex;
		m = executese(this.re, s, (i, len s), i == 0, 1, multiline == true, ignorecase == true);
		if(m != nil)
			break;
		i++;
		i = -1;	# no need to loop with executese
	}
	(i, e) = m[0];
	if(glob == true)
		esput(ex, this, "lastIndex", numval(real e), 0);
	n := len m;
	av := array[n] of ref Val;
	for(j := 0; j < n; j++){
		(a, b) := m[j];
		if(a < 0)
			av[j] = undefined;
		else
			av[j] = strval(s[a: b]);
	}
	a := narray(ex, nil, av);
	esput(ex, a, "index", numval(real i), 0);
	esput(ex, a, "input", strval(s), 0);
	return objval(a);
}

cregexpprototest(ex: ref Exec, f, this: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	regexpcheck(ex, this, f);
	v := cregexpprotoexec(ex, f, this, args);
	if(!isnull(v))
		return true;
	return false;
}

cregexpprototoString(ex: ref Exec, f, this: ref Ecmascript->Obj, nil: array of ref Val): ref Val
{
	regexpcheck(ex, this, f);
	(p, fl, nil) := regexpvals(ex, nil, this);
	return strval("/" + p + "/" + fl);
}

regexpcheck(ex: ref Exec, o: ref Ecmascript->Obj, f: ref Obj)
{
	if(f == nil)
		s := "exec";
	else
		s = f.val.str;
	if(!isregexpobj(o))
		runtime(ex, TypeError, "RegExp.prototype." + s + " called on non-RegExp object");
}

cstrprotomatch(ex: ref Exec, nil, this: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	v := biarg(args, 0);
	if(!isregexp(v))
		re := nregexp(ex, nil, args);
	else if(v.ty == TObj)
		re = v.obj;
	else
		re = nobj(ex, nil, args);
	s := toString(ex, this.val);
	glob := esget(ex, re, "global", 0);
	av := array[1] of ref Val;
	av[0] = strval(s);
	if(glob == false)
		return cregexpprotoexec(ex, nil, re, av);
	li := 0;
	esput(ex, re, "lastIndex", numval(real li), 0);
	ms: list of ref Val;
	for(;;){
		v = cregexpprotoexec(ex, nil, re, av);
		if(isnull(v))
			break;
		ms = esget(ex, v.obj, "0", 0) :: ms;
		ni := int toUint32(ex, esget(ex, re, "lastIndex", 0));
		if(ni == li)
			esput(ex, re, "lastIndex", numval(real ++li), 0);
		else
			li = ni;
	}	
	n := len ms;
	av = array[n] of ref Val;
	for(j := n-1; j >= 0; j--){
		av[j] = hd ms;
		ms = tl ms;
	}
	return objval(narray(ex, nil, av));
}

cstrprotoreplace(ex: ref Exec, nil, this: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	re: ref Ecmascript->Obj;

	v := biarg(args, 0);
	rege := isregexp(v);
	if(!rege){
		if(args == nil)
			re = nregexp(ex, nil, args);
		else
			re = nregexp(ex, nil, args[0:1]);
	}
	else if(v.ty == TObj)
		re = v.obj;
	else
		re = nobj(ex, nil, args);
	s := toString(ex, this.val);
	if(rege)
		glob := esget(ex, re, "global", 0);
	else
		glob = false;
	av := array[1] of ref Val;
	av[0] = strval(s);
	ms: list of ref Val;
	li := 0;
	if(glob == true)
		esput(ex, re, "lastIndex", numval(real li), 0);
	for(;;){
		v = cregexpprotoexec(ex, nil, re, av);
		if(!isnull(v))
			ms = v :: ms;
		if(isnull(v) || glob == false)
			break;
		ni := int toUint32(ex, esget(ex, re, "lastIndex", 0));
		if(ni == li)
			esput(ex, re, "lastIndex", numval(real ++li), 0);
		else
			li = ni;
	}
	if(ms == nil)
		return strval(s);
	ms = rev(ms);
	if(rege)
		lcp := int toUint32(ex, esget(ex, (hd ms).obj, "length", 0))-1;
	else
		lcp = 0;
	v = biarg(args, 1);
	if(isobj(v) && isfuncobj(v.obj)){
		ns := s;
		n := len ms;
		args = array[lcp+3] of ref Val;
		o := inc := 0;
		for(i := 0; i < n; i++){
			a := (hd ms).obj;
			ms = tl ms;
			for(j := 0; j <= lcp; j++)
				args[j] = esget(ex, a, string j, 0);
			ss := toString(ex, args[0]);
			o = offset(ss, s, o);
			args[lcp+1] = numval(real o);
			args[lcp+2] = strval(s);
			rs := toString(ex, getValue(ex, escall(ex, v.obj, nil, args, 0)));
			ns = repl(ns, o+inc, o+inc+len ss, rs);
			o += len ss;
			inc += len rs - len ss;
		}
		return strval(ns);
	}
	else{
		ps := toString(ex, v);
		lps := len ps;
		ns := s;
		n := len ms;
		o := inc := 0;
		for(i := 0; i < n; i++){
			a := (hd ms).obj;
			ms = tl ms;
			ss := toString(ex, esget(ex, a, "0", 0));
			o = offset(ss, s, o);
			rs := "";
			for(j := 0; j < lps; j++){
				if(ps[j] == '$' && j < lps-1){
					j++;
					case(c := ps[j]){
						'$' =>
							rs += "$";
						'&' =>
							rs += ss;
						'`' =>
							rs += s[0: o];
						''' =>
							rs += s[o+len ss: ];
						'0' to '9' =>
							if(j < lps-1 && isdigit(ps[j+1]))
								c = 10*(c-'0')+ps[++j]-'0';
							else
								c = c-'0';
							if(c >= 1 && c <= lcp)
								rs += toString(ex, esget(ex, a, string c, 0));
					}
				}
				else
					rs += ps[j: j+1];
			}
			ns = repl(ns, o+inc, o+inc+len ss, rs);
			o += len ss;
			inc += len rs - len ss;
		}
		return strval(ns);
	}
}

cstrprotosearch(ex: ref Exec, nil, this: ref Ecmascript->Obj, args: array of ref Val): ref Val
{
	v := biarg(args, 0);
	if(!isregexp(v))
		re := nregexp(ex, nil, args);
	else if(v.ty == TObj)
		re = v.obj;
	else
		re = nobj(ex, nil, args);
	s := toString(ex, this.val);
	glob := esget(ex, re, "global", 0);
	esput(ex, re, "global", false, 0);
	av := array[1] of ref Val;
	av[0] = strval(s);
	v = cregexpprotoexec(ex, nil, re, av);
	if(isnull(v))
		r := -1;
	else{
		ss := toString(ex, esget(ex, v.obj, "0", 0));
		r = offset(ss, s, 0);
	}
	esput(ex, re, "global", glob, 0);
	return numval(real r);
}

offset(ss: string, s: string, m: int): int
{
	nn := len ss;
	n := len s;
	for(i := m; i <= n-nn; i++){
		if(s[i: i+nn] == ss)
			return i;
	}
	return -1;
}

repl(s: string, a: int, b: int, ns: string): string
{
	return s[0: a] + ns + s[b: ];
}

rev(ls: list of ref Val): list of ref Val
{
	ns: list of ref Val;

	for( ; ls != nil; ls = tl ls)
		ns = hd ls :: ns;
	return ns;
}

#########################################################################
# regex.b originally

# normally imported identifiers

# internal identifiers, not normally imported

ALT, CAT, DOT, SET, HAT, DOL, NUL, PCLO, CLO, OPT, LPN, RPN, LPN0, RPN0, LPN1, RPN1, LPN2, RPN2, BEET, BEEF, MNCLO, LCP, IDLE: con (1<<16)+iota;

# syntax

# RE	ALT		regular expression
#	NUL
# ALT	CAT		alternation
# 	CAT | ALT
#
# CAT	DUP		catenation
# 	DUP CAT
#
# DUP	PRIM		possibly duplicated primary
# 	PCLO
# 	CLO
# 	OPT
#
# PCLO	PRIM +		1 or more
# CLO	PRIM *		0 or more
# OPT	PRIM ?		0 or 1
#
# PRIM	( RE )
#	()
# 	DOT		any character
# 	CHAR		a single character
#	ESC		escape sequence
# 	[ SET ]		character set
# 	NUL		null string
# 	HAT		beginning of string
# 	DOL		end of string
#

regex: ref Exec;

NIL : con -1;		# a refRex constant
NONE: con -2;		# ditto, for an un-set value
BAD: con 1<<16;		# a non-character 
HUGE: con (1<<31) - 1;

# the data structures of re.m would like to be ref-linked, but are
# circular (see fn walk), thus instead of pointers we use indexes
# into an array (arena) of nodes of the syntax tree of a regular expression.
# from a storage-allocation standpoint, this replaces many small
# allocations of one size with one big one of variable size.

ReStr: adt {
	s : string;
	i : int;	# cursor postion
	n : int;	# number of chars left; -1 on error
	peek : fn(s: self ref ReStr): int;
	next : fn(s: self ref ReStr): int;
	unput: fn(s: self ref ReStr);
};

ReStr.peek(s: self ref ReStr): int
{
	if(s.n <= 0)
		return BAD;
	return s.s[s.i];
}

ReStr.next(s: self ref ReStr): int
{
	if(s.n <= 0)
		syntax("bad regular expression");
	s.n--;
	return s.s[s.i++];
}

ReStr.unput(s: self ref ReStr)
{
	s.n++;
	s.i--;
}

newRe(kind: int, left, right: refRex, set: ref Set, ar: ref Arena, pno: int, greedy: int): refRex
{
	ar.rex[ar.ptr] = Rex(kind, left, right, set, pno, greedy, nil);
	return ar.ptr++;
}

# parse a regex by recursive descent to get a syntax tree

re(s: ref ReStr, ar: ref Arena): refRex
{
	left := cat(s, ar);
	if(left==NIL || s.peek()!='|')
		return left;
	s.next();
	right := re(s, ar);
	if(right == NIL)
		return NIL;
	return newRe(ALT, left, right, nil, ar, 0, 0);
}

cat(s: ref ReStr, ar: ref Arena): refRex
{
	left := dup(s, ar);
	if(left == NIL)
		return left;
	right := cat(s, ar);
	if(right == NIL)
		return left;
	return newRe(CAT, left, right, nil, ar, 0, 0);
}

dup(s: ref ReStr, ar: ref Arena): refRex
{
	n1, n2: int;

	case s.peek() {
	BAD or ')' or ']' or '|' or '?' or '*' or '+' =>
		return NIL;
	}
	prim: refRex;
	case kind:=s.next() {
	'(' =>	if(ar.pno < 0) {
			if(s.peek() == ')') {
				s.next();
				prim = newRe(NUL, NONE, NONE, nil, ar, 0, 0);
			} else {
				prim = re(s, ar);
				if(prim==NIL || s.next()!=')')
					syntax("( with no )");
			}
		} else {
			pno := ++ar.pno;
			lp := newRe(LPN, NONE, NONE, nil, ar, pno, 0);
			rp := newRe(RPN, NONE, NONE, nil, ar, pno, 0);
			if(s.peek() == ')') {
				s.next();
				prim = newRe(CAT, lp, rp, nil, ar, 0, 0);
			} else {
				if(s.peek() == '?'){
					s.next();
					case s.next(){
						':' => ar.rex[lp].kind = LPN0;
							ar.rex[rp].kind = RPN0;
						'=' => ar.rex[lp].kind = LPN1;
							ar.rex[rp].kind = RPN1;
						'!' => ar.rex[lp].kind = LPN2;
							ar.rex[rp].kind = RPN2;
						* => syntax("bad char after ?");
					}
				}
				prim = re(s, ar);
				if(prim==NIL || s.next()!=')')
					syntax("( with no )");
				else {
					prim = newRe(CAT, prim, rp, nil, ar, 0, 0);
					prim = newRe(CAT, lp, prim, nil, ar, 0, 0);
				}
			}
		}
	'[' =>	prim = newRe(SET, NONE, NONE, newSet(s), ar, 0, 0);
	* =>	case kind {
		'.' =>		kind = DOT;
		'^' =>	kind = HAT;
		'$' =>	kind = DOL;
		}
		(c, set, op) := esc(s, kind, 0);
		if(set != nil)
			prim = newRe(SET, NONE, NONE, set, ar, 0, 0);
		else if(op == LCP){
			if(c > ar.pno)
				syntax("\num too big");
			prim = newRe(LCP, NONE, NONE, nil, ar, 0, 0);
			ar.rex[prim].ns = ref Nstate(c, c);
		}
		else
			prim = newRe(c, NONE, NONE, nil, ar, 0, 0);
	}
	case s.peek() {
	'*' =>	kind = CLO;
	'+' =>	kind = PCLO;
	'?' =>	kind = OPT;
	'{' =>	s.next();
		(n1, n2) = drange(s);
		kind = MNCLO;
		if(s.peek() != '}')
			syntax("{ with no }");
	* =>	return prim;
	}
	s.next();
	greedy := 1;
	if(s.peek() == '?'){
		# non-greedy op
		greedy = 0;
		s.next();
	}
	prim = newRe(kind, prim, NONE, nil, ar, 0, greedy);
	if(kind == MNCLO)
		ns := ar.rex[prim].ns = ref Nstate(n1, n2);
	return prim;
}

esc(s: ref ReStr, char: int, inset: int): (int, ref Set, int)
{
	set: ref Set;

	op := 0;
	if(char == '\\') {
		char = s.next();
		case char {
		'b' =>
				if(inset)
					char = '\b';
				else
					char = BEET;
		'B' =>	if(inset)
					syntax("\\B in set");
				else
					char = BEEF;
		'f' =>		char = '\u000c';
		'n' =>	char = '\n';
		'r' =>		char = '\r';
		't' =>		char = '\t';
		'v' =>	char = '\v';
		'0' to '9' =>
				s.unput();
				char = digits(s);
				if(char == 0)
					char = '\0';
				else if(inset)
					syntax("\num in set");
				else
					op = LCP;
		'x' =>	char = hexdigits(s, 2);
		'u' =>	char = hexdigits(s, 4);
		'c' =>	char = s.next()%32;
		'd' or 'D' =>
				set = newset('0', '9');
				if(char == 'D')
					set.neg = 1;
		's' or 'S' =>
				set = newset(' ', ' ');
				addsets(set, "\t\v\u000c\u00a0\n\r\u2028\u2029");
				if(char == 'S')
					set.neg = 1;
		'w' or 'W' =>
				set = newset('0', '9');
				addset(set, 'a', 'z');
				addset(set, 'A', 'Z');
				addset(set, '_', '_');
				if(char == 'W')
					set.neg = 1;
		* =>
				;
		}
	}
	if(char == -1){
		if(inset)
			syntax("bad set");
		else
			syntax("bad character");
	}
	return (char, set, op);
}

isdigit(c: int): int
{
	return c >= '0' && c <= '9';
}

islower(c: int): int
{
	return c >= 'a' && c <= 'z';
}

isupper(c: int): int
{
	return c >= 'A' && c <= 'Z';
}

isalpha(c: int): int
{
	return islower(c) || isupper(c);
}

hexdigit(c: int): int
{
	if(isdigit(c))
		return c-'0';
	if('a' <= c && c <= 'f')
		return c-'a'+10;
	if('A' <= c && c <= 'F')
		return c-'A'+10;
	return -1;
}

digits(s: ref ReStr): int
{
	n := 0;
	while(isdigit(s.peek()))
		n = 10*n + s.next() -'0';
	return n;
}

hexdigits(s: ref ReStr, n: int): int
{
	x := 0;
	for(i := 0; i < n; i++){
		v := hexdigit(s.next());
		if(v < 0)
			return -1;
		x = 16*x+v;
	}
	return x;
}

drange(s: ref ReStr): (int, int)
{
	n1 := n2 := -1;
	if(isdigit(s.peek()))
		n1 = digits(s);
	if(s.peek() == ','){
		s.next();
		if(isdigit(s.peek()))
			n2 = digits(s);
		else
			n2 = HUGE;
	}
	else
		n2 = n1;
	if(n1 < 0 || n1 > n2)
		syntax("bad number range");
	return (n1, n2);
}

# walk the tree adjusting pointers to refer to 
# next state of the finite state machine

walk(r: refRex, succ: refRex, ar: ref Arena)
{
	if(r==NONE)
		return;
	rex := ar.rex[r];
	case rex.kind {
	ALT =>	walk(rex.left, succ, ar);
		walk(rex.right, succ, ar);
		return;
	CAT =>	walk(rex.left, rex.right, ar);
		walk(rex.right, succ, ar);
		ar.rex[r] = ar.rex[rex.left];	# optimization
		return;
	CLO or PCLO =>
		end := newRe(OPT, r, succ, nil, ar, 0, rex.greedy); # here's the circularity
		walk(rex.left, end, ar);
	OPT =>	walk(rex.left, succ, ar);
	MNCLO =>
		ar.ptr++;
		walk(rex.left, r, ar);
	LCP =>
		ar.rex[r].left = newRe(IDLE, NONE, succ, nil, ar, 0, 0);
	}
	ar.rex[r].right = succ;
}

prtree(r: refRex, ar: ref Arena, done: list of int, ind: string): list of int
{
	sys->print("%s", ind);
	if(r==NIL){
		sys->print("NIL\n");
		return done;
	}
	if(r==NONE){
		sys->print("NONE\n");
		return done;
	}
	printed := 0;
	for(li := done; li != nil; li = tl li){
		if(hd li == r){
			printed = 1;
			break;
		}
	}
	rex := ar.rex[r];
	op := "";
	z := "Z";
	case rex.kind{
		ALT => op = "|";
		CAT => op = "and";
		DOT => op = ".";
		SET => op = "[]";
		HAT => op = "^";
		DOL => op = "$";
		NUL => op = "NUL";
		PCLO => op = "+";
		CLO => op = "*";
		OPT => op = "?";
		LPN => op = "(";
		RPN => op = ")";
		LPN0 => op = "?:";
		RPN0 => op = ":?";
		LPN1 => op = "?=";
		RPN1 => op = "=?";
		LPN2 => op = "?!";
		RPN2 => op = "!?";
		BEET => op = "\\b";
		BEEF => op = "\\B";
		MNCLO => op = "{}";
		LCP => op = "n";
		IDLE => op = "i";
		* => z[0] = rex.kind; op = z;
	}
	if(printed){
		sys->print("node %d (%d)\n", r, r);
		return done;
	}
	else{
		if(rex.ns != nil)
			sys->print("%s [%d-%d] (%d)\n", op, rex.ns.m, rex.ns.n, r);
		else
			sys->print("%s (%d)\n", op, r);
		done = r :: done;
		ind += "  ";
		done = prtree(rex.left, ar, done, ind);
		done  = prtree(rex.right, ar, done, ind);
		return done;
	}
}

compile(e: string, flag: int): (Re, string)
{
	if(e == nil)
		return (nil, "missing expression");	
	s := ref ReStr(e, 0, len e);
	ar := ref Arena(array[2*s.n] of Rex, 0, 0, (flag&1)-1);
	start := ar.start = re(s, ar);
	if(start==NIL || s.n!=0)
		syntax("invalid regular expression");
	walk(start, NIL, ar);
	# prtree(start, ar, nil, "");
	if(ar.pno < 0)
		ar.pno = 0;
	return (ar, nil);
}

# todo: queue for epsilon and advancing transitions

Num: adt{
	ns: ref Nstate;
	m: int;
	n: int;
};
Gaz: adt {
	pno: int;
	beg: int;
	end: int;
};
Trace: adt {
	cre: refRex;		# cursor in Re
	trans: int;		# 0 epsilon transition, 1 advancing transition
	beg: int;		# where this trace began;
	end: int;		# where this trace ended if success (-1 by default)
	gaz: list of Gaz;
	ns: list of ref Num;
};
Queue: adt {
	ptr: int;
	q: array of Trace;
};

execute(re: Re, s: string): array of (int, int)
{
	return executese(re, s, (-1,-1), 1, 1, 1, 0);
}

executese(re: Re, s: string, range: (int, int), bol: int, eol: int, multiline: int, ignorecase: int): array of (int,int)
{
	if(re==nil)
		return nil;
	(s0, s1) := range;
	if(s0 < 0)
		s0 = 0;
	if(s1 < 0)
		s1 = len s;
	match := 0;
	todo := ref Queue(0, array[2*re.ptr] of Trace);
	for(i:=s0; i<=s1; i++) {
		if(!match)		# no leftmost match yet
			todo.q[todo.ptr++] = Trace(re.start, 0, i, -1, nil, nil);
		for(k:=0; k<todo.ptr; k++) {
			q := todo.q[k];
			if(q.trans)
				continue;
			rex := re.rex[q.cre];
			next0 := next1 := next2 := NONE;
			case rex.kind {
			NUL =>
				next1 = rex.right;
			DOT =>
				if(i<len s && !islt(s[i]))
					next2 = rex.right;
			HAT =>
				if(i == s0 && bol)
					next1 = rex.right;
				else if(multiline && i > 0 && islt(s[i-1]))
					next1 = rex.right;
			DOL =>
				if(i == s1 && eol)
					next1 = rex.right;
				else if(multiline && i < s1 && islt(s[i]))
					next1 = rex.right;
			SET =>
				if(i<len s && member(s[i], rex.set, ignorecase))
					next2 = rex.right;
			CAT or
			PCLO =>
				next1 = rex.left;
			ALT or 
			CLO or 
			OPT =>
				if(rex.kind == ALT || rex.greedy){
					next0 = rex.left;
					next1 = rex.right;
				}
				else{
					next0 = rex.right;
					next1 = rex.left;
				}
			LPN =>
				next1 = rex.right;
				q.gaz = Gaz(rex.pno,i,-1)::q.gaz;
			RPN =>
				next1 = rex.right;
				for(r:=q.gaz; ; r=tl r) {
					(pno,beg1,end1) := hd r;
					if(rex.pno==pno && end1==-1) {
						q.gaz = Gaz(pno,beg1,i)::q.gaz;
						break;
					}
				}
			LPN0 or RPN0 or RPN1 or RPN2 =>
				next1 = rex.right;
			LPN1 =>
				(rpn, nxt, nre) := storetree(q.cre, re);
				m := executese(nre, s, (i, -1), bol, eol, multiline, ignorecase);
				if(m != nil && m[0].t0 == i){
					next1 = nxt;
					for(j := 1; j < len m; j++)
						if(m[j].t0 >= 0)
							q.gaz = Gaz(j, m[j].t0, m[j].t1)::q.gaz;	
				}
				restoretree(LPN1, rpn, nxt, nre);
			LPN2 =>
				(rpn, nxt, nre) := storetree(q.cre, re);
				m := executese(nre, s, (i, -1), bol, eol, multiline, ignorecase);
				if(m == nil || m[0].t0 != i)
					next1 = nxt;
				restoretree(LPN2, rpn, nxt, nre);
			MNCLO =>
				num: ref Num;

				(q.ns, num) = nextn(q.cre, q.ns, rex.ns.m, rex.ns.n, re);
				if(num.m > 0)
					next1 = rex.left;
				else if(num.n > 0){
					if(rex.greedy){
						next0 = rex.left;
						next1 = rex.right;
					}
					else{
						next0 = rex.right;
						next1 = rex.left;	
					}
				}
				else{
					next1 = rex.right;
					(num.m, num.n) = (-1, -1);
				}
			LCP =>
				pno := rex.ns.m;
				(beg1, end1) := lcpar(q.gaz, pno);
				l := end1-beg1;
				if(beg1 < 0)	# undefined so succeeds
					next1 = rex.right;
				else if(i+l <= s1 && eqstr(s[beg1: end1], s[i: i+l], ignorecase)){
					(q.ns, nil) = nextn(rex.left, q.ns, l, l, re);
					next1 = rex.left;	# idle
				}
			IDLE =>
				num: ref Num;

				(q.ns, num) = nextn(q.cre, q.ns, -1, -1, re);
				if(num.m >= 0)
					next2 = q.cre;
				else{
					next1 = rex.right;
					(num.m, num.n) = (-1, -1);
				}
			BEET =>
				if(iswordc(s, i-1) != iswordc(s, i))
					next1 = rex.right;
			BEEF =>
				if(iswordc(s, i-1) == iswordc(s, i))
					next1 = rex.right;
			* =>
				if(i<len s && (rex.kind==s[i] || (ignorecase && eqcase(rex.kind, s[i]))))
					next2 = rex.right;
			}
			l := k;
			if(next0 != NONE) {
				if(next0 != NIL)
					(k, l) = insert(next0, 0, q.beg, -1, q.gaz, q.ns, todo, k, l);
				else{
					match = 1;
					(k, l) = insert(NIL, 2, q.beg, i, q.gaz, nil, todo, k, l);
				}
			}
			if(next1 != NONE) {
				if(next1 != NIL)
					(k, l) = insert(next1, 0, q.beg, -1, q.gaz, q.ns, todo, k, l);
				else{
					match = 1;
					(k, l) = insert(NIL, 2, q.beg, i, q.gaz, nil, todo, k, l);
				}
			}
			if(next2 != NONE) {
				if(next2 != NIL)
					(k, l) = insert(next2, 1, q.beg, -1, q.gaz, q.ns, todo, k, l);
				else{
					match = 1;
					(k, l) = insert(NIL, 2, q.beg, i+1, q.gaz, nil, todo, k, l);
				}
			}
		}
		if(!atoe(todo) && match)
			break;
	}
	if(todo.ptr == 0)
		return nil;
	if(todo.ptr > 1)
		rfatal(sys->sprint("todo.ptr = %d", todo.ptr));
	if(todo.q[0].trans != 2)
		rfatal(sys->sprint("trans = %d", todo.q[0].trans));
	if(todo.q[0].cre != NIL)
		rfatal(sys->sprint("cre = %d", todo.q[0].cre));
	beg := todo.q[0].beg;
	end := todo.q[0].end;
	gaz := todo.q[0].gaz;
	if(beg == -1)
		return nil;
	result := array[re.pno+1] of { 0 => (beg,end), * => (-1,-1) };
	for( ; gaz!=nil; gaz=tl gaz) {
		(pno, beg1, end1) := hd gaz;
		(rbeg, nil) := result[pno];
		if(rbeg==-1 && (beg1|end1)!=-1)
			result[pno] = (beg1,end1);
	}
	return result;
}

better(newbeg, newend, oldbeg, oldend: int): int
{
	return oldbeg==-1 || newbeg<oldbeg ||
	       newbeg==oldbeg && newend>oldend;
}

insert(next: refRex, trans: int, tbeg: int, tend: int, tgaz: list of Gaz, tns: list of ref Num, todo: ref Queue, k: int, l: int): (int, int)
{
# sys->print("insert %d eps=%d beg=%d end=%d (k, l) = (%d %d) => ", next, trans, tbeg, tend, k, l);
	for(j:=0; j<todo.ptr; j++){
		if(todo.q[j].trans == trans){
			if(todo.q[j].cre == next){
				if(better(todo.q[j].beg, todo.q[j].end, tbeg, tend))
					return (k, l);
				else if(better(tbeg, tend, todo.q[j].beg, todo.q[j].end))
					break;
				else if(j < k)
					return (k, l);
				else
					break;
			}
		}
	}
	if(j < k){
		k--;
		l--;
	}
	if(j < todo.ptr){
		todo.q[j: ] = todo.q[j+1: todo.ptr];
		todo.ptr--;
	}
	todo.q[l+2: ] = todo.q[l+1: todo.ptr];
	todo.ptr++;
	todo.q[l+1] = Trace(next, trans, tbeg, tend, tgaz, tns);
# for(j=0; j < todo.ptr; j++) sys->print("%d(%d) ", todo.q[j].cre, todo.q[j].trans); sys->print("\n");
	return (k, l+1);
}

# remove epsilon transitions and move advancing transitions to epsilon ones
atoe(todo: ref Queue): int
{
	n := 0;
	for(j := 0; j < todo.ptr; j++){
		if(todo.q[j].trans){
			if(todo.q[j].trans == 1){
				todo.q[j].trans = 0;
				n++;
			}
		}
		else{
			todo.q[j: ] = todo.q[j+1: todo.ptr];
			todo.ptr--;
			j--;
		}
	}
	return n;
}

nextn(re: int, ln: list of ref Num, m: int, n: int, ar: ref Arena): (list of ref Num, ref Num)
{
	num: ref Num;

	ns := ar.rex[re].ns;
	for(l := ln; l != nil; l = tl l){
		if((hd l).ns == ns){
			num = hd l;
			break;
		}
	}
	if(num == nil)
		ln = (num = ref Num(ns, -1, -1)) :: ln;
	if(num.m == -1 && num.n == -1)
		(num.m, num.n) = (m, n);
	else
		(nil, nil) = (--num.m, --num.n);
	return (ln, num);
}

ASCII : con 128;
WORD : con 32;

mem(c: int, set: ref Set): int
{
	return (set.ascii[c/WORD]>>c%WORD)&1;
}

member(char: int, set: ref Set, ignorecase: int): int
{
	if(set.subset != nil){
		for(l := set.subset; l != nil; l = tl l)
			if(member(char, hd l, ignorecase))
				return !set.neg;
	}
	if(char < 128){
		if(ignorecase)
			return (mem(tolower(char), set) || mem(toupper(char), set))^set.neg;
		else
			return ((set.ascii[char/WORD]>>char%WORD)&1)^set.neg;
	}
	for(l:=set.unicode; l!=nil; l=tl l) {
		(beg, end) := hd l;
		if(char>=beg && char<=end)
			return !set.neg;
	}
	return set.neg;
}

newSet(s: ref ReStr): ref Set
{
	op: int;
	set0: ref Set;

	set := ref Set(0, array[ASCII/WORD] of {* => 0}, nil, nil);
	if(s.peek() == '^') {
		set.neg = 1;
		s.next();
	}
	while(s.n > 0) {
		char1 := s.next();
		if(char1 == ']')
			return set;
		(char1, set0, op) = esc(s, char1, 1);
		if(set0 != nil)
			mergeset(set, set0);
		char2 := char1;
		if(s.peek() == '-') {
			if(set0 != nil)
				syntax("set in range");
			s.next();
			char2 = s.next();
			if(char2 == ']')
				break;
			(char2, set0, op) = esc(s, char2, 1);
			if(set0 != nil)
				syntax("set in range");
			if(char2 < char1)
				break;
		}
		addset(set, char1, char2);
	}
	syntax("bad set");
	return nil;
}

addset(set: ref Set, c1: int, c2: int)
{
	for(c := c1; c <= c2; c++){
		if(c < ASCII)
			set.ascii[c/WORD] |= 1<<c%WORD;
		else{
			set.unicode = (c, c2) :: set.unicode;
			break;
		}
	}
}

addsets(set: ref Set, s: string)
{
	for(i := 0; i < len s; i++)
		addset(set, s[i], s[i]);
}

mergeset(set: ref Set, set0: ref Set)
{
	if(!set0.neg){
		for(i := 0; i < ASCII/WORD; i++)
			set.ascii[i] |= set0.ascii[i];
		for(l := set0.unicode; l != nil; l = tl l)
			set.unicode = hd l :: set.unicode;
	}
	else
		set.subset = set0 :: set.subset;
}
		
newset(c1: int, c2: int): ref Set
{
	set := ref Set(0, array[ASCII/WORD] of {* => 0}, nil, nil);
	addset(set, c1, c2);
	return set;
}

storetree(lpn: int, re: ref Arena): (int, int, ref Arena)
{
	rpn: int;

	rex := re.rex[lpn];
	k := rex.kind;
	l := 1;
	for(;;){
		rpn = rex.right;
		rex = re.rex[rpn];
		if(rex.kind == k)
			l++;
		else if(rex.kind == k+1 && --l == 0)
			break;
	}
	re.rex[lpn].kind = LPN;
	re.rex[rpn].kind = RPN;
	nxt := re.rex[rpn].right;
	re.rex[rpn].right = NIL;
	nre := ref *re;
	nre.start = lpn;
	return (rpn, nxt, nre);
}

restoretree(lop: int, rpn: int, nxt: int, re: ref Arena)
{
	lpn := re.start;
	re.rex[lpn].kind = lop;
	re.rex[rpn].kind = lop+1;
	re.rex[rpn].right = nxt;
}

iswordc(s: string, i: int): int
{
	if(i < 0 || i >= len s)
		return 0;
	c := s[i];
	return isdigit(c) || isalpha(c) || c == '_';
}

lcpar(gaz: list of Gaz, pno: int): (int, int)
{
	for(r := gaz; r != nil; r = tl r) {
		(pno1, beg1, end1) := hd r;
		if(pno == pno1)
			return (beg1, end1);
	}
	return (-1, -1);
}

eqstr(s: string, t: string, ic: int): int
{
	if(!ic)
		return s == t;
	if(len s != len t)
		return 0;
	for(i := 0; i < len s; i++)
		if(!eqcase(s[i], t[i]))
			return 0;
	return 1;
}

eqcase(c1: int, c2: int): int
{
	return toupper(c1) == toupper(c2);
}
	
syntax(s: string)
{
	runtime(regex, SyntaxError, s);
}

rfatal(s: string)
{
	runtime(regex, InternalError, s);
}
