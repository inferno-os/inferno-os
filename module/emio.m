#
# File: emio.m
#
# This file contains the declaration of the EMIO module.
# The EMIO module provides protocol independent access
# to an email server.
#
 
EMIO : module
{
        #
        # The init function initializes the EMIO module.
        # It must be called before any other function in the
        # module.
        #
        init: fn();
 
        #
        # The open function opens a connection with the email
        # server.  The function requires the email server's
        # tcp/ip address, a username and a password to make the
        # connection to the email server.  It returns a tuple
        # (int, string).  The int indicates success or failure
        # (0 = failure, 1 = success). If the function fails,
        # the int returned is 0, the string returned will indicate
        # why the function failed. It should be called after the
        # init function and before any other function in the module.
        #
        open: fn(ipaddr : string,
                 username : string,
                 password : string) : (int, string);
 
        #
        # The numberofmessages function indicates how many mail
        # messages are in the specified users mailbox. It returns
        # a tuple (int, string).  The int indicates the number of
        # mail messages in the mailbox (-1 = function failed, 0 =
        # no mail message, 1 = one mail message ...). If the function fails,
        # the int returned is -1, the string returned will indicate
        # why the function failed.
        #
        numberofmessages: fn() : (int, string);

	#
	# This function provides the number of octets in the specified
	# message number.  It returns a tuple (int, string).  The int indicates
	# the number of octets in the mail message.  If it is -1, the
	# function has failed and the string returned will contain the
	# possible reason.  
	# This function implements the LIST command, but only with an
	# argument - the message number.
	messagelength: fn(num : int) : (int, string); 

        #
        # The messagetext function returns the text of the specified
        # mail message.  The function requires the number of the
        # mail message to retrieve. It returns a triple
        # (int, string, list of string). The int indicates success or failure
        # (0 = failure, 1 = success). If the function fails,
        # the int returned is 0, the string returned will indicate
        # why the function failed. If the function succeded the list
        # of string contains the text for the specified mail message.
        #
        messagetext: fn(messagenumber : int) : (int, string, list of string);

	#
	# This is similar to messagetext() but returns a string, rather than
	# a list of string. The string contains the complete text of the mail
	# message, header and body. Each line of the message is separate by a
	# DELIMETER (currently set to |&|) fo easier processing.
	#
	msgtextstring: fn (num : int) : (int, string, string);
 
        #
        # The deletemessage function markes the specified mail
        # message as deleted. The function requires the number of
        # the mail message to delete. It returns a tuple
        # (int, string).  The int indicates success or failure
        # (0 = failure, 1 = success). If the function fails,
        # the int returned is 0, the string returned will indicate
        # why the function failed.
        #
        deletemessage: fn(messagenumber : int) : (int, string);
 
        #
        # The reset function unmarks all messages that have been
        # marked deleted during this session. It returns a tuple
        # (int, string).  The int indicates success or failure
        # (0 = failure, 1 = success). If the function fails,
        # the int returned is 0, the string returned will indicate
        # why the function failed.
        #
        reset: fn() : (int, string);
 
        #
        # The close function closes a connection with the email
        # server. It returns a tuple (int, string).  The int
        # indicates success or failure (0 = failure, 1 = success).
        # If the function fails, the int returned is 0, the string
        # returned will indicate why the function failed.
        #
        close: fn() : (int, string);
};
