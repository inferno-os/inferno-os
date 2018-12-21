#include	"mk.h"
#include	<ar.h>

static int dolong;

static void atimes(char *);
static char *split(char*, char**);

long
atimeof(int force, char *name)
{
	Symtab *sym;
	long t;
	char *archive, *member, buf[512];

	archive = split(name, &member);
	if(archive == 0)
		Exit();

	t = mtime(archive);
	sym = symlook(archive, S_AGG, 0);
	if(sym){
		if(force || (t > (long)sym->value)){
			atimes(archive);
			sym->value = (void *)t;
		}
	}
	else{
		atimes(archive);
		/* mark the aggegate as having been done */
		symlook(strdup(archive), S_AGG, "")->value = (void *)t;
	}
	snprint(buf, sizeof(buf), "%s(%s)", archive, member);
	sym = symlook(buf, S_TIME, 0);
	if (sym)
		return (long)sym->value;	/* uggh */
	return 0;
}

void
atouch(char *name)
{
	char *archive, *member;
	int fd, i, namelen;
	struct fl_hdr g;
	struct ar_hdr h;
	long t;
	char memname[256];

	archive = split(name, &member);
	if(archive == 0)
		Exit();

	fd = open(archive, ORDWR);
	if(fd < 0){
		fd = create(archive, OWRITE, 0666);
		if(fd < 0){
			perror(archive);
			Exit();
		}
		write(fd, ARMAG, SARMAG);
		for(i = 0; i < 6; i++)
			fprint(fd, "%-20ld", 0);
	}
	if(symlook(name, S_TIME, 0)){
		/* hoon off and change it in situ */
		LSEEK(fd, 0, 0);
		if(read(fd, &g, SAR_FLHDR) != SAR_FLHDR){
			close(fd);
			return;
		}
		t = atol(g.fstmoff);
		if(t == 0){
			close(fd);
			return;
		}
		for(;;){
			LSEEK(fd, t, 0);
			if(read(fd, (char *)&h, SAR_HDR) != SAR_HDR)
				break;

			namelen = atol(h.namlen);
			if(namelen == 0 || namelen >= sizeof memname){
				namelen = 0;
				goto skip;
			}
			if(read(fd, memname, namelen) != namelen)
				break;
			memname[namelen] = 0;

			if(strcmp(member, memname) == 0){
				snprint(h.date, sizeof(h.date), "%-12ld", time(0));
				LSEEK(fd, t, 0);
				write(fd, (char *)&h, SAR_HDR);
				break;
			}
		skip:
			t = atol(h.nxtmem);
			if(t == 0)
				break;
		}
	}
	close(fd);
}

static void
atimes(char *ar)
{
	struct fl_hdr g;
	struct ar_hdr h;
	long o, t;
	int fd, i, namelen;
	char buf[2048], *p, *strings;
	char name[1024];
	Symtab *sym;

	strings = nil;
	fd = open(ar, OREAD);
	if(fd < 0)
		return;

	if(read(fd, &g, SAR_FLHDR) != SAR_FLHDR){
		close(fd);
		return;
	}
	o = atol(g.fstmoff);
	if(o == 0){
		close(fd);
		return;
	}
	for(;;){
		LSEEK(fd, o, 0);
		if(read(fd, (char *)&h, SAR_HDR) != SAR_HDR)
			break;

		t = atol(h.date);
		if(t == 0)	/* as it sometimes happens; thanks ken */
			t = 1;

		namelen = atol(h.namlen);
		if(namelen == 0 || namelen >= sizeof name){
			namelen = 0;
			goto skip;
		}
		if(read(fd, name, namelen) != namelen)
			break;
		name[namelen] = 0;

		snprint(buf, sizeof buf, "%s(%s)", ar, name);
		sym = symlook(strdup(buf), S_TIME, (void *)t);
		sym->value = (void *)t;
	skip:
		o = atol(h.nxtmem);
		if(o == 0)
			break;
	}
	close(fd);
	free(strings);
}

static int
type(char *file)
{
	int fd;
	char buf[SARMAG];

	fd = open(file, OREAD);
	if(fd < 0){
		if(symlook(file, S_BITCH, 0) == 0){
			Bprint(&bout, "%s doesn't exist: assuming it will be an archive\n", file);
			symlook(file, S_BITCH, (void *)file);
		}
		return 1;
	}
	if(read(fd, buf, SARMAG) != SARMAG){
		close(fd);
		return 0;
	}
	close(fd);
	return strncmp(ARMAG, buf, SARMAG) == 0;
}

static char*
split(char *name, char **member)
{
	char *p, *q;

	p = strdup(name);
	q = utfrune(p, '(');
	if(q){
		*q++ = 0;
		if(member)
			*member = q;
		q = utfrune(q, ')');
		if (q)
			*q = 0;
		if(type(p))
			return p;
		free(p);
		fprint(2, "mk: '%s' is not an archive\n", name);
	}
	return 0;
}
