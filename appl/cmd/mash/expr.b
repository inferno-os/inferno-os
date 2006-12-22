#
#	Expression evaluation.
#

#
#	Filename pattern matching.
#
glob(e: ref Env, s: string): (string, list of string)
{
	if (filepat == nil) {
		filepat = load Filepat Filepat->PATH;
		if (filepat == nil)
			e.couldnot("load", Filepat->PATH);
	}
	l := filepat->expand(s);
	if (l != nil)
		return (nil, l);
	return (s, nil);
}

#
#	RE pattern matching.
#
match(s1, s2: string): int
{
	(re, nil) := regex->compile(s2, 0);
	return regex->execute(re, s1) != nil;
}

#
#	RE match of two lists.  Two non-singleton lists never match.
#
match2(e: ref Env, s1: string, l1: list of string, s2: string, l2: list of string): int
{
	if (regex == nil) {
		regex = load Regex Regex->PATH;
		if (regex == nil)
			e.couldnot("load", Regex->PATH);
	}
	if (s1 != nil) {
		if (s2 != nil)
			return match(s1, s2);
		while (l2 != nil) {
			if (match(s1, hd l2))
				return 1;
			l2 = tl l2;
		}
	} else if (l1 != nil) {
		if (s2 == nil)
			return 0;
		while (l1 != nil) {
			if (match(hd l1, s2))
				return 1;
			l1 = tl l1;
		}
	} else if (s2 != nil)
		return match(nil, s2);
	else if (l2 != nil) {
		while (l2 != nil) {
			if (match(nil, hd l2))
				return 1;
			l2 = tl l2;
		}
	} else
		return 1;
	return 0;
}

#
#	Test list equality.  Same length and identical members.
#
eqlist(l1, l2: list of string): int
{
	while (l1 != nil && l2 != nil) {
		if (hd l1 != hd l2)
			return 0;
		l1 = tl l1;
		l2 = tl l2;
	}
	return l1 == nil && l2 == nil;
}

#
#	Equality operator.
#
Cmd.evaleq(c: self ref Cmd, e: ref Env): int
{
	(s1, l1, nil) := c.left.eeval2(e);
	(s2, l2, nil) := c.right.eeval2(e);
	if (s1 != nil)
		return s1 == s2;
	if (l1 != nil)
		return eqlist(l1, l2);
	return s2 == nil && l2 == nil;
}

#
#	Match operator.
#
Cmd.evalmatch(c: self ref Cmd, e: ref Env): int
{
	(s1, l1, nil) := c.left.eeval2(e);
	(s2, l2, nil) := c.right.eeval2(e);
	return match2(e, s1, l1, s2, l2);
}

#
#	Catenation operator.
#
Item.caret(i: self ref Item, e: ref Env): (string, list of string, int)
{
	(s1, l1, x1) := i.left.ieval2(e);
	(s2, l2, x2) := i.right.ieval2(e);
	return caret(s1, l1, x1, s2, l2, x2);
}

#
#	Caret of lists.  A singleton distributes.  Otherwise pairwise, padded with nils.
#
caret(s1: string, l1: list of string, x1: int, s2: string, l2: list of string, x2: int): (string, list of string, int)
{
	l: list of string;
	if (s1 != nil) {
		if (s2 != nil)
			return (s1 + s2, nil, x1 | x2);
		if (l2 == nil)
			return (s1, nil, x1);
		while (l2 != nil) {
			l = (s1 + hd l2) :: l;
			l2 = tl l2;
		}
	} else if (s2 != nil) {
		if (l1 == nil)
			return (s2, nil, x2);
		while (l1 != nil) {
			l = (hd l1 + s2) :: l;
			l1 = tl l1;
		}
	} else if (l1 != nil) {
		if (l2 == nil)
			return (nil, l1, 0);
		while (l1 != nil || l2 != nil) {
			if (l1 != nil) {
				s1 = hd l1;
				l1 = tl l1;
			} else
				s1 = nil;
			if (l2 != nil) {
				s2 = hd l2;
				l2 = tl l2;
			} else
				s2 = nil;
			l = (s1 + s2) :: l;
		}
	} else if (l2 != nil)
		return (nil, l2, 0);
	return (nil, revstrs(l), 0);
}
