Inflate: module
{
	PATH:	con "/dis/lib/inflate.dis";

	InflateBlock:	con 16r8000;
	InflateMask:	con 16rf0000;

	InflateEmptyIn,
	InflateFlushOut,
	InflateAck,
	InflateDone,
	InflateError:	con iota + (1 << 16) + 1;

	# conduit for data streaming between inflate and its producer/consumer
	InflateIO: adt
	{
		ibuf: array of byte;	# input buffer [InflateBlock]
		obuf: array of byte;	# output buffer [InflateBlock]
		c: chan of int;	# for inflate <-> server comm.
	};
	
	init: fn();
	reset: fn(): ref InflateIO;
	inflate: fn();
};
