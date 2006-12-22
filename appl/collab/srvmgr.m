Srvmgr: module
{
	PATH:	con "/dis/collab/srvmgr.dis";
	Srvreq: adt {
		sname: string;
		id: string;
		pick {
		Acquire =>
			uname: string;
			reply: chan of Srvreply;
		Release =>
		}
	};

	Srvreply: type (
		string,		# error
		string,		# root path
		ref Sys->FD	# styx fd
	);

	init: fn(cfg: string): (string, chan of ref Srvreq);
};
