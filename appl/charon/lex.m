Lex: module
{
	PATH: con "/dis/charon/lex.dis";

	# HTML 4.0 tags (blink, nobr)
	# sorted in lexical order; used as array indices
	Notfound, Comment,
	Ta, Tabbr, Tacronym, Taddress, Tapplet, Tarea, Tb,
		Tbase, Tbasefont, Tbdo, Tbig, Tblink, Tblockquote, Tbody,
		Tbq, Tbr, Tbutton, Tcaption, Tcenter, Tcite, Tcode, Tcol, Tcolgroup,
		Tdd, Tdel, Tdfn, Tdir, Tdiv, Tdl, Tdt, Tem,
		Tfieldset, Tfont, Tform, Tframe, Tframeset,
		Th1, Th2, Th3, Th4, Th5, Th6, Thead, Thr, Thtml, Ti, Tiframe, Timage,
		Timg, Tinput, Tins, Tisindex, Tkbd, Tlabel, Tlegend, Tli, Tlink, Tmap,
		Tmenu, Tmeta, Tnobr, Tnoframes, Tnoscript,
		Tobject, Tol, Toptgroup, Toption, Tp, Tparam, Tpre,
		Tq, Ts, Tsamp, Tscript, Tselect, Tsmall, Tspan, Tstrike, Tstrong,
		Tstyle, Tsub, Tsup, Ttable, Ttbody, Ttd, Ttextarea, Ttfoot, Tth,
		Tthead, Ttitle, Ttr, Ttt, Tu, Tul, Tvar, Txmp,
		Numtags
			: con iota;
	RBRA : con Numtags;
	Data: con Numtags+RBRA;

	tagnames: array of string;

	# HTML 4.0 tag attributes
	# Keep sorted in lexical order
	Aabbr, Aaccept, Aaccept_charset, Aaccesskey, Aaction,
		Aalign, Aalink, Aalt, Aarchive, Aaxis,
		Abackground, Abgcolor, Aborder,
		Acellpadding, Acellspacing, Achar, Acharoff,
		Acharset, Achecked, Acite, Aclass, Aclassid, Aclear,
		Acode, Acodebase, Acodetype,
		Acolor, Acols, Acolspan, Acompact, Acontent, Acoords,
		Adata, Adatafld, Adataformatas, Adatapagesize, Adatasrc,
		Adatetime, Adeclare, Adefer, Adir, Adisabled,
		Aenctype, Aevent,
		Aface, Afor, Aframe, Aframeborder,
		Aheaders, Aheight, Ahref, Ahreflang, Ahspace, Ahttp_equiv,
		Aid, Aismap, Alabel, Alang, Alanguage, Alink, Alongdesc, Alowsrc,
		Amarginheight, Amarginwidth, Amaxlength, Amedia, Amethod, Amultiple,
		Aname, Anohref, Anoresize, Anoshade, Anowrap, Aobject,
		Aonabort, Aonblur, Aonchange, Aonclick, Aondblclick,
		Aonerror, Aonfocus, Aonkeydown, Aonkeypress, Aonkeyup, Aonload,
		Aonmousedown, Aonmousemove, Aonmouseout, Aonmouseover,
		Aonmouseup, Aonreset, Aonresize, Aonselect, Aonsubmit, Aonunload,
		Aprofile, Aprompt, Areadonly, Arel, Arev, Arows, Arowspan, Arules,
		Ascheme, Ascope, Ascrolling, Aselected, Ashape, Asize,
		Aspan, Asrc, Astandby, Astart, Astyle, Asummary,
		Atabindex, Atarget, Atext, Atitle, Atype, Ausemap,
		Avalign, Avalue, Avaluetype, Aversion, Avlink, Avspace, Awidth,
		Numattrs
			: con iota;

	attrnames: array of string;

	Token: adt
	{
		tag:		int;
		text:		string;	# text in Data, attribute text in tag
		attr:		list of Attr;

		aval: fn(t: self ref Token, attid: int) : (int, string);
		tostring: fn(t: self ref Token) : string;
	};

	Attr: adt
	{
		attid:		int;
		value:	string;
	};

	# A source of HTML tokens.
	# After calling new with a ByteSource (which is past 'gethdr' stage),
	# call gettoks repeatedly until get nil.  Errors are signalled by exceptions.
	# Possible exceptions raised:
	#	EXInternal		(start, gettoks)
	#	exGeterror	(gettoks)
	#	exAbort		(gettoks)
	TokenSource: adt
	{
		b: ref CharonUtils->ByteSource;
		chset: Btos;				# charset converter
		state : ref TSstate;
		mtype: int;				# CU->TextHtml or CU->TextPlain
		inxmp: int;

		new: fn(b: ref CharonUtils->ByteSource, chset : Btos, mtype: int) : ref TokenSource;
		gettoks: fn(ts: self ref TokenSource) : array of ref Token;
		setchset: fn(ts: self ref TokenSource, conv : Btos);
	};

	TSstate : adt {
		bi : int;
		prevbi : int;
		s : string;
		si : int;
		csstate : Convcs->State;
		prevcsstate : Convcs->State;
	};
	

	init: fn(cu: CharonUtils);
};
