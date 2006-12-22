implement Bloomfilter;

include "sys.m";
	sys: Sys;
include "sets.m";
	sets: Sets;
	Set: import sets;
include "keyring.m";
	keyring: Keyring;
include "bloomfilter.m";

init()
{
	sys = load Sys Sys->PATH;
	sets = load Sets Sets->PATH;
	sets->init();
	keyring = load Keyring Keyring->PATH;
}

Bits: adt {
	d: array of byte;
	n: int;			# bits used
	get:	fn(bits: self ref Bits, n: int): int;
};

filter(d: array of byte, logm, k: int): Set
{
	if(logm < 3 || logm > 30)
		raise "invalid bloom filter size";
	nb := 1 << logm;
	f := array[nb / 8 + 1] of {* => byte 0};	# one extra zero to make sure set's not inverted.
	bits := hashbits(d, logm * k);
	while(k--){
		v := bits.get(logm);
		f[v >> 3] |= byte 1 << (v & 7);
	}
	return sets->bytes2set(f);
}

hashbits(data: array of byte, n: int): ref Bits
{
	d := array[((n + 7) / 8)] of byte;
	digest := array[Keyring->SHA1dlen] of byte;
	state := keyring->sha1(data, len data, nil, nil);
	extra := array[2] of byte;
	e := 0;
	for(i := 0; i < len d; i += Keyring->SHA1dlen){
		extra[0] = byte e;
		extra[1] = byte (e>>8);
		e++;
		state = keyring->sha1(extra, len extra, digest, state);
		if(i + Keyring->SHA1dlen > len d)
			digest = digest[0:len d - i];
		d[i:] = digest;
	}
	return ref Bits(d, 0);
}

# XXX could be more efficient.
Bits.get(bits: self ref Bits, n: int): int
{
	d := bits.d;
	v := 0;
	nb := bits.n;
	for(i := 0; i < n; i++){
		j := nb + i;
		if(int d[j >> 3] & (1 << (j & 7)))
			v |= (1 << i);
	}
	bits.n += n;
	return v;
}
