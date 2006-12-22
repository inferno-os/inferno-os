#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	<interp.h>
#include	<isa.h>
#include	"ip.h"
#include	"srv.h"
#include	"srvm.h"

static	QLock	dbq;

void
Srv_init(void *fp)
{
	USED(fp);
}

void
Srv_iph2a(void *fp)
{
	Heap *hpt;
	String *ss;
	F_Srv_iph2a *f;
	int i, n, nhost;
	List **h, *l, *nl;
	char *hostv[10];
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);
	release();
	qlock(&dbq);
	if(waserror()){
		qunlock(&dbq);
		acquire();
		return;
	}
	nhost = so_gethostbyname(string2c(f->host), hostv, nelem(hostv));
	poperror();
	qunlock(&dbq);
	acquire();
	if(nhost == 0)
		return;

	l = (List*)H;
	h = &l;
	for(i = 0; i < nhost; i++) {
		n = strlen(hostv[i]);
		ss = newstring(n);
		memmove(ss->Sascii, hostv[i], n);
		free(hostv[i]);

		hpt = nheap(sizeof(List) + IBY2WD);
		hpt->t = &Tlist;
		hpt->t->ref++;
		nl = H2D(List*, hpt);
		nl->t = &Tptr;
		Tptr.ref++;
		nl->tail = (List*)H;
		*(String**)nl->data = ss;

		*h = nl;
		h = &nl->tail;
	}
	*f->ret = l;
}

void
Srv_ipa2h(void *fp)
{
	Heap *hpt;
	String *ss;
	F_Srv_ipa2h *f;
	int i, n, naliases;
	List **h, *l, *nl;
	char *hostv[10];
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);
	release();
	qlock(&dbq);
	if(waserror()){
		qunlock(&dbq);
		acquire();
		return;
	}
	naliases = so_gethostbyaddr(string2c(f->addr), hostv, nelem(hostv));
	poperror();
	qunlock(&dbq);
	acquire();
	if(naliases == 0)
		return;

	l = (List*)H;
	h = &l;
	for(i = 0; i < naliases; i++) {
		n = strlen(hostv[i]);
		ss = newstring(n);
		memmove(ss->Sascii, hostv[i], n);
		free(hostv[i]);

		hpt = nheap(sizeof(List) + IBY2WD);
		hpt->t = &Tlist;
		hpt->t->ref++;
		nl = H2D(List*, hpt);
		nl->t = &Tptr;
		Tptr.ref++;
		nl->tail = (List*)H;
		*(String**)nl->data = ss;

		*h = nl;
		h = &nl->tail;
	}
	*f->ret = l;
}

void
Srv_ipn2p(void *fp)
{
	int n;
	char buf[16];
	F_Srv_ipn2p *f;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);
	release();
	qlock(&dbq);
	if(waserror()){
		qunlock(&dbq);
		acquire();
		return;
	}
	n = so_getservbyname(string2c(f->service), string2c(f->net), buf);
	poperror();
	qunlock(&dbq);
	acquire();
	if(n >= 0)
		retstr(buf, f->ret);
}

void
srvmodinit(void)
{
	builtinmod("$Srv", Srvmodtab, Srvmodlen);
}
