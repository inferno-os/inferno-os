implement RegexUtils;

# matching and substitution functions
# evb@lucent.com

include "sys.m";
	sys: Sys;
	
include "regexutils.m";

init()
{
	if (sys == nil)
		sys = load Sys Sys->PATH;
		
	regex = load Regex Regex->PATH;
	if (regex == nil)
		raise "fail: Regex not loaded";
}

match(pattern: Regex->Re, s: string): string
{
	pos := regex->execute(pattern, s);
	if (pos == nil)
		return "";
	(beg, end) := pos[0];
	
	return s[beg:end];
}

match_mult(pattern: Regex->Re, s: string): array of (int, int)
{
	return regex->execute(pattern, s);
}

sub(text, pattern, new: string): string
{
	return sub_re(text, regex->compile(pattern, 0).t0, new);
}

sub_re(text: string, pattern: Regex->Re, new: string): string
{
	pos := regex->execute(pattern, text);
	if (pos == nil) 
		return text;
	
	(beg, end) := pos[0];
	newline := text[:beg] + new + text[end:];
	return newline;
}

subg(text, pattern, new: string): string
{
	return subg_re(text, regex->compile(pattern, 0).t0, new);
}

subg_re(text: string, pattern: Regex->Re, new: string): string
{
	oldtext := text;
	while ( (text = sub_re(text, pattern, new)) != oldtext) {
		oldtext = text;
	}

	return text;
}
