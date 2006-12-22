Auth9: module
{
	PATH:	con "/dis/lib/auth9.dis";

	#
	# plan 9 authentication
	#

	ANAMELEN: con 	28; # maximum size of name in previous proto
	AERRLEN: con 	64; # maximum size of errstr in previous proto
	DOMLEN: con 		48; # length of an authentication domain name
	DESKEYLEN: con 	7; # length of a des key for encrypt/decrypt
	CHALLEN: con 	8; # length of a plan9 sk1 challenge
	NETCHLEN: con 	16; # max network challenge length (used in AS protocol)
	SECRETLEN: con 	32; # max length of a secret

	# encryption numberings (anti-replay)
	AuthTreq: con 1; 	# ticket request
	AuthChal: con 2; 	# challenge box request
	AuthPass: con 3; 	# change password
	AuthOK: con 4; 	# fixed length reply follows
	AuthErr: con 5; 	# error follows
	AuthMod: con 6; 	# modify user
	AuthApop: con 7; 	# apop authentication for pop3
	AuthOKvar: con 9; 	# variable length reply follows
	AuthChap: con 10; 	# chap authentication for ppp
	AuthMSchap: con 11; 	# MS chap authentication for ppp
	AuthCram: con 12; 	# CRAM verification for IMAP (RFC2195 & rfc2104)
	AuthHttp: con 13; 	# http domain login
	AuthVNC: con 14; 	# VNC server login (deprecated)


	AuthTs: con 64;	# ticket encrypted with server's key
	AuthTc: con 65;	# ticket encrypted with client's key
	AuthAs: con 66;	# server generated authenticator
	AuthAc: con 67;	# client generated authenticator
	AuthTp: con 68;	# ticket encrypted with client's key for password change
	AuthHr: con 69;	# http reply

	Ticketreq: adt {
		rtype: int;
		authid: string;	# [ANAMELEN]	server's encryption id
		authdom: string;	# [DOMLEN]	server's authentication domain
		chal:	array of byte; # [CHALLEN]	challenge from server
		hostid: string;	# [ANAMELEN]		host's encryption id
		uid: string;	# [ANAMELEN]	uid of requesting user on host

		pack:	fn(t: self ref Ticketreq): array of byte;
		unpack:	fn(a: array of byte): (int, ref Ticketreq);
	};
		TICKREQLEN: con	3*ANAMELEN+CHALLEN+DOMLEN+1;

	Ticket: adt {
		num: int;	# replay protection
		chal:	array of byte;	# [CHALLEN]	server challenge
		cuid: string;	# [ANAMELEN]	uid on client
		suid: string;	# [ANAMELEN]	uid on server
		key:	array of byte;	# [DESKEYLEN]	nonce DES key

		pack:	fn(t: self ref Ticket, key: array of byte): array of byte;
		unpack:	fn(a: array of byte, key: array of byte): (int, ref Ticket);
	};
		TICKETLEN: con CHALLEN+2*ANAMELEN+DESKEYLEN+1;

	Authenticator: adt {
		num: int;			# replay protection
		chal: array of byte;	# [CHALLEN]
		id:	int;			# authenticator id, ++'d with each auth

		pack:	fn(f: self ref Authenticator, key: array of byte): array of byte;
		unpack:	fn(a: array of byte, key: array of byte): (int, ref Authenticator);
	};
		AUTHENTLEN: con CHALLEN+4+1;

	Passwordreq: adt {
		num: int;
		old:	array of byte;	# [ANAMELEN]
		new:	array of byte;	# [ANAMELEN]
		changesecret:	int;
		secret:	array of byte; # [SECRETLEN]	new secret

		pack:	fn(f: self ref Passwordreq, key: array of byte): array of byte;
		unpack:	fn(a: array of byte, key: array of byte): (int, ref Passwordreq);
	};
	PASSREQLEN: con	2*ANAMELEN+1+1+SECRETLEN;

	# secure ID and Plan 9 auth key/request/reply encryption
	netcrypt:	fn(key: array of byte, chal: string): string;
	passtokey:	fn(pw: string): array of byte;
	des56to64:	fn(a: array of byte): array of byte;
	encrypt:	fn(key: array of byte, data: array of byte, n: int);
	decrypt:	fn(key: array of byte, data: array of byte, n: int);

	# dial auth server
#	authdial(netroot: string, authdom: string): ref Sys->FD;

	# exchange messages with auth server
	_asgetticket:	fn(fd: ref Sys->FD, tr: ref Ticketreq, key: array of byte): (ref Ticket, array of byte);
	_asrdresp:	fn(fd: ref Sys->FD, n: int): array of byte;

	init:	fn();
};

