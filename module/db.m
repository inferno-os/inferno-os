DB : module
{
	PATH : con "/dis/lib/db.dis";

	# Open the connection to the DB server
    	# returns (New handle, "") or (nil, "Error Message")
	#
	open:	fn(addr, username, password, dbname: string) :
					(ref DB_Handle, list of string);
	#
	# Opens a connection to an Inferno on the database machine, with the
	# specified level of security.
	# 
	connect : fn(addr, alg : string) : (ref Sys->FD, string);
	#
	# Mounts the file descriptor on dir, then opens the database.
	#
	dbopen: fn(fd : ref Sys->FD, username, password, dbname : string) :
						(ref DB_Handle, list of string);

	DB_Handle : adt
	{
		#
		# Open another SQL stream for the same connection.
		#
		SQLOpen :	fn(oldh : self ref DB_Handle) : (int, ref DB_Handle);
		SQLClose : fn(dbh : self ref DB_Handle) : int;

	                   # Execute the SQL command
		# returns (0, "") or (error code, "Message")
		#
	    	SQL:	fn(handle: self ref DB_Handle, command: string)
							: (int, list of string);

		# Check the number of columns of last select command
		#
		columns:	fn(handle: self ref DB_Handle): int;

		# Fetch the next row of the selection results.
		# returns current row number, or 0
		#
	  	nextRow:	fn(handle: self ref DB_Handle): int;	

		# Read the data of column[i] of current row
		#
	  	read:	fn(handle: self ref DB_Handle, column: int)
							: (int, array of byte);

		# Write data to be used for parameter[i]
		#
		write:	fn(handle: self ref DB_Handle, column: int,
						fieldval: array of byte) : int;

		# Title of the column[i]
		#
	  	columnTitle: 	fn(handle: self ref DB_Handle, column: int)
							: string;

		#error message associated with last command
		#
		errmsg:		fn(handle: self ref DB_Handle): string;

		datafd : ref Sys->FD;
		sqlconn:int;
		sqlstream : int;
		lock : chan of int;

	};
};
