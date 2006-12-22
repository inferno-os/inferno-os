implement Dictionary;

#
# This is intended to be a simple dictionary of string tuples
# It is not intended for large data sets or efficient deletion of keys
#

include "dict.m";

Dict.add( d: self ref Dict, e: (string, string) )
{
	if (d.entries == nil) 
		d.entries =  e::nil;
	else 
		d.entries = e::d.entries;
}

Dict.delete( d: self ref Dict, k: string )
{
	key : string;
	newlist : list of (string, string);
	temp := d.entries;

	while (temp != nil) {
		(key,nil) = hd temp;
		if (key != k)
			newlist = (hd temp)::newlist;
		temp = tl temp;
	}
	d.entries = newlist;
}

Dict.lookup( d: self ref Dict, k: string ) :string
{
	key, value :string;
	temp := d.entries;
	while (temp != nil) {
		(key,value) = hd temp;
		if (key == k)
			return value;
		temp = tl temp;
	}
	return nil;
}

Dict.keys( d: self ref Dict ) :list of string
{
	key: string;
	keylist : list of string;
	temp := d.entries;
	while (temp != nil) {
		(key, nil) = hd temp;
		keylist = key::keylist;
		temp = tl temp;
	}
	return keylist;
}
