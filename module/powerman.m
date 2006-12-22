Powerman: module
{
	PATH:	con "/dis/lib/powerman.dis";
	init:	fn(file: string, cmd: chan of string): int;
	ack:	fn(cmd: string);
	ctl:	fn(cmd: string): string;
	stop:	fn();
};
