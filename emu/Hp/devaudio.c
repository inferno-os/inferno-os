#include	"dat.h"
#include	"fns.h"
#include	"error.h"

#include	<sys/audio.h>


enum{
	Qdir,
	Qaudio,
	Qaudioctl,			/* deprecated */
	Qvolume,

	Fmono		= 1,
	Fin		= 2,
	Fout		= 4,
	Fhearn	= 8,

	Vaudio		= 0,
	Vsynth,
	Vcd,
	Vline,
	Vmic,
	Vspeaker,
	Vtreb,
	Vbass,
	Vspeed,
	Vbits,
	Vchans,
	Venc,
	Nvol,

	Epcm = 0,
	Eulaw,
	Ealaw,
	Nenc,

	Speed		= 44100,
	Ncmd		= 50,		/* max volume command words */
};
Dirtab audiotab[]={
	"audio",		{Qaudio, 0},	0,	0666,
	"audioctl",	{Qaudioctl, 0},	0,	0666,
	"volume",		{Qvolume, 0},	0,	0666,
};

typedef struct	Audiodev	Audiodev;

struct Audiodev {
	int		fd;
	int		swab;
	int		repl1;
	int		repl2;
};

static	struct
{
	QLock;				/* XXX maybe we should use this guy! */
	int	rivol[Nvol];		/* right/left input/output volumes */
	int	livol[Nvol];
	int	rovol[Nvol];
	int	lovol[Nvol];
} audio;

static	struct
{
	char*	name;
	int	flag;
	int	ilval;		/* initial values */
	int	irval;
} volumes[] =
{
/*[Vaudio]*/	"audio",	Fout, 		50,	50,
/*[Vsynth]*/	"synth",	Fin|Fout,	0,	0,
/*[Vcd]*/		"cd",		Fin|Fout,	0,	0,
/*[Vline]*/		"line",		Fin|Fout,	0,	0,
/*[Vmic]*/		"mic",		Fin|Fout|Fmono,	0,	0,
/*[Vspeaker]*/	"speaker",	Fout|Fmono,	0,	0,

/*[Vtreb]*/		"treb",		Fout, 		50,	50,
/*[Vbass]*/		"bass",		Fout, 		50,	50,

/*[Vspeed]*/	"speed",	Fin|Fout|Fmono,	Speed,	Speed,
/*[Vbits]*/	"bits",	Fin|Fout|Fmono|Fhearn,	16,	16,
/*[Vchans]*/	"chans",	Fin|Fout|Fmono|Fhearn,	2,	2,
/*[Venc]*/	"enc",	Fin|Fout|Fmono|Fhearn,	Epcm,	Epcm,
		0
};

static char *encname[] =
{
/*Epcm*/	"pcm",
/*Eulaw*/	"ulaw",
/*Ealaw*/	"alaw",
};

static char	Evolume[]	= "illegal volume specifier";

static void
resetlevel(void)
{
	int i;

	for(i=0; volumes[i].name; i++) {
		audio.lovol[i] = volumes[i].ilval;
		audio.rovol[i] = volumes[i].irval;
		audio.livol[i] = volumes[i].ilval;
		audio.rivol[i] = volumes[i].irval;
	}
}

/* Start OS-dependant code */
static int
doioctl(int fd, int whim, void *data, char *what)
{
	char ebuf[ERRMAX];
	int r, n;

	osenter();
	r = ioctl(fd, whim, data);
	osleave();
	if (r < 0) {
		n = snprint(ebuf, ERRMAX, "ioctl %s: ", what);
		oserrstr(ebuf+n, sizeof ebuf-n);
		error(ebuf);
	}
	return r;
}

static void
setlevels(Audiodev *a)
{
	struct audio_describe au;
	struct audio_gain gain;
	int i, x;

/* XXX todo: simulate it with a data conversion routine (could also do swab...) */
	if (audio.lovol[Venc] == Epcm && audio.lovol[Vbits] != 16) {
		audio.lovol[Vbits] = 16;
		error("pcm must be 16 bits");
	}
	if (audio.lovol[Vchans] != 1 && audio.lovol[Vchans] != 2) {
		audio.lovol[Vchans] = 1;
		error("bad number of channels");
	}

	doioctl(a->fd, AUDIO_DESCRIBE, &au, "describe");
	doioctl(a->fd, AUDIO_SET_SAMPLE_RATE, audio.lovol[Vspeed], "rate");	/* what if input != output??? */
	doioctl(a->fd, AUDIO_SET_CHANNELS, audio.lovol[Vchans], "channels");

	switch (audio.lovol[Venc]) {
	default:
	case Epcm:
		x = AUDIO_FORMAT_LINEAR16BIT;
		break;
	case Eulaw:
		x = AUDIO_FORMAT_ULAW;
		break;
	case Ealaw:
		x = AUDIO_FORMAT_ALAW;
		break;
	}
	doioctl(a->fd, AUDIO_SET_DATA_FORMAT, x, "set format");

	x = 0;
	if (audio.lovol[Vspeaker] != 0 || audio.rovol[Vspeaker] != 0)
		x |= AUDIO_OUT_SPEAKER;
	if (audio.lovol[Vaudio] != 0 || audio.rovol[Vaudio] != 0)
		x |= AUDIO_OUT_HEADPHONE;
	if (audio.lovol[Vline] != 0 || audio.rovol[Vline] != 0)
		x |= AUDIO_OUT_LINE;
	doioctl(a->fd, AUDIO_SET_OUTPUT, x, "set output");

	x = 0;
	if (audio.livol[Vline] != 0 || audio.rivol[Vline] != 0)
		x |= AUDIO_IN_LINE;
	if (audio.livol[Vmic] != 0 || audio.rivol[Vmic] != 0 || x == 0)	/* must set at least one */
		x |= AUDIO_IN_MIKE;
	doioctl(a->fd, AUDIO_SET_INPUT, x, "set input");

/* XXX todo: get the gains right.  should scale 0-100 into min-max (as in struct audio_describe au) */
/*	doioctl(a->fd, AUDIO_GET_GAINS, &gain, "get gains"); */
	gain.channel_mask = AUDIO_CHANNEL_LEFT|AUDIO_CHANNEL_RIGHT;
	for (i = 0; i < 2; i++) {
		gain.cgain[i].receive_gain = au.min_receive_gain;
		gain.cgain[i].monitor_gain = au.min_monitor_gain;
		gain.cgain[i].transmit_gain = au.max_transmit_gain;
	}
	doioctl(a->fd, AUDIO_SET_GAINS, &gain, "set gains");
}

static char *
audiofname(int isctl)
{
	if (isctl)
		return "/dev/audioCtl";
	else
		return "/dev/audio";
}

static void
audioswab(uchar *p, int n)
{
	int x;

	/* XXX slow; should check for 16bit mode; should be combined with format conversion; etc */
	while (n >= 2) {
		x = p[0];
		p[0] = p[1];
		p[1] = x;
		p +=2;
		n -=2;
	}
}
/* End OS-dependant code */

static void
audioinit(void)
{
	resetlevel();
}

static Chan*
audioattach(char* spec)
{
	return devattach('A', spec);
}

static int
audiowalk(Chan* c, char* name)
{
	return devwalk(c, name, audiotab, nelem(audiotab), devgen);
}

static void
audiostat(Chan* c, char* db)
{
	devstat(c, db, audiotab, nelem(audiotab), devgen);
}

static Chan*
audioopen(Chan *c, int omode)
{
	Audiodev *a;
	long path;
	char ebuf[ERRMAX];

	path = c->qid.path & ~CHDIR;
	if (path != Qdir){
/* XXX Irix portability?  (multiple opens -- how to match ctl with data???) */
		a = malloc(sizeof(Audiodev));
		if(a == nil)
			error(Enomem);
		if (waserror()) {
			free(a);
			nexterror();
		}
		a->fd = open(audiofname(path != Qaudio), omode&7);
		if(a->fd < 0)
			oserror();
		if (path == Qaudio)
			setlevels(a);
		c->aux = a;
		poperror();
	}
	return devopen(c, omode, audiotab, nelem(audiotab), devgen);
}

static void
audioclose(Chan* c)
{
	Audiodev *a;

	a = c->aux;
	if (a != nil) {
		close(a->fd);
		free(a);
	}
}

static long
audioread(Chan* c, void *ua, long n, vlong offset)
{
	Audiodev *a;
	char buf[300], ebuf[ERRMAX];
	int liv, riv, lov, rov;
	int j, m;
	long path;

	a = c->aux;
	path = (c->qid.path & ~CHDIR);
	switch(path){
	case Qdir:
		return devdirread(c, a, n, audiotab, nelem(audiotab), devgen);
	case Qaudio:
		osenter();
		n = read(a->fd, ua, n);
		osleave();
		if (n < 0)
			oserror();
		audioswab(ua, n);		/* XXX what if n is odd?  also, only if 16 bit... must fix portability */
		break;
	case Qaudioctl:
	case Qvolume:
		j = 0;
		buf[0] = 0;
		for(m=0; volumes[m].name; m++){
			if ((volumes[m].flag & Fhearn) && path == Qvolume)
				continue;
			liv = audio.livol[m];
			riv = audio.rivol[m];
			lov = audio.lovol[m];
			rov = audio.rovol[m];
			j += snprint(buf+j, sizeof(buf)-j, "%s", volumes[m].name);
			if(m == Venc)
				j += snprint(buf+j, sizeof(buf)-j, " %s", encname[lov]);
			else if((volumes[m].flag & Fmono) || liv==riv && lov==rov){
				if((volumes[m].flag&(Fin|Fout))==(Fin|Fout) && liv==lov)
					j += snprint(buf+j, sizeof(buf)-j, " %d", liv);
				else{
					if(volumes[m].flag & Fin)
						j += snprint(buf+j, sizeof(buf)-j, " in %d", liv);
					if(volumes[m].flag & Fout)
						j += snprint(buf+j, sizeof(buf)-j, " out %d", lov);
				}
			}else{
				if((volumes[m].flag&(Fin|Fout))==(Fin|Fout) && liv==lov && riv==rov)
					j += snprint(buf+j, sizeof(buf)-j, " left %d right %d",
						liv, riv);
				else{
					if(volumes[m].flag & Fin)
						j += snprint(buf+j, sizeof(buf)-j, " in left %d right %d",
							liv, riv);
					if(volumes[m].flag & Fout)
						j += snprint(buf+j, sizeof(buf)-j, " out left %d right %d",
							lov, rov);
				}
			}
			j += snprint(buf+j, sizeof(buf)-j, "\n");
		}
		return readstr(offset, ua, n, buf);
	default:
		n=0;
		break;
	}
	return n;
}

static long
audiowrite(Chan* c, char *ua, long n, vlong offset)
{
	Audiodev *a;
	long m, n0;
	int i, nf, v, left, right, in, out;
	char buf[255], *field[Ncmd], ebuf[ERRMAX], *p;

	a = c->aux;
	switch(c->qid.path & ~CHDIR){
	case Qaudio:
		n &= ~1;
		audioswab(ua, n);		/* XXX VERY BAD BUG; THIS CHANGES THE CALLER'S DATA */
		osenter();
		n = write(a->fd, ua, n);
		osleave();
		if (n < 0)
			oserror();
		break;
	case Qaudioctl:
	case Qvolume:
		v = Vaudio;
		left = 1;
		right = 1;
		in = 1;
		out = 1;
		if(n > sizeof(buf)-1)
			n = sizeof(buf)-1;
		memmove(buf, ua, n);
		buf[n] = '\0';

		nf = getfields(buf, field, Ncmd, 1, " \t\n");
		for(i = 0; i < nf; i++){
			/*
			 * a number is volume
			 */
			if(field[i][0] >= '0' && field[i][0] <= '9') {
				m = strtoul(field[i], &p, 10);
				if (p != nil && *p == 'k')
					m *= 1000;
				if(left && out)
					audio.lovol[v] = m;
				if(left && in)
					audio.livol[v] = m;
				if(right && out)
					audio.rovol[v] = m;
				if(right && in)
					audio.rivol[v] = m;
				setlevels(a);
				goto cont0;
			}

			for(m=0; volumes[m].name; m++) {
				if(strcmp(field[i], volumes[m].name) == 0) {
					v = m;
					in = 1;
					out = 1;
					left = 1;
					right = 1;
					goto cont0;
				}
			}

			if(strcmp(field[i], "reset") == 0) {
				resetlevel();
				setlevels(a);
				goto cont0;
			}
			if(strcmp(field[i], "in") == 0) {
				in = 1;
				out = 0;
				goto cont0;
			}
			if(strcmp(field[i], "out") == 0) {
				in = 0;
				out = 1;
				goto cont0;
			}
			if(strcmp(field[i], "left") == 0) {
				left = 1;
				right = 0;
				goto cont0;
			}
			if(strcmp(field[i], "right") == 0) {
				left = 0;
				right = 1;
				goto cont0;
			}
			if(strcmp(field[i], "rate") == 0) {
				v = Vspeed;
				in = 1;
				out = 1;
				left = 1;
				right = 1;
				goto cont0;
			}
			if(strcmp(field[i], "chan") == 0) {	/* XXX egregious backward compatibility hack */
				v = Vchans;
				in = 1;
				out = 1;
				left = 1;
				right = 1;
				goto cont0;
			}
			if(v == Venc) {
				if (strcmp(field[i], "pcm") == 0) {
					audio.lovol[v] = Epcm;
					goto cont0;
				}
				if (strcmp(field[i], "ulaw") == 0) {
					audio.lovol[v] = Eulaw;
					goto cont0;
				}
				if (strcmp(field[i], "alaw") == 0) {
					audio.lovol[v] = Ealaw;
					goto cont0;
				}
			}
			if(v == Vchans) {
				if (strcmp(field[i], "mono") == 0) {
					audio.lovol[v] = 1;
					goto cont0;
				}
				if (strcmp(field[i], "stereo") == 0) {
					audio.lovol[v] = 2;
					goto cont0;
				}
			}
			error(Evolume);
			break;
		cont0:;
		}
		break;
	default:
		error(Ebadusefd);
	}
	return n;
}

Dev audiodevtab = {
	'A',
	"audio",

	audioinit,
	audioattach,
	devclone,
	audiowalk,
	audiostat,
	audioopen,
	devcreate,
	audioclose,
	audioread,
	devbread,
	audiowrite,
	devbwrite,
	devremove,
	devwstat,
};
