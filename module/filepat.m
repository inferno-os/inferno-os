Filepat: module
{
	PATH:	con "/dis/lib/filepat.dis";
	
	# Turn file name with * ? [] into list of files.  Slashes are significant.
	expand:	fn(pat: string): list of string;

	# See if file name matches pattern; slashes not treated specially.
	match:	fn(pat, name: string): int;
};
