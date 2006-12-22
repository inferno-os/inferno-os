#
# Copyright © 1998 Vita Nuova Limited.  All rights reserved.
#

Event.str(ev: self ref Event) : string
{
	s := "?";
	pick e := ev {
		Edata =>
			s = sprint("Edata %d = ", len e.data);
			for(i:=0; i<len e.data; i++)
				s += hex(int e.data[i], 2) + " ";
		Equit =>
			s = "Equit";
		Eproto =>
			s = sprint("Eproto %ux (%s)", e.cmd, e.s);
	}
	return s;
}
