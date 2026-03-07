#include "os.h"
#include <mp.h>
#include <libsec.h>
#if defined(__linux__)
#include <sys/random.h>
#endif

//
//  fill a buffer with cryptographically secure random bytes
//
void
prng(uchar *p, int n)
{
#if defined(__APPLE__)
	arc4random_buf(p, n);
#elif defined(__linux__)
	while(n > 0) {
		ssize_t r = getrandom(p, n, 0);
		if(r < 0) {
			if(errno == EINTR)
				continue;
			/* fallback to /dev/urandom */
			int fd = open("/dev/urandom", 0);
			if(fd >= 0) {
				read(fd, p, n);
				close(fd);
			}
			return;
		}
		p += r;
		n -= r;
	}
#else
	int fd;
	fd = open("/dev/urandom", 0);
	if(fd >= 0) {
		read(fd, p, n);
		close(fd);
	} else {
		/* last resort fallback */
		uchar *e;
		for(e = p+n; p < e; p++)
			*p = rand();
	}
#endif
}
