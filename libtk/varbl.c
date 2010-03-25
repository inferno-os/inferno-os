#include <lib9.h>
#include <kernel.h>
#include "draw.h"
#include "tk.h"
#include "label.h"

char*
tksetvar(TkTop *top, char *c, char *newval)
{
	TkVar *v;
	TkWin *tkw;
	Tk *f, *m;
	void (*vc)(Tk*, char*, char*);

	if (c == nil || c[0] == '\0')
		return nil;

	v = tkmkvar(top, c, TkVstring);
	if(v == nil)
		return TkNomem;
	if(v->type != TkVstring)
		return TkNotvt;

	if(newval == nil)
		newval = "";

	if(v->value != nil) {
		if (strcmp(v->value, newval) == 0)
			return nil;
		free(v->value);
	}

	v->value = strdup(newval);
	if(v->value == nil)
		return TkNomem;

	for(f = top->root; f; f = f->siblings) {
		if(f->type == TKmenu) {
			tkw = TKobj(TkWin, f);
			for(m = tkw->slave; m; m = m->next)
				if ((vc = tkmethod[m->type]->varchanged) != nil)
					(*vc)(m, c, newval);
		} else
			if ((vc = tkmethod[f->type]->varchanged) != nil)
				(*vc)(f, c, newval);
	}

	return nil;
}

char*
tkvariable(TkTop *t, char *arg, char **ret)
{
	TkVar *v;
	char *fmt, *e, *buf, *ebuf, *val;
	int l;

	l = strlen(arg) + 2;
	buf = malloc(l);
	if(buf == nil)
		return TkNomem;
	ebuf = buf+l;

	arg = tkword(t, arg, buf, ebuf, nil);
	arg = tkskip(arg, " \t");
	if (*arg == '\0') {
		if(strcmp(buf, "lasterror") == 0) {
			free(buf);
			if(t->err == nil)
				return nil;
			fmt = "%s: %s";
			if(strlen(t->errcmd) == sizeof(t->errcmd)-1)
				fmt = "%s...: %s";
			e = tkvalue(ret, fmt, t->errcmd, t->err);
			t->err = nil;
			return e;
		}
		v = tkmkvar(t, buf, 0);
		free(buf);
		if(v == nil || v->value == nil)
			return nil;
		if(v->type != TkVstring)
			return TkNotvt;
		return tkvalue(ret, "%s", v->value);
	}
	val = buf+strlen(buf)+1;
	tkword(t, arg, val, ebuf, nil);
	e = tksetvar(t, buf, val);
	free(buf);
	return e;
}
