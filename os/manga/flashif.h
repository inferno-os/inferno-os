typedef struct Flash Flash;

/*
 * structure defining a flash memory card
 */
struct Flash {
	QLock;	/* interlock on flash operations */
	Flash*	next;

	/* the following are filled in by devflash before Flash.reset called */
	char*	name;
	void*	addr;
	ulong	size;
	void *	archdata;
	int	(*reset)(Flash*);

	/* the following are filled in by the reset routine */
	int	(*eraseall)(Flash*);
	int	(*erasezone)(Flash*, int);
	int	(*read)(Flash*, ulong, void*, long);	/* reads of correct width and alignment */
	int	(*write)(Flash*, ulong, void*, long);	/* writes of correct width and alignment */
	int	(*suspend)(Flash*);
	int	(*resume)(Flash*);
	int	(*attach)(Flash*);

	uchar	id;	/* flash manufacturer ID */
	uchar	devid;	/* flash device ID */
	int	width;	/* bytes per flash line */
	int	erasesize;	/* size of erasable unit (accounting for width) */
	void*	data;		/* flash type routines' private storage, or nil */
	ulong	unusable;	/* bit mask of unusable sections */
};

/*
 * called by link routine of driver for specific flash type: arguments are
 * conventional name for card type/model, and card driver's reset routine.
 */
void	addflashcard(char*, int (*)(Flash*));

/*
 * called by devflash.c:/^flashreset; if flash exists,
 * sets type, address, and size in bytes of flash
 * and returns 0; returns -1 if flash doesn't exist
 */
int	archflashreset(int instance, char*, int, void**, long*, void **archdata);

int	archflash12v(int);
void	archflashwp(void *archdata, int);

/*
 * Architecture specific routines for managing nand devices
 */

/*
 * do any device spcific initialisation
 */
void archnand_init(void *archdata);

/*
 * if claim is 1, claim device exclusively, and enable it (power it up)
 * if claim is 0, release, and disable it (power it down)
 * claiming may be as simple as a qlock per device
 */
void archnand_claim(void *archdata, int claim);

/*
 * set command latch enable (CLE) and address latch enable (ALE)
 * appropriately
 */
void archnand_setCLEandALE(void *archdata, int cle, int ale);

/*
 * write a sequence of bytes to the device
 */
void archnand_write(void *archdata, void *buf, int len);

/*
 * read a sequence of bytes from the device
 * if buf is 0, throw away the data
 */
void archnand_read(void *archdata, void *buf, int len);

