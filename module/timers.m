Timers: module
{
	PATH: con "/dis/lib/timers.dis";

	Sec: con 1000;

	Timer: adt {
		dt:	int;
		timeout:	chan of int;

		start:	fn(msec: int): ref Timer;
		stop:	fn(t: self ref Timer);
	};

	init:	fn(gran: int): int;
	shutdown:	fn();
};
