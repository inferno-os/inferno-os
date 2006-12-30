Ida: module
{
	PATH: con "/dis/lib/ida/ida.dis";

	Frag: adt {
		dlen:	int;	# length of original data
		m:	int;	# minimum pieces for reconstruction
		a:	array of int;	# encoding array row for this fragment
		enc:	array of int;	# encoded data

		tag:	array of byte;	# user data, such as SHA1 hash
	};

	init:	fn();
	fragment:	fn(data: array of byte, m: int): ref Frag;
	consistent:	fn(frags: array of ref Frag): array of ref Frag;
	reconstruct:	fn(frags: array of ref Frag): (array of byte, string);
};

Idatab: module
{
	PATH: con "/dis/lib/ida/idatab.dis";
	init:	fn(): array of int;
};
