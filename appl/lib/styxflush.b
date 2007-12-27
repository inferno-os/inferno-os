implement Styxflush;
include "sys.m";
	sys: Sys;
include "tables.m";
	tables: Tables;
	Table: import tables;
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "styxflush.m";

reqs: ref Table[ref Req];
Req: adt {
	m: ref Tmsg;
	flushc: chan of (int, chan of int);
	oldreq: cyclic ref Req;
	flushes: cyclic ref Req;		# flushes queued on this req.
	nextflush: cyclic ref Req;		# (flush only) next req in flush queue.
	flushready: chan of int;		# (flush only) wait for flush attempt.
	flushing: int;				# request is subject of a flush.
	finished: chan of int;			# [1]; signals finish to late flushers.
	responded: int;
};

init()
{
	sys = load Sys Sys->PATH;
	tables = load Tables Tables->PATH;
	styx = load Styx Styx->PATH;
	styx->init();

	reqs = Table[ref Req].new(11, nil);
}

tmsg(gm: ref Styx->Tmsg, flushc: chan of (int, chan of int), reply: chan of ref Styx->Rmsg): (int, ref Rmsg)
{
	req := ref Req(
		gm,
		flushc,				# flushc
		nil,					# oldreq
		nil,					# flushes
		nil,					# nextflush
		nil,					# flushready
		0,					# flushing
		chan[1] of int,			# finished
		0					# responded
	);
	if(reqs.add(gm.tag, req) == 0)
		return (1, ref Rmsg.Error(gm.tag, "duplicate tag"));
	pick m := gm {
	Flush =>
		req.oldreq = reqs.find(m.oldtag);
		if(req.oldreq == nil)
			return (1, ref Rmsg.Flush(m.tag));
		addflush(req);
		req.flushc = chan of (int, chan of int);
		spawn flushreq(req, reply);
		return (1, nil);
	}
	return (0, nil);
}

rmsg(rm: ref Styx->Rmsg): int
{
	req := reqs.find(rm.tag);
	if(req == nil){
		complain("req has disappeared, reply "+rm.text());
		return 0;
	}
	reqs.del(rm.tag);
	if(tagof rm == tagof Rmsg.Flush)
		delflush(req);
	if(req.flushing)
		req.finished <-= 1;
	req.responded = 1;
	pick m := rm {
	Error =>
		if(m.ename == Einterrupted){
			if(!req.flushing)
				complain("interrupted reply but no flush "+req.m.text());
			return 0;
		}
	}
	return 1;
}

addflush(req: ref Req)
{
	o := req.oldreq;
	for(r := o.flushes; r != nil; r = r.nextflush)
		if(r.nextflush == nil)
			break;
	if(r == nil){
		o.flushes = req;
		req.flushready = nil;
	}else{
		r.nextflush = req;
		req.flushready = chan of int;
	}
	o.flushing = 1;
}

# remove req (a flush request) from the list of flushes pending
# for req.oldreq. if it was at the head of the list, then give
# the next req a go.
delflush(req: ref Req)
{
	oldreq := req.oldreq;
	prev: ref Req;
	for(r := oldreq.flushes; r != nil; r = r.nextflush){
		if(r == req)
			break;
		prev = r;
	}
	if(prev == nil){
		oldreq.flushes = r.nextflush;
		if(oldreq.flushes != nil)
			oldreq.flushes.flushready <-= 1;
	}else
		prev.nextflush = r.nextflush;
	r.nextflush = nil;
}

flushreq(req: ref Req, reply: chan of ref Styx->Rmsg)
{
	o := req.oldreq;
	# if we're queued up, wait our turn.
	if(req.flushready != nil)
		<-req.flushready;
	rc := chan of int;
	alt{
	o.flushc <-= (req.m.tag, rc) =>
		<-rc;
		reply <-= ref Rmsg.Flush(req.m.tag);
		# old request must have responded before sending on rc,
		# but be defensive because it's easy to forget.
		if(!o.responded){
			complain("flushed request not responded to: "+o.m.text());
			o.responded = 1;		# race but better than nothing.
		}
	(nil, nrc)  := <-req.flushc =>
		reply <-= ref Rmsg.Error(req.m.tag, Einterrupted);
		nrc <-= 1;
	<-o.finished =>
		o.finished <-= 1;
		reply <-= ref Rmsg.Flush(req.m.tag);
	}
}

complain(e: string)
{
	sys->fprint(sys->fildes(2), "styxflush: warning: %s\n", e);
}
