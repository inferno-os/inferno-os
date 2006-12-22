#include "lib9.h"
#include "draw.h"
#include "tk.h"

int	
tkextndeliver(Tk *tk, TkAction *binds, int event, void *data)
{
	return tksubdeliver(tk, binds, event, data, 1);
}

void
tkextnfreeobj(Tk *tk)
{
	USED(tk);
}

int
tkextnnewctxt(TkCtxt *ctxt)
{
	USED(ctxt);
	return 0;
}

void
tkextnfreectxt(TkCtxt *ctxt)
{
	USED(ctxt);
}

char*
tkextnparseseq(char *seq, char *rest, int *event)
{
	USED(seq);
	USED(rest);
	USED(event);
	return nil;
}
