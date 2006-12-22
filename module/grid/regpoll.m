RegPoll : module {
	PATH: con "/usr/danny/res/regpoll.dis";

	STOPPED, STARTED, ERROR: con iota;
	init : fn (regaddr: string): (chan of int, chan of int);
};
