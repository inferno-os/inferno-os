	bin = bufio->fopen(stdin, bufio->OREAD);
	seq = 0;
	nf = 0;
	f = nil;
	while((s=bin.gets('\n')) != nil){
		s = s[0:len s - 1];
		(n, tf) = findfile(s);
		if(n == 0)
			errors("no files match input", s);
		for(i=0; i<n; i++)
			tf[i].seq = seq++;
		off := f;
		f = array[n+nf] of File;
		if(f == nil)
			rerror("out of memory");
		if (off != nil) {
			f[0:] = off[0:nf];
			off = nil;
		}
		f[nf:] = tf[0:n];
		nf += n;
		tf = nil;
	}

	# sort by file name
	qsort(f, nf, NCMP);

	# convert to character positions if necessary
	for(i=0; i<nf; i++){
		f[i].ok = 1;
		# see if it's easy
		s = f[i].addr;
		if(s[0]=='#'){
			s = s[1:];
			n = 0;
			while(len s > 0 && '0'<=s[0] && s[0]<='9'){
				n = n*10+(s[0]-'0');
				s = s[1:];
			}
			f[i].q0 = n;
			if(len s == 0){
				f[i].q1 = n;
				continue;
			}
			if(s[0] == ',') {
				s = s[1:];
				n = 0;
				while(len s > 0 && '0'<=s[0] && s[0]<='9'){
					n = n*10+(s[0]-'0');
					s = s[1:];
				}
				f[i].q1 = n;
				if(len s == 0)
					continue;
			}
		}
		id = f[i].id;
		buf = sprint("/chan/%d/addr", id);
		afd = open(buf, ORDWR);
		if(afd == nil)
			rerror(buf);
		buf = sprint("/chan/%d/ctl", id);
		cfd = open(buf, ORDWR);
		if(cfd == nil)
			rerror(buf);
		if(write(cfd, array of byte "addr=dot\n", 9) != 9)
			rerror("setting address to dot");
		ab := array of byte f[i].addr;
		if(write(afd, ab, len ab) != len ab){
			fprint(stderr, "%s: %s:%s is invalid address\n", prog, f[i].name, f[i].addr);
			f[i].ok = 0;
			afd = cfd = nil;
			continue;
		}
		seek(afd, big 0, 0);
		bbuf := array[2*12] of byte;
		if(read(afd, bbuf, len bbuf) != 2*12)
			rerror("reading address");
		afd = cfd = nil;
		buf = string bbuf;
		bbuf = nil;
		f[i].q0 = int buf;
		f[i].q1 = int buf[12:];
	}
