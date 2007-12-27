#include "dat.h"
#include "fns.h"
#include "error.h"
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/filio.h>
#include "audio.h"
#include <sys/soundcard.h>

#define 	Audio_Mic_Val		SOUND_MIXER_MIC
#define 	Audio_Linein_Val	SOUND_MIXER_LINE

#define	Audio_Speaker_Val	SOUND_MIXER_SPEAKER
#define	Audio_Headphone_Val	SOUND_MIXER_PHONEOUT
#define	Audio_Lineout_Val	SOUND_MIXER_VOLUME

#define 	Audio_Pcm_Val		AFMT_S16_LE
#define 	Audio_Ulaw_Val		AFMT_MU_LAW
#define 	Audio_Alaw_Val		AFMT_A_LAW

#include "audio-tbls.c"

#define	min(a,b)	((a) < (b) ? (a) : (b))
static int debug;

#define AUDIO_FILE_STRING	"/dev/dsp"

enum {
	A_Pause,
	A_UnPause
};

enum {
	A_In,
	A_Out
};

static QLock inlock;
static QLock outlock;

static	int	audio_file  = -1;	/* file in/out */
static	int	audio_file_in  = -1;	/* copy of above when opened O_READ/O_RDWR */
static	int	audio_file_out  = -1;	/* copy of above when opened O_WRITE/O_RDWR */

static	int	audio_swap_flag = 0;	/* endian swap */

static	int	audio_in_pause = A_UnPause;

static Audio_t av;
static int mixerleftvol[32];
static int mixerrightvol[32];

static int audio_enforce(Audio_t*);
static int audio_open(void);
static int audio_pause_in(int, int);
static int audio_flush(int, int);
static int audio_pause_out(int);
static int audio_set_blocking(int);
static int audio_set_info(int, Audio_d*, int);
static void audio_swap_endian(char*, int);

void
audio_file_init(void)
{
	int i;
	static ushort flag = 1;

	audio_swap_flag = *((uchar*)&flag) == 0;	/* big-endian? */
	audio_info_init(&av);
	for (i = 0; i < 32; i++)
		mixerleftvol[i] = mixerrightvol[i] = 100;
}

void
audio_ctl_init(void)
{
}

void
audio_file_open(Chan *c, int omode)
{
	char ebuf[ERRMAX];

	if (debug)
		print("audio_file_open(0x%.8lux, %d)\n", c, omode);
	switch(omode){
	case OREAD:
		qlock(&inlock);
		if(waserror()){
			qunlock(&inlock);
			nexterror();
		}

		if(audio_file_in >= 0)
			error(Einuse);
		if (audio_file < 0)
			audio_file = audio_open();
		audio_file_in = audio_file;
		poperror();
		qunlock(&inlock);
		break;
	case OWRITE:
		qlock(&outlock);
		if(waserror()){
			qunlock(&outlock);
			nexterror();
		}
		if(audio_file_out >= 0)
			error(Einuse);
		if (audio_file < 0)
			audio_file = audio_open();
		audio_file_out = audio_file;
		poperror();
		qunlock(&outlock);
		break;
	case ORDWR:
		qlock(&inlock);
		qlock(&outlock);
		if(waserror()){
			qunlock(&outlock);
			qunlock(&inlock);
			nexterror();
		}
		if(audio_file_in >= 0 || audio_file_out >= 0)
			error(Einuse);
		if (audio_file < 0)
			audio_file = audio_open();
		audio_file_in = audio_file_out = audio_file;
		poperror();
		qunlock(&outlock);
		qunlock(&inlock);
		break;
	}
	if (debug)
		print("audio_file_open: success\nin %d out %d both %d\n",
			audio_file_out, audio_file_in, audio_file);
}

void
audio_ctl_open(Chan *c, int omode)
{
	USED(c);
	USED(omode);
}

void
audio_file_close(Chan *c)
{
	switch(c->mode){
	case OREAD:
		qlock(&inlock);
		qlock(&outlock);
		if (audio_file_out < 0) {
			close(audio_file);
			audio_file = -1;
		}
		qunlock(&outlock);
		audio_file_in = -1;
		qunlock(&inlock);
		break;
	case OWRITE:
		qlock(&inlock);
		qlock(&outlock);
		if (audio_file_in < 0) {
			close(audio_file);
			audio_file = -1;
		}
		audio_file_out = -1;
		qunlock(&outlock);
		qunlock(&inlock);
		break;
	case ORDWR:
		qlock(&inlock);
		qlock(&outlock);
		close(audio_file);
		audio_file_in = audio_file_out = audio_file = -1;
		qunlock(&outlock);
		qunlock(&inlock);
		break;
	}
}

void
audio_ctl_close(Chan *c)
{
}

long
audio_file_read(Chan *c, void *va, long count, vlong offset)
{
	struct  timespec time;
	long ba, status, chunk, total;
	char *pva = (char *) va;

	qlock(&inlock);
	if(waserror()){
		qunlock(&inlock);
		nexterror();
	}

	if(audio_file_in < 0)
		error(Eperm);

	/* check block alignment */
	ba = av.in.bits * av.in.chan / Bits_Per_Byte;

	if(count % ba)
		error(Ebadarg);

	if(! audio_pause_in(audio_file_in, A_UnPause))
		error(Eio);
	
	total = 0;
	while(total < count) {
		chunk = count - total;
		osenter();
		status = read(audio_file_in, pva + total, chunk);
		osleave(); 
		if(status < 0)
			error(Eio);
		total += status;
	}

	if(total != count)
		error(Eio);

	if(audio_swap_flag && av.out.bits == 16)
		audio_swap_endian(pva, count); 

	poperror();
	qunlock(&inlock);

	return count;
}

long
audio_file_write(Chan *c, void *va, long count, vlong offset)
{
	struct  timespec time;
	long status = -1;
	long ba, total, chunk, bufsz;

	if (debug > 1)
		print("audio_file_write(0x%.8lux, 0x%.8lux, %ld, %uld)\n",
			c, va, count, offset);

	qlock(&outlock);
	if(waserror()){
		qunlock(&outlock);
		nexterror();
	}

	if(audio_file_out < 0)
		error(Eperm);

	/* check block alignment */
	ba = av.out.bits * av.out.chan / Bits_Per_Byte;

	if(count % ba)
		error(Ebadarg);

	if(audio_swap_flag && av.out.bits == 16)
		audio_swap_endian(va, count); 

	total = 0;
	bufsz = av.out.buf * Audio_Max_Buf / Audio_Max_Val;

	if(bufsz == 0)
		error(Ebadarg);

	while(total < count) {
		chunk = min(bufsz, count - total);
		osenter();
		status = write(audio_file_out, va, chunk);
		osleave();
		if(status <= 0)
			error(Eio);
		total += status;
	}

	poperror();
	qunlock(&outlock);

	return count;
}

static int
audio_open(void)
{
	int fd;

	/* open non-blocking in case someone already has it open */
	/* otherwise we would block until they close! */
	fd = open(AUDIO_FILE_STRING, O_RDWR|O_NONBLOCK);
	if(fd < 0)
		oserror();

	/* change device to be blocking */
	if(!audio_set_blocking(fd)) {
		if (debug)
			print("audio_open: failed to set blocking\n");
		close(fd);
		error("cannot set blocking mode");
	}

	if (debug)
		print("audio_open: blocking set\n");

	/* set audio info */
	av.in.flags = ~0;
	av.out.flags = 0;

	if(! audio_set_info(fd, &av.in, A_In)) {
		close(fd);
		error(Ebadarg);
	}

	av.in.flags = 0;

	/* tada, we're open, blocking, paused and flushed */
	return fd;
}

long
audio_ctl_write(Chan *c, void *va, long count, vlong offset)
{
	int	fd;
	int	ff;
	Audio_t tmpav = av;

	tmpav.in.flags = 0;
	tmpav.out.flags = 0;

	if (!audioparse(va, count, &tmpav))
		error(Ebadarg);

	if (!audio_enforce(&tmpav))
		error(Ebadarg);

	qlock(&inlock);
	if (waserror()) {
		qunlock(&inlock);
		nexterror();
	}

	if (audio_file_in >= 0 && (tmpav.in.flags & AUDIO_MOD_FLAG)) {
		if (!audio_pause_in(audio_file_in, A_Pause))
			error(Ebadarg);
		if (!audio_flush(audio_file_in, A_In))
			error(Ebadarg);
		if (!audio_set_info(audio_file_in, &tmpav.in, A_In))
			error(Ebadarg);
	}
	poperror();
	qunlock(&inlock);

	qlock(&outlock);
	if (waserror()) {
		qunlock(&outlock);
		nexterror();
	}
	if (audio_file_out >= 0 && (tmpav.out.flags & AUDIO_MOD_FLAG)){
		if (!audio_pause_out(audio_file_out))
			error(Ebadarg);
		if (!audio_set_info(audio_file_out, &tmpav.out, A_Out))
			error(Ebadarg);
	}
	poperror();
	qunlock(&outlock);

	tmpav.in.flags = 0;
	tmpav.out.flags = 0;

	av = tmpav;

	return count;
}



static int
audio_set_blocking(int fd)
{
	int val;

	if((val = fcntl(fd, F_GETFL, 0)) == -1)
		return 0;
	
	val &= ~O_NONBLOCK;

	if(fcntl(fd, F_SETFL, val) < 0)
		return 0;

	return 1;
}

static int
doioctl(int fd, int ctl, int *info)
{
	int status;
	osenter();
	status = ioctl(fd, ctl, info);  /* qlock and load general stuff */
	osleave();
	if (status < 0)
		print("doioctl(0x%.8lux, 0x%.8lux) failed %d\n", ctl, *info, errno);
	return status;
}

static int
choosefmt(Audio_d *i)
{
	int newbits, newenc;
	
	newbits = i->bits;
	newenc = i->enc;
	switch (newenc) {
	case Audio_Alaw_Val:
		if (newbits == 8)
			return AFMT_A_LAW;
		break;
	case Audio_Ulaw_Val:
		if (newbits == 8)
			return AFMT_MU_LAW;
		break;
	case Audio_Pcm_Val:
		if (newbits == 8)
			return AFMT_U8;
		else if (newbits == 16)
			return AFMT_S16_LE;
		break;
	}
	return -1;
}

static int
audio_set_info(int fd, Audio_d *i, int d)
{
	int status;
	int unequal_stereo = 0;

	if(fd < 0)
		return 0;

	/* fmt */
	if(i->flags & (AUDIO_BITS_FLAG || AUDIO_ENC_FLAG)) {
		int oldfmt, newfmt;
		oldfmt = AFMT_QUERY;
		if (doioctl(fd, SNDCTL_DSP_SETFMT, &oldfmt) < 0)
			return 0;
		if (debug)
			print("audio_set_info: current format 0x%.8lux\n", oldfmt);
		newfmt = choosefmt(i);
		if (debug)
			print("audio_set_info: new format 0x%.8lux\n", newfmt);
		if (newfmt == -1 || newfmt != oldfmt && doioctl(fd, SNDCTL_DSP_SETFMT, &newfmt) < 0)
			return 0;
	}

	/* channels */
	if(i->flags & AUDIO_CHAN_FLAG) {
		int channels = i->chan;
		if (debug)
			print("audio_set_info: new channels %d\n", channels);
		if (doioctl(fd, SNDCTL_DSP_CHANNELS, &channels) < 0
			|| channels != i->chan)
			return 0;
	}

	/* sample rate */
	if(i->flags & AUDIO_RATE_FLAG) {
		int speed = i->rate;
		if (debug)
			print("audio_set_info: new speed %d\n", speed);
		if (doioctl(fd, SNDCTL_DSP_SPEED, &speed) < 0 || speed != i->rate)
			return 0;
	}

	/* dev volume */
	if(i->flags & (AUDIO_LEFT_FLAG | AUDIO_VOL_FLAG | AUDIO_RIGHT_FLAG)) {
		int val;
		if (i->flags & (AUDIO_LEFT_FLAG | AUDIO_VOL_FLAG))
			mixerleftvol[i->dev] = (i->left * 100) / Audio_Max_Val;
		if (i->flags & (AUDIO_RIGHT_FLAG | AUDIO_VOL_FLAG))
			mixerrightvol[i->dev] = (i->right * 100) / Audio_Max_Val;
		val = mixerleftvol[i->dev] | (mixerrightvol[i->dev] << 8);
		doioctl(fd, MIXER_WRITE(i->dev), &val);
	}

	if (i->flags & AUDIO_DEV_FLAG) {
	}
	
	return 1;
}

void 
audio_swap_endian(char *p, int n)
{
	int b;

	while (n > 1) {
		b = p[0];
		p[0] = p[1];
		p[1] = b;
		p += 2;
		n -= 2;
	}
}

static int
audio_pause_out(int fd)
{
	USED(fd);
	return 1;
}

static int
audio_pause_in(int fd, int f)
{
	USED(fd);
	USED(f);
	return 1;
}

static int
audio_flush(int fd, int d)
{
	int x;
	return doioctl(fd, SNDCTL_DSP_SYNC, &x) >= 0;
}

static int
audio_enforce(Audio_t *t)
{
	if((t->in.enc == Audio_Ulaw_Val || t->in.enc == Audio_Alaw_Val) && 
		(t->in.rate != 8000 || t->in.chan != 1))
		 return 0;
	if((t->out.enc == Audio_Ulaw_Val || t->out.enc == Audio_Alaw_Val) && 
		(t->out.rate != 8000 || t->out.chan != 1))
		 return 0;
	return 1;
}

Audio_t*
getaudiodev(void)
{
	return &av;
}
