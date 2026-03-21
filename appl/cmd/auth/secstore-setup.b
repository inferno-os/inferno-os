implement SecstoreSetup;

#
# secstore-setup - Create secstore user accounts
#
# Prompts for a username and password, computes the PAK verifier,
# and stores it in the secstore directory.  Optionally imports
# current factotum keys into the new secstore account.
#
# Usage:
#   auth/secstore-setup [-s storedir] [-u user] [-i]
#
# Options:
#   -s storedir   secstore data directory (default: /usr/inferno/secstore)
#   -u user       username (default: current user from /dev/user)
#   -i            import current factotum keys into secstore
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "dial.m";

include "keyring.m";
	kr: Keyring;
	IPint: import kr;

include "secstore.m";
	secstore: Secstore;

include "arg.m";

SecstoreSetup: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

storedir := "/usr/inferno/secstore";
stderr: ref Sys->FD;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	secstore = load Secstore Secstore->PATH;
	stderr = sys->fildes(2);

	if(kr == nil || secstore == nil)
		fatal("cannot load required modules");

	secstore->init();

	user := readfile("/dev/user");
	importkeys := 0;
	pass: string;

	arg := load Arg Arg->PATH;
	if(arg != nil){
		arg->init(args);
		arg->setusage("auth/secstore-setup [-i] [-k password] [-s storedir] [-u user]");
		while((o := arg->opt()) != 0)
			case o {
			'i' =>	importkeys = 1;
			'k' =>	pass = arg->earg();
			's' =>	storedir = arg->earg();
			'u' =>	user = arg->earg();
			* =>	arg->usage();
			}
	}

	if(user == nil || user == "")
		fatal("no username");

	sys->fprint(stderr, "secstore setup for user: %s\n", user);
	sys->fprint(stderr, "store directory: %s\n", storedir);

	# Prompt for password if not provided via -k
	if(pass == nil || pass == "") {
		pass = promptpassword("secstore password: ");
		if(pass == nil || pass == "")
			fatal("no password");
		pass2 := promptpassword("confirm password: ");
		if(pass2 != pass)
			fatal("passwords don't match");
	}

	# Compute PAK verifier: Hi = H^-1 mod p
	pwhash := secstore->mkseckey(pass);
	(hexHi, nil, nil) := PAK_Hi(user, pwhash);
	secstore->erasekey(pwhash);

	# Create user directory
	userdir := storedir + "/" + user;
	sys->create(storedir, Sys->OREAD, Sys->DMDIR | 8r700);
	sys->create(userdir, Sys->OREAD, Sys->DMDIR | 8r700);

	# Write verifier
	pakpath := userdir + "/PAK";
	fd := sys->create(pakpath, Sys->OWRITE, 8r600);
	if(fd == nil)
		fatal(sys->sprint("can't create %s: %r", pakpath));
	b := array of byte hexHi;
	sys->write(fd, b, len b);
	fd = nil;

	sys->fprint(stderr, "PAK verifier stored in %s\n", pakpath);

	# Optionally import factotum keys
	if(importkeys){
		keys := readfile("/mnt/factotum/ctl");
		if(keys == nil || keys == ""){
			sys->fprint(stderr, "no keys in factotum to import\n");
		} else {
			# Encrypt with modern AES-GCM file key
			filekey := secstore->mkfilekey2(pass);
			plaintext := array of byte keys;
			encrypted := secstore->encrypt2(plaintext, filekey);
			secstore->erasekey(filekey);
			secstore->erasekey(plaintext);

			if(encrypted == nil)
				fatal("encryption failed");

			fpath := userdir + "/factotum";
			fd = sys->create(fpath, Sys->OWRITE, 8r600);
			if(fd == nil)
				fatal(sys->sprint("can't create %s: %r", fpath));
			sys->write(fd, encrypted, len encrypted);
			fd = nil;
			sys->fprint(stderr, "imported factotum keys to %s\n", fpath);
		}
	}

	sys->fprint(stderr, "setup complete\n");
}

# Compute Hi = H^-1 mod p (same as secstore.b PAK_Hi)
PAK_Hi(C: string, passhash: array of byte): (string, ref IPint, ref IPint)
{
	H := secstore_longhash("secstore", C, passhash);
	# Need PAK params
	p := IPint.strtoip("C41CFBE4D4846F67A3DF7DE9921A49D3B42DC33728427AB159CEC8CBB"+
		"DB12B5F0C244F1A734AEB9840804EA3C25036AD1B61AFF3ABBC247CD4B384224567A86"+
		"3A6F020E7EE9795554BCD08ABAD7321AF27E1E92E3DB1C6E7E94FAAE590AE9C48F96D9"+
		"3D178E809401ABE8A534A1EC44359733475A36A70C7B425125062B1142D", 16);
	Hi := H.invert(p);
	return (Hi.iptostr(64), H, Hi);
}

secstore_longhash(ver: string, C: string, passwd: array of byte): ref IPint
{
	aver := array of byte ver;
	aC := array of byte C;
	Cp := array[len aver + len aC + len passwd] of byte;
	Cp[0:] = aver;
	Cp[len aver:] = aC;
	Cp[len aver+len aC:] = passwd;

	p := IPint.strtoip("C41CFBE4D4846F67A3DF7DE9921A49D3B42DC33728427AB159CEC8CBB"+
		"DB12B5F0C244F1A734AEB9840804EA3C25036AD1B61AFF3ABBC247CD4B384224567A86"+
		"3A6F020E7EE9795554BCD08ABAD7321AF27E1E92E3DB1C6E7E94FAAE590AE9C48F96D9"+
		"3D178E809401ABE8A534A1EC44359733475A36A70C7B425125062B1142D", 16);
	r := IPint.strtoip("DF310F4E54A5FEC5D86D3E14863921E834113E060F90052AD332B3241"+
		"CEF2497EFA0303D6344F7C819691A0F9C4A773815AF8EAECFB7EC1D98F039F17A32A7E"+
		"887D97251A927D093F44A55577F4D70444AEBD06B9B45695EC23962B175F266895C67D"+
		"21C4656848614D888A4", 16);

	buf := array[7*Keyring->SHA1dlen] of byte;
	for(i := 0; i < 7; i++){
		key := array[] of { byte('A'+i) };
		kr->hmac_sha1(Cp, len Cp, key, buf[i*Keyring->SHA1dlen:], nil);
	}
	erasekey(Cp);
	return mod(IPint.bebytestoip(buf), p).expmod(r, p);
}

mod(a, b: ref IPint): ref IPint
{
	return a.div(b).t1;
}

erasekey(a: array of byte)
{
	for(i := 0; i < len a; i++)
		a[i] = byte 0;
}

promptpassword(prompt: string): string
{
	sys->fprint(stderr, "%s", prompt);

	consctl := sys->open("/dev/consctl", Sys->OWRITE);
	if(consctl != nil)
		sys->fprint(consctl, "rawon");

	fd := sys->open("/dev/cons", Sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[256] of byte;
	pass := "";
	for(;;){
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		s := string buf[0:n];
		for(i := 0; i < len s; i++){
			if(s[i] == '\n' || s[i] == '\r'){
				if(consctl != nil)
					sys->fprint(consctl, "rawoff");
				sys->fprint(stderr, "\n");
				return pass;
			}
			pass[len pass] = s[i];
		}
	}

	if(consctl != nil)
		sys->fprint(consctl, "rawoff");
	sys->fprint(stderr, "\n");
	if(len pass > 0)
		return pass;
	return nil;
}

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[8192] of byte;
	all := "";
	for(;;){
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		all += string buf[0:n];
	}
	# Strip trailing newline
	while(len all > 0 && all[len all-1] == '\n')
		all = all[:len all-1];
	return all;
}

fatal(s: string)
{
	sys->fprint(stderr, "secstore-setup: %s\n", s);
	raise "fail:error";
}
