Ir: module
{
	PATH:	con	"/dis/lib/ir.dis";
	SIMPATH:	con	"/dis/lib/irsim.dis";
	MPATH:	con	"/dis/lib/irmpath.dis";
	SAGEPATH:	con	"/dis/lib/irsage.dis";

	#
	# "standard" remote buttons
	#
	Zero:	con 0;
	One:	con 1;
	Two:	con 2;
	Three:	con 3;
	Four:	con 4;
	Five:	con 5;
	Six:	con 6;
	Seven:	con 7;
	Eight:	con 8;
	Nine:	con 9;
	ChanUP:	con 10;
	ChanDN:	con 11;
	VolUP:	con 12;
	VolDN:	con 13;
	FF:	con 14;
	Rew:	con 15;
	Up:	con 16;
	Dn:	con 17;
	Select:	con 18;
	Power:	con 19;
	Enter:	con 20;
	Rcl:	con 21;
	Record:	con 22;
	Mute:	con 23;
	#
	# Control
	#
	Error:	con 9999;
	EOF:	con -1;

	init: 		fn(c, p: chan of int): int;
	translate:	fn(c: int): int;
};
