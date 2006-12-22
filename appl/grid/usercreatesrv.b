implement Usercreatesrv;

#
# Copyright © 2003 Vita Nuova Holdings Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "string.m";
	str: String;
include "keyring.m";
	keyring: Keyring;

# create insecure users.

Usercreatesrv: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	keyring = load Keyring Keyring->PATH;

	sys->pctl(Sys->FORKNS, nil);

	fio := export();
	for(;;) alt {
	(nil, nil, nil, rc) := <-fio.read =>
		if(rc != nil)
			rc <-= (nil, "permission denied");
	(nil, data, fid, wc) := <-fio.write =>
		# request:
		# username email
		if(wc == nil)
			break;
		toks := str->unquoted(string data);
		if(len toks != 2){
			wc <-= (0, "invalid request");
			break;
		}
		uname := hd toks; toks = tl toks;
		password := array of byte hd toks; toks = tl toks;
		secret := array[Keyring->SHA1dlen] of byte;
		keyring->sha1(password, len password, secret, nil);
#		email := hd toks; toks = tl toks;
#		e := checkemail(email);
#		if(e != nil){
#			wc <-= (0, e);
#			break;
#		}
		dir := "/mnt/keys/" + uname;
		if(sys->create(dir, Sys->OREAD, Sys->DMDIR|8r777) == nil){
			wc <-= (0, sys->sprint("cannot create account: %r"));
			break;
		}
		sys->write(sys->create(dir + "/secret", Sys->OWRITE, 8r600), secret, len secret);
		wc <-= (len data, nil);
#		sys->print("create %q %q\n", uname, email);
	}
}

checkemail(addr: string): string
{
	for(i := 0; i < len addr; i++)
		if(addr[i] == '@')
			 break;
	if(i == len addr)
		return "email address does not contain an '@' character";
	return nil;
}

export(): ref Sys->FileIO
{
	sys->bind("#s", "/chan", Sys->MREPL|Sys->MCREATE);
	fio := sys->file2chan("/chan", "createuser");
	w := sys->nulldir;
	w.mode = 8r222;
	sys->wstat("/chan/createuser", w);
	sync := chan of int;
	spawn exportproc(sync);
	<-sync;
	return fio;
}

exportproc(sync: chan of int)
{
	sys->pctl(Sys->FORKNS|Sys->NEWFD, 0 :: nil);
	sync <-= 0;
	sys->export(sys->fildes(0), "/chan", Sys->EXPWAIT);
}
