Modem: module
{
	PATH:	con "/dis/ip/ppp/modem.dis";

	ModemInfo: adt {
		path:			string;
		init:			string;
		country:		string;
		other:			string;
		errorcorrection:string;
		compression:	string;
		flowctl:		string;
		rateadjust:		string;
		mnponly:		string;
		dialtype:		string;
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
		t:		ref ModemInfo;
		# input reader
		avail:	array of byte;
		pid:		int;
	};
	
	init:		fn(i: ref ModemInfo): ref Device;
	dial:		fn( m: ref Device, number: string);
	getc:		fn(m: ref Device, timout: int): int;
	getinput:	fn(m: ref Device, n: int ): array of byte;
	send:		fn(m: ref Device, x: string): int;
	close:	fn(m: ref Device): ref Sys->Connection;
	onhook:		fn(m: ref Device);
};
