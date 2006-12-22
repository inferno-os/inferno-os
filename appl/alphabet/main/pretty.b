implement Pretty, Mainmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	n_BLOCK,  n_VAR, n_BQ, n_BQ2, n_REDIR,
	n_DUP, n_LIST, n_SEQ, n_CONCAT, n_PIPE, n_ADJ,
	n_WORD, n_NOWAIT, n_SQUASH, n_COUNT,
	n_ASSIGN, n_LOCAL,
	GLOB: import Sh;
include "alphabet/reports.m";
	reports: Reports;
		Report, report: import reports;
include "alphabet.m";
	alphabet: Alphabet;
		Value: import alphabet;

Pretty: module {};

typesig(): string
{
	return "sc";
}

init()
{
	sys = load Sys Sys->PATH;
	alphabet = load Alphabet Alphabet->PATH;
	sh = load Sh Sh->PATH;
	sh->initialise();
}

quit()
{
}

run(nil: ref Draw->Context, nil: ref Reports->Report, nil: chan of string,
		nil: list of (int, list of ref Value),
		args: list of ref Value): ref Value
{
	{
		return ref Value.Vs(pretty((hd args).c().i, 0));
	}exception{
	"bad expr" =>
		return nil;
	}
}

pretty(n: ref Sh->Cmd, depth: int): string
{
	if (n == nil)
		return nil;
	s: string;
	case n.ntype {
	n_BLOCK =>
		s = "{\n"+tabs(depth+1)+pretty(n.left,depth+1) + "\n"+tabs(depth)+"}";
	n_VAR =>
		s = "$" + pretty(n.left, depth);
	n_LIST =>
		s = "(" + pretty(n.left, depth) + ")";
	n_SEQ =>
		s = pretty(n.left, depth) + "\n"+tabs(depth)+pretty(n.right, depth);
	n_PIPE =>
		s = pretty(n.left, depth) + " |\n"+tabs(depth)+pretty(n.right, depth);
	n_ADJ =>
		s = pretty(n.left, depth) + " " + pretty(n.right, depth);
	n_WORD =>
		s = quote(n.word, 1);
	n_BQ2 =>
		# if we can't do it, revert to ugliness.
		{
			s = "\"" + pretty(n.left, depth);
		} exception {
		"bad expr" =>
			s = sh->cmd2string(n);
		}
	* =>
		raise "bad expr";
	}
	return s;
}

tabs(n: int): string
{
	s: string;
	while(n-- > 0)
		s[len s] = '\t';
	return s;
}

# stolen from sh.y
quote(s: string, glob: int): string
{
	needquote := 0;
	t := "";
	for (i := 0; i < len s; i++) {
		case s[i] {
		'{' or '}' or '(' or ')' or '`' or '&' or ';' or '=' or '>' or '<' or '#' or
		'|' or '*' or '[' or '?' or '$' or '^' or ' ' or '\t' or '\n' or '\r' =>
			needquote = 1;
		'\'' =>
			t[len t] = '\'';
			needquote = 1;
		GLOB =>
			if (glob) {
				if (i < len s - 1)
					i++;
			}
		}
		t[len t] = s[i];
	}
	if (needquote || t == nil)
		t = "'" + t + "'";
	return t;
}
