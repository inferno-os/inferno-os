/* there's a better way.  we should use it. */
#ifdef _STDDEF_H_
#define	__STDDEF_H
#endif
#ifdef _SYS_TYPES_H_
#define	__STDDEF_H
#endif
#ifdef _STDLIB_H_
#define	__STDDEF_H
#endif

#ifndef __STDDEF_H
#define __STDDEF_H	/* various */
#define _STDDEF_H_	/* FreeBSD */

#ifndef NULL
#define NULL 0
#endif

#ifndef _PTRDIFF_T
#define	_PTRDIFF_T
typedef long ptrdiff_t;
#endif
#undef _BSD_PTRDIFF_T
#ifndef _SIZE_T
#define _SIZE_T
typedef unsigned long size_t;
#endif
#undef _BSD_SIZE_T
#ifndef _WCHAR_T
#define _WCHAR_T
typedef unsigned short wchar_t;
#endif
#undef _BSD_WCHAR_T

#endif /* __STDDEF_H */
