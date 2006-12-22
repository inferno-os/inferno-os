#include <lib9.h>
#include <draw.h>
#include <interp.h>
#include <isa.h>
#include "../libinterp/runt.h"
#include <drawif.h>
#include <prefab.h>

static
PElement*
iconelement1(Prefab_Environ *e, Draw_Rect r, Draw_Image *icon, Draw_Image *mask, enum Elementtype kind)
{
	PElement *pelem;
	Prefab_Element *elem;

	if(badenviron(e, 0) || icon==H || mask==H)
		return H;
	pelem = mkelement(e, kind);
	if(pelem == H)
		return H;
	elem = &pelem->e;

	if(Dx(r))
		elem->r = r;
	else{
		elem->r.min = r.min;
		elem->r.max.x = r.min.x + Dx(icon->r);
		elem->r.max.y = r.min.y + Dy(icon->r);
	}
	elem->mask = mask;
	D2H(mask)->ref++;
	elem->image = icon;
	D2H(icon)->ref++;
	pelem->drawpt = IPOINT(r.min);
	pelem->nkids = 1;
	pelem->pkind = kind;
	return pelem;
}

PElement*
iconelement(Prefab_Environ *e, Draw_Rect r, Draw_Image *icon, Draw_Image *mask)
{
	return iconelement1(e, r, icon, mask, EIcon);
}

PElement*
separatorelement(Prefab_Environ *e, Draw_Rect r, Draw_Image *icon, Draw_Image *mask)
{
	return iconelement1(e, r, icon, mask, ESeparator);
}
