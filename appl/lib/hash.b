# ehg@research.bell-labs.com 14Dec1996
implement Hash;

include "hash.m";

# from Aho Hopcroft Ullman
fun1(s:string, n:int):int
{
	h := 0;
	m := len s;
	for(i:=0; i<m; i++){
		h = 65599*h+s[i];
	}
	return (h & 16r7fffffff) % n;
}

# from Limbo compiler
fun2(s:string, n:int):int
{
	h := 0;
	m := len s;
	for(i := 0; i < m; i++){
		c := s[i];
		d := c;
		c ^= c << 6;
		h += (c << 11) ^ (c >> 1);
		h ^= (d << 14) + (d << 7) + (d << 4) + d;
	}
	return (h & 16r7fffffff) % n;
}

new(size: int):ref HashTable
{
	return ref HashTable(array[size] of list of HashNode);
}

HashTable.find(h: self ref HashTable, key: string): ref HashVal
{
	j := fun1(key,len h.a);
	for(q := h.a[j]; q!=nil; q = tl q){
		if((hd q).key==key)
			return (hd q).val;
	}
	return nil;
}

HashTable.insert(h: self ref HashTable, key: string, val: HashVal)
{
	j := fun1(key,len h.a);
	for(q := h.a[j]; q!=nil; q = tl q){
		if((hd q).key==key){
			p := (hd q).val;
			p.i = val.i;
			p.r = val.r;
			p.s = val.s;
			return;
		}
	}
	h.a[j] = HashNode(key,ref HashVal(val.i,val.r,val.s)) :: h.a[j];
}

HashTable.delete(h:self ref HashTable, key:string)
{
	j := fun1(key,len h.a);
	dl:list of HashNode; dl = nil;
	for(q := h.a[j]; q!=nil; q = tl q){
		if((hd q).key!=key)
			dl = (hd q) :: dl;
	}
	h.a[j] = dl;
}

HashTable.all(h:self ref HashTable): list of HashNode
{
	dl:list of HashNode; dl = nil;
	for(j:=0; j<len h.a; j++)
		for(q:=h.a[j]; q!=nil; q = tl q)
			dl = (hd q) :: dl;
	return dl;
}
