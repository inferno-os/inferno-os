#include <u.h>
typedef usize size_t;

#define	Rendez	xRendez
#include <libc.h>
#undef Rendez


/*
 *	Extensions for Inferno to basic libc.h
 */

#define	setbinmode()
#define	USE_FPdbleword
