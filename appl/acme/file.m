Filem : module {
	PATH : con "/dis/acme/file.dis";

	init : fn(mods : ref Dat->Mods);

	File : adt {
		buf : ref Bufferm->Buffer;		# the data
		delta : ref Bufferm->Buffer;		# transcript of changes
		epsilon : ref Bufferm->Buffer;	# inversion of delta for redo
		elogbuf: ref Bufferm->Buffer;	# log of pending editor changes
		elog: Editlog->Elog;			# current pending change
		name : string;				# name of associated file
		qidpath : big;				# of file when read
		mtime : int;				# of file when read
		dev : int;					# of file when read
		unread : int;				# file has not been read from disk
		editclean: int;				# mark clean after edit command
		seq : int;					# if seq==0, File acts like Buffer
		mod : int;
		curtext : cyclic ref Textm->Text;	# most recently used associated text
		text : cyclic array of ref Textm->Text;		# list of associated texts
		ntext : int;
		dumpid : int;				# used in dumping zeroxed windows

		addtext : fn(f : self ref File, t : ref Textm->Text) : ref File;
		deltext : fn(f : self ref File, t : ref Textm->Text);
		insert : fn(f : self ref File, n : int, s : string, m : int);
		delete : fn(f : self ref File, m : int, n : int);
		loadx : fn(f : self ref File, p : int, fd : ref Sys->FD) : int;
		setname : fn(f : self ref File, s : string, n : int);
		undo : fn(f : self ref File, p : int, q : int, r : int) : (int, int);
		mark : fn(f : self ref File);
		reset : fn(f : self ref File);
		close : fn(f : self ref File);
		undelete : fn(f : self ref File, b : ref Bufferm->Buffer, m : int, n : int);
		uninsert : fn(f : self ref File, b : ref Bufferm->Buffer, m : int, n : int);
		unsetname : fn(f : self ref File, b : ref Bufferm->Buffer);
		redoseq : fn(f: self ref File): int;
	};
};
