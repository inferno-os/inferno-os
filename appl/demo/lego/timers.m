Timers : module{
	Timer : adt {
		id : int;
		tick : chan of int;

		reset : fn (t : self ref Timer);
		cancel : fn (t : self ref Timer);
		destroy : fn (t : self ref Timer);
	};

	init : fn (res : int);
	new : fn(ms, rep : int) : ref Timer;
};


