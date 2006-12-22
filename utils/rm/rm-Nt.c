#include <lib9.h>
#include <windows.h>

typedef struct	Direntry
{
	int	isdir;
	char	*name;
} Direntry;

char	errbuf[ERRMAX];
long	ndirbuf = 0;
int	ignerr = 0;

void
err(char *f)
{
	if(!ignerr){
		errstr(errbuf, sizeof errbuf);
		fprint(2, "rm: %s: %s\n", f, errbuf);
	}
}

int
badentry(char *filename)
{
	if(*filename == 0)
		return 1;
	if(filename[0] == '.'){
		if(filename[1] == 0)
			return 1;
		if(filename[1] == '.' && filename[2] == 0)
			return 1;
	}
	return 0;
}

/*
 * Read a whole directory before removing anything as the holes formed
 * by removing affect the read offset.
 */
Direntry*
readdirect(char *path)
{
	long n;
	HANDLE h;
	Direntry *d;
	char fullpath[MAX_PATH];
	WIN32_FIND_DATA data;

	snprint(fullpath, MAX_PATH, "%s\\*.*", path);
	h = FindFirstFile(fullpath, &data);
	if(h == INVALID_HANDLE_VALUE)
		err(path);

	n = 0;
	d = 0;
	for(;;){
		if(!badentry(data.cFileName)){
			d = realloc(d, (n+2)*sizeof(Direntry));
			if(d == 0){
				err("memory allocation");
				exits(errbuf);
			}
			d[n].name = malloc(strlen(data.cFileName)+1);
			if(d[n].name == 0){
				err("memory allocation");
				exits(errbuf);
			}
			strcpy(d[n].name, data.cFileName);
			if(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
				d[n].isdir = 1;
			else
				d[n].isdir = 0;
			n++;
		}
		if(FindNextFile(h, &data) == 0)
			break;
	}
	FindClose(h);
	if(d){
		d[n].name = 0;
		d[n].isdir = 0;
	}
	return d;
}

/*
 * f is a non-empty directory. Remove its contents and then it.
 */
void
Ntrmdir(char *f)
{
	Direntry *dp, *dq;
	char name[MAX_PATH];

	dq = readdirect(f);

	if(dq == 0)
		return;

	for(dp = dq; dp->name; dp++){
		snprint(name, MAX_PATH, "%s/%s", f, dp->name);
		if(remove(name) == -1){
			if(dp->isdir == 0)
				err(name);
			else
			if(RemoveDirectory(name) == 0)
				Ntrmdir(name);
		}
		free(dp->name);
	}
	if(RemoveDirectory(f) == 0)
		err(f);
	free(dq);
}

void
main(int argc, char *argv[])
{
	int i;
	int recurse;
	char *f;
	Dir *db;

	ignerr = 0;
	recurse = 0;
	ARGBEGIN{
	case 'r':
		recurse = 1;
		break;
	case 'f':
		ignerr = 1;
		break;
	default:
		fprint(2, "usage: rm [-fr] file ...\n");
		exits("usage");
	}ARGEND
	for(i=0; i<argc; i++){
		f = argv[i];
		if(remove(f) != -1)
			continue;
		if((db = dirstat(f)) == nil || (db->qid.type&QTDIR) ==0)
			err(f);
		else if(RemoveDirectory(f) == 0)
			if(recurse)
				Ntrmdir(f);
			else
				err(f);
	}
	exits(errbuf);
}
