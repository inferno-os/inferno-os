#include "lib9.h"
#include "draw.h"
#include "tk.h"

#define RGB(R,G,B) ((R<<24)|(G<<16)|(B<<8)|(0xff))

enum
{
	tkBackR		= 0xdd,		/* Background base color */
	tkBackG 	= 0xdd,
	tkBackB 	= 0xdd,

	tkSelectR	= 0xb0,		/* Check box selected color */
	tkSelectG	= 0x30,
	tkSelectB	= 0x60,

	tkSelectbgndR	= 0x40,		/* Selected item background */
	tkSelectbgndG	= 0x40,
	tkSelectbgndB	= 0x40
};

typedef struct Coltab Coltab;
struct Coltab {
	int	c;
	ulong rgba;
	int shade;
};

static Coltab coltab[] =
{
	TkCbackgnd,
		RGB(tkBackR, tkBackG, tkBackB),
		TkSameshade,
	TkCbackgndlght,
		RGB(tkBackR, tkBackG, tkBackB),
		TkLightshade,
	TkCbackgnddark,
		RGB(tkBackR, tkBackG, tkBackB),
		TkDarkshade,
	TkCactivebgnd,
		RGB(tkBackR+0x10, tkBackG+0x10, tkBackB+0x10),
		TkSameshade,
	TkCactivebgndlght,
		RGB(tkBackR+0x10, tkBackG+0x10, tkBackB+0x10),
		TkLightshade,
	TkCactivebgnddark,
		RGB(tkBackR+0x10, tkBackG+0x10, tkBackB+0x10),
		TkDarkshade,
	TkCactivefgnd,
		RGB(0, 0, 0),
		TkSameshade,
	TkCforegnd,
		RGB(0, 0, 0),
		TkSameshade,
	TkCselect,
		RGB(tkSelectR, tkSelectG, tkSelectB),
		TkSameshade,
	TkCselectbgnd,
		RGB(tkSelectbgndR, tkSelectbgndG, tkSelectbgndB),
		TkSameshade,
	TkCselectbgndlght,
		RGB(tkSelectbgndR, tkSelectbgndG, tkSelectbgndB),
		TkLightshade,
	TkCselectbgnddark,
		RGB(tkSelectbgndR, tkSelectbgndG, tkSelectbgndB),
		TkDarkshade,
	TkCselectfgnd,
		RGB(0xff, 0xff, 0xff),
		TkSameshade,
	TkCdisablefgnd,
		RGB(0x88, 0x88, 0x88),
		TkSameshade,
	TkChighlightfgnd,
		RGB(0, 0, 0),
		TkSameshade,
	TkCtransparent,
		DTransparent,
		TkSameshade,
	-1,
};

void
tksetenvcolours(TkEnv *env)
{
	Coltab *c;

	c = &coltab[0];
	while(c->c != -1) {
		env->colors[c->c] = tkrgbashade(c->rgba, c->shade);
		env->set |= (1<<c->c);
		c++;
	}
}
