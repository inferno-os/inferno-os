typedef struct Sys_Qid Sys_Qid;
typedef struct Sys_Dir Sys_Dir;
typedef struct Sys_FD Sys_FD;
typedef struct Sys_Connection Sys_Connection;
typedef struct Sys_FileIO Sys_FileIO;
typedef struct Keyring_IPint Keyring_IPint;
typedef struct Keyring_SigAlg Keyring_SigAlg;
typedef struct Keyring_PK Keyring_PK;
typedef struct Keyring_SK Keyring_SK;
typedef struct Keyring_Certificate Keyring_Certificate;
typedef struct Keyring_DigestState Keyring_DigestState;
typedef struct Keyring_AESstate Keyring_AESstate;
typedef struct Keyring_AESGCMstate Keyring_AESGCMstate;
typedef struct Keyring_ChaChastate Keyring_ChaChastate;
typedef struct Keyring_ECpoint Keyring_ECpoint;
typedef struct Keyring_DESstate Keyring_DESstate;
typedef struct Keyring_IDEAstate Keyring_IDEAstate;
typedef struct Keyring_RC4state Keyring_RC4state;
typedef struct Keyring_BFstate Keyring_BFstate;
typedef struct Keyring_Authinfo Keyring_Authinfo;
typedef struct Keyring_RSApk Keyring_RSApk;
typedef struct Keyring_RSAsk Keyring_RSAsk;
typedef struct Keyring_RSAsig Keyring_RSAsig;
typedef struct Keyring_DSApk Keyring_DSApk;
typedef struct Keyring_DSAsk Keyring_DSAsk;
typedef struct Keyring_DSAsig Keyring_DSAsig;
typedef struct Keyring_EGpk Keyring_EGpk;
typedef struct Keyring_EGsk Keyring_EGsk;
typedef struct Keyring_EGsig Keyring_EGsig;
struct Sys_Qid
{
	LONG	path;
	WORD	vers;
	WORD	qtype;
};
#define Sys_Qid_size 24
#define Sys_Qid_map {0}
struct Sys_Dir
{
	String*	name;
	String*	uid;
	String*	gid;
	String*	muid;
	Sys_Qid	qid;
	WORD	mode;
	WORD	atime;
	WORD	mtime;
	LONG	length;
	WORD	dtype;
	WORD	dev;
};
#define Sys_Dir_size 104
#define Sys_Dir_map {0xf0,}
struct Sys_FD
{
	WORD	fd;
};
#define Sys_FD_size 8
#define Sys_FD_map {0}
struct Sys_Connection
{
	Sys_FD*	dfd;
	Sys_FD*	cfd;
	String*	dir;
};
#define Sys_Connection_size 24
#define Sys_Connection_map {0xe0,}
typedef struct{ Array* t0; String* t1; } Sys_Rread;
#define Sys_Rread_size 16
#define Sys_Rread_map {0xc0,}
typedef struct{ WORD t0; String* t1; } Sys_Rwrite;
#define Sys_Rwrite_size 16
#define Sys_Rwrite_map {0x40,}
struct Sys_FileIO
{
	Channel*	read;
	Channel*	write;
};
typedef struct{ WORD t0; WORD t1; WORD t2; Channel* t3; } Sys_FileIO_read;
#define Sys_FileIO_read_size 32
#define Sys_FileIO_read_map {0x10,}
typedef struct{ WORD t0; Array* t1; WORD t2; Channel* t3; } Sys_FileIO_write;
#define Sys_FileIO_write_size 32
#define Sys_FileIO_write_map {0x50,}
#define Sys_FileIO_size 16
#define Sys_FileIO_map {0xc0,}
struct Keyring_IPint
{
	WORD	x;
};
#define Keyring_IPint_size 8
#define Keyring_IPint_map {0}
struct Keyring_SigAlg
{
	String*	name;
};
#define Keyring_SigAlg_size 8
#define Keyring_SigAlg_map {0x80,}
struct Keyring_PK
{
	Keyring_SigAlg*	sa;
	String*	owner;
};
#define Keyring_PK_size 16
#define Keyring_PK_map {0xc0,}
struct Keyring_SK
{
	Keyring_SigAlg*	sa;
	String*	owner;
};
#define Keyring_SK_size 16
#define Keyring_SK_map {0xc0,}
struct Keyring_Certificate
{
	Keyring_SigAlg*	sa;
	String*	ha;
	String*	signer;
	WORD	exp;
};
#define Keyring_Certificate_size 32
#define Keyring_Certificate_map {0xe0,}
struct Keyring_DigestState
{
	WORD	x;
};
#define Keyring_DigestState_size 8
#define Keyring_DigestState_map {0}
struct Keyring_AESstate
{
	WORD	x;
};
#define Keyring_AESstate_size 8
#define Keyring_AESstate_map {0}
struct Keyring_AESGCMstate
{
	WORD	x;
};
#define Keyring_AESGCMstate_size 8
#define Keyring_AESGCMstate_map {0}
struct Keyring_ChaChastate
{
	WORD	x;
};
#define Keyring_ChaChastate_size 8
#define Keyring_ChaChastate_map {0}
struct Keyring_ECpoint
{
	WORD	x;
};
#define Keyring_ECpoint_size 8
#define Keyring_ECpoint_map {0}
struct Keyring_DESstate
{
	WORD	x;
};
#define Keyring_DESstate_size 8
#define Keyring_DESstate_map {0}
struct Keyring_IDEAstate
{
	WORD	x;
};
#define Keyring_IDEAstate_size 8
#define Keyring_IDEAstate_map {0}
struct Keyring_RC4state
{
	WORD	x;
};
#define Keyring_RC4state_size 8
#define Keyring_RC4state_map {0}
struct Keyring_BFstate
{
	WORD	x;
};
#define Keyring_BFstate_size 8
#define Keyring_BFstate_map {0}
struct Keyring_Authinfo
{
	Keyring_SK*	mysk;
	Keyring_PK*	mypk;
	Keyring_Certificate*	cert;
	Keyring_PK*	spk;
	Keyring_IPint*	alpha;
	Keyring_IPint*	p;
};
#define Keyring_Authinfo_size 48
#define Keyring_Authinfo_map {0xfc,}
struct Keyring_RSApk
{
	Keyring_IPint*	n;
	Keyring_IPint*	ek;
};
#define Keyring_RSApk_size 16
#define Keyring_RSApk_map {0xc0,}
struct Keyring_RSAsk
{
	Keyring_RSApk*	pk;
	Keyring_IPint*	dk;
	Keyring_IPint*	p;
	Keyring_IPint*	q;
	Keyring_IPint*	kp;
	Keyring_IPint*	kq;
	Keyring_IPint*	c2;
};
#define Keyring_RSAsk_size 56
#define Keyring_RSAsk_map {0xfe,}
struct Keyring_RSAsig
{
	Keyring_IPint*	n;
};
#define Keyring_RSAsig_size 8
#define Keyring_RSAsig_map {0x80,}
struct Keyring_DSApk
{
	Keyring_IPint*	p;
	Keyring_IPint*	q;
	Keyring_IPint*	alpha;
	Keyring_IPint*	key;
};
#define Keyring_DSApk_size 32
#define Keyring_DSApk_map {0xf0,}
struct Keyring_DSAsk
{
	Keyring_DSApk*	pk;
	Keyring_IPint*	secret;
};
#define Keyring_DSAsk_size 16
#define Keyring_DSAsk_map {0xc0,}
struct Keyring_DSAsig
{
	Keyring_IPint*	r;
	Keyring_IPint*	s;
};
#define Keyring_DSAsig_size 16
#define Keyring_DSAsig_map {0xc0,}
struct Keyring_EGpk
{
	Keyring_IPint*	p;
	Keyring_IPint*	alpha;
	Keyring_IPint*	key;
};
#define Keyring_EGpk_size 24
#define Keyring_EGpk_map {0xe0,}
struct Keyring_EGsk
{
	Keyring_EGpk*	pk;
	Keyring_IPint*	secret;
};
#define Keyring_EGsk_size 16
#define Keyring_EGsk_map {0xc0,}
struct Keyring_EGsig
{
	Keyring_IPint*	r;
	Keyring_IPint*	s;
};
#define Keyring_EGsig_size 16
#define Keyring_EGsig_map {0xc0,}
void Sys_announce(void*);
typedef struct F_Sys_announce F_Sys_announce;
struct F_Sys_announce
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Connection t1; }*	ret;
	uchar	temps[24];
	String*	addr;
};
void Sys_aprint(void*);
typedef struct F_Sys_aprint F_Sys_aprint;
struct F_Sys_aprint
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	String*	s;
	WORD	vargs;
};
void Sys_bind(void*);
typedef struct F_Sys_bind F_Sys_bind;
struct F_Sys_bind
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	String*	s;
	String*	on;
	WORD	flags;
};
void Sys_byte2char(void*);
typedef struct F_Sys_byte2char F_Sys_byte2char;
struct F_Sys_byte2char
{
	WORD	regs[NREG-1];
	struct{ WORD t0; WORD t1; WORD t2; }*	ret;
	uchar	temps[24];
	Array*	buf;
	WORD	n;
};
void Sys_char2byte(void*);
typedef struct F_Sys_char2byte F_Sys_char2byte;
struct F_Sys_char2byte
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	WORD	c;
	Array*	buf;
	WORD	n;
};
void Sys_chdir(void*);
typedef struct F_Sys_chdir F_Sys_chdir;
struct F_Sys_chdir
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	String*	path;
};
void Sys_create(void*);
typedef struct F_Sys_create F_Sys_create;
struct F_Sys_create
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[24];
	String*	s;
	WORD	mode;
	WORD	perm;
};
void Sys_dial(void*);
typedef struct F_Sys_dial F_Sys_dial;
struct F_Sys_dial
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Connection t1; }*	ret;
	uchar	temps[24];
	String*	addr;
	String*	local;
};
void Sys_dirread(void*);
typedef struct F_Sys_dirread F_Sys_dirread;
struct F_Sys_dirread
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Array* t1; }*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
};
void Sys_dup(void*);
typedef struct F_Sys_dup F_Sys_dup;
struct F_Sys_dup
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	WORD	old;
	WORD	new;
};
void Sys_export(void*);
typedef struct F_Sys_export F_Sys_export;
struct F_Sys_export
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	c;
	String*	dir;
	WORD	flag;
};
void Sys_fauth(void*);
typedef struct F_Sys_fauth F_Sys_fauth;
struct F_Sys_fauth
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	String*	aname;
};
void Sys_fd2path(void*);
typedef struct F_Sys_fd2path F_Sys_fd2path;
struct F_Sys_fd2path
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[24];
	Sys_FD*	fd;
};
void Sys_fildes(void*);
typedef struct F_Sys_fildes F_Sys_fildes;
struct F_Sys_fildes
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[24];
	WORD	fd;
};
void Sys_file2chan(void*);
typedef struct F_Sys_file2chan F_Sys_file2chan;
struct F_Sys_file2chan
{
	WORD	regs[NREG-1];
	Sys_FileIO**	ret;
	uchar	temps[24];
	String*	dir;
	String*	file;
};
void Sys_fprint(void*);
typedef struct F_Sys_fprint F_Sys_fprint;
struct F_Sys_fprint
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	String*	s;
	WORD	vargs;
};
void Sys_fstat(void*);
typedef struct F_Sys_fstat F_Sys_fstat;
struct F_Sys_fstat
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Dir t1; }*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
};
void Sys_fversion(void*);
typedef struct F_Sys_fversion F_Sys_fversion;
struct F_Sys_fversion
{
	WORD	regs[NREG-1];
	struct{ WORD t0; String* t1; }*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	WORD	msize;
	String*	version;
};
void Sys_fwstat(void*);
typedef struct F_Sys_fwstat F_Sys_fwstat;
struct F_Sys_fwstat
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	Sys_Dir	d;
};
void Sys_iounit(void*);
typedef struct F_Sys_iounit F_Sys_iounit;
struct F_Sys_iounit
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
};
void Sys_listen(void*);
typedef struct F_Sys_listen F_Sys_listen;
struct F_Sys_listen
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Connection t1; }*	ret;
	uchar	temps[24];
	Sys_Connection	c;
};
void Sys_millisec(void*);
typedef struct F_Sys_millisec F_Sys_millisec;
struct F_Sys_millisec
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
};
void Sys_mount(void*);
typedef struct F_Sys_mount F_Sys_mount;
struct F_Sys_mount
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	Sys_FD*	afd;
	String*	on;
	WORD	flags;
	String*	spec;
};
void Sys_open(void*);
typedef struct F_Sys_open F_Sys_open;
struct F_Sys_open
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[24];
	String*	s;
	WORD	mode;
};
void Sys_pctl(void*);
typedef struct F_Sys_pctl F_Sys_pctl;
struct F_Sys_pctl
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	WORD	flags;
	List*	movefd;
};
void Sys_pipe(void*);
typedef struct F_Sys_pipe F_Sys_pipe;
struct F_Sys_pipe
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Array*	fds;
};
void Sys_pread(void*);
typedef struct F_Sys_pread F_Sys_pread;
struct F_Sys_pread
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
	LONG	off;
};
void Sys_print(void*);
typedef struct F_Sys_print F_Sys_print;
struct F_Sys_print
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	String*	s;
	WORD	vargs;
};
void Sys_pwrite(void*);
typedef struct F_Sys_pwrite F_Sys_pwrite;
struct F_Sys_pwrite
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
	LONG	off;
};
void Sys_read(void*);
typedef struct F_Sys_read F_Sys_read;
struct F_Sys_read
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Sys_readn(void*);
typedef struct F_Sys_readn F_Sys_readn;
struct F_Sys_readn
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Sys_remove(void*);
typedef struct F_Sys_remove F_Sys_remove;
struct F_Sys_remove
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	String*	s;
};
void Sys_seek(void*);
typedef struct F_Sys_seek F_Sys_seek;
struct F_Sys_seek
{
	WORD	regs[NREG-1];
	LONG*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	LONG	off;
	WORD	start;
};
void Sys_sleep(void*);
typedef struct F_Sys_sleep F_Sys_sleep;
struct F_Sys_sleep
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	WORD	period;
};
void Sys_sprint(void*);
typedef struct F_Sys_sprint F_Sys_sprint;
struct F_Sys_sprint
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[24];
	String*	s;
	WORD	vargs;
};
void Sys_stat(void*);
typedef struct F_Sys_stat F_Sys_stat;
struct F_Sys_stat
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Dir t1; }*	ret;
	uchar	temps[24];
	String*	s;
};
void Sys_stream(void*);
typedef struct F_Sys_stream F_Sys_stream;
struct F_Sys_stream
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	src;
	Sys_FD*	dst;
	WORD	bufsiz;
};
void Sys_tokenize(void*);
typedef struct F_Sys_tokenize F_Sys_tokenize;
struct F_Sys_tokenize
{
	WORD	regs[NREG-1];
	struct{ WORD t0; List* t1; }*	ret;
	uchar	temps[24];
	String*	s;
	String*	delim;
};
void Sys_unmount(void*);
typedef struct F_Sys_unmount F_Sys_unmount;
struct F_Sys_unmount
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	String*	s1;
	String*	s2;
};
void Sys_utfbytes(void*);
typedef struct F_Sys_utfbytes F_Sys_utfbytes;
struct F_Sys_utfbytes
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Array*	buf;
	WORD	n;
};
void Sys_werrstr(void*);
typedef struct F_Sys_werrstr F_Sys_werrstr;
struct F_Sys_werrstr
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	String*	s;
};
void Sys_write(void*);
typedef struct F_Sys_write F_Sys_write;
struct F_Sys_write
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Sys_wstat(void*);
typedef struct F_Sys_wstat F_Sys_wstat;
struct F_Sys_wstat
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	String*	s;
	Sys_Dir	d;
};
#define Sys_PATH "$Sys"
#define Sys_Maxint 2147483647
#define Sys_QTDIR 128
#define Sys_QTAPPEND 64
#define Sys_QTEXCL 32
#define Sys_QTAUTH 8
#define Sys_QTTMP 4
#define Sys_QTFILE 0
#define Sys_ATOMICIO 8192
#define Sys_SEEKSTART 0
#define Sys_SEEKRELA 1
#define Sys_SEEKEND 2
#define Sys_NAMEMAX 256
#define Sys_ERRMAX 128
#define Sys_WAITLEN 192
#define Sys_OREAD 0
#define Sys_OWRITE 1
#define Sys_ORDWR 2
#define Sys_OTRUNC 16
#define Sys_ORCLOSE 64
#define Sys_OEXCL 4096
#define Sys_DMDIR -2147483648
#define Sys_DMAPPEND 1073741824
#define Sys_DMEXCL 536870912
#define Sys_DMAUTH 134217728
#define Sys_DMTMP 67108864
#define Sys_MREPL 0
#define Sys_MBEFORE 1
#define Sys_MAFTER 2
#define Sys_MCREATE 4
#define Sys_MCACHE 16
#define Sys_NEWFD 1
#define Sys_FORKFD 2
#define Sys_NEWNS 4
#define Sys_FORKNS 8
#define Sys_NEWPGRP 16
#define Sys_NODEVS 32
#define Sys_NEWENV 64
#define Sys_FORKENV 128
#define Sys_EXPWAIT 0
#define Sys_EXPASYNC 1
#define Sys_UTFmax 3
#define Sys_UTFerror 128
void IPint_add(void*);
typedef struct F_IPint_add F_IPint_add;
struct F_IPint_add
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void Keyring_aescbc(void*);
typedef struct F_Keyring_aescbc F_Keyring_aescbc;
struct F_Keyring_aescbc
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[24];
	Keyring_AESstate*	state;
	Array*	buf;
	WORD	n;
	WORD	direction;
};
void Keyring_aesgcmdecrypt(void*);
typedef struct F_Keyring_aesgcmdecrypt F_Keyring_aesgcmdecrypt;
struct F_Keyring_aesgcmdecrypt
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Keyring_AESGCMstate*	state;
	Array*	dat;
	Array*	aad;
	Array*	tag;
};
void Keyring_aesgcmencrypt(void*);
typedef struct F_Keyring_aesgcmencrypt F_Keyring_aesgcmencrypt;
struct F_Keyring_aesgcmencrypt
{
	WORD	regs[NREG-1];
	struct{ Array* t0; Array* t1; }*	ret;
	uchar	temps[24];
	Keyring_AESGCMstate*	state;
	Array*	dat;
	Array*	aad;
};
void Keyring_aesgcmsetup(void*);
typedef struct F_Keyring_aesgcmsetup F_Keyring_aesgcmsetup;
struct F_Keyring_aesgcmsetup
{
	WORD	regs[NREG-1];
	Keyring_AESGCMstate**	ret;
	uchar	temps[24];
	Array*	key;
	Array*	iv;
};
void Keyring_aessetup(void*);
typedef struct F_Keyring_aessetup F_Keyring_aessetup;
struct F_Keyring_aessetup
{
	WORD	regs[NREG-1];
	Keyring_AESstate**	ret;
	uchar	temps[24];
	Array*	key;
	Array*	ivec;
};
void IPint_and(void*);
typedef struct F_IPint_and F_IPint_and;
struct F_IPint_and
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void Keyring_auth(void*);
typedef struct F_Keyring_auth F_Keyring_auth;
struct F_Keyring_auth
{
	WORD	regs[NREG-1];
	struct{ String* t0; Array* t1; }*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	Keyring_Authinfo*	info;
	WORD	setid;
};
void IPint_b64toip(void*);
typedef struct F_IPint_b64toip F_IPint_b64toip;
struct F_IPint_b64toip
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	String*	str;
};
void IPint_bebytestoip(void*);
typedef struct F_IPint_bebytestoip F_IPint_bebytestoip;
struct F_IPint_bebytestoip
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Array*	mag;
};
void IPint_bits(void*);
typedef struct F_IPint_bits F_IPint_bits;
struct F_IPint_bits
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Keyring_IPint*	i;
};
void Keyring_blowfishcbc(void*);
typedef struct F_Keyring_blowfishcbc F_Keyring_blowfishcbc;
struct F_Keyring_blowfishcbc
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[24];
	Keyring_BFstate*	state;
	Array*	buf;
	WORD	n;
	WORD	direction;
};
void Keyring_blowfishsetup(void*);
typedef struct F_Keyring_blowfishsetup F_Keyring_blowfishsetup;
struct F_Keyring_blowfishsetup
{
	WORD	regs[NREG-1];
	Keyring_BFstate**	ret;
	uchar	temps[24];
	Array*	key;
	Array*	ivec;
};
void IPint_bytestoip(void*);
typedef struct F_IPint_bytestoip F_IPint_bytestoip;
struct F_IPint_bytestoip
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Array*	buf;
};
void Keyring_ccpolydecrypt(void*);
typedef struct F_Keyring_ccpolydecrypt F_Keyring_ccpolydecrypt;
struct F_Keyring_ccpolydecrypt
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Array*	dat;
	Array*	aad;
	Array*	tag;
	Array*	key;
	Array*	nonce;
};
void Keyring_ccpolyencrypt(void*);
typedef struct F_Keyring_ccpolyencrypt F_Keyring_ccpolyencrypt;
struct F_Keyring_ccpolyencrypt
{
	WORD	regs[NREG-1];
	struct{ Array* t0; Array* t1; }*	ret;
	uchar	temps[24];
	Array*	dat;
	Array*	aad;
	Array*	key;
	Array*	nonce;
};
void Keyring_certtoattr(void*);
typedef struct F_Keyring_certtoattr F_Keyring_certtoattr;
struct F_Keyring_certtoattr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[24];
	Keyring_Certificate*	c;
};
void Keyring_certtostr(void*);
typedef struct F_Keyring_certtostr F_Keyring_certtostr;
struct F_Keyring_certtostr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[24];
	Keyring_Certificate*	c;
};
void IPint_cmp(void*);
typedef struct F_IPint_cmp F_IPint_cmp;
struct F_IPint_cmp
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void IPint_copy(void*);
typedef struct F_IPint_copy F_IPint_copy;
struct F_IPint_copy
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	i;
};
void DigestState_copy(void*);
typedef struct F_DigestState_copy F_DigestState_copy;
struct F_DigestState_copy
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Keyring_DigestState*	d;
};
void RSAsk_decrypt(void*);
typedef struct F_RSAsk_decrypt F_RSAsk_decrypt;
struct F_RSAsk_decrypt
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_RSAsk*	k;
	Keyring_IPint*	m;
};
void Keyring_descbc(void*);
typedef struct F_Keyring_descbc F_Keyring_descbc;
struct F_Keyring_descbc
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[24];
	Keyring_DESstate*	state;
	Array*	buf;
	WORD	n;
	WORD	direction;
};
void Keyring_desecb(void*);
typedef struct F_Keyring_desecb F_Keyring_desecb;
struct F_Keyring_desecb
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[24];
	Keyring_DESstate*	state;
	Array*	buf;
	WORD	n;
	WORD	direction;
};
void Keyring_dessetup(void*);
typedef struct F_Keyring_dessetup F_Keyring_dessetup;
struct F_Keyring_dessetup
{
	WORD	regs[NREG-1];
	Keyring_DESstate**	ret;
	uchar	temps[24];
	Array*	key;
	Array*	ivec;
};
void Keyring_dhparams(void*);
typedef struct F_Keyring_dhparams F_Keyring_dhparams;
struct F_Keyring_dhparams
{
	WORD	regs[NREG-1];
	struct{ Keyring_IPint* t0; Keyring_IPint* t1; }*	ret;
	uchar	temps[24];
	WORD	nbits;
};
void IPint_div(void*);
typedef struct F_IPint_div F_IPint_div;
struct F_IPint_div
{
	WORD	regs[NREG-1];
	struct{ Keyring_IPint* t0; Keyring_IPint* t1; }*	ret;
	uchar	temps[24];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void Keyring_ed25519_sign(void*);
typedef struct F_Keyring_ed25519_sign F_Keyring_ed25519_sign;
struct F_Keyring_ed25519_sign
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Array*	seed;
	Array*	msg;
};
void Keyring_ed25519_verify(void*);
typedef struct F_Keyring_ed25519_verify F_Keyring_ed25519_verify;
struct F_Keyring_ed25519_verify
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Array*	pk;
	Array*	msg;
	Array*	sig;
};
void RSApk_encrypt(void*);
typedef struct F_RSApk_encrypt F_RSApk_encrypt;
struct F_RSApk_encrypt
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_RSApk*	k;
	Keyring_IPint*	m;
};
void IPint_eq(void*);
typedef struct F_IPint_eq F_IPint_eq;
struct F_IPint_eq
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void IPint_expmod(void*);
typedef struct F_IPint_expmod F_IPint_expmod;
struct F_IPint_expmod
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	base;
	Keyring_IPint*	exp;
	Keyring_IPint*	mod;
};
void RSAsk_fill(void*);
typedef struct F_RSAsk_fill F_RSAsk_fill;
struct F_RSAsk_fill
{
	WORD	regs[NREG-1];
	Keyring_RSAsk**	ret;
	uchar	temps[24];
	Keyring_IPint*	n;
	Keyring_IPint*	e;
	Keyring_IPint*	d;
	Keyring_IPint*	p;
	Keyring_IPint*	q;
};
void RSAsk_gen(void*);
typedef struct F_RSAsk_gen F_RSAsk_gen;
struct F_RSAsk_gen
{
	WORD	regs[NREG-1];
	Keyring_RSAsk**	ret;
	uchar	temps[24];
	WORD	nlen;
	WORD	elen;
	WORD	nrep;
};
void DSAsk_gen(void*);
typedef struct F_DSAsk_gen F_DSAsk_gen;
struct F_DSAsk_gen
{
	WORD	regs[NREG-1];
	Keyring_DSAsk**	ret;
	uchar	temps[24];
	Keyring_DSApk*	oldpk;
};
void EGsk_gen(void*);
typedef struct F_EGsk_gen F_EGsk_gen;
struct F_EGsk_gen
{
	WORD	regs[NREG-1];
	Keyring_EGsk**	ret;
	uchar	temps[24];
	WORD	nlen;
	WORD	nrep;
};
void Keyring_genSK(void*);
typedef struct F_Keyring_genSK F_Keyring_genSK;
struct F_Keyring_genSK
{
	WORD	regs[NREG-1];
	Keyring_SK**	ret;
	uchar	temps[24];
	String*	algname;
	String*	owner;
	WORD	length;
};
void Keyring_genSKfromPK(void*);
typedef struct F_Keyring_genSKfromPK F_Keyring_genSKfromPK;
struct F_Keyring_genSKfromPK
{
	WORD	regs[NREG-1];
	Keyring_SK**	ret;
	uchar	temps[24];
	Keyring_PK*	pk;
	String*	owner;
};
void Keyring_getbytearray(void*);
typedef struct F_Keyring_getbytearray F_Keyring_getbytearray;
struct F_Keyring_getbytearray
{
	WORD	regs[NREG-1];
	struct{ Array* t0; String* t1; }*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
};
void Keyring_getmsg(void*);
typedef struct F_Keyring_getmsg F_Keyring_getmsg;
struct F_Keyring_getmsg
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Sys_FD*	fd;
};
void Keyring_getstring(void*);
typedef struct F_Keyring_getstring F_Keyring_getstring;
struct F_Keyring_getstring
{
	WORD	regs[NREG-1];
	struct{ String* t0; String* t1; }*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
};
void Keyring_hmac_md5(void*);
typedef struct F_Keyring_hmac_md5 F_Keyring_hmac_md5;
struct F_Keyring_hmac_md5
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Array*	data;
	WORD	n;
	Array*	key;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_hmac_sha1(void*);
typedef struct F_Keyring_hmac_sha1 F_Keyring_hmac_sha1;
struct F_Keyring_hmac_sha1
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Array*	data;
	WORD	n;
	Array*	key;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_hmac_sha256(void*);
typedef struct F_Keyring_hmac_sha256 F_Keyring_hmac_sha256;
struct F_Keyring_hmac_sha256
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Array*	data;
	WORD	n;
	Array*	key;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_hmac_sha384(void*);
typedef struct F_Keyring_hmac_sha384 F_Keyring_hmac_sha384;
struct F_Keyring_hmac_sha384
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Array*	data;
	WORD	n;
	Array*	key;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_hmac_sha512(void*);
typedef struct F_Keyring_hmac_sha512 F_Keyring_hmac_sha512;
struct F_Keyring_hmac_sha512
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Array*	data;
	WORD	n;
	Array*	key;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_ideacbc(void*);
typedef struct F_Keyring_ideacbc F_Keyring_ideacbc;
struct F_Keyring_ideacbc
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[24];
	Keyring_IDEAstate*	state;
	Array*	buf;
	WORD	n;
	WORD	direction;
};
void Keyring_ideaecb(void*);
typedef struct F_Keyring_ideaecb F_Keyring_ideaecb;
struct F_Keyring_ideaecb
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[24];
	Keyring_IDEAstate*	state;
	Array*	buf;
	WORD	n;
	WORD	direction;
};
void Keyring_ideasetup(void*);
typedef struct F_Keyring_ideasetup F_Keyring_ideasetup;
struct F_Keyring_ideasetup
{
	WORD	regs[NREG-1];
	Keyring_IDEAstate**	ret;
	uchar	temps[24];
	Array*	key;
	Array*	ivec;
};
void IPint_inttoip(void*);
typedef struct F_IPint_inttoip F_IPint_inttoip;
struct F_IPint_inttoip
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	WORD	i;
};
void IPint_invert(void*);
typedef struct F_IPint_invert F_IPint_invert;
struct F_IPint_invert
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	base;
	Keyring_IPint*	mod;
};
void IPint_iptob64(void*);
typedef struct F_IPint_iptob64 F_IPint_iptob64;
struct F_IPint_iptob64
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[24];
	Keyring_IPint*	i;
};
void IPint_iptob64z(void*);
typedef struct F_IPint_iptob64z F_IPint_iptob64z;
struct F_IPint_iptob64z
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[24];
	Keyring_IPint*	i;
};
void IPint_iptobebytes(void*);
typedef struct F_IPint_iptobebytes F_IPint_iptobebytes;
struct F_IPint_iptobebytes
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Keyring_IPint*	i;
};
void IPint_iptobytes(void*);
typedef struct F_IPint_iptobytes F_IPint_iptobytes;
struct F_IPint_iptobytes
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Keyring_IPint*	i;
};
void IPint_iptoint(void*);
typedef struct F_IPint_iptoint F_IPint_iptoint;
struct F_IPint_iptoint
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Keyring_IPint*	i;
};
void IPint_iptostr(void*);
typedef struct F_IPint_iptostr F_IPint_iptostr;
struct F_IPint_iptostr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[24];
	Keyring_IPint*	i;
	WORD	base;
};
void Keyring_keccak256(void*);
typedef struct F_Keyring_keccak256 F_Keyring_keccak256;
struct F_Keyring_keccak256
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Array*	buf;
	WORD	n;
	Array*	digest;
};
void Keyring_md4(void*);
typedef struct F_Keyring_md4 F_Keyring_md4;
struct F_Keyring_md4
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_md5(void*);
typedef struct F_Keyring_md5 F_Keyring_md5;
struct F_Keyring_md5
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_mlkem1024_decaps(void*);
typedef struct F_Keyring_mlkem1024_decaps F_Keyring_mlkem1024_decaps;
struct F_Keyring_mlkem1024_decaps
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Array*	sk;
	Array*	ct;
};
void Keyring_mlkem1024_encaps(void*);
typedef struct F_Keyring_mlkem1024_encaps F_Keyring_mlkem1024_encaps;
struct F_Keyring_mlkem1024_encaps
{
	WORD	regs[NREG-1];
	struct{ Array* t0; Array* t1; }*	ret;
	uchar	temps[24];
	Array*	pk;
};
void Keyring_mlkem1024_keygen(void*);
typedef struct F_Keyring_mlkem1024_keygen F_Keyring_mlkem1024_keygen;
struct F_Keyring_mlkem1024_keygen
{
	WORD	regs[NREG-1];
	struct{ Array* t0; Array* t1; }*	ret;
	uchar	temps[24];
};
void Keyring_mlkem768_decaps(void*);
typedef struct F_Keyring_mlkem768_decaps F_Keyring_mlkem768_decaps;
struct F_Keyring_mlkem768_decaps
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Array*	sk;
	Array*	ct;
};
void Keyring_mlkem768_encaps(void*);
typedef struct F_Keyring_mlkem768_encaps F_Keyring_mlkem768_encaps;
struct F_Keyring_mlkem768_encaps
{
	WORD	regs[NREG-1];
	struct{ Array* t0; Array* t1; }*	ret;
	uchar	temps[24];
	Array*	pk;
};
void Keyring_mlkem768_keygen(void*);
typedef struct F_Keyring_mlkem768_keygen F_Keyring_mlkem768_keygen;
struct F_Keyring_mlkem768_keygen
{
	WORD	regs[NREG-1];
	struct{ Array* t0; Array* t1; }*	ret;
	uchar	temps[24];
};
void IPint_mod(void*);
typedef struct F_IPint_mod F_IPint_mod;
struct F_IPint_mod
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void IPint_mul(void*);
typedef struct F_IPint_mul F_IPint_mul;
struct F_IPint_mul
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void IPint_neg(void*);
typedef struct F_IPint_neg F_IPint_neg;
struct F_IPint_neg
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	i;
};
void IPint_not(void*);
typedef struct F_IPint_not F_IPint_not;
struct F_IPint_not
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	i1;
};
void IPint_ori(void*);
typedef struct F_IPint_ori F_IPint_ori;
struct F_IPint_ori
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void Keyring_p256_ecdh(void*);
typedef struct F_Keyring_p256_ecdh F_Keyring_p256_ecdh;
struct F_Keyring_p256_ecdh
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Array*	priv;
	Keyring_ECpoint*	pub;
};
void Keyring_p256_ecdsa_sign(void*);
typedef struct F_Keyring_p256_ecdsa_sign F_Keyring_p256_ecdsa_sign;
struct F_Keyring_p256_ecdsa_sign
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Array*	priv;
	Array*	hash;
};
void Keyring_p256_ecdsa_verify(void*);
typedef struct F_Keyring_p256_ecdsa_verify F_Keyring_p256_ecdsa_verify;
struct F_Keyring_p256_ecdsa_verify
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Keyring_ECpoint*	pub;
	Array*	hash;
	Array*	sig;
};
void Keyring_p256_keygen(void*);
typedef struct F_Keyring_p256_keygen F_Keyring_p256_keygen;
struct F_Keyring_p256_keygen
{
	WORD	regs[NREG-1];
	struct{ Array* t0; Keyring_ECpoint* t1; }*	ret;
	uchar	temps[24];
};
void Keyring_p256_make_point(void*);
typedef struct F_Keyring_p256_make_point F_Keyring_p256_make_point;
struct F_Keyring_p256_make_point
{
	WORD	regs[NREG-1];
	Keyring_ECpoint**	ret;
	uchar	temps[24];
	Array*	pubkey;
};
void Keyring_p256_point_bytes(void*);
typedef struct F_Keyring_p256_point_bytes F_Keyring_p256_point_bytes;
struct F_Keyring_p256_point_bytes
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Keyring_ECpoint*	pub;
};
void Keyring_p384_ecdsa_verify(void*);
typedef struct F_Keyring_p384_ecdsa_verify F_Keyring_p384_ecdsa_verify;
struct F_Keyring_p384_ecdsa_verify
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Array*	pubkey;
	Array*	hash;
	Array*	sig;
};
void Keyring_pktoattr(void*);
typedef struct F_Keyring_pktoattr F_Keyring_pktoattr;
struct F_Keyring_pktoattr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[24];
	Keyring_PK*	pk;
};
void Keyring_pktostr(void*);
typedef struct F_Keyring_pktostr F_Keyring_pktostr;
struct F_Keyring_pktostr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[24];
	Keyring_PK*	pk;
};
void Keyring_putbytearray(void*);
typedef struct F_Keyring_putbytearray F_Keyring_putbytearray;
struct F_Keyring_putbytearray
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	Array*	a;
	WORD	n;
};
void Keyring_puterror(void*);
typedef struct F_Keyring_puterror F_Keyring_puterror;
struct F_Keyring_puterror
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	String*	s;
};
void Keyring_putstring(void*);
typedef struct F_Keyring_putstring F_Keyring_putstring;
struct F_Keyring_putstring
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	String*	s;
};
void IPint_random(void*);
typedef struct F_IPint_random F_IPint_random;
struct F_IPint_random
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	WORD	minbits;
	WORD	maxbits;
};
void Keyring_rc4(void*);
typedef struct F_Keyring_rc4 F_Keyring_rc4;
struct F_Keyring_rc4
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[24];
	Keyring_RC4state*	state;
	Array*	buf;
	WORD	n;
};
void Keyring_rc4back(void*);
typedef struct F_Keyring_rc4back F_Keyring_rc4back;
struct F_Keyring_rc4back
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[24];
	Keyring_RC4state*	state;
	WORD	n;
};
void Keyring_rc4setup(void*);
typedef struct F_Keyring_rc4setup F_Keyring_rc4setup;
struct F_Keyring_rc4setup
{
	WORD	regs[NREG-1];
	Keyring_RC4state**	ret;
	uchar	temps[24];
	Array*	seed;
};
void Keyring_rc4skip(void*);
typedef struct F_Keyring_rc4skip F_Keyring_rc4skip;
struct F_Keyring_rc4skip
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[24];
	Keyring_RC4state*	state;
	WORD	n;
};
void Keyring_readauthinfo(void*);
typedef struct F_Keyring_readauthinfo F_Keyring_readauthinfo;
struct F_Keyring_readauthinfo
{
	WORD	regs[NREG-1];
	Keyring_Authinfo**	ret;
	uchar	temps[24];
	String*	filename;
};
void Keyring_secp256k1_keygen(void*);
typedef struct F_Keyring_secp256k1_keygen F_Keyring_secp256k1_keygen;
struct F_Keyring_secp256k1_keygen
{
	WORD	regs[NREG-1];
	struct{ Array* t0; Array* t1; }*	ret;
	uchar	temps[24];
};
void Keyring_secp256k1_pubkey(void*);
typedef struct F_Keyring_secp256k1_pubkey F_Keyring_secp256k1_pubkey;
struct F_Keyring_secp256k1_pubkey
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Array*	priv;
};
void Keyring_secp256k1_recover(void*);
typedef struct F_Keyring_secp256k1_recover F_Keyring_secp256k1_recover;
struct F_Keyring_secp256k1_recover
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Array*	hash;
	Array*	sig;
};
void Keyring_secp256k1_sign(void*);
typedef struct F_Keyring_secp256k1_sign F_Keyring_secp256k1_sign;
struct F_Keyring_secp256k1_sign
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Array*	priv;
	Array*	hash;
};
void Keyring_senderrmsg(void*);
typedef struct F_Keyring_senderrmsg F_Keyring_senderrmsg;
struct F_Keyring_senderrmsg
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	String*	s;
};
void Keyring_sendmsg(void*);
typedef struct F_Keyring_sendmsg F_Keyring_sendmsg;
struct F_Keyring_sendmsg
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Keyring_sha1(void*);
typedef struct F_Keyring_sha1 F_Keyring_sha1;
struct F_Keyring_sha1
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_sha224(void*);
typedef struct F_Keyring_sha224 F_Keyring_sha224;
struct F_Keyring_sha224
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_sha256(void*);
typedef struct F_Keyring_sha256 F_Keyring_sha256;
struct F_Keyring_sha256
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_sha384(void*);
typedef struct F_Keyring_sha384 F_Keyring_sha384;
struct F_Keyring_sha384
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_sha3_256(void*);
typedef struct F_Keyring_sha3_256 F_Keyring_sha3_256;
struct F_Keyring_sha3_256
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Array*	buf;
	WORD	n;
	Array*	digest;
};
void Keyring_sha3_512(void*);
typedef struct F_Keyring_sha3_512 F_Keyring_sha3_512;
struct F_Keyring_sha3_512
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Array*	buf;
	WORD	n;
	Array*	digest;
};
void Keyring_sha512(void*);
typedef struct F_Keyring_sha512 F_Keyring_sha512;
struct F_Keyring_sha512
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[24];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
void IPint_shl(void*);
typedef struct F_IPint_shl F_IPint_shl;
struct F_IPint_shl
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	i;
	WORD	n;
};
void IPint_shr(void*);
typedef struct F_IPint_shr F_IPint_shr;
struct F_IPint_shr
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	i;
	WORD	n;
};
void Keyring_sign(void*);
typedef struct F_Keyring_sign F_Keyring_sign;
struct F_Keyring_sign
{
	WORD	regs[NREG-1];
	Keyring_Certificate**	ret;
	uchar	temps[24];
	Keyring_SK*	sk;
	WORD	exp;
	Keyring_DigestState*	state;
	String*	ha;
};
void RSAsk_sign(void*);
typedef struct F_RSAsk_sign F_RSAsk_sign;
struct F_RSAsk_sign
{
	WORD	regs[NREG-1];
	Keyring_RSAsig**	ret;
	uchar	temps[24];
	Keyring_RSAsk*	k;
	Keyring_IPint*	m;
};
void DSAsk_sign(void*);
typedef struct F_DSAsk_sign F_DSAsk_sign;
struct F_DSAsk_sign
{
	WORD	regs[NREG-1];
	Keyring_DSAsig**	ret;
	uchar	temps[24];
	Keyring_DSAsk*	k;
	Keyring_IPint*	m;
};
void EGsk_sign(void*);
typedef struct F_EGsk_sign F_EGsk_sign;
struct F_EGsk_sign
{
	WORD	regs[NREG-1];
	Keyring_EGsig**	ret;
	uchar	temps[24];
	Keyring_EGsk*	k;
	Keyring_IPint*	m;
};
void Keyring_signm(void*);
typedef struct F_Keyring_signm F_Keyring_signm;
struct F_Keyring_signm
{
	WORD	regs[NREG-1];
	Keyring_Certificate**	ret;
	uchar	temps[24];
	Keyring_SK*	sk;
	Keyring_IPint*	m;
	String*	ha;
};
void Keyring_sktoattr(void*);
typedef struct F_Keyring_sktoattr F_Keyring_sktoattr;
struct F_Keyring_sktoattr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[24];
	Keyring_SK*	sk;
};
void Keyring_sktopk(void*);
typedef struct F_Keyring_sktopk F_Keyring_sktopk;
struct F_Keyring_sktopk
{
	WORD	regs[NREG-1];
	Keyring_PK**	ret;
	uchar	temps[24];
	Keyring_SK*	sk;
};
void Keyring_sktostr(void*);
typedef struct F_Keyring_sktostr F_Keyring_sktostr;
struct F_Keyring_sktostr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[24];
	Keyring_SK*	sk;
};
void Keyring_strtocert(void*);
typedef struct F_Keyring_strtocert F_Keyring_strtocert;
struct F_Keyring_strtocert
{
	WORD	regs[NREG-1];
	Keyring_Certificate**	ret;
	uchar	temps[24];
	String*	s;
};
void IPint_strtoip(void*);
typedef struct F_IPint_strtoip F_IPint_strtoip;
struct F_IPint_strtoip
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	String*	str;
	WORD	base;
};
void Keyring_strtopk(void*);
typedef struct F_Keyring_strtopk F_Keyring_strtopk;
struct F_Keyring_strtopk
{
	WORD	regs[NREG-1];
	Keyring_PK**	ret;
	uchar	temps[24];
	String*	s;
};
void Keyring_strtosk(void*);
typedef struct F_Keyring_strtosk F_Keyring_strtosk;
struct F_Keyring_strtosk
{
	WORD	regs[NREG-1];
	Keyring_SK**	ret;
	uchar	temps[24];
	String*	s;
};
void IPint_sub(void*);
typedef struct F_IPint_sub F_IPint_sub;
struct F_IPint_sub
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
void Keyring_verify(void*);
typedef struct F_Keyring_verify F_Keyring_verify;
struct F_Keyring_verify
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Keyring_PK*	pk;
	Keyring_Certificate*	cert;
	Keyring_DigestState*	state;
};
void RSApk_verify(void*);
typedef struct F_RSApk_verify F_RSApk_verify;
struct F_RSApk_verify
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Keyring_RSApk*	k;
	Keyring_RSAsig*	sig;
	Keyring_IPint*	m;
};
void DSApk_verify(void*);
typedef struct F_DSApk_verify F_DSApk_verify;
struct F_DSApk_verify
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Keyring_DSApk*	k;
	Keyring_DSAsig*	sig;
	Keyring_IPint*	m;
};
void EGpk_verify(void*);
typedef struct F_EGpk_verify F_EGpk_verify;
struct F_EGpk_verify
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Keyring_EGpk*	k;
	Keyring_EGsig*	sig;
	Keyring_IPint*	m;
};
void Keyring_verifym(void*);
typedef struct F_Keyring_verifym F_Keyring_verifym;
struct F_Keyring_verifym
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	Keyring_PK*	pk;
	Keyring_Certificate*	cert;
	Keyring_IPint*	m;
};
void Keyring_writeauthinfo(void*);
typedef struct F_Keyring_writeauthinfo F_Keyring_writeauthinfo;
struct F_Keyring_writeauthinfo
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[24];
	String*	filename;
	Keyring_Authinfo*	info;
};
void Keyring_x25519(void*);
typedef struct F_Keyring_x25519 F_Keyring_x25519;
struct F_Keyring_x25519
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Array*	scalar;
	Array*	point;
};
void Keyring_x25519_base(void*);
typedef struct F_Keyring_x25519_base F_Keyring_x25519_base;
struct F_Keyring_x25519_base
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[24];
	Array*	scalar;
};
void IPint_xor(void*);
typedef struct F_IPint_xor F_IPint_xor;
struct F_IPint_xor
{
	WORD	regs[NREG-1];
	Keyring_IPint**	ret;
	uchar	temps[24];
	Keyring_IPint*	i1;
	Keyring_IPint*	i2;
};
#define Keyring_PATH "$Keyring"
#define Keyring_SHA1dlen 20
#define Keyring_SHA224dlen 28
#define Keyring_SHA256dlen 32
#define Keyring_SHA384dlen 48
#define Keyring_SHA512dlen 64
#define Keyring_MD5dlen 16
#define Keyring_MD4dlen 16
#define Keyring_SHA3_256dlen 32
#define Keyring_SHA3_512dlen 64
#define Keyring_SLHDSA192S_PKLEN 48
#define Keyring_SLHDSA192S_SKLEN 96
#define Keyring_SLHDSA192S_SIGLEN 16224
#define Keyring_SLHDSA256S_PKLEN 64
#define Keyring_SLHDSA256S_SKLEN 128
#define Keyring_SLHDSA256S_SIGLEN 29792
#define Keyring_Encrypt 0
#define Keyring_Decrypt 1
#define Keyring_AESbsize 16
#define Keyring_Keccak256dlen 32
#define Keyring_MLKEM768_PKLEN 1184
#define Keyring_MLKEM768_SKLEN 2400
#define Keyring_MLKEM768_CTLEN 1088
#define Keyring_MLKEM768_SSLEN 32
#define Keyring_MLKEM1024_PKLEN 1568
#define Keyring_MLKEM1024_SKLEN 3168
#define Keyring_MLKEM1024_CTLEN 1568
#define Keyring_MLKEM1024_SSLEN 32
#define Keyring_DESbsize 8
#define Keyring_IDEAbsize 8
#define Keyring_BFbsize 8
