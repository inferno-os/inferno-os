#include "lib9.h"
#include "draw.h"
#include "tk.h"
#include "textw.h"

#define istring u.string
#define iwin u.win
#define imark u.mark
#define iline u.line

/* debugging */
extern int tktdbg;
extern void tktprinttext(TkText*);
extern void tktprintindex(TkTindex*);
extern void tktprintitem(TkTitem*);
extern void tktprintline(TkTline*);

char*
tktindparse(Tk *tk, char **pspec, TkTindex *ans)
{
	int m, n, done, neg, modstart;
	char *s, *mod;
	TkTline *lend;
	TkText *tkt;
	char *buf;

	buf = mallocz(Tkmaxitem, 0);
	if(buf == nil)
		return TkNomem;

	tkt = TKobj(TkText, tk);
	lend = &tkt->end;

	*pspec = tkword(tk->env->top, *pspec, buf, buf+Tkmaxitem, nil);
	modstart = 0;
	for(mod = buf; *mod != '\0'; mod++)
		if(*mod == ' ' || *mod == '-' || *mod == '+') {
			modstart = *mod;
			*mod = '\0';
			break;
		}

	/*
	 * XXX there's a problem here - if either coordinate is negative
	 * which shouldn't be precluded, then the above scanning code
	 * will break up the coordinate pair, so @-23,45 for example
	 * yields a bad index, when it should probably return the index
	 * of the character at the start of the line containing y=45.
	 * i've seen this cause wm/sh to crash.
	 */
	if(strcmp(buf, "end") == 0)
		tktendind(tkt, ans);
	else
	if(*buf == '@') {
		/* by coordinates */

		s = strchr(buf, ',');
		if(s == nil) {
			free(buf);
			return TkBadix;
		}
		*s = '\0';
		m = atoi(buf+1);
		n = atoi(s+1);
		tktxyind(tk, m, n, ans);
	}
	else
	if(*buf >= '0' && *buf <= '9') {
		/* line.char */

		s = strchr(buf, '.');
		if(s == nil) {
			free(buf);
			return TkBadix;
		}
		*s = '\0';
		m = atoi(buf);
		n = atoi(s+1);

		if(m < 1)
			m = 1;

		tktstartind(tkt, ans);

		while(--m > 0 && ans->line->next != lend)
			tktadjustind(tkt, TkTbyline, ans);

		while(n-- > 0 && ans->item->kind != TkTnewline)
			tktadjustind(tkt, TkTbychar, ans);
	}
	else
	if(*buf == '.') {
		/* window */

		tktstartind(tkt, ans);

		while(ans->line != lend) {
			if(ans->item->kind == TkTwin &&
			   ans->item->iwin->sub != nil &&
			   ans->item->iwin->sub->name != nil &&
			   strcmp(ans->item->iwin->sub->name->name, buf) == 0)
				break;
			if(!tktadjustind(tkt, TkTbyitem, ans))
				ans->line = lend;
		}
		if(ans->line == lend) {
			free(buf);
			return TkBadix;
		}
	}
	else {
		s = strchr(buf, '.');
		if(s == nil) {
			if(tktmarkind(tk, buf, ans) == 0) {
				free(buf);
				return TkBadix;
			}
		}
		else {
			/* tag.first or tag.last */

			*s = '\0';
			if(strcmp(s+1, "first") == 0) {
				if(tkttagind(tk, buf, 1, ans) == 0) {
					free(buf);
					return TkBadix;
				}
			}
			else
			if(strcmp(s+1, "last") == 0) {
				if(tkttagind(tk, buf, 0, ans) == 0) {
					free(buf);
					return TkBadix;
				}
			}
			else {
				free(buf);
				return TkBadix;
			}
		}
	}

	if(modstart == 0) {
		free(buf);
		return nil;
	}

	*mod = modstart;
	while(*mod == ' ')
		mod++;

	while(*mod != '\0') {
		done = 0;
		switch(*mod) {
		case '+':
		case '-':
			neg = (*mod == '-');
			mod++;
			while(*mod == ' ')
				mod++;
			n = strtol(mod, &mod, 10);
			while(*mod == ' ')
				mod++;
			while(n-- > 0) {
				if(*mod == 'c')
					tktadjustind(tkt, neg? TkTbycharback : TkTbychar, ans);
				else
				if(*mod == 'l')
					tktadjustind(tkt, neg? TkTbylineback : TkTbyline, ans);
				else
					done = 1;
			}
			break;
		case 'l':
			if(strncmp(mod, "lines", 5) == 0)
				tktadjustind(tkt, TkTbylinestart, ans);
			else
			if(strncmp(mod, "linee", 5) == 0)
				tktadjustind(tkt, TkTbylineend, ans);
			else
				done = 1;
			break;
		case 'w':
			if(strncmp(mod, "words", 5) == 0)
				tktadjustind(tkt, TkTbywordstart, ans);
			else
			if(strncmp(mod, "worde", 5) == 0)
				tktadjustind(tkt, TkTbywordend, ans);
			else
				done = 1;
			break;
		default:
				done = 1;
		}

		if(done)
			break;

		while(tkiswordchar(*mod))
			mod++;
		while(*mod == ' ')
			mod++;
	}

	free(buf);
	return nil;
}

int
tktisbreak(int c)
{
	/* unicode rules suggest / as well but that would split dates, and URLs might as well char. wrap */
	return c == ' ' || c == '\t' || c == '\n' || c == '-' || c == ',';
	/* previously included . but would probably need more then to handle ." */
}

/*
 * Adjust the index p by units (one of TkTbyitem, etc.).
 * The TkTbychar units mean that the final point should rest on a
 * "character" (in text widget index space; i.e., a newline, a rune,
 * and an embedded window are each 1 character, but marks and contlines are not).
 *
 * Indexes may not point in the tkt->start or tkt->end lines (which have
 * no items); tktadjustind sticks at the beginning or end of the buffer.
 *
 * Return 1 if the index changes at all, 0 otherwise.
 */
int
tktadjustind(TkText *tkt, int units, TkTindex *p)
{
	int n, opos, count, c;
	TkTitem *i, *it, *oit;
	TkTindex q;

	oit = p->item;
	opos = p->pos;
	count = 1;

	switch(units) {
	case TkTbyitemback:
		it = p->item;
		p->item = p->line->items;
		p->pos = 0;
		if(it == p->item) {
			if(p->line->prev != &tkt->start) {
				p->line = p->line->prev;
				p->item = tktlastitem(p->line->items);
			}
		}
		else {
			while(p->item->next != it) {
				p->item = p->item->next;
				if(tktdbg && p->item == nil) {
					print("tktadjustind: botch 1\n");
					break;
				}
			}
		}
		break;

	case TkTbyitem:
		p->pos = 0;
		i = p->item->next;
		if(i == nil) {
			if(p->line->next != &tkt->end) {
				p->line = p->line->next;
				p->item = p->line->items;
			}
		}
		else
			p->item = i;
		break;

	case TkTbytlineback:
		if(p->line->prev != &tkt->start)
			p->line = p->line->prev;
		p->item = p->line->items;
		p->pos = 0;
		break;

	case TkTbytline:
		if(p->line->next != &tkt->end)
			p->line = p->line->next;
		p->item = p->line->items;
		p->pos = 0;
		break;

	case TkTbycharstart:
		count = 0;
	case TkTbychar:
		while(count > 0) {
			i = p->item;
			n = tktposcount(i) - p->pos;
			if(count >= n) {
				if(tktadjustind(tkt, TkTbyitem, p))
					count -= n;
				else
					break;
			}
			else {
				p->pos += count;
				break;
			}
		}
		while(p->item->kind == TkTmark || p->item->kind == TkTcontline)
			if(!tktadjustind(tkt, TkTbyitem, p))
				break;
		break;
	case TkTbycharback:
		count = -1;
		while(count < 0) {
			if(p->pos + count >= 0) {
				p->pos += count;
				count = 0;
			}
			else {
				count += p->pos;
				if(!tktadjustind(tkt, TkTbyitemback, p))
					break;
				n = tktposcount(p->item);
				p->pos = n;
			}
		}
		break;

	case TkTbylineback:
		count = -1;
		/* fall through */
	case TkTbyline:
		n = tktlinepos(tkt, p);
		while(count > 0) {
			if(p->line->next == &tkt->end) {
				count = 0;
				break;
			}
			if(p->line->flags&TkTlast)
				count--;
			p->line = p->line->next;
		}
		while(count < 0 && p->line->prev != &tkt->start) {
			if(p->line->flags&TkTfirst)
				count++;
			p->line = p->line->prev;
		}
		tktadjustind(tkt, TkTbylinestart, p);
		while(n > 0) {
			if(p->item->kind == TkTnewline)
				break;
			if(!tktadjustind(tkt, TkTbychar, p))
				break;
			n--;
		}
		break;

	case TkTbylinestart:
		/* note: can call this with only p->line set correctly  in *p */

		while(!(p->line->flags&TkTfirst))
			p->line = p->line->prev;
		p->item = p->line->items;
		p->pos = 0;
		break;

	case TkTbylineend:
		while(p->item->kind != TkTnewline)
			if(!tktadjustind(tkt, TkTbychar, p))
				break;
		break;

	case TkTbywordstart:
		tktadjustind(tkt, TkTbycharstart, p);
		q = *p;
		c = tktindrune(p);
		while(tkiswordchar(c)) {
			q = *p;
			if(!tktadjustind(tkt, TkTbycharback, p))
				break;
			c = tktindrune(p);
		}
		*p = q;
		break;

	case TkTbywordend:
		tktadjustind(tkt, TkTbycharstart, p);
		if(p->item->kind == TkTascii || p->item->kind == TkTrune) {
			c = tktindrune(p);
			if(tkiswordchar(c)) {
				do {
					if(!tktadjustind(tkt, TkTbychar, p))
						break;
					c = tktindrune(p);
				} while(tkiswordchar(c));
			}
			else
				tktadjustind(tkt, TkTbychar, p);
		}
		else if(!(p->item->kind == TkTnewline && p->line->next == &tkt->end))
			tktadjustind(tkt, TkTbychar, p);

		break;

	case TkTbywrapstart:
		tktadjustind(tkt, TkTbycharstart, p);
		q = *p;
		c = tktindrune(p);
		while(!tktisbreak(c)) {
			q = *p;
			if(!tktadjustind(tkt, TkTbycharback, p))
				break;
			c = tktindrune(p);
		}
		*p = q;
		break;

	case TkTbywrapend:
		tktadjustind(tkt, TkTbycharstart, p);
		if(p->item->kind == TkTascii || p->item->kind == TkTrune) {
			c = tktindrune(p);
			if(!tktisbreak(c)) {
				do {
					if(!tktadjustind(tkt, TkTbychar, p))
						break;
					c = tktindrune(p);
				} while(!tktisbreak(c) && (p->item->kind == TkTascii || p->item->kind == TkTrune));
				while(tktisbreak(c) && tktadjustind(tkt, TkTbychar, p))
					c = tktindrune(p);	/* could limit it */
			}
			else
				tktadjustind(tkt, TkTbychar, p);
		}
		else if(!(p->item->kind == TkTnewline && p->line->next == &tkt->end))
			tktadjustind(tkt, TkTbychar, p);

		break;
	}
	return (p->item != oit || p->pos != opos);
}

/* return 1 if advancing i1 by item eventually hits i2 */
int
tktindbefore(TkTindex *i1, TkTindex *i2)
{
	int ans;
	TkTitem *i;
	TkTline *l1, *l2;

	ans = 0;
	l1 = i1->line;
	l2 = i2->line;

	if(l1 == l2) {
		if(i1->item == i2->item)
			ans = (i1->pos < i2->pos);
		else {
			for(i = i1->item; i != nil; i = i->next)
				if(i->next == i2->item) {
					ans = 1;
					break;
				}
		}
	}
	else {
		if(l1->orig.y < l2->orig.y)
			ans = 1;
		else
		if(l1->orig.y == l2->orig.y) {
			for(; l1 != nil; l1 = l1->next) {
				if(l1->next == l2) {
					ans = 1;
					break;
				}
				if(l1->orig.y > l2->orig.y)
					break;
			}
		}
	}

	return ans;
}

/*
 * This comparison only cares which characters the indices are before.
 * So two marks should be called "equal" (and not "less" or "greater")
 * if they are adjacent.
 */
int
tktindcompare(TkText *tkt, TkTindex *i1, int op, TkTindex *i2)
{
	int eq, ans;
	TkTindex x1, x2;

	x1 = *i1;
	x2 = *i2;

	/* skip over any marks, contlines, to see if on same character */
	tktadjustind(tkt, TkTbycharstart, &x1);
	tktadjustind(tkt, TkTbycharstart, &x2);
	eq = (x1.item == x2.item && x1.pos == x2.pos);

	switch(op) {
	case TkEq:
		ans = eq;
		break;
	case TkNeq:
		ans = !eq;
		break;
	case TkLte:
		ans = eq || tktindbefore(i1, i2);
		break;
	case TkLt:
		ans = !eq && tktindbefore(i1, i2);
		break;
	case TkGte:
		ans = eq || tktindbefore(i2, i1);
		break;
	case TkGt:
		ans = !eq && tktindbefore(i2, i1);
		break;
	default:
		SET(ans);
	};

	return ans;
}

void
tktstartind(TkText *tkt, TkTindex *ans)
{
	ans->line = tkt->start.next;
	ans->item = ans->line->items;
	ans->pos = 0;
}

void
tktendind(TkText *tkt, TkTindex *ans)
{
	ans->line = tkt->end.prev;
	ans->item = tktlastitem(ans->line->items);
	ans->pos = 0;
}

void
tktitemind(TkTitem *it, TkTindex *ans)
{
	ans->item = it;
	ans->line = tktitemline(it);
	ans->pos = 0;
}

/*
 * Fill ans with the item that (x,y) (in V space) is over.
 * Return 0 if it is over the first half of the width,
 * and 1 if it is over the second half.
 */
int
tktxyind(Tk *tk, int x, int y, TkTindex *ans)
{
	int n, w, secondhalf, k;
	Point p, q;
	TkTitem *i;
	TkText *tkt;

 	tkt = TKobj(TkText, tk);
	tktstartind(tkt, ans);
	secondhalf = 0;

	/* (x,y), p, q in V space */
	p = subpt(ans->line->orig, tkt->deltatv);
	q = subpt(ans->line->next->orig, tkt->deltatv);
	while(ans->line->next != &tkt->end) {
		if(q.y > y)
			break;
		tktadjustind(tkt, TkTbytline, ans);
		p = q;
		q = subpt(ans->line->next->orig, tkt->deltatv);
	}
	if (ans->line->next == &tkt->end) {
		Point ep = subpt(tkt->end.orig, tkt->deltatv);
		if (ep.y < y)
			x = 1000000;
	}

	while(ans->item->next != nil) {
		i = ans->item;
		w = i->width;
		if(p.x+w > x) {
			n = tktposcount(i);
			if(n > 1) {
				for(k = 0; k < n; k++) {
					/* probably wrong w.r.t tag tabs */
					w = tktdispwidth(tk, nil, i, nil, p.x, k, 1);
					if(p.x+w > x) {
						ans->pos = k;
						break;
					}
					p.x += w;
				}
			}
			secondhalf = (p.x + w/2 <= x);
			break;
		}
		p.x += w;
		if(!tktadjustind(tkt, TkTbyitem, ans))
			break;
	}
	tktadjustind(tkt, TkTbycharstart, ans);
	return secondhalf;
}

