Transport: module
{
	init:		fn(w: WebgetUtils);
	connect:	fn(c: ref Fid, r: ref Req, donec: chan of ref Fid);
};
