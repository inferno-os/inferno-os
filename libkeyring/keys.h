typedef struct IPint IPint;
typedef struct SigAlg SigAlg;
typedef struct SigAlgVec SigAlgVec;
typedef struct SK SK;
typedef struct PK PK;
typedef struct Certificate Certificate;
typedef struct XDigestState XDigestState;
typedef struct XAESstate XAESstate;
typedef struct XDESstate XDESstate;
typedef struct XIDEAstate XIDEAstate;
typedef struct XRC4state XRC4state;

enum
{
	Maxbuf=	4096,
	MaxBigBytes = 1024
};

/* infininite precision integer */
struct IPint
{
	Keyring_IPint x;
	mpint*	b;
};

/* generic certificate */
struct Certificate
{
	Keyring_Certificate x;
	void		*signa;	/* actual signature */
};

/* generic public key */
struct PK
{
	Keyring_PK	x;
	void		*key;	/* key and system parameters */
};

/* digest state */
struct XDigestState
{
	Keyring_DigestState	x;
	DigestState	state;
};

/* AES state */
struct XAESstate
{
	Keyring_AESstate	x;
	AESstate	state;
};

/* DES state */
struct XDESstate
{
	Keyring_DESstate	x;
	DESstate	state;
};

/* IDEA state */
struct XIDEAstate
{
	Keyring_IDEAstate	x;
	IDEAstate	state;
};

/* RC4 state */
struct XRC4state
{
	Keyring_RC4state	x;
	RC4state	state;
};

/* generic secret key */
struct SK
{
	Keyring_SK	x;
	void		*key;	/* key and system parameters */
};

struct SigAlgVec {
	char	*name;

	char**	skattr;
	char**	pkattr;
	char**	sigattr;

	void*	(*str2sk)(char*, char**);
	void*	(*str2pk)(char*, char**);
	void*	(*str2sig)(char*, char**);

	int	(*sk2str)(void*, char*, int);
	int	(*pk2str)(void*, char*, int);
	int	(*sig2str)(void*, char*, int);

	void*	(*sk2pk)(void*);

	void*	(*gensk)(int);
	void*	(*genskfrompk)(void*);
	void*	(*sign)(mpint*, void*);
	int	(*verify)(mpint*, void*, void*);

	void	(*skfree)(void*);
	void	(*pkfree)(void*);
	void	(*sigfree)(void*);
};

struct SigAlg
{
	Keyring_SigAlg	x;
	SigAlgVec	*vec;
};

int	bigtobase64(mpint* b, char *buf, int blen);
mpint*	base64tobig(char *str, char **strp);
SigAlgVec*	findsigalg(char*);
Keyring_IPint*	newIPint(mpint*);
