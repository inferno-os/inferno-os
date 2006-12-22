# pop3 protocol independent access to an email server.
 
Pop3: module
{
	PATH: con "/dis/lib/pop3.dis";
 
	# all functions return status (-ve when error)

         # open a connection with the pop3 server
         # requires the email server's name or address or nil if a default server is to be used
	# returns (status, errror string)
         open: fn(user, password, server: string) : (int, string);

	# stat the user's mailbox 
	# returns (status, error string, no. messages, total no. bytes)
	stat: fn(): (int, string, int, int);

	# list the user's mailbox
	# returns (status, error string, list of (message no., bytes in message))
	msglist: fn(): (int, string, list of (int, int));

	# list as above but return (status, error string, list of message nos.)
	msgnolist: fn(): (int, string, list of int);

	# top of a message given it's no.
	# returns (status, error string, message top)
	top: fn(m: int) : (int, string, string);

	# full text of a message given it's no.
	# returns (status, error string, message)
	get: fn(m: int) : (int, string, string);

	# delete a message given it's no.
	# returns (status, error string)
	delete: fn(m: int) : (int, string);

         # close the connection
	# returns (status, error string)
         close: fn(): (int, string);
};
