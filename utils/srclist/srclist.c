#include <lib9.h>
#include <bio.h>
#include <mach.h>

int	conly;
int	exists;

enum {
	Maxroot = 10,
};

int	nroot;
char	*root[Maxroot];
int	rootlen[Maxroot];

void	usage(void);
void	error(char *);
void	addroot(char *);
void	addroots(char *);
void	chomp(char *);

extern char	*mygetwd(char*, int);

void
main(int argc, char **argv)
{
	char buf[1024], *cwd;

	cwd = mygetwd(buf, sizeof(buf));
	ARGBEGIN {
	case 'c':
		conly = 1;
		break;
	case 'e':
		exists = 1;
		break;
	case 'r':
		addroots(EARGF(usage()));
		break;
	default:
		usage();
	} ARGEND

	if(argc != 1)
		usage();

	if(cwd != nil)
		chdir(cwd);
	setbinmode();
	chomp(argv[0]);

	exits(0);
}

void
addroot(char *x)
{
	if(nroot >= Maxroot){
		fprint(2, "srclist: too many root directories\n");
		exits("usage");
	}
	root[nroot] = x;
	rootlen[nroot] = strlen(x);
	nroot++;
}

void
addrootnt(char *r)
{
	addroot(r);
	if(r[1] != ':')
		return;	/* phew! */
	if(*r >= 'a' && *r <= 'z' || *r >= 'A' && *r <= 'Z')
		addroot(r+2);
}

void
addroots(char *r)
{
	char buf[1024], *r2;

	addrootnt(r);
	if(chdir(r) < 0)
		return;
	r2 = mygetwd(buf, sizeof(buf));
	if(r2 && strcmp(r2, r) != 0)
		addrootnt(r2);
}

void
chomp(char *file)
{
	int fd, i, j, len;
	Fhdr fhdr;
	Dir *td;
	char fname[1024];

	fd = open(file, OREAD);
	if(fd < 0)
		error("open");

	if(crackhdr(fd, &fhdr) == 0)
		error("crackhdr");

	if(syminit(fd, &fhdr) < 0)
		error("syminit");

	for(i = 0; i < 1000; i++)
		if(filesym(i, fname, sizeof(fname)-1)){
			cleanname(fname);
			if(conly){
				len = strlen(fname);
				if(len < 2 || strcmp(fname+len-2, ".c") != 0)
					continue;
			}
			if(exists){
				if((td = dirstat(fname)) == nil)
					continue;
				free(td);
			}
			if(nroot){
				for(j = 0; j < nroot; j++)
					if(strncmp(fname, root[j], rootlen[j]) == 0)
						break;
				if(j == nroot)
					continue;
			}
			print("%s\n", fname);
		}
}

void
usage(void)
{
	fprint(2, "usage: srclist [-ce] [-r root] <objfile>\n");
	exits("usage");
}

void
error(char *s)
{
	fprint(2, "srclist: %s: %r\n", s);
	exits(s);
}
