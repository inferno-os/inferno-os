CgiData : adt {
    method : string;
    version : string;
    uri : string;
    search : string;
    tmstamp : string;
    host : string;
    remote : string;
    referer : string;
    httphd : string;
    header : list of (string, string);
    form : list of (string, string);
};

CgiParse : module
{
    PATH : con "/dis/svc/httpd/cgiparse.dis";
    cgiparse : fn( g : ref Httpd->Private_info, req: Httpd->Request): ref CgiData;
    getbase : fn() : string;
    gethost : fn() : string;
};

