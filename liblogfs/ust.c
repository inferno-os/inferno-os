#include "lib9.h"
#include "logfs.h"
#include "local.h"

enum {
	USTMOD = 127
};

typedef struct UstNode {
	char s[1];
} UstNode;

struct Ust {
	UstNode *head[USTMOD];
};

int
logfshashstring(void *s, int n)
{
	int h = 0;
	char *p;
	for(p = s; *p; p++) {
		ulong g;
		h = (h << 4) + *p;
		g = h & 0xf0000000;
		if(g != 0)
			h ^= ((g >> 24) & 0xff) | g;
	}
	return (h & ~(1 << 31)) % n;
}

static int
compare(char *entry, char *key)
{
	return strcmp(entry, key) == 0;
}

static int
allocsize(void *key)
{
	return strlen(key) + 1;
}

char *
logfsustnew(Ust **ustp)
{
	return logfsmapnew(USTMOD, logfshashstring, (int (*)(void *, void *))compare, allocsize, nil, ustp);
}

char *
logfsustadd(Ust *ust, char *s)
{
	char *errmsg;
	char *ep;
	ep = logfsmapfindentry(ust, s);
	if(ep) {
//		print("ust: found %s\n", s);
		return ep;
	}
	errmsg = logfsmapnewentry(ust, s, &ep);
	if(errmsg)
		return errmsg;
//	print("ust: new %s\n", s);
	return strcpy(ep, s);
}
