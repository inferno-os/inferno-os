# Copyright  © 1999 Roger Peppe.  All rights reserved.
implement Scoretable;
include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "scoretable.m";

# this is the cut-down version - it doesn't bother
# with score table locking at all; there is such a version,
# but it needs a lock server, so is often more hassle than
# it's worth. if you want a distributed score file, contact
# rog@vitanuova.com
# currently this module is only used by tetris - the interface
# will probably change in the future.

scorefile: string;
username: string;

MAXSCORES: con 10;

init(nil: int, user, nil: string, sfile: string): (int, string)
{
	if (sys == nil) {
		sys = load Sys Sys->PATH;
		stderr = sys->fildes(2);
		bufio = load Bufio Bufio->PATH;
		if (bufio == nil) {
			sys = nil;
			return (-1, sys->sprint("cannot load %s: %r", Bufio->PATH));
		}
	}
	username = user;
	lock();
	scorefd: ref Sys->FD;
	if ((scorefd = sys->open(sfile, Sys->ORDWR)) == nil
	&& (scorefd = sys->create(sfile, Sys->ORDWR, 8r666)) == nil) {
		unlock();
		return (-1, sys->sprint("cannot open %s: %r", sfile));
	}
	unlock();
	scorefile = sfile;
	return (0, nil);
}

lock()
{
}

unlock()
{
}

scores(): list of Score
{
	lock();
	sl := readscores();
	unlock();
	return sl;
}
	
readscores(): list of Score
{
	sl: list of Score;
	iob := bufio->open(scorefile, Sys->OREAD);
	if (iob == nil)
		return nil;
	iob.seek(big 0, Bufio->SEEKSTART);
	while ((s := iob.gets('\n')) != nil) {
		(n, toks) := sys->tokenize(s, " \t\n");
		if (toks == nil)
			continue;
		if (n < 2) {
			sys->fprint(stderr, "bad line in score table: %s", s);
			continue;
		}
		score: Score;
		(score.user, toks) = (hd toks, tl toks);
		(score.score, toks) = (int hd toks, tl toks);
		score.other = nil;
		while (toks != nil) {
			score.other += hd toks;
			if (tl toks != nil)
				score.other += " ";
			toks = tl toks;
		}
		sl = score :: sl;
	}
	iob.close();
	nl: list of Score;
	while (sl != nil) {
		nl = hd sl :: nl;
		sl = tl sl;
	}
	return nl;
}

writescores(sl: list of Score)
{
	scoreiob := bufio->open(scorefile, Sys->OWRITE|Sys->OTRUNC);
	if (scoreiob == nil) {
		sys->fprint(stderr, "scoretable: cannot write score file '%s': %r\n", scorefile);
		return;
	}
	scoreiob.seek(big 0, Bufio->SEEKSTART);
	n := 0;
	while (sl != nil && n < MAXSCORES) {
		s := hd sl;
		scoreiob.puts(sys->sprint("%s %d %s\n", s.user, s.score, s.other));
		n++;
		sl = tl sl;
	}
	scoreiob.close();
}

setscore(score: int, other: string): int
{
	lock();
	sl := readscores();
	nl: list of Score;
	done := 0;
	n := rank := 0;
	while (sl != nil) {
		s := hd sl;
		if (score > s.score && !done) {
			nl = Score(username, score, other) :: nl;
			rank = n;
			done = 1;
		}
		nl = s :: nl;
		sl = tl sl;
		n++;
	}
	if (!done) {
		nl = Score(username, score, other) :: nl;
		rank = n;
	}
	sl = nil;
	while (nl != nil) {
		sl = hd nl :: sl;
		nl = tl nl;
	}
	writescores(sl);
	unlock();
	# XXX minor race condition in returning the rank, not our idea of the rank.
	return rank;
}
