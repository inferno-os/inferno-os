#include "devfs-posix.c"

#include	<linux/hdreg.h>
#include	<linux/fs.h>
#include	<sys/ioctl.h>

static vlong
osdisksize(int fd)
{
	uvlong u64;
	long l;
	struct hd_geometry geo;
	
	memset(&geo, 0, sizeof geo);
	l = 0;
	u64 = 0;
#ifdef BLKGETSIZE64
	if(ioctl(fd, BLKGETSIZE64, &u64) >= 0)
		return u64;
#endif
	if(ioctl(fd, BLKGETSIZE, &l) >= 0)
		return l*512;
	if(ioctl(fd, HDIO_GETGEO, &geo) >= 0)
		return (vlong)geo.heads*geo.sectors*geo.cylinders*512;
	return 0;
}
