implement Proxy;

include "sys.m";
	sys: Sys;

include "srvmgr.m";
include "proxy.m";

Srvreq, Srvreply: import Srvmgr;

init(root: string, fd: ref Sys->FD, rc: chan of ref Srvreq, user: string)
{
	sys = load Sys Sys->PATH;

	sys->chdir(root);
	sys->bind("export/services", "export/services", Sys->MCREATE);
	sys->bind("#s", "export/services", Sys->MBEFORE);

	ctlio := sys->file2chan("export/services", "ctl");

	hangup := chan of int;
	spawn export(fd, "export", hangup);
	fd = nil;

	for (;;) alt {
	<- hangup =>
		# closedown all clients
		sys->print("client exit [%s]\n", user);
		rmclients(rc);
		return;
	(offset, count, fid, r) := <- ctlio.read =>
		client := fid2client(fid);
		if (r == nil) {
			if (client != nil)
				rmclient(rc, client);
			continue;
		}
		if (client == nil) {
			rreply(r, (nil, "service not set"));
			continue;
		}
		rreply(r, reads(client.path, offset, count));

	(offset, data, fid, w) := <- ctlio.write =>
		client := fid2client(fid);
		if (w == nil) {
			if (client != nil)
				rmclient(rc, client);
			continue;
		}
		if (client != nil) {
			wreply(w, (0, "service set"));
			continue;
		}
		err := newclient(rc, user, fid, string data);
		if (err != nil)
			wreply(w, (0, err));
		else
			wreply(w, (len data, nil));
	}
	
}

rreply(rc: chan of (array of byte, string), reply: (array of byte, string))
{
	alt {
	rc <-= reply =>;
	* =>;
	}
}

wreply(wc: chan of (int, string), reply: (int, string))
{
	alt {
	wc <-= reply=>;
	* =>;
	}
}

reads(str: string, off, nbytes: int): (array of byte, string)
{
	bstr := array of byte str;
	slen := len bstr;
	if(off < 0 || off >= slen)
		return (nil, nil);
	if(off + nbytes > slen)
		nbytes = slen - off;
	if(nbytes <= 0)
		return (nil, nil);
	return (bstr[off:off+nbytes], nil);
}

export(exportfd: ref Sys->FD, dir: string, done: chan of int)
{
	sys->export(exportfd, dir, Sys->EXPWAIT);
	done <-= 1;
}

Client: adt {
	fid: int;
	path: string;
	sname: string;
	id: string;
};

clients: list of ref Client;
freepaths: list of string;
nextpath := 0;

fid2client(fid: int): ref Client
{
	for(cl := clients; cl != nil; cl = tl cl)
		if ((c := hd cl).fid == fid)
			return c;
	return nil;
}

newclient(rc: chan of ref Srvreq, user: string, fid: int, cmd: string): string
{
sys->print("new Client %s [%s]\n", user, cmd);
	for (i := 0; i < len cmd; i++)
		if (cmd[i] == ' ')
			break;
	if (i == 0 || i == len cmd)
		return "bad command";

	sname := cmd[:i];
	id := cmd[i:];
	reply := chan of Srvreply;
	rc <-= ref Srvreq.Acquire(sname, id, user, reply);
	(err, root, fd) := <- reply;
	if (err != nil)
		return err;

	path := "";
	if (freepaths != nil)
		(path, freepaths) = (hd freepaths, tl freepaths);
	else
		path = string nextpath++;

	sys->mount(fd, nil, "mnt", Sys->MREPL, nil);	# connection to the active service fs
	mkdir("export/services/"+path);
	sys->bind("mnt/"+root, "export/services/"+path, Sys->MREPL|Sys->MCREATE);
	sys->unmount("mnt", nil);
	clients = ref Client(fid, path, sname, id) :: clients;
	return nil;
}

rmclient(rc: chan of ref Srvreq, client: ref Client)
{
sys->print("rmclient [%s %s]\n", client.sname, client.id);
	nl: list of ref Client;
	for(cl := clients; cl != nil; cl = tl cl)
		if((c := hd cl) == client){
			sys->unmount("export/services/" + client.path, nil);
			freepaths = client.path :: freepaths;
			rc <-= ref Srvreq.Release(client.sname, client.id);
		} else
			nl = c :: nl;
	clients = nl;
}

rmclients(rc: chan of ref Srvreq)
{
	for(cl := clients; cl != nil; cl = tl cl){
		c := hd cl;
sys->print("rmclients [%s %s]\n", c.sname, c.id);
		rc <-= ref Srvreq.Release(c.sname, c.id);
	}
	clients = nil;
}

mkdir(path: string)
{
	sys->print("mkdir [%s]\n", path);
	sys->create(path, Sys->OREAD, 8r777 | Sys->DMDIR);
}
