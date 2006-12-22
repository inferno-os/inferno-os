Script: module
{
	PATH:	con "/dis/ip/nppp/script.dis";

	ScriptInfo: adt {
		path:			string;
		content:		list of string;
		timeout:		int;
		username:	string;
		password:		string;
	};

	init:	fn(m: Modem): string;
	execute:	fn(m: ref Modem->Device, scriptinfo: ref ScriptInfo): string;
};
