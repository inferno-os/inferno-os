#include "rc.h"

int	interrupted;
Ref	ntrap;

/* runs in a different thread */
void
dointr(void)
{
	refinc(&ntrap);
	interrupted = 1;
}

void
dotrap(void)
{
	Var *trapreq;
	Word *starval;

	while(refdec(&ntrap) >= 0) {
		if(flag['S'])
			exits(truestatus()?"":getstatus());
		starval=vlook("*")->val;
		trapreq=vlook("sysint");
		if(trapreq->fn){
			start(trapreq->fn, trapreq->pc, (Var*)0);
			runq->local=newvar(strdup("*"), runq->local);
			runq->local->val=copywords(starval, (Word*)0);
			runq->local->changed=1;
			runq->redir=runq->startredir=0;
		} else {
			/*
			 * run the stack down until we uncover the
			 * command reading loop.  Xreturn will exit
			 * if there is none (i.e. if this is not
			 * an interactive rc.)
			 */
			while(!runq->iflag)
				Xreturn();
		}
	}
}
