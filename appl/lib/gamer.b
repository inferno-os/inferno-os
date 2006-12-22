implement Gamer;

include "sys.m";
include "gamer.m";

sys: Sys;
FD, Connection: import Sys;

devsysname: con "/dev/sysname";

addr: string;
stderr: ref FD;

getaddr() : int
{
	f := sys->open(devsysname, sys->OREAD);
	if (f == nil) {
		sys->fprint(stderr, "open %s failed: %r\n", devsysname);
		return -1;
	}
	buff := array[64] of byte;
	n := sys->read(f, buff, len buff);
	if (n < 0) {
		sys->fprint(stderr, "read %s failed: %r\n", devsysname);
		return -1;
	}
	addr = "tcp!" + string buff[0:n] + "!gamed";
	return 0;
}

Join(game: string) : Game
{
	g: Game;

	g.player = -1;
	if(sys == nil) {
		sys = load Sys Sys->PATH;
		stderr = sys->fildes(2);

		if (getaddr() < 0)
			return g;
	}

	(ok, c) := sys->dial(addr, nil);
	if (ok < 0) {
		sys->fprint(stderr, "dial %s failed: %r\n", addr);
		return g;
	}

	s := "join " + game;
	b := array of byte s;
	if (sys->write(c.dfd, b, len b) < 0) {
		sys->fprint(stderr, "write %s failed: %r\n", addr);
		return g;
	}

	buff := array[64] of byte;
	n := sys->read(c.dfd, buff, len buff);
	if (n < 0) {
		sys->fprint(stderr, "read %s failed: %r\n", addr);
		return g;
	}
	if (n == 0) {
		sys->fprint(stderr, "eof on read %s\n", addr);
		return g;
	}
	s = string buff[0:n];
	if (s == "error") {
		sys->fprint(stderr, "%s returns error\n", addr);
		return g;
	}
	c.dfd = nil;
	(t, l) := sys->tokenize(s, " \t\n");
	if (t != 3) {
		sys->fprint(stderr, "%s returns bad response\n", addr);
		return g;
	}
	g.opponent = hd tl l;
	player := int hd tl tl l;
	s = "local " + s;

	(ok, c) = sys->dial(addr, nil);
	if (ok < 0) {
		sys->fprint(stderr, "dial %s failed: %r\n", addr);
		return g;
	}
	b = array of byte s;
	if (sys->write(c.dfd, b, len b) < 0) {
		sys->fprint(stderr, "write %s failed: %r\n", addr);
		return g;
	}
	n = sys->read(c.dfd, buff, len buff);
	if (n < 0) {
		sys->fprint(stderr, "read %s failed: %r\n", addr);
		return g;
	}
	g.wf = c.dfd;
	if (n == 0) {
		sys->fprint(stderr, "eof on read %s\n", addr);
		return g;
	}
	s = string buff[0:n];
	if (s == "error") {
		sys->fprint(stderr, "%s returns error\n", addr);
		return g;
	}
	g.rf = sys->open(s, sys->OREAD);
	if (g.rf == nil) {
		sys->fprint(stderr, "pipe open %s failed: %r\n", s);
		return g;
	}
	g.player = player;
	return g;
}

Game.In(g: self Game) : int
{
	buff := array[1] of byte;

	if ((rd := sys->read(g.rf, buff, 1)) == 1)
		return int buff[0];

	if (rd < 0)
		sys->fprint(stderr, "gamed read failed: %r\n");

	g.rf = nil;
	return -1;
}

Game.Out(g: self Game, i: int)
{
	buff := array[1] of byte;

	buff[0] = byte i;
	if (sys->write(g.wf, buff, 1) != 1) {
		sys->fprint(stderr, "gamed write failed: %r\n");
		g.wf = nil;
		return;
	}
}

Game.Exit(g: self Game)
{
	g.Out(255);
	g.rf = nil;
	g.wf = nil;
}
