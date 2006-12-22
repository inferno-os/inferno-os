implement Newtypeset, Abcmodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "alphabet/reports.m";
	reports: Reports;
	report: import reports;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "alphabet.m";
include "alphabet/abc.m";
	abc: Abc;
	Value, Vtype: import abc;

# types abc -> types
#	returns a set of types defined in terms of the types and modules in $1
# stdtypes types -> types
#	adds the standard root types to $1
# newtype [-u] types string string cmd -> types
#	adds a new type named $2 to $1; the underlying type will be $3, and the destructor $4.
#	-u flag implies values of this type cannot be duplicated.
# modules types -> modules
#	returns a value suitable for defining modules in terms of types defined in $1,
#	containing no module definitions.
# module modules string string cmd -> modules
# newtypeset abc string modules -> abc

# declares adds some autoconversions:
# 
# 	autoconvert abc types "{| types}
# 	autoconvert types modules "{| modules}
# 
# declares "{(abc)
# 	autodeclare 1 |
# 	newtypeset $1 /images {
#		abc |
#		autoconvert 1 |
# 		newtype image /fd "{} |
# 		newmodule read '/fd -> image' "{
#			| /filter "{canonimage}
#		} |
# 		newmodule rotate 'image -> image' "{
#			| /filter "{rotate}
#		} |
# 		newmodule display 'image -> /status' "{
#			| /filter "{showimage} | /create /dev/null
#		}
# 	} |
# 	type /images/image |
# 	import /images/rotate |
# 	autoconvert /string /fd "{|/read} |
# 	autoconvert /fd image "{|/images/read} |
# 	autoconvert image /status "{|/images/display}
# }
# 
# -{rotate x.bit}

Newtypeset: module {};
types(): string
{
	return "AAsm";
}

init()
{
	sys = load Sys Sys->PATH;
	reports = checkload(load Reports Reports->PATH, Reports->PATH);
	abc = checkload(load Abc Abc->PATH, Abc->PATH);
	abc->init();
}

quit()
{
}

run(errorc: chan of string, nil: ref Reports->Report,
		nil: list of (int, list of ref Value),
		args: list of ref Value
	): ref Value
{
	a := (hd args).A().i.alphabet;
	d := (hd tl args).s().i;
	path := "/dis/alphabet/" + d + "/alphabet"
	iob := bufio->open(, Sys->OREAD);
	if(iob == nil){
		report(errorc, sys->sprint("scripttypeset: cannot open %q: %r", path));
		return nil;
	}
	{
		(types, decls) := parse(iob);
		alphabet := load Alphabet Alphabet->PATH;
		if(alphabet == nil){
			report(errorc, sys->sprint("scripttypeset: cannot load %q: %r", Alphabet->PATH));
			return nil;
		}
		declares := load Declares Declares->PATH;
		if(declares == nil){
			report(errorc, sys->sprint("scripttypeset: cannot load %q: %r", Alphabet->PATH));
			return nil;
		}
		if((err := declares->declares(alphabet, decls, errorc)) != nil){
			report(errorc, "scripttypeset: error on declarations: "+err);
			return nil;
		}
		declares->quit();
		declares = nil;
		if(checktypes(alphabet, types, errorc) == -1)
			return nil;
		spawn scripttypesetproc(alphabet, types, c := chan of ref Proxy->Typescmd[ref Alphabet->Value]);
		if((err := a->loadtypeset(d, c, errorc)) != nil){
			c <-= nil;
			return nil;
		}
		return (hd args).dup();
	} exception e {
	"parse:*" =>
		report(errorc, sys->sprint("scripttypeset: error parsing %q: %s", path, e[6:]));
		return nil;
	}
}

checktypes(alphabet: Alphabet, types: list of ref Type, errorc: chan of string): int
{
	for(; types != nil; types = tl types){
		t := hd types;
		if(t.destructor != nil){
			report(errorc, "destructors not supported yet");
		}
	}
}

scripttypesetproc(alphabet: Alphabet, types: list of ref Type, c: chan of Proxy->Typescmd[ref Alphabet->Value])
{
	while((gr := <-c) != nil){
		pick r := gr {
		Alphabet =>
		Load =>
		

checkload[T](m: T, path: string): T
{
	if(m != nil)
		return m;
	raise sys->sprint("fail:cannot load %s: %r", path);
}
