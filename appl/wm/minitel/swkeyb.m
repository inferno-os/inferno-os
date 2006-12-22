###
### This data and information is not to be used as the basis of manufacture,
### or be reproduced or copied, or be distributed to another party, in whole
### or in part, without the prior written consent of Lucent Technologies.
###
### (C) Copyright 1997 Lucent Technologies
###
### Written by N. W. Knauft
###

# Revisions Copyright © 1998 Vita Nuova Limited.

Keyboard: module
{
        PATH:           con "/dis/wm/minitel/swkeyb.dis";

        initialize:     fn(t: ref Tk->Toplevel, ctxt : ref Draw->Context,
				dot: string): chan of string;
        chaninit:       fn(t: ref Tk->Toplevel, ctxt : ref Draw->Context,
				dot: string, rc: chan of string): chan of string;
};
