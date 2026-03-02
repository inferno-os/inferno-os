/*
 * gpu-stub.c - Stub GPU module for builds without TensorRT/CUDA.
 * Provides gpumodinit() so the emulator links, but the GPU module
 * is not registered (no builtinmod call).
 */

void
gpumodinit(void)
{
	/* GPU not available in this build */
}
