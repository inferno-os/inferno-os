Brutus: module
{
	# Font tags are given as (font*NSIZE + size)
	Size6, Size8, Size10, Size12, Size16, NSIZE: con iota;
	Roman, Italic, Bold, Type, NFONT: con iota;
	NFONTTAG: con NFONT*NSIZE;
	Example, Caption, List, Listelem, Label, Labelref, Exercise, Heading,
		Nofill, Author, Title, Index, Indextopic, NTAG: con NFONTTAG + iota;
	DefFont: con Roman;
	DefSize: con Size10;
	TitleFont: con Bold;
	TitleSize: con Size16;
	HeadingFont: con Bold;
	HeadingSize: con Size12;

	fontname: array of string;
	sizename: array of string;
	tagname: array of string;
	tagconfig: array of string;

	init:	fn(ctxt: ref Draw->Context, args: list of string);
};
