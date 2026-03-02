implement GpuSmoke;

include "sys.m";
	sys: Sys;

include "draw.m";

include "gpu.m";
	gpu: GPU;

GpuSmoke: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	sys->print("Loading GPU module...\n");
	gpu = load GPU GPU->PATH;
	if(gpu == nil) {
		sys->print("FAIL: cannot load GPU module: %r\n");
		raise "fail:load";
	}
	sys->print("OK: GPU module loaded\n");

	sys->print("Initializing GPU...\n");
	err := gpu->init();
	if(err != nil) {
		sys->print("FAIL: GPU init: %s\n", err);
		raise "fail:init";
	}
	sys->print("OK: GPU initialized\n");

	info := gpu->gpuinfo();
	sys->print("GPU info: %s\n", info);

	# Test bad model load
	sys->print("Testing bad model load...\n");
	(handle, lerr) := gpu->loadmodel("/nonexistent.plan");
	if(lerr != nil)
		sys->print("OK: bad model load correctly failed: %s\n", lerr);
	else
		sys->print("UNEXPECTED: bad model load returned handle %d\n", handle);

	# Test bad handle
	sys->print("Testing bad handle infer...\n");
	input := array[4] of byte;
	(nil, ierr) := gpu->infer(99, input);
	if(ierr != nil)
		sys->print("OK: bad handle infer correctly failed: %s\n", ierr);
	else
		sys->print("UNEXPECTED: bad handle infer succeeded\n");

	sys->print("\nAll smoke tests passed!\n");
}
