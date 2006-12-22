Strcache: module {
	PATH: con "/dis/ebook/./strcache.dis";
	init:		fn(n: int);
	cache:	fn(s: string): string;
	flush:	fn(): string;
};
