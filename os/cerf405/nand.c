#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

#include	"flashif.h"

/*
 * Cerf405-specific NAND flash interface
 */

#define	BE(n)	(1<<(31-(n)))	/* big-endian bit numbering */

enum {
	/* GPIO lines */
	Gpio_CLE_o_b=	31,
	Gpio_ALE_o_b=	30,
	Gpio_NCE_o_b=	24,	/* CE#, active low */
	Gpio_RDY_i_b=	23,

	/* bit masks */
	Gpio_CLE_o=	BE(Gpio_CLE_o_b),
	Gpio_ALE_o=	BE(Gpio_ALE_o_b),
	Gpio_NCE_o=	BE(Gpio_NCE_o_b),
	Gpio_RDY_i=	BE(Gpio_RDY_i_b),

	Gpio_NAND_o=	Gpio_CLE_o | Gpio_ALE_o | Gpio_NCE_o,

	CS_NAND=	1,
	Gpio_PerCS1_o=	BE(10),
};

void
archnand_init(Flash*)
{
	gpioreserve(Gpio_NAND_o | Gpio_RDY_i);
	gpioset(Gpio_NAND_o, Gpio_NCE_o);
	gpioconfig(Gpio_NAND_o, Gpio_out);
	gpioconfig(Gpio_RDY_i, Gpio_in);
}

void
archnand_claim(Flash*, int claim)
{
	gpioset(Gpio_NCE_o, claim? 0: Gpio_NCE_o);
}

void
archnand_setCLEandALE(Flash*, int cle, int ale)
{
	ulong v;

	v = 0;
	if(cle)
		v |= Gpio_CLE_o;
	if(ale)
		v |= Gpio_ALE_o;
	gpioset(Gpio_CLE_o | Gpio_ALE_o, v);
}

/*
 * could unroll the loops
 */

void
archnand_read(Flash *f, void *buf, int len)
{
	uchar *p, *bp;

	p = f->addr;
	if(buf != nil){
		bp = buf;
		while(--len >= 0)
			*bp++ = *p;
	}else{
		int junk;
		while(--len >= 0){
			junk = *p;
			USED(junk);
		}
	}
}

void
archnand_write(Flash *f, void *buf, int len)
{
	uchar *p, *bp;

	p = f->addr;
	bp = buf;
	while(--len >= 0)
		*p = *bp++;
}
