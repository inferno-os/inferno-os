NSys: module
{
	# Unique file identifier for file objects
	Qid: adt
	{
		path:	big;
		vers:	int;
		qtype:	int;
	};

	QTDIR:	con 16r80;
	QTAPPEND:	con 16r40;
	QTEXCL:	con 16r20;
	QTAUTH:	con 16r08;
	QTTMP:	con 16r04;
	QTFILE:	con 0;

	# Return from stat and directory read
	Dir: adt
	{
		name:	string;
		uid:	string;
		gid:	string;
		muid:	string;
		qid:	Qid;
		mode:	int;
		atime:	int;
		mtime:	int;
		length:	big;
		dtype:	int;
		dev:	int;
	};

	# Maximum read which will be completed atomically;
	# also the optimum block size
	#
	ATOMICIO:	con 8192;

	OREAD:		con 0;
	OWRITE:		con 1;
	ORDWR:		con 2;
	OTRUNC:		con 16;
	ORCLOSE:	con 64;
	OEXCL:		con 16r1000;

	DMDIR:		con int 1<<31;
	DMAPPEND:	con int 1<<30;
	DMEXCL:		con int 1<<29;
	DMAUTH:		con int 1<<27;
	DMTMP:		con int 1<<26;
};
