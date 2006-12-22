typedef struct PPP	PPP;
typedef struct Pstate	Pstate;
typedef struct Lcpmsg	Lcpmsg;
typedef struct Lcpopt	Lcpopt;
typedef struct Qualpkt	Qualpkt;
typedef struct Qualstats Qualstats;
typedef struct Tcpc	Tcpc;

typedef uchar Ipaddr[IPaddrlen];

enum
{
	HDLC_frame=	0x7e,
	HDLC_esc=	0x7d,

	/* PPP frame fields */
	PPP_addr=	0xff,
	PPP_ctl=	0x3,
	PPP_initfcs=	0xffff,
	PPP_goodfcs=	0xf0b8,

	/* PPP phases */
	Pdead=		0,	
	Plink,				/* doing LCP */
	Pauth,				/* doing chap */
	Pnet,				/* doing IPCP, CCP */
	Pterm,				/* closing down */

	/* PPP protocol types */
	Pip=		0x21,		/* internet */
	Pvjctcp=	0x2d,		/* compressing van jacobson tcp */
	Pvjutcp=	0x2f,		/* uncompressing van jacobson tcp */
	Pcdata=		0xfd,		/* compressed datagram */
	Pipcp=		0x8021,		/* ip control */
	Pecp=		0x8053,		/* encryption control */
	Pccp=		0x80fd,		/* compressed datagram control */
	Plcp=		0xc021,		/* link control */
	Ppap=		0xc023,		/* password auth. protocol */
	Plqm=		0xc025,		/* link quality monitoring */
	Pchap=		0xc223,		/* challenge/response */

	/* LCP codes */
	Lconfreq=	1,
	Lconfack=	2,
	Lconfnak=	3,
	Lconfrej=	4,
	Ltermreq=	5,
	Ltermack=	6,
	Lcoderej=	7,
	Lprotorej=	8,
	Lechoreq=	9,
	Lechoack=	10,
	Ldiscard=	11,

	/* Lcp configure options */
	Omtu=		1,
	Octlmap=	2,
	Oauth=		3,
	Oquality=	4,
	Omagic=		5,
	Opc=		7,
	Oac=		8,
	Obad=		12,		/* for testing */

	/* authentication protocols */
	APmd5=		5,

	/* lcp flags */
	Fmtu=		1<<Omtu,
	Fctlmap=	1<<Octlmap,
	Fauth=		1<<Oauth,
	Fquality=	1<<Oquality,
	Fmagic=		1<<Omagic,
	Fpc=		1<<Opc,
	Fac=		1<<Oac,
	Fbad=		1<<Obad,

	/* Chap codes */
	Cchallenge=	1,
	Cresponse=	2,
	Csuccess=	3,
	Cfailure=	4,

	/* Pap codes */
	Cpapreq=		1,
	Cpapack=		2,
	Cpapnak=		3,

	/* link states */
	Sclosed=		0,
	Sclosing,
	Sreqsent,
	Sackrcvd,
	Sacksent,
	Sopened,

	/* ccp configure options */
	Ocoui=		0,	/* proprietary compression */
	Ocstac=		17,	/* stac electronics LZS */
	Ocmppc=		18,	/* microsoft ppc */

	/* ccp flags */
	Fcoui=		1<<Ocoui,
	Fcstac=		1<<Ocstac,
	Fcmppc=		1<<Ocmppc,

	/* ecp configure options */
	Oeoui=		0,	/* proprietary compression */
	Oedese=		1,	/* DES */

	/* ecp flags */
	Feoui=		1<<Oeoui,
	Fedese=		1<<Oedese,

	/* ipcp configure options */
	Oipaddrs=	1,
	Oipcompress=	2,
	Oipaddr=	3,
	Oipdns=		129,
	Oipwins=	130,
	Oipdns2=	131,
	Oipwins2=	132,

	/* ipcp flags */
	Fipaddrs=	1<<Oipaddrs,
	Fipcompress=	1<<Oipcompress,
	Fipaddr=	1<<Oipaddr,

	Period=		3*1000,	/* period of retransmit process (in ms) */
	Timeout=	10,	/* xmit timeout (in Periods) */

	MAX_STATES	= 16,		/* van jacobson compression states */
	Defmtu=		1450,		/* default that we will ask for */
	Minmtu=		128,		/* minimum that we will accept */
	Maxmtu=		2000,		/* maximum that we will accept */
};


struct Pstate
{
	int	proto;		/* protocol type */
	int	timeout;		/* for current state */
	int	rxtimeout;	/* for current retransmit */
	ulong	flags;		/* options received */
	uchar	id;		/* id of current message */
	uchar	confid;		/* id of current config message */
	uchar	termid;		/* id of current termination message */
	uchar	rcvdconfid;	/* id of last conf message received */
	uchar	state;		/* PPP link state */
	ulong	optmask;		/* which options to request */
	int	echoack;	/* recieved echo ack */
	int	echotimeout;	/* echo timeout */
};

struct Qualstats
{
	ulong	reports;
	ulong	packets;
	ulong	bytes;
	ulong	discards;
	ulong	errors;
};

struct PPP
{
	QLock;

	Chan*	dchan;			/* serial line */
	Chan*	cchan;			/* serial line control */
	int		framing;	/* non-zero to use framing characters */
	Ipaddr	local;
	int		localfrozen;
	Ipaddr	remote;
	int		remotefrozen;

	int	pppup;
	Fs	*f;		/* file system we belong to */
	Ipifc*	ifc;
	Proc*	readp;			/* reading process */
	Proc*	timep;			/* timer process */
	Block*	inbuf;			/* input buffer */
	Block*	outbuf;			/* output buffer */
	QLock	outlock;		/*  and its lock */

	ulong	magic;			/* magic number to detect loop backs */
	ulong	rctlmap;		/* map of chars to ignore in rcvr */
	ulong	xctlmap;		/* map of chars to excape in xmit */
	int		phase;		/* PPP phase */
	Pstate*	lcp;			/* lcp state */
	Pstate*	ipcp;			/* ipcp state */
	char	secret[256];		/* md5 key */
	char	chapname[256];		/* chap system name */
	Tcpc*	ctcp;
	ulong		mtu;		/* maximum xmit size */
	ulong		mru;		/* maximum recv size */

	int	baud;
	int	usepap;	/* authentication is PAP in every sense, not CHAP */
	int	papid;
	int	usechap;

	/* rfc */
	int	usedns;
	Ipaddr	dns1;
	Ipaddr	dns2;

	/* link quality monitoring */
	int		period;		/* lqm period */
	int		timeout;	/* time to next lqm packet */
	Qualstats	in;		/* local */
	Qualstats	out;
	Qualstats	pin;		/* peer */
	Qualstats	pout;
	Qualstats	sin;		/* saved */
};

PPP*		pppopen(PPP*, char*, Ipaddr, Ipaddr, int, int, char*, char*);
Block*	pppread(PPP*);
int		pppwrite(PPP*, Block*);
void		pppclose(PPP*);

struct Lcpmsg
{
	uchar	code;
	uchar	id;
	uchar	len[2];
	uchar	data[1];
};

struct Lcpopt
{
	uchar	type;
	uchar	len;
	uchar	data[1];
};

struct Qualpkt
{
	uchar	magic[4];

	uchar	lastoutreports[4];
	uchar	lastoutpackets[4];
	uchar	lastoutbytes[4];
	uchar	peerinreports[4];
	uchar	peerinpackets[4];
	uchar	peerindiscards[4];
	uchar	peerinerrors[4];
	uchar	peerinbytes[4];
	uchar	peeroutreports[4];
	uchar	peeroutpackets[4];
	uchar	peeroutbytes[4];
};

ushort	compress(Tcpc*, Block*, Fs*);
Tcpc*	compress_init(Tcpc*);
int		compress_negotiate(Tcpc*, uchar*);
ushort	tcpcompress(Tcpc*, Block*, Fs*);
Block*	tcpuncompress(Tcpc*, Block*, ushort, Fs*);
