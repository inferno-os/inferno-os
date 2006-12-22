Mashparse: module {

	PATH:	con "/dis/lib/mashparse.dis";

	init:		fn(l: Mashlib);
	parse:	fn(e: ref Mashlib->Env);

	YYSTYPE: adt
	{
		cmd:		ref Mashlib->Cmd;
		item:		ref Mashlib->Item;
		items:	list of ref Mashlib->Item;
		flag:		int;
	};

	YYETYPE:	type ref Mashlib->Env;
Lcase: con	57346;
Lfor: con	57347;
Lif: con	57348;
Lwhile: con	57349;
Loffparen: con	57350;
Lelse: con	57351;
Lpipe: con	57352;
Leqeq: con	57353;
Lmatch: con	57354;
Lnoteq: con	57355;
Lcons: con	57356;
Lcaret: con	57357;
Lnot: con	57358;
Lhd: con	57359;
Ltl: con	57360;
Llen: con	57361;
Lword: con	57362;
Lbackq: con	57363;
Lcolon: con	57364;
Lcolonmatch: con	57365;
Ldefeq: con	57366;
Leq: con	57367;
Lmatched: con	57368;
Lquote: con	57369;
Loncurly: con	57370;
Lonparen: con	57371;
Loffcurly: con	57372;
Lat: con	57373;
Lgreat: con	57374;
Lgreatgreat: con	57375;
Lless: con	57376;
Llessgreat: con	57377;
Lfn: con	57378;
Lin: con	57379;
Lrescue: con	57380;
Land: con	57381;
Leof: con	57382;
Lsemi: con	57383;
Lerror: con	57384;
};
