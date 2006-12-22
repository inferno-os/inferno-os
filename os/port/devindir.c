#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

static Chan *
indirattach(char *spec)
{
	char *p;
	Dev *d;

	if(*spec == 0)
		error(Ebadspec);
	p = strrchr(spec, '!');
	if(p == nil)
		p = "";
	else
		*p++ = 0;
	d = devbyname(spec);
	if(d == nil || d->dc == '*'){
		snprint(up->env->errstr, ERRMAX, "unknown device: %s", spec);
		error(up->env->errstr);
	}
	if(up->env->pgrp->nodevs &&
	   (utfrune("|esDa", d->dc) == nil || d->dc == 's' && *p!='\0'))
		error(Enoattach);
	return d->attach(p);
}

Dev indirdevtab = {
	'*',
	"indir",

	devreset,
	devinit,
	devshutdown,
	indirattach,
};
