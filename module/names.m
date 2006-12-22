Names: module
{
	PATH:	con "/dis/lib/names.dis";

	cleanname:	fn(name: string): string;
	dirname:	fn(name: string): string;
	basename:	fn(name: string, suffix: string): string;
	elements:	fn(name: string): list of string;
	isprefix:	fn(a: string, b: string): int;
	pathname:	fn(els: list of string): string;
	rooted:	fn(root: string, name: string): string;
	relative:	fn(name: string, root: string): string;
};
