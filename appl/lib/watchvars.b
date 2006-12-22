implement Watchvars;
include "watchvars.m";

Watchvar[T].new(v: T): Watchvar
{
	e := Watchvar[T](chan[1] of (T, chan of T));
	e.c <-= (v, chan[1] of T);
	return e;
}

Watchvar[T].get(e: self Watchvar): T
{
	(v, ic) := <-e.c;
	e.c <-= (v, ic);
	return v;
}

Watchvar[T].set(e: self Watchvar, v: T)
{
	(ov, ic) := <-e.c;
	ic <-= v;
	e.c <-= (v, chan[1] of T);
}

Watchvar[T].wait(e: self Watchvar): T
{
	(v, ic) := <-e.c;
	e.c <-= (v, ic);
	v = <-ic;
	ic <-= v;
	return v;
}

Watchvar[T].waitc(e: self Watchvar): (T, chan of T)
{
	vic := <-e.c;
	e.c <-= vic;
	return vic;
}

Watchvar[T].waited(nil: self Watchvar, ic: chan of T, v: T)
{
	ic <-= v;
}
