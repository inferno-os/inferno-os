implement Exctest;

#
# exctest: where exceptions are caught. Each case prints the same line
# whether the module is interpreted or compiled (emu -c0, -c1).
#

include "sys.m";
	sys: Sys;
include "draw.m";

Exctest: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

Typed: exception(string);
nok, nfail: int;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	# a write to a closed pipe raises an exception in the writer
	for(depth := 0; depth < 3; depth++){
		c := chan of string;
		spawn pipeproc(depth, c);
		check(sys->sprint("closed pipe, handler %d frames above the write", depth), <-c, sys->sprint("caught at %d", depth));
	}
	check("string exception, same function", str0(), "caught: boom");
	check("string exception, from a callee", str1(), "caught: boom");
	check("string exception, from two calls down", str2(), "caught: boom");
	check("typed exception, same function", typed0(), "caught typed: t");
	# beyond the function that raised it a typed exception is a string
	check("typed exception, from a callee, as a string", typed1(), "caught as string: Exctest.0.Typed");
	check("nil array sliced, same function", nilslice(), "caught");
	check("array index out of range, same function", bounds(1), "caught");
	check("array index out of range, from a callee", bounds2(), "caught");
	check("division by zero, same function", divzero(0), "caught");
	check("handler chosen by pattern", pattern(), "second");
	sys->print("exctest: %d ok, %d failed\n", nok, nfail);
	if(nfail)
		raise "fail:failed";
}

check(what, got, want: string)
{
	if(got == want){
		nok++;
		sys->print("ok   %s\n", what);
	}else{
		nfail++;
		sys->print("FAIL %s: got %q, want %q\n", what, got, want);
	}
}

pipeproc(depth: int, c: chan of string)
{
	{
		c <-= p2(depth);
	}exception{
	"*" =>
		c <-= "escaped";
	}
}

p2(depth: int): string
{
	r: string;
	{
		r = p1(depth);
	}exception{
	"write on closed pipe" =>
		return "caught at 2";
	}
	return r;
}

p1(depth: int): string
{
	r: string;
	{
		r = p0(depth);
	}exception e{
	"write on closed pipe" =>
		if(depth > 1)
			raise e;
		return "caught at 1";
	}
	return r;
}

p0(depth: int): string
{
	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0)
		return "no pipe";
	fds[0] = nil;
	n := 0;
	{
		n = sys->write(fds[1], array of byte "x", 1);
	}exception e{
	"write on closed pipe" =>
		if(depth > 0)
			raise e;
		return "caught at 0";
	}
	return sys->sprint("write returned %d", n);
}

boom(n: int): string
{
	if(n > 0)
		return boom(n-1) + ".";
	raise "boom";
}

str0(): string
{
	{
		raise "boom";
	}exception e{
	"boom" =>
		return "caught: " + e;
	}
	return "not raised";
}

str1(): string
{
	{
		return boom(0);
	}exception e{
	"boom" =>
		return "caught: " + e;
	}
}

str2(): string
{
	{
		return boom(1);
	}exception e{
	"boom" =>
		return "caught: " + e;
	}
}

typed0(): string
{
	{
		raise Typed("t");
	}exception e{
	Typed =>
		return "caught typed: " + e;
	}
	return "not raised";
}

# recursive, so that the compiler does not put it in line
raisetyped(n: int)
{
	if(n > 0)
		raisetyped(n-1);
	raise Typed("t");
}

typed1(): string
{
	{
		raisetyped(1);
	}exception e{
	Typed =>
		return "caught typed: " + e;
	"*" =>
		return "caught as string: " + e;
	}
	return "not raised";
}

nilslice(): string
{
	buf: array of byte;
	{
		b := buf[0:1];
		return "not raised " + string len b;
	}exception{
	"*" =>
		return "caught";
	}
}

bounds(n: int): string
{
	a := array[n] of int;
	{
		a[n+2] = 1;
	}exception{
	"array bounds*" or "*bounds*" =>
		return "caught";
	}
	return "not raised";
}

index(a: array of int, n: int): int
{
	if(n < 0)
		return index(a, n+1);
	return a[n];
}

bounds2(): string
{
	a := array[2] of int;
	{
		return "not raised " + string index(a, 5);
	}exception{
	"*" =>
		return "caught";
	}
}

divzero(z: int): string
{
	{
		return "not raised " + string (10/z);
	}exception{
	"*" =>
		return "caught";
	}
}

pattern(): string
{
	{
		raise "second: thing";
	}exception{
	"first*" =>
		return "first";
	"second*" =>
		return "second";
	"*" =>
		return "other";
	}
	return "not raised";
}
