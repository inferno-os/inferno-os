#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

#include "dosfs.h"

static char *confname[MAXCONF];
static char *confval[MAXCONF];
static int nconf;

static	char*	defplan9ini =
	"ether0=type=CS8900\r\n"
	"vgasize=640x480x8\r\n"
	"kernelpercent=40\r\n"
	"console=1\r\nbaud=9600\r\n"
;

extern char **ini;

char*
getconf(char *name)
{
	int i;

	for(i = 0; i < nconf; i++)
		if(strcmp(confname[i], name) == 0)
			return confval[i];
	return 0;
}

/*
 *  read configuration file
 */
int
plan9ini(Dos *dos, char *val)
{
	Dosfile rc;
	int i, n;
	char *cp, *p, *q, *line[MAXCONF];

	cp = BOOTARGS;
	if(dos) {
		if(dosstat(dos, *ini, &rc) <= 0)
			return -1;

		*cp = 0;
		n = dosread(&rc, cp, BOOTARGSLEN-1);
		if(n <= 0)
			return -1;
		cp[n] = 0;
	} else if(val != nil){
		if(memchr(val, 0, BOOTARGSLEN-1) == nil)
			return -1;
		print("Using flash configuration\n");
		strcpy(cp, val);
		n = strlen(cp);
	}else{
		print("Using default configuration\n");
		strcpy(cp, defplan9ini);
		n = strlen(cp);
	}

	/*
	 * Make a working copy.
	 * We could change this to pass the parsed strings
	 * to the booted programme instead of the raw
	 * string, then it only gets done once.
	 */
	memmove(cp+BOOTARGSLEN, cp, n+1);
	cp += BOOTARGSLEN;

	/*
	 * Strip out '\r', change '\t' -> ' '.
	 */
	p = cp;
	for(q = cp; *q; q++){
		if(*q == '\r')
			continue;
		if(*q == '\t')
			*q = ' ';
		*p++ = *q;
	}
	*p = 0;
	n = getcfields(cp, line, MAXCONF, "\n");
	for(i = 0; i < n; i++){
		cp = strchr(line[i], '=');
		if(cp == 0)
			continue;
		*cp++ = 0;
		if(cp - line[i] >= NAMELEN+1)
			*(line[i]+NAMELEN-1) = 0;
		confname[nconf] = line[i];
		confval[nconf] = cp;
		nconf++;
	}
	return 0;
}

static int
parseether(uchar *to, char *from)
{
	char nip[4];
	char *p;
	int i;

	p = from;
	while(*p == ' ')
		++p;
	for(i = 0; i < 6; i++){
		if(*p == 0)
			return -1;
		nip[0] = *p++;
		if(*p == 0)
			return -1;
		nip[1] = *p++;
		nip[2] = 0;
		to[i] = strtoul(nip, 0, 16);
		if(*p == ':')
			p++;
	}
	return 0;
}

int
isaconfig(char *class, int ctlrno, ISAConf *isa)
{
	char cc[NAMELEN], *p, *q, *r;
	int n;

	sprint(cc, "%s%d", class, ctlrno);
	for(n = 0; n < nconf; n++){
		if(strncmp(confname[n], cc, NAMELEN))
			continue;
		isa->nopt = 0;
		p = confval[n];
		while(*p){
			while(*p == ' ' || *p == '\t')
				p++;
			if(*p == '\0')
				break;
			if(strncmp(p, "type=", 5) == 0){
				p += 5;
				for(q = isa->type; q < &isa->type[NAMELEN-1]; q++){
					if(*p == '\0' || *p == ' ' || *p == '\t')
						break;
					*q = *p++;
				}
				*q = '\0';
			}
			else if(strncmp(p, "port=", 5) == 0)
				isa->port = strtoul(p+5, &p, 0);
			else if(strncmp(p, "irq=", 4) == 0)
				isa->irq = strtoul(p+4, &p, 0);
			else if(strncmp(p, "mem=", 4) == 0)
				isa->mem = strtoul(p+4, &p, 0);
			else if(strncmp(p, "size=", 5) == 0)
				isa->size = strtoul(p+5, &p, 0);
			else if(strncmp(p, "ea=", 3) == 0){
				if(parseether(isa->ea, p+3) == -1)
					memset(isa->ea, 0, 6);
			}
			else if(isa->nopt < NISAOPT){
				r = isa->opt[isa->nopt];
				while(*p && *p != ' ' && *p != '\t'){
					*r++ = *p++;
					if(r-isa->opt[isa->nopt] >= ISAOPTLEN-1)
						break;
				}
				*r = '\0';
				isa->nopt++;
			}
			while(*p && *p != ' ' && *p != '\t')
				p++;
		}
		return 1;
	}
	return 0;
}
