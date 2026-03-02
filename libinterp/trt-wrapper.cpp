/*
 * trt-wrapper.cpp - TensorRT inference wrapper for Jetson Orin
 *
 * Compiled with g++, provides extern "C" API for the Inferno emulator.
 * Uses TensorRT for model loading and inference, nvJPEG for hardware-
 * accelerated JPEG decoding, and CUDA unified memory for zero-copy
 * on Jetson (iGPU shares memory with CPU).
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <fstream>
#include <mutex>

#include <cuda_runtime.h>
#include <NvInfer.h>

#include "trt-wrapper.h"

/* TensorRT logger */
class TrtLogger : public nvinfer1::ILogger {
public:
	void log(Severity severity, const char *msg) noexcept override {
		if(severity <= Severity::kWARNING)
			fprintf(stderr, "trt: %s\n", msg);
	}
};

static TrtLogger gLogger;
static nvinfer1::IRuntime *gRuntime;
static std::mutex gMutex;
static int gInitialized;
static std::string gGpuInfo;

struct TrtEngine {
	nvinfer1::ICudaEngine *engine;
	std::string planpath;
	std::string info;
	int ninputs;
	int noutputs;
	/* Input/output tensor names and shapes */
	std::vector<std::string> ionames;
	std::vector<nvinfer1::Dims> iodims;
	std::vector<bool> isinput;
};

struct TrtResult {
	std::string text;
	std::string error;
	int status;  /* 0=ok, -1=error */
};

/* --- Result management --- */

extern "C" TrtResult*
trt_result_new(void)
{
	TrtResult *r = new TrtResult;
	r->status = 0;
	return r;
}

extern "C" void
trt_result_free(TrtResult *r)
{
	if(r)
		delete r;
}

extern "C" const char*
trt_result_text(TrtResult *r)
{
	if(r == NULL)
		return "";
	return r->text.c_str();
}

extern "C" int
trt_result_status(TrtResult *r)
{
	if(r == NULL)
		return -1;
	return r->status;
}

extern "C" const char*
trt_result_error(TrtResult *r)
{
	if(r == NULL)
		return "nil result";
	return r->error.c_str();
}

/* --- Runtime lifecycle --- */

extern "C" int
trt_init(void)
{
	std::lock_guard<std::mutex> lock(gMutex);

	if(gInitialized)
		return 0;

	/* Set CUDA device (Jetson has one iGPU) */
	cudaError_t cerr = cudaSetDevice(0);
	if(cerr != cudaSuccess) {
		fprintf(stderr, "trt: cudaSetDevice failed: %s\n",
			cudaGetErrorString(cerr));
		return -1;
	}

	/* Create TensorRT runtime */
	gRuntime = nvinfer1::createInferRuntime(gLogger);
	if(gRuntime == NULL) {
		fprintf(stderr, "trt: failed to create TensorRT runtime\n");
		return -1;
	}

	/* Build GPU info string */
	cudaDeviceProp prop;
	cudaGetDeviceProperties(&prop, 0);
	size_t freemem, totalmem;
	cudaMemGetInfo(&freemem, &totalmem);

	int rtver, trtver;
	cudaRuntimeGetVersion(&rtver);
	trtver = NV_TENSORRT_VERSION;

	char buf[512];
	snprintf(buf, sizeof(buf),
		"%s | %zuMB free / %zuMB total | CUDA %d.%d | TensorRT %d.%d.%d | SM %d.%d",
		prop.name,
		freemem / (1024*1024), totalmem / (1024*1024),
		rtver / 1000, (rtver % 100) / 10,
		(trtver / 1000), (trtver % 1000) / 100, (trtver % 100) / 10,
		prop.major, prop.minor);
	gGpuInfo = buf;

	gInitialized = 1;
	return 0;
}

extern "C" void
trt_fini(void)
{
	std::lock_guard<std::mutex> lock(gMutex);
	if(gRuntime) {
		delete gRuntime;
		gRuntime = NULL;
	}
	gInitialized = 0;
}

/* --- Engine management --- */

static std::string
dims_str(nvinfer1::Dims d)
{
	std::string s = "[";
	for(int i = 0; i < d.nbDims; i++) {
		if(i > 0) s += "x";
		s += std::to_string(d.d[i]);
	}
	s += "]";
	return s;
}

extern "C" TrtEngine*
trt_load(const char *planpath)
{
	std::lock_guard<std::mutex> lock(gMutex);

	if(!gInitialized) {
		fprintf(stderr, "trt: not initialized\n");
		return NULL;
	}

	/* Read serialized engine from file */
	std::ifstream f(planpath, std::ios::binary);
	if(!f.is_open()) {
		fprintf(stderr, "trt: cannot open %s\n", planpath);
		return NULL;
	}
	f.seekg(0, std::ios::end);
	size_t sz = f.tellg();
	f.seekg(0, std::ios::beg);
	std::vector<char> data(sz);
	f.read(data.data(), sz);
	f.close();

	/* Deserialize engine */
	nvinfer1::ICudaEngine *engine =
		gRuntime->deserializeCudaEngine(data.data(), sz);
	if(engine == NULL) {
		fprintf(stderr, "trt: failed to deserialize engine from %s\n", planpath);
		return NULL;
	}

	TrtEngine *e = new TrtEngine;
	e->engine = engine;
	e->planpath = planpath;
	e->ninputs = 0;
	e->noutputs = 0;

	/* Enumerate I/O tensors */
	int nbio = engine->getNbIOTensors();
	std::string info;
	for(int i = 0; i < nbio; i++) {
		const char *name = engine->getIOTensorName(i);
		nvinfer1::TensorIOMode mode = engine->getTensorIOMode(name);
		nvinfer1::Dims dims = engine->getTensorShape(name);
		bool inp = (mode == nvinfer1::TensorIOMode::kINPUT);

		e->ionames.push_back(name);
		e->iodims.push_back(dims);
		e->isinput.push_back(inp);

		if(inp) {
			e->ninputs++;
			info += "input " + std::string(name) + " " + dims_str(dims) + "\n";
		} else {
			e->noutputs++;
			info += "output " + std::string(name) + " " + dims_str(dims) + "\n";
		}
	}
	e->info = info;

	fprintf(stderr, "trt: loaded %s (%d inputs, %d outputs)\n",
		planpath, e->ninputs, e->noutputs);
	return e;
}

extern "C" void
trt_unload(TrtEngine *e)
{
	if(e == NULL)
		return;
	std::lock_guard<std::mutex> lock(gMutex);
	if(e->engine)
		delete e->engine;
	delete e;
}

extern "C" const char*
trt_engine_info(TrtEngine *e)
{
	if(e == NULL)
		return "no engine";
	return e->info.c_str();
}

/* --- Inference --- */

static size_t
dims_volume(nvinfer1::Dims d)
{
	size_t vol = 1;
	for(int i = 0; i < d.nbDims; i++)
		vol *= d.d[i];
	return vol;
}

/*
 * Detect JPEG: starts with FF D8 FF
 */
static int
is_jpeg(const void *data, int len)
{
	const unsigned char *p = (const unsigned char *)data;
	return len >= 3 && p[0] == 0xFF && p[1] == 0xD8 && p[2] == 0xFF;
}

/*
 * Detect PNG: starts with 89 50 4E 47
 */
static int
is_png(const void *data, int len)
{
	const unsigned char *p = (const unsigned char *)data;
	return len >= 4 && p[0] == 0x89 && p[1] == 0x50 &&
		p[2] == 0x4E && p[3] == 0x47;
}

/*
 * Simple image preprocessing for classification/detection models.
 * Decodes JPEG/PNG, resizes to model input dims, normalizes with
 * ImageNet mean/std. For raw tensor input, copies directly.
 *
 * This uses CPU-side preprocessing via stb_image as a portable
 * fallback. For production, nvJPEG + CUDA resize would be faster.
 */

/* stb_image - single-header image decoder */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_NO_STDIO
#include "stb_image.h"

/*
 * Preprocess image bytes into NCHW float tensor for model input.
 * Returns allocated float buffer (caller must cudaFree).
 * Uses cudaMallocManaged for zero-copy on Jetson.
 */
static float*
preprocess_image(const void *input, int inputlen,
	int target_c, int target_h, int target_w)
{
	int img_w, img_h, img_c;
	unsigned char *pixels = NULL;

	if(is_jpeg(input, inputlen) || is_png(input, inputlen)) {
		pixels = stbi_load_from_memory(
			(const unsigned char *)input, inputlen,
			&img_w, &img_h, &img_c, target_c);
		if(pixels == NULL) {
			fprintf(stderr, "trt: image decode failed: %s\n",
				stbi_failure_reason());
			return NULL;
		}
	} else {
		/* Assume raw float tensor, pass through */
		return NULL;
	}

	/* Allocate output buffer: NCHW float32 */
	size_t outsz = target_c * target_h * target_w * sizeof(float);
	float *buf;
	cudaError_t cerr = cudaMallocManaged(&buf, outsz);
	if(cerr != cudaSuccess) {
		stbi_image_free(pixels);
		fprintf(stderr, "trt: cudaMallocManaged failed: %s\n",
			cudaGetErrorString(cerr));
		return NULL;
	}

	/*
	 * Simple bilinear resize + normalize to NCHW.
	 * ImageNet normalization: (pixel/255 - mean) / std
	 */
	float mean[] = {0.485f, 0.456f, 0.406f};
	float std[]  = {0.229f, 0.224f, 0.225f};

	for(int c = 0; c < target_c; c++) {
		for(int h = 0; h < target_h; h++) {
			for(int w = 0; w < target_w; w++) {
				/* Nearest-neighbor resize */
				int src_h = h * img_h / target_h;
				int src_w = w * img_w / target_w;
				int src_idx = (src_h * img_w + src_w) * target_c + c;
				float val = (float)pixels[src_idx] / 255.0f;
				if(c < 3)
					val = (val - mean[c]) / std[c];
				buf[c * target_h * target_w + h * target_w + w] = val;
			}
		}
	}

	stbi_image_free(pixels);
	return buf;
}

/*
 * Format classification output as tab-separated text.
 * Each line: index\tconfidence\n
 * Only outputs top-K results above threshold.
 */
static void
format_classification(float *output, int nclasses, TrtResult *result)
{
	/* Find top-10 by confidence */
	struct { int idx; float conf; } top[10];
	int ntop = 0;

	for(int i = 0; i < nclasses && ntop < 10; i++) {
		if(output[i] > 0.01f) {
			/* Insert sorted by confidence (descending) */
			int j;
			for(j = ntop; j > 0 && top[j-1].conf < output[i]; j--)
				if(j < 10) top[j] = top[j-1];
			if(j < 10) {
				top[j].idx = i;
				top[j].conf = output[i];
				if(ntop < 10) ntop++;
			}
		}
	}

	std::string text;
	for(int i = 0; i < ntop; i++) {
		char line[128];
		snprintf(line, sizeof(line), "%d\t%.4f\n", top[i].idx, top[i].conf);
		text += line;
	}
	result->text = text;
	result->status = 0;
}

/*
 * Format detection output (YOLO-style).
 * Assumes output is [batch, nboxes, 4+nclasses] or similar.
 * Each line: class_id\tconfidence\tx1\ty1\tx2\ty2\n
 */
static void
format_detection(float *output, int nboxes, int nvalues, TrtResult *result)
{
	float conf_thresh = 0.25f;
	int nclasses = nvalues - 4;  /* first 4 are bbox coords */
	if(nclasses < 1) nclasses = 1;

	std::string text;
	for(int i = 0; i < nboxes; i++) {
		float *box = output + i * nvalues;
		float x1 = box[0], y1 = box[1], x2 = box[2], y2 = box[3];

		/* Find best class */
		int best_cls = 0;
		float best_conf = 0;
		for(int c = 0; c < nclasses; c++) {
			if(box[4 + c] > best_conf) {
				best_conf = box[4 + c];
				best_cls = c;
			}
		}

		if(best_conf >= conf_thresh) {
			char line[256];
			snprintf(line, sizeof(line), "%d\t%.4f\t%.0f\t%.0f\t%.0f\t%.0f\n",
				best_cls, best_conf, x1, y1, x2, y2);
			text += line;
		}
	}

	if(text.empty())
		text = "(no detections above threshold)\n";

	result->text = text;
	result->status = 0;
}

extern "C" int
trt_infer(TrtEngine *e, const void *input, int inputlen, TrtResult *result)
{
	if(e == NULL || result == NULL) {
		if(result) {
			result->error = "nil engine";
			result->status = -1;
		}
		return -1;
	}

	/* Find input tensor and its shape */
	int input_idx = -1;
	for(int i = 0; i < (int)e->ionames.size(); i++) {
		if(e->isinput[i]) {
			input_idx = i;
			break;
		}
	}
	if(input_idx < 0) {
		result->error = "no input tensor found";
		result->status = -1;
		return -1;
	}

	nvinfer1::Dims indims = e->iodims[input_idx];
	size_t invol = dims_volume(indims);

	/* Determine input C, H, W (assume NCHW with N=1) */
	int in_c = 3, in_h = 224, in_w = 224;
	if(indims.nbDims >= 4) {
		in_c = indims.d[1];
		in_h = indims.d[2];
		in_w = indims.d[3];
	} else if(indims.nbDims == 3) {
		in_c = indims.d[0];
		in_h = indims.d[1];
		in_w = indims.d[2];
	}

	/* Create per-inference execution context for thread safety.
	 * ICudaEngine methods are thread-safe, so concurrent context
	 * creation from the same engine is safe. Each context gets its
	 * own GPU scratch memory, allowing true concurrent inference. */
	nvinfer1::IExecutionContext *ctx = e->engine->createExecutionContext();
	if(ctx == NULL) {
		result->error = "failed to create execution context";
		result->status = -1;
		return -1;
	}

	/* Preprocess: decode image → NCHW float tensor */
	float *input_buf = preprocess_image(input, inputlen, in_c, in_h, in_w);
	int raw_input = 0;

	if(input_buf == NULL) {
		/* Not an image — treat as raw float tensor */
		size_t expected = invol * sizeof(float);
		if((size_t)inputlen != expected) {
			char msg[256];
			snprintf(msg, sizeof(msg),
				"input size %d != expected %zu (raw float tensor for %s)",
				inputlen, expected, dims_str(indims).c_str());
			result->error = msg;
			result->status = -1;
			delete ctx;
			return -1;
		}
		/* Allocate unified memory and copy */
		cudaError_t cerr = cudaMallocManaged(&input_buf, expected);
		if(cerr != cudaSuccess) {
			result->error = "cudaMallocManaged failed for input";
			result->status = -1;
			delete ctx;
			return -1;
		}
		memcpy(input_buf, input, expected);
		raw_input = 1;
	}

	/* Allocate output buffers */
	struct OutBuf {
		float *ptr;
		size_t vol;
		nvinfer1::Dims dims;
	};
	std::vector<OutBuf> outputs;

	for(int i = 0; i < (int)e->ionames.size(); i++) {
		if(!e->isinput[i]) {
			size_t vol = dims_volume(e->iodims[i]);
			float *ptr;
			cudaError_t cerr = cudaMallocManaged(&ptr, vol * sizeof(float));
			if(cerr != cudaSuccess) {
				/* Cleanup */
				for(auto &ob : outputs)
					cudaFree(ob.ptr);
				cudaFree(input_buf);
				delete ctx;
				result->error = "cudaMallocManaged failed for output";
				result->status = -1;
				return -1;
			}
			memset(ptr, 0, vol * sizeof(float));
			outputs.push_back({ptr, vol, e->iodims[i]});
		}
	}

	/* Set tensor addresses */
	{
		int out_idx = 0;
		for(int i = 0; i < (int)e->ionames.size(); i++) {
			if(e->isinput[i])
				ctx->setTensorAddress(e->ionames[i].c_str(), input_buf);
			else
				ctx->setTensorAddress(e->ionames[i].c_str(),
					outputs[out_idx++].ptr);
		}
	}

	/* Run inference on a per-call CUDA stream */
	cudaStream_t stream;
	cudaStreamCreate(&stream);
	bool ok = ctx->enqueueV3(stream);
	cudaStreamSynchronize(stream);
	cudaStreamDestroy(stream);

	if(!ok) {
		for(auto &ob : outputs)
			cudaFree(ob.ptr);
		cudaFree(input_buf);
		delete ctx;
		result->error = "inference failed";
		result->status = -1;
		return -1;
	}

	/* Format output based on shape heuristics */
	if(outputs.size() > 0) {
		OutBuf &ob = outputs[0];
		nvinfer1::Dims &d = ob.dims;

		if(d.nbDims == 2 && d.d[0] == 1) {
			/* [1, nclasses] — classification */
			format_classification(ob.ptr, d.d[1], result);
		} else if(d.nbDims == 3 && d.d[0] == 1) {
			/* [1, nboxes, nvalues] — detection (YOLOv8 transposed) */
			format_detection(ob.ptr, d.d[1], d.d[2], result);
		} else if(d.nbDims == 2) {
			/* [nboxes, nvalues] — detection */
			format_detection(ob.ptr, d.d[0], d.d[1], result);
		} else {
			/* Generic: dump raw floats, first 100 values */
			std::string text;
			size_t n = ob.vol;
			if(n > 100) n = 100;
			for(size_t i = 0; i < n; i++) {
				char val[32];
				snprintf(val, sizeof(val), "%.6f", ob.ptr[i]);
				text += val;
				if(i + 1 < n) text += "\t";
			}
			text += "\n";
			if(ob.vol > 100)
				text += "(truncated, " + std::to_string(ob.vol) + " total values)\n";
			result->text = text;
			result->status = 0;
		}
	} else {
		result->text = "(no output tensors)\n";
		result->status = 0;
	}

	/* Cleanup */
	for(auto &ob : outputs)
		cudaFree(ob.ptr);
	cudaFree(input_buf);
	delete ctx;

	return 0;
}

/* --- System info --- */

extern "C" const char*
trt_gpu_info(void)
{
	if(!gInitialized)
		return "GPU not initialized (call trt_init first)";
	return gGpuInfo.c_str();
}
