#include <lib9.h>

void
main(int argc, char **argv)
{
	for(argv++; *argv; argv++){
		if(access(*argv, 0) == 0){
			fprint(2, "mkdir: %s already exists\n", *argv);
			exits("exists");
		}
		if(mkdir(*argv) < 0){
			fprint(2, "mkdir: can't create %s\n", *argv);
			perror(0);
			exits("error");
		}
	}
	exits(0);
}
