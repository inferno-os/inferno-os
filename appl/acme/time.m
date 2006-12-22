Timerm : module {
	PATH : con "/dis/acme/time.dis";

	init : fn(mods : ref Dat->Mods);

	timerinit: fn();
	timerstart : fn(dt : int) : ref Dat->Timer;
	timerstop : fn(t : ref Dat->Timer);
	timerwaittask : fn(t : ref Dat->Timer);
};