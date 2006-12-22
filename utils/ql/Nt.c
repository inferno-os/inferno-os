#include <windows.h>

/*
 *	We can't include l.h, because Windoze wants to use some names
 *	like FLOAT and ABC which we declare.  Define what we need here.
 */
typedef	unsigned char	uchar;
typedef	unsigned int	uint;
typedef	unsigned long	ulong;

extern char	*hunk;
extern long	nhunk;

void	gethunk(void);

/*
 * fake malloc
 */
void*
malloc(uint n)
{
	void *p;

	while(n & 7)
		n++;
	while(nhunk < n)
		gethunk();
	p = hunk;
	nhunk -= n;
	hunk += n;
	return p;
}

void
free(void *p)
{
}

void*
calloc(uint m, uint n)
{
	void *p;

	n *= m;
	p = malloc(n);
	memset(p, 0, n);
	return p;
}

void*
realloc(void *p, uint n)
{
	void *new;

	new = malloc(n);
	if(new && p)
		memmove(new, p, n);
	return new;
}

#define	Chunk	(1*1024*1024)

void*
mysbrk(ulong size)
{
	void *v;
	static int chunk;
	static uchar *brk;

	if(chunk < size) {
		chunk = Chunk;
		if(chunk < size)
			chunk = Chunk + size;
		brk = VirtualAlloc(NULL, chunk, MEM_COMMIT, PAGE_EXECUTE_READWRITE); 	
		if(brk == 0)
			return (void*)-1;
	}
	v = brk;
	chunk -= size;
	brk += size;
	return v;
}

double
cputime(void)
{
	return ((double)0);
}
