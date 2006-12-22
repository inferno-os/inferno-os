Image2enc: module
{
	PATH:	con "/dis/svc/webget/image2enc.dis";

	image2enc: fn(i: ref RImagefile->Rawimage, errdiff: int): (array of byte, array of byte, string);
};

