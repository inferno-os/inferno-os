enum
{
	IPaddrlen		= 16,	/* IPv6 */
	IPv4addrlen	= 4,	/* IPv4 */
	IPv4off		= 12,	/* length of IPv6 prefix for IPv4 addresses */
	Udphdrlen	= 3*IPaddrlen+2*2,
	OUdphdrlen	= 2*IPaddrlen+2*2,
	OUdphdrlenv4	= 2*IPv4addrlen+2*2,

	S_TCP		= 0,
	S_UDP
};

typedef struct Fs Fs;
typedef struct Proto	Proto;
typedef struct Conv	Conv;

extern int		so_socket(int type);
extern void		so_connect(int, unsigned long, unsigned short);
extern void		so_getsockname(int, unsigned long*, unsigned short*);
extern void		so_bind(int, int, unsigned long, unsigned short);
extern void		so_listen(int);
extern int		so_accept(int, unsigned long*, unsigned short*);
extern int		so_getservbyname(char*, char*, char*);
extern int		so_gethostbyname(char*, char**, int);
extern int		so_gethostbyaddr(char*, char**, int);
extern int		so_recv(int, void*, int, void*, int);
extern int		so_send(int, void*, int, void*, int);
extern void		so_close(int);
extern int		so_hangup(int, int);
extern void		so_setsockopt(int, int, int);
extern int		so_mustbind(int, int);
extern void		so_keepalive(int, int);


extern void		hnputl(void *p, unsigned long v);
extern void		hnputs(void *p, unsigned short v);
extern unsigned long	nhgetl(void *p);
extern unsigned short	nhgets(void *p);
extern unsigned long	parseip(uchar *to, char *from);
extern int	parsemac(uchar *to, char *from, int len);
extern char*	v4parseip(uchar*, char*);
extern int		bipipe(int[]);

extern int	isv4(uchar*);
extern void	v4tov6(uchar *v6, uchar *v4);
extern int	v6tov4(uchar *v4, uchar *v6);
extern int	eipfmt(Fmt*);

#define	ipmove(x, y) memmove(x, y, IPaddrlen)
#define	ipcmp(x, y) ( (x)[IPaddrlen-1] != (y)[IPaddrlen-1] || memcmp(x, y, IPaddrlen) )

extern uchar IPv4bcast[IPaddrlen];
extern uchar IPv4bcastobs[IPaddrlen];
extern uchar IPv4allsys[IPaddrlen];
extern uchar IPv4allrouter[IPaddrlen];
extern uchar IPnoaddr[IPaddrlen];
extern uchar v4prefix[IPaddrlen];
extern uchar IPallbits[IPaddrlen];

extern void	arpadd(char*, char*, int);
extern int	arpwrite(char*, int);

extern	int	Fsproto(Fs*, Proto*);
