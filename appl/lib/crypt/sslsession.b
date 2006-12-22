#
# SSL Session Cache
#
implement SSLsession;

include "sys.m";
	sys					: Sys;

include "daytime.m";
	daytime					: Daytime;

include "sslsession.m";


# default session id timeout
TIMEOUT_SECS 					: con 5*60; # sec

SessionCache: adt {
	db					: list of ref Session;
	time_out				: int;
};

# The shared session cache by all ssl contexts is available for efficiently resumming
# sessions for different run time contexts.

Session_Cache					: ref SessionCache;


init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "sslsession: load sys module failed";

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		return "sslsession: load Daytime module failed";

	Session_Cache = ref SessionCache(nil, TIMEOUT_SECS);

	return "";
}

Session.new(peer: string, time: int, ver: array of byte): ref Session
{
	s := ref Session;

	s.peer = peer;
	s.connection_time = time;
	s.version = array [2] of byte;
	s.version[0:] = ver;
	s.session_id = nil;
	s.suite = nil;
	s.master_secret = nil;
	s.peer_certs = nil;

	return s;
}

Session.duplicate(s: self ref Session): ref Session
{
	new := ref Session;

	new.peer = s.peer;
	new.connection_time = s.connection_time;
	new.version = array [len s.version] of byte;
	new.version[0:] = s.version;
	new.session_id = array [len s.session_id] of byte;
	new.session_id[0:] = s.session_id;
	new.suite = array [len s.suite] of byte;
	new.suite[0:] = s.suite;
	new.master_secret = array [len s.master_secret] of byte;
	new.master_secret[0:] = s.master_secret;
	l: list of array of byte;
	pcs := s.peer_certs;
	while(pcs != nil) {
		a := hd pcs;
		b := array [len a] of byte;
		b[0:] = a;
		l = b :: l;
		pcs = tl pcs;
	}
	while(l != nil) {
		new.peer_certs = (hd l) :: new.peer_certs;
		l = tl l;
	}
	return new;
}

# Each request process should get a copy of a session. A session will be
# removed from database if it is expired. The garbage
# collector will finally remove it from memory if there are no more
# references to it.

get_session_byname(peer: string): ref Session
{
	s: ref Session;
	now := daytime->now(); # not accurate but more efficient

	l := Session_Cache.db;
	while(l != nil) {
		if((hd l).peer == peer) {
			s = hd l;
			# TODO: remove expired session
			if(now > s.connection_time+Session_Cache.time_out)
				s = nil;
			break;
		}
		l = tl l;
	}
	if(s == nil)
		s = Session.new(peer, now, nil);
	else
		s = s.duplicate();

	return s;
}

# replace the old by the new one
add_session(s: ref Session)
{
	#old : ref Session;

	#ls := Session_Cache.db;
	#while(ls != nil) {
	#	old = hd ls;
	#	if(s.session_id == old.session_id) {
	#		# old = s;
	#		return;
	#	}
	#}

	# always resume the most recent
	if(s != nil)
		Session_Cache.db = s :: Session_Cache.db;
}

get_session_byid(session_id: array of byte): ref Session
{
	s: ref Session;	
	now := daytime->now(); # not accurate but more efficient
	l := Session_Cache.db;
	while(l != nil) {
		if(bytes_cmp((hd l).session_id, session_id) == 0) {
			s = hd l;
			# replace expired session
			if(now > s.connection_time+Session_Cache.time_out)
				s = Session.new(s.peer, now, nil);
			else
				s = s.duplicate();
			break;
		}
		l = tl l;
	}
	return s;
}

set_timeout(t: int)
{
	Session_Cache.time_out = t;
}

bytes_cmp(a, b: array of byte): int
{
	if(len a != len b)
		return -1;

	n := len a;
	for(i := 0; i < n; i++) {
		if(a[i] != b[i])
			return -1;
	}

	return 0;
}

