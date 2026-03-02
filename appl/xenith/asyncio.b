implement Asyncio;

include "common.m";

include "webclient.m";
	webclient: Webclient;

sys: Sys;
dat: Dat;
utils: Utils;
bufferm: Bufferm;

error, warning: import utils;
Buffer: import bufferm;

# Next operation ID
nextopid: int;

# Chunk size for reads
CHUNKSIZE: con 8*1024;

# Max content to load into heap — files larger than this get a header-only read
# (renderers like pdfrender stream directly from the file path)
MAXCONTENTLOAD: con 4*1024*1024;

init(mods: ref Dat->Mods)
{
	sys = mods.sys;
	dat = mods.dat;
	utils = mods.utils;
	bufferm = mods.bufferm;

	nextopid = 1;
	# Initialize the global casync channel in dat module
	# Buffer size of 64 allows async tasks to make progress even when
	# the main loop is in a nested event loop (e.g., dragwin)
	dat->casync = chan[64] of ref AsyncMsg;
}

asyncload(path: string, q0: int): ref AsyncOp
{
	op := ref AsyncOp;
	op.opid = nextopid++;
	op.ctl = chan[1] of int;
	op.path = path;
	op.active = 1;
	op.winid = 0;

	spawn readtask(op, path, q0);
	return op;
}

asyncloadimage(path: string, winid: int): ref AsyncOp
{
	op := ref AsyncOp;
	op.opid = nextopid++;
	op.ctl = chan[1] of int;
	op.path = path;
	op.active = 1;
	op.winid = winid;

	spawn imagetask(op, path, winid);
	return op;
}

asyncloadtext(path: string, q0: int, winid: int): ref AsyncOp
{
	op := ref AsyncOp;
	op.opid = nextopid++;
	op.ctl = chan[1] of int;
	op.path = path;
	op.active = 1;
	op.winid = winid;

	spawn texttask(op, path, q0, winid);
	return op;
}

texttask(op: ref AsyncOp, path: string, q0: int, winid: int)
{
	# Check for cancellation before starting
	alt {
		<-op.ctl =>
			op.active = 0;
			return;
		* => ;
	}

	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) {
		# Non-blocking send - if cancelled, just exit
		alt {
			dat->casync <-= ref AsyncMsg.TextComplete(op.opid, winid, path, 0, 0, sys->sprint("can't open: %r")) => ;
			<-op.ctl => ;
		}
		op.active = 0;
		return;
	}

	# Get file size for progress
	(ok, dir) := sys->fstat(fd);
	fsize := 0;
	if(ok == 0)
		fsize = int dir.length;

	pbuf := array[Dat->Maxblock+Sys->UTFmax] of byte;
	m := 0;
	nbytes := 0;
	nrunes := 0;

	for(;;) {
		# Check for cancellation
		alt {
			<-op.ctl =>
				fd = nil;
				op.active = 0;
				return;
			* => ;
		}

		n := sys->read(fd, pbuf[m:], Dat->Maxblock);
		if(n < 0) {
			fd = nil;
			# Non-blocking send
			alt {
				dat->casync <-= ref AsyncMsg.TextComplete(op.opid, winid, path, nbytes, nrunes, sys->sprint("read error: %r")) => ;
				<-op.ctl => ;
			}
			op.active = 0;
			return;
		}
		if(n == 0)
			break;

		m += n;
		# Find valid UTF-8 boundary
		nb := sys->utfbytes(pbuf, m);
		if(nb == 0 && m > 0) {
			# No complete characters yet, need more data
			continue;
		}

		data := string pbuf[0:nb];
		nr := len data;

		# Move leftover bytes to start
		if(nb < m) {
			pbuf[0:] = pbuf[nb:m];
			m = m - nb;
		} else {
			m = 0;
		}

		nbytes += nb;

		# Send chunk - retry with cancellation check if channel full
		for(;;) {
			alt {
				dat->casync <-= ref AsyncMsg.TextData(op.opid, winid, path, q0, data, nrunes, nil) =>
					nrunes += nr;
				<-op.ctl =>
					fd = nil;
					op.active = 0;
					return;
				* =>
					# Channel full - yield and retry
					sys->sleep(1);
					continue;
			}
			break;
		}
	}

	fd = nil;
	# Final send - non-blocking with cancellation check
	alt {
		dat->casync <-= ref AsyncMsg.TextComplete(op.opid, winid, path, nbytes, nrunes, nil) => ;
		<-op.ctl => ;
	}
	op.active = 0;
}

imagetask(op: ref AsyncOp, path: string, winid: int)
{
	# Check for cancellation before starting
	alt {
		<-op.ctl =>
			# Non-blocking error send - drop if channel full
			alt { dat->casync <-= ref AsyncMsg.ImageData(op.opid, winid, path, nil, "cancelled") => ; * => ; }
			op.active = 0;
			return;
		* => ;
	}

	# Open file
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) {
		# Non-blocking error send
		alt { dat->casync <-= ref AsyncMsg.ImageData(op.opid, winid, path, nil, sys->sprint("can't open: %r")) => ; * => ; }
		op.active = 0;
		return;
	}

	# Get file size
	(ok, dir) := sys->fstat(fd);
	if(ok != 0) {
		fd = nil;
		alt { dat->casync <-= ref AsyncMsg.ImageData(op.opid, winid, path, nil, "can't stat file") => ; * => ; }
		op.active = 0;
		return;
	}
	fsize := int dir.length;
	if(fsize <= 0) {
		fd = nil;
		alt { dat->casync <-= ref AsyncMsg.ImageData(op.opid, winid, path, nil, "empty file") => ; * => ; }
		op.active = 0;
		return;
	}
	# No arbitrary file size limit - imgload.b handles large images
	# by automatically subsampling to fit in available memory

	# Allocate buffer and read entire file
	data := array[fsize] of byte;
	total := 0;
	while(total < fsize) {
		# Check for cancellation periodically
		alt {
			<-op.ctl =>
				fd = nil;
				alt { dat->casync <-= ref AsyncMsg.ImageData(op.opid, winid, path, nil, "cancelled") => ; * => ; }
				op.active = 0;
				return;
			* => ;
		}

		n := sys->read(fd, data[total:], fsize - total);
		if(n <= 0)
			break;
		total += n;
	}
	fd = nil;

	if(total < fsize) {
		alt { dat->casync <-= ref AsyncMsg.ImageData(op.opid, winid, path, nil, "short read") => ; * => ; }
		op.active = 0;
		return;
	}

	# Send raw bytes to main thread - retry with cancellation check if channel full
	for(;;) {
		alt {
			dat->casync <-= ref AsyncMsg.ImageData(op.opid, winid, path, data, nil) => ;
			<-op.ctl =>
				op.active = 0;
				return;
			* =>
				# Channel full - yield and retry
				sys->sleep(1);
				continue;
		}
		break;
	}
	op.active = 0;
}

asyncloadcontent(path: string, winid: int): ref AsyncOp
{
	op := ref AsyncOp;
	op.opid = nextopid++;
	op.ctl = chan[1] of int;
	op.path = path;
	op.active = 1;
	op.winid = winid;

	spawn contenttask(op, path, winid);
	return op;
}

# Check if path is a URL
isurlpath(path: string): int
{
	if(len path >= 8 && path[0:8] == "https://")
		return 1;
	if(len path >= 7 && path[0:7] == "http://")
		return 1;
	return 0;
}

# Load raw content bytes (same I/O as imagetask, different message type)
# For URLs (http:// or https://), fetches via webclient instead of local file.
contenttask(op: ref AsyncOp, path: string, winid: int)
{
	alt {
		<-op.ctl =>
			alt { dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, path, nil, "cancelled") => ; * => ; }
			op.active = 0;
			return;
		* => ;
	}

	# URL fetch path — use webclient for http:// and https://
	if(isurlpath(path)) {
		contenttask_url(op, path, winid);
		return;
	}

	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) {
		alt { dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, path, nil, sys->sprint("can't open: %r")) => ; * => ; }
		op.active = 0;
		return;
	}

	(ok, dir) := sys->fstat(fd);
	if(ok != 0) {
		fd = nil;
		alt { dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, path, nil, "can't stat file") => ; * => ; }
		op.active = 0;
		return;
	}
	fsize := int dir.length;
	if(fsize <= 0) {
		fd = nil;
		alt { dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, path, nil, "empty file") => ; * => ; }
		op.active = 0;
		return;
	}

	# For large files, read only a header for format detection.
	# Renderers stream from the file path (hint) for actual I/O.
	readsize := fsize;
	if(readsize > MAXCONTENTLOAD)
		readsize = 8192;

	data := array[readsize] of byte;
	total := 0;
	while(total < readsize) {
		alt {
			<-op.ctl =>
				fd = nil;
				alt { dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, path, nil, "cancelled") => ; * => ; }
				op.active = 0;
				return;
			* => ;
		}

		n := sys->read(fd, data[total:], readsize - total);
		if(n <= 0)
			break;
		total += n;
	}
	fd = nil;

	if(total < readsize) {
		alt { dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, path, nil, "short read") => ; * => ; }
		op.active = 0;
		return;
	}

	for(;;) {
		alt {
			dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, path, data, nil) => ;
			<-op.ctl =>
				op.active = 0;
				return;
			* =>
				sys->sleep(1);
				continue;
		}
		break;
	}
	op.active = 0;
}

# Fetch URL content via webclient and send as ContentData
contenttask_url(op: ref AsyncOp, url: string, winid: int)
{
	stderr := sys->fildes(2);

	# Load webclient lazily
	if(webclient == nil) {
		webclient = load Webclient Webclient->PATH;
		if(webclient == nil) {
			sys->fprint(stderr, "webfetch: can't load webclient\n");
			dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, url, nil, "can't load webclient");
			op.active = 0;
			return;
		}
		err := webclient->init();
		if(err != nil) {
			sys->fprint(stderr, "webfetch: webclient init: %s\n", err);
			dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, url, nil, "webclient init: " + err);
			op.active = 0;
			return;
		}
	}

	# Check for cancellation before fetch
	alt {
		<-op.ctl =>
			dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, url, nil, "cancelled");
			op.active = 0;
			return;
		* => ;
	}

	sys->fprint(stderr, "webfetch: fetching %s\n", url);
	(resp, err) := webclient->get(url);
	if(err != nil) {
		sys->fprint(stderr, "webfetch: fetch error: %s\n", err);
		dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, url, nil, "fetch: " + err);
		op.active = 0;
		return;
	}

	sys->fprint(stderr, "webfetch: got %d bytes\n", len resp.body);
	if(resp.body == nil || len resp.body == 0) {
		dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, url, nil, "empty response");
		op.active = 0;
		return;
	}

	# Send response body as content data
	dat->casync <-= ref AsyncMsg.ContentData(op.opid, winid, url, resp.body, nil);
	op.active = 0;
}

asynccancel(op: ref AsyncOp)
{
	if(op != nil && op.active) {
		op.active = 0;
		# Non-blocking send to cancel
		alt {
			op.ctl <-= 1 => ;
			* => ;
		}
	}
}

asyncactive(op: ref AsyncOp): int
{
	if(op == nil)
		return 0;
	return op.active;
}

readtask(op: ref AsyncOp, path: string, q0: int)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) {
		dat->casync <-= ref AsyncMsg.Error(op.opid, sys->sprint("can't open %s: %r", path));
		op.active = 0;
		return;
	}

	# Get file size for progress reporting
	(ok, dir) := sys->fstat(fd);
	total := 0;
	if(ok == 0)
		total = int dir.length;

	buf := array[CHUNKSIZE + Sys->UTFmax] of byte;
	nbytes := 0;
	nrunes := 0;
	offset := q0;
	leftover := 0;  # Bytes left over from partial UTF-8 sequence

	for(;;) {
		# Check for cancellation
		alt {
			<-op.ctl =>
				fd = nil;
				dat->casync <-= ref AsyncMsg.Error(op.opid, "cancelled");
				op.active = 0;
				return;
			* => ;
		}

		n := sys->read(fd, buf[leftover:], CHUNKSIZE);
		if(n < 0) {
			dat->casync <-= ref AsyncMsg.Error(op.opid, sys->sprint("read error: %r"));
			op.active = 0;
			return;
		}
		if(n == 0)
			break;

		m := leftover + n;
		# Find valid UTF-8 boundary
		nb := sys->utfbytes(buf, m);
		if(nb == 0 && m > 0) {
			# No complete characters yet, need more data
			leftover = m;
			continue;
		}

		s := string buf[0:nb];
		nr := len s;

		# Move leftover bytes to start
		if(nb < m) {
			buf[0:] = buf[nb:m];
			leftover = m - nb;
		} else {
			leftover = 0;
		}

		nbytes += nb;
		nrunes += nr;

		# Send chunk
		dat->casync <-= ref AsyncMsg.Chunk(op.opid, s, offset);
		offset += nr;

		# Send progress every 64KB
		if((nbytes % (64*1024)) < CHUNKSIZE)
			dat->casync <-= ref AsyncMsg.Progress(op.opid, nbytes, total);
	}

	fd = nil;
	dat->casync <-= ref AsyncMsg.Complete(op.opid, nbytes, nrunes, nil);
	op.active = 0;
}

asyncloaddir(path: string, winid: int): ref AsyncOp
{
	op := ref AsyncOp;
	op.opid = nextopid++;
	op.ctl = chan[1] of int;
	op.path = path;
	op.active = 1;
	op.winid = winid;

	spawn dirtask(op, path, winid);
	return op;
}

dirtask(op: ref AsyncOp, path: string, winid: int)
{
	# Check for cancellation before starting
	alt {
		<-op.ctl =>
			op.active = 0;
			return;
		* => ;
	}

	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) {
		alt {
			dat->casync <-= ref AsyncMsg.DirComplete(op.opid, winid, path, 0, sys->sprint("can't open: %r")) => ;
			<-op.ctl => ;
		}
		op.active = 0;
		return;
	}

	nentries := 0;

	for(;;) {
		# Check for cancellation
		alt {
			<-op.ctl =>
				fd = nil;
				op.active = 0;
				return;
			* => ;
		}

		(nd, dbuf) := sys->dirread(fd);
		if(nd <= 0)
			break;

		for(i := 0; i < nd; i++) {
			name := dbuf[i].name;
			isdir := 0;
			if(dbuf[i].mode & Sys->DMDIR) {
				name = name + "/";
				isdir = 1;
			}

			# Send entry - retry with cancellation check if channel full
			for(;;) {
				alt {
					dat->casync <-= ref AsyncMsg.DirEntry(op.opid, winid, name, isdir) =>
						nentries++;
					<-op.ctl =>
						fd = nil;
						op.active = 0;
						return;
					* =>
						# Channel full - yield and retry
						sys->sleep(1);
						continue;
				}
				break;
			}
		}
	}

	fd = nil;
	# Final send - non-blocking with cancellation check
	alt {
		dat->casync <-= ref AsyncMsg.DirComplete(op.opid, winid, path, nentries, nil) => ;
		<-op.ctl => ;
	}
	op.active = 0;
}

asyncsavefile(path: string, winid: int, buf: ref Bufferm->Buffer, q0, q1: int): ref AsyncOp
{
	op := ref AsyncOp;
	op.opid = nextopid++;
	op.ctl = chan[1] of int;
	op.path = path;
	op.active = 1;
	op.winid = winid;

	spawn savetask(op, path, winid, buf, q0, q1);
	return op;
}

savetask(op: ref AsyncOp, path: string, winid: int, buf: ref Bufferm->Buffer, q0, q1: int)
{
	# Check for cancellation before starting
	alt {
		<-op.ctl =>
			op.active = 0;
			return;
		* => ;
	}

	fd := sys->create(path, Sys->OWRITE, 8r664);
	if(fd == nil) {
		alt {
			dat->casync <-= ref AsyncMsg.SaveComplete(op.opid, winid, path, 0, 0, sys->sprint("can't create: %r")) => ;
			<-op.ctl => ;
		}
		op.active = 0;
		return;
	}

	total := q1 - q0;
	written := 0;
	rp := ref Dat->Astring;

	for(q := q0; q < q1; ) {
		# Check for cancellation
		alt {
			<-op.ctl =>
				fd = nil;
				op.active = 0;
				return;
			* => ;
		}

		n := q1 - q;
		if(n > Dat->BUFSIZE)
			n = Dat->BUFSIZE;

		buf.read(q, rp, 0, n);
		ab := array of byte rp.s[0:n];

		nw := sys->write(fd, ab, len ab);
		ab = nil;

		if(nw != len ab) {
			fd = nil;
			alt {
				dat->casync <-= ref AsyncMsg.SaveComplete(op.opid, winid, path, written, 0, sys->sprint("write error: %r")) => ;
				<-op.ctl => ;
			}
			op.active = 0;
			return;
		}

		written += nw;
		q += n;

		# Send progress every 64KB
		if((written % (64*1024)) < Dat->BUFSIZE) {
			alt {
				dat->casync <-= ref AsyncMsg.SaveProgress(op.opid, winid, written, total) => ;
				<-op.ctl =>
					fd = nil;
					op.active = 0;
					return;
				* => ;
			}
		}
	}

	# Get new mtime
	(ok, dir) := sys->fstat(fd);
	mtime := 0;
	if(ok == 0)
		mtime = dir.mtime;

	fd = nil;
	# Final send - non-blocking with cancellation check
	alt {
		dat->casync <-= ref AsyncMsg.SaveComplete(op.opid, winid, path, written, mtime, nil) => ;
		<-op.ctl => ;
	}
	op.active = 0;
}
