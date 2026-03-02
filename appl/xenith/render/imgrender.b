implement Renderer;

#
# Image renderer - wraps Xenith's imgload module to conform to the
# Renderer interface.  Handles PNG, PPM, PGM, PBM, BIT, PIC formats.
#
# This is the reference renderer implementation: it delegates all
# actual decoding to imgload and adapts the progress/result types.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	drawm: Draw;
	Display, Image, Rect, Point: import drawm;

include "renderer.m";

# We load imgload dynamically to avoid a hard compile-time dependency.
# This keeps the renderer self-contained and loadable from anywhere.
Imgload: module {
	PATH: con "/dis/xenith/imgload.dis";

	ImgProgress: adt {
		image: ref Draw->Image;
		rowsdone: int;
		rowstotal: int;
	};

	init: fn(d: ref Draw->Display);
	readimage: fn(path: string): (ref Draw->Image, string);
	readimagedata: fn(data: array of byte, hint: string): (ref Draw->Image, string);
	readimagedataprogressive: fn(data: array of byte, hint: string,
	                             progress: chan of ref ImgProgress): (ref Draw->Image, string);
};

imgload: Imgload;
display: ref Display;

init(d: ref Draw->Display)
{
	sys = load Sys Sys->PATH;
	drawm = load Draw Draw->PATH;
	display = d;

	imgload = load Imgload Imgload->PATH;
	if(imgload != nil)
		imgload->init(d);
}

info(): ref RenderInfo
{
	return ref RenderInfo(
		"Image",
		".png .ppm .pgm .pbm .bit .pic",
		0  # Images have no text content
	);
}

canrender(data: array of byte, hint: string): int
{
	if(data == nil || len data < 8)
		return 0;

	# PNG magic: 137 80 78 71 13 10 26 10
	if(data[0] == byte 137 && data[1] == byte 80 &&
	   data[2] == byte 78 && data[3] == byte 71 &&
	   data[4] == byte 13 && data[5] == byte 10 &&
	   data[6] == byte 26 && data[7] == byte 10)
		return 100;

	# PPM/PGM/PBM magic: P3, P5, P6
	if(data[0] == byte 'P'){
		c := int data[1];
		if(c == '3' || c == '5' || c == '6')
			return 90;
	}

	return 0;
}

render(data: array of byte, hint: string,
       width, height: int,
       progress: chan of ref RenderProgress): (ref Draw->Image, string, string)
{
	if(imgload == nil)
		return (nil, nil, "image loader not available");

	# Create an adapter channel for imgload's progress format
	imgprogress := chan[4] of ref Imgload->ImgProgress;

	# Spawn a forwarder that converts ImgProgress -> RenderProgress
	spawn progressadapter(imgprogress, progress);

	# Delegate to imgload
	(im, err) := imgload->readimagedataprogressive(data, hint, imgprogress);

	# Signal end of progress
	imgprogress <-= nil;

	# No text content for images
	return (im, nil, err);
}

commands(): list of ref Command
{
	return
		ref Command("Zoom+", "b3", "+", "2") ::
		ref Command("Zoom-", "b3", "-", "2") ::
		ref Command("Fit", "b3", "f", nil) ::
		ref Command("1:1", "b3", "1", nil) ::
		ref Command("Grab", "b3", "g", nil) ::
		ref Command("Rotate", "b3", "r", "90") ::
		nil;
}

command(cmd: string, arg: string,
        data: array of byte, hint: string,
        width, height: int): (ref Draw->Image, string)
{
	# Image commands will be implemented as the renderer gains state.
	# For now, re-render from source data is the pattern.
	case cmd {
	"Zoom+" or "Zoom-" or "Fit" or "1:1" or "Grab" or "Rotate" =>
		return (nil, "not yet implemented: " + cmd);
	* =>
		return (nil, "unknown command: " + cmd);
	}
}

# Convert imgload progress updates to renderer progress updates
progressadapter(src: chan of ref Imgload->ImgProgress,
                dst: chan of ref RenderProgress)
{
	for(;;){
		p := <-src;
		if(p == nil)
			return;

		rp := ref RenderProgress(p.image, p.rowsdone, p.rowstotal);
		# Non-blocking send - drop if consumer is slow
		alt {
			dst <-= rp => ;
			* => ;
		}
	}
}
