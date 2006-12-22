/*
 * Memory-mapped IO
 */

#define	PHYSPCIBRIDGE	0x80000000
#define	PHYSMMIO	0xEF600000
#define	MMIO(i)	(PHYSMMIO+(i)*0x100)
#define	PHYSGPT	MMIO(0)
#define	PHYSUART0	MMIO(3)
#define	PHYSUART1	MMIO(4)
#define	PHYSIIC	MMIO(5)
#define	PHYSOPB	MMIO(6)
#define	PHYSGPIO	MMIO(7)
#define	PHYSEMAC0	MMIO(8)
#define	PHYSEMAC1	MMIO(9)

#define	PHYSPCIIO0	0xE8000000	/* for 64M */
#define	PHYSPCIMEM	0x80000000
#define	PHYSPCIADDR	0xEEC00000	/* for 8 bytes */
#define	PHYSPCIDATA	0xEEC00004
#define	PHYSPCIACK	0xEED00000	/* interrupt acknowledge */
#define	PHYSPCIBCFG	0xEF400000	/* bridge configuration registers */
