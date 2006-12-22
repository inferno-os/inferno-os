implement ASN1;

include "sys.m";
	sys: Sys;

include "asn1.m";

# Masks
TAG_MASK : con 16r1F;
CONSTR_MASK : con 16r20;
CLASS_MASK : con 16rC0;

# Decoding errors
OK, ESHORT, ETOOBIG, EVALLEN, ECONSTR, EPRIM, EINVAL, EUNIMPL: con iota;

debug : con 0;

init()
{
	sys = load Sys Sys->PATH;
}

# Decode the whole array as a BER encoding of an ASN1 type.
# If there's an error, the return string will contain the error.
# Depending on the error, the returned elem may or may not
# be nil.
decode(a: array of byte) : (string, ref Elem)
{
	(ecode, i, elem) := ber_decode(a, 0, len a);
	return (errstr(ecode, i, len a), elem);
}

# Like decode, but continue decoding after first element
# of array ends.
decode_seq(a: array of byte) : (string, list of ref Elem)
{
	(ecode, i, elist) := seq_decode(a, 0, len a, -1, 1);
	return (errstr(ecode, i, len a), elist);
}

# Decode the whole array as a BER encoding of an ASN1 value,
# (i.e., the part after the tag and length).
# Assume the value is encoded as universal tag "kind".
# The constr arg is 1 if the value is constructed, 0 if primitive.
# If there's an error, the return string will contain the error.
# Depending on the error, the returned value may or may not
# be nil.
decode_value(a: array of byte, kind, constr: int) : (string, ref Value)
{
	n := len a;
	(ecode, i, val) := value_decode(a, 0, n, n, kind, constr);
	return (errstr(ecode, i, len a), val);
}

# The rest of the decoding routines take the array (a), the
# starting position (i), and the ending position +1 (n).
# They return (err code, new i, [... varies]).

# for debugging
ber_ind := "";
ber_ind_save := "";

# Decode an ASN1 (tag, length, value).
ber_decode(a: array of byte, i, n: int) : (int, int, ref Elem)
{
	if(debug) {
		ber_ind_save = ber_ind;
		ber_ind = ber_ind + "  ";
		sys->print("%sber_decode, byte %d\n", ber_ind, i);
	}
	err, length: int;
	tag : Tag;
	val : ref Value;
	elem : ref Elem = nil;
	(err, i, tag) = tag_decode(a, i, n);
	if(err == OK) {
		(err, i, length) = length_decode(a, i, n);
		if(err == OK) {
			if(debug)
				sys->print("%sgot tag %s, length %d, now at byte %d\n",
						ber_ind, tag.tostring(), length, i);
			if(tag.class == Universal)
				(err, i, val) = value_decode(a, i, n, length, tag.num, tag.constr);
			else
				(err, i, val) = value_decode(a, i, n, length, OCTET_STRING, 0);
			if(val != nil)
				elem = ref Elem(tag, val);
		}
	}
	if(debug) {
		sys->print("%send ber_decode, byte %d\n", ber_ind, i);
		if(val != nil) {
			sys->print("%sdecode result:\n", ber_ind);
			print_elem(elem);
		}
		if(err != OK)
			sys->print("%serror: %s\n", ber_ind, errstr(err, i, i));
		ber_ind = ber_ind_save;
	}
	return (err, i, elem);
}

# Decode a tag field.  As well as Tag, return an int that
# is 1 if the type is constructed, 0 if not.
tag_decode(a: array of byte, i, n: int) : (int, int, Tag)
{
	err := OK;
	class, num, constr: int;
	if(n-i >= 2) {
		v := int a[i++];
		class = v & CLASS_MASK;
		if(v & CONSTR_MASK)
			constr = 1;
		else
			constr = 0;
		num = v & TAG_MASK;
		if(num == TAG_MASK)
			# long tag number
			(err, i, num) = uint7_decode(a, i, n);
	}
	else
		err = ESHORT;
	return (err, i, Tag(class, num, constr));
}

# Decode a length field.  Assume it fits in a Limbo int.
# If "indefinite length", return -1.
length_decode(a: array of byte, i, n: int) : (int, int, int)
{
	err := OK;
	num := 0;
	if(i < n) {
		v := int a[i++];
		if(v & 16r80)
			return int_decode(a, i, n, v&16r7F, 1);
		else if(v == 16r80)
			num = -1;
		else
			num = v;
	}
	else
		err = ESHORT;
	return (err, i, num);
}

# Decode a value according to the encoding of the Universal
# type with number "kind" and constructed/primitive according
# to "constr", with given length (may be -1, for "indefinite").
value_decode(a: array of byte, i, n, length, kind, constr: int) : (int, int, ref Value)
{
	err := OK;
	val : ref Value;
	va : array of byte;
	if(length == -1) {
		if(!constr)
			err = EINVAL;
	}
	else if(i+length > n)
		err = EVALLEN;
	if(err != OK)
		return (err, i, nil);
	case kind {
	0 =>
		# marker for end of indefinite constructions
		if(length == 0)
			val = ref Value.EOC;
		else
			err = EINVAL;
	BOOLEAN =>
		if(constr)
			err = ECONSTR;
		else if(length != 1)
			err = EVALLEN;
		else {
			val = ref Value.Bool(int a[0]);
			i++;
		}
	INTEGER or ENUMERATED =>
		if(constr)
			err = ECONSTR;
		else if(length <= 4) {
			num : int;
			(err, i, num) = int_decode(a, i, i+length, length, 0);
			if(err == OK)
				val = ref Value.Int(num);
		}
		else {
			va = array[length] of byte;
			va[0:] = a[i:i+length];
			val = ref Value.BigInt(va);
			i += length;
		}
	BIT_STRING =>
		if(constr) {
			if(length == -1 && i+2 <= n && a[i] == byte 0 && a[i+1] == byte 0) {
				val = ref Value.BitString(0, nil);
				i += 2;
			}
			else
				# TODO: recurse and concat results
				err = EUNIMPL;
		}
		else {
			if(length < 2) {
				if(length == 1 && a[0] == byte 0) {
					val = ref Value.BitString(0, nil);
					i ++;
				}
				else
					err = EINVAL;
			}
			else {
				bitsunused := int a[i];
				if(bitsunused > 7)
					err = EINVAL;
				else if(length > 16r0FFFFFFF)
					err = ETOOBIG;
				else {
					va = array[length-1] of byte;
					va[0:] = a[i+1:i+length];
					val = ref Value.BitString(bitsunused, va);
					i += length;
				}
			}
		}
	OCTET_STRING or ObjectDescriptor =>
		(err, i, va) = octet_decode(a, i, n, length, constr);
		if(err == OK)
			val = ref Value.Octets(va);
	NULL =>
		if(constr)
			err = ECONSTR;
		else if(length != 0)
			err = EVALLEN;
		else
			val = ref Value.Null;
	OBJECT_ID =>
		if(constr)
			err = ECONSTR;
		else if (length == 0)
			err = EVALLEN;
		else {
			subids : list of int = nil;
			iend := i+length;
			while(i < iend) {
				x : int;
				(err, i, x) = uint7_decode(a, i, n);
				if(err != OK)
					break;
				subids = x :: subids;
			}
			if(err == OK) {
				if(i != iend)
					err = EVALLEN;
				else {
					m := len subids;
					ia := array[m+1] of int;
					while(subids != nil) {
						y := hd subids;
						subids = tl subids;
						if(m == 1) {
							ia[1] = y % 40;
							ia[0] = y / 40;
						}
						else
							ia[m--] = y;
					}
					val = ref Value.ObjId(ref Oid(ia));
				}
			}
		}
	EXTERNAL or EMBEDDED_PDV =>
		# TODO: parse this internally
		va = array[length] of byte;
		va[0:] = a[i:i+length];
		val = ref Value.Other(va);
		i += length;
	REAL =>
		# let the appl decode, with math module
		if(constr)
			err = ECONSTR;
		else {
			va = array[length] of byte;
			va[0:] = a[i:i+length];
			val = ref Value.Real(va);
			i += length;
		}
	SEQUENCE or SET=>
		vl : list of ref Elem;
		(err, i, vl) = seq_decode(a, i, n, length, constr);
		if(err == OK) {
			if(kind == SEQUENCE)
				val = ref Value.Seq(vl);
			else
				val = ref Value.Set(vl);
		}
	NumericString or PrintableString or TeletexString
	or VideotexString or IA5String or UTCTime
	or GeneralizedTime or GraphicString or VisibleString
	or GeneralString or UniversalString or BMPString =>
		(err, i, va) = octet_decode(a, i, n, length, constr);
		if(err == OK)
			# sometimes wrong: need to do char set conversion
			val = ref Value.String(string va);
		
	* =>
		va = array[length] of byte;
		va[0:] = a[i:i+length];
		val = ref Value.Other(va);
		i += length;
	}
	return (err, i, val);
}

# Decode an int in format where count bytes are
# concatenated to form value.
# Although ASN1 allows any size integer, we return
# an error if the result doesn't fit in a Limbo int.
# If unsigned is not set, make sure to propagate sign bit.
int_decode(a: array of byte, i, n, count, unsigned: int) : (int, int, int)
{
	err := OK;
	num := 0;
	if(n-i >= count) {
		if((count > 4) || (unsigned && count == 4 && (int a[i] & 16r80)))
			err = ETOOBIG;
		else {
			if(!unsigned && count > 0 && count < 4 && (int a[i] & 16r80))
				num = -1;		# all bits set
			for(j := 0; j < count; j++) {
				v := int a[i++];
				num = (num << 8) | v;
			}
		}
	}
	else
		err = ESHORT;
	return (err, i, num);
}

# Decode an unsigned int in format where each
# byte except last has high bit set, and remaining
# seven bits of each byte are concatenated to form value.
# Although ASN1 allows any size integer, we return
# an error if the result doesn't fit in a Limbo int.
uint7_decode(a: array of byte, i, n: int) : (int, int, int)
{
	err := OK;
	num := 0;
	more := 1;
	while(more && i < n) {
		v := int a[i++];
		if(num & 16r7F000000) {
			err = ETOOBIG;
			break;
		}
		num <<= 7;
		more = v & 16r80;
		num |= (v & 16r7F);
	}
	if(n == i)
		err = ESHORT;
	return (err, i, num);
}

# Decode an octet string, recursively if constr.
# We've already checked that length==-1 implies constr==1,
# and otherwise that specified length fits within a[i..n].
octet_decode(a: array of byte, i, n, length, constr: int) : (int, int, array of byte)
{
	err := OK;
	va : array of byte;
	if(length >= 0 && !constr) {
		va = array[length] of byte;
		va[0:] = a[i:i+length];
		i += length;
	}
	else {
		# constructed, either definite or indefinite length
		lva : list of array of byte = nil;
		elem : ref Elem;
		istart := i;
		totbytes := 0;
	    cloop:
		for(;;) {
			if(length >= 0 && i >= istart+length) {
				if(i != istart+length)
					err = EVALLEN;
				break cloop;
			}
			oldi := i;
			(err, i, elem) = ber_decode(a, i, n);
			if(err != OK)
				break;
			pick v := elem.val {
				Octets =>
					lva = v.bytes :: lva;
					totbytes += len v.bytes;
				EOC =>
					if(length != -1) {
						i = oldi;
						err = EINVAL;
					}
					break cloop;
				* =>
					i = oldi;
					err = EINVAL;
					break cloop;
			}
		}
		if(err == OK) {
			va = array[totbytes] of byte;
			j := totbytes;
			while(lva != nil) {
				x := hd lva;
				lva = tl lva;
				m := len x;
				va[j-m:] = x[0:];
				j -= m;
			}
		}
	}
	return (err, i, va);
}

# Decode a sequence or set.
# We've already checked that length==-1 implies constr==1,
# and otherwise that specified length fits within a[i..n].
seq_decode(a : array of byte, i, n, length, constr: int) : (int, int, list of ref Elem)
{
	err := OK;
	ans : list of ref Elem = nil;
	if(!constr)
		err = EPRIM;
	else {
		# constructed, either definite or indefinite length
		lve : list of ref Elem = nil;
		elem : ref Elem;
		istart := i;
	    cloop:
		for(;;) {
			if(length >= 0 && i >= istart+length) {
				if(i != istart+length)
					err = EVALLEN;
				break cloop;
			}
			oldi := i;
			(err, i, elem) = ber_decode(a, i, n);
			if(err != OK)
				break;
			pick v := elem.val {
				EOC =>
					if(length != -1) {
						i = oldi;
						err = EINVAL;
					}
					break cloop;
				* =>
					lve = elem :: lve;
			}
		}
		if(err == OK) {
			# reverse back to original order
			while(lve != nil) {
				e := hd lve;
				lve = tl lve;
				ans = e :: ans;
			}
		}
	}
	return (err, i, ans);
}

# Encode e by BER rules
encode(e: ref Elem) : (string, array of byte)
{
	(err, n) := enc(nil, e, 0, 1);
	if(err != "")
		return (err, nil);
	b := array[n] of byte;
	enc(b, e, 0, 0);
	return ("", b);
}

# Encode e into array b, only putting in bytes if !lenonly.
# Start at loc i, return index after.
enc(b: array of byte, e: ref Elem, i, lenonly: int) : (string, int)
{
	(err, vlen, constr) := val_enc(b, e, 0, 1);
	if(err != "")
		return (err, i);
	tag := e.tag;
	v := tag.class | constr;
	if(tag.num < 31) {
		if(!lenonly)
			b[i] = byte (v | tag.num);
		i++;
	}
	else {
		if(!lenonly)
			b[i] = byte (v | 31);
		if(tag.num < 0)
			return ("negative tag number", i);
		i = uint7_enc(b, tag.num, i+1, lenonly);
	}
	if(vlen < 16r80) {
		if(!lenonly)
			b[i] = byte vlen;
		i++;
	}
	else {
		ilen := int_enc(b, vlen, 1, 0, 1);
		if(!lenonly) {
			b[i] = byte (16r80 | ilen);
			i = int_enc(b, vlen, 1, i+1, 0);
		}
		else
			i += 1+ilen;
	}
	if(!lenonly)
		val_enc(b, e, i, 0);
	i += vlen;
	return ("", i);
}

# Encode e.val into array b, only putting in bytes if !lenonly.
# Start at loc i, return (err, index after, constructed or primitive)
val_enc(b: array of byte, e: ref Elem, i, lenonly: int) : (string, int, int)
{
	kind := e.tag.num;
	cl := e.tag.class;
	ok := 1;
	v : int;
	bb : array of byte;
	constr := 0;
	if(cl != Universal) {
		pick vv := e.val {
		Bool =>
			kind = BOOLEAN;
		Int =>
			kind = INTEGER;
		BigInt =>
			kind = INTEGER;
		Octets =>
			kind = OCTET_STRING;
		Real =>
			kind = REAL;
		Other =>
			kind = OCTET_STRING;
		BitString =>
			kind = BIT_STRING;
		Null =>
			kind = NULL;
		ObjId =>
			kind = OBJECT_ID;
		String =>
			kind = UniversalString;
		Seq =>
			kind = SEQUENCE;
		Set =>
			kind = SET;
		}
	}
	case kind {
	BOOLEAN =>
		(ok, v) = e.is_int();
		if(ok) {
			if(v != 0)
				v = 255;
			i = int_enc(b, v, 1, i, lenonly);
		}
	INTEGER or ENUMERATED =>
		(ok, v) = e.is_int();
		if(ok)
			i = int_enc(b, v, 0, i, lenonly);
		else {
			(ok, bb) = e.is_bigint();
			if(ok) {
				if(!lenonly)
					b[i:] = bb;
				i += len bb;
			}
		}
	BIT_STRING =>
		(ok, v, bb) = e.is_bitstring();
		if(ok) {
			if(bb == nil) {
				if(!lenonly)
					b[i] = byte 0;
				i++;
			}
			else {
				if(v < 0 || v > 7)
					ok = 0;
				else {
					if(!lenonly) {
						b[i] = byte v;
						b[i+1:] = bb;
					}
					i += 1 + len bb;
				}
			}
		}
	OCTET_STRING or ObjectDescriptor or EXTERNAL or REAL
	or EMBEDDED_PDV =>
		pick vv := e.val {
		Octets or Real or Other =>
			if(!lenonly && vv.bytes != nil)
					b[i:] = vv.bytes;
			i += len vv.bytes;
		 * =>
			ok = 0;
		}
	NULL =>
		;
	OBJECT_ID =>
		oid : ref Oid;
		(ok, oid) = e.is_oid();
		if(ok) {
			n := len oid.nums;
			for(k := 0; k < n; k++) {
				v = oid.nums[k];
				if(k == 0) {
					v *= 40;
					if(n > 1)
						v += oid.nums[++k];
				}
				i = uint7_enc(b, v, i, lenonly);
			}
		}
	SEQUENCE or SET =>
		pick vv := e.val {
		Seq or Set =>
			constr = CONSTR_MASK;
			for(l := vv.l; l != nil; l = tl l) {
				err : string;
				(err, i) = enc(b, hd l, i, lenonly);
				if(err != "")
					return (err, i, 0);
			}
	}
	NumericString or PrintableString or TeletexString
	or VideotexString or IA5String or UTCTime
	or GeneralizedTime or GraphicString or VisibleString
	or GeneralString or UniversalString or BMPString =>
		pick vv := e.val {
			String =>
				bb = array of byte vv.s;
				if(!lenonly && bb != nil)
					b[i:] = bb;
				i += len bb;
			* =>
				ok = 0;
		}
	* =>
		ok = 0;
	}
	if(!ok)
		return ("bad value for encoding kind", i, constr);
	return ("", i, constr);
}

# Encode num as unsigned 7 bit values with top bit 1 on all bytes
# except last, into array b, only putting in bytes if !lenonly.
# Start at loc i, return index after.
uint7_enc(b: array of byte, num, i, lenonly: int) : int
{
	n := 1;
	v := num>>7;
	while(v > 0) {
		v >>= 7;
		n++;
	}
	if(lenonly)
		i += n;
	else {
		for(k := (n-1)*7; k > 0; k -= 7)
			b[i++] = byte ((num>>k) | 16r80);
		b[i++] = byte (num & 16r7F);
	}
	return i;
}

# Encode num as unsigned or signed integer into array b,
# only putting in bytes if !lenonly.
# Encoding is length followed by bytes to concatenate.
# Start at loc i, return index after.
int_enc(b: array of byte, num, unsigned, i, lenonly: int) : int
{
	v := num;
	if(v < 0)
		v = -(v+1);
	n := 1;
	prevv := v;
	v >>= 8;
	while(v > 0) {
		prevv = v;
		v >>= 8;
		n++;
	}
	if(!unsigned && (prevv & 16r80))
		n++;
	if(lenonly)
		i += n;
	else {
		for(k := (n-1)*8; k >= 0; k -= 8)
			b[i++] = byte (num>>k);
	}
	return i;
}

# Compare two arrays of integers; return true if they match
intarr_eq(a: array of int, b: array of int) : int
{
	alen := len a;
	if(alen != len b)
		return 0;
	for(i := 0; i < alen; i++)
		if(a[i] != b[i])
			return 0;
	return 1;
}

# Look for o in tab; if found, return index, else return -1.
oid_lookup(o: ref Oid, tab: array of Oid) : int
{
	for(i := 0; i < len tab; i++)
		if(intarr_eq(o.nums, tab[i].nums))
			return i;
	return -1;
}

# If e is a SEQUENCE, return (1, e's element list)
# else return (error, nil).
Elem.is_seq(e: self ref Elem) : (int, list of ref Elem)
{
	if(e.tag.class == Universal && e.tag.num == SEQUENCE) {
		pick v := e.val {
		Seq =>
			return (1, v.l);
		}
	}
	return (0, nil);
}

# If e is a SET, return (1, e's element list)
# else return (error, nil).
Elem.is_set(e: self ref Elem) : (int, list of ref Elem)
{
	if(e.tag.class == Universal && e.tag.num == SET) {
		pick v := e.val {
		Set =>
			return (1, v.l);
		}
	}
	return (0, nil);
}

# If e is an INTEGER that fits in a limbo int, return (1, val)
# else return (0, 0l).
Elem.is_int(e: self ref Elem) : (int, int)
{
	if(e.tag.class == Universal && (e.tag.num == INTEGER || e.tag.num == BOOLEAN)) {
		pick v := e.val {
		Bool or
		Int =>
			return (1, v.v);
		}
	}
	return (0, 0);
}

# If e is an INTEGER that doesn't fit in a limbo int, return (1, bytes),
# or even if it does fit, return it as an array of bytes.
# else return (0, nil).
Elem.is_bigint(e: self ref Elem) : (int, array of byte)
{
	if(e.tag.class == Universal && e.tag.num == INTEGER) {
		pick v := e.val {
		BigInt =>
			return (1, v.bytes);
		Int =>
			x := v.v;
			a := array[4] of byte;
			for(i := 0; i < 4; i++)
				a[i] = byte ((x >> (8*(3-i))) & 16rFF);
			for(j := 0; j < 3; j++)
				if(a[j] != byte 0)
					break;
			return (1, a[j:]);
		}
	}
	return (0, nil);
}

# If e is a bitstring, return (1, unused bits, bytes containing bit string),
# else return (0, nil)
Elem.is_bitstring(e: self ref Elem) : (int, int, array of byte)
{
	if(e.tag.class == Universal && e.tag.num == BIT_STRING) {
		pick v := e.val {
		BitString =>
			return (1, v.unusedbits, v.bits);
		}
	}
	return (0, 0, nil);
}

# If e is an octetstring, return (1, bytes),
# else return (0, nil)
Elem.is_octetstring(e: self ref Elem) : (int, array of byte)
{
	if(e.tag.class == Universal && e.tag.num == OCTET_STRING) {
		pick v := e.val {
		Octets =>
			return (1, v.bytes);
		}
	}
	return (0, nil);
}

# If e is an object id, return (1, ref Oid),
# else return (0, nil)
Elem.is_oid(e: self  ref Elem) : (int, ref Oid)
{
	if(e.tag.class == Universal && e.tag.num == OBJECT_ID) {
		pick v := e.val {
		ObjId =>
			return (1, v.id);
		}
	}
	return (0, nil);
}

# If e is some kind of string (excluding times), return (1, string),
# else return (0, "")
Elem.is_string(e: self ref Elem) : (int, string)
{
	if(e.tag.class == Universal) {
		case e.tag.num {
		NumericString or PrintableString or TeletexString
		or VideotexString or IA5String or GraphicString
		or VisibleString or GeneralString or UniversalString
		or BMPString =>
		pick v := e.val {
			String =>
				return (1, v.s);
			}
		}
	}
	return (0, nil);
}

# If e is some kind of time, return (1, string),
# else return (0, "")
Elem.is_time(e: self ref Elem) : (int, string)
{
	if(e.tag.class == Universal
	   && (e.tag.num == UTCTime || e.tag.num == GeneralizedTime)) {
		pick v := e.val {
		String =>
			return (1, v.s);
		}
	}
	return (0, nil);
}

# Return printable error string for code ecode.
# i is position where error is first noted.
# n is the end of the passed data: if i!=n then
# we didn't use all the data and an error should
# be returned about that.
errstr(ecode, i, n: int) : string
{
	if(ecode == OK && i == n)
		return "";
	err := "BER decode: ";
	case ecode {
		OK =>
			err += "OK";
		ESHORT =>
			err += "need more data";
		ETOOBIG =>
			err += "value exceeds implementation limit";
		EVALLEN =>
			err += "value has wrong length";
		ECONSTR =>
			err += "value is constructed, should be primitive";
		EPRIM =>
			err += "value is primitive";
		EINVAL =>
			err += "value encoding invalid";
		* =>
			err += "unknown error " + string ecode;
	}
	if(err == "" && i != n)
		err += "extra data";
	err += " at byte " + string i;
	return err;
}

# Printing functions, for debugging

Tag.tostring(t: self Tag) : string
{
	ans := "";
	snum := string t.num;
	if(t.class == Universal) {
		case t.num {
		BOOLEAN => ans = "BOOLEAN";
		INTEGER => ans = "INTEGER";
		BIT_STRING => ans = "BIT STRING";
		OCTET_STRING => ans = "OCTET STRING";
		NULL => ans = "NULL";
		OBJECT_ID => ans = "OBJECT IDENTIFER";
		ObjectDescriptor => ans = "OBJECT_DES";
		EXTERNAL => ans = "EXTERNAL";
		REAL => ans = "REAL";
		ENUMERATED => ans = "ENUMERATED";
		EMBEDDED_PDV => ans = "EMBEDDED PDV";
		SEQUENCE => ans = "SEQUENCE";
		SET => ans = "SET";
		NumericString => ans = "NumericString";
		PrintableString => ans = "PrintableString";
		TeletexString => ans = "TeletexString";
		VideotexString => ans = "VideotexString";
		IA5String => ans = "IA5String";
		UTCTime => ans = "UTCTime";
		GeneralizedTime => ans = "GeneralizedTime";
		GraphicString => ans = "GraphicString";
		VisibleString => ans = "VisibleString";
		GeneralString => ans = "GeneralString";
		UniversalString => ans = "UniversalString";
		BMPString => ans = "BMPString";
		* => ans = "UNIVERSAL " + snum;
		}
	}
	else {
		case t.class {
		Application =>
			ans = "APPLICATION " + snum;
		Context =>
			ans = "CONTEXT "+ snum;
		Private =>
			ans = "PRIVATE " + snum;
		}
	}
	return ans;
}

Elem.tostring(e: self ref Elem) : string
{
	return estring(e, "");
}

Value.tostring(v: self ref Value) : string
{
	return vstring(v, "");
}

estring(e: ref Elem, indent: string) : string
{
	return indent + e.tag.tostring() + " " + vstring(e.val, indent);
}

vstring(val: ref Value, indent: string) : string
{
	ans := "";
	pick v := val {
		Bool or Int =>
			ans += string v.v;
		Octets or BigInt or Real or Other =>
			ans += bastring(v.bytes, indent + "\t");
		BitString =>
			ans += " bits (unused " +string v.unusedbits + ")" +  bastring(v.bits, indent + "\t");
		Null  or EOC =>
			;
		ObjId =>
			ans += v.id.tostring();
		String =>
			ans += "\"" + v.s + "\"";
		Seq or Set =>
			ans += "{\n";
			newindent := indent + "\t";
			l := v.l;
			while(l != nil) {
				if(ans[len ans-1] != '\n')
					ans[len ans] = '\n';
				ans += estring(hd l, newindent);
				l = tl l;
			}
			if(ans[len ans-1] != '\n')
				ans[len ans] = '\n';
			ans += indent + "}";
	}
	return ans;
}

bastring(a: array of byte, indent: string) : string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	ans := indent;
	nlindent := "\n" + indent;
	for(i := 0; i < len a; i++) {
		if(i < len a - 1 && i%10 == 0)
			ans += nlindent ;
		ans += sys->sprint("%2x ", int a[i]);
	}
	return ans;
}

Oid.tostring(o: self ref Oid) : string
{
	ans := "";
	for(i := 0; i < len o.nums; i++) {
		ans += string o.nums[i];
		if(i < len o.nums - 1)
			ans[len ans] = '.';
	}
	return ans;
}

print_elem(e: ref Elem)
{
	s := e.tostring();
	a := array of byte s;
	sys->write(sys->fildes(1), a, len a);
	sys->print("\n");
}
