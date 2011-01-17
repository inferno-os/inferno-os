
	#  internal debugging flags 
	DBG, DBG_CRYPTO, DBG_PACKET, DBG_AUTH, DBG_PROC, DBG_PROTO, DBG_IO, DBG_SCP: con 1<<iota;

	#  protocol packet types
	SSH_MSG_NONE,		# 0
	SSH_MSG_DISCONNECT,
	SSH_SMSG_PUBLIC_KEY,
	SSH_CMSG_SESSION_KEY,
	SSH_CMSG_USER,
	SSH_CMSG_AUTH_RHOSTS,
	SSH_CMSG_AUTH_RSA,
	SSH_SMSG_AUTH_RSA_CHALLENGE,
	SSH_CMSG_AUTH_RSA_RESPONSE,
	SSH_CMSG_AUTH_PASSWORD,	#  10 
	SSH_CMSG_REQUEST_PTY,
	SSH_CMSG_WINDOW_SIZE,
	SSH_CMSG_EXEC_SHELL,
	SSH_CMSG_EXEC_CMD,
	SSH_SMSG_SUCCESS,
	SSH_SMSG_FAILURE,
	SSH_CMSG_STDIN_DATA,
	SSH_SMSG_STDOUT_DATA,
	SSH_SMSG_STDERR_DATA,
	SSH_CMSG_EOF,	#  20 
	SSH_SMSG_EXITSTATUS,
	SSH_MSG_CHANNEL_OPEN_CONFIRMATION,
	SSH_MSG_CHANNEL_OPEN_FAILURE,
	SSH_MSG_CHANNEL_DATA,
	SSH_MSG_CHANNEL_INPUT_EOF,
	SSH_MSG_CHANNEL_OUTPUT_CLOSED,
	SSH_MSG_UNIX_DOMAIN_X11_FORWARDING,	#  obsolete 
	SSH_SMSG_X11_OPEN,
	SSH_CMSG_PORT_FORWARD_REQUEST,
	SSH_MSG_PORT_OPEN,	#  30 
	SSH_CMSG_AGENT_REQUEST_FORWARDING,
	SSH_SMSG_AGENT_OPEN,
	SSH_MSG_IGNORE,
	SSH_CMSG_EXIT_CONFIRMATION,
	SSH_CMSG_X11_REQUEST_FORWARDING,
	SSH_CMSG_AUTH_RHOSTS_RSA,
	SSH_MSG_DEBUG,
	SSH_CMSG_REQUEST_COMPRESSION,
	SSH_CMSG_MAX_PACKET_SIZE,
	SSH_CMSG_AUTH_TIS,	#  40 
	SSH_SMSG_AUTH_TIS_CHALLENGE,
	SSH_CMSG_AUTH_TIS_RESPONSE,
	SSH_CMSG_AUTH_KERBEROS,
	SSH_SMSG_AUTH_KERBEROS_RESPONSE,
	SSH_CMSG_HAVE_KERBEROS_TGT: con iota;

	SSH_MSG_ERROR: con -1;

	#  protocol flags 
	SSH_PROTOFLAG_SCREEN_NUMBER: con 1<<0;
	SSH_PROTOFLAG_HOST_IN_FWD_OPEN: con 1<<1;

	#  agent protocol packet types 
	SSH_AGENTC_NONE,
	SSH_AGENTC_REQUEST_RSA_IDENTITIES,
	SSH_AGENT_RSA_IDENTITIES_ANSWER,
	SSH_AGENTC_RSA_CHALLENGE,
	SSH_AGENT_RSA_RESPONSE,
	SSH_AGENT_FAILURE,
	SSH_AGENT_SUCCESS,
	SSH_AGENTC_ADD_RSA_IDENTITY,
	SSH_AGENTC_REMOVE_RSA_IDENTITY: con iota;

	#  protocol constants 
	SSH_MAX_DATA: con 256*1024;
	SSH_MAX_MSG: con SSH_MAX_DATA+4;
	SESSKEYLEN: con 32;
	SESSIDLEN: con 16;
	COOKIELEN: con 8;

	#  crypto ids 
	SSH_CIPHER_NONE,
	SSH_CIPHER_IDEA,
	SSH_CIPHER_DES,
	SSH_CIPHER_3DES,
	SSH_CIPHER_TSS,
	SSH_CIPHER_RC4,
	SSH_CIPHER_BLOWFISH: con iota;

	#  auth method ids 
	SSH_AUTH_RHOSTS,
	SSH_AUTH_RSA,
	SSH_AUTH_PASSWORD,
	SSH_AUTH_RHOSTS_RSA,
	SSH_AUTH_TIS,
	SSH_AUTH_USER_RSA: con 1+iota;

Edecode: con "error decoding input packet";
Eencode: con "out of space encoding output packet (BUG)";
Ehangup: con "hungup connection";
Ememory: con "out of memory";

Cipher: module
{
	id:	fn(): int;
	init:	fn(key: array of byte, isserver: int);
	encrypt: fn(a: array of byte, n: int);
	decrypt: fn(a: array of byte, n: int);
};

Auth: module
{
	AuthInfo:	adt{
		user:	string;
		cap:	string;
	};

	id:	fn(): int;
	firstmsg:	fn(): int;
	init:	fn(nil: Sshio);
	authsrv:	fn(nil: ref Sshio->Conn, nil: ref Sshio->Msg): ref AuthInfo;
	auth:	fn(nil: ref Sshio->Conn): int;
};

Sshio: module
{
	PATH:	con "sshio.dis";

	Conn: adt{
		in: chan of (ref Msg, string);
		out: chan of ref Msg;

		sessid: array of byte;
		sesskey: array of byte;
		hostkey: ref Crypt->PK.RSA;
		flags: int;
		cipher: Cipher;	#  chosen cipher 
		user: string;
		host: string;
		interactive: int;
		unget: ref Msg;

		mk:	fn(host: string, fd: ref Sys->FD): ref Conn;
		setkey:	fn(c: self ref Conn, key: ref Crypt->PK.RSA);
	};

	Msg: adt{
		mtype: int;
		data: array of byte;
		rp: int;	#  read pointer 
		wp: int;	#  write pointer 
		ep: int;	#  byte just beyond message data

		mk:	fn(mtype: int, length: int): ref Msg;
		text:	fn(m: self ref Msg): string;
		fulltext:	fn(m: self ref Msg): string;

		get1: fn(m: self ref Msg): int;
		get2: fn(m: self ref Msg): int;
		get4: fn(m: self ref Msg): int;
		getstring: fn(m: self ref Msg): string;
		getbytes: fn(m: self ref Msg, n: int): array of byte;
		getarray:	fn(m: self ref Msg): array of byte;
		getipint: fn(m: self ref Msg): ref IPints->IPint;
		getpk: fn(m: self ref Msg): ref Crypt->PK.RSA;

		put1: fn(m: self ref Msg, nil: int);
		put2: fn(m: self ref Msg, nil: int);
		put4: fn(m: self ref Msg, nil: int);
		putstring: fn(m: self ref Msg, s: string);
		putbytes: fn(m: self ref Msg, a: array of byte, n: int);
		putipint: fn(m: self ref Msg, mp: ref IPints->IPint);
		putpk: fn(m: self ref Msg, pk: ref Crypt->PK.RSA);
	};

	init:	fn();

	badmsg:	fn(nil: ref Msg, nil: int, err: string);
	recvmsg:	fn(nil: ref Conn, nil: int): ref Msg;
	unrecvmsg:	fn(nil: ref Conn, nil: ref Msg);
	rsapad:	fn(nil: ref IPints->IPint, nil: int): ref IPints->IPint;
	rsaunpad:	fn(nil: ref IPints->IPint): ref IPints->IPint;
	iptorjustbe:	fn(nil: ref IPints->IPint, nil: array of byte, nil: int);
	rsaencryptbuf:	fn(nil: ref Crypt->PK.RSA, nil: array of byte, nil: int): ref IPints->IPint;
	rsagen:	fn(nbits: int): ref Crypt->SK.RSA;
	rsaencrypt:	fn(key: ref Crypt->PK.RSA, b: ref IPints->IPint): ref IPints->IPint;
	rsadecrypt:	fn(key: ref Crypt->SK.RSA, b: ref IPints->IPint): ref IPints->IPint;

	debug: fn(nil: int, nil: string);
	error: fn(nil: string);
	readstrnl:	fn(fd: ref Sys->FD, buf: array of byte, nbytes: int): int;
	calcsessid: fn(hostmod: ref IPints->IPint, servermod: ref IPints->IPint, cookie: array of byte): array of byte;
#	sshlog: fn(nil: array of byte);	# TBA was ...

	fastrand: fn(): int;
	eqbytes:	fn(a: array of byte, b: array of byte, n: int): int;
	readversion:	fn(fd: ref Sys->FD): (int, int, string);
	hex:	fn(a: array of byte): string;
};
