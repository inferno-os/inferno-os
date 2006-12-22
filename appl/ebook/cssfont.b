implement CSSfont;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Font: import draw;
include "units.m";
	units: Units;
include "cssfont.m";

# locally available font styles
BOLD, CW, ITALIC, PLAIN, NSTYLES: con iota;
NSIZES: con 5;			# number of locally available font sizes

fonts := array[] of {
	PLAIN => array[] of {
		"/fonts/charon/plain.tiny.font",
		"/fonts/charon/plain.small.font",
		"/fonts/charon/plain.normal.font",
		"/fonts/charon/plain.large.font",
		"/fonts/charon/plain.vlarge.font",
	},
	BOLD => array[] of {
		"/fonts/charon/bold.tiny.font",
		"/fonts/charon/bold.small.font",
		"/fonts/charon/bold.normal.font",
		"/fonts/charon/bold.large.font",
		"/fonts/charon/bold.vlarge.font",
		},
	CW => array[] of {
		"/fonts/charon/cw.tiny.font",
		"/fonts/charon/cw.small.font",
		"/fonts/charon/cw.normal.font",
		"/fonts/charon/cw.large.font",
		"/fonts/charon/cw.vlarge.font",
		},
	ITALIC => array[] of {
		"/fonts/charon/italic.tiny.font",
		"/fonts/charon/italic.small.font",
		"/fonts/charon/italic.normal.font",
		"/fonts/charon/italic.large.font",
		"/fonts/charon/italic.vlarge.font",
	},
};

fontinfo := array[NSTYLES] of array of ref Font;
sizechoice := array[NSTYLES] of array of byte;

init(displ: ref Draw->Display)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	units = load Units Units->PATH;
	if (units == nil) {
		sys->fprint(sys->fildes(2), "cssfont: cannot load %s: %r\n", Units->PATH);
		raise "fail:bad module";
	}
	units->init();

	for (i := 0; i < len fonts; i++) {
		fpaths := fonts[i];
		fontinfo[i] = array[len fpaths] of ref Font;

		# could make this process lazier, only computing sizes
		# when a font of a particular class was asked for.
		maxheight := 0;
		for (j := 0; j < len fpaths; j++) {
			if ((fontinfo[i][j] = f := Font.open(displ, fpaths[j])) == nil) {
				sys->fprint(sys->fildes(2), "cssfont: font %s unavailable: %r\n", fpaths[j]);
				raise "fail:font unavailable";
			}
			if (f.height > maxheight)
				maxheight = f.height;
		}
		sizechoice[i] = array[maxheight + 1] of byte;
		for (j = 0; j < maxheight + 1; j++)
			sizechoice[i][j] = byte matchheight(j, fontinfo[i]);
	}

#	for (i = 0; i < NSTYLES; i++) {
#		sys->print("class %d\n", i);
#		for (j := 0; j < NSIZES; j++) {
#			sys->print("	height %d; translates to %d [%d]\n",
#				fontinfo[i][j].height,
#				int sizechoice[i][fontinfo[i][j].height],
#				fontinfo[i][int sizechoice[i][fontinfo[i][j].height]].height);
#		}
#	}
}

# find the closest match to a given desired height from the choices given.
matchheight(desired: int, choices: array of ref Font): int
{
	n := len choices;
	if (desired <= choices[0].height)
		return 0;
	if (desired >= choices[n - 1].height)
		return n - 1;
	for (i := 1; i < n; i++) {
		if (desired >= choices[i - 1].height &&
				desired <= choices[i].height) {
			if (desired - choices[i - 1].height <
					choices[i].height - desired)
				return i - 1;
			else
				return i;
		}
	}
	sys->fprint(sys->fildes(2), "cssfont: can't happen!\n");
	raise "error";
	return -1;		# should never happen
}

# get an appropriate font given the css specification.
getfont(spec: Spec, parentem, parentex: int): (string, int, int)
{
#sys->print("getfont size:%s family:%s; style:%s; weight:%s -> ",
#		spec.size, spec.family, spec.style, spec.weight);
	class := getclass(spec);
	i := choosesize(class, spec.size, parentem, parentex);

#sys->print("%s (height:%d)\n", fonts[class][i], fontinfo[class][i].height);

	# XXX i suppose we should really find out what height(widgth?) the 'x' is.
	return (fonts[class][i], fontinfo[class][i].height, fontinfo[class][i].height);
}

getclass(spec: Spec): int
{
	if (spec.family == "monospace")
		return CW;
	if (spec.style == "italic")
		return ITALIC;
	if (spec.weight == "bold")
		return BOLD;
	return PLAIN;
}

choosesize(class: int, size: string, parentem, parentex: int): int
{
	if (size != nil && (size[0] >= '0' && size[0] <= '9')) {
		(height, nil) := units->length(size, parentem, parentex, nil);
		choices := sizechoice[class];
		if (height > len choices)
			height = len choices - 1;
		return int choices[height];
	}
	case size {
	"xx-small" or
	"x-small" =>
		return 0;
	"small" =>
		return 1;
	"medium" =>
		return 2;
	"large" =>
		return 3;
	"x-large" or
	"xx-large" =>
		return 4;
	"larger" or
	"smaller" =>
		choice := sizechoice[class];
		if (parentem >= len choice)
			parentem = len choice - 1;
		i := int choice[parentem];
		if (size[0] == 's') {
			if (i > 0)
				i--;
		} else {
			if (i < len fonts[class] - 1)
				i++;
		}
		return i;
	* =>
		sys->fprint(sys->fildes(2), "cssfont: unknown font size spec '%s'\n", size);
		return 2;
	}
}
