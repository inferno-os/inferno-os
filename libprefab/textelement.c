#include <lib9.h>
#include <draw.h>
#include <interp.h>
#include <isa.h>
#include "../libinterp/runt.h"
#include <drawif.h>
#include <prefab.h>
#include <kernel.h>

typedef struct State State;

struct State
{
	Prefab_Environ	*env;
	List			*list;
	char			word[Maxchars+UTFmax];
	char			*s;
	char			*pending;
	Draw_Font	*font;
	Draw_Image	*color;
	Draw_Image	*icon;
	Draw_Image	*mask;
	String		*tag;
	Point			p;
	int			mainkind;
	int			kind;
	int			wid;
	int			newelem;
	int			ascent;
	int			descent;
};

static
char*
advword(char *s, char *word)
{
	char *e;
	int w;
	Rune r;

	e = s+Maxchars-1;
	switch(*word++ = *s){
	case '\t':		/* BUG: what to do about tabs? */
		strcpy(word-1, "    ");
		return s+1;
	case '\n':
	case ' ':
		*word = 0;
		return s+1;
	case '\0':
		return s;
	}
	s++;
	while(s<e && *s && *s!=' ' && *s!='\t' && *s!='\n'){
		if(*(uchar*)s < Runeself)
			*word++ = *s++;
		else{
			w = chartorune(&r, s);
			memmove(word, s, w);
			word += w;
			s += w;
		}
	}
	*word = 0;
	return s;
}

static
int
ismore(State *state)
{
	Prefab_Style *style;
	Prefab_Layout *lay;
	int text, icon;

	state->newelem = 0;
	if(state->kind==EIcon || (state->s && state->s[0]) || state->pending)
		return 1;
	if(state->list == H)
		return 0;
	lay = (Prefab_Layout*)state->list->data;
	text = (lay->text!=H && lay->text->len != 0);
	icon = (lay->icon!=H && lay->mask!=H);
	if(!text && !icon)
		return 0;
	state->newelem = 1;
	state->s = string2c(lay->text);
	state->font = lay->font;
	state->color = lay->color;
	state->icon = lay->icon;
	state->mask = lay->mask;
	state->tag = lay->tag;
	style = state->env->style;
	if(icon)	/* has precedence; if lay->icon is set, we ignore the text */
		state->kind = EIcon;
	else{
		if(state->mainkind == ETitle){
			if(state->font == H)
				state->font = style->titlefont;
			if(state->color == H)
				state->color = style->titlecolor;
		}else{
			if(state->font == H)
				state->font = style->textfont;
			if(state->color == H)
				state->color = style->textcolor;
		}
		state->kind = state->mainkind;
	}
	state->list = state->list->tail;
	return 1;
}

PElement*
growtext(PElement *pline, State *state, char *w, int minx, int maxx)
{
	String *s;
	PElement *pe, *plist;
	Prefab_Element *e;
	List *atom;
	Point size;
	Image *image;

	if(state->newelem || pline==H) {
		pe = mkelement(state->env, state->kind);
		e = &pe->e;
		e->r.min.x = minx;
		if(state->kind == EIcon){
			e->image = state->icon;
			D2H(e->image)->ref++;
			e->mask = state->mask;
			D2H(e->mask)->ref++;
		}else{
			e->image = state->color;
			D2H(e->image)->ref++;
			e->font = state->font;
			D2H(e->font)->ref++;
		}
		e->tag = state->tag;
		if(e->tag != H)
			D2H(e->tag)->ref++;
		if(pline == H)
			pline = pe;
		else{
			if(pline->pkind != EHorizontal){
				/* promote pline to list encapsulating current contents */
				atom = prefabwrap(pline);
				plist = mkelement(state->env, EHorizontal);
				destroy(pline);
				/* rest of plist->e.r will be set later */
				plist->e.r.min.x = state->p.x;
				plist->drawpt = state->p;
				plist->e.kids = atom;
				plist->first = atom;
				plist->last = atom;
				plist->vfirst = atom;
				plist->vlast = atom;
				pline = plist;
			}
			/* add e to line */
			atom = prefabwrap(e);
			destroy(e);	/* relevant data now in wrapper */
			e = *(Prefab_Element**)atom->data;
			pline->last->tail = atom;
			pline->last = atom;
			pline->vlast = atom;
			pline->nkids++;
		}
		state->newelem = 0;
	}else{
		pe = pline;
		if(pe->pkind == EHorizontal)
			pe = *(PElement**)pe->last->data;
		e = &pe->e;
	}

	if(state->kind == EIcon){
		/* guaranteed OK by buildine */	
		image = lookupimage(state->icon);
		size = iconsize(image);
		/* put one pixel on each side */
		e->r.max.x = e->r.min.x+1+size.x+1;
		pline->e.r.max.x = e->r.max.x;
		if(state->ascent < size.y)
			state->ascent = size.y;
		state->kind = -1;	/* consume EIcon from state */
		return pline;
	}

	e->r.max.x = maxx;
	pline->e.r.max.x = maxx;
	if(*w == '\n') {
		pline->newline = 1;
		return pline;
	}

	s = addstring(e->str, c2string(w, strlen(w)), 0);
	destroy(e->str);
	e->str = s;

	if(state->ascent < e->font->ascent)
		state->ascent = e->font->ascent;
	if(state->descent < e->font->height-e->font->ascent)
		state->descent = e->font->height-e->font->ascent;
	return pline;
}

PElement*
buildline(State *state, int *ok)
{
	int wordwid, linewid, nb, rwid, x;
	char tmp[UTFmax+1], *w, *t;
	PElement *pl, *pe;
	Rune r;
	Font *f;
	List *l;
	Image *icon;
	Point size;

	*ok = 1;
	linewid = 0;
	pl = H;
	state->ascent = 0;
	state->descent = 0;
	x = state->p.x;
	while(ismore(state)){
		f = nil;
		if(state->kind == EIcon){
			icon = lookupimage(state->icon);
			if(icon == nil){
    Error:
				destroy(pl);
				*ok = 0;
				return H;
			}
			size = iconsize(icon);
			wordwid = 1+size.x+1;
		}else{
			if(state->pending == 0){
				state->s = advword(state->s, state->word);
				state->pending = state->word;
			}
			if(*(state->pending) == '\n'){
				pl = growtext(pl, state, state->pending, x, x);
				if(pl == H){
					*ok = 0;
					return H;
				}
				state->pending = 0;
				break;
			}
			f = lookupfont(state->font);
			if(f == nil)
				goto Error;
			wordwid = stringwidth(f, state->pending);
		}
		if(linewid+wordwid<=state->wid){
    Easy:
			pl = growtext(pl, state, state->pending, x, x+wordwid);
			if(pl == H){
				*ok = 0;
				return H;
			}
			linewid += wordwid;
			state->pending = 0;
			x += wordwid;
			continue;
		}
		/* this word doesn't fit on this line */
		/* if it's white space or an icon, just generate a line break */
		if(state->word[0]==' ' || state->kind==EIcon){
			if(linewid == 0)	/* it's just too wide; emit it and it'll get clipped */
				goto Easy;
			state->pending = 0;
			break;
		}
		/* if word would fit were we to break the line now, do so */
		if(wordwid <= state->wid)
			break;
		/* worst case: bite off the biggest piece that fits */
		w = state->pending;
		while(*w){
			nb = chartorune(&r, w);
			memmove(tmp, w, nb);
			tmp[nb] = 0;
			rwid = stringwidth(f, tmp);
			if(linewid+rwid > state->wid)
				break;
			linewid += rwid;
			w += nb;
		}
		if(w == state->pending){
			/* first char too wide for remaining space */
			if(linewid > 0)
				break;
			/* remaining space is all we'll get */
			kwerrstr("can't handle wide word in textelement\n");
			goto Error;
		}
		nb = w-state->pending;
		t = malloc(nb+1);
		if(t == nil)
			goto Error;
		memmove(t, state->pending, nb);
		t[nb] = 0;
		pl = growtext(pl, state, t, x, state->p.x+linewid);
		free(t);
		if(pl == H){
			*ok = 0;
			return H;
		}
		state->pending = w;
		break;
	}
	pl->e.r.min.y = state->p.y;
	pl->e.r.max.y = state->p.y+state->ascent+state->descent;
	P2P(pl->drawpt, pl->e.r.min);
	if(pl->pkind==EHorizontal){
		for(l=pl->first; l!=H; l=l->tail){
			pe = *(PElement**)l->data;
			pe->e.r.min.y = state->p.y;
			pe->e.r.max.y = state->p.y+state->ascent+state->descent;
			pe->drawpt.x = pe->e.r.min.x;
			if(pe->e.kind == EIcon){
				/* add a pixel on the left; room was left in growtext */
				pe->drawpt.x += 1;
				pe->drawpt.y = pe->e.r.min.y+(state->ascent-Dy(pe->e.image->r));
			}else
				pe->drawpt.y = pe->e.r.min.y+(state->ascent-pe->e.font->ascent);
		}
	}
	return pl;
}

PElement*
layoutelement(Prefab_Environ *env, List *laylist, Draw_Rect rr, enum Elementtype kind)
{
	PElement *pline, *plist, *firstpline;
	List *lines, *atom, *tail;
	State state;
	int nlines, linewid, maxwid, wid, trim, maxy, ok;
	Point p;
	Rectangle r;
	Screen *screen;

	nlines = 0;
	trim = 0;
	wid = Dx(rr);
	if(wid < 25){
		if(wid <= 0)
			trim = 1;
		screen = lookupscreen(env->screen);
		if(screen == nil)
			return H;
		wid = Dx(screen->display->image->r)-32;
		if(wid < 100)
			wid = 100;
	}
	wid -= 3+3;	/* three pixels left and right */

	gchalt++;
	state.env = env;
	state.list = laylist;
	state.s = 0;
	state.pending = 0;
	state.font = H;
	state.color = H;
	state.tag = H;
	p = IPOINT(rr.min);
	p.x += 3;
	state.p = p;
	state.kind = EText;	/* anything but EIcon */
	state.mainkind = kind;
	state.wid = wid;
	lines = H;
	tail = H;
	firstpline = H;
	maxwid = 0;
	maxy = 0;
	while(ismore(&state)){
		pline = buildline(&state, &ok);
		if(ok == 0){
			plist = H;
			goto Return;
		}
		if(pline == H)
			break;
		linewid = Dx(pline->e.r);
		if(linewid > maxwid)
			maxwid = linewid;
		if(firstpline == H)
			firstpline = pline;
		else{
			atom = prefabwrap(pline);
			destroy(pline);	/* relevant data now in wrapper */
			pline = *(PElement**)atom->data;
			if(lines == H){
				lines = prefabwrap(firstpline);
				destroy(firstpline);
				firstpline = 0;	/* never used again; this proves it! */
				tail = lines;
			}
			tail->tail = atom;
			tail = atom;
		}
		nlines++;
		state.p.y = pline->e.r.max.y;
		if(maxy==0 || state.p.y<=rr.max.y)
			maxy = state.p.y;
	}
	if(trim == 0)
		maxwid = wid;
	if(nlines == 0){
		plist = H;
		goto Return;
	}
	if(nlines == 1){
		if(trim == 0){	/* restore clipping around element */
			firstpline->e.r.min.x = rr.min.x;
			firstpline->e.r.max.x = rr.min.x+3+maxwid+3;
		}
		plist = firstpline;
		goto Return;
	}
	plist = mkelement(env, EVertical);
	plist->e.r.min.x = rr.min.x;
	plist->e.r.min.y = p.y;
	plist->e.r.max.x = rr.min.x+3+maxwid+3;
	plist->e.r.max.y = (*(Prefab_Element**)tail->data)->r.max.y;
	plist->drawpt = p;
	plist->e.kids = lines;
	plist->first = lines;
	plist->last = tail;
	plist->vfirst = lines;
	plist->vlast = tail;
	plist->nkids = nlines;
	/* if asked for a fixed size and list is too long, clip */
	if(Dy(rr)>0 && rr.max.y<plist->e.r.max.y){
		R2R(r, plist->e.r);
		r.max.y = maxy;
		clipelement(&plist->e, r);
	}

Return:
	gchalt--;
	return plist;
}

/*
 * Create List with one Layout in it, using malloc instead of heap to
 * keep it out of the eyes of the garbage collector
 */
List*
listoflayout(Prefab_Style *style, String *text, int kind)
{
	List *listp;
	Prefab_Layout *layp;

	listp = malloc(sizeof(List) + TLayout->size);
	if(listp == nil)
		return H;
	listp->tail = H;
	layp = (Prefab_Layout*)listp->data;
	if(kind == EText){
		layp->font = style->textfont;
		layp->color = style->textcolor;
	}else{
		layp->font = style->titlefont;
		layp->color = style->titlecolor;
	}
	layp->text = text;
	layp->icon = H;
	layp->mask = H;
	layp->tag = H;
	return listp;
}

PElement*
textelement(Prefab_Environ *env, String *str, Draw_Rect rr, enum Elementtype kind)
{
	PElement *pe;
	List *l;

	l = listoflayout(env->style, str, kind);
	pe = layoutelement(env, l, rr, kind);
	free(l);
	return pe;
}
