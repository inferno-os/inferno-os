implement Format;

#
# Formatter registry - loads and caches text formatter modules.
# Matches file extensions to the appropriate formatter (mdfmt, htmlfmt).
#

include "sys.m";
	sys: Sys;

include "formatter.m";
include "format.m";

# Cached formatter modules
Entry: adt {
	modpath: string;
	extensions: string;
	mod: Formatter;
};

entries: list of ref Entry;

init()
{
	sys = load Sys Sys->PATH;
	entries = nil;

	# Register built-in formatters
	register("/dis/xenith/render/mdfmt.dis");
	register("/dis/xenith/render/htmlfmt.dis");
}

# Register a formatter module
register(modpath: string)
{
	mod := load Formatter modpath;
	if(mod == nil)
		return;
	mod->init();
	inf := mod->info();
	if(inf == nil)
		return;

	entries = ref Entry(modpath, inf.extensions, mod) :: entries;
}

# Find a formatter for the given file path
find(path: string): (Formatter, string)
{
	ext := getext(path);
	if(ext == nil)
		return (nil, "no file extension");

	for(e := entries; e != nil; e = tl e){
		ent := hd e;
		if(matchext(ext, ent.extensions))
			return (ent.mod, nil);
	}

	return (nil, "no formatter for " + ext);
}

# Check if a path has a text formatter available
hasformatter(path: string): int
{
	ext := getext(path);
	if(ext == nil)
		return 0;

	for(e := entries; e != nil; e = tl e)
		if(matchext(ext, (hd e).extensions))
			return 1;

	return 0;
}

# Extract lowercase extension from path
getext(path: string): string
{
	if(path == nil)
		return nil;

	dot := -1;
	for(i := len path - 1; i >= 0; i--){
		if(path[i] == '.'){
			dot = i;
			break;
		}
		if(path[i] == '/')
			break;
	}
	if(dot < 0)
		return nil;

	ext := path[dot:];
	# Lowercase
	lext := "";
	for(i = 0; i < len ext; i++){
		c := ext[i];
		if(c >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		lext[len lext] = c;
	}
	return lext;
}

# Check if ext matches any extension in space-separated list
matchext(ext: string, extensions: string): int
{
	i := 0;
	while(i < len extensions){
		# Skip spaces
		while(i < len extensions && extensions[i] == ' ')
			i++;
		if(i >= len extensions)
			break;
		# Collect extension
		start := i;
		while(i < len extensions && extensions[i] != ' ')
			i++;
		e := extensions[start:i];
		if(e == ext)
			return 1;
	}
	return 0;
}
