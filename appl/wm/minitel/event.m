#
# Copyright © 1998 Vita Nuova Limited.  All rights reserved.
#

Event: adt {
	path: int;					# path for delivery
	from: int;					# sending module (for reply)
	pick {
		Edata =>
			data: array of byte;
		Eproto =>
			cmd: int;
			s: string;
			a0, a1, a2: int;		# parameters
		Equit =>
	}

	str: 	fn(e: self ref Event) : string;	# convert to readable form
};
