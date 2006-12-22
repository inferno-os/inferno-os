Reports: module {
	PATH: con "/dis/alphabet/reports.dis";
	Report: adt {
		startc: chan of (string, chan of string, chan of int);
		enablec: chan of int;
	
		enable:	fn(r: self ref Report);
		start:		fn(r: self ref Report, name: string): chan of string;
		add:		fn(r: self ref Report, name: string, errorc: chan of string, stopc: chan of int);
	};
	KILL, PROPAGATE: con 1<<iota;
	reportproc: fn(errorc: chan of string, stopc: chan of int, reply: chan of ref Report);
	quit: fn(errorc: chan of string);
	report: fn(errorc: chan of string, err: string);
	newpgrp: fn(stopc: chan of int, flags: int): chan of int;
};
