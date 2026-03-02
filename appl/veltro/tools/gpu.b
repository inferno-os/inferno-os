implement ToolGpu;

#
# gpu - GPU inference tool for Veltro agent
#
# Wraps the /mnt/gpu filesystem to provide GPU inference
# capabilities to Veltro agents. Uses the clone-based session
# pattern to run inference on images.
#
# Usage:
#   Gpu info                         # GPU info
#   Gpu models                       # list loaded models
#   Gpu detect <model> <imagepath>   # run object detection
#   Gpu classify <model> <imagepath> # run classification
#   Gpu infer <model> <imagepath>    # run generic inference
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "../tool.m";

ToolGpu: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

GPUDIR: con "/mnt/gpu";

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	return nil;
}

name(): string
{
	return "gpu";
}

doc(): string
{
	return "Gpu - GPU inference tool\n\n" +
		"Usage:\n" +
		"  Gpu info                          # GPU hardware info\n" +
		"  Gpu models                        # List loaded models\n" +
		"  Gpu infer <model> <imagepath>     # Run inference\n" +
		"  Gpu detect <model> <imagepath>    # Run object detection\n" +
		"  Gpu classify <model> <imagepath>  # Run classification\n\n" +
		"Arguments:\n" +
		"  model     - Name of loaded TensorRT model (e.g., yolov8)\n" +
		"  imagepath - Path to input image (JPEG or PNG)\n\n" +
		"Examples:\n" +
		"  Gpu info\n" +
		"  Gpu models\n" +
		"  Gpu detect yolov8 /tmp/photo.jpg\n" +
		"  Gpu classify resnet50 /tmp/cat.png\n\n" +
		"Returns inference results as tab-separated text,\n" +
		"or GPU/model information.";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	(n, argv) := sys->tokenize(args, " \t");
	if(n < 1)
		return "error: usage: Gpu <command> [args...]";

	cmd := hd argv;
	argv = tl argv;

	case cmd {
	"info" =>
		return gpuinfo();
	"models" =>
		return listmodels();
	"infer" or "detect" or "classify" =>
		if(argv == nil)
			return "error: usage: Gpu " + cmd + " <model> <imagepath>";
		model := hd argv;
		argv = tl argv;
		if(argv == nil)
			return "error: usage: Gpu " + cmd + " <model> <imagepath>";
		imagepath := hd argv;
		return runinfer(model, imagepath);
	* =>
		return "error: unknown command: " + cmd +
			"\nUsage: Gpu info | models | infer <model> <path> | detect <model> <path> | classify <model> <path>";
	}
}

gpuinfo(): string
{
	return readfile(GPUDIR + "/ctl");
}

listmodels(): string
{
	# Read models directory
	fd := sys->open(GPUDIR + "/models", Sys->OREAD);
	if(fd == nil)
		return "error: cannot open " + GPUDIR + "/models: " + errmsg();
	(ndir, dirs) := sys->dirread(fd);
	if(ndir <= 0)
		return "(no models loaded)";

	result := "";
	for(i := 0; i < ndir; i++) {
		info := readfile(GPUDIR + "/models/" + dirs[i].name);
		if(info != "")
			result += dirs[i].name + ":\n" + info + "\n";
		else
			result += dirs[i].name + "\n";
	}
	return result;
}

runinfer(model, imagepath: string): string
{
	# 1. Read clone to get session ID
	sid := readfile(GPUDIR + "/clone");
	if(sid == "" || sid[0] == 'e')
		return "error: failed to allocate GPU session: " + sid;
	# Strip trailing newline
	if(len sid > 0 && sid[len sid - 1] == '\n')
		sid = sid[0:len sid - 1];

	sessdir := GPUDIR + "/" + sid;

	# 2. Set model
	err := writefile(sessdir + "/ctl", "model " + model);
	if(err != nil)
		return "error: " + err;

	# 3. Write input image
	imgdata := readbytes(imagepath);
	if(imgdata == nil)
		return "error: cannot read image: " + imagepath;

	err = writebytes(sessdir + "/input", imgdata);
	if(err != nil)
		return "error: writing input: " + err;

	# 4. Trigger inference
	err = writefile(sessdir + "/ctl", "infer");
	if(err != nil)
		return "error: inference failed: " + err;

	# 5. Read status
	status := readfile(sessdir + "/status");
	if(status == "" || hasprefix(status, "error"))
		return "error: " + status;

	# 6. Read output
	output := readfile(sessdir + "/output");
	if(output == "")
		return "(no output)";
	return output;
}

# --- I/O helpers ---

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return "";
	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "";
	return string buf[0:n];
}

readbytes(path: string): array of byte
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;

	# Read file in chunks
	chunks: list of array of byte;
	total := 0;
	for(;;) {
		buf := array[65536] of byte;
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		chunks = buf[0:n] :: chunks;
		total += n;
	}

	if(total == 0)
		return nil;

	# Assemble chunks in order
	result := array[total] of byte;
	pos := total;
	for(; chunks != nil; chunks = tl chunks) {
		chunk := hd chunks;
		pos -= len chunk;
		result[pos:] = chunk;
	}
	return result;
}

writefile(path, data: string): string
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return "cannot open " + path + ": " + errmsg();
	b := array of byte data;
	n := sys->write(fd, b, len b);
	if(n != len b)
		return "write failed: " + errmsg();
	return nil;
}

writebytes(path: string, data: array of byte): string
{
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil)
		return "cannot open " + path + ": " + errmsg();
	n := sys->write(fd, data, len data);
	if(n != len data)
		return "write failed: " + errmsg();
	return nil;
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

errmsg(): string
{
	fd := sys->open("/dev/sysctl", Sys->OREAD);
	if(fd == nil)
		return "unknown error";
	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "unknown error";
	return string buf[0:n];
}
