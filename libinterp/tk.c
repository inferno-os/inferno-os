#include "lib9.h"
#include "interp.h"
#include "isa.h"
#include "runt.h"
#include "draw.h"
#include "tk.h"
#include "tkmod.h"
#include "pool.h"
#include "drawif.h"
#include "keyboard.h"
#include "raise.h"
#include "kernel.h"

extern	void	tkfreetop(Heap*, int);
Type*	fakeTkTop;
static	uchar	TktypeMap[] = Tk_Toplevel_map;
int	tkstylus;
void	(*tkwiretap)(void*, char*, char*, void*, Rectangle*);

static void tktopimagedptr(TkTop*, Draw_Image*);
static char*tkputwinimage(Tk*, Draw_Image*, int);

static void
lockctxt(TkCtxt *ctxt)
{
	libqlock(ctxt->lock);
}

static void
unlockctxt(TkCtxt *ctxt)
{
	libqunlock(ctxt->lock);
}

static void
tkmarktop(Type *t, void *vw)
{
	Heap *h;
	TkVar *v;
	TkPanelimage *di;
	TkTop *top;
	Tk *w, *next;
	TkWin *tkw;

	markheap(t, vw);
	top = vw;
	// XXX do we need to lock context here??
	for(v = top->vars; v; v = v->link) {
		if(v->type == TkVchan) {
			h = D2H(v->value);
			Setmark(h);
		}
	}
	for (di = top->panelimages; di != nil; di = di->link) {
		h = D2H(di->image);
		Setmark(h);
	}
	for(w = top->windows; w != nil; w = next){
		tkw = TKobj(TkWin, w);
		if(tkw->image != nil){
			h = D2H(tkw->di);
			Setmark(h);
		}
		next = tkw->next;
	}
}

void
tkmodinit(void)
{
	builtinmod("$Tk", Tkmodtab, Tkmodlen);
	fmtinstall('v', tkeventfmt);			/* XXX */

	fakeTkTop = dtype(tkfreetop, sizeof(TkTop), TktypeMap, sizeof(TktypeMap));
	fakeTkTop->mark = tkmarktop;

	tksorttable();
}

void
Tk_toplevel(void *a)
{
	Tk *tk;
	Heap *h;
	TkTop *t;
	TkWin *tkw;
	TkCtxt *ctxt;
	Display *disp;
	F_Tk_toplevel *f = a;
	void *r;

	r = *f->ret;
	*f->ret = H;
	destroy(r);
	disp = checkdisplay(f->d);

	h = heapz(fakeTkTop);
	t = H2D(TkTop*, h);
	poolimmutable(h);

	t->dd = f->d;
	D2H(t->dd)->ref++;

	t->execdepth = -1;
	t->display = disp;

	tk = tknewobj(t, TKframe, sizeof(Tk)+sizeof(TkWin));
	if(tk == nil) {
		destroy(t);
		return;
	}

	tk->act.x = 0;
	tk->act.y = 0;
	tk->act.width = 1;		/* XXX why not zero? */
	tk->act.height = 1;
	tk->flag |= Tkwindow;

	tkw = TKobj(TkWin, tk);
	tkw->di = H;

	tktopopt(tk, string2c(f->arg));
	
	tk->geom = tkmoveresize;
	tk->name = tkmkname(".");
	if(tk->name == nil) {
		tkfreeobj(tk);
		destroy(t);
		return;
	}

	ctxt = tknewctxt(disp);
	if(ctxt == nil) {
		tkfreeobj(tk);
		destroy(t);
		return;
	}
	t->ctxt = ctxt;
	t->screenr = disp->image->r;

	tkw->next = t->windows;
	t->windows = tk;
	t->root = tk;
	Setmark(h);
	poolmutable(h);
	t->wreq = cnewc(&Tptr, movp, 8);
	*f->ret = (Tk_Toplevel*)t;
}

void
Tk_cmd(void *a)
{
	TkTop *t;
	char *val, *e;
	F_Tk_cmd *f = a;

	t = (TkTop*)f->t;
	if(t == H || D2H(t)->t != fakeTkTop) {
		retstr(TkNotop, f->ret);
		return;
	}
	lockctxt(t->ctxt);
	val = nil;
	e = tkexec(t, string2c(f->arg), &val);
	unlockctxt(t->ctxt);
	if(e == TkNomem){
		free(val);
		error(exNomem);		/* what about f->ret? */
	}
	if(e != nil && t->errx[0] != '\0'){
		char *s = tkerrstr(t, e);

		retstr(s, f->ret);
		free(s);
	}
	else
		retstr(e == nil ? val : e, f->ret);
	if(tkwiretap != nil)
		tkwiretap(t, string2c(f->arg), val, nil, nil);
	free(val);
}

void
Tk_color(void *fp)
{
	ulong rgba;
	F_Tk_color *f = fp;
	if(tkparsecolor(string2c(f->col), &rgba) != nil)
		*f->ret = DNotacolor;
	else
		*f->ret = rgba;
}

void
Tk_rect(void *fp)
{
	F_Tk_rect *f = fp;
	Tk *tk;
	TkTop *t;
	Rectangle r;
	TkGeom *g;
	Point o;
	int bd, flags;

	t = (TkTop*)f->t;
	if(t == H || D2H(t)->t != fakeTkTop){
		*(Rectangle *)f->ret = ZR;
		return;
	}
	lockctxt(t->ctxt);
	tk = tklook(t, string2c(f->name), 0);
	if(tk == nil){
		*(Rectangle *)f->ret = ZR;
		unlockctxt(t->ctxt);
		return;
	}
	o = tkposn(tk);
	flags = f->flags;
	if(flags & Tk_Local)
		o = subpt(o, tkposn(tk->env->top->root));
	bd = tk->borderwidth;
	g = (flags & Tk_Required) ? &tk->req : &tk->act;
	if(flags & Tk_Border){
		r.min = o;
		r.max.x = r.min.x + g->width + bd + bd;
		r.max.y = r.min.y + g->height + bd + bd;
	} else {
		r.min.x = o.x + bd;
		r.min.y = o.y + bd;
		r.max.x = r.min.x + g->width;
		r.max.y = r.min.y + g->height;
	}
	*(Rectangle *)f->ret = r;
	unlockctxt(t->ctxt);
}

int
tkdescendant(Tk *p, Tk *c)
{
	int n;

	if(c == nil || p->env->top != c->env->top)
		return 0;

	if (p->name != nil && c->name != nil) {
 		n = strlen(p->name->name);
		if(strncmp(p->name->name, c->name->name, n) == 0)
			return 1;
	}

	return 0;
}

void
tkenterleave(TkTop *t)
{
	Tk *fw, *ent;
	TkMouse m;
	TkTop *t1, *t2;
	TkCtxt *c;

	c = t->ctxt;
	m = c->mstate;

	if (c->mgrab != nil && (c->mgrab->flag & Tknograb)) {
		fw = tkfindfocus(t, m.x, m.y, 1);
		if (fw != c->mgrab && fw != nil && (fw->flag & Tknograb) == 0)
			fw = nil;
	} else if (c->focused) {
		fw = tkfindfocus(t, m.x, m.y, 1);
		if (fw != c->mfocus)
			fw = nil;
	} else if (c->mgrab != nil) {
		fw = tkfindfocus(t, m.x, m.y, 1);
		if (fw != nil) {
			if (!tkdescendant(c->mgrab, fw) && !(fw->flag & c->mgrab->flag & Tknograb))
				fw = nil;
		}
	} else if (m.b == 0)
		fw = tkfindfocus(t, m.x, m.y, 0);
	else if (tkfindfocus(t, m.x, m.y, 1) == c->entered)
		return;
	else
		fw = nil;

 	if (c->entered == fw)
		return;

	t1 = t2 = nil;
	if (c->entered != nil) {
		ent = c->entered;
		t1 = ent->env->top;
		c->entered = nil;
		tkdeliver(ent, TkLeave, nil);
	}

	if (fw != nil) {
		t2 = fw->env->top;
		c->entered = fw;
		tkdeliver(fw, TkEnter, &m);
	}
	if (t1 != nil)
		tkupdate(t1);
	if (t2 != nil && t1 != t2)
		tkupdate(t2);
}

void
Tk_pointer(void *a)
{
	static int buttonr[] = {TkButton1R, TkButton2R, TkButton3R, TkButton4R, TkButton5R, TkButton6R};
	static int buttonp[] = {TkButton1P, TkButton2P, TkButton3P, TkButton4P, TkButton5P, TkButton6P};
	Tk *fw, *target, *dest, *ent;
	TkMouse m;
	TkCtxt *c;
	TkTop *t, *ot;
	int d, dtype, etype;
	F_Tk_pointer *f = a;
	int b, lastb, inside;

	t = (TkTop*)f->t;
	if(t == H || D2H(t)->t != fakeTkTop)
		return;

	c = t->ctxt;

	/* ignore no-button-motion for emulated stylus input */
	if(tkstylus && c->mstate.b == 0 && (f->p.buttons&0x1f)==0)
		return;

	lockctxt(c);
//if (f->p.buttons != 0 || c->mstate.b != 0)
//print("tkmouse %d [%d %d], focused %d[%s], grab %s, entered %s\n",
//	f->p.buttons, f->p.xy.x, f->p.xy.y, c->focused, tkname(c->mfocus), tkname(c->mgrab), tkname(c->entered));
	/*
	 * target is the widget that we're deliver the mouse event to.
	 * inside is true if the mouse point is located inside target.
	 */
	inside = 1;
	if (c->mgrab != nil && (c->mgrab->flag & Tknograb)) {
		fw = tkfindfocus(t, f->p.xy.x, f->p.xy.y, 1);
		if (fw != nil && (fw->flag & Tknograb))
			target = fw;
		else {
			target = c->mgrab;
			inside = 0;
		}
	} else if (c->focused) {
		if (c->mfocus != nil) {
			fw = tkfindfocus(t, f->p.xy.x, f->p.xy.y, 1);
			if (fw != c->mfocus)
				inside = 0;
		}
		target = c->mfocus;
	} else if (c->mgrab != nil && (c->mgrab->flag & Tkdisabled) == 0) {
		/*
		 * XXX this isn't quite right, as perhaps we should do a tkinwindow()
		 * (below the grab).
		 * so that events to containers underneath the grab arrive
		 * via the containers (as is usual)
		 */
		fw = tkfindfocus(t, f->p.xy.x, f->p.xy.y, 1);
		if (fw != nil && tkdescendant(c->mgrab, fw))
			target = fw;
		else {
			target = c->mgrab;
			inside = 0;
		}
	} else
		target = tkfindfocus(t, f->p.xy.x, f->p.xy.y, 0);

	lastb = c->mstate.b;
	c->mstate.x = f->p.xy.x;
	c->mstate.y = f->p.xy.y;
	c->mstate.b = f->p.buttons & 0x1f;		/* Just the buttons */
	m = c->mstate;

	/* XXX if the mouse is being moved with the buttons held down
	 * and we've no mfocus and no mgrab then ignore
	 * the event as our original target has gone away (or never existed)
	 */
	if (lastb && m.b && !c->focused && c->mgrab == nil)
		target = nil;

	if (target != c->entered || (c->entered != nil && !inside)) {
		if (c->entered != nil) {
			fw = c->entered;
			c->entered =  nil;
			tkdeliver(fw, TkLeave, nil);
			if (target == nil || fw->env->top != target->env->top)
				tkupdate(fw->env->top);
		}
		if (inside) {
			c->entered = target;
			tkdeliver(target, TkEnter, &m);
		}
	}

	dest = nil;
	if (target != nil) {
		etype = 0;
		dtype = 0;
		if(f->p.buttons & (1<<8))		/* Double */
			dtype = TkDouble;
	
		d = lastb ^ m.b;
		if (d)	{
			/* cancel any autorepeat, notifying existing client */
			tkrepeat(nil, nil, nil, 0, 0);
			if (d & ~lastb & 1)		/* button 1 potentially takes the focus */
				tkdeliver(target, TkTakefocus|TkButton1P, &m);
		}
		for(b=0; b<nelem(buttonp); b++){
			if(d & (1<<b)){
				etype = buttonr[b];
				if(m.b & (1<<b))
					etype = buttonp[b]|dtype;
				dest = tkdeliver(target, etype, &m);
			}
		}
		if(tkstylus && m.b==0) {
			if ((ent = c->entered) != nil) {
				c->entered = nil;
				ot = ent->env->top;
				tkdeliver(ent, TkLeave, nil);
				if (ot != target->env->top)
					tkupdate(ot);
			}
		} else if(etype == 0) {
			etype = TkMotion;
			for(b = 0; b<nelem(buttonp); b++)
				if (m.b & (1<<b))
					etype |= buttonp[b];
			tkdeliver(target, etype, &m);
		}
		if (m.b != 0) {
			if (lastb == 0 && !c->focused) {		/* (some deliver might have grabbed it...) */
				if (dest == nil)
					dest = target;
				if ((dest->flag & Tknograb) == 0) {
					c->focused = 1;
					c->mfocus = dest;
				}
			}
		} else {
			c->focused = 0;
			c->mfocus = nil;
			if (lastb != 0)
				tkenterleave(t);
		}
		tkupdate(target->env->top);
	} else if (c->focused && m.b == 0) {
		c->focused = 0;
		tkenterleave(t);
	}
	unlockctxt(c);
}

void
Tk_keyboard(void *a)
{
	Tk *grab;
	TkTop *t;
	TkCtxt *c;
	F_Tk_keyboard *f = a;

	t = (TkTop*)f->t;
	if(t == H || D2H(t)->t != fakeTkTop)
		return;
	c = t->ctxt;
	if (c == nil)
		return;
	lockctxt(c);
	if (c->tkmenu != nil)
		grab = c->tkmenu;
	else
		grab = c->tkkeygrab;
	if(grab == nil){
		unlockctxt(c);
		return;
	}

	t = grab->env->top;
	tkdeliver(grab, TkKey|TKKEY(f->key), nil);
	tkupdate(t);
	unlockctxt(c);
}

TkVar*
tkmkvar(TkTop *t, char *name, int type)
{
	TkVar *v;

	for(v = t->vars; v; v = v->link)
		if(strcmp(v->name, name) == 0)
			return v;

	if(type == 0)
		return nil;

	v = malloc(sizeof(TkVar)+strlen(name)+1);
	if(v == nil)
		return nil;
	strcpy(v->name, name);
	v->link = t->vars;
	t->vars = v;
	v->type = type;
	v->value = nil;
	if(type == TkVchan)
		v->value = H;
	return v;
}

void
tkfreevar(TkTop *t, char *name, int swept)
{
	TkVar **l, *p;

	if(name == nil)
		return;
	l = &t->vars;
	for(p = *l; p != nil; p = p->link) {
		if(strcmp(p->name, name) == 0) {
			*l = p->link;
			switch(p->type) {
			default:
				free(p->value);
				break;
			case TkVchan:
				if(!swept)
					destroy(p->value);
				break;
			}
			free(p);
			return;
		}
		l = &p->link;
	}
}

void
Tk_namechan(void *a)
{
	Heap *h;
	TkVar *v;
	TkTop *t;
	char *name;
	F_Tk_namechan *f = a;

	t = (TkTop*)f->t;
	if(t == H || D2H(t)->t != fakeTkTop) {
		retstr(TkNotop, f->ret);
		return;
	}
	if(f->c == H) {
		retstr("nil channel", f->ret);
		return;
	}
	name = string2c(f->n);
	if(name[0] == '\0') {
		retstr(TkBadvl, f->ret);
		return;
	}

	lockctxt(t->ctxt);
	v = tkmkvar(t, name, TkVchan);
	if(v == nil) {
		unlockctxt(t->ctxt);
		retstr(TkNomem, f->ret);
		return;
	}
	if(v->type != TkVchan) {
		unlockctxt(t->ctxt);
		retstr(TkNotvt, f->ret);
		return;
	}
	destroy(v->value);
	v->value = f->c;
	unlockctxt(t->ctxt);
	h = D2H(v->value);
	h->ref++;
	Setmark(h);
	// poolimmutable((void *)h);
	retstr("", f->ret);
}

void
Tk_quote(void *a)
{
	String *s, *ns;
	F_Tk_quote *f;
	void *r;
	int c, i, need, len, userune, last, n;
	Rune *sr;
	char *sc;

	f = a;

	r = *f->ret;
	*f->ret = H;
	destroy(r);

	s = f->s;
	if(s == H){
		retstr("{}", f->ret);
		return;
	}
	len = s->len;
	userune = 0;
	if(len < 0) {
		len = -len;
		userune = 1;
	}
	need = len+2;
	for(i = 0; i < len; i++) {
		c = userune? s->Srune[i]: s->Sascii[i];
		if(c == '{' || c == '}' || c == '\\')
			need++;
	}
	if(userune) {
		ns = newrunes(need);
		sr = ns->Srune;
		*sr++ = '{';
		last = 0;
		for(i = 0;; i++) {
			if(i >= len || (c = s->Srune[i]) == '{' || c == '}' || c == '\\'){
				n = i-last;
				if(n) {
					memmove(sr, &s->Srune[last], n*sizeof(Rune));
					sr += n;
				}
				if(i >= len)
					break;
				*sr++ = '\\';
				last = i;
			}
		}
		*sr = '}';
	} else {
		ns = newstring(need);
		sc = ns->Sascii;
		*sc++ = '{';
		last = 0;
		for(i = 0;; i++) {
			if(i >= len || (c = s->Sascii[i]) == '{' || c == '}' || c == '\\'){
				n = i-last;
				if(n) {
					memmove(sc, &s->Sascii[last], n);
					sc += n;
				}
				if(i >= len)
					break;
				*sc++ = '\\';
				last = i;
			}
		}
		*sc= '}';
	}
	*f->ret = ns;
}

static void
tkreplimg(TkTop *t, Draw_Image *f, Draw_Image *m, Image **ximg)
{
	Display *d;
	Image *cimg, *cmask, *new;

	cimg = lookupimage(f);
	d = t->display;
	if(cimg == nil || cimg->screen != nil || cimg->display != d)
		return;
	cmask = lookupimage(m);
	if(cmask != nil && (cmask->screen != nil || cmask->display != d))
		return;

	if (cmask == nil)
		new = allocimage(d, Rect(0, 0, Dx(cimg->r), Dy(cimg->r)), cimg->chan, 0, DNofill);
	else {
		if(cmask->screen != nil || cmask->display != d)
			return;
		new = allocimage(d, Rect(0, 0, Dx(cimg->r), Dy(cimg->r)), RGBA32, 0, DTransparent);
	}
	if(new == nil)
		return;
	draw(new, new->r, cimg, cmask, cimg->r.min);
	if(tkwiretap != nil)
		tkwiretap(t, "replimg", nil, cimg, &cimg->r);
	if(*ximg != nil)
		freeimage(*ximg);
	*ximg = new;
}

static char*
tkaddpanelimage(TkTop *t, Draw_Image *di, Image **i)
{
	TkPanelimage *pi;

	if (di == H) {
		*i = 0;
		return nil;
	}

	*i = lookupimage(di);
	if (*i == nil || (*i)->display != t->display)
		return TkNotwm;

	for (pi = t->panelimages; pi != nil; pi = pi->link) {
		if (pi->image == di) {
			pi->ref++;
			return nil;
		}
	}

	pi = malloc(sizeof(TkPanelimage));
	if (pi == nil)
		return TkNomem;
	pi->image = di;
	D2H(di)->ref++;
	pi->ref = 1;
	pi->link = t->panelimages;
	t->panelimages = pi;
	return nil;
}

void
tkdelpanelimage(TkTop *t, Image *i)
{
	TkPanelimage *pi, *prev;
	int locked;

	if (i == nil)
		return;

	prev = nil;
	for (pi = t->panelimages; pi != nil; pi = pi->link) {
		if (lookupimage(pi->image) == i)
			break;
		prev = pi;
	}
	if (pi == nil || --pi->ref > 0)
		return;
	if (prev)
		prev->link = pi->link;
	else
		t->panelimages = pi->link;
	if (D2H(pi->image)->ref == 1) {		/* don't bother locking if it's not going away */
		locked = lockdisplay(t->display);
		destroy(pi->image);
		if (locked)
			unlockdisplay(t->display);
	}
		
	free(pi);
}

void
Tk_putimage(void *a)
{
	TkTop *t;
	TkImg *tki;
	Image *i, *m, *oldi, *oldm;
	int locked, found, reqid, n;
	char *words[2];
	Display *d;
	F_Tk_putimage *f;
	void *r;
	char *name, *e;
	Tk *tk;

	f = a;

	r = *f->ret;
	*f->ret = H;
	destroy(r);

	t = (TkTop*)f->t;
	if(t == H || D2H(t)->t != fakeTkTop) {
		retstr(TkNotop, f->ret);
		return;
	}

	if(f->i == H) {
		retstr(TkBadvl, f->ret);
		return;
	}

	name = string2c(f->name);
	lockctxt(t->ctxt);
	e = nil;
	found = 0;
	if(name[0] == '.'){
		n = getfields(name, words, nelem(words), 1, " ");
		reqid = -1;
		if(n > 1){
			reqid = atoi(words[1]);
			name = words[0];
		}
		if((tk = tklook(t, name, 0)) != nil){
			if(tk->type == TKchoicebutton){
				tk = tkfindchoicemenu(tk);
				if(tk == nil)
					goto Error;
			}
			if(tk->type == TKframe || tk->type == TKmenu){
				if((tk->flag & Tkwindow) == 0){
					e = TkNotwm;
					goto Error;
				}
				e = tkputwinimage(tk, f->i, reqid);
				found = 1;
			} else
			if(tk->type == TKpanel){
				if(n > 1){
					e = TkBadvl;
					goto Error;
				}
				e = tkaddpanelimage(t, f->i, &i);
				if(e != nil)
					goto Error;
				e = tkaddpanelimage(t, f->m, &m);
				if(e != nil){
					tkdelpanelimage(t, i);
					goto Error;
				}
				tkgetpanelimage(tk, &oldi, &oldm);
				tkdelpanelimage(t, oldi);
				tkdelpanelimage(t, oldm);
				tksetpanelimage(tk, i, m);
				tkdirty(tk);
				found = 1;
			}
		}
	}
	if(!found){
		/* XXX perhaps we shouldn't ever do this if name begins with '.'? */
		tki = tkname2img(t, name);
		if(tki == nil) {
			e = TkBadvl;
			goto Error;
		}
	
		d = t->display;
		locked = lockdisplay(d);
		tkreplimg(t, f->i, f->m, &tki->img);
		if(locked)
			unlockdisplay(d);
	
		tksizeimage(t->root, tki);
	}
Error:
	unlockctxt(t->ctxt);
	if(e != nil)
		retstr(e, f->ret);
	return;
}

Draw_Image*
tkimgcopy(TkTop *t, Image *cimg)
{
	Image *new;
	Display *dp;
	Draw_Image *i;

	if(cimg == nil)
		return H;

	dp = t->display;
	new = allocimage(dp, cimg->r, cimg->chan, cimg->repl, DNofill);
	if(new == nil)
		return H;
	new->clipr = cimg->clipr;

	drawop(new, new->r, cimg, nil, cimg->r.min, S);
	if(tkwiretap != nil)
		tkwiretap(t, "imgcopy", nil, cimg, &cimg->r);

	i = mkdrawimage(new, H, t->dd, nil);
	if(i == H)
		freeimage(new);

	return i;
}

void
Tk_getimage(void *a)
{
	Tk *tk;
	char *n;
	TkImg *i;
	TkTop *t;
	int locked;
	Display *d;
	F_Tk_getimage *f;
	void *r;
	void (*getimgs)(Tk*, Image**, Image**);
	Image *image, *mask;

	f = a;

	r = f->ret->t0;
	f->ret->t0 = H;
	destroy(r);
	r = f->ret->t1;
	f->ret->t1 = H;
	destroy(r);
	r = f->ret->t2;
	f->ret->t2 = H;
	destroy(r);

	t = (TkTop*)f->t;
	if(t == H || D2H(t)->t != fakeTkTop) {
		retstr(TkNotop, &f->ret->t2);
		return;
	}
	d = t->ctxt->display;
	n = string2c(f->name);
	lockctxt(t->ctxt);
	i = tkname2img(t, n);
	if (i != nil) {
		image = i->img;
		mask = nil;
	} else {
		tk = tklook(t, n, 0);
		if (tk == nil || (getimgs = tkmethod[tk->type]->getimgs) == nil) {
			unlockctxt(t->ctxt);
			retstr(TkBadvl, &f->ret->t2);
			return;
		}
		getimgs(tk, &image, &mask);
	}
	locked = lockdisplay(d);
	f->ret->t0 = tkimgcopy(t, image);
	if (mask != nil)
		f->ret->t1 = tkimgcopy(t, mask);
	if (locked)
		unlockdisplay(d);
	unlockctxt(t->ctxt);
}

void
tkfreetop(Heap *h, int swept)
{
	TkTop *t;
	Tk *f;
	TkImg *i, *nexti;
	TkVar *v, *nextv;
	int wgtype;
	void *r;
	TkPanelimage *pi, *nextpi;

	t = H2D(TkTop*, h);
	lockctxt(t->ctxt);

	if(swept) {
		t->di = H;
		t->dd = H;
		t->wreq = H;
		t->wmctxt = H;
	}

	t->windows = nil;

	for(f = t->root; f; f = f->siblings) {
		f->flag |= Tkdestroy;
		tkdeliver(f, TkDestroy, nil);
		if(f->destroyed != nil)
			f->destroyed(f);
	}

	for(f = t->root; f; f = t->root) {
		t->root = f->siblings;
		if(swept)
			f->flag |= Tkswept;
		tkfreeobj(f);
	}

	for(v = t->vars; v; v = nextv) {
		nextv = v->link;
		switch(v->type) {
		default:
			free(v->value);
			break;
		case TkVchan:
			if(!swept)
				destroy(v->value);
			break;
		}
		free(v);
	}

	for (pi = t->panelimages; pi; pi = nextpi) {
		if (!swept)
			destroy(pi->image);
		nextpi = pi->link;
		free(pi);
	}

	for(i = t->imgs; i; i = nexti) {
		if(i->ref != 1)
			abort();
		nexti = i->link;
		tkimgput(i);
	}
	/* XXX free images inside widgets */

	for(wgtype = 0; wgtype < TKwidgets; wgtype++)
		if(t->binds[wgtype])
			tkfreebind(t->binds[wgtype]);

	unlockctxt(t->ctxt);
	/* XXX should we leave it locked for this bit? */
	tkfreectxt(t->ctxt);
	if(!swept) {
		r = t->di;
		t->di = H;
		destroy(r);

		r = t->dd;
		t->dd = H;
		destroy(r);

		r = t->wreq;
		t->wreq = H;
		destroy(r);

		r = t->wmctxt;
		t->wmctxt = H;
		destroy(r);
	}
}

static void
tktopimagedptr(TkTop *top, Draw_Image *di)
{
	if(top->di != H){
		destroy(top->di);
		top->di = H;
	}
	if(di == H)
		return;
	D2H(di)->ref++;
	top->di = di;
}

static void
tkfreewinimage(TkWin *w)
{
	destroy(w->di);
	w->image = nil;
	w->di = H;
}

static int
tksetwindrawimage(Tk *tk, Draw_Image *di)
{
	TkWin *tkw;
	char *name;
	Image *i;
	int locked;
	int same;

	tkw = TKobj(TkWin, tk);

	same = tkw->di == di;
	if(!same)
		if(tkw->image != nil)
			destroy(tkw->di);
	if(di == H){
		tkw->di = H;
		tkw->image = nil;
		return same;
	}
	tkw->di = di;
	i = lookupimage(di);
	tkw->image = i;

	locked = lockdisplay(i->display);
	if(originwindow(i, ZP, i->r.min) == -1)
		print("tk originwindow failed: %r\n");
	di->r = DRECT(i->r);
	di->clipr = DRECT(i->clipr);
	if(locked)
		unlockdisplay(i->display);

	if(!same){
		D2H(di)->ref++;
		if(tk->name){
			name = tk->name->name;
			if(name[0] == '.' && name[1] == '\0')
				tktopimagedptr(tk->env->top, tkw->di);
		}
	}
	return same;
}

void
tkdestroywinimage(Tk *tk)
{
	TkWin *tkw;
	TkTop *top;
	char *name;

	assert(tk->flag & Tkwindow);
	tkw = TKobj(TkWin, tk);
	top = tk->env->top;

	if(tkw->image != nil && !(tk->flag & Tkswept))
		destroy(tkw->di);
	tkw->di = H;
	tkw->image = nil;
	if(tk->name == nil)
		name = tkw->cbname;
	else
		name = tk->name->name;
	if(name[0] == '.' && name[1] == '\0' && !(tk->flag & Tkswept))
		tktopimagedptr(top, H);
	tkw->reqid++;
	tkwreq(top, "delete %s", name);
}

static char*
tkputwinimage(Tk *tk, Draw_Image *di, int reqid)
{
	TkWin *tkw;
	TkTop *top;
	Image *i;
	int bw2, prop, resize;
	Rectangle req;

	top = tk->env->top;
	tkw = TKobj(TkWin, tk);
	i = lookupimage(di);
	if (i == nil || i->display != top->display)
		return TkNotwm;

	if(reqid != -1 && reqid < tkw->reqid)
		return "!request out of date";

	bw2 = 2*tk->borderwidth;
	req.min.x = tkw->req.x;
	req.min.y = tkw->req.y;
	req.max.x = req.min.x + tk->act.width + bw2;
	req.max.y = req.min.y + tk->act.height + bw2;

	resize = 0;
	if(eqrect(req, i->r) == 0){
		/*
		 * if we'd sent a request and our requested rect has now changed,
		 * then resend the request (via tkupdatewinsize),
		 * otherwise accept the new size and repack if necessary
		 */
		if(reqid != -1 && tkw->changed){
			if(tkupdatewinsize(tk))
				return "!requested size has changed";

		} else if(Dx(req) != Dx(i->r) || Dy(req) != Dy(i->r)){
			tk->flag |= Tksuspended;
			tk->act.width = Dx(i->r) - bw2;
			tk->act.height = Dy(i->r) - bw2;
			tk->req = tk->act;
			prop = tk->flag & Tknoprop;
			tk->flag |= Tknoprop;
			tkpackqit(tk);
			tkrunpack(top);
			tk->flag = (tk->flag & ~Tknoprop) | prop;
			resize = 1;
		}
	}
	if(reqid == -1)
		tkw->reqid++;		/* invalidate all buffered requests. */
	tkw->act = i->r.min;
	tkw->req = tkw->act;
	tkw->changed = 0;
	tk->req.width = Dx(i->r) - bw2;
	tk->req.height = Dy(i->r) - bw2;
	tk->act = tk->req;
	if((tk->flag & Tkmapped) == 0){
		tk->flag |= Tkmapped;
		tkdeliver(tk, TkMap, nil);
	}
	if(tksetwindrawimage(tk, di) == 0 || resize){
		tk->dirty = tkrect(tk, 1);
		tk->flag |= Tkrefresh;
	}
	tk->flag &= ~Tksuspended;

	lookupimage(di);			/* make sure limbo image coords correspond correctly */
	tkupdate(top);
	return nil;
}

void
tkwreq(TkTop *top, char *fmt, ...)
{
	char *buf;
	va_list arg;

	va_start(arg, fmt);
	buf = vsmprint(fmt, arg);
	va_end(arg);
	tktolimbo(top->wreq, buf);
	free(buf);
}

int
tktolimbo(void *var, char *msg)
{
	void *ptrs[1];
	int r;

	if(var==H)
		return 0;
	ptrs[0] = H;
	retstr(msg, (String**) &ptrs[0]);
	r = csendalt((Channel *)var, ptrs, &Tptr, TkMaxmsgs);
	return r;
}

static void
hexify(char *buf, int n)
{
	static char hex[] = "0123456789abcdef";
	uchar b;
	char *dp, *fp;
	fp = buf+n;
	dp = buf+n*2;
	*dp-- = '\0';
	while(fp-- > buf){
		b = (uchar)*fp;
		*dp-- = hex[b & 0xf];
		*dp-- = hex[b >> 4];
	}
}

char*
tkcursorswitch(TkTop *top, Image *i, TkImg *img)
{
	Image *ci, *scratch;
	char *buf;
	Rectangle r;
	int n, maxb, nb;

	if(i == nil && img == nil){
		tktolimbo(top->wreq, "cursor");
		return nil;
	}

	if(img != nil){
		if(img->cursor){
			tktolimbo(top->wreq, img->cursor);
			return nil;
		}
		i = img->img;
	}
	if(i->depth != 1 || Dx(i->r)*Dy(i->r) > 16000 || Dy(i->r)%8 != 0 || Dy(i->r)%2 != 0)
		return TkBadcursor;
	/*
	 * readjust image, inferring hotspot from origin.
	 */
	if(i->r.min.x != 0 || i->r.min.y != 0){
		r.min.x = 0;
		r.min.y = 0;
		r.max.x = Dx(i->r);
		r.max.y = Dy(i->r);
		scratch = allocimage(i->display, r, GREY1, 0, DNofill);
		if(scratch == nil)
			return TkNomem;
		draw(scratch, r, i, nil, i->r.min);
		ci = scratch;
	}else{
		scratch = nil;
		ci = i;
	}
	nb = ci->r.max.x/8 * ci->r.max.y;
	maxb = 7 + 12*4 + 2*nb + 1;
	buf = mallocz(maxb, 0);
	if(buf == nil)
		return TkNomem;
	n = sprint(buf, "cursor %d %d %d %d ", i->r.min.x, i->r.min.y, ci->r.max.x, ci->r.max.y);
	unloadimage(ci, ci->r, (uchar*)buf+n, maxb-n);
	hexify(buf+n, nb);
	tktolimbo(top->wreq, buf);
	if(img != nil){
		free(img->cursor);
		img->cursor = buf;
	}
	freeimage(scratch);
	return nil;
}

void
tkcursorset(TkTop *t, Point p)
{
	tkwreq(t, "ptr %d %d", p.x, p.y);
}
