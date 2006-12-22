# smtp protocol independent access to an email server.
 
Smtp : module
{
	PATH : con "/dis/lib/smtp.dis";
 
	# all functions return status (-ve when error)

         # open a connection with the email server
         # requires the email server's name or address or nil if a default server is to be used
	# returns (status, errror string)
         open: fn(server : string) : (int, string);

	# send mail - returns (status, error string)
	sendmail: fn(fromwho: string, 
		             towho: list of string, 
		             cc : list of string,
		             msg: list of string) : (int, string);

         # close the connection - returns (status, error string)
         close: fn() : (int, string);
};
