implement Randpass;

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;

include "draw.m";

include "keyring.m";
	kr : Keyring;
	IPint: import kr;

Randpass: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;

	if(args != nil)
		args = tl args;
	pwlen := 16;
	if(args != nil){
		if(!isnumeric(hd args) || (pwlen = int hd args) <= 8 || pwlen > 256){
			sys->fprint(sys->fildes(2), "Usage: randpass [password-length(<256, default=16)]\n");
			raise "fail:usage";
		}
	}

	rbig := IPint.random(pwlen*8, pwlen*16);
	rstr := rbig.iptob64();

	sys->print("%s\n", rstr[0:pwlen]);
}

isnumeric(s: string): int
{
	for(i := 0; i < len s; i++)
		if(!(s[i]>='0' && s[i]<='9'))
			return 0;
	return i > 0;
}
