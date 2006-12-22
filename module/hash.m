Hash: module{
	PATH: con "/dis/lib/hash.dis";
	fun1, fun2: fn(s:string,n:int):int;

	HashVal: adt{
		i: int;
		r: real;
		s: string;
	};
	HashNode: adt{
		key:string;
		val:ref HashVal;  # insert() can update contents
	};
	HashTable: adt{
		a:	array of list of HashNode;
		find:	fn(h:self ref HashTable, key:string):ref HashVal;
		insert:	fn(h:self ref HashTable, key:string, val:HashVal);
		delete:	fn(h:self ref HashTable, key:string);
		all:	fn(h:self ref HashTable): list of HashNode;
	};
	new: fn(size:int):ref HashTable;
};

