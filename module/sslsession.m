SSLsession: module {

	PATH: con "/dis/lib/crypt/sslsession.dis";

	Session: adt {
		session_id			: array of byte; # [32]
		peer				: string;
	
		connection_time			: int;
		version				: array of byte; # [2]

		suite				: array of byte; # [2]
		compression			: byte;

		master_secret			: array of byte; # [48]	
		peer_certs			: list of array of byte;

		new: fn(peer: string, time: int, ver: array of byte): ref Session;
		duplicate: fn(s: self ref Session): ref Session;
	};

	init: fn(): string;
	add_session: fn(s: ref Session);
	get_session_byid: fn(session_id: array of byte): ref Session;
	get_session_byname: fn(peer: string): ref Session;
	set_timeout: fn(t: int);
};
