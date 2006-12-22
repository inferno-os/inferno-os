#
# Copyright © 1998 Lucent Technologies Inc.  All rights reserved.
# Revisions copyright © 2000,2001 Vita Nuova Holdings Limited.  All rights reserved.
#
# Originally Written by N. W. Knauft
# Adapted by E. V. Hensbergen (ericvh@lucent.com)
# Further adapted by Vita Nuova
#

PPPGUI: module
{
        PATH:	con "/dis/ip/ppp/pppgui.dis";

	# Dimension constant for ISP Connect window
	WIDTH: con 300;
	HEIGHT: con 58;

        init:	fn(ctxt: ref Draw->Context, stat: chan of int,
			ppp: PPPClient, args: list of string): chan of int;
};

