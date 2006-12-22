Redirect: module
{
	PATH: con "/dis/svc/httpd/redirect.dis";

	redirect_init: fn(file : string);
	redirect: fn(path : string): string;
};
