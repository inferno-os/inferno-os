/*
 * trt-wrapper.h - C API for TensorRT inference on Jetson Orin
 *
 * Thin wrapper around TensorRT C++ classes, compiled with g++,
 * linked into the Inferno emulator via extern "C".
 */

#ifndef TRT_WRAPPER_H
#define TRT_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TrtEngine TrtEngine;
typedef struct TrtResult TrtResult;

/* Result management */
TrtResult*  trt_result_new(void);
void        trt_result_free(TrtResult *r);
const char* trt_result_text(TrtResult *r);   /* tab-separated output */
int         trt_result_status(TrtResult *r);  /* 0=ok, -1=error */
const char* trt_result_error(TrtResult *r);   /* error message if status<0 */

/* Runtime lifecycle */
int         trt_init(void);                   /* init CUDA + TRT runtime */
void        trt_fini(void);                   /* cleanup */

/* Engine management */
TrtEngine*  trt_load(const char *planpath);   /* load serialized .plan engine */
void        trt_unload(TrtEngine *e);
const char* trt_engine_info(TrtEngine *e);    /* input/output shape info */

/* Inference */
int         trt_infer(TrtEngine *e, const void *input,
                      int inputlen, TrtResult *result);

/* System info */
const char* trt_gpu_info(void);               /* GPU name, memory, versions */

#ifdef __cplusplus
}
#endif

#endif /* TRT_WRAPPER_H */
