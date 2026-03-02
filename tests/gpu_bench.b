implement GpuBench;

#
# gpu_bench - GPU inference benchmark
# Runs inference in a loop to verify GPU utilization
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "gpu.m";
	gpu: GPU;

GpuBench: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

PLANPATH: con "/lib/gpu/gpu_classifier.plan";
ITERATIONS: con 100;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	gpu = load GPU GPU->PATH;
	if(gpu == nil) {
		sys->print("FAIL: cannot load GPU module: %r\n");
		raise "fail:load";
	}

	err := gpu->init();
	if(err != nil) {
		sys->print("FAIL: GPU init: %s\n", err);
		raise "fail:init";
	}

	sys->print("GPU: %s\n", gpu->gpuinfo());

	(handle, lerr) := gpu->loadmodel(PLANPATH);
	if(lerr != nil) {
		sys->print("FAIL: loadmodel: %s\n", lerr);
		raise "fail:load";
	}
	sys->print("Model loaded: %s\n", gpu->modelinfo(handle));

	# Create raw float tensor input [1,3,224,224] = 150528 floats = 602112 bytes
	nfloats := 1 * 3 * 224 * 224;
	buf := array[nfloats * 4] of byte;
	for(i := 0; i < nfloats; i++) {
		off := i * 4;
		buf[off+0] = byte 16r00;
		buf[off+1] = byte 16r00;
		buf[off+2] = byte 16r00;
		buf[off+3] = byte 16r3F;
	}

	sys->print("Running %d inferences...\n", ITERATIONS);
	t0 := sys->millisec();

	for(j := 0; j < ITERATIONS; j++) {
		(nil, ierr) := gpu->infer(handle, buf);
		if(ierr != nil) {
			sys->print("FAIL at iteration %d: %s\n", j, ierr);
			raise "fail:infer";
		}
	}

	t1 := sys->millisec();
	elapsed := t1 - t0;
	sys->print("Done: %d inferences in %dms (%.1f infer/sec)\n",
		ITERATIONS, elapsed, real ITERATIONS * 1000.0 / real elapsed);

	gpu->unloadmodel(handle);
}
