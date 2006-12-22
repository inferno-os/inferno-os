Muxclient: module
{
	# From appl to mux
	AMexit:		con 10;		# application is exiting
	AMstartir:	con 11;		# application is ready to receive IR events
	AMstartkbd:	con 12;		# application is ready to receive keyboard characters
	AMstartptr:	con 13;		# application is ready to receive mouse events
	AMnewpin:	con 14;		# application needs a PIN

	# From mux to appl
	MAtop:		con 20;		# application should make all its windows visible

	Context: adt
	{
		screen: 	ref Screen;		# place to make windows
		display: 	ref Display;		# frame buffer on which windows reside
		cir: 		chan of int;		# incoming events from IR remote
		ckbd: 		chan of int;		# incoming characters from keyboard
		cptr: 		chan of ref Pointer;	# incoming stream of mouse positions
		ctoappl:	chan of int;		# commands from mux to application
		ctomux:		chan of int;		# commands from application to mux
	};
};
