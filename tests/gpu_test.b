implement GpuTest;

#
# gpu_test - Unit tests for the GPU compute module
#
# Tests GPU module initialization, info queries, model loading,
# and inference through the built-in $GPU module. Tests that
# require actual GPU hardware are skipped if unavailable.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

include "gpu.m";
	gpu: GPU;

GpuTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/gpu_test.b";
TESTMODEL: con "/lib/gpu/gpu_classifier.plan";

passed := 0;
failed := 0;
skipped := 0;

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	{
		testfn(t);
	} exception {
	"fail:fatal" =>
		;
	"fail:skip" =>
		;
	"*" =>
		t.failed = 1;
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

# Test that the GPU module can be loaded
testLoadModule(t: ref T)
{
	t.assert(gpu != nil, "GPU module loaded");
}

# Test GPU initialization
testInit(t: ref T)
{
	err := gpu->init();
	if(err != nil) {
		t.skip("GPU not available: " + err);
		return;
	}
	t.assert(1, "GPU init succeeded");
}

# Test GPU info query
testGpuInfo(t: ref T)
{
	err := gpu->init();
	if(err != nil) {
		t.skip("GPU not available: " + err);
		return;
	}

	info := gpu->gpuinfo();
	t.assert(info != nil, "gpuinfo returned non-nil");
	t.assert(len info > 0, "gpuinfo returned non-empty string");
	t.log("GPU info: " + info);

	# Should contain basic GPU identifiers
	t.assert(contains(info, "|"), "gpuinfo contains pipe separators");
	t.assert(contains(info, "CUDA"), "gpuinfo mentions CUDA");
	t.assert(contains(info, "TensorRT"), "gpuinfo mentions TensorRT");
}

# Test loading a non-existent model
testLoadBadModel(t: ref T)
{
	err := gpu->init();
	if(err != nil) {
		t.skip("GPU not available: " + err);
		return;
	}

	(handle, lerr) := gpu->loadmodel("/nonexistent/model.plan");
	t.assert(lerr != nil, "loading nonexistent model returns error");
	t.log("expected error: " + lerr);
	# Handle should be 0 (default) when error
	(nil, nil) = (handle, handle);  # suppress unused warning
}

# Test inference with no model loaded (invalid handle)
testInferBadHandle(t: ref T)
{
	err := gpu->init();
	if(err != nil) {
		t.skip("GPU not available: " + err);
		return;
	}

	input := array[10] of byte;
	(result, ierr) := gpu->infer(99, input);
	t.assert(ierr != nil, "infer with bad handle returns error");
	t.assertseq(result, nil, "infer with bad handle returns nil result");
	t.log("expected error: " + ierr);
}

# Test unload with invalid handle
testUnloadBadHandle(t: ref T)
{
	err := gpu->init();
	if(err != nil) {
		t.skip("GPU not available: " + err);
		return;
	}

	uerr := gpu->unloadmodel(99);
	t.assert(uerr != nil, "unload bad handle returns error");
	t.log("expected error: " + uerr);
}

# Test modelinfo with invalid handle
testModelInfoBadHandle(t: ref T)
{
	err := gpu->init();
	if(err != nil) {
		t.skip("GPU not available: " + err);
		return;
	}

	info := gpu->modelinfo(99);
	t.assert(info != nil, "modelinfo bad handle returns non-nil");
	t.log("modelinfo(99): " + info);
}

# Test loading a real model if available
testLoadRealModel(t: ref T)
{
	err := gpu->init();
	if(err != nil) {
		t.skip("GPU not available: " + err);
		return;
	}

	# Check if test model exists
	planpath := TESTMODEL;
	fd := sys->open(planpath, Sys->OREAD);
	if(fd == nil) {
		t.skip("test model not found: " + planpath);
		return;
	}
	fd = nil;

	(handle, lerr) := gpu->loadmodel(planpath);
	if(lerr != nil) {
		t.error("loadmodel failed: " + lerr);
		return;
	}
	t.assert(handle >= 0, "loadmodel returned valid handle");
	t.log(sys->sprint("loaded model, handle=%d", handle));

	# Check model info
	info := gpu->modelinfo(handle);
	t.assert(info != nil, "modelinfo returns info");
	t.assert(len info > 0, "modelinfo non-empty");
	t.log("model info: " + info);

	# Unload
	uerr := gpu->unloadmodel(handle);
	t.assertnil(uerr, "unload succeeded");
}

# Test inference with a real model and raw tensor data
testInferRealModel(t: ref T)
{
	err := gpu->init();
	if(err != nil) {
		t.skip("GPU not available: " + err);
		return;
	}

	planpath := TESTMODEL;
	fd := sys->open(planpath, Sys->OREAD);
	if(fd == nil) {
		t.skip("test model not found: " + planpath);
		return;
	}
	fd = nil;

	# Load model
	(handle, lerr) := gpu->loadmodel(planpath);
	if(lerr != nil) {
		t.skip("cannot load model: " + lerr);
		return;
	}

	# Create raw float tensor input for gpu_classifier model
	# Model expects [1,3,224,224] = 150528 floats = 602112 bytes
	# Fill with a simple pattern (normalized pixel values)
	nfloats := 1 * 3 * 224 * 224;
	buf := array[nfloats * 4] of byte;
	for(i := 0; i < nfloats; i++) {
		# Write float 0.5 in little-endian IEEE 754
		# 0.5f = 0x3F000000
		off := i * 4;
		buf[off+0] = byte 16r00;
		buf[off+1] = byte 16r00;
		buf[off+2] = byte 16r00;
		buf[off+3] = byte 16r3F;
	}

	# Run inference
	(result, ierr) := gpu->infer(handle, buf);
	if(ierr != nil)
		t.error("inference failed: " + ierr);
	else {
		t.assert(result != nil, "inference returned result");
		t.assert(len result > 0, "inference result non-empty");
		t.log("inference result:\n" + result);
	}

	# Cleanup
	gpu->unloadmodel(handle);
}

# Test multiple init calls are idempotent
testDoubleInit(t: ref T)
{
	err1 := gpu->init();
	err2 := gpu->init();

	if(err1 != nil) {
		t.skip("GPU not available: " + err1);
		return;
	}

	t.assertnil(err2, "second init also succeeds");
}

# Test inference with empty input
testInferEmptyInput(t: ref T)
{
	err := gpu->init();
	if(err != nil) {
		t.skip("GPU not available: " + err);
		return;
	}

	planpath := TESTMODEL;
	fd := sys->open(planpath, Sys->OREAD);
	if(fd == nil) {
		t.skip("test model not found: " + planpath);
		return;
	}
	fd = nil;

	(handle, lerr) := gpu->loadmodel(planpath);
	if(lerr != nil) {
		t.skip("cannot load model: " + lerr);
		return;
	}

	# Empty input should fail gracefully
	empty := array[0] of byte;
	(nil, ierr) := gpu->infer(handle, empty);
	t.assert(ierr != nil, "infer with empty input returns error");
	t.log("expected error: " + ierr);

	gpu->unloadmodel(handle);
}

# --- Helpers ---

contains(s, sub: string): int
{
	if(len sub > len s)
		return 0;
	for(i := 0; i <= len s - len sub; i++) {
		if(s[i:i+len sub] == sub)
			return 1;
	}
	return 0;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	# Load GPU module
	gpu = load GPU GPU->PATH;
	if(gpu == nil) {
		sys->fprint(sys->fildes(2), "cannot load GPU module: %r\n");
		raise "fail:cannot load GPU";
	}

	# Run tests
	run("LoadModule", testLoadModule);
	run("Init", testInit);
	run("DoubleInit", testDoubleInit);
	run("GpuInfo", testGpuInfo);
	run("LoadBadModel", testLoadBadModel);
	run("InferBadHandle", testInferBadHandle);
	run("UnloadBadHandle", testUnloadBadHandle);
	run("ModelInfoBadHandle", testModelInfoBadHandle);
	run("LoadRealModel", testLoadRealModel);
	run("InferEmptyInput", testInferEmptyInput);
	run("InferRealModel", testInferRealModel);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
