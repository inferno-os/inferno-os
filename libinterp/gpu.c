/*
 * gpu.c - GPU compute module for Inferno/Dis VM
 *
 * Built-in module ($GPU) providing TensorRT inference on Jetson Orin.
 * Follows the keyring.c pattern: auto-generated headers from limbo -t/-a,
 * functions named GPU_functionname(void *fp), builtinmod() registration.
 *
 * Manages a table of loaded TrtEngine pointers indexed by handle.
 * Thread-safe via QLock around engine table.
 */

#include "lib9.h"
#include "kernel.h"
#include <isa.h>
#include "interp.h"
#include "raise.h"

#include "gpuif.h"
#include "gpu.h"

#include "trt-wrapper.h"

/* From emu/port/dat.h — host root directory for path translation */
extern char rootdir[];

/*
 * Engine table: maps integer handles to TrtEngine pointers.
 * Protected by a QLock for thread safety.
 */
enum {
	MAXENGINES = 32
};

static struct {
	TrtEngine	*engine;
	int		inuse;
	char		name[256];
} engines[MAXENGINES];

static int gpu_initialized;
static QLock gpu_lock;

/*
 * GPU_init() - Initialize CUDA and TensorRT runtime.
 * Returns nil string on success, error string on failure.
 */
void
GPU_init(void *fp)
{
	F_GPU_init *f;
	int r;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	qlock(&gpu_lock);
	if(!gpu_initialized) {
		release();
		r = trt_init();
		acquire();
		if(r < 0) {
			qunlock(&gpu_lock);
			retstr("failed to initialize GPU runtime", f->ret);
			return;
		}
		gpu_initialized = 1;
	}
	qunlock(&gpu_lock);
	/* return H (nil) for success */
}

/*
 * GPU_gpuinfo() - Return GPU info string.
 */
void
GPU_gpuinfo(void *fp)
{
	F_GPU_gpuinfo *f;
	char *info;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	release();
	info = (char*)trt_gpu_info();
	acquire();
	retstr(info, f->ret);
}

/*
 * GPU_loadmodel() - Load a TensorRT .plan engine file.
 * Returns (handle, error) tuple.
 */
void
GPU_loadmodel(void *fp)
{
	F_GPU_loadmodel *f;
	char hostpath[1024];
	TrtEngine *e;
	int handle;

	f = fp;
	f->ret->t0 = 0;
	destroy(f->ret->t1);
	f->ret->t1 = H;

	if(!gpu_initialized) {
		retstr("GPU not initialized", &f->ret->t1);
		return;
	}

	/* Translate Inferno path to host path */
	snprint(hostpath, sizeof(hostpath), "%s%s", rootdir, string2c(f->planpath));

	/* Find a free slot */
	qlock(&gpu_lock);
	handle = -1;
	{
		int i;
		for(i = 0; i < MAXENGINES; i++) {
			if(!engines[i].inuse) {
				handle = i;
				break;
			}
		}
	}
	if(handle < 0) {
		qunlock(&gpu_lock);
		retstr("too many loaded models", &f->ret->t1);
		return;
	}
	engines[handle].inuse = 1;  /* Reserve slot */
	qunlock(&gpu_lock);

	/* Load engine (may take seconds for large models) */
	release();
	e = trt_load(hostpath);
	acquire();

	if(e == nil) {
		qlock(&gpu_lock);
		engines[handle].inuse = 0;
		qunlock(&gpu_lock);
		retstr("failed to load engine", &f->ret->t1);
		return;
	}

	qlock(&gpu_lock);
	engines[handle].engine = e;
	snprint(engines[handle].name, sizeof(engines[handle].name), "%s", hostpath);
	qunlock(&gpu_lock);

	f->ret->t0 = handle;
	/* t1 stays H (nil) for success */
}

/*
 * GPU_unloadmodel() - Unload a previously loaded model.
 */
void
GPU_unloadmodel(void *fp)
{
	F_GPU_unloadmodel *f;
	int handle;
	TrtEngine *e;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	handle = f->handle;
	if(handle < 0 || handle >= MAXENGINES) {
		retstr("invalid handle", f->ret);
		return;
	}

	qlock(&gpu_lock);
	if(!engines[handle].inuse) {
		qunlock(&gpu_lock);
		retstr("handle not in use", f->ret);
		return;
	}
	e = engines[handle].engine;
	engines[handle].engine = nil;
	engines[handle].inuse = 0;
	engines[handle].name[0] = '\0';
	qunlock(&gpu_lock);

	release();
	trt_unload(e);
	acquire();
	/* return H (nil) for success */
}

/*
 * GPU_modelinfo() - Return model input/output shape info.
 */
void
GPU_modelinfo(void *fp)
{
	F_GPU_modelinfo *f;
	int handle;
	char *info;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;

	handle = f->handle;
	if(handle < 0 || handle >= MAXENGINES) {
		retstr("invalid handle", f->ret);
		return;
	}

	qlock(&gpu_lock);
	if(!engines[handle].inuse || engines[handle].engine == nil) {
		qunlock(&gpu_lock);
		retstr("handle not loaded", f->ret);
		return;
	}
	info = (char*)trt_engine_info(engines[handle].engine);
	qunlock(&gpu_lock);

	retstr(info, f->ret);
}

/*
 * GPU_infer() - Run inference.
 * Returns (result_text, error) tuple.
 */
void
GPU_infer(void *fp)
{
	F_GPU_infer *f;
	int handle, r;
	TrtEngine *e;
	TrtResult *res;
	void *data;
	int datalen;

	f = fp;
	destroy(f->ret->t0);
	f->ret->t0 = H;
	destroy(f->ret->t1);
	f->ret->t1 = H;

	handle = f->handle;
	if(handle < 0 || handle >= MAXENGINES) {
		retstr("invalid handle", &f->ret->t1);
		return;
	}

	if(f->input == H || f->input->len == 0) {
		retstr("empty input", &f->ret->t1);
		return;
	}

	qlock(&gpu_lock);
	if(!engines[handle].inuse || engines[handle].engine == nil) {
		qunlock(&gpu_lock);
		retstr("handle not loaded", &f->ret->t1);
		return;
	}
	e = engines[handle].engine;
	qunlock(&gpu_lock);

	/* Extract byte array data */
	data = f->input->data;
	datalen = f->input->len;

	release();
	res = trt_result_new();
	r = trt_infer(e, data, datalen, res);
	acquire();

	if(r < 0 || trt_result_status(res) < 0) {
		retstr((char*)trt_result_error(res), &f->ret->t1);
	} else {
		retstr((char*)trt_result_text(res), &f->ret->t0);
	}

	trt_result_free(res);
}

/*
 * gpumodinit() - Register the GPU module at startup.
 */
void
gpumodinit(void)
{
	memset(engines, 0, sizeof(engines));
	gpu_initialized = 0;
	builtinmod("$GPU", GPUmodtab, GPUmodlen);
}
