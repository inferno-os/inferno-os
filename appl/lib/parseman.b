implement Parseman;

include "sys.m";
include "bufio.m";
include "man.m";

sys: Sys;
bufio: Bufio;
Iobuf: import bufio;

FONT_LITERAL: con -1;

init(): string
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
		return sys->sprint("cannot load module: %r");
	return nil;
}

ParseState: adt[T]
	for{
	T =>
		textwidth: fn(t: self T, text: Text): int;
	}{
	metrics: Metrics;
	ql: int;		# quote Literal text
	margin: int;
	mstack: list of int;
	istack: list  of int;
	indent: int;
	ntlsetindent: int;	#copy prevailindent to indent on n.t.l
	prevailindent: int;
	curfont: int;
	curattr: int;
	verbatim: int;
	pspace: int;
	curline: list of (int, Text);	# most recent first
	curwidth: int;
	newpara: int;
	heading: int;
	igto: string;
	link: string;
	viewer: T;
	setline: chan of list of (int, Text);

	# addstring() is simply an addtext() of the current font
	addstring: fn(s: self ref ParseState, s: string);
	addtext: fn(s: self ref ParseState, t: list of Text);
	brk: fn(s: self ref ParseState);
	paragraph: fn( s: self ref ParseState);
};

parseman[T](fd: ref Sys->FD, metrics: Metrics, ql: int, viewer: T, setline: chan of list of (int, Text))
	for{
	T =>
		textwidth: fn(t: self T, text: Text): int;
	}
{
	iob := bufio->fopen(fd, Sys->OREAD);
	state := ref ParseState[T](metrics, ql, 0, nil, nil, 0, 0, metrics.indent, FONT_ROMAN, 0, 0, 1, nil, 0, 1, 0, "", nil, viewer, setline);
	while ((l := iob.gets('\n')) != nil) {
		if (l[len l -1] == '\n')
			l = l[0: len l - 1];
		if (state.igto != nil && state.igto != l)
			continue;
		state.igto = nil;
		parseline(state, l);
	}
	state.pspace = 2;
	state.pspace = 1;
	state.paragraph();
	footer := Text(FONT_ROMAN, 0, "Inferno Manual", 0, nil);
	textw := state.viewer.textwidth(footer);
#should do 'center' in addtext (state.justify = CENTER)
	state.indent = (state.metrics.pagew - textw) / 2;
	state.addtext(footer::nil);
	state.brk();
	setline <- = nil;
}

parseline[T](state: ref ParseState[T], t: string)
	for{
	T =>
		textwidth: fn(t: self T, text: Text): int;
	}
{
	if (t == nil) {
		if (state.verbatim) {
			blank := Text(state.curfont, state.curattr, "", 0, "");
			state.setline <- = (0, blank)::nil;
		} else
			state.paragraph();
		return;
	}
	ntlsetindent := state.ntlsetindent;
	state.ntlsetindent = 0;
	if (t[0] == '.' || t[0] == '\'')
		parsemacro(state, t[1:]);
	else {
		state.addtext(parsetext(state, t));
		if (state.verbatim)
			state.brk();
	}
	if (ntlsetindent) {
		state.indent = state.prevailindent;
		if (state.curwidth + state.metrics.en > state.indent + state.margin)
			state.brk();
	}
}

parsemacro[T](state: ref ParseState[T], t: string)
	for{
	T =>
		textwidth: fn(t: self T, text: Text): int;
	}
{
	for (n := 0; n < len t && n < 2; n++)
		if (t[n] == ' '  || t[n] == '\t')
			break;
	macro := t[0:n];
	params: list of string;
	quote := 0;
	param := 0;
	esc := 0;
	p := "";
	for (; n < len t; n++) {
		if (esc)
			esc = 0;
		else {
			case t[n] {
			' ' or '\t' =>
				if (!quote) {
					if (param) {
						params = p :: params;
						p = "";
						param = 0;
					}
				continue;
				}
			'"' =>
				param = 1;
				quote = !quote;
				continue;
			'\\' =>
				esc = 1;
			}
		}
		param = 1;
		p[len p] = t[n];
	}
	if (param)
		params = p :: params;
	plist: list of string;
	for (; params != nil; params = tl params)
		plist = hd params :: plist;
	params = plist;

	case macro {
		"ig" =>
			igto := "..";
			if (params != nil)
				igto = "." + hd params;
			state.brk();
			state.igto = igto;
		"sp" =>
			sp := "1";
			if(params != nil)
				sp = hd params;
			d := tval(state.metrics, sp, 'v');
			gap := d / state.metrics.V;
			if (gap < 1)
				gap = 1;
			while (gap--)
				state.paragraph();
		"br" =>
			state.brk();
		"nf" =>
			state.verbatim = 1;
		"fi" =>
			state.verbatim = 0;
		"ti" =>
			state.brk();
			#i := 0;
			#if(params != nil)
			#	i = tval(state.metrics, hd params, 'n');
			#state.ntlsetindent = 1;
			#state.prevailindent = i;
		"in" =>
			state.brk();
			#i := 0;
			#if(params != nil)
			#	i = tval(state.metrics, hd params, 'n');
			#state.indent = i;
			#state.prevailindent = state.indent;
		"1C" =>
			state.brk();
			# not implemented
		"2C" =>
			state.brk();
			# not implemented
		"BI" =>
			altattr(state, FONT_BOLD, FONT_ITALIC, params);
		"BR" =>
			altattr(state, FONT_BOLD, FONT_ROMAN, params);
		"IB" =>
			altattr(state, FONT_ITALIC, FONT_BOLD, params);
		"IR" =>
			# need to determine link if params of valid form
			state.link = convlink(params);;
			altattr(state, FONT_ITALIC, FONT_ROMAN, params);
			state.link = nil;
		"RB" =>
			altattr(state, FONT_ROMAN, FONT_BOLD, params);
		"RI" =>
			altattr(state, FONT_ROMAN, FONT_ITALIC, params);
		"B" =>
			state.curfont = FONT_BOLD;
			if (params != nil) {
				for (; params != nil; params = tl params) {
					textl := parsetext(state, hd params);
					for (; textl != nil; textl = tl textl)
						state.addtext(hd textl::nil);
				}
				state.curfont = FONT_ROMAN;
			}
		"I" =>
			state.curfont = FONT_ITALIC;
			if (params != nil) {
				for (; params != nil; params = tl params) {
					textl := parsetext(state, hd params);
					for (; textl != nil; textl = tl textl)
						state.addtext(hd textl::nil);
				}
				state.curfont = FONT_ROMAN;
			}
 		"SM"=>
			state.curattr |= ATTR_SMALL;
			if (params != nil) {
				for (; params != nil; params = tl params)
					state.addstring(hd params);
				state.curattr &= ~ATTR_SMALL;
			}
		"L" =>
			state.curfont = FONT_LITERAL;
			if (params != nil) {
				str := "`";
				for (pl := params; pl != nil;) {
					str += hd pl;
					if ((pl = tl pl) != nil)
						str += " ";
					else
						break;
				}
				str += "'";
				state.addstring(str);
				state.curfont = FONT_ROMAN;
			}
		"LR" =>
			if (params != nil) {
				l := Text(FONT_LITERAL, state.curattr, hd params, 0, nil);
				t: list of Text;
				params = tl params;
				if (params == nil)
					t = l :: nil;
				else {
					r := Text(FONT_ROMAN, state.curattr, hd params, 0, nil);
					t = l :: r :: nil;
				}
				state.addtext(t);
			}
		"RL" =>
			if (params != nil) {
				r := Text(FONT_ROMAN, state.curattr, hd params, 0, nil);
				t: list of Text;
				params = tl params;
				if (params == nil)
					t = r :: nil;
				else {
					l := Text(FONT_LITERAL, state.curattr, hd params, 0, nil);
					t = r :: l :: nil;
				}
				state.addtext(t);
			}
		"DT" =>
			# not yet supported
			;
		"EE" =>
			state.brk();
			state.verbatim = 0;
			state.curfont = FONT_ROMAN;
		"EX" =>
			state.brk();
			state.verbatim = 1;
			state.curfont = FONT_BOLD;
		"HP" =>
			state.paragraph();
			i := state.metrics.indent;
			if (params != nil)
				i = tval(state.metrics, hd params, 'n');
			state.prevailindent = state.indent + i;
		"IP" =>
			state.paragraph();
			i := state.metrics.indent;
			if (params != nil) {
				tag := hd params;
				params = tl params;
				state.addtext(parsetext(state, tag));
				if (params != nil)
					i = tval(state.metrics, hd params, 'n');
			}
			state.indent = state.metrics.indent + i;
			state.prevailindent = state.indent;
		"PD" =>
			state.pspace = 1;
			if (params != nil) {
				v := tval(state.metrics, hd params, 'v') / state.metrics.V;
				state.pspace = v;
			}
		"LP" or "PP" =>
			state.paragraph();
			state.prevailindent = state.indent;
		"RE" =>
			state.brk();
			if (state.mstack == nil || state.istack == nil)
				break;
			
			state.margin = hd state.mstack;
			state.mstack = tl state.mstack;
			state.prevailindent = hd state.istack;
			state.indent = state.prevailindent;
			state.istack = tl state.istack;
		"RS" =>
			state.brk();
			i := state.prevailindent - state.metrics.indent;
			if (params != nil)
				i = tval(state.metrics, hd params, 'n');
			state.mstack = state.margin :: state.mstack;
			state.istack = state.prevailindent :: state.istack;
			state.margin += i;
			state.indent = 2 * state.metrics.indent;
			state.prevailindent = state.indent;
		"SH" =>
			state.paragraph();
			state.prevailindent = state.indent;
			state.curfont = FONT_ROMAN;
			state.curattr = 0;
			state.indent = 0;
			state.heading = 1;
			state.verbatim = 0;

			for (pl := params; pl != nil; pl = tl pl)
				state.addstring(hd pl);

			state.heading = 0;
			state.brk();
			state.newpara = 1;
			state.pspace = 1;
		"SS" =>
			state.paragraph();
			state.prevailindent = state.indent;
			state.curfont = FONT_ROMAN;
			state.curattr = 0;
			state.indent = state.metrics.ssindent;
			state.heading = 2;

			for (pl := params; pl != nil; pl = tl pl)
				state.addstring(hd pl);

			state.heading = 0;
			state.brk();
			state.newpara = 1;
			state.pspace = 1;

		"TF" =>
			state.brk();
			state.pspace = 0;
			i := state.metrics.indent;
			if (params != nil) {
				str := hd params;
				text := Text(FONT_BOLD, 0, str, 0, nil);
				w := state.viewer.textwidth(text) + 2*state.metrics.em;
				if (w > i)
					i = w;
			}
			state.indent = state.metrics.indent;;
			state.prevailindent = state.indent + i;
		"TH" =>
			state.brk();
			if (len params < 2)
				break;
			str := hd params + "(" + hd tl params + ")";
			txt := Text(FONT_ROMAN, 0, str, 0, nil);
			txtw := state.viewer.textwidth(txt);
			state.indent = 0;
			state.addtext(txt::nil);
			state.indent = state.metrics.pagew - txtw;
			state.addtext(txt::nil);
			state.indent = 0;
			state.brk();
		"TP" =>
			state.paragraph();
			if (state.prevailindent == state.metrics.indent)
				state.prevailindent += state.metrics.indent;
			state.indent = state.metrics.indent;
			state.ntlsetindent = 1;
			if (params != nil) {
				i := tval(state.metrics, hd params, 'n');
				if (i == 0)
					i = state.metrics.indent;
				state.prevailindent = state.indent + i;
			}
		* =>
			;
	}
	if (state.verbatim)
		state.brk();
}

parsetext[T](state: ref ParseState[T], t: string): list of Text
	for{
	T =>
		textwidth: fn(t: self T, text: Text): int;
	}
{
	# need to do better here - spot inline font changes etc
	# we also currently cannot support troff tab stops
	textl: list of Text;
	line := "";
	curfont := state.curfont;
	prevfont := state.curfont;	# should perhaps be in State
	step := 1;
	for (i := 0; i < len t; i += step) {
		step = 1;
		ch := t[i];
		if (ch == '\\') {
			i++;
			width := len t - i;
			if (width <= 0)
				break;
			case t[i] {
			'-' or '.' or '\\' =>
				ch = t[i];
			' '  =>
				ch = ' ';
			'e' =>
				ch = '\\';
			'|' or '&' =>
				continue;
			'(' =>
				if (width > 3)
					width = 3;
				step = width;
				if (step != 3)
					continue;
				case t[i+1:i+3] {
				"bu" =>
					ch = '•';
				"em" =>
					ch = '—';
				"mi" =>
					ch = '-';
				"mu" =>
					ch = '×';
				"*m" =>
					ch = 'µ';
				"*G" =>
					ch = 'Γ';
				"*p" =>
					ch = 'π';
				"*b" =>
					ch = 'β';
				"<=" =>
					ch = '≤';
				"->" =>
					ch = '→';
				* =>
					continue;
				}

			'f' =>
				if (width == 1)
					continue;
				if (t[i+1] == '(') {
					if (width > 4)
						width = 4;
					step = width;
					continue;
				}
				i++;
				case t[i] {
				'0' or 'R' =>
					curfont = FONT_ROMAN;
				'1' or 'I' =>
					curfont = FONT_ITALIC;
				'2' =>
					# should be bold but our 'bold' font is constant width
					curfont = FONT_ROMAN;
				'5' or 'L' =>
					curfont = FONT_BOLD;
				'P' =>
					curfont = prevfont;
				}
				continue;
			'*' =>
				if (width == 1)
					continue;
				case t[i+1] {
				'R' =>
					step = 2;
					ch = '®';
				'(' =>
					if (width > 4)
						width = 4;
					step = width;
					continue;
				}
			* =>
				i--;
			}
		}
		if (curfont != state.curfont) {
			if (line != "") {
				txt := Text(state.curfont, state.curattr, line, state.heading, state.link);
				line = "";
				textl = txt :: textl;
			}
			prevfont = state.curfont;
			state.curfont = curfont;
		}
		line[len line] = ch;
	}
	if (line != "") {
		txt := Text(state.curfont, state.curattr, line, state.heading, state.link);
		textl = txt :: textl;
	}
	state.curfont = curfont;

	r: list of Text;
	for (; textl != nil; textl = tl textl)
		r = hd textl :: r;
	return r;
}

ParseState[T].addstring(state: self ref ParseState[T], s: string)
{
	t := Text(state.curfont, state.curattr, s, state.heading, state.link);
	state.addtext(t::nil);
}

ParseState[T].addtext(state: self ref ParseState[T], t: list of Text)
{
#dumptextlist(t);
	# on setting a line copy state.prevailindent to state.indent
	#
	# always make sure that current indent is achieved
	#
	# if FONT_LITERAL and state.ql then convert to FONT_BOLD and
	# quote the text before any other processing

	state.newpara = 0;
	addspace := 1;
	while (t != nil) {
		# this scheme is inadequate...
		# results in mixed formatting at end of line getting split up
		# e.g.
		#	.IR man (1)
		# can get split at the '('

		indent := 0;
		spacew := 0;
		text := hd t;
		t = tl t;
		if (state.indent + state.margin > state.curwidth || state.curline == nil) {
			indent = state.indent + state.margin;
			state.curwidth = indent;
			addspace = 0;
			if (!state.verbatim) {
				text.text = trim(text.text);
				while (text.text == "" && t != nil) {
					text = hd t;
					t = tl t;
					text.text = trim(text.text);
				}
			}
		}

		if (text.font == FONT_LITERAL) {
			if (state.ql)
				text.text = "`" + text.text + "'";
			text.font = FONT_BOLD;
		}
		if (addspace) {
			(nil, previtem) := hd state.curline;
			if (previtem.text[len previtem.text -1] == ' ')
				addspace = 0;
			else {
				space := Text(previtem.font, previtem.attr, " ", 0, nil);
				spacew = state.viewer.textwidth(space);
			}
		}
		# it doesn't fit - try to word wrap...
		t2 := text;
		end := len text.text;
		prevend := end;
		nextstart := 0;
		while (end > 0) {
			t2.text = text.text[0:end];
			tlen := state.viewer.textwidth(t2);
			if (state.verbatim || state.curwidth + spacew + tlen <= state.metrics.pagew) {
				# easy - just add it!
				state.curwidth += spacew+tlen;
				if (addspace) {
					t2.text = " " + t2.text;
					addspace = 0;
				}
				state.curline = (indent, t2) :: state.curline;
				indent = 0;
				break;
			}
			prevend = end;
			for (; end > 0; end--) {
				if (t2.text[end-1] == ' ') {
					nextstart = end;
					for (; end >0 && t2.text[end-1] == ' '; end--)
						;
					break;
				}
			}
		}
		if (end != len text.text) {
			# couldn't fit whole item onto line
			if (state.curline == nil) {
				# couldn't fit (sub)item on empty line - add it anyway
				# as there is nowhere else to put it
				end = prevend;
				t2.text = text.text[0:end];
				state.curline = (indent, t2) :: state.curline;
				if (nextstart != 0) {
					text.text = text.text[nextstart:];
					t = text :: t;
				}
			} else {
				# already stuff on line and we have consumed upto nexstart of
				# the current item
				if (end != 0)
					text.text = text.text[nextstart:];
				t = text :: t;
			}
			state.brk();
		}
		addspace = 0;
	}
}

trim(s: string): string
{
	for (spi :=0; spi < len s && s[spi] == ' '; spi++)
			;
	return s[spi:];
}

ParseState[T].brk(state: self ref ParseState)
{
	if (state.curline != nil) {
		line: list of (int, Text);
		for (l := state.curline; l != nil; l = tl l)
			line = hd l :: line;
		state.setline <- = line;
		state.curline = nil;
		state.curwidth = 0;
	}
	state.indent = state.prevailindent;
}

ParseState[T].paragraph(state: self ref ParseState)
{
	state.brk();
	if (state.newpara == 0) {
		blank := Text(state.curfont, state.curattr, "", 0, "");
		for (i := 0; i < state.pspace; i++)
			state.setline <- = (0, blank)::nil;
		state.newpara = 1;
	}
	state.curattr = 0;
	state.curfont = FONT_ROMAN;
	state.indent = state.metrics.indent;
#	state.prevailindent = state.indent;
	state.ntlsetindent = 0;
}

# convert troff 'values' into output 'dots'
tval(m: Metrics, v: string, defunits: int): int
{
	if (v == nil)
		return 0;
	units := v[len v -1];
	val: real;

	case units {
	'i' or
	'c' or
	'P' or
	'm' or
	'n' or
	'p' or
	'u' or
	'v' =>
		val = real v[0:len v - 1];
	* =>
		val = real v;
		units = defunits;
	}
	r := 0;
	case units {
	'i' =>
		r = int (real m.dpi * val);
	'c' =>
		r =  int ((real m.dpi * val)/2.54);
	'P' =>
		r =  int ((real m.dpi * val)/ 6.0);
	'm' =>
		r =  int (real m.em * val);
	'n' =>
		r =  int (real m.en * val);
	'p' =>
		r =  int ((real m.dpi * val)/72.0);
	'u' =>
		r =  int val;
	'v' =>
		r =  int (real m.V * val);
	}
	return r;
}

altattr[T](state: ref ParseState[T], f1, f2: int, strs: list of string)
	for{
	T =>
		textwidth: fn(t: self T, text: Text): int;
	}
{
	index := 0;
	textl: list of Text;

	prevfont := state.curfont;
	for (; strs != nil; strs = tl strs) {
		str := hd strs;
		f := f1;
		if (index++ & 1)
			f = f2;
		state.curfont = f;
		newtext := parsetext(state, str);
		for (; newtext != nil; newtext = tl newtext)
			textl = hd newtext :: textl;
	}
	orderedtext: list of Text;
	for (; textl != nil; textl = tl textl)
		orderedtext = hd textl :: orderedtext;
	state.addtext(orderedtext);
	state.curfont = prevfont;
}

dumptextlist(t: list of Text)
{
	sys->print("textlist[");
	for (; t != nil; t = tl t) {
		s := hd t;
		sys->print("(%s)", s.text);
	}
	sys->print("]\n");
}

convlink(params: list of string): string
{
	# merge the texts
	s := "";
	for (; params != nil; params = tl params)
		s = s + (hd params);

	for (i := 0; i < len s; i ++)
		if (s[i] == '(')
			break;
	if (i+1 >= len s)
		return nil;
	cmd := s[0:i];
	i++;
	s = s[i:];
	for (i = 0; i < len s; i++)
		if (s[i] == ')')
			break;
	section := s[0:i];
	if (section == nil || !isint(section))
		return nil;

	return section + " " + cmd;
}

isint(s: string): int
{
	for (i := 0; i < len s; i++)
		if (s[i] != '.' && (s[i] < '0' || s[i] > '9'))
			return 0;
	return 1;
}
