Acme : module {
	PATH : con "/dis/acme.dis";

	RELEASECOPY : con 1;

	M_LBUT : con 1;
	M_MBUT : con 2;
	M_RBUT : con 4;
	M_TBS : con 8;
	M_PLUMB : con 16;
	M_QUIT : con 32;
	M_HELP : con 64;
	M_RESIZE : con 128;
	M_DOUBLE : con 256;

	textcols, tagcols : array of ref Draw->Image;
	but2col, but3col, but2colt, but3colt : ref Draw->Image;

	acmectxt : ref Draw->Context;
	keyboardpid, mousepid, timerpid, fsyspid : int;
	fontnames : array of string;
	wdir : string;

	init : fn(ctxt : ref Draw->Context, argv : list of string);
	timing : fn(s : string);
	frgetmouse : fn();
	get : fn(p, q, r : int, b : string) : ref Dat->Reffont;
	close : fn(r : ref Dat->Reffont);
	acmeexit : fn(err : string);
	getsnarf : fn(); 
	putsnarf : fn();
};