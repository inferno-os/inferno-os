#define	ARMAG	"<bigaf>\n"
#define	SARMAG	8

#define	ARFMAG	"`\n"

struct fl_hdr /* archive fixed length header - printable ascii */
{
	char	magic[SARMAG];	/* Archive file magic string */
	char	memoff[20];		/* Offset to member table */
	char	gstoff[20];		/* Offset to 32-bit global sym table */
	char	gst64off[20];	/* Offset to 64-bit global sym table */
	char	fstmoff[20];		/* Offset to first archive member */
	char	lstmoff[20];		/* Offset to last archive member */
	char	freeoff[20];		/* Offset to first mem on free list */
};
#define	SAR_FLHDR	(SARMAG+120)

struct ar_hdr /* archive file member header - printable ascii */
{
	char	size[20];	/* file member size - decimal */
	char	nxtmem[20];	/* pointer to next member -  decimal */
	char	prvmem[20];	/* pointer to previous member -  decimal */
	char	date[12];	/* file member date - decimal */
	char	uid[12];	/* file member user id - decimal */
	char	gid[12];	/* file member group id - decimal */
	char	mode[12];	/* file member mode - octal */
	char	namlen[4];	/* file member name length - decimal */
	/*      and variable length name follows*/
};
#define	SAR_HDR	112
