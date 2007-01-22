JSON: module
{
	PATH:	con "/dis/lib/json.dis";

	JValue: adt {
		pick{
		Object =>
			mem: cyclic list of (string, ref JValue);
		Array =>
			a: cyclic array of ref JValue;
		String =>
			s: string;
		Int =>
			value:	big;	# could use IPint?	# just use Number (as string)
		Real =>
			value:	real;
		True or False or Null =>
		}

		isarray:	fn(o: self ref JValue): int;
		isfalse:	fn(o: self ref JValue): int;
		isint:		fn(o: self ref JValue): int;
		isnull:	fn(o: self ref JValue): int;
		isnumber: fn(o: self ref JValue): int;
		isobject:	fn(o: self ref JValue): int;
		isreal:	fn(o: self ref JValue): int;
		isstring:	fn(o: self ref JValue): int;
		istrue:	fn(o: self ref JValue): int;
		copy:	fn(o: self ref JValue): ref JValue;
		eq:	fn(a: self ref JValue, b: ref JValue): int;
		get:	fn(a: self ref JValue, n: string): ref JValue;
		set:	fn(a: self ref JValue, mem: string, value: ref JValue);
		text:	fn(a: self ref JValue): string;
	};

	init:	fn(bufio: Bufio);
	readjson:	fn(buf: ref Bufio->Iobuf): (ref JValue, string);
	writejson:	fn(buf: ref Bufio->Iobuf, val: ref JValue): int;

	# shorthand?
	jvarray:	fn(a: array of ref JValue): ref JValue.Array;
	jvbig:	fn(b: big): ref JValue.Int;
	jvfalse:	fn(): ref JValue.False;
	jvint:		fn(i: int): ref JValue.Int;
	jvnull:	fn(): ref JValue.Null;
	jvobject:	fn(m: list of (string, ref JValue)): ref JValue.Object;
	jvreal:	fn(r: real): ref JValue.Real;
	jvstring:	fn(s: string): ref JValue.String;
	jvtrue:	fn(): ref JValue.True;
};
