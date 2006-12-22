/*
 *  styx.c
 *
 *  A Styx fileserver for a Lego RCX
 *
 *  Nigel Roles
 *  Vita Nuova
 *
 *  This is a heavily modified version of test5.c
 *
 *  I couldn't have done this without Kekoa...
 *
 *
 *  The contents of this file are subject to the Mozilla Public License
 *  Version 1.0 (the "License"); you may not use this file except in
 *  compliance with the License. You may obtain a copy of the License at
 *  http://www.mozilla.org/MPL/
 *
 *  Software distributed under the License is distributed on an "AS IS"
 *  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
 *  License for the specific language governing rights and limitations
 *  under the License.
 *
 *  The Original Code is Librcx sample program code, released February 9,
 *  1999.
 *
 *  The Initial Developer of the Original Code is Kekoa Proudfoot.
 *  Portions created by Kekoa Proudfoot are Copyright (C) 1999
 *  Kekoa Proudfoot. All Rights Reserved.
 *
 *  Contributor(s): Kekoa Proudfoot <kekoa@graphics.stanford.edu>
 */

//#include "stdlib.h"
#include "rom.h"

#include "lib9.h"
#include "styx.h"

#include "llp.h"

#define ASSERT(cond) if (!(cond)) fatal(__LINE__)
#define FATAL fatal(__LINE__)
#define PROGRESS progress(__LINE__)

#if 0
#define ABP
#endif

uchar *send_fid_reply_payload(void);
void send_fid_reply(uchar type, ushort tag, ushort fid, uchar *msg, short len);
void send_error_reply(unsigned short tag, char *msg);

static unsigned short msgcount;
static unsigned char compressed_incoming[150];
static unsigned char incoming[1024];
static unsigned char compressed_reply[150];
short compressed_reply_len;
static unsigned char reply[1024];
unsigned short reply_len;
unsigned short transmitted_reply_len;
unsigned char alternating_bit;
static uchar dir[116];
uchar prepared;
uchar reader_count;
uchar dispatch[6];

/* ROM pseudofunctions */

static inline void
set_data_pointer (void *ptr)
{
    play_sound_or_set_data_pointer(0x1771, (short)ptr, 0);
}

static inline char
check_valid (void)
{
	char valid;
	check_for_data(&valid, NULL);
	return valid;
}

static inline int
receive_message (void *ptr, int len)
{
	char bytes = 0;
	receive_data(ptr, len, &bytes);
	/* Bytes includes checksum, since we don't want that, return bytes-1 */
	return bytes - 1;
}

static inline void
send_message (void *ptr, int len)
{
	if (len)
		while (send_data(0x1776, 0, ptr, len));
}

int
poll_power(void)
{
	static short debounce = 0;
	static short state = -1;
	short status;
	get_power_status(0x4000, &status);
	if (state != status)
		debounce = 0;
	else if (debounce < 10)
		debounce++;
	state = status;
	return debounce >= 10 ? state : -1;
}

static void
progress(short line)
{
	set_lcd_number(LCD_UNSIGNED, line, LCD_DECIMAL_0);
	refresh_display();
}

static void
fatal(short line)
{
	set_lcd_segment(LCD_STANDING);
	progress(line);
	while (poll_power() != 0)
		;
}

typedef struct Reader {
	ushort tag;
	ushort fid;
	ushort offset;
	ushort count;
	struct Reader *next;
} Reader;

typedef struct DirectoryEntry {
	char *name;
	uchar qid;
	const struct DirectoryEntry *sub;
	short (*read)(const struct DirectoryEntry *dp, ushort tag, ushort fid, ushort offset, ushort count);
	short (*write)(const struct DirectoryEntry *dp, ushort offset, ushort count, uchar *buf);
} DirectoryEntry;

#define QID_ROOT 0
#define QID_MOTOR 1
#define QID_MOTOR_0 2
#define QID_MOTOR_1 3
#define QID_MOTOR_2 4
#define QID_MOTOR_012 5
#define QID_SENSOR 6
#define QID_SENSOR_0 7
#define QID_SENSOR_1 8
#define QID_SENSOR_2 9

typedef struct Sensor {
	sensor_t sensor;
	uchar active;
	uchar greater;
	ushort thresh;
	Reader *reader;
} Sensor;

Sensor sensor[3];

short
atoin(char *s, short lim)
{
	short total = 0;
	while (*s && lim) {
		char c = *s++;
		if (c >= '0' && c <= '9')
			total = total * 10 + c - '0';
		else
			break;
		lim--;
	}
	return total;
}

short
itoa(char *buf, short value)
{
	char *bp = buf;
	short divisor;
	if (value < 0) {
		*bp++ = '-';
		value = -value;
	}
	if (value == 0)
		*bp++ = '0';
	else {
		divisor = 10000;
		while (divisor > value)
			divisor /= 10;
		while (divisor) {
			*bp++ = '0' + value / divisor;
			value %= divisor;
			divisor /= 10;
		}
	}
	return bp - buf;
}

Reader *
readercreate(ushort tag, ushort fid, ushort offset, ushort count)
{
	Reader *rp = malloc(sizeof(Reader));
	rp->tag = tag;
	rp->fid = fid;
	rp->offset = offset;
	rp->count = count;
	rp->next = 0;
	reader_count++;
	return rp;
}

void
readerfree(Reader *rp)
{
	free(rp);
	reader_count--;
}

int
senderrorreset(Reader *rp, void *magic)
{
	send_error_reply(rp->tag, "reset");
	return 1;
}

void
readerlistfindanddestroy(Reader **rpp, int (*action)(Reader *rp, void *magic), void *magic)
{
	while (*rpp) {
		Reader *rp = *rpp;
		if ((*action)(rp, magic)) {
			*rpp = rp->next;
			readerfree(rp);
		}
		else
			rpp = &(rp->next);
	}
}

void
allreaderlistfindanddestroy(int (*action)(Reader *rp, void *magic), void *magic)
{
	short i;
	for (i = 0; i < 3; i++)
		readerlistfindanddestroy(&sensor[i].reader, action, magic);
}

short
sensorwrite(const DirectoryEntry *dp, ushort offset, ushort count, uchar *data)
{
	short i;
	Sensor *sp;
	uchar greater;
	short type, mode;
	ushort k;

	if (offset != 0)
		return -1;
	i = dp->qid - QID_SENSOR_0;
	sp = &sensor[i];
	k = count;
	if (k == 0)
		return -1;
	switch (data[0]) {
	case 'b':
		type = SENSOR_TYPE_TOUCH;
		mode = SENSOR_MODE_PULSE;
		break;
	case 'l':
		type = SENSOR_TYPE_TOUCH;
		mode = SENSOR_MODE_RAW;
		break;
	default:
		return -1;
	}
	data++; k--;
	if (k == 0)
		return -1;
	if (*data == '>') {
		greater = 1;
		data++;
		k--;
	}
	else if (*data == '<') {
		greater = 0;
		data++;
		k--;
	}
	else
		greater = 1;
	if (k == 0)
		return -1;
	readerlistfindanddestroy(&sp->reader, senderrorreset, 0);
	set_sensor_passive(SENSOR_0 + i);
	sp->sensor.type = type;
	sp->sensor.mode = mode;
	sp->thresh = atoin(data, k);
	sp->sensor.raw = 0;
	sp->sensor.value = 0;
	sp->sensor.boolean = 0;
	sp->active = 1;
	sp->greater = greater;
	set_sensor_active(SENSOR_0 + i);
	return count;
}

void
send_read_reply(ushort tag, ushort fid, ushort offset, ushort len, uchar *answer, short answerlen)
{
	uchar *out = send_fid_reply_payload();
	ushort actual;
	if (offset < answerlen) {
		actual = answerlen - offset;
		if (actual > len)
			actual = len;
		memcpy(out + 3, answer + offset, actual);
	}
	else
		actual = 0;
	out[0] = actual;
	out[1] = actual >> 8;
	out[2] = 0;
	send_fid_reply(Rread, tag, fid, 0, actual + 3);
}

void
send_sensor_read_reply(ushort tag, ushort fid, ushort offset, ushort count, short value)
{
	short answerlen;
	char answer[8];
	/* reply is countlow counthigh pad data[count] */
	answerlen = itoa(answer, value);
	send_read_reply(tag, fid, offset, count, answer, answerlen);
}

int
sensortriggered(Sensor *sp)
{
	if (sp->greater)
		return sp->sensor.value >= sp->thresh;
	else
		return sp->sensor.value < sp->thresh;
}

short
sensorread(const struct DirectoryEntry *dp, ushort tag, ushort fid, ushort offset, ushort count)
{
	short i;
	Sensor *sp;
	i = dp->qid - QID_SENSOR_0;
	sp = sensor + i;
	if (!sp->active)
		return -1;
	if (sensortriggered(sp))
		send_sensor_read_reply(tag, fid, offset, count, sp->sensor.value);
	else {
		/* add to queue */
		Reader *rp = readercreate(tag, fid, offset, count);
		rp->next = sp->reader;
		sp->reader = rp;
	}
	return 0;
}

void
sensorpoll(void)
{
	short i;
	Sensor *sp;

	if ((dispatch[0] & 0x80) == 0) {
		return;
	}
	dispatch[0] &= 0x7f;
	/* do the following every 3 ms with a following wind */
	for (i = 0; i < 3; i++) {
		sp = sensor + i;
		if (sp->active) {
			/*
			 * read sensor 4 times to reduce debounce on each
			 * edge to effectively 25 counts, or 75ms
			 * allowing about 8 pulses a second
			 */
			read_sensor(SENSOR_0 + i, &sp->sensor);
			read_sensor(SENSOR_0 + i, &sp->sensor);
			read_sensor(SENSOR_0 + i, &sp->sensor);
			read_sensor(SENSOR_0 + i, &sp->sensor);
			if (sensortriggered(sp)) {
				/* complete any outstanding reads */
				while (sp->reader) {
					Reader *rp = sp->reader;
					sp->reader = rp->next;
					send_sensor_read_reply(rp->tag, rp->fid, rp->offset, rp->count, sp->sensor.value);
					readerfree(rp);
				}
			}
		}
	}
}

short
motorparse(uchar *flag, short *mode, short *power, uchar *data)
{
	switch (data[0]) {
	case 'f': *mode = MOTOR_FWD; break;
	case 'r': *mode = MOTOR_REV; break;
	case 's': *mode = MOTOR_STOP; break;
	case 'F': *mode = MOTOR_FLOAT; break;
	case '-': return 1;
	default:
		return 0;
	}
	if (data[1] >= '0' && data[1] <= '7')
		*power = data[1] - '0';
	else
		return 0;
	*flag = 1;
	return 1;
}

short
motorwrite(const DirectoryEntry *dp, ushort offset, ushort count, uchar *data)
{
	short mode[3], power[3];
	uchar flag[3];
	short i;

	if (offset != 0)
		return -1;
	flag[0] = flag[1] = flag[2] = 0;
	if (dp->qid == QID_MOTOR_012) {
		if (count != 6)
			return -1;
		if (!motorparse(flag, mode, power, data)
		 || !motorparse(flag + 1, mode + 1, power + 1, data + 2)
		 || !motorparse(flag + 2, mode + 2, power + 2, data + 4))
			return -1;
	}
	else {
		if (count != 2)
			return -1;
		i = dp->qid - QID_MOTOR_0;
		if (!motorparse(flag + i, mode + i, power + i, data))
			return -1;
	}
	for (i = 0; i < 3; i++)
		if (flag[i])
			control_motor(MOTOR_0 + i, mode[i], power[i]);
	return count;
}

const uchar qid_root[8] = { QID_ROOT, 0, 0, 0x80 };

const DirectoryEntry dir_root[], dir_slash[];

const DirectoryEntry dir_motor[] = {
	{ "..", QID_ROOT, dir_root },
	{ "0", QID_MOTOR_0,	0, 0, motorwrite },
	{ "1", QID_MOTOR_1,	0, 0, motorwrite },
	{ "2", QID_MOTOR_2,	0, 0, motorwrite },
	{ "012", QID_MOTOR_012, 0, 0, motorwrite },
	{ 0 }
};

const DirectoryEntry dir_sensor[] = {
	{ "..", QID_ROOT, dir_root },
	{ "0", QID_SENSOR_0,	0, sensorread, sensorwrite },
	{ "1", QID_SENSOR_1,	0, sensorread, sensorwrite },
	{ "2", QID_SENSOR_2,	0, sensorread, sensorwrite },
	{ 0 }
};

const DirectoryEntry dir_root[] = {
	{ "..", QID_ROOT, dir_slash },
	{ "motor", QID_MOTOR, dir_motor },
	{ "sensor", QID_SENSOR, dir_sensor },
	{ 0 }
};

const DirectoryEntry dir_slash[] = {
	{ "/", QID_ROOT, dir_root },
	{ 0 }
};

const DirectoryEntry *qid_map[] = {
	/* QID_ROOT */		&dir_slash[0],
	/* QID_MOTOR */		&dir_root[1],
	/* QID_MOTOR_0 */	&dir_motor[1],
	/* QID_MOTOR_1 */	&dir_motor[2],
	/* QID_MOTOR_2 */	&dir_motor[3],
	/* QID_MOTOR_012 */	&dir_motor[4],
	/* QID_SENSOR */	&dir_root[2],
	/* QID_SENSOR_0 */	&dir_sensor[1],
	/* QID_SENSOR_1 */	&dir_sensor[2],
	/* QID_SENSOR_2 */	&dir_sensor[3],
};

#define QID_MAP_MAX (sizeof(qid_map) / sizeof(qid_map[0]))

typedef struct Fid {
	struct Fid *next;
	ushort fid;
	uchar open;
	uchar qid[8];
} Fid;

Fid *fids;

Fid *
fidfind(ushort fid)
{
	Fid *fp;
	for (fp = fids; fp && fp->fid != fid; fp = fp->next)
		;
	return fp;
}

Fid *
fidcreate(ushort fid, const uchar qid[8])
{
	Fid *fp;
	fp = malloc(sizeof(Fid));
	ASSERT(fp);
	fp->open = 0;
	fp->fid = fid;
	fp->next = fids;
	memcpy(fp->qid, qid, 8);
	fids = fp;
	return fp;
}

int
matchfp(Reader *rp, void *magic)
{
	if (rp->fid == ((Fid *)magic)->fid) {
		return 1;
	}
	return 0;
}

void
fiddelete(Fid *fp)
{
	Fid **fpp;
	/* clobber any outstanding reads on this fid */
	allreaderlistfindanddestroy(matchfp, fp);
	/* now clobber the fid */
	for (fpp = &fids; *fpp; fpp = &(*fpp)->next)
		if (*fpp == fp) {
			*fpp = fp->next;
			free(fp);
			return;
		}
	FATAL;
}

const DirectoryEntry *
nthentry(const DirectoryEntry *dp, ushort n)
{
	const DirectoryEntry *sdp;
	ASSERT(dp->sub);
	for (sdp = dp->sub; sdp->name; sdp++)
		if (strcmp(sdp->name, "..") != 0) {
			if (n == 0)
				return sdp;
			n--;
		}
	return 0;
}

int
fidwalk(Fid *fp, char name[28])
{
	const DirectoryEntry *sdp;
	const DirectoryEntry *dp;

	if (fp->open)
		return -1;
	ASSERT(fp->qid[0] < QID_MAP_MAX);
	dp = qid_map[fp->qid[0]];
	if (dp->sub == 0)
		return -1;
	for (sdp = dp->sub; sdp->name; sdp++)
		if (strcmp(sdp->name, name) == 0) {
			fp->qid[0] = sdp->qid;
			fp->qid[3] = sdp->sub ? 0x80 : 0;
			return 1;
		}
	return 0;
}

void
mkdirent(const DirectoryEntry *dp, uchar *dir)
{
	memset(dir, 0, DIRLEN);
	strcpy(dir, dp->name);
	strcpy(dir + 28, "lego");
	strcpy(dir + 56, "lego");
	dir[84] = dp->qid;
	dir[92] = dp->sub ? 0555 : 0666;
	dir[93] = dp->sub ? (0555 >> 8) : (0666 >> 8);
	dir[95] = dp->sub ? 0x80 : 0;
}

int
fidstat(Fid *fp, uchar *dir)
{
	const DirectoryEntry *dp;
	if (fp->open)
		return -1;
	ASSERT(fp->qid[0] < QID_MAP_MAX);
	dp = qid_map[fp->qid[0]];
	mkdirent(dp, dir);
	return 1;
}

int
fidopen(Fid *fp, uchar mode)
{
	if (fp->open
	    || (mode & ORCLOSE)
	    /*|| (mode & OTRUNC) */)
		return 0;
	if (fp->qid[3] && (mode == OWRITE || mode == ORDWR))
		/* can't write directories */
		return 0;
	fp->open = 1;
	return 1;
}

short
fidread(Fid *fp, ushort tag, ushort offset, ushort count)
{
	short k;
	uchar *p;
	const DirectoryEntry *dp;
	uchar *buf;

	ASSERT(fp->qid[0] < QID_MAP_MAX);
	dp = qid_map[fp->qid[0]];

	if (fp->qid[3] & 0x80) {
		if (!fp->open)
			return -1;
		if (count % DIRLEN != 0 || offset % DIRLEN != 0)
			return -1;
		count /= DIRLEN;
		offset /= DIRLEN;
		buf = send_fid_reply_payload();
		p = buf + 3;
		for (k = 0; k < count; k++) {
			const DirectoryEntry *sdp = nthentry(dp, offset + k);
			if (sdp == 0)
				break;
			mkdirent(sdp, p);
			p += DIRLEN;
		}
/* a read beyond just returns 0 
		if (k == 0 && count)
			return -1;
*/
		k *= DIRLEN;
		buf[0] = k;
		buf[1] = k >> 8;
		buf[2] = 0;
		send_fid_reply(Rread, tag, fp->fid, 0, k + 3);
		return 0;
	}
	/* right, that's that out of the way */
	if (!dp->read)
		return -1;
	return (*dp->read)(dp, tag, fp->fid, offset, count);
}

short
fidwrite(Fid *fp, ushort offset, ushort count, uchar *buf)
{
	const DirectoryEntry *dp;
	if (fp->qid[3] & 0x80)
		return -1;		/* can't write directories */
	if (!fp->open)
		return -1;
	ASSERT(fp->qid[0] < QID_MAP_MAX);
	dp = qid_map[fp->qid[0]];
	if (!dp->write)
		return -1;		/* no write method */
	return (*dp->write)(dp, offset, count, buf);
}

int
rlencode(unsigned char *out, int limit, unsigned char *in, int len)
{
	unsigned char *ip, *op;
	int oc, zc;

	if (len == 0)
		return -1;
	ip = in;
	op = out;
	zc = 0;

	oc = 0;

	for (;;) {
		int last = ip >= in + len;
		if (*ip != 0 || last)
		{
			switch (zc) {
			case 1:
				if (oc >= len - 1)
					return -1;
				*op++ = 0;
				oc++;
				break;
			case 2:
				if (oc >= len - 2)
					return -1;
				*op++ = 0;
				*op++ = 0;
				oc += 2;
				break;
			case 0:
				break;
			default:
				if (oc >= len - 2)
					return -1;
				*op++ = 0x88;
				*op++ = zc - 2;
				oc += 2;
				break;
			}
			zc = 0;
		}
		if (last)
			break;
		if (*ip == 0x88) {
			if (oc >= len - 2)
				return -1;
			*op++ = 0x88;
			*op++ = 0x00;
			oc += 2;
		}
		else if (*ip == 0x00)
		{
			zc++;
		}
		else {
			if (oc >= len - 1)
				return -1;
			*op++ = *ip;
			oc++;
		}
		ip++;
	}
	return oc;
}

int
rldecode(unsigned char *out, unsigned char *in, int len)
{
	int oc, k;

	oc = 0;

	while (len) {
		if (*in != 0x88) {
			*out++ = *in++;
			oc++;
			len--;
			continue;
		}
		in++;
		switch (*in) {
		case 0:
			*out++ = 0x88;
			oc++;
			break;
		default:
			k = *in + 2;
			oc += k;
			while (k-- > 0)
				*out++ = 0;
		}
		in++;
		len -= 2;
	}
	return oc;
}

void
prepare_transmission(void)
{
	if (prepared)
		return;
	compressed_reply_len = rlencode(compressed_reply + 3, sizeof(compressed_reply) - 3, reply, reply_len);
	if (compressed_reply_len < 0) {
		memcpy(compressed_reply + 3, reply, reply_len);
		compressed_reply_len = reply_len;
		compressed_reply[2] = 0x0;
	}
	else
		compressed_reply[2] = LLP_COMPRESSION;
	if (reader_count)
		compressed_reply[2] |= LLP_POLL_PERIODIC;
	compressed_reply[2] |= !alternating_bit;
	compressed_reply_len++;
	compressed_reply[0] = compressed_reply_len;
	compressed_reply[1] = compressed_reply_len >> 8;
	compressed_reply_len += 2;
	prepared = 1;
}

void
transmit(void)
{
	prepare_transmission();
	transmitted_reply_len = reply_len;
	send_message(compressed_reply, compressed_reply_len);
}

void
flush_reply_buffer(void)
{
	if (reply_len > transmitted_reply_len)
		memcpy(reply, reply + transmitted_reply_len, reply_len - transmitted_reply_len);
	reply_len -= transmitted_reply_len;
	prepared = 0;
}

void
send_reply(unsigned char type, unsigned short tag, unsigned char *msg, short len)
{
	uchar *p = reply + reply_len;
	p[0] = type;
	p[1] = tag & 0xff;
	p[2] = tag >> 8;
	if (msg)
		memcpy(p + 3, msg, len);
	reply_len += len + 3;
	prepared = 0;
}

void
send_error_reply(unsigned short tag, char *msg)
{
	short len;
	uchar *p = reply + reply_len;
	p[0] = Rerror;
	p[1] = tag & 0xff;
	p[2] = tag >> 8;
	len = (short)strlen(msg);
	if (len > 64)
		len = 64;
	memcpy(p + 3, msg, len);
	reply_len += 67;
	prepared = 0;
}

uchar *
send_fid_reply_payload(void)
{
	return reply + reply_len + 5;
}

void
send_fid_reply(uchar type, ushort tag, ushort fid, uchar *msg, short len)
{
	uchar *p = reply + reply_len;
	p[0] = type;
	p[1] = tag & 0xff;
	p[2] = tag >> 8;
	p[3] = fid & 0xff;
	p[4] = fid >> 8;
	if (msg)
		memcpy(p + 5, msg, len);
	reply_len += len + 5;
	prepared = 0;
}

int
matchtag(Reader *rp, void *oldtag)
{
	if (rp->tag == (ushort)oldtag) {
		return 1;
	}
	return 0;
}

void
flushtag(ushort oldtag)
{
	/* a little inefficient this - there can be at most one match! */
	allreaderlistfindanddestroy(matchtag, (void *)oldtag);
}

void
process_styx_message(unsigned char *msg, short len)
{
	unsigned char type;
	ushort tag, oldtag, fid, newfid;
	ushort offset, count;
	short extra;
	Fid *fp, *nfp;
	short written;
	uchar buf[2];

	ASSERT(len >= 3);
	
	type = *msg++; len--;
	tag = (msg[1] << 8) | msg[0]; len -= 2; msg += 2;

	switch (type) {
	case Tnop:
		send_reply(Rnop, tag, 0, 0);
		goto done;
	case Tflush:
		ASSERT(len == 2);
		oldtag = (msg[1] << 8) | msg[0];
		flushtag(oldtag);
		send_reply(Rflush, tag, 0, 0);
		goto done;
	}
	/* all other messages take a fid as well */
	ASSERT(len >= 2);
	fid = (msg[1] << 8) | msg[0]; len -= 2; msg += 2;
	fp = fidfind(fid);
	
	switch (type) {
	case Tattach:
		ASSERT(len == 56);
		if (fp) {
		fid_in_use:
			send_error_reply(tag, "fid in use");
		}
		else {
			fp = fidcreate(fid, qid_root);
			send_fid_reply(Rattach, tag, fid, fp->qid, 8);
		}
		break;
	case Tclunk:
	case Tremove:
		ASSERT(len == 0);
		if (!fp) {
		no_such_fid:
			send_error_reply(tag, "no such fid");
		}
		else {
			fiddelete(fp);
			if (type == Tremove)
				send_error_reply(tag, "can't remove");
			else
				send_fid_reply(Rclunk, tag, fid, 0, 0);
		}
		break;
	case Tclone:
		ASSERT(len == 2);
		newfid = (msg[1] << 8) | msg[0];
		nfp = fidfind(newfid);
		if (!fp)
			goto no_such_fid;
		if (fp->open) {
			send_error_reply(tag, "can't clone");
			break;
		}
		if (nfp)
			goto fid_in_use;
		nfp = fidcreate(newfid, fp->qid);
		send_fid_reply(Rclone, tag, fid, 0, 0);
		break;
	case Twalk:
		ASSERT(len == 28);
		if (!fidwalk(fp, msg))
			send_error_reply(tag, "no such name");
		else
			send_fid_reply(Rwalk, tag, fid, fp->qid, 8);
		break;
	case Tstat:
		ASSERT(len == 0);
		if (!fidstat(fp, dir))
			send_error_reply(tag, "can't stat");
		else
			send_fid_reply(Rstat, tag, fid, dir, 116);
		break;
		ASSERT(len == 0);
	case Tcreate:
		ASSERT(len == 33);
		send_error_reply(tag, "can't create");
		break;
	case Topen:
		ASSERT(len == 1);
		if (!fidopen(fp, msg[0]))
			send_error_reply(tag, "can't open");
		else
			send_fid_reply(Ropen, tag, fid, fp->qid, 8);
		break;
	case Tread:
		ASSERT(len == 10);
		offset = (msg[1] << 8) | msg[0];
		count = (msg[9] << 8) | msg[8];
		if (fidread(fp, tag, offset, count) < 0)
			send_error_reply(tag, "can't read");
		break;
	case Twrite:
		ASSERT(len >= 11);
		offset = (msg[1] << 8) | msg[0];
		count = (msg[9] << 8) | msg[8];
		msg += 11;
		len -= 11;
		ASSERT(count == len);
		written = fidwrite(fp, offset, count, msg);
		if (written < 0)
			send_error_reply(tag, "can't write");
		else {
			buf[0] = written;
			buf[1] = written >> 8;
			send_fid_reply(Rwrite, tag, fid, buf, 2);
		}
		break;
	default:
		FATAL;
	}
done:
	;
}

void
process_llp_message(unsigned char *msg, short len)
{
	short styxlen;
	switch (msg[0]) {
	case 0x45:
	case 0x4d:
		if (len != 5)
			FATAL;
		styxlen = compressed_incoming[0] | (compressed_incoming[1] << 8);
		/* transfer the transmitted checksum to the end */
		compressed_incoming[styxlen + 2 - 1] = msg[3];
		/* check alternating bit */
#ifdef ABP
		if ((compressed_incoming[2] & 1) != alternating_bit ||
		    ((msg[0] & 8) != 0) != alternating_bit) {
			transmit();
			break;
		}
#endif
		alternating_bit = !alternating_bit;
		flush_reply_buffer();
		if (styxlen > 1) {
			if (compressed_incoming[2] & LLP_COMPRESSION) {
				/* decompress everything but length and link header */
				styxlen = rldecode(incoming, compressed_incoming + 3, styxlen - 1);
				process_styx_message(incoming, styxlen);
			}
			else
				process_styx_message(compressed_incoming + 3, styxlen - 1);
		}
		transmit();
		break;
	default:
		FATAL;
	}
}

int
main (void)
{
	int count = 0;
	char buf[16];
	char temp[64];

	mem_init();
	memset(temp,0, sizeof(temp));

	/* Initialize */

	init_timer(&temp[6], &dispatch[0]);
	init_power();
	init_sensors();
	init_serial(&temp[4], &temp[6], 1, 1);

	set_lcd_number(LCD_UNSIGNED, 0, LCD_DECIMAL_0);
	set_lcd_segment(LCD_WALKING);
	refresh_display();

	set_data_pointer(compressed_incoming);

	alternating_bit = 0;
	compressed_reply_len = 0;
	reply_len = 0;
	prepared = 0;

	while (poll_power() != 0) {

		/* If a message has arrived, send a response with opcode inverted */

		if (check_valid()) {
			int len = receive_message(buf, sizeof(buf));
			msgcount++;
			process_llp_message(buf, len);
		}
		sensorpoll();
	}

	return 0;
}
