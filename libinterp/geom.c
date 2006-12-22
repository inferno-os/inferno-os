#include "lib9.h"
#include "interp.h"
#include "isa.h"
#include "draw.h"
#include "runt.h"
#include "raise.h"

void
Point_add(void *fp)
{
	F_Point_add *f;
	Draw_Point *ret;

	f = fp;

	ret = f->ret;
	ret->x = f->p.x + f->q.x;
	ret->y = f->p.y + f->q.y;
}

void
Point_sub(void *fp)
{
	F_Point_sub *f;
	Draw_Point *ret;

	f = fp;

	ret = f->ret;
	ret->x = f->p.x - f->q.x;
	ret->y = f->p.y - f->q.y;
}

void
Point_mul(void *fp)
{
	F_Point_mul *f;
	Draw_Point *ret;

	f = fp;

	ret = f->ret;
	ret->x = f->p.x * f->i;
	ret->y = f->p.y * f->i;
}

void
Point_div(void *fp)
{
	F_Point_div *f;
	Draw_Point *ret;

	f = fp;

	if(f->i == 0)
		error(exZdiv);
	ret = f->ret;
	ret->x = f->p.x / f->i;
	ret->y = f->p.y / f->i;
}

void
Point_eq(void *fp)
{
	F_Point_eq *f;

	f = fp;
	*f->ret = f->p.x == f->q.x && f->p.y == f->q.y;
}

void
Point_in(void *fp)
{
	F_Point_in *f;

	f = fp;
	*f->ret = f->p.x >= f->r.min.x && f->p.x < f->r.max.x &&
	       f->p.y >= f->r.min.y && f->p.y < f->r.max.y;
}

void
Rect_canon(void *fp)
{
	F_Rect_canon *f;
	Draw_Rect *ret;
	WORD t;

	f = fp;

	ret = f->ret;
	if(f->r.max.x < f->r.min.x){
		t = f->r.max.x;
		ret->max.x = f->r.min.x;
		ret->min.x = t;
	}else{
		t = f->r.max.x;
		ret->min.x = f->r.min.x;
		ret->max.x = t;
	}
	if(f->r.max.y < f->r.min.y){
		t = f->r.max.y;
		ret->max.y = f->r.min.y;
		ret->min.y = t;
	}else{
		t = f->r.max.y;
		ret->min.y = f->r.min.y;
		ret->max.y = t;
	}
}

void
Rect_combine(void *fp)
{
	F_Rect_combine *f;
	Draw_Rect *ret;

	f = fp;
	ret = f->ret;
	*ret = f->r;
	if(f->r.min.x > f->s.min.x)
		ret->min.x = f->s.min.x;
	if(f->r.min.y > f->s.min.y)
		ret->min.y = f->s.min.y;
	if(f->r.max.x < f->s.max.x)
		ret->max.x = f->s.max.x;
	if(f->r.max.y < f->s.max.y)
		ret->max.y = f->s.max.y;
}

void
Rect_eq(void *fp)
{
	F_Rect_eq *f;

	f = fp;

	*f->ret = f->r.min.x == f->s.min.x
		&& f->r.max.x == f->s.max.x
		&& f->r.min.y == f->s.min.y
		&& f->r.max.y == f->s.max.y;
}

void
Rect_Xrect(void *fp)
{
	F_Rect_Xrect *f;

	f = fp;

	*f->ret = f->r.min.x < f->s.max.x
		&& f->s.min.x < f->r.max.x
		&& f->r.min.y < f->s.max.y
		&& f->s.min.y < f->r.max.y;
}

void
Rect_clip(void *fp)
{
	F_Rect_clip *f;
	Draw_Rect *r, *s, *ret;

	f = fp;

	r = &f->r;
	s = &f->s;
	ret = &f->ret->t0;

	/*
	 * Expand rectXrect() in line for speed
	 */
	if(!(r->min.x<s->max.x && s->min.x<r->max.x
	&& r->min.y<s->max.y && s->min.y<r->max.y)){
		*ret = *r;
		f->ret->t1 = 0;
		return;
	}

	/* They must overlap */
	if(r->min.x < s->min.x)
		ret->min.x = s->min.x;
	else
		ret->min.x = r->min.x;
	if(r->min.y < s->min.y)
		ret->min.y = s->min.y;
	else
		ret->min.y = r->min.y;
	if(r->max.x > s->max.x)
		ret->max.x = s->max.x;
	else
		ret->max.x = r->max.x;
	if(r->max.y > s->max.y)
		ret->max.y = s->max.y;
	else
		ret->max.y = r->max.y;
	f->ret->t1 = 1;
}

void
Rect_inrect(void *fp)
{
	F_Rect_inrect *f;

	f = fp;

	*f->ret = f->s.min.x <= f->r.min.x
		&& f->r.max.x <= f->s.max.x
		&& f->s.min.y <= f->r.min.y
		&& f->r.max.y <= f->s.max.y;
}

void
Rect_contains(void *fp)
{
	F_Rect_contains *f;
	WORD x, y;

	f = fp;

	x = f->p.x;
	y = f->p.y;
	*f->ret = x >= f->r.min.x && x < f->r.max.x
		&& y >= f->r.min.y && y < f->r.max.y;
}

void
Rect_addpt(void *fp)
{
	F_Rect_addpt *f;
	Draw_Rect *ret;
	WORD n;

	f = fp;

	ret = f->ret;
	n = f->p.x;
	ret->min.x = f->r.min.x + n;
	ret->max.x = f->r.max.x + n;
	n = f->p.y;
	ret->min.y = f->r.min.y + n;
	ret->max.y = f->r.max.y + n;
}

void
Rect_subpt(void *fp)
{
	WORD n;
	F_Rect_subpt *f;
	Draw_Rect *ret;

	f = fp;

	ret = f->ret;
	n = f->p.x;
	ret->min.x = f->r.min.x - n;
	ret->max.x = f->r.max.x - n;
	n = f->p.y;
	ret->min.y = f->r.min.y - n;
	ret->max.y = f->r.max.y - n;
}

void
Rect_inset(void *fp)
{
	WORD n;
	Draw_Rect *ret;
	F_Rect_inset *f;

	f = fp;

	ret = f->ret;
	n = f->n;
	ret->min.x = f->r.min.x + n;
	ret->min.y = f->r.min.y + n;
	ret->max.x = f->r.max.x - n;
	ret->max.y = f->r.max.y - n;
}

void
Rect_dx(void *fp)
{
	F_Rect_dx *f;

	f = fp;

	*f->ret = f->r.max.x-f->r.min.x;
}

void
Rect_dy(void *fp)
{
	F_Rect_dy *f;

	f = fp;

	*f->ret = f->r.max.y-f->r.min.y;
}

void
Rect_size(void *fp)
{
	F_Rect_size *f;
	Draw_Point *ret;

	f = fp;

	ret = f->ret;
	ret->x = f->r.max.x-f->r.min.x;
	ret->y = f->r.max.y-f->r.min.y;
}
