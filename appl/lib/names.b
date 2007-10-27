implement Names;

include "sys.m";

include "names.m";

# return name rewritten to compress /+, eliminate ., and interpret ..

cleanname(name: string): string
{
	if(name == nil)
		return ".";

	p := rooted := name[0]=='/';
	if(name[0] == '#'){	# special
		if(len name < 2)
			return name;
		p += 2;	# character after # whatever it is, is the name (including /)
		for(; p < len name; p++)
			if(name[p] == '/')
				break;
		rooted = p;
	}
	dotdot := rooted;

	#
	# invariants:
	#	p points at beginning of path element we're considering.
	#	out records up to the last path element (no trailing slash unless root or #/).
	#	dotdot points in out just past the point where .. cannot backtrack
	#		any further (no slash).
	#
	out := name[0:rooted];
	while(p < len name){
		for(q := p; p < len name && name[p] != '/'; p++){
			# skip
		}
		n := name[q:p];	# path element
		p++;
		case n {
		"" or "." =>
			;	# null effect
		".." =>
			if(len out > dotdot){	# can backtrack
				for(q = len out; --q > dotdot && out[q] != '/';)
					;
				out = out[:q];
			}else if(!rooted){	# /.. is / but ./../ is ..
				if(out != nil)
					out += "/..";
				else
					out += "..";
				dotdot = len out;
			}
		* =>
			if(rooted > 1 || len out > rooted)
				out[len out] = '/';
			out += n;
		}
	}
	if(out == nil)
		return ".";
	return out;
}

dirname(name: string): string
{
	for(i := len name; --i >= 0;)
		if(name[i] == '/')
			break;
	if(i < 0)
		return nil;
	d := name[0:i];
	if(d != nil)
		return d;
	if(name[0] == '/')
		return "/";
	return nil;
}

basename(name: string, suffix: string): string
{
	for(i := len name; --i >= 0;)
		if(name[i] == '/')
			break;
	if(i >= 0)
		name = name[i+1:];
	if(suffix != nil){
		o := len name - len suffix;
		if(o >= 0 && name[o:] == suffix)
			return name[0:o];
	}
	return name;
}

relative(name: string, root: string): string
{
	if(root == nil || name == nil)
		return name;
	if(isprefix(root, name)){
		name = name[len root:];
		while(name != nil && name[0] == '/')
			name = name[1:];
	}
	return name;
}

rooted(root: string, name: string): string
{
	if(name == nil)
		return root;
	if(root == nil || name[0] == '/' || name[0] == '#')
		return name;
	if(root[len root-1] != '/' && name[0] != '/')
		return root+"/"+name;
	return root+name;
}

isprefix(a: string, b: string): int
{
	la := len a;
	while(la > 1 && a[la-1] == '/')
		a = a[0:--la];
	lb := len b;
	if(la > lb)
		return 0;
	if(la == lb)
		return a == b;
	return a == b[0:la] && (b[la] == '/' || a == "/");
}

elements(name: string): list of string
{
	sys := load Sys Sys->PATH;
	(nil, fld) := sys->tokenize(name, "/");
	if(name != nil && name[0] == '/')
		fld = "/" :: fld;
	return fld;
}

pathname(els: list of string): string
{
	name: string;
	sl := els != nil && hd els == "/";
	for(; els != nil; els = tl els){
		if(!sl)
			name += "/";
		name += hd els;
		sl = 0;
	}
	return name;
}
