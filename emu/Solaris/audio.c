#include "dat.h"
#include "fns.h"
#include "error.h"
#define __EXTENSIONS__
#include <sys/time.h>
#include <time.h>
#include <fcntl.h>
#include <stropts.h>
#include <sys/audioio.h>
#include <sys/ioctl.h>
#include <sys/filio.h>
#include "audio.h"
#include <sys/audioio.h>

#define 	Audio_Mic_Val		AUDIO_MICROPHONE
#define 	Audio_Linein_Val	AUDIO_LINE_IN

#define	Audio_Speaker_Val	AUDIO_SPEAKER
#define	Audio_Headphone_Val	AUDIO_HEADPHONE
#define	Audio_Lineout_Val	AUDIO_LINE_OUT

#define 	Audio_Pcm_Val		AUDIO_ENCODING_LINEAR
#define 	Audio_Ulaw_Val		AUDIO_ENCODING_ULAW
#define 	Audio_Alaw_Val		AUDIO_ENCODING_ALAW

#include "audio-tbls.c"

#define	min(a,b)	((a) < (b) ? (a) : (b))
static int debug = 0;

extern int nanosleep(const struct timespec *, struct timespec *);

#define AUDIO_FILE_STRING	"/dev/audio"

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

static	int	audio_file_in  = -1;	/* file in */
static	int	audio_file_out = -1;	/* file out */

static	int	audio_swap_flag = 0;	/* endian swap */

static	int	audio_in_pause = A_UnPause;

static Audio_t av;

static int audio_enforce(Audio_t*);
static int audio_open_in(void);
static int audio_open_out(void);
static int audio_pause_in(int, int);
static int audio_flush(int, int);
static int audio_pause_out(int);
static int audio_set_blocking(int);
static int audio_set_info(int, Audio_d*, int);
static void audio_swap_endian(char*, int);

void
audio_file_init(void)
{
	static ushort flag = 1;
	audio_swap_flag = *((uchar*)&flag) == 0;	/* big-endian? */
	audio_info_init(&av);
}

void
audio_file_open(Chan *c, int omode)
{
	switch(omode){
	case OREAD:
		qlock(&inlock);
		if(waserror()){
			qunlock(&inlock);
			nexterror();
		}

		if(audio_file_in >= 0)
			error(Einuse);
		if((audio_file_in = audio_open_in()) < 0)
			oserror();

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
		if((audio_file_out = audio_open_out() ) < 0)
			oserror();
		poperror();
		qunlock(&outlock);
		break;
	case ORDWR:
		qlock(&inlock);
		qlock(&outlock);
		if(waserror()){
			qunlock(&inlock);
			qunlock(&outlock);
			nexterror();
		}
		if(audio_file_in >= 0 || audio_file_out >= 0)
			error(Einuse);

		if((audio_file_in = audio_open_in()) < 0)
			oserror();
		if(waserror()){
			close(audio_file_in);
			audio_file_in = -1;
			nexterror();
		}
		if((audio_file_out = audio_open_out()) < 0)
			oserror();
		poperror();

		poperror();
		qunlock(&inlock);
		qunlock(&outlock);
		break;
	}
}

void
audio_file_close(Chan *c)
{
	switch(c->mode){
	case OREAD:
		qlock(&inlock);
		close(audio_file_in);
		audio_file_in = -1;
		qunlock(&inlock);
		break;
	case OWRITE:
		qlock(&outlock);
		close(audio_file_out);
		audio_file_out = -1;
		qunlock(&outlock);
		break;
	case ORDWR:
		qlock(&inlock);
		close(audio_file_in);
		audio_file_in = -1;
		qunlock(&inlock);
		qlock(&outlock);
		close(audio_file_out);
		audio_file_out = -1;
		qunlock(&outlock);
		break;
	}
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

	if(!audio_pause_in(audio_file_in, A_UnPause))
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

	time.tv_sec = 0; /* hack around broken thread scheduler in Solaris */
	time.tv_nsec= 1;
	nanosleep(&time,nil);

	return count;
}

long
audio_file_write(Chan *c, void *va, long count, vlong offset)
{
	struct  timespec time;
	long status = -1;
	long ba, total, chunk, bufsz;

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

	time.tv_sec = 0; /* hack around broken thread scheduler in Solaris */
	time.tv_nsec= 1;
	nanosleep(&time,nil);

	return count;
}

int
audio_open_in(void)
{
	int fd;

	/* open non-blocking in case someone already has it open */
	/* otherwise we would block until they close! */
	fd = open(AUDIO_FILE_STRING, O_RDONLY|O_NONBLOCK);

	if(fd < 0)
		oserror();

	/* change device to be blocking */
	if(!audio_set_blocking(fd)) {
		close(fd);
		error(Eio);
	}

	if(!audio_pause_in(fd, A_Pause)) {
		close(fd);
		error(Eio);
	}

	if(!audio_flush(fd, A_In)) {
		close(fd);
		error(Eio);
	}

	/* set audio info */
	av.in.flags = ~0;
	av.out.flags = 0;

	if(!audio_set_info(fd, &av.in, A_In)) {
		close(fd);
		error(Ebadarg);
	}

	av.in.flags = 0;

	/* tada, we're open, blocking, paused and flushed */
	return fd;
}

int
audio_open_out(void)
{
	int fd;
	struct audio_info	hdr;

	/* open non-blocking in case someone already has it open */
	/* otherwise we would block until they close! */
	fd = open(AUDIO_FILE_STRING, O_WRONLY|O_NONBLOCK);

	if(fd < 0)
		oserror();

	/* change device to be blocking */
	if(!audio_set_blocking(fd)) {
		close(fd);
		error("cannot set blocking mode");
	}

	/* set audio info */
	av.in.flags = 0;
	av.out.flags = ~0;

	if(!audio_set_info(fd, &av.out, A_Out)) {
		close(fd);
		error(Ebadarg);
	}

	av.out.flags = 0;

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
audio_set_info(int fd, Audio_d *i, int d)
{
	int status;
	int unequal_stereo = 0;
	audio_info_t	info;
	audio_prinfo_t  *dev;

	if(fd < 0)
		return 0;

	/* devitialize header */
	AUDIO_INITINFO(&info);

	if(d == A_In)
		dev = &info.record;
	else
		dev = &info.play;

	/* sample rate */
	if(i->flags & AUDIO_RATE_FLAG)
		dev->sample_rate = i->rate;

	/* channels */
	if(i->flags & AUDIO_CHAN_FLAG)
		dev->channels = i->chan;

	/* precision */
	if(i->flags & AUDIO_BITS_FLAG)
		dev->precision = i->bits;

	/* encoding */
	if(i->flags & AUDIO_ENC_FLAG)
		dev->encoding = i->enc;

	/* devices */
	if(i->flags & AUDIO_DEV_FLAG)
		dev->port = i->dev;

	/* dev volume */
	if(i->flags & (AUDIO_LEFT_FLAG|AUDIO_VOL_FLAG)) {
		dev->gain = (i->left * AUDIO_MAX_GAIN) / Audio_Max_Val;

		/* do left first then right later */
		if(i->left == i->right) 
			dev->balance = AUDIO_MID_BALANCE;
		else {
			dev->balance = AUDIO_LEFT_BALANCE;
			if(i->chan != 1)
				unequal_stereo = 1;
		}
	}

	osenter();
	status = ioctl(fd, AUDIO_SETINFO, &info);  /* qlock and load general stuff */
	osleave();

	if(status == -1) {
		if(debug) print("audio_set_info 1 failed: fd = %d errno = %d\n", fd, errno);
		return 0;
	}

	/* check for different right and left for dev */
	if(unequal_stereo) {

		/* re-init header */
		AUDIO_INITINFO(&info);

		dev->gain = (i->right * AUDIO_MAX_GAIN) / Audio_Max_Val;
		dev->balance == AUDIO_RIGHT_BALANCE;

		osenter();
		status = ioctl(fd, AUDIO_SETINFO, &info);
		osleave();

		if(status == -1) {
			if(debug) print("audio_set_info 2 failed: fd = %d errno = %d\n",fd, errno);
			return 0;
		}
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
	audio_info_t	info;
	int	foo = 0;
	int status;

	osenter();
	status = ioctl(fd, AUDIO_DRAIN, &foo);
	osleave();

	if(status == -1) 
		return 0;
	return 1;
}

static int
audio_pause_in(int fd, int f)
{
	audio_info_t	info;
	int status;

	if(fd < 0)
		return 0;

	if(audio_in_pause == f)
		return 1;
	
	/* initialize header */
	AUDIO_INITINFO(&info);

	/* unpause input */
	if(f == A_Pause)
		info.record.pause = 1;
	else
		info.record.pause = 0;

	osenter();
	status = ioctl(fd, AUDIO_SETINFO, &info);
	osleave();

	if(status == -1) 
		return 0;

	audio_in_pause = f;

	return 1;
}

static int
audio_flush(int fd, int d)
{
	int flag = d==A_In? FLUSHR: FLUSHW;
	int status;

	osenter();
	status = ioctl(fd, I_FLUSH, flag); /* drain anything already put into buffer */
	osleave();

	if(status == -1) 
		return 0;
	return 1;
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
