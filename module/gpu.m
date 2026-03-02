#
# gpu.m - GPU compute module interface
#
# Built-in module providing TensorRT inference on Jetson Orin.
# Loaded via $GPU path (like $Keyring for crypto).
#

GPU: module {
	PATH: con "$GPU";

	# Initialize the GPU runtime (CUDA + TensorRT).
	# Returns nil on success, error string on failure.
	init:     fn(): string;

	# Return GPU info: name, memory, CUDA version, TensorRT version.
	gpuinfo:  fn(): string;

	# Load a TensorRT serialized engine (.plan file).
	# Returns (handle, error). Handle is used for infer/unload.
	loadmodel:   fn(planpath: string): (int, string);

	# Unload a previously loaded model.
	# Returns nil on success, error string on failure.
	unloadmodel: fn(handle: int): string;

	# Return model info (input/output shapes) for a loaded model.
	modelinfo:   fn(handle: int): string;

	# Run inference on a loaded model with input data.
	# Input can be JPEG, PNG, or raw float tensor.
	# Returns (result_text, error). Result is tab-separated.
	infer:   fn(handle: int, input: array of byte): (string, string);
};
