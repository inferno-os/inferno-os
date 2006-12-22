
Itslib: module {

	PATH: con "/dis/lib/itslib.dis";

	init: fn(): ref Tconfig;
 	S_INFO: con 0;
	S_WARN: con 1;
	S_ERROR: con 2;
	S_FATAL: con 3;
	S_STIME: con 4;
	S_ETIME: con 5;
	ENV_VERBOSITY: con "ITS_VERBOSITY";
	ENV_MFD: con "ITS_MFD";


	Tconfig: adt {
		verbosity: int;
		mfd: ref Sys->FD;
		report: fn(t: self ref Tconfig, sev: int, verb: int, msg: string);
		done: fn(t: self ref Tconfig);
	};

};
