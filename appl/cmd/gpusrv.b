implement Gpusrv;

#
# gpusrv - GPU Compute Filesystem
#
# Plan 9-style Styx server exposing TensorRT inference as a filesystem
# with clone-based multiplexing for concurrent sessions.
#
# Filesystem layout:
#   /mnt/gpu/
#       clone           read: allocates session N, returns "N\n"
#       ctl             read: GPU info (name, memory, CUDA/TRT versions)
#       models/         directory of loaded TensorRT engines
#           <name>      read: model info (input/output shapes)
#       N/              per-session directory
#           ctl         write: "model <name>" "infer"
#                       read: session status
#           input       write: raw image bytes (JPEG/PNG/raw tensor)
#           output      read: inference results (tab-separated text)
#           status      read: "idle" "running" "done" "error: ..."
#
# Usage:
#   gpusrv                          # mount at /mnt/gpu
#   gpusrv -m /n/gpu                # custom mount point
#   gpusrv -p /lib/gpu/yolov8.plan  # preload a model
#   gpusrv -D                       # debug tracing
#
# Example session:
#   id=`{cat /mnt/gpu/clone}
#   echo 'model yolov8' > /mnt/gpu/$id/ctl
#   cat photo.jpg > /mnt/gpu/$id/input
#   echo infer > /mnt/gpu/$id/ctl
#   cat /mnt/gpu/$id/output
#

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "draw.m";

include "arg.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "styxservers.m";
	styxservers: Styxservers;
	Fid, Styxserver, Navigator, Navop: import styxservers;
	Enotfound, Eperm, Ebadarg: import styxservers;

include "string.m";
	str: String;

include "gpu.m";
	gpu: GPU;

Gpusrv: module {
	init: fn(nil: ref Draw->Context, nil: list of string);
};

# File types (low byte of qid path)
Qroot: con 0;
Qclone: con 1;
Qgctl: con 2;
Qmodelsdir: con 3;
# Per-model files start at 8
Qmodelbase: con 8;
# Per-session files start at 16
Qsessdir: con 16;
Qsctl: con 17;
Qsinput: con 18;
Qsoutput: con 19;
Qsstatus: con 20;

# Session state
GpuSession: adt {
	id:       int;
	model:    int;       # model handle (-1 = not set)
	mname:    string;    # model name
	input:    array of byte;
	output:   string;
	status:   string;    # idle, running, done, error: ...
};

# Model registry
GpuModel: adt {
	handle:   int;       # GPU module handle
	name:     string;    # short name (e.g., "yolov8")
	planpath: string;    # filesystem path to .plan file
};

stderr: ref Sys->FD;
user: string;
vers: int;

# Session pool
sessions: array of ref GpuSession;
nsessions: int;
nextsid: int;

# Model registry
models: array of ref GpuModel;
nmodels: int;

usage()
{
	sys->fprint(stderr, "Usage: gpusrv [-D] [-m mountpoint] [-p model.plan] ...\n");
	raise "fail:usage";
}

nomod(s: string)
{
	sys->fprint(stderr, "gpusrv: can't load %s: %r\n", s);
	raise "fail:load";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	styx = load Styx Styx->PATH;
	if(styx == nil)
		nomod(Styx->PATH);
	styx->init();

	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil)
		nomod(Styxservers->PATH);
	styxservers->init(styx);

	str = load String String->PATH;
	if(str == nil)
		nomod(String->PATH);

	gpu = load GPU GPU->PATH;
	if(gpu == nil)
		nomod(GPU->PATH);

	# Initialize GPU
	gerr := gpu->init();
	if(gerr != nil) {
		sys->fprint(stderr, "gpusrv: GPU init: %s\n", gerr);
		raise "fail:init";
	}

	arg := load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	arg->init(args);

	mountpt := "/mnt/gpu";
	preloads: list of string;

	while((o := arg->opt()) != 0)
		case o {
		'D' =>	styxservers->traceset(1);
		'm' =>	mountpt = arg->earg();
		'p' =>	preloads = arg->earg() :: preloads;
		* =>	usage();
		}
	args = arg->argv();
	arg = nil;

	# Initialize pools
	sessions = array[16] of ref GpuSession;
	nsessions = 0;
	nextsid = 1;
	models = array[MAXMODELS] of ref GpuModel;
	nmodels = 0;
	vers = 0;

	# Preload models
	for(pl := preloads; pl != nil; pl = tl pl) {
		path := hd pl;
		name := basename(path);
		err := loadmodel(name, path);
		if(err != nil)
			sys->fprint(stderr, "gpusrv: preload %s: %s\n", path, err);
		else
			sys->fprint(stderr, "gpusrv: loaded %s as '%s'\n", path, name);
	}

	sys->pctl(Sys->FORKFD, nil);

	user = rf("/dev/user");
	if(user == nil)
		user = "inferno";

	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0) {
		sys->fprint(stderr, "gpusrv: can't create pipe: %r\n");
		raise "fail:pipe";
	}

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	fds[0] = nil;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc, navops);
	<-pidc;

	ensuredir(mountpt);

	if(sys->mount(fds[1], nil, mountpt, Sys->MREPL|Sys->MCREATE, nil) < 0) {
		sys->fprint(stderr, "gpusrv: mount failed: %r\n");
		raise "fail:mount";
	}
}

# --- Constants ---
MAXMODELS: con 32;

# --- Session management ---

newsession(): ref GpuSession
{
	id := nextsid++;
	s := ref GpuSession(id, -1, "", nil, "", "idle");

	if(nsessions >= len sessions) {
		ns := array[len sessions * 2] of ref GpuSession;
		ns[0:] = sessions[0:nsessions];
		sessions = ns;
	}
	sessions[nsessions++] = s;
	vers++;
	return s;
}

findsession(id: int): ref GpuSession
{
	for(i := 0; i < nsessions; i++)
		if(sessions[i].id == id)
			return sessions[i];
	return nil;
}

freesession(id: int)
{
	for(i := 0; i < nsessions; i++) {
		if(sessions[i].id == id) {
			sessions[i:] = sessions[i+1:nsessions];
			nsessions--;
			sessions[nsessions] = nil;
			vers++;
			return;
		}
	}
}

# --- Model management ---

loadmodel(name, planpath: string): string
{
	if(nmodels >= MAXMODELS)
		return "too many models";

	# Check for duplicate name
	for(i := 0; i < nmodels; i++)
		if(models[i].name == name)
			return "model already loaded: " + name;

	(handle, err) := gpu->loadmodel(planpath);
	if(err != nil)
		return err;

	models[nmodels] = ref GpuModel(handle, name, planpath);
	nmodels++;
	vers++;
	return nil;
}

findmodel(name: string): ref GpuModel
{
	for(i := 0; i < nmodels; i++)
		if(models[i].name == name)
			return models[i];
	return nil;
}

# --- QID encoding ---

MKPATH(id, filetype: int): big
{
	return big ((id << 8) | filetype);
}

SESSID(path: big): int
{
	return (int path >> 8) & 16rFFFFFF;
}

FTYPE(path: big): int
{
	return int path & 16rFF;
}

# --- Serve loop ---

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver,
	pidc: chan of int, navops: chan of ref Navop)
{
	pidc <-= sys->pctl(Sys->FORKNS|Sys->NEWFD, 1::2::srv.fd.fd::nil);

Serve:
	while((gm := <-tchan) != nil) {
		pick m := gm {
		Readerror =>
			sys->fprint(stderr, "gpusrv: fatal read error: %s\n", m.error);
			break Serve;

		Open =>
			c := srv.getfid(m.fid);
			if(c == nil) {
				srv.open(m);
				break;
			}

			mode := styxservers->openmode(m.mode);
			if(mode < 0) {
				srv.reply(ref Rmsg.Error(m.tag, Ebadarg));
				break;
			}

			qid := Qid(c.path, 0, c.qtype);
			c.open(mode, qid);
			srv.reply(ref Rmsg.Open(m.tag, qid, srv.iounit()));

		Read =>
			(c, err) := srv.canread(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}

			if(c.qtype & Sys->QTDIR) {
				srv.read(m);
				break;
			}

			ft := FTYPE(c.path);
			sid := SESSID(c.path);

			case ft {
			Qclone =>
				sess := newsession();
				data := array of byte (string sess.id + "\n");
				srv.reply(styxservers->readbytes(m, data));

			Qgctl =>
				info := gpu->gpuinfo();
				if(info == nil)
					info = "GPU not available";
				# Append loaded model list
				if(nmodels > 0) {
					info += "\nmodels:";
					for(i := 0; i < nmodels; i++)
						info += " " + models[i].name;
				}
				info += "\n";
				srv.reply(styxservers->readbytes(m, array of byte info));

			Qsctl =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				info := "status " + sess.status + "\n";
				if(sess.mname != "")
					info += "model " + sess.mname + "\n";
				srv.reply(styxservers->readbytes(m, array of byte info));

			Qsoutput =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				srv.reply(styxservers->readbytes(m, array of byte sess.output));

			Qsstatus =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				srv.reply(styxservers->readbytes(m, array of byte (sess.status + "\n")));

			* =>
				# Check if it's a model info file
				if(ft >= Qmodelbase && ft < Qsessdir) {
					midx := ft - Qmodelbase;
					if(midx >= 0 && midx < nmodels) {
						info := gpu->modelinfo(models[midx].handle);
						if(info == nil)
							info = "";
						info = "name " + models[midx].name + "\n" +
							"path " + models[midx].planpath + "\n" +
							info;
						srv.reply(styxservers->readbytes(m, array of byte info));
					} else
						srv.reply(ref Rmsg.Error(m.tag, Enotfound));
				} else
					srv.reply(ref Rmsg.Error(m.tag, Eperm));
			}

		Write =>
			(c, merr) := srv.canwrite(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, merr));
				break;
			}

			ft := FTYPE(c.path);
			sid := SESSID(c.path);

			case ft {
			Qsctl =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				data := string m.data;
				# Strip trailing newline
				if(len data > 0 && data[len data - 1] == '\n')
					data = data[0:len data - 1];
				cerr := sessctl(sess, data);
				if(cerr != nil) {
					srv.reply(ref Rmsg.Error(m.tag, cerr));
					break;
				}
				srv.reply(ref Rmsg.Write(m.tag, len m.data));

			Qsinput =>
				sess := findsession(sid);
				if(sess == nil) {
					srv.reply(ref Rmsg.Error(m.tag, Enotfound));
					break;
				}
				# Append to input buffer
				if(sess.input == nil)
					sess.input = array[0] of byte;
				newinput := array[len sess.input + len m.data] of byte;
				newinput[0:] = sess.input[0:len sess.input];
				for(i := 0; i < len m.data; i++)
					newinput[len sess.input + i] = m.data[i];
				sess.input = newinput;
				vers++;
				srv.reply(ref Rmsg.Write(m.tag, len m.data));

			* =>
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
			}

		Clunk =>
			srv.clunk(m);

		Remove =>
			srv.remove(m);

		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;
}

# --- Session control commands ---

sessctl(sess: ref GpuSession, data: string): string
{
	if(hasprefix(data, "model ")) {
		name := data[len "model ":];
		mdl := findmodel(name);
		if(mdl == nil)
			return "unknown model: " + name;
		sess.model = mdl.handle;
		sess.mname = name;
		sess.status = "idle";
		sess.output = "";
		sess.input = nil;
		vers++;
		return nil;
	}

	if(data == "infer") {
		if(sess.model < 0)
			return "no model set (use: model <name>)";
		if(sess.input == nil || len sess.input == 0)
			return "no input data";

		sess.status = "running";
		vers++;

		# Run inference (synchronous — blocks this request)
		(result, err) := gpu->infer(sess.model, sess.input);
		if(err != nil) {
			sess.status = "error: " + err;
			sess.output = "";
		} else {
			sess.status = "done";
			sess.output = result;
		}
		vers++;
		return nil;
	}

	if(data == "reset") {
		sess.input = nil;
		sess.output = "";
		sess.status = "idle";
		vers++;
		return nil;
	}

	if(hasprefix(data, "load ")) {
		# Dynamic model loading: "load name /path/to/model.plan"
		rest := data[len "load ":];
		(ntok, toks) := sys->tokenize(rest, " \t");
		if(ntok != 2)
			return "usage: load <name> <planpath>";
		name := hd toks;
		planpath := hd tl toks;
		err := loadmodel(name, planpath);
		if(err != nil)
			return err;
		return nil;
	}

	return "unknown ctl command: " + data;
}

# --- Directory generation ---

dir(qid: Sys->Qid, name: string, length: big, perm: int): ref Sys->Dir
{
	d := ref sys->zerodir;
	d.qid = qid;
	if(qid.qtype & Sys->QTDIR)
		perm |= Sys->DMDIR;
	d.mode = perm;
	d.name = name;
	d.uid = user;
	d.gid = user;
	d.length = length;
	return d;
}

dirgen(p: big): (ref Sys->Dir, string)
{
	ft := FTYPE(p);
	sid := SESSID(p);

	case ft {
	Qroot =>
		return (dir(Qid(p, vers, Sys->QTDIR), "/", big 0, 8r755), nil);

	Qclone =>
		return (dir(Qid(p, vers, Sys->QTFILE), "clone", big 0, 8r444), nil);

	Qgctl =>
		return (dir(Qid(p, vers, Sys->QTFILE), "ctl", big 0, 8r444), nil);

	Qmodelsdir =>
		return (dir(Qid(p, vers, Sys->QTDIR), "models", big 0, 8r555), nil);

	Qsessdir =>
		return (dir(Qid(p, vers, Sys->QTDIR), string sid, big 0, 8r755), nil);

	Qsctl =>
		return (dir(Qid(p, vers, Sys->QTFILE), "ctl", big 0, 8r644), nil);

	Qsinput =>
		return (dir(Qid(p, vers, Sys->QTFILE), "input", big 0, 8r222), nil);

	Qsoutput =>
		return (dir(Qid(p, vers, Sys->QTFILE), "output", big 0, 8r444), nil);

	Qsstatus =>
		return (dir(Qid(p, vers, Sys->QTFILE), "status", big 0, 8r444), nil);
	}

	# Model info files
	if(ft >= Qmodelbase && ft < Qsessdir) {
		midx := ft - Qmodelbase;
		if(midx >= 0 && midx < nmodels)
			return (dir(Qid(p, vers, Sys->QTFILE), models[midx].name, big 0, 8r444), nil);
	}

	return (nil, Enotfound);
}

# --- Navigator ---

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil) {
		pick n := m {
		Stat =>
			n.reply <-= dirgen(n.path);

		Walk =>
			ft := FTYPE(n.path);
			sid := SESSID(n.path);

			case ft {
			Qroot =>
				case n.name {
				".." =>
					;  # stay at root
				"clone" =>
					n.path = MKPATH(0, Qclone);
				"ctl" =>
					n.path = MKPATH(0, Qgctl);
				"models" =>
					n.path = MKPATH(0, Qmodelsdir);
				* =>
					# Try as session ID
					id := strtoint(n.name);
					if(id > 0 && findsession(id) != nil)
						n.path = MKPATH(id, Qsessdir);
					else {
						n.reply <-= (nil, Enotfound);
						continue;
					}
				}
				n.reply <-= dirgen(n.path);

			Qmodelsdir =>
				case n.name {
				".." =>
					n.path = big Qroot;
					n.reply <-= dirgen(n.path);
				* =>
					# Walk to a model info file
					mdl := findmodel(n.name);
					if(mdl == nil) {
						n.reply <-= (nil, Enotfound);
						continue;
					}
					# Find model index
					found := 0;
					for(i := 0; i < nmodels; i++) {
						if(models[i].name == n.name) {
							n.path = MKPATH(0, Qmodelbase + i);
							n.reply <-= dirgen(n.path);
							found = 1;
							break;
						}
					}
					if(!found) {
						n.reply <-= (nil, Enotfound);
						continue;
					}
				}

			Qsessdir =>
				case n.name {
				".." =>
					n.path = big Qroot;
				"ctl" =>
					n.path = MKPATH(sid, Qsctl);
				"input" =>
					n.path = MKPATH(sid, Qsinput);
				"output" =>
					n.path = MKPATH(sid, Qsoutput);
				"status" =>
					n.path = MKPATH(sid, Qsstatus);
				* =>
					n.reply <-= (nil, Enotfound);
					continue;
				}
				n.reply <-= dirgen(n.path);

			* =>
				# Files are not directories
				case n.name {
				".." =>
					# Go up from model file or session file
					if(ft >= Qmodelbase && ft < Qsessdir)
						n.path = MKPATH(0, Qmodelsdir);
					else if(ft >= Qsessdir)
						n.path = MKPATH(sid, Qsessdir);
					else
						n.path = big Qroot;
					n.reply <-= dirgen(n.path);
				* =>
					n.reply <-= (nil, "not a directory");
				}
			}

		Readdir =>
			ft := FTYPE(m.path);

			case ft {
			Qroot =>
				# Root: clone, ctl, models dir, plus session directories
				entries: list of big;
				entries = MKPATH(0, Qclone) :: entries;
				entries = MKPATH(0, Qgctl) :: entries;
				entries = MKPATH(0, Qmodelsdir) :: entries;
				for(i := 0; i < nsessions; i++)
					entries = MKPATH(sessions[i].id, Qsessdir) :: entries;

				# Reverse to preserve order
				rev: list of big;
				for(; entries != nil; entries = tl entries)
					rev = hd entries :: rev;
				entries = rev;

				i = 0;
				for(e := entries; e != nil; e = tl e) {
					if(i >= n.offset && n.count > 0) {
						n.reply <-= dirgen(hd e);
						n.count--;
					}
					i++;
				}
				n.reply <-= (nil, nil);

			Qmodelsdir =>
				i := n.offset;
				for(; i < nmodels && n.count > 0; i++) {
					n.reply <-= dirgen(MKPATH(0, Qmodelbase + i));
					n.count--;
				}
				n.reply <-= (nil, nil);

			Qsessdir =>
				files := array[] of {
					MKPATH(SESSID(m.path), Qsctl),
					MKPATH(SESSID(m.path), Qsinput),
					MKPATH(SESSID(m.path), Qsoutput),
					MKPATH(SESSID(m.path), Qsstatus),
				};
				i := n.offset;
				for(; i < len files && n.count > 0; i++) {
					n.reply <-= dirgen(files[i]);
					n.count--;
				}
				n.reply <-= (nil, nil);

			* =>
				n.reply <-= (nil, "not a directory");
			}
		}
	}
}

# --- Helpers ---

ensuredir(path: string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd != nil)
		return;

	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			ensuredir(path[0:i]);
			break;
		}
	}

	fd = sys->create(path, Sys->OREAD, Sys->DMDIR | 8r755);
	if(fd == nil)
		sys->fprint(stderr, "gpusrv: cannot create directory %s: %r\n", path);
}

rf(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;
	b := array[Sys->NAMEMAX] of byte;
	n := sys->read(fd, b, len b);
	if(n < 0)
		return nil;
	return string b[0:n];
}

strtoint(s: string): int
{
	n := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c < '0' || c > '9')
			return -1;
		n = n * 10 + (c - '0');
	}
	if(len s == 0)
		return -1;
	return n;
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

basename(path: string): string
{
	name := path;
	for(i := len path - 1; i >= 0; i--) {
		if(path[i] == '/') {
			name = path[i+1:];
			break;
		}
	}
	# Strip .plan extension
	if(len name > 5 && name[len name - 5:] == ".plan")
		name = name[0:len name - 5];
	return name;
}
