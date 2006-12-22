#
# Copyright © 1998 Vita Nuova Limited.  All rights reserved.
#

Socket: adt {
	m:		ref Module;		# common attributes
	in:		chan of ref Event;

	init:		fn(c: self ref Socket);
	reset:	fn(c: self ref Socket);
	run:		fn(c: self ref Socket);
	quit:		fn(c: self ref Socket);
};

Socket.init(c: self ref Socket)
{
	c.in = chan of ref Event;
	c.reset();
}

Socket.reset(c: self ref Socket)
{
	c.m = ref Module(Pscreen, 0);
}

Socket.run(c: self ref Socket)
{
Runloop:
	for(;;){
		ev := <- c.in;
		pick e := ev {
		Equit =>
			break Runloop;
		Eproto =>
			case e.cmd {
			Creset =>
				c.reset();
			* => break;
			}
		Edata =>
		}
	}
	send(nil);	
}

Socket.quit(c: self ref Socket)
{
	if(c==nil);
}
