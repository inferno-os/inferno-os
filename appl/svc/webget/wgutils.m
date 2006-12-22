WebgetUtils: module
{
	PATH: con "/dis/svc/webget/wgutils.dis";

	Req: adt
	{
		index:	int;
		method:	string;
		bodylen:	int;
		reqid:	string;
		loc:		string;
		types:	string;
		cachectl:	string;
		auth:		string;
		body:	array of byte;
		url:		ref Url->ParsedUrl;
		reply:	ref Message->Msg;
	};

	Fid: adt
	{
		fid:		int;
		link:		cyclic ref Fid;
		reqs:		array of ref Req;
		writer:	int;
		readr:	int;
		nbyte:	int;
		nread:	int;
		rc:		Sys->Rread;
	};

	M: Message;
	B: Bufio;
	S: String;
	U: Url;

	# media types (must track mnames array in wgutils.b)
	UnknownType,
	TextPlain, TextHtml,
	ApplPostscript, ApplRtf, ApplPdf,
	ImageJpeg, ImageGif, ImageIef, ImageTiff,
	ImageXCompressed, ImageXCompressed2, ImageXXBitmap,
	AudioBasic,
	VideoMpeg, VideoQuicktime: con iota;

	init : fn(m: Message, s: String, b: Bufio, u: Url, logfd: ref Sys->FD);
	usererr: fn(r: ref Req, msg: string) : ref Message->Msg;
	okprefix: fn(r: ref Req, mrep: ref Message->Msg);
	getdata: fn(io: ref Bufio->Iobuf, m: ref Message->Msg,
					accept: string, url: ref Url->ParsedUrl) : string;
	fixaccept: fn(a: string) : string;
	log: fn(c: ref Fid, msg: string);
};
