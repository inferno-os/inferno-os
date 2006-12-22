Exception: module{

	PATH:	con "/dis/lib/exception.dis";

	# returns the last exception in the form pc, module, exception
	# on the process with the given pid (-1 gives current process)
	# returns (0, nil, nil) if no exception
	getexc:	fn(pid: int): (int, string, string);

	NOTIFYLEADER, PROPAGATE: con iota;

	# set the exception mode(NOTIFYLEADER or PROPAGATE)
	# on the current process
	# it is assumed that the process is a group leader (see Sys->NEWPGRP)
	# returns -1 on failure, 0 on success
	setexcmode:	fn(mode: int): int;

};
