implement Readstrokes;

#
# read structures from stroke classifier files
#

include "sys.m";
	sys: Sys;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "strokes.m";
	strokes: Strokes;
	Classifier, Penpoint, Stroke, Region: import strokes;
	buildstrokes: Buildstrokes;

init(s: Strokes)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	strokes = s;
}

getint(fp: ref Iobuf): (int, int)
{
	while((c := fp.getc()) == ' ' || c == '\t' || c == '\n')
		;
	if(c < 0)
		return (c, 0);
	sign := 1;
	if(c == '-')
		sign = -1;
	else if(c == '+')
		;
	else
		fp.ungetc();
	rc := 0;
	n := 0;
	while((c = fp.getc()) >= '0' && c <= '9'){
		n = n*10 + (c-'0');
		rc = 1;
	}
	return (rc, n*sign);
}

getstr(fp: ref Iobuf): (int, string)
{
	while((c := fp.getc()) == ' ' || c == '\t' || c == '\n')
		;
	if(c < 0)
		return (c, nil);
	fp.ungetc();
	s := "";
	while((c = fp.getc()) != ' ' && c != '\t' && c != '\n')
		s[len s] = c;
	return (0, s);
}

getpoint(fp: ref Iobuf): (int, Penpoint)
{
	(okx, x) := getint(fp);
	(oky, y) := getint(fp);
	if(okx <= 0 || oky <= 0)
		return (-1, (0,0,0));
	return (0, (x,y,0));
}

getpoints(fp: ref Iobuf): ref Stroke
{
	(ok, npts) := getint(fp);
	if(ok <= 0 || npts < 0 || npts > 4000)
		return nil;
	pts := array[npts] of Penpoint;
	for(i := 0; i < npts; i++){
		(ok, pts[i]) = getpoint(fp);
		if(ok < 0)
			return nil;
	}
	return ref Stroke(npts, pts, 0, 0);
}

read_classifier_points(fp: ref Iobuf, nclass: int): (int, array of string, array of list of ref Stroke)
{
	names := array[nclass] of string;
	examples := array[nclass] of list of ref Stroke;
	for(k := 0; k < nclass; k++){
		# read class name and number of examples
		(ok, nex) := getint(fp);
		if(ok <= 0)
			return (-1, nil, nil);
		(ok, names[k]) = getstr(fp);
		if(ok < 0)
			return (ok, nil, nil);

		# read examples
		for(i := 0; i < nex; i++){
			pts := getpoints(fp);
			if(pts == nil)
				return (-1, nil, nil);
			examples[k] = pts :: examples[k];
		}
	}
	return (0, names, examples);
}

#
# read a classifier, using its digest if that exists
#
read_classifier(file: string, build: int, needex: int): (string, ref Classifier)
{
	rc := ref Classifier;
	l := len file;
	digestfile: string;
	if(l >= 4 && file[l-4:]==".clx")
		digestfile = file;
	else if(!needex && l >= 3 && file[l-3:]==".cl")
		digestfile = file[0:l-3]+".clx";	# try the digest file first
	err: string;
	if(digestfile != nil){
		fd := sys->open(digestfile, Sys->OREAD);
		if(fd != nil){
			(err, rc.cnames, rc.dompts) = read_digest(fd);
			rc.nclasses = len rc.cnames;
			if(rc.cnames == nil)
				err = "empty digest file";
			if(err == nil)
				return (nil, rc);
		}else
			err = sys->sprint("%r");
		if(!build)
			return (sys->sprint("digest file: %s", err), nil);
	}

	if(buildstrokes == nil){
		buildstrokes = load Buildstrokes Buildstrokes->PATH;
		if(buildstrokes == nil)
			return (sys->sprint("module %s: %r", Buildstrokes->PATH), nil);
		buildstrokes->init(strokes);
	}

	fd := sys->open(file, Sys->OREAD);
	if(fd == nil)
		return (sys->sprint("%r"), nil);
	(emsg, cnames, examples) := read_examples(fd);
	if(emsg != nil)
		return (emsg, nil);
	rc.nclasses = len cnames;
	(err, rc.canonex, rc.dompts) = buildstrokes->canonical_example(rc.nclasses, cnames, examples);
	if(err != nil)
		return ("failed to calculate canonical examples", nil);
	rc.cnames = cnames;
	if(needex)
		rc.examples = examples;

	return (nil, rc);
}

read_examples(fd: ref Sys->FD): (string, array of string, array of list of ref Strokes->Stroke)
{
	fp := bufio->fopen(fd, Bufio->OREAD);
	(ok, nclasses) := getint(fp);
	if(ok <= 0)
		return ("missing number of classes", nil, nil);
	(okc, cnames, examples) := read_classifier_points(fp, nclasses);
	if(okc < 0)
		return ("couldn't read examples", nil, nil);
	return (nil, cnames, examples);
}

#
# attempt to read the digest of a classifier,
# and return its contents if successful;
# return a diagnostic if not
#
read_digest(fd: ref Sys->FD): (string, array of string, array of ref Stroke)
{
	#  Read-in the name and dominant points for each class.
	fp := bufio->fopen(fd, Bufio->OREAD);
	cnames := array[32] of string;
	dompts := array[32] of ref Stroke;
	for(nclasses := 0;; nclasses++){
		if(nclasses >= len cnames){
			a := array[nclasses+32] of string;
			a[0:] = cnames;
			cnames = a;
			b := array[nclasses+32] of ref Stroke;
			b[0:] = dompts;
			dompts = b;
		}
		(okn, class) := getstr(fp);
		if(okn == Bufio->EOF)
			break;
		if(class == nil)
			return ("expected class name", nil, nil);
		cnames[nclasses] = class;
		dpts := getpoints(fp);
		if(dpts == nil)
			return ("bad points list", nil, nil);
		strokes->compute_chain_code(dpts);
		dompts[nclasses] = dpts;
	}
	return (nil, cnames[0:nclasses], dompts[0:nclasses]);
}
