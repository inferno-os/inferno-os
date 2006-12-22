implement StringIntTab;

include "strinttab.m";

lookup(t: array of StringInt, key: string) : (int, int)
{
	min := 0;
	max := len t-1;
	while(min <= max){
		try := (min+max)/2;
		if(t[try].key < key)
			min = try+1;
		else if(t[try].key > key)
			max = try-1;
		else
			return (1, t[try].val);
	}
	return (0, 0);
}

revlookup(t: array of StringInt, val: int) : string
{
	n := len t;
	for(i:=0; i < n; i++)
		if(t[i].val == val)
			return t[i].key;
	return nil;
}
