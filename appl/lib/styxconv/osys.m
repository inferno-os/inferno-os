OSys: module
{
	# Unique file identifier for file objects
	Qid: adt
	{
		path:	int;
		vers:	int;
	};

	# Return from stat and directory read
	Dir: adt
	{
		name:	string;
		uid:	string;
		gid:	string;
		qid:	Qid;
		mode:	int;
		atime:	int;
		mtime:	int;
		length:	int;
		dtype:	int;
		dev:	int;
	};

	# Maximum read which will be completed atomically;
	# also the optimum block size
	#
	ATOMICIO:	con 8192;

	NAMELEN:	con 28;
	ERRLEN:		con 64;

	CHDIR:		con int 16r80000000;
};
