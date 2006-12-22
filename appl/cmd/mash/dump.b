#
#	Output routines.
#

#
#	Echo list of strings.
#
echo(e: ref Env, s: list of string)
{
	out := e.outfile();
	if (out == nil)
		return;
	out.putc('+');
	for (t := s; t != nil; t = tl t) {
		out.putc(' ');
		out.puts(hd t);
	}
	out.putc('\n');
	out.close();
}

#
#	Return text representation of Word/Item/Cmd.
#

Word.word(w: self ref Word, d: string): string
{
	if (w == nil)
		return nil;
	if (d != nil)
		return d + w.text;
	if (w.flags & Wquoted)
		return enquote(w.text);
	return w.text;
}

Item.text(i: self ref Item): string
{
	if (i == nil)
		return nil;
	case i.op {
	Icaret =>
		return i.left.text() + " ^ " + i.right.text();
	Iicaret =>
		return i.left.text() + i.right.text();
	Idollarq =>
		return i.word.word("$\"");
	Idollar or Imatch =>
		return i.word.word("$");
	Iword =>
		return i.word.word(nil);
	Iexpr =>
		return "(" + i.cmd.text() + ")";
	Ibackq =>
		return "`" + group(i.cmd);
	Iquote =>
		return "\"" + group(i.cmd);
	Iinpipe =>
		return "<" + group(i.cmd);
	Ioutpipe =>
		return ">" + group(i.cmd);
	* =>
		return "?" + string i.op;
	}
}

words(l: list of ref Item): string
{
	s: string;
	while (l != nil) {
		if (s == nil)
			s = (hd l).text();
		else
			s = s + " " + (hd l).text();
		l = tl l;
	}
	return s;
}

redir(s: string, c: ref Cmd): string
{
	if (c == nil)
		return s;
	for (l := c.redirs; l != nil; l = tl l) {
		r := hd l;
		s = s + " " + rdsymbs[r.op] + " " + r.word.text();
	}
	return s;
}

cmd2in(c: ref Cmd, s: string): string
{
	return c.left.text() + " " + s + " " + c.right.text();
}

group(c: ref Cmd): string
{
	if (c == nil)
		return "{ }";
	return redir("{ " + c.text() + " }", c);
}

sequence(c: ref Cmd): string
{
	s: string;
	do {
		r := c.right;
		t := ";";
		if (r.op == Casync) {
			r = r.left;
			t = "&";
		}
		if (s == nil)
			s = r.text() + t;
		else
			s = r.text() + t + " " + s;
		c = c.left;
	} while (c != nil);
	return s;
}

Cmd.text(c: self ref Cmd): string
{
	if (c == nil)
		return nil;
	case c.op {
	Csimple =>
		return redir(words(c.words), c);
	Cseq =>
		return sequence(c);
	Cfor =>
		return "for (" + c.item.text() + " in " + words(c.words) + ") " + c.left.text();
	Cif =>
		return "if (" + c.left.text() +") " + c.right.text();
	Celse =>
		return c.left.text() +" else " + c.right.text();
	Cwhile =>
		return "while (" + c.left.text() +") " + c.right.text();
	Ccase =>
		return redir("case " + c.left.text() + " { " + c.right.text() + "}", c);
	Ccases =>
		s := c.left.text();
		if (s[len s - 1] != '&')
			return s + "; " + c.right.text();
		return s + " " + c.right.text();
	Cmatched =>
		return cmd2in(c, "=>");
	Cdefeq =>
		return c.item.text() + " := " + words(c.words);
	Ceq =>
		return c.item.text() + " = " + words(c.words);
	Cfn =>
		return "fn " + c.item.text() + " " + group(c.left);
	Crescue =>
		return "rescue " + c.item.text() + " " + group(c.left);
	Casync =>
		return c.left.text() + "&";
	Cgroup =>
		return group(c.left);
	Clistgroup =>
		return ":" + group(c.left);
	Csubgroup =>
		return "@" + group(c.left);
	Cnop =>
		return nil;
	Cword =>
		return c.item.text();
	Ccaret =>
		return cmd2in(c, "^");
	Chd =>
		return "hd " + c.left.text();
	Clen =>
		return "len " + c.left.text();
	Cnot =>
		return "!" + c.left.text();
	Ctl =>
		return "tl " + c.left.text();
	Ccons =>
		return cmd2in(c, "::");
	Ceqeq =>
		return cmd2in(c, "==");
	Cnoteq =>
		return cmd2in(c, "!=");
	Cmatch =>
		return cmd2in(c, "~");
	Cpipe =>
		return cmd2in(c, "|");
	Cdepend =>
		return words(c.words) + " : " + words(c.left.words) + " " + c.left.text();
	Crule =>
		return c.item.text() + " :~ " + c.left.item.text() + " " + c.left.text();
	* =>
		if (c.op >= Cprivate)
			return "Priv+" + string (c.op - Cprivate);
		else
			return "?" + string c.op;
	}
	return nil;
}
