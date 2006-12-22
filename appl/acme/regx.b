implement Regx;

include "common.m";

sys : Sys;
utils : Utils;
textm : Textm;

FALSE, TRUE, XXX : import Dat;
NRange : import Dat;
Range, Rangeset : import Dat;
error, warning, tgetc, rgetc : import utils;
Text : import textm;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	utils = mods.utils;
	textm = mods.textm;
}

None : con 0;
Fore : con '+';
Back : con '-';

Char : con 0;
Line : con 1;

isaddrc(r : int) : int
{
	if (utils->strchr("0123456789+-/$.#", r) >= 0)
		return TRUE;
	return FALSE;
}

#
# quite hard: could be almost anything but white space, but we are a little conservative,
# aiming for regular expressions of alphanumerics and no white space
#
isregexc(r : int) : int
{
	if(r == 0)
		return FALSE;
	if(utils->isalnum(r))
		return TRUE;
	if(utils->strchr("^+-.*?#,;[]()$", r)>=0)
		return TRUE;
	return FALSE;
}

number(md: ref Dat->Mntdir, t : ref Text, r : Range, line : int, dir : int, size : int) : (int, Range)
{
	q0, q1 : int;

	{
		if(size == Char){
			if(dir == Fore)
				line = r.q1+line;	# was t.file.buf.nc+line;
			else if(dir == Back){
				if(r.q0==0 && line > 0)
					r.q0 = t.file.buf.nc;
				line = r.q0-line;	# was t.file.buf.nc - line;
			}
			if(line<0 || line>t.file.buf.nc)
				raise "e";
			return (TRUE, (line, line));
		}
		(q0, q1) = r;
		case(dir){
		None =>
			q0 = 0;
			q1 = 0;
			while(line>0 && q1<t.file.buf.nc)
				if(t.readc(q1++) == '\n')
					if(--line > 0)
						q0 = q1;
			if(line==1 && t.readc(q1-1)!='\n')	# no newline at end - count it
				;
			else if(line > 0)
				raise "e";
		Fore =>
			if(q1 > 0)
				while(t.readc(q1-1) != '\n')
					q1++;
			q0 = q1;
			while(line>0 && q1<t.file.buf.nc)
				if(t.readc(q1++) == '\n')
					if(--line > 0)
						q0 = q1;
			if(line > 0)
				raise "e";
		Back =>
			if(q0 < t.file.buf.nc)
				while(q0>0 && t.readc(q0-1)!='\n')
					q0--;
			q1 = q0;
			while(line>0 && q0>0){
				if(t.readc(q0-1) == '\n'){
					if(--line >= 0)
						q1 = q0;
				}
				--q0;
			}
			if(line > 0)
				raise "e";
			while(q0>0 && t.readc(q0-1)!='\n')
				--q0;
		}
		return (TRUE, (q0, q1));
	}
	exception{
		* =>
			if(md != nil)
				warning(nil, "address out of range\n");
			return (FALSE, r);
	}
	return (FALSE, r);
}

regexp(md: ref Dat->Mntdir, t : ref Text, lim : Range, r : Range, pat : string, dir : int) : (int, Range)
{
	found : int;
	sel : Rangeset;
	q : int;

	if(pat == nil && rxnull()){
		warning(md, "no previous regular expression");
		return (FALSE, r);
	}
	if(pat == nil || !rxcompile(pat))
		return (FALSE, r);
	if(dir == Back)
		(found, sel) = rxbexecute(t, r.q0);
	else{
		if(lim.q0 < 0)
			q = Dat->Infinity;
		else
			q = lim.q1;
		(found, sel) = rxexecute(t, nil, r.q1, q);
	}
	if(!found && md == nil)
		warning(nil, "no match for regexp\n");
	return (found, sel[0]);
}

xgetc(a0 : ref Text, a1 : string, n : int) : int
{
	if (a0 == nil)
		return rgetc(a1, n);
	return tgetc(a0, n);
}

address(md: ref Dat->Mntdir, t : ref Text, lim : Range, ar : Range, a0 : ref Text, a1 : string, q0 : int, q1 : int,  eval : int) : (int, int, Range)
{
	dir, size : int;
	prevc, c, n : int;
	q : int;
	pat : string;
	r, nr : Range;

	r = ar;
	q = q0;
	dir = None;
	size = Line;
	c = 0;
	while(q < q1){
		prevc = c;
		c = xgetc(a0, a1, q++);
		case(c){
		';' =>
			ar = r;
			if(prevc == 0)	# lhs defaults to 0
				r.q0 = 0;
			if(q>=q1 && t!=nil && t.file!=nil)	# rhs defaults to $
				r.q1 = t.file.buf.nc;
			else{
				(eval, q, nr) = address(md, t, lim, ar, a0, a1, q, q1, eval);
				r.q1 = nr.q1;
			}
			return (eval, q, r);
		',' =>
			if(prevc == 0)	# lhs defaults to 0
				r.q0 = 0;
			if(q>=q1 && t!=nil && t.file!=nil)	# rhs defaults to $
				r.q1 = t.file.buf.nc;
			else{
				(eval, q, nr) = address(md, t, lim, ar, a0, a1, q, q1, eval);
				r.q1 = nr.q1;
			}
			return (eval, q, r);
		'+'  or '-' =>
			if(eval && (prevc=='+' || prevc=='-')){
				if((nc := xgetc(a0, a1, q)) != '#' && nc != '/' && nc != '?')
					(eval, r) = number(md, t, r, 1, prevc, Line);	# do previous one
			}
			dir = c;
		'.' or '$' =>
			if(q != q0+1)
				return (eval, q-1, r);
			if(eval)
				if(c == '.')
					r = ar;
				else
					r = (t.file.buf.nc, t.file.buf.nc);
			if(q < q1)
				dir = Fore;
			else
				dir = None;
		'#' =>
			if(q==q1 || (c=xgetc(a0, a1, q++))<'0' || '9'<c)
				return (eval, q-1, r);
			size = Char;
			n = c -'0';
			while(q<q1){
				c = xgetc(a0, a1, q++);
				if(c<'0' || '9'<c){
					q--;
					break;
				}
				n = n*10+(c-'0');
			}
			if(eval)
				(eval, r) = number(md, t, r, n, dir, size);
			dir = None;
			size = Line;
		'0' to '9' =>
			n = c -'0';
			while(q<q1){
				c = xgetc(a0, a1, q++);
				if(c<'0' || '9'<c){
					q--;
					break;
				}
				n = n*10+(c-'0');
			}
			if(eval)
				(eval, r) = number(md, t, r, n, dir, size);
			dir = None;
			size = Line;
		'/' =>
			pat = nil;
			break2 := 0; # Ow !
			while(q<q1){
				c = xgetc(a0, a1, q++);
				case(c){
				'\n' =>
					--q;
					break2 = 1;
				'\\' =>
					pat[len pat] = c;
					if(q == q1)
						break2 = 1;
					else
						c = xgetc(a0, a1, q++);
				'/' =>
					break2 = 1;
				}
				if (break2)
					break;
				pat[len pat] = c;
			}
			if(eval)
				(eval, r) = regexp(md, t, lim, r, pat, dir);
			pat = nil;
			dir = None;
			size = Line;
		* =>
			return (eval, q-1, r);
		}
	}
	if(eval && dir != None)
		(eval, r) = number(md, t, r, 1, dir, Line);	# do previous one
	return (eval, q, r);
}

sel : Rangeset = array[NRange] of Range;
lastregexp : string;

# Machine Information
 
Inst : adt {
	typex : int;		# < 16r10000 ==> literal, otherwise action 
	# sid : int;
	subid : int;
	class : int;
	# other : cyclic ref Inst;
	right : cyclic ref Inst;
	# left : cyclic ref Inst;
	next : cyclic ref Inst;
};

NPROG : con	1024;
program := array[NPROG] of ref Inst;
progp : int;
startinst : ref Inst;		# First inst. of program; might not be program[0] 
bstartinst : ref Inst;		# same for backwards machine 

Ilist : adt {
	inst : ref Inst;			# Instruction of the thread 
	se : Rangeset;
	startp : int;		# first char of match 
};

NLIST : con	128;

thl, nl : array of Ilist;			# This list, next list 
listx := array[2] of array of Ilist;
sempty : Rangeset = array[NRange] of Range;

#
# Actions and Tokens
#
#	0x100xx are operators, value == precedence
#	0x200xx are tokens, i.e. operands for operators
#

OPERATOR : con		16r10000;	# Bitmask of all operators 
START	  : con		16r10000;	# Start, used for marker on stack 
RBRA	  : con		16r10001;	# Right bracket, ) 
LBRA	  : con		16r10002;	# Left bracket, ( 
OR		  : con		16r10003;	# Alternation, | 
CAT		  : con		16r10004;	# Concatentation, implicit operator 
STAR	  : con		16r10005;	# Closure, * 
PLUS		  : con		16r10006;	# a+ == aa* 
QUEST	  : con		16r10007;	# a? == a|nothing, i.e. 0 or 1 a's 
ANY		  : con		16r20000;	# Any character but newline, . 
NOP		  : con		16r20001;	# No operation, internal use only 
BOL		  : con		16r20002;	# Beginning of line, ^ 
EOL		  : con		16r20003;	# End of line, $ 
CCLASS	  : con		16r20004;	# Character class, [] 
NCCLASS	  : con		16r20005;	# Negated character class, [^] 
END		  : con		16r20077;	# Terminate: match found 

ISATOR	  : con		16r10000;
ISAND	  : con		16r20000;

# Parser Information
 
Node : adt {
	first : ref Inst;
	last : ref Inst;
};

NSTACK : con	20;
andstack := array[NSTACK] of ref Node;
andp : int;
atorstack := array[NSTACK] of int;
atorp : int;
lastwasand : int;	# Last token was operand 
cursubid : int;
subidstack := array[NSTACK] of int;
subidp : int;
backwards : int;
nbra : int;
exprs : string;
exprp : int;		# pointer to next character in source expression 
DCLASS : con	10;	# allocation increment 
nclass : int;		# number active 
Nclass : int = 0;		# high water mark 
class : array of string;
negateclass : int;

nilnode : Node;
nilinst : Inst;

rxinit()
{
	lastregexp = nil;
	for (k := 0; k < NPROG; k++)
		program[k] = ref nilinst;
	for (k = 0; k < NSTACK; k++)
		andstack[k] = ref nilnode;
	for (k = 0; k < 2; k++) {
		listx[k] = array[NLIST] of Ilist;
		for (i := 0; i < NLIST; i++) {
			listx[k][i].inst = nil;
			listx[k][i].startp = 0;
			listx[k][i].se = array[NRange] of Range;
			for (j := 0; j < NRange; j++)
				listx[k][i].se[j].q0 = listx[k][i].se[j].q1 = 0;
		}
	}
}

regerror(e : string)
{
	lastregexp = nil;
	buf := sys->sprint("regexp: %s\n", e);
	warning(nil, buf);
	raise "regerror";
}

newinst(t : int) : ref Inst
{
	if(progp >= NPROG)
		regerror("expression too long");
	program[progp].typex = t;
	program[progp].next = nil;	# next was left
	program[progp].right = nil;
	return program[progp++];
}

realcompile(s : string) : ref Inst
{
	token : int;

	{
		startlex(s);
		atorp = 0;
		andp = 0;
		subidp = 0;
		cursubid = 0;
		lastwasand = FALSE;
		# Start with a low priority operator to prime parser 
		pushator(START-1);
		while((token=lex()) != END){
			if((token&ISATOR) == OPERATOR)
				operator(token);
			else
				operand(token);
		}
		# Close with a low priority operator 
		evaluntil(START);
		# Force END 
		operand(END);
		evaluntil(START);
		if(nbra)
			regerror("unmatched `('");
		--andp;	# points to first and only operand 
		return andstack[andp].first;
	}
	exception{
		"regerror" =>
			return nil;
	}
	return nil;
}

rxcompile(r : string) : int
{
	oprogp : int;

	if(lastregexp == r)
		return TRUE;
	lastregexp = nil;
	for (i := 0; i < nclass; i++)
		class[i] = nil;
	nclass = 0;
	progp = 0;
	backwards = FALSE;
	bstartinst = nil;
	startinst = realcompile(r);
	if(startinst == nil)
		return FALSE;
	optimize(0);
	oprogp = progp;
	backwards = TRUE;
	bstartinst = realcompile(r);
	if(bstartinst == nil)
		return FALSE;
	optimize(oprogp);
	lastregexp = r;
	return TRUE;
}

operand(t : int)
{
	i : ref Inst;

	if(lastwasand)
		operator(CAT);	# catenate is implicit 
	i = newinst(t);
	if(t == CCLASS){
		if(negateclass)
			i.typex = NCCLASS;	# UGH 
		i.class = nclass-1;		# UGH 
	}
	pushand(i, i);
	lastwasand = TRUE;
}

operator(t : int)
{
	if(t==RBRA && --nbra<0)
		regerror("unmatched `)'");
	if(t==LBRA){
		cursubid++;	# silently ignored 
		nbra++;
		if(lastwasand)
			operator(CAT);
	}else
		evaluntil(t);
	if(t!=RBRA)
		pushator(t);
	lastwasand = FALSE;
	if(t==STAR || t==QUEST || t==PLUS || t==RBRA)
		lastwasand = TRUE;	# these look like operands 
}

pushand(f : ref Inst, l : ref Inst)
{
	if(andp >= NSTACK)
		error("operand stack overflow");
	andstack[andp].first = f;
	andstack[andp].last = l;
	andp++;
}

pushator(t : int)
{
	if(atorp >= NSTACK)
		error("operator stack overflow");
	atorstack[atorp++]=t;
	if(cursubid >= NRange)
		subidstack[subidp++]= -1;
	else
		subidstack[subidp++]=cursubid;
}

popand(op : int) : ref Node
{
	if(andp <= 0)
		if(op){
			buf := sys->sprint("missing operand for %c", op);
			regerror(buf);
		}else
			regerror("malformed regexp");
	return andstack[--andp];
}

popator() : int
{
	if(atorp <= 0)
		error("operator stack underflow");
	--subidp;
	return atorstack[--atorp];
}

evaluntil(pri : int)
{
	op1, op2 : ref Node;
	inst1, inst2 : ref Inst;

	while(pri==RBRA || atorstack[atorp-1]>=pri){
		case(popator()){
		LBRA =>
			op1 = popand('(');
			inst2 = newinst(RBRA);
			inst2.subid = subidstack[subidp];
			op1.last.next = inst2;
			inst1 = newinst(LBRA);
			inst1.subid = subidstack[subidp];
			inst1.next = op1.first;
			pushand(inst1, inst2);
			return;		# must have been RBRA 
		OR =>
			op2 = popand('|');
			op1 = popand('|');
			inst2 = newinst(NOP);
			op2.last.next = inst2;
			op1.last.next = inst2;
			inst1 = newinst(OR);
			inst1.right = op1.first;
			inst1.next = op2.first;	# next was left
			pushand(inst1, inst2);
		CAT =>
			op2 = popand(0);
			op1 = popand(0);
			if(backwards && op2.first.typex!=END)
				(op1, op2) = (op2, op1);
			op1.last.next = op2.first;
			pushand(op1.first, op2.last);
		STAR =>
			op2 = popand('*');
			inst1 = newinst(OR);
			op2.last.next = inst1;
			inst1.right = op2.first;
			pushand(inst1, inst1);
		PLUS =>
			op2 = popand('+');
			inst1 = newinst(OR);
			op2.last.next = inst1;
			inst1.right = op2.first;
			pushand(op2.first, inst1);
		QUEST =>
			op2 = popand('?');
			inst1 = newinst(OR);
			inst2 = newinst(NOP);
			inst1.next = inst2;	# next was left
			inst1.right = op2.first;
			op2.last.next = inst2;
			pushand(inst1, inst2);
		* =>
			error("unknown regexp operator");
		}
	}
}

optimize(start : int)
{
	inst : int;
	target : ref Inst;

	for(inst=start; program[inst].typex!=END; inst++){
		target = program[inst].next;
		while(target.typex == NOP)
			target = target.next;
		program[inst].next = target;
	}
}

startlex(s : string)
{
	exprs = s;
	exprp = 0;
	nbra = 0;
}

lex() : int
{
	c : int;

	if (exprp == len exprs)
		return END;
	c = exprs[exprp++];
	case(c){
	'\\' =>
		if(exprp < len exprs)
			if((c= exprs[exprp++])=='n')
				c='\n';
	'*' =>
		c = STAR;
	'?' =>
		c = QUEST;
	'+' =>
		c = PLUS;
	 '|' =>
		c = OR;
	'.' =>
		c = ANY;
	'(' =>
		c = LBRA;
	')' =>
		c = RBRA;
	'^' =>
		c = BOL;
	'$' =>
		c = EOL;
	'[' =>
		c = CCLASS;
		bldcclass();
	}
	return c;
}

nextrec() : int
{
	if(exprp == len exprs || (exprp == len exprs-1 && exprs[exprp]=='\\'))
		regerror("malformed `[]'");
	if(exprs[exprp] == '\\'){
		exprp++;
		if(exprs[exprp]=='n'){
			exprp++;
			return '\n';
		}
		return exprs[exprp++] | 16r10000;
	} 
	return exprs[exprp++];
}

bldcclass()
{
	c1, c2 : int;
	classp : string;

	# we have already seen the '[' 
	if(exprp < len exprs && exprs[exprp] == '^'){
		classp[len classp] = '\n';	# don't match newline in negate case 
		negateclass = TRUE;
		exprp++;
	}else
		negateclass = FALSE;
	while((c1 = nextrec()) != ']'){
		if(c1 == '-'){
			classp = nil;
			regerror("malformed `[]'");
		}
		if(exprp < len exprs && exprs[exprp] == '-'){
			exprp++;	# eat '-' 
			if((c2 = nextrec()) == ']') {
				classp = nil;
				regerror("malformed '[]'");
			}
			classp[len classp] = 16rFFFF;
			classp[len classp] = c1;
			classp[len classp] = c2;
		}else
			classp[len classp] = c1;
	}
	if(nclass == Nclass){
		Nclass += DCLASS;
		oc := class;
		class = array[Nclass] of string;
		if (oc != nil) {
			class[0:] = oc[0:Nclass-DCLASS];
			oc = nil;
		}
	}
	class[nclass++] = classp;
}

classmatch(classno : int, c : int, negate : int) : int
{
	p : string;

	p = class[classno];
	for (i := 0; i < len p; ) {
		if(p[i] == 16rFFFF){
			if(p[i+1]<=c && c<=p[i+2])
				return !negate;
			i += 3;
		}else if(p[i++] == c)
			return !negate;
	}
	return negate;
}

#
# Note optimization in addinst:
# 	*l must be pending when addinst called; if *l has been looked
#		at already, the optimization is a bug.
#
addinst(l : array of Ilist, inst : ref Inst, sep : Rangeset)
{
	p : int;

	for(p = 0; l[p].inst != nil; p++){
		if(l[p].inst==inst){
			if(sep[0].q0 < l[p].se[0].q0)
				l[p].se[0:] = sep[0:NRange]; # this would be bug 
			return;	# It's already there 
		}
	}
	l[p].inst = inst;
	l[p].se[0:]= sep[0:NRange];
	l[p+1].inst = nil;
}

rxnull() : int
{
	return startinst==nil || bstartinst==nil;
}

OVERFLOW : con "overflow";

# either t!=nil or r!=nil, and we match the string in the appropriate place
rxexecute(t : ref Text, r: string, startp : int, eof : int) : (int, Rangeset)
{
	flag : int;
	inst : ref Inst;
	tlp : int;
	p : int;
	nnl, ntl : int;
	nc, c : int;
	wrapped : int;
	startchar : int;

	flag = 0;
	p = startp;
	startchar = 0;
	wrapped = 0;
	nnl = 0;
	if(startinst.typex<OPERATOR)
		startchar = startinst.typex;
	listx[0][0].inst = listx[1][0].inst = nil;
	sel[0].q0 = -1;
	
	{
		if(t != nil)
			nc = t.file.buf.nc;
		else
			nc = len r;
		# Execute machine once for each character 
		for(;;p++){
			if(p>=eof || p>=nc){
				case(wrapped++){
				0 or 2 =>		# let loop run one more click 
					;
				1 =>		# expired; wrap to beginning 
					if(sel[0].q0>=0 || eof!=Dat->Infinity)
						return (sel[0].q0>=0, sel);
					listx[0][0].inst = listx[1][0].inst = nil;
					p = -1;
					continue;
				* =>
					return (sel[0].q0>=0, sel);
				}
				c = 0;
			}else{
				if(((wrapped && p>=startp) || sel[0].q0>0) && nnl==0)
					break;
				if(t != nil)
					c = t.readc(p);
				else
					c = r[p];
			}
			# fast check for first char 
			if(startchar && nnl==0 && c!=startchar)
				continue;
			thl = listx[flag];
			nl = listx[flag^=1];
			nl[0].inst = nil;
			ntl = nnl;
			nnl = 0;
			if(sel[0].q0<0 && (!wrapped || p<startp || startp==eof)){
				# Add first instruction to this list 
				if(++ntl >= NLIST)
					raise OVERFLOW;
				sempty[0].q0 = p;
				addinst(thl, startinst, sempty);
			}
			# Execute machine until this list is empty 
			tlp = 0;
			inst = thl[0].inst;
			while(inst  != nil){	# assignment = 
				case(inst.typex){
				LBRA =>
					if(inst.subid>=0)
						thl[tlp].se[inst.subid].q0 = p;
					inst = inst.next;
					continue;
				RBRA =>
					if(inst.subid>=0)
						thl[tlp].se[inst.subid].q1 = p;
					inst = inst.next;
					continue;
				ANY =>
					if(c!='\n') {
						if(++nnl >= NLIST)
							raise OVERFLOW;
						addinst(nl, inst.next, thl[tlp].se);
					}
				BOL =>
					if(p==0 || (t != nil && t.readc(p-1)=='\n') || (r != nil && r[p-1] == '\n')){
						inst = inst.next;
						continue;
					}
				EOL =>
					if(c == '\n') {
						inst = inst.next;
						continue;
					}
				CCLASS =>
					if(c>=0 && classmatch(inst.class, c, 0)) {
						if(++nnl >= NLIST)
							raise OVERFLOW;
						addinst(nl, inst.next, thl[tlp].se);
					}
				NCCLASS =>
					if(c>=0 && classmatch(inst.class, c, 1)) {
						if(++nnl >= NLIST)
							raise OVERFLOW;
						addinst(nl, inst.next, thl[tlp].se);
					}
				OR =>
					# evaluate right choice later 
					if(++ntl >= NLIST)
						raise OVERFLOW;
					addinst(thl[tlp:], inst.right, thl[tlp].se);
					# efficiency: advance and re-evaluate 
					inst = inst.next;	# next was left
					continue;
				END =>		# Match! 
					thl[tlp].se[0].q1 = p;
					newmatch(thl[tlp].se);
				* =>		# regular character 
					if(inst.typex==c){
						if(++nnl >= NLIST)
							raise OVERFLOW;
						addinst(nl, inst.next, thl[tlp].se);
					}
				}
				tlp++;
				inst = thl[tlp].inst;
			}
		}
		return (sel[0].q0>=0, sel);
	}
	exception{
		OVERFLOW =>
			error("regexp list overflow");
			sel[0].q0 = -1;
			return (0, sel);
	}
	return (0, sel);
}

newmatch(sp : Rangeset)
{
	if(sel[0].q0<0 || sp[0].q0<sel[0].q0 ||
	   (sp[0].q0==sel[0].q0 && sp[0].q1>sel[0].q1))
		sel[0:] = sp[0:NRange];
}

rxbexecute(t : ref Text, startp : int) : (int, Rangeset)
{
	flag : int;
	inst : ref Inst;
	tlp : int;
	p : int;
	nnl, ntl : int;
	c : int;
	wrapped : int;
	startchar : int;

	flag = 0;
	nnl = 0;
	wrapped = 0;
	p = startp;
	startchar = 0;
	if(bstartinst.typex<OPERATOR)
		startchar = bstartinst.typex;
	listx[0][0].inst = listx[1][0].inst = nil;
	sel[0].q0= -1;
	
	{
		# Execute machine once for each character, including terminal NUL 
		for(;;--p){
			if(p <= 0){
				case(wrapped++){
				0 or 2 =>		# let loop run one more click 
					;
				1 =>			# expired; wrap to end 
					if(sel[0].q0>=0)
						return (sel[0].q0>=0, sel);
					listx[0][0].inst = listx[1][0].inst = nil;
					p = t.file.buf.nc+1;
					continue;
				3 or * =>
					return (sel[0].q0>=0, sel);
				}
				c = 0;
			}else{
				if(((wrapped && p<=startp) || sel[0].q0>0) && nnl==0)
					break;
				c = t.readc(p-1);
			}
			# fast check for first char 
			if(startchar && nnl==0 && c!=startchar)
				continue;
			thl = listx[flag];
			nl = listx[flag^=1];
			nl[0].inst = nil;
			ntl = nnl;
			nnl = 0;
			if(sel[0].q0<0 && (!wrapped || p>startp)){
				# Add first instruction to this list 
				if(++ntl >= NLIST)
					raise OVERFLOW;
				# the minus is so the optimizations in addinst work 
				sempty[0].q0 = -p;
				addinst(thl, bstartinst, sempty);
			}
			# Execute machine until this list is empty 
			tlp = 0;
			inst = thl[0].inst;
			while(inst != nil){	# assignment = 
				case(inst.typex){
				LBRA =>
					if(inst.subid>=0)
						thl[tlp].se[inst.subid].q0 = p;
					inst = inst.next;
					continue;
				RBRA =>
					if(inst.subid >= 0)
						thl[tlp].se[inst.subid].q1 = p;
					inst = inst.next;
					continue;
				ANY =>
					if(c != '\n') {
						if(++nnl >= NLIST)
							raise OVERFLOW;
						addinst(nl, inst.next, thl[tlp].se);
					}
				BOL =>
					if(c=='\n' || p==0){
						inst = inst.next;
						continue;
					}
				EOL =>
					if(p<t.file.buf.nc && t.readc(p)=='\n') {
						inst = inst.next;
						continue;
					}
				CCLASS =>
					if(c>0 && classmatch(inst.class, c, 0)) {
						if(++nnl >= NLIST)
							raise OVERFLOW;
						addinst(nl, inst.next, thl[tlp].se);
					}
				NCCLASS =>
					if(c>0 && classmatch(inst.class, c, 1)) {
						if(++nnl >= NLIST)
							raise OVERFLOW;
						addinst(nl, inst.next, thl[tlp].se);
					}
				OR =>
					# evaluate right choice later 
					if(++ntl >= NLIST)
						raise OVERFLOW;
					addinst(thl[tlp:], inst.right, thl[tlp].se);
					# efficiency: advance and re-evaluate 
					inst = inst.next;	# next was left
					continue;
				END =>		# Match! 
					thl[tlp].se[0].q0 = -thl[tlp].se[0].q0; # minus sign 
					thl[tlp].se[0].q1 = p;
					bnewmatch(thl[tlp].se);
				* =>	# regular character 
					if(inst.typex == c){
						if(++nnl >= NLIST)
							raise OVERFLOW;
						addinst(nl, inst.next, thl[tlp].se);
					}
				}
				tlp++;
				inst = thl[tlp].inst;
			}
		}
		return (sel[0].q0>=0, sel);
	}
	exception{
		OVERFLOW =>
			error("regexp list overflow");
			sel[0].q0 = -1;
			return (0, sel);
	}
	return (0, sel);
}

bnewmatch(sp : Rangeset)
{
        i : int;

        if(sel[0].q0<0 || sp[0].q0>sel[0].q1 || (sp[0].q0==sel[0].q1 && sp[0].q1<sel[0].q0))
                for(i = 0; i<NRange; i++){       # note the reversal; q0<=q1 
                        sel[i].q0 = sp[i].q1;
                        sel[i].q1 = sp[i].q0;
                }
}
