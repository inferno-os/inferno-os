Tabs: module
{
	PATH:	con "/dis/lib/tabs.dis";

	init:	fn();

	mktabs:		fn(t: ref Tk->Toplevel, dot: string,
				tabs: array of (string, string),
				dflt: int): chan of string;

	tabsctl:	fn(t: ref Tk->Toplevel,
				dot: string,
				tabs: array of (string, string),
				id: int,
				s: string): int;
};
