Objstore: module {
	PATH: con "/dis/spree/lib/objstore.dis";

	init:			fn(mod: Spree, g: ref Clique);
	unarchive:	fn();
	setname:		fn(o: ref Object, name: string);
	get:			fn(name: string): ref Object;
};
