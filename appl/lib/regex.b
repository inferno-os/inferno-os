implement Regex;

include "regex.m";

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
		return BAD;
	s.n--;
	return s.s[s.i++];
}

newRe(kind: int, left, right: refRex, set: ref Set, ar: ref Arena, pno: int): refRex
{
	ar.rex[ar.ptr] = Rex(kind, left, right, set, pno);
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
	return newRe(ALT, left, right, nil, ar, 0);
}

cat(s: ref ReStr, ar: ref Arena): refRex
{
	left := dup(s, ar);
	if(left == NIL)
		return left;
	right := cat(s, ar);
	if(right == NIL)
		return left;
	return newRe(CAT, left, right, nil, ar, 0);
}

dup(s: ref ReStr, ar: ref Arena): refRex
{
	case s.peek() {
	BAD or ')' or ']' or '|' or '?' or '*' or '+' =>
		return NIL;
	}
	prim: refRex;
	case kind:=s.next() {
	'(' =>	if(ar.pno < 0) {
			if(s.peek() == ')') {
				s.next();
				prim = newRe(NUL, NONE, NONE, nil, ar, 0);
			} else {
				prim = re(s, ar);
				if(prim==NIL || s.next()!=')')
					s.n = -1;
			}
		} else {
			pno := ++ar.pno;
			lp := newRe(LPN, NONE, NONE, nil, ar, pno);
			rp := newRe(RPN, NONE, NONE, nil, ar, pno);
			if(s.peek() == ')') {
				s.next();
				prim = newRe(CAT, lp, rp, nil, ar, 0);
				
			} else {
				prim = re(s, ar);
				if(prim==NIL || s.next()!=')')
					s.n = -1;
				else {
					prim = newRe(CAT, prim, rp, nil, ar, 0);
					prim = newRe(CAT, lp, prim, nil, ar, 0);
				}
			}
		}
	'[' =>	prim = newRe(SET, NONE, NONE, newSet(s), ar, 0);
	* =>	case kind {
		'.' =>	kind = DOT;
		'^' =>	kind = HAT;
		'$' =>	kind = DOL;
		}
		prim = newRe(esc(s, kind), NONE, NONE, nil, ar, 0);
	}
	case s.peek() {
	'*' =>	kind = CLO;
	'+' =>	kind = PCLO;
	'?' =>	kind = OPT;
	* =>	return prim;
	}
	s.next();
	return newRe(kind, prim, NONE, nil, ar, 0);
}

esc(s: ref ReStr, char: int): int
{
	if(char == '\\') {
		char = s.next();
		case char {
		BAD =>	s.n = -1;
		'n' =>	char = '\n';
		}
	}
	return char;
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
		end := newRe(OPT, r, succ, nil, ar, 0); # here's the circularity
		walk(rex.left, end, ar);
	OPT =>	walk(rex.left, succ, ar);
	}
	ar.rex[r].right = succ;
}

compile(e: string, flag: int): (Re, string)
{
	if(e == nil)
		return (nil, "missing expression");	
	s := ref ReStr(e, 0, len e);
	ar := ref Arena(array[2*s.n] of Rex, 0, 0, (flag&1)-1);
	start := ar.start = re(s, ar);
	if(start==NIL || s.n!=0)
		return (nil, "invalid regular expression");
	walk(start, NIL, ar);
	if(ar.pno < 0)
		ar.pno = 0;
	return (ar, nil);
}

# todo1, todo2: queues for epsilon and advancing transitions
Gaz: adt {
	pno: int;
	beg: int;
	end: int;
};
Trace: adt {
	cre: refRex;		# cursor in Re
	beg: int;		# where this trace began;
	gaz: list of Gaz;
};
Queue: adt {
	ptr: int;
	q: array of Trace;
};

execute(re: Re, s: string): array of (int, int)
{
	return executese(re, s, (-1,-1), 1, 1);
}

executese(re: Re, s: string, range: (int, int), bol: int, eol: int): array of (int,int)
{
	if(re==nil)
		return nil;
	(s0, s1) := range;
	if(s0 < 0)
		s0 = 0;
	if(s1 < 0)
		s1 = len s;
	gaz : list of Gaz;
	(beg, end) := (-1, -1);
	todo1 := ref Queue(0, array[re.ptr] of Trace);
	todo2 := ref Queue(0, array[re.ptr] of Trace);
	for(i:=s0; i<=s1; i++) {
		small2 := HUGE;		# earliest possible match if advance
		if(beg == -1)		# no leftmost match yet
			todo1.q[todo1.ptr++] = Trace(re.start, i, nil);
		for(k:=0; k<todo1.ptr; k++) {
			q := todo1.q[k];
			rex := re.rex[q.cre];
			next1 := next2 := NONE;
			case rex.kind {
			NUL =>
				next1 = rex.right;
			DOT =>
				if(i<len s && s[i]!='\n')
					next2 = rex.right;
			HAT =>
				if(i == s0 && bol)
					next1 = rex.right;
			DOL =>
				if(i == s1 && eol)
					next1 = rex.right;
			SET =>
				if(i<len s && member(s[i], rex.set))
					next2 = rex.right;
			CAT or
			PCLO =>
				next1 = rex.left;
			ALT or 
			CLO or 
			OPT =>
				next1 = rex.right;
				k = insert(rex.left, q.beg, q.gaz, todo1, k);
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
			* =>
				if(i<len s && rex.kind==s[i])
					next2 = rex.right;
			}
			if(next1 != NONE) {
				if(next1 != NIL)
					k =insert(next1, q.beg, q.gaz, todo1, k);
				else if(better(q.beg, i, beg, end))
					(gaz, beg, end) = (q.gaz, q.beg, i);
			}
			if(next2 != NONE) {
				if(next2 != NIL) {
					if(q.beg < small2)
						small2 = q.beg;
					insert(next2, q.beg, q.gaz, todo2, 0);
				 } else if(better(q.beg, i+1, beg, end))
					(gaz, beg, end) = (q.gaz, q.beg, i+1);
			}
			
		}
		if(beg!=-1 && beg<small2)	# nothing better possible
			break;
		(todo1,todo2) = (todo2, todo1);
		todo2.ptr = 0;
	}
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

insert(next: refRex, tbeg: int, tgaz: list of Gaz, todo: ref Queue, k: int): int
{
	for(j:=0; j<todo.ptr; j++)
		if(todo.q[j].cre == next)
			if(todo.q[j].beg <= tbeg)
			 	return k;
			else
				break;
	if(j < k)
		k--;
	if(j < todo.ptr)
		todo.ptr--;
	for( ; j<todo.ptr; j++)
		todo.q[j] = todo.q[j+1];
	todo.q[todo.ptr++] = Trace(next, tbeg, tgaz);
	return k;
}

ASCII : con 128;
WORD : con 32;

member(char: int, set: ref Set): int
{
	if(char < 128)
		return ((set.ascii[char/WORD]>>char%WORD)&1)^set.neg;
	for(l:=set.unicode; l!=nil; l=tl l) {
		(beg, end) := hd l;
		if(char>=beg && char<=end)
			return !set.neg;
	}
	return set.neg;
}

newSet(s: ref ReStr): ref Set
{
	set := ref Set(0, array[ASCII/WORD] of {* => 0}, nil);
	if(s.peek() == '^') {
		set.neg = 1;
		s.next();
	}
	while(s.n > 0) {
		char1 := s.next();
		if(char1 == ']')
			return set;
		char1 = esc(s, char1);
		char2 := char1;
		if(s.peek() == '-') {
			s.next();
			char2 = s.next();
			if(char2 == ']')
				break;
			char2 = esc(s, char2);
			if(char2 < char1)
				break;
		}
		for( ; char1<=char2; char1++)
			if(char1 < ASCII)
				set.ascii[char1/WORD] |= 1<<char1%WORD;
			else {
				set.unicode = (char1,char2)::set.unicode;
				break;
			}
	}
	s.n = -1;
	return nil;
}
