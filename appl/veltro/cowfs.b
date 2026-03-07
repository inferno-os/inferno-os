implement Cowfs;

#
# cowfs.b - Copy-on-Write Filesystem for Veltro Agent Safety
#
# Styx server providing a transparent overlay over a base directory.
# Reads fall through to the base when overlay has no modification.
# Writes are redirected to the overlay directory.
# Deletes create whiteout entries so base files appear removed.
#
# The overlay directory stores:
#   - Modified/new files at their relative paths
#   - .whiteout file listing deleted paths (one per line)
#   - .cowmeta file with basepath and metadata
#
# Module-level functions (diff, promote, revert) operate directly
# on overlay and base directories without going through Styx.
#

include "sys.m";
	sys: Sys;
	Qid: import Sys;

include "draw.m";

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "styxservers.m";
	styxservers: Styxservers;
	Fid, Styxserver, Navigator, Navop: import styxservers;
	Enotfound, Eperm, Ebadarg: import styxservers;

include "readdir.m";
	readdir: Readdir;

include "cowfs.m";

# Permissions
DIR_PERM: con 8r755 | Sys->DMDIR;
FILE_PERM: con 8r644;

# QID management: dynamic path → relative path mapping
PathEntry: adt {
	qpath:   big;      # qid path value
	relpath: string;   # relative path from base ("" = root)
	isdir:   int;      # cached directory flag
};

# Per-instance server state (captured in closures via channels)
SrvState: adt {
	basepath:   string;
	overlaydir: string;
	whiteouts:  list of string;   # whiteout relative paths
	entries:    list of ref PathEntry;
	nextqpath:  big;
	vers:       int;
};

# Internal file names to hide from directory listings
WHITEOUT_FILE: con ".whiteout";
META_FILE: con ".cowmeta";

stderr: ref Sys->FD;
user: string;

nomod(s: string)
{
	sys->fprint(stderr, "cowfs: can't load %s: %r\n", s);
	raise "fail:load";
}

# --- Module interface ---

start(basepath, overlaydir: string): (ref Sys->FD, string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	styx = load Styx Styx->PATH;
	if(styx == nil)
		return (nil, sys->sprint("can't load %s: %r", Styx->PATH));
	styx->init();

	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil)
		return (nil, sys->sprint("can't load %s: %r", Styxservers->PATH));
	styxservers->init(styx);

	readdir = load Readdir Readdir->PATH;
	if(readdir == nil)
		return (nil, sys->sprint("can't load %s: %r", Readdir->PATH));

	user = rf("/dev/user");
	if(user == nil)
		user = "inferno";

	# Verify base exists
	(bok, bdir) := sys->stat(basepath);
	if(bok < 0)
		return (nil, sys->sprint("base path %s: %r", basepath));
	if(!(bdir.mode & Sys->DMDIR))
		return (nil, basepath + " is not a directory");

	# Ensure overlay dir exists
	merr := mkdirp(overlaydir);
	if(merr != nil)
		return (nil, merr);

	# Write metadata
	writemeta(overlaydir, basepath);

	# Load whiteouts
	wh := loadwhiteouts(overlaydir);

	# Initialize server state
	state := ref SrvState(
		basepath, overlaydir, wh,
		nil, big 1, 0    # root = qpath 0 added below
	);

	# Add root entry
	state.entries = ref PathEntry(big 0, "", 1) :: state.entries;

	# Create pipe
	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0)
		return (nil, sys->sprint("can't create pipe: %r"));

	navops := chan of ref Navop;
	spawn navigator(navops, state);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big 0);
	fds[0] = nil;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc, navops, state);
	<-pidc;

	return (fds[1], nil);
}

diff(overlaydir: string): list of string
{
	initsys();

	result: list of string;

	# List whiteout entries as "D relpath"
	wh := loadwhiteouts(overlaydir);
	for(; wh != nil; wh = tl wh)
		result = ("D " + hd wh) :: result;

	# Walk overlay directory for modified/added files
	basepath := readmeta(overlaydir);
	meta := ref MetaInfo(basepath, overlaydir);
	result = diffwalk(overlaydir, "", meta, result);

	# Reverse for stable ordering
	rev: list of string;
	for(; result != nil; result = tl result)
		rev = hd result :: rev;
	return rev;
}

modcount(overlaydir: string): int
{
	initsys();

	n := 0;

	# Count whiteouts
	wh := loadwhiteouts(overlaydir);
	for(; wh != nil; wh = tl wh)
		n++;

	# Count overlay files
	n += countfiles(overlaydir, "");

	return n;
}

promote(basepath, overlaydir: string): (int, string)
{
	initsys();

	count := 0;

	# Apply whiteout deletes to base
	wh := loadwhiteouts(overlaydir);
	for(; wh != nil; wh = tl wh) {
		relpath := hd wh;
		bpath := basepath + "/" + relpath;
		# Remove from base (best-effort)
		removefile(bpath);
		count++;
	}

	# Copy overlay files to base
	(n, err) := promotewalk(basepath, overlaydir, "");
	if(err != nil)
		return (count + n, err);
	count += n;

	# Clear overlay
	clearoverlay(overlaydir);

	# Re-write metadata (overlay is now clean)
	writemeta(overlaydir, basepath);

	return (count, nil);
}

promotefile(basepath, overlaydir, relpath: string): string
{
	initsys();

	# Check if it's a whiteout (deletion)
	wh := loadwhiteouts(overlaydir);
	if(inlist(relpath, wh)) {
		# Apply delete to base
		bpath := basepath + "/" + relpath;
		removefile(bpath);
		# Remove from whiteout list
		newwh: list of string;
		for(; wh != nil; wh = tl wh)
			if(hd wh != relpath)
				newwh = hd wh :: newwh;
		savewhiteouts(overlaydir, newwh);
		return nil;
	}

	# Copy overlay file to base
	opath := overlaydir + "/" + relpath;
	bpath := basepath + "/" + relpath;

	(ook, nil) := sys->stat(opath);
	if(ook < 0)
		return sys->sprint("overlay file not found: %s", relpath);

	# Ensure parent in base
	ensureparent(bpath);

	err := copyfile(opath, bpath);
	if(err != nil)
		return err;

	# Remove from overlay
	sys->remove(opath);

	return nil;
}

revert(overlaydir: string): string
{
	initsys();
	clearoverlay(overlaydir);
	return nil;
}

revertfile(overlaydir, relpath: string): string
{
	initsys();

	# Remove from whiteout list if present
	wh := loadwhiteouts(overlaydir);
	if(inlist(relpath, wh)) {
		newwh: list of string;
		for(; wh != nil; wh = tl wh)
			if(hd wh != relpath)
				newwh = hd wh :: newwh;
		savewhiteouts(overlaydir, newwh);
		return nil;
	}

	# Remove overlay file
	opath := overlaydir + "/" + relpath;
	sys->remove(opath);
	return nil;
}

# --- Helper: ensure sys is loaded (for module-level functions) ---

initsys()
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(stderr == nil)
		stderr = sys->fildes(2);
	if(readdir == nil)
		readdir = load Readdir Readdir->PATH;
}

# --- Metadata tracking ---

MetaInfo: adt {
	basepath:   string;
	overlaydir: string;
};

writemeta(overlaydir, basepath: string)
{
	path := overlaydir + "/" + META_FILE;
	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd != nil) {
		sys->fprint(fd, "basepath=%s\n", basepath);
		fd = nil;
	}
}

# --- Whiteout management ---

loadwhiteouts(overlaydir: string): list of string
{
	path := overlaydir + "/" + WHITEOUT_FILE;
	content := rf(path);
	if(content == nil)
		return nil;

	result: list of string;
	line := "";
	for(i := 0; i < len content; i++) {
		if(content[i] == '\n') {
			if(len line > 0)
				result = line :: result;
			line = "";
		} else
			line[len line] = content[i];
	}
	if(len line > 0)
		result = line :: result;

	return result;
}

savewhiteouts(overlaydir: string, wh: list of string)
{
	path := overlaydir + "/" + WHITEOUT_FILE;
	if(wh == nil) {
		sys->remove(path);
		return;
	}

	fd := sys->create(path, Sys->OWRITE, 8r644);
	if(fd == nil)
		return;

	for(; wh != nil; wh = tl wh)
		sys->fprint(fd, "%s\n", hd wh);

	fd = nil;
}

addwhiteout(state: ref SrvState, relpath: string)
{
	if(!inlist(relpath, state.whiteouts))
		state.whiteouts = relpath :: state.whiteouts;
	savewhiteouts(state.overlaydir, state.whiteouts);
}

removewhiteout(state: ref SrvState, relpath: string)
{
	newwh: list of string;
	for(wh := state.whiteouts; wh != nil; wh = tl wh)
		if(hd wh != relpath)
			newwh = hd wh :: newwh;
	state.whiteouts = newwh;
	savewhiteouts(state.overlaydir, state.whiteouts);
}

iswhiteout(state: ref SrvState, relpath: string): int
{
	return inlist(relpath, state.whiteouts);
}

# --- QID / path management ---

lookuppath(state: ref SrvState, qpath: big): ref PathEntry
{
	for(e := state.entries; e != nil; e = tl e)
		if((hd e).qpath == qpath)
			return hd e;
	return nil;
}

findbyrel(state: ref SrvState, relpath: string): ref PathEntry
{
	for(e := state.entries; e != nil; e = tl e)
		if((hd e).relpath == relpath)
			return hd e;
	return nil;
}

getoralloc(state: ref SrvState, relpath: string, isdir: int): ref PathEntry
{
	pe := findbyrel(state, relpath);
	if(pe != nil) {
		pe.isdir = isdir;
		return pe;
	}

	pe = ref PathEntry(state.nextqpath, relpath, isdir);
	state.nextqpath++;
	state.entries = pe :: state.entries;
	return pe;
}

# Build a relpath from parent + child name
joinrel(parent, name: string): string
{
	if(parent == "")
		return name;
	return parent + "/" + name;
}

# --- File resolution: overlay-first, then base ---

# Resolve a relative path to the actual filesystem path (overlay or base).
# Returns (actual_path, exists, is_in_overlay).
resolve(state: ref SrvState, relpath: string): (string, int, int)
{
	# Check whiteout first
	if(relpath != "" && iswhiteout(state, relpath))
		return ("", 0, 0);

	# Check overlay
	opath := state.overlaydir + "/" + relpath;
	(ook, nil) := sys->stat(opath);
	if(ook >= 0)
		return (opath, 1, 1);

	# Check base
	bpath := state.basepath + "/" + relpath;
	if(relpath == "")
		bpath = state.basepath;
	(bok, nil) := sys->stat(bpath);
	if(bok >= 0)
		return (bpath, 1, 0);

	return ("", 0, 0);
}

# --- Styx server ---

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver,
	pidc: chan of int, navops: chan of ref Navop, state: ref SrvState)
{
	pidc <-= sys->pctl(Sys->FORKNS|Sys->NEWFD, 1 :: 2 :: srv.fd.fd :: nil);

Serve:
	while((gm := <-tchan) != nil) {
		pick m := gm {
		Readerror =>
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

		Create =>
			c := srv.getfid(m.fid);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
				break;
			}
			pe := lookuppath(state, c.path);
			if(pe == nil || !pe.isdir) {
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
				break;
			}

			relpath := joinrel(pe.relpath, m.name);

			# Remove whiteout if creating over a deleted file
			if(iswhiteout(state, relpath))
				removewhiteout(state, relpath);

			# Create in overlay
			isdir := (m.perm & Sys->DMDIR) != 0;
			opath := state.overlaydir + "/" + relpath;
			ensureparent(opath);

			fd: ref Sys->FD;
			if(isdir) {
				fd = sys->create(opath, Sys->OREAD, DIR_PERM);
			} else {
				fd = sys->create(opath, Sys->OWRITE, FILE_PERM);
			}
			if(fd == nil) {
				srv.reply(ref Rmsg.Error(m.tag, sys->sprint("create: %r")));
				break;
			}
			fd = nil;

			newpe := getoralloc(state, relpath, isdir);
			state.vers++;
			qt := Sys->QTFILE;
			if(isdir)
				qt = Sys->QTDIR;
			qid := Qid(newpe.qpath, state.vers, qt);
			c.open(styxservers->openmode(m.mode), qid);
			c.path = newpe.qpath;
			c.qtype = qt;
			srv.reply(ref Rmsg.Create(m.tag, qid, srv.iounit()));

		Read =>
			(c, rerr) := srv.canread(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, rerr));
				break;
			}
			if(c.qtype & Sys->QTDIR) {
				srv.read(m);
				break;
			}

			pe := lookuppath(state, c.path);
			if(pe == nil) {
				srv.reply(ref Rmsg.Error(m.tag, Enotfound));
				break;
			}

			(rpath, exists, nil) := resolve(state, pe.relpath);
			if(!exists) {
				srv.reply(ref Rmsg.Error(m.tag, Enotfound));
				break;
			}

			# Read from resolved path
			data := readat(rpath, int m.offset, m.count);
			srv.reply(ref Rmsg.Read(m.tag, data));

		Write =>
			(c, werr) := srv.canwrite(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, werr));
				break;
			}

			pe := lookuppath(state, c.path);
			if(pe == nil) {
				srv.reply(ref Rmsg.Error(m.tag, Enotfound));
				break;
			}

			# Copy-up: if file exists in base but not overlay, copy first
			opath := state.overlaydir + "/" + pe.relpath;
			(ook, nil) := sys->stat(opath);
			if(ook < 0) {
				# Not in overlay yet — check base for copy-up
				bpath := state.basepath + "/" + pe.relpath;
				(bok, nil) := sys->stat(bpath);
				if(bok >= 0) {
					ensureparent(opath);
					cerr := copyfile(bpath, opath);
					if(cerr != nil) {
						srv.reply(ref Rmsg.Error(m.tag, cerr));
						break;
					}
				} else {
					# New file — ensure parent dir
					ensureparent(opath);
				}
			}

			# Write to overlay
			fd := sys->open(opath, Sys->OWRITE);
			if(fd == nil) {
				fd = sys->create(opath, Sys->OWRITE, FILE_PERM);
			}
			if(fd == nil) {
				srv.reply(ref Rmsg.Error(m.tag, sys->sprint("write: %r")));
				break;
			}
			sys->seek(fd, m.offset, Sys->SEEKSTART);
			n := sys->write(fd, m.data, len m.data);
			fd = nil;
			if(n < 0) {
				srv.reply(ref Rmsg.Error(m.tag, sys->sprint("write: %r")));
				break;
			}

			# Remove whiteout if writing over a deleted file
			if(iswhiteout(state, pe.relpath))
				removewhiteout(state, pe.relpath);

			state.vers++;
			srv.reply(ref Rmsg.Write(m.tag, n));

		Remove =>
			(c, nil, rerr) := srv.canremove(m);
			if(c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, rerr));
				break;
			}
			pe := lookuppath(state, c.path);
			if(pe == nil || pe.relpath == "") {
				# Can't remove root
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
				break;
			}

			# Remove from overlay if present
			opath := state.overlaydir + "/" + pe.relpath;
			sys->remove(opath);

			# If file exists in base, add whiteout
			bpath := state.basepath + "/" + pe.relpath;
			(bok, nil) := sys->stat(bpath);
			if(bok >= 0)
				addwhiteout(state, pe.relpath);

			state.vers++;
			srv.reply(ref Rmsg.Remove(m.tag));

		Clunk =>
			srv.clunk(m);

		* =>
			srv.default(gm);
		}
	}
	navops <-= nil;
}

# --- Navigator ---

navigator(navops: chan of ref Navop, state: ref SrvState)
{
	while((m := <-navops) != nil) {
		pick n := m {
		Stat =>
			n.reply <-= cowstat(state, n.path);

		Walk =>
			pe := lookuppath(state, n.path);
			if(pe == nil) {
				n.reply <-= (nil, Enotfound);
				continue;
			}

			if(n.name == "..") {
				# Go up to parent
				parent := parentrel(pe.relpath);
				ppe := findbyrel(state, parent);
				if(ppe == nil)
					ppe = getoralloc(state, parent, 1);
				n.reply <-= cowstat(state, ppe.qpath);
				continue;
			}

			if(!pe.isdir) {
				n.reply <-= (nil, "not a directory");
				continue;
			}

			# Walk into child
			childrel := joinrel(pe.relpath, n.name);

			# Check whiteout
			if(iswhiteout(state, childrel)) {
				n.reply <-= (nil, Enotfound);
				continue;
			}

			# Resolve child
			(rpath, exists, nil) := resolve(state, childrel);
			if(!exists) {
				n.reply <-= (nil, Enotfound);
				continue;
			}

			# Stat the resolved path
			(ok, dir) := sys->stat(rpath);
			if(ok < 0) {
				n.reply <-= (nil, Enotfound);
				continue;
			}
			isdir := (dir.mode & Sys->DMDIR) != 0;
			cpe := getoralloc(state, childrel, isdir);
			n.reply <-= cowstat(state, cpe.qpath);

		Readdir =>
			pe := lookuppath(state, m.path);
			if(pe == nil || !pe.isdir) {
				n.reply <-= (nil, "not a directory");
				continue;
			}

			# Merge overlay + base directory entries
			entries := mergedirents(state, pe.relpath);

			# Serve requested range
			i := n.offset;
			for(e := entries; e != nil && i > 0; e = tl e)
				i--;
			count := n.count;
			for(; e != nil && count > 0; e = tl e) {
				child := hd e;
				cpe := getoralloc(state, child.relpath, child.isdir);
				n.reply <-= cowstat(state, cpe.qpath);
				count--;
			}
			n.reply <-= (nil, nil);
		}
	}
}

# Generate a Sys->Dir for a qid path
cowstat(state: ref SrvState, qpath: big): (ref Sys->Dir, string)
{
	pe := lookuppath(state, qpath);
	if(pe == nil)
		return (nil, Enotfound);

	(rpath, exists, nil) := resolve(state, pe.relpath);
	if(!exists && pe.relpath != "")
		return (nil, Enotfound);

	# For root, use base directory
	if(pe.relpath == "")
		rpath = state.basepath;

	(ok, rdir) := sys->stat(rpath);
	if(ok < 0)
		return (nil, Enotfound);

	d := ref sys->zerodir;
	d.qid.path = qpath;
	d.qid.vers = state.vers;
	if(rdir.mode & Sys->DMDIR) {
		d.qid.qtype = Sys->QTDIR;
		d.mode = DIR_PERM;
	} else {
		d.qid.qtype = Sys->QTFILE;
		d.mode = FILE_PERM;
	}
	d.length = rdir.length;
	d.uid = user;
	d.gid = user;
	d.mtime = rdir.mtime;
	d.atime = rdir.atime;

	# Name is the last component, or "." for root
	if(pe.relpath == "")
		d.name = ".";
	else
		d.name = basename(pe.relpath);

	return (d, nil);
}

# --- Merged directory entries ---

DirEnt: adt {
	relpath: string;
	name:    string;
	isdir:   int;
};

mergedirents(state: ref SrvState, parentrel: string): list of ref DirEnt
{
	seen: list of string;
	result: list of ref DirEnt;

	# 1. Read overlay entries (takes priority)
	odir := state.overlaydir;
	if(parentrel != "")
		odir += "/" + parentrel;
	(odirs, on) := readdir->init(odir, Readdir->NAME);
	for(i := 0; i < on; i++) {
		name := odirs[i].name;
		if(isinternal(name))
			continue;
		childrel := joinrel(parentrel, name);
		if(iswhiteout(state, childrel))
			continue;
		isdir := (odirs[i].mode & Sys->DMDIR) != 0;
		result = ref DirEnt(childrel, name, isdir) :: result;
		seen = name :: seen;
	}

	# 2. Read base entries (fill in what overlay doesn't have)
	bdir := state.basepath;
	if(parentrel != "")
		bdir += "/" + parentrel;
	(bdirs, bn) := readdir->init(bdir, Readdir->NAME);
	for(i = 0; i < bn; i++) {
		name := bdirs[i].name;
		childrel := joinrel(parentrel, name);
		if(inlist(name, seen))
			continue;
		if(iswhiteout(state, childrel))
			continue;
		isdir := (bdirs[i].mode & Sys->DMDIR) != 0;
		result = ref DirEnt(childrel, name, isdir) :: result;
	}

	# Reverse for stable ordering
	rev: list of ref DirEnt;
	for(; result != nil; result = tl result)
		rev = hd result :: rev;
	return rev;
}

# --- File I/O helpers ---

readat(path: string, offset, count: int): array of byte
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return array[0] of byte;

	sys->seek(fd, big offset, Sys->SEEKSTART);
	buf := array[count] of byte;
	n := sys->read(fd, buf, count);
	if(n <= 0)
		return array[0] of byte;
	return buf[0:n];
}

copyfile(src, dst: string): string
{
	sfd := sys->open(src, Sys->OREAD);
	if(sfd == nil)
		return sys->sprint("can't open %s: %r", src);

	dfd := sys->create(dst, Sys->OWRITE, FILE_PERM);
	if(dfd == nil)
		return sys->sprint("can't create %s: %r", dst);

	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(sfd, buf, len buf);
		if(n <= 0)
			break;
		w := sys->write(dfd, buf, n);
		if(w != n)
			return sys->sprint("write %s: %r", dst);
	}
	return nil;
}

removefile(path: string)
{
	# Try removing file. If directory, remove contents first.
	(ok, dir) := sys->stat(path);
	if(ok < 0)
		return;

	if(dir.mode & Sys->DMDIR) {
		(dirs, n) := readdir->init(path, Readdir->NONE);
		for(i := 0; i < n; i++)
			removefile(path + "/" + dirs[i].name);
	}
	sys->remove(path);
}

clearoverlay(overlaydir: string)
{
	(dirs, n) := readdir->init(overlaydir, Readdir->NONE);
	for(i := 0; i < n; i++)
		removefile(overlaydir + "/" + dirs[i].name);
}

# --- Diff / promote walk helpers ---

diffwalk(overlaydir, parentrel: string, meta: ref MetaInfo, result: list of string): list of string
{
	odir := overlaydir;
	if(parentrel != "")
		odir += "/" + parentrel;

	(dirs, n) := readdir->init(odir, Readdir->NAME);
	for(i := 0; i < n; i++) {
		name := dirs[i].name;
		if(isinternal(name))
			continue;

		childrel := joinrel(parentrel, name);

		if(dirs[i].mode & Sys->DMDIR) {
			# Recurse into subdirectories
			result = diffwalk(overlaydir, childrel, meta, result);
		} else {
			# Check if file exists in base
			bpath := meta.basepath + "/" + childrel;
			(bok, nil) := sys->stat(bpath);
			if(bok >= 0)
				result = ("M " + childrel) :: result;
			else
				result = ("A " + childrel) :: result;
		}
	}
	return result;
}

# Read basepath from .cowmeta for module-level diff function
readmeta(overlaydir: string): string
{
	content := rf(overlaydir + "/" + META_FILE);
	if(content == nil)
		return "";

	prefix := "basepath=";
	for(i := 0; i <= len content - len prefix; i++) {
		if(content[i:i + len prefix] == prefix) {
			# Find end of line
			j := i + len prefix;
			for(; j < len content && content[j] != '\n'; j++)
				;
			return content[i + len prefix:j];
		}
	}
	return "";
}

countfiles(overlaydir, parentrel: string): int
{
	n := 0;
	odir := overlaydir;
	if(parentrel != "")
		odir += "/" + parentrel;

	(dirs, dn) := readdir->init(odir, Readdir->NONE);
	for(i := 0; i < dn; i++) {
		name := dirs[i].name;
		if(isinternal(name))
			continue;
		if(dirs[i].mode & Sys->DMDIR)
			n += countfiles(overlaydir, joinrel(parentrel, name));
		else
			n++;
	}
	return n;
}

promotewalk(basepath, overlaydir, parentrel: string): (int, string)
{
	count := 0;
	odir := overlaydir;
	if(parentrel != "")
		odir += "/" + parentrel;

	(dirs, n) := readdir->init(odir, Readdir->NAME);
	for(i := 0; i < n; i++) {
		name := dirs[i].name;
		if(isinternal(name))
			continue;

		childrel := joinrel(parentrel, name);
		opath := overlaydir + "/" + childrel;
		bpath := basepath + "/" + childrel;

		if(dirs[i].mode & Sys->DMDIR) {
			# Ensure directory exists in base
			ensureparent(bpath + "/x");
			(ok, nil) := sys->stat(bpath);
			if(ok < 0) {
				fd := sys->create(bpath, Sys->OREAD, DIR_PERM);
				if(fd != nil)
					fd = nil;
			}
			# Recurse
			(cn, cerr) := promotewalk(basepath, overlaydir, childrel);
			count += cn;
			if(cerr != nil)
				return (count, cerr);
		} else {
			# Copy file to base
			ensureparent(bpath);
			err := copyfile(opath, bpath);
			if(err != nil)
				return (count, err);
			count++;
		}
	}
	return (count, nil);
}

# --- General helpers ---

basename(path: string): string
{
	for(i := len path - 1; i >= 0; i--)
		if(path[i] == '/')
			return path[i+1:];
	return path;
}

parentrel(relpath: string): string
{
	for(i := len relpath - 1; i >= 0; i--)
		if(relpath[i] == '/')
			return relpath[0:i];
	return "";
}

isinternal(name: string): int
{
	return name == WHITEOUT_FILE || name == META_FILE;
}

inlist(s: string, l: list of string): int
{
	for(; l != nil; l = tl l)
		if(hd l == s)
			return 1;
	return 0;
}

rf(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;
	result := "";
	buf := array[8192] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		result += string buf[0:n];
	}
	return result;
}

mkdirp(path: string): string
{
	(ok, nil) := sys->stat(path);
	if(ok >= 0)
		return nil;

	# Create parent first
	parent := "";
	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			parent = path[0:i];
			break;
		}
	}
	if(parent != "" && parent != "/") {
		err := mkdirp(parent);
		if(err != nil)
			return err;
	}

	fd := sys->create(path, Sys->OREAD, DIR_PERM);
	if(fd == nil)
		return sys->sprint("cannot create %s: %r", path);
	fd = nil;
	return nil;
}

ensureparent(path: string)
{
	for(i := len path - 1; i > 0; i--) {
		if(path[i] == '/') {
			mkdirp(path[0:i]);
			return;
		}
	}
}

hasprefix(s, prefix: string): int
{
	if(len prefix > len s)
		return 0;
	return s[0:len prefix] == prefix;
}
