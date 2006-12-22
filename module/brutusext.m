Brutusext: module
{
	# More tags, needed by Cook
	SGML, Text, Par, Extension, Float, Special: con Brutus->NTAG + iota;

	# Output formats
	FLatex, FLatexProc, FLatexBook, FLatexPart, FLatexSlides, FLatexPaper, FHtml: con iota;

	# Cook element
	Celem: adt
	{
		tag: int;
		s: string;
		contents: cyclic ref Celem;
		parent: cyclic ref Celem;
		next: cyclic ref Celem;
		prev: cyclic ref Celem;
	};


	init:	fn(sys: Sys, draw: Draw, bufio: Bufio, tk: Tk, tkclient: Tkclient);
	create:	fn(parent: string, t: ref Tk->Toplevel, name, args: string): string;
	cook:	fn(parent: string, fmt: int, args: string) : (ref Celem, string);
};
