Readjpg: module
{

	PATH: con "/dis/grid/readjpg.dis";

	ImageSource: adt
	{
		width:	int;
		height:	int;
		origw:	int;
		origh:	int;
		i:		int;
		jstate:	ref Jpegstate;
		data:		array of byte;
	};

	Jpegstate: adt
	{
		# variables in i/o routines
		sr:	int;	# shift register, right aligned
		cnt:	int;	# # bits in right part of sr
	
		Nf:		int;
		comp:	array of Framecomp;
		mode:	byte;
		X,Y:		int;
		qt:		array of array of int;	# quantization tables
		dcht:		array of ref Huffman;
		acht:		array of ref Huffman;
		Ns:		int;
		scomp:	array of Scancomp;
		Ss:		int;
		Se:		int;
		Ah:		int;
		Al:		int;
		ri:		int;
		nseg:	int;
		nblock:	array of int;
		
		# progressive scan
		dccoeff:	array of array of int;
		accoeff:	array of array of array of int;	# only need 8 bits plus quantization
		nacross:	int;
		ndown:	int;
		Hmax:	int;
		Vmax:	int;
	};
	
	Huffman: adt
	{
		bits:	array of int;
		size:	array of int;
		code:	array of int;
		val:	array of int;
		mincode:	array of int;
		maxcode:	array of int;
		valptr:	array of int;
		# fast lookup
		value:	array of int;
		shift:	array of int;
	};
		
	Framecomp: adt	# Frame component specifier from SOF marker
	{
		C:	int;
		H:	int;
		V:	int;
		Tq:	int;
	};
	
	Scancomp: adt	# Frame component specifier from SOF marker
	{
		C:	int;
		tdc:	int;
		tac:	int;
	};
	
	# Constants, all preceded by byte 16rFF
	SOF:	con 16rC0;	# Start of Frame
	SOF2:	con 16rC2;	# Start of Frame; progressive Huffman
	DHT:	con 16rC4;	# Define Huffman Tables
	RST:	con 16rD0;	# Restart interval termination
	SOI:	con 16rD8;	# Start of Image
	EOI:	con 16rD9;	# End of Image
	SOS:	con 16rDA;	# Start of Scan
	DQT:	con 16rDB;	# Define quantization tables
	DNL:	con 16rDC;	# Define number of lines
	DRI:	con 16rDD;	# Define restart interval
	APPn:	con 16rE0;	# Reserved for application segments
	COM:	con 16rFE;	# Comment

	init : fn (disp: ref Draw->Display);
	fjpg2img : fn (fd: ref sys->FD, cachepath: string, chanin, chanout: chan of string): ref Image;
	jpg2img : fn (filename, cachepath: string, chanin, chanout: chan of string): ref Image;
};