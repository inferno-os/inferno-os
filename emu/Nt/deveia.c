/*
 *  Windows serial driver
 *
 * to do:
 *	scan the registry for serial ports?
 */

#define Unknown win_Unknown
#include	<windows.h>
#undef Unknown
#undef	Sleep
#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	<sys/types.h>
#include	<sys/stat.h>
#include	<fcntl.h>
#include	<stdio.h>
#include	<lm.h>
#include	<direct.h>

// local fcts
static void openport(int);
static void wrctl(int, char*);
static long rdstat(int, void*, long, ulong );

enum
{
	Devchar = 't',

	Ndataqid = 1,
	Nctlqid,
	Nstatqid,
	Nqid = 3,		/* number of QIDs */

	Maxctl = 128,

	// in/out buffer sizes for comm port (NT requires an even number)
	// set it to x* the max styx message rounded up to the
	// nearest 4 byte value
	CommBufSize = ((((8192+128)*2)+3) & ~3)
};

/*
 *  Macros to manage QIDs
 */
#define NETTYPE(x)	((x)&0x0F)
#define NETID(x)	((x)>>4)
#define NETQID(i,t)	(((i)<<4)|(t))

static Dirtab *eiadir;
static int ndir;

typedef struct Eia Eia;
struct Eia {
	Ref	r;
	HANDLE      comfh;          //handle to open port
	int		restore;       //flag to restore prev. states 
	DCB		dcb;           //win32 device control block used for restore
	int		id;            //index to host port name in sysdev
};

// the same timeouts are used for all ports
// currently there is no Inferno interface to
// change the timeouts.
static COMMTIMEOUTS  timeouts;  
                   
// std win32 serial port names are COM1..COM4
// however there can be more and they can be
// named anything. we should be more flexible
// pehaps adding a ctl command to allow you to
// access any win32 comm port
static char* sysdev[] = {
	"COM1:",
	"COM2:",
	"COM3:",
	"COM4:",
	"COM5:",
	"COM6:",
	"COM7:",
	"COM8:",
	NULL
};
    
static Eia *eia;

typedef struct OptTable OptTable;
struct OptTable {
	char   *str;
	DWORD  flag;
};

#define BAD ((DWORD)-1)

// valid bit-per-byte sizes
static OptTable size[] = {
	{"5",	5},
	{"6",	6},
	{"7",	7},
	{"8",	8},
	{NULL,  BAD}
};

// valid stop bits
static OptTable stopbits[] = {
	{"1",    ONESTOPBIT},
	{"1.5",  ONE5STOPBITS},
	{"2",    TWOSTOPBITS},
	{NULL,   BAD}
};

// valid parity settings
static OptTable parity[] = {
	{"o",    ODDPARITY},
	{"e",    EVENPARITY},
	{"s",    SPACEPARITY},
	{"m",    MARKPARITY},
	{"n",    NOPARITY},
	{NULL,   NOPARITY}
};


static char *
ftos(OptTable *tbl, DWORD flag)
{
	while(tbl->str && tbl->flag != flag)
		tbl++;
	if(tbl->str == 0)
		return "unknown";
	return tbl->str;
}

static DWORD
stof(OptTable *tbl, char *str)
{
	while(tbl->str && strcmp(tbl->str, str) != 0)
		tbl++;
	return tbl->flag;
}

static void
eiainit(void)
{
	int     i,x;
	byte    ports;   //bitmask of active host ports
	int     nports;  //number of active host ports
	int     max;     //number of highest port
	Dirtab *dp;

	// setup the timeouts; choose carefully
	timeouts.ReadIntervalTimeout = 2;
	timeouts.ReadTotalTimeoutMultiplier = 0;
	timeouts.ReadTotalTimeoutConstant = 200;
	timeouts.WriteTotalTimeoutMultiplier = 0;
	timeouts.WriteTotalTimeoutConstant = 400;

	// check to see which ports exist by trying to open them
	// keep results in a bitmask
	ports = nports = max = 0;
	for(i=0; (sysdev[i] != NULL) && (i<8); i++) {
		HANDLE comfh = CreateFile(sysdev[i], 0, 0, NULL,	/* no security attrs */
			OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);

		if(comfh != INVALID_HANDLE_VALUE) {
			ports |= 1<<i;   
			CloseHandle(comfh);
			nports++;
			max = i;
		}
	}

	if(nports == 0)
		return;  //no ports

	// allocate directory table and eia structure
	// for each active port.
	ndir = Nqid*nports+1;
	dp = eiadir = malloc(ndir*sizeof(Dirtab));
	if(dp == 0)
		panic("eiainit");
	eia = malloc(nports*sizeof(Eia));
	if(eia == 0) {
		free(dp);
		panic("eiainit");
	}

	// fill in the directory table and initialize
	// the eia structure.  skip inactive ports.
	sprint(dp->name, ".");
	dp->qid.path = 0;
	dp->qid.type = QTDIR;
	dp->perm = DMDIR|0555;
	dp++;
	x = 0;  // index in eia[]
	for(i = 0; i <= max; i++) {
		if( (ports & (1<<i)) == 0)
			continue;  //port 'i' is not active
		sprint(dp->name, "eia%d", i);
		dp->qid.path = NETQID(x, Ndataqid);
		dp->perm = 0660;
		dp++;
		sprint(dp->name, "eia%dctl", i);
		dp->qid.path = NETQID(x, Nctlqid);
		dp->perm = 0660;
		dp++;
		sprint(dp->name, "eia%dstatus", i);
		dp->qid.path = NETQID(x, Nstatqid);
		dp->perm = 0660;
		dp++;
		// init the eia structure
		eia[x].restore = 0;
		eia[x].id = i;
		x++;
	}
}

static Chan*
eiaattach(char *spec)
{
	if(eiadir == nil)
		error(Enodev);

	return devattach(Devchar, spec);
}

static Walkqid*
eiawalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, eiadir, ndir, devgen);
}

static int
eiastat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, eiadir, ndir, devgen);
}

static Chan*
eiaopen(Chan *c, int mode)
{
	int port = NETID(c->qid.path);

	c = devopen(c, mode, eiadir, ndir, devgen);

	switch(NETTYPE(c->qid.path)) {
	case Nctlqid:
	case Ndataqid:
	case Nstatqid:
		if(incref(&eia[port].r) != 1)
			break;
		if(waserror()) {
			decref(&eia[port].r);
			nexterror();
		}
		openport(port);
		poperror();
		break;
	}
	return c;
}

static void
eiaclose(Chan *c)
{
	int port = NETID(c->qid.path);

	if((c->flag & COPEN) == 0)
		return;

	switch(NETTYPE(c->qid.path)) {
	case Nctlqid:
	case Ndataqid:
	case Nstatqid:
		if(decref(&eia[port].r) == 0) {
			osenter();
			CloseHandle(eia[port].comfh);
			osleave();
		}
		break;
	}

}

static long
eiaread(Chan *c, void *buf, long n, vlong offset)
{
	DWORD cnt;
	int port = NETID(c->qid.path);
	BOOL good;

	if(c->qid.type & QTDIR)
		return devdirread(c, buf, n, eiadir, ndir, devgen);

	switch(NETTYPE(c->qid.path)) {
	case Ndataqid:
		cnt = 0;
		// if ReadFile timeouts and cnt==0 then just re-read
		// this will give osleave() a chance to detect an
		// interruption (i.e. killprog)
		while(cnt==0) {
  			osenter(); 
			good = ReadFile(eia[port].comfh, buf, n, &cnt, NULL);
			SleepEx(0,FALSE);  //allow another thread access to port
			osleave();
			if(!good)
				oserror();
		}
		return cnt;
	case Nctlqid:
		return readnum(offset, buf, n, eia[port].id, NUMSIZE);
	case Nstatqid:
		return rdstat(port, buf, n, offset);
	}

	return 0;
}

static long
eiawrite(Chan *c, void *buf, long n, vlong offset)
{
	DWORD cnt;
	char cmd[Maxctl];
	int port = NETID(c->qid.path);
	BOOL good;
	uchar *data;

	if(c->qid.type & QTDIR)
		error(Eperm);

	switch(NETTYPE(c->qid.path)) {
	case Ndataqid:
		cnt = 0;
		data = (uchar*)buf;
		// if WriteFile times out (i.e. return true; cnt<n) then
		// allow osleave() to check for an interrupt otherwise try
		// to send the unsent data.
		while(n>0) {
	  		osenter(); 
			good = WriteFile(eia[port].comfh, data, n, &cnt, NULL);
			osleave(); 
			if(!good)
				oserror();
			data += cnt;
			n -= cnt;
		}
		return (data-(uchar*)buf);
	case Nctlqid:
		if(n >= sizeof(cmd))
			n = sizeof(cmd)-1;
		memmove(cmd, buf, n);
		cmd[n] = 0;
		wrctl(port, cmd);
		return n;
	}
	return 0;
}

static int
eiawstat(Chan *c, uchar *dp, int n)
{
	Dir d;
	int i;

	if(!iseve())
		error(Eperm);
	if(c->qid.type & QTDIR)
		error(Eperm);
	if(NETTYPE(c->qid.path) == Nstatqid)
		error(Eperm);

	n = convM2D(dp, n, &d, nil);
	i = Nqid*NETID(c->qid.path)+NETTYPE(c->qid.path)-Ndataqid;
	if(d.mode != ~0UL)
		eiadir[i+1].perm = d.mode&0666;
	return n;
}

Dev eiadevtab = {
        Devchar,
        "eia",

        eiainit,
        eiaattach,
        eiawalk,
        eiastat,
        eiaopen,
        devcreate,
        eiaclose,
        eiaread,
        devbread,
        eiawrite,
        devbwrite,
        devremove,
        eiawstat
};


//
// local functions
//

/*
 * open the indicated comm port and then set 
 * the default settings for the port.
 */
static void
openport(int port)
{
	Eia* p = &eia[port];

	// open the port
	p->comfh = CreateFile(sysdev[p->id], 
		GENERIC_READ|GENERIC_WRITE,     //open underlying port for rd/wr
		0,	                            //comm port can't be shared
		NULL,	                        //no security attrs
		OPEN_EXISTING,                  //a must for comm port
		FILE_ATTRIBUTE_NORMAL,          //nonoverlapped io
		NULL);                          //another must for comm port

	if(p->comfh == INVALID_HANDLE_VALUE)
		oserror();
	if(waserror()){
		CloseHandle(p->comfh);
		p->comfh = INVALID_HANDLE_VALUE;
		nexterror();
	}

	// setup in/out buffers (NT requires an even number)
	if(!SetupComm(p->comfh, CommBufSize, CommBufSize))
		oserror();

	// either use existing settings or set defaults
	if(!p->restore) {
		// set default settings
		if(!GetCommState(p->comfh, &p->dcb))
			oserror();
		p->dcb.BaudRate = 9600;
		p->dcb.ByteSize = 8;
		p->dcb.fParity = 0;
		p->dcb.Parity = NOPARITY;
		p->dcb.StopBits = ONESTOPBIT;
		p->dcb.fInX = 0;  //default to xoff
		p->dcb.fOutX = 0;  
		p->dcb.fAbortOnError = 1; //read/write abort on err
	}

	// set state and timeouts
	if(!SetCommState(p->comfh, &p->dcb) ||
	   !SetCommTimeouts(p->comfh, &timeouts))
		oserror();
	poperror();
}

/*
 * Obtain status information on the com port.
 */
static long
rdstat(int port, void *buf, long n, ulong offset)
{
	HANDLE comfh = eia[port].comfh;
	char str[Maxctl];
	char *s;
	DCB dcb;
	DWORD modemstatus;
	DWORD porterr;
	COMSTAT  portstat;
	int frame, overrun, i;

	// valid line control ids
	static enum {
		L_CTS, L_DSR, L_RING, L_DCD, L_DTR, L_RTS, L_MAX
	};
	int status[L_MAX];

	// line control strings (should match above id's)
	static char* lines[] = {
		"cts", "dsr", "ring", "dcd", "dtr",	"rts", NULL
	};


	// get any error conditions; also clears error flag
	// and enables io
	if(!ClearCommError(comfh, &porterr, &portstat))
		oserror();

	// get comm port state
	if(!GetCommState(comfh, &dcb))
		oserror();

	// get modem line information
	if(!GetCommModemStatus(comfh, &modemstatus))
		oserror();

	// now set our local flags
	status[L_CTS] = MS_CTS_ON & modemstatus;
	status[L_DSR] = MS_DSR_ON & modemstatus;
	status[L_RING] = MS_RING_ON & modemstatus;
	status[L_DCD] = MS_RLSD_ON & modemstatus;
	status[L_DTR] = FALSE;  //?? cand this work: dcb.fDtrControl;
	status[L_RTS] = FALSE;  //??   dcb.fRtsControl;
	frame = porterr & CE_FRAME;
	overrun = porterr & CE_OVERRUN;

	/* TO DO: mimic native eia driver's first line */

	s = seprint(str, str+sizeof(str), "opens %d ferr %d oerr %d baud %d", 
		    eia[port].r.ref-1, 
			frame, 
			overrun,
		    dcb.BaudRate);

	// add line settings
	for(i=0; i < L_MAX; i++) 
		if(status[i])
			s = seprint(s, str+sizeof(str), " %s", lines[i]);
	seprint(s, str+sizeof(str), "\n");
	return readstr(offset, buf, n, str);
}

//
// write on ctl file. modify the settings for
// the underlying port.
//
static void
wrctl(int port, char *cmd)
{
	DCB dcb;
	int nf, n,  i;
	char *f[16];
	HANDLE comfh = eia[port].comfh;
	DWORD  flag, opt;
	BOOL   rslt;
	int chg;

	// get the current settings for the port
	if(!GetCommState(comfh, &dcb))
		oserror();

	chg = 0;
	nf = tokenize(cmd, f, nelem(f));
	for(i = 0; i < nf; i++){
		if(strcmp(f[i], "break") == 0){
			if(!SetCommBreak(comfh))
				oserror();
			SleepEx((DWORD)300, FALSE);
			if(!ClearCommBreak(comfh))
				oserror();
			continue;
		}

		n = atoi(f[i]+1);
		switch(*f[i]) {
		case 'B':
		case 'b':	// set the baud rate
			if(n < 110)
				error(Ebadarg);
			dcb.BaudRate = n;
			chg = 1;
			break;
		case 'C':
		case 'c':
			/* dcd */
			break;
		case 'D':
		case 'd':  // set DTR
			opt = n ? SETDTR : CLRDTR;
			if(!EscapeCommFunction(comfh, opt))
				oserror();
			break;
		case 'E':
		case 'e':
			/* dsr */
			break;
		case 'F':
		case 'f':	// flush any untransmitted data
			if(!PurgeComm(comfh, PURGE_TXCLEAR)) 
				oserror();
			break;
		case 'H':
		case 'h':
			/* hangup */
			/* TO DO: close handle */
			break;
		case 'I':
		case 'i':
			/* fifo: nothing to do */
			break;
		case 'K':
		case 'k':
			/* send a break */
			if(!SetCommBreak(comfh))
				oserror();
			SleepEx((DWORD)300, FALSE);
			if(!ClearCommBreak(comfh))
				oserror();
			break;
		case 'L':
		case 'l':	// set bits per byte 
			flag = stof(size, f[0]+1);
			if(flag == BAD)
				error(Ebadarg);
			dcb.ByteSize = (BYTE)flag;
			chg = 1;
			break;
		case 'M':
		case 'm':	// set CTS (modem control)
			dcb.fOutxCtsFlow = (n!=0);
			chg = 1;
			break;
		case 'N':
		case 'n':
			/* don't block on output */
			break;
		case 'P':
		case 'p':	// set parity -- even or odd
			flag = stof(parity, f[0]+1);
			if(flag==BAD)
				error(Ebadarg);
			dcb.Parity = (BYTE)flag;
			chg = 1;
			break;
		case 'Q':
		case 'q':
			/* set i/o queue limits */
			break;
		case 'R':
		case 'r':	// set RTS
			opt = n ? SETRTS : CLRRTS;
			if(!EscapeCommFunction(comfh, opt))
				oserror();
			break;
		case 'S':
		case 's':	// set stop bits -- valid: 1 or 2 (win32 allows 1.5??)
			flag = stof(stopbits, f[0]+1);
			if(flag==BAD)
				error(Ebadarg);
			dcb.StopBits = flag;
			chg = 1;
			break;
		case 'T':
		case 't':
			break;
		case 'W':
		case 'w':
			/* set uart timer */
			break;
		case 'X':
		case 'x':	// xon/xoff
			opt = n ? SETXON : SETXOFF;
			if(!EscapeCommFunction(comfh, opt))
				oserror();
			break;
		default:
			/* ignore */
			break;
		}
	}

	if(!chg)
		return;
	// make the changes on the underlying port, but flush
	// outgoing chars down the port before
	osenter();
	rslt = FlushFileBuffers(comfh);
	if(rslt)
		rslt = SetCommState(comfh, &dcb);
	osleave();
	if(!rslt)
		oserror();
	eia[port].restore = 1;
	eia[port].dcb = dcb;
}
