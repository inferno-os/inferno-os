Parser: module {
	Runeself : con 	16r80;
	Word : con 1;

	PATH:  		con	"/dis/svc/httpd/parser.dis";

	init: fn();
	urlunesc: fn(s: string): string;
	fail: fn(g: ref Httpd->Private_info,reason: int, message: string);
	logit: fn(g: ref Httpd->Private_info, message: string );
	notmodified: fn(g: ref Httpd->Private_info);
	httpheaders: fn(g: ref Httpd->Private_info, vers: string);
	urlconv: fn(url : string): string;
	okheaders: fn(g: ref Httpd->Private_info);
};
