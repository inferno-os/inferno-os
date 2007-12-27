Styxflush: module {
	PATH: con "/dis/lib/styxflush.dis";
	Einterrupted: con "interrupted";
	init: fn();
	tmsg: fn(m: ref Styx->Tmsg, flushc: chan of (int, chan of int), reply: chan of ref Styx->Rmsg): (int, ref Styx->Rmsg);
	rmsg: fn(m: ref Styx->Rmsg): int;
};
