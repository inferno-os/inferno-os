#include <lib9.h>

static void
usage(void)
{
	fprint(2, "usage: mkdir [-p] dir ...\n");
	exits("usage");
}

static int
mkdirp(char *s, int pflag)
{
	char *p;

	if(!pflag) {
		if(access(s, 0) == 0){
			fprint(2, "mkdir: %s already exists\n", s);
			exits("exists");
		}
		return mkdir(s);
	}

	/* create intermediate directories */
	p = strchr(s+1, '/');
	while(p != nil) {
		*p = '\0';
		if(access(s, 0) != 0 && mkdir(s) != 0)
			return -1;
		*p = '/';
		p = strchr(p+1, '/');
	}

	/* create final directory */
	if(access(s, 0) == 0)
		return 0;
	return mkdir(s);
}

void
main(int argc, char **argv)
{
	int pflag;

	pflag = 0;
	ARGBEGIN{
	case 'p':
		pflag++;
		break;
	default:
		usage();
	}ARGEND
	for(; *argv; argv++){
		if(mkdirp(*argv, pflag) < 0){
			fprint(2, "mkdir: can't create %s\n", *argv);
			perror(0);
			exits("error");
		}
	}
	exits(0);
}
