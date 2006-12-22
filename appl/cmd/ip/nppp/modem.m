Modem: module
{
	PATH:	con "/dis/ip/nppp/modem.dis";

	ModemInfo: adt {
		path:			string;
		init:			string;
		country:		string;
		other:		string;
		errorcorrection:string;
		compression:	string;
		flowctl:		string;
		rateadjust:	string;
		mnponly:		string;
		dialtype:		string;
		hangup:		string;
	};

	Device: adt {
		lock:	ref Lock->Semaphore;
		# modem stuff
		ctl:	ref Sys->FD;
		data:	ref Sys->FD;

		local:	string;
		remote:	string;
		status:	string;
		speed:	int;
		t:		ModemInfo;
		trace:	int;

		# input reader
		avail:	array of byte;
		pid:		int;

		new:		fn(i: ref ModemInfo, trace: int): ref Device;
		dial:		fn(m: self ref Device, number: string): string;
		getc:		fn(m: self ref Device, msec: int): int;
		getinput:	fn(m: self ref Device, n: int): array of byte;
		send:	fn(m: self ref Device, x: string): string;
		close:	fn(m: self ref Device): ref Sys->Connection;
		onhook:	fn(m: self ref Device);
	};

	init:	fn(): string;

};
