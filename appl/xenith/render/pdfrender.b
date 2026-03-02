implement Renderer;

#
# PDF renderer - thin wrapper around the PDF module.
#
# Renders PDF pages natively using Inferno's Draw primitives.
# Text extraction provided for the body buffer so the AI can
# read document content.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	drawm: Draw;
	Display, Image, Font, Rect, Point: import drawm;

include "renderer.m";

include "pdf.m";
	pdf: PDF;
	Doc: import pdf;

display: ref Display;
curdoc: ref Doc;
curpage := 1;
totalpages := 0;
curdpi := 300;
stderr: ref Sys->FD;

# Max PDF size for in-memory parsing
MAXPARSE: con 64*1024*1024;

init(d: ref Display)
{
	sys = load Sys Sys->PATH;
	drawm = load Draw Draw->PATH;
	display = d;
	stderr = sys->fildes(2);

	pdf = load PDF PDF->PATH;
	if(pdf == nil)
		sys->fprint(stderr, "pdfrender: cannot load PDF module: %r\n");
	else {
		err := pdf->init(d);
		if(err != nil)
			sys->fprint(stderr, "pdfrender: pdf init: %s\n", err);
	}
}

info(): ref RenderInfo
{
	return ref RenderInfo(
		"PDF",
		".pdf",
		1  # Has text content
	);
}

canrender(data: array of byte, hint: string): int
{
	if(len data >= 5 &&
	   data[0] == byte '%' && data[1] == byte 'P' &&
	   data[2] == byte 'D' && data[3] == byte 'F' &&
	   data[4] == byte '-')
		return 90;
	return 0;
}

render(data: array of byte, hint: string,
       width, height: int,
       progress: chan of ref RenderProgress): (ref Draw->Image, string, string)
{
	if(pdf == nil){
		progress <-= nil;
		return (nil, nil, "PDF module not available");
	}

	# Read file from path for parsing
	pdfdata := readpdffile(hint, MAXPARSE);
	if(pdfdata == nil)
		pdfdata = data;

	if(pdfdata == nil || len pdfdata < 5){
		progress <-= nil;
		return (nil, nil, "no PDF data");
	}

	doc: ref Doc;
	oerr: string;
	{
		(doc, oerr) = pdf->open(pdfdata, nil);
	} exception e {
	"*" =>
		progress <-= nil;
		return (nil, nil, "PDF open exception: " + e);
	}
	if(doc == nil){
		progress <-= nil;
		return (nil, nil, "PDF parse error: " + oerr);
	}

	curdoc = doc;
	totalpages = doc.pagecount();
	curpage = 1;

	# Extract text for body buffer
	text := "";
	{
		text = doc.extractall();
	} exception {
	"*" =>
		text = "[text extraction failed]";
	}
	if(text == nil || len text == 0)
		text = "[No extractable text in PDF]";

	# Render first page at curdpi — MAXPIX in pdf.b caps allocation
	im: ref Draw->Image;
	rerr: string;
	{
		(im, rerr) = doc.renderpage(curpage, curdpi);
	} exception e {
	"*" =>
		progress <-= nil;
		return (nil, text, "render exception: " + e);
	}
	pdfdata = nil;  # Free before return

	progress <-= nil;

	if(im == nil && rerr != nil)
		return (nil, text, "render: " + rerr);

	return (im, text, nil);
}

commands(): list of ref Command
{
	return
		ref Command("NextPage", "b2", "n", nil) ::
		ref Command("PrevPage", "b2", "p", nil) ::
		ref Command("FirstPage", "b2", "^", nil) ::
		ref Command("Zoom+", "b2", "+", nil) ::
		ref Command("Zoom-", "b2", "-", nil) ::
		nil;
}

command(cmd: string, arg: string,
        data: array of byte, hint: string,
        width, height: int): (ref Draw->Image, string)
{
	if(curdoc == nil)
		return (nil, "no document loaded");

	case cmd {
	"NextPage" =>
		if(curpage < totalpages)
			curpage++;
		else
			return (nil, nil);
	"PrevPage" =>
		if(curpage > 1)
			curpage--;
		else
			return (nil, nil);
	"FirstPage" =>
		curpage = 1;
	"Zoom+" =>
		curdpi += 25;
		if(curdpi > 600) curdpi = 600;
	"Zoom-" =>
		curdpi -= 25;
		if(curdpi < 50) curdpi = 50;
	* =>
		return (nil, "unknown command: " + cmd);
	}

	(im, err) := curdoc.renderpage(curpage, curdpi);
	if(im == nil)
		return (nil, "render page " + string curpage + ": " + err);
	return (im, nil);
}

# Read a PDF file up to maxsize bytes
readpdffile(path: string, maxsize: int): array of byte
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	(ok, dir) := sys->fstat(fd);
	if(ok != 0 || int dir.length <= 0)
		return nil;
	fsize := int dir.length;
	if(fsize > maxsize)
		return nil;
	data := array[fsize] of byte;
	total := 0;
	while(total < fsize){
		n := sys->read(fd, data[total:], fsize - total);
		if(n <= 0)
			break;
		total += n;
	}
	if(total < fsize)
		return nil;
	return data;
}
