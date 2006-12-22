#
# simple adt that operates on whitespace separated config files
# such as /services/webget/config
#
CfgFile: module
{
	PATH: con	"/dis/lib/cfgfile.dis";
	ConfigFile: adt
	{
		getcfg:	fn(me: self ref ConfigFile,field:string):list of string;
		setcfg:	fn(me: self ref ConfigFile,field:string,val:string);
		delete:	fn(me: self ref ConfigFile,field:string);
		flush:	fn(me: self ref ConfigFile): string;

		 # ----- private ------
		lines:	list of string;
		file:	string;
		readonly:	int;
	};

	init:	fn(file:string):ref ConfigFile;
	verify:	fn(defaultpath: string, path: string) :ref Sys->FD;
};
