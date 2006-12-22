#include "lib9.h"
#include "logfs.h"
#include "local.h"

typedef struct ExtentNode {
	Extent e;
	struct ExtentNode *next;
} ExtentNode;

struct ExtentList {
	ExtentNode *head;
};

char *
logfsextentlistnew(ExtentList **ep)
{
	ExtentList *l;
	l = logfsrealloc(nil, sizeof(*l));
	if(l == nil)
		return Enomem;
	*ep = l;
	return  nil;
}

void
logfsextentlistreset(ExtentList *l)
{
	ExtentNode *n;
	n = l->head;
	while(n) {
		ExtentNode *next;
		next = n->next;
		logfsfreemem(n);
		n = next;
	}
	l->head = nil;
}

void
logfsextentlistfree(ExtentList **lp)
{
	ExtentList *l;
	if(lp == nil || (l = *lp) == nil)
		return;
	logfsextentlistreset(l);
	logfsfreemem(l);
	*lp = nil;
}

char *
logfsextentlistinsert(ExtentList *l, Extent *add, Extent **new)
{
	ExtentNode *old, *prev;
	ExtentNode *saved = nil;

	if(l == nil)
		return "nil extentlist";

	/* initially a's extents are non-empty, disjoint and sorted */
	old = l->head;
	prev = nil;
	while(old) {
		ExtentNode *next = old->next;
		if(add->max <= old->e.min)
			break;
		if(old->e.min < add->max && add->min < old->e.max) {	/* they intersect */
			if(add->min <= old->e.min) {
				/* add overlaps front of old */
				if(add->max < old->e.max) {
					int trimmed;
					/* but doesn't overlap end */
					/* retain tail of old */
					if(saved == nil)
						saved = logfsrealloc(nil, sizeof(*saved));
					if(saved == nil)
						goto nomem;
					trimmed = add->max - old->e.min;
					old->e.min += trimmed;
					old->e.flashaddr += trimmed;
					/* can't touch any further extents, so... */
					break;
				}
				/* add.min ≤ old.min < old.max ≤ add.max ⇒ add completely covers old */
				/* delete old */
				if(prev)
					prev->next = next;
				else
					l->head = next;
				/* stash the deleted extent, so we can reuse it */
				if(saved == nil)
					saved = old;
				else
					logfsfreemem(old);
				old = next;
				continue;
			}
			else {
				/* add.min > old.min, so overlaps end of old or splits it */
				if(add->max < old->e.max) {	/* add inside old, splitting it */
					ExtentNode *frag;
					/*
					 * will need at most two add extents, so ensure
					 * enough store exists before changing data structures
					 */
					if(saved == nil)
						saved = logfsrealloc(nil, sizeof(*saved));
					frag = logfsrealloc(nil, sizeof(*frag));
					if(saved == nil || frag == nil)
						goto nomem;
					frag->next = next;
					old->next = frag;
					frag->e.min = add->max;
					frag->e.max = old->e.max;
					frag->e.flashaddr = old->e.flashaddr + (add->max - old->e.min);
					old->e.max = add->min;
					prev = old;
					break;
				}
				else {
					/*
					 * will need at most one add extent, so create one
					 * now before changing data structures
					 */
					if(saved == nil)
						saved = logfsrealloc(nil, sizeof(*saved));
					if(saved == nil)
						goto nomem;
					old->e.max = add->min;		/* retain start of old */
				}
				/* old.max <= add.max ⇒ add covers tail of old */
			}
		}
		prev = old;
		old = next;
	}
	/*
	 * if here, and saved == nil, then there was no overlap
	 */
	if(saved == nil)
		saved = logfsrealloc(nil, sizeof(*saved));
	if(saved == nil) {
	nomem:
		return Enomem;
	}
	saved->e = *add;
	if(prev) {
		saved->next = prev->next;
		prev->next = saved;
	}
	else {
		saved->next = l->head;
		l->head = saved;
	}
	if(new)
		*new = &saved->e;
	return nil;
}

Extent *
logfsextentlistmatch(ExtentList *l, Extent *e)
{
	ExtentNode *m;
	u32int flashmax;

	if(l == nil)
		return nil;

	flashmax = e->flashaddr + (e->max - e->min);

	for(m = l->head; m; m = m->next) {
		u32int l = m->e.max - m->e.min;
		if(e->min < m->e.max && m->e.min < e->max	/* they intersect */
			&& m->e.flashaddr < flashmax && e->flashaddr < m->e.flashaddr + l) /* the store intersects */
			return &(m->e);
	}
	return nil;
}

int
logfsextentlistmatchall(ExtentList *l, int (*func)(void *magic, Extent *), void *magic, Extent *e)
{
	ExtentNode *m;
	u32int flashmax;

	if(l == nil)
		return 1;

	flashmax = e->flashaddr + (e->max - e->min);

	for(m = l->head; m; m = m->next) {
		u32int l;
		if(m->e.min >= e->max)
			return 1;
		l = m->e.max - m->e.min;
		if(e->min < m->e.max	/* they intersect */
			&& m->e.flashaddr < flashmax && e->flashaddr < m->e.flashaddr + l) {
			/* the store intersects */
			int rv = (*func)(magic, &(m->e));
			if(rv <= 0)
				return rv;
		}
	}
	return 1;
}

int
logfsextentlistwalk(ExtentList *l, int (*func)(void *magic, Extent *, int hole), void *magic)
{
	ExtentNode *n;
	u32int last = 0;
	if(l == nil)
		return 1;
	for(n = l->head; n; n = n->next) {
		int rv;
		if(last < n->e.min) {
			Extent hole;
			hole.min = last;
			hole.max = n->e.min;
			hole.flashaddr = ~0;
			rv = (*func)(magic, &hole, 1);
			if(rv <= 0)
				return rv;
		}
		rv = (*func)(magic, &n->e, 0);
		if(rv <= 0)
			return rv;
		last = n->e.max;
	}
	return 1;
}

int
logfsextentlistwalkrange(ExtentList *l, int (*func)(void *magic, u32int baseoffset, u32int limitoffset, Extent *, u32int extentoffset), void *magic, u32int base, u32int limit)
{
	ExtentNode *n;
	u32int last = 0;
	if(l == nil)
		return 1;
	for(n = l->head; n; n = n->next) {
		Extent hole;
		Extent *e;
		if(last < n->e.min) {
			hole.min = last;
			hole.max = n->e.min;
			e = &hole;
		}
		else {
		again:
			e = &n->e;
		}
		if(e->min >= limit)
			return 1;
//print("walkrange %ud .. %ud\n", e->min, e->max);
		if(e->max > base) {
			ulong rangebase, rangelimit, extentoffset;
			int rv;
			rangebase = e->min;
			if(rangebase < base) {
				extentoffset = base - rangebase;
				rangebase += extentoffset;
			}
			else
				extentoffset = 0;
			rangelimit = e->max;
			if(rangelimit > limit)
				rangelimit = limit;
			rv = (*func)(magic, rangebase - base, rangelimit - base, e == &hole ? nil : e, extentoffset);
			if(rv <= 0)
				return rv;
		}
		last = e->max;
		if(e == &hole)
			goto again;
	}
	return 1;
}
