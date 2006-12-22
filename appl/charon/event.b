implement Events;

include "common.m";

sys: Sys;
url: Url;
	Parsedurl: import url;

archan : chan of (ref Event, int, int);

init(ev : chan of ref Event)
{
	sys = load Sys Sys->PATH;
	url = load Url Url->PATH;
	if (url != nil)
		url->init();
	evchan = chan of ref Event;
	archan = chan of (ref Event, int ,int);
	spawn eventfilter(evchan, ev);
}

timer(go, tick : chan of int)
{
	go <-= sys->pctl(0, nil);
	for(;;) {
		ms := <- go;
		sys->sleep(ms);
		tick <-= 1;
	}
}

# Handle mouse filtering and auto-repeating.
# If we are waiting to send to Charon then accept events whilst they are
# compatible with the pending event (eg. only keep most recent mouse move).
# Once we have a recv event that isn't compatible with the pending send event
# stop accepting events until the pending one has been sent.
# Auto-repeat events are discarded if they cannot be sent or combined with the pending one.
#
eventfilter(fromc, toc : chan of ref Event)
{
	timergo := chan of int;
	timertick := chan of int;
	timeractive := 0;
	spawn timer(timergo, timertick);
	timerpid := <-timergo;

	pendingev : ref Event;
	bufferedev : ref Event;
	dummyin := chan of ref Event;
	dummyout := chan of ref Event;
	inchan := fromc;
	outchan := dummyout;

	arev : ref Event;
	aridlems, arms : int;

	for (;;) alt {
	ev := <- inchan =>
		outchan = toc;
		if (pendingev == nil) 
			pendingev = ev;
		else {
			# an event is pending - see if we can combine/replace it
			replace := evreplace(pendingev, ev);
			if (replace != nil)
				pendingev = replace;
			else
				bufferedev = ev;
		}
		if (bufferedev != nil)
			inchan = dummyin;

	outchan <- = pendingev =>
		pendingev = bufferedev;
		bufferedev = nil;
		inchan = fromc;
		if (pendingev == nil)
			outchan = dummyout;

	(arev, aridlems, arms) = <- archan =>
		if (arev == nil) {
			if(timeractive) {
				# kill off old timer action so we don't get nasty
				# holdovers from past autorepeats.
				kill(timerpid);
				spawn timer(timergo, timertick);
				timerpid = <-timergo;
				timeractive = 0;
			}
		} else if (!timeractive) {
			timeractive = 1;
			timergo <-= aridlems;
		}

	<- timertick =>
		timeractive = 0;
		if (arev != nil) {
			if (pendingev == nil) {
				pendingev = arev;
			} else if (bufferedev == nil) {
				replace := evreplace(pendingev, arev);
				if (replace != nil)
					pendingev = replace;
				else
					bufferedev = arev;
			} else {
				# try and combine with the buffered event
				replace := evreplace(bufferedev, arev);
				if (replace != nil)
					bufferedev = replace;
			} # else: discard auto-repeat event

			if (bufferedev != nil)
				inchan = dummyin;

			# kick-start sends (we always have something to send)
			outchan = toc;
			timergo <- = arms;
			timeractive = 1;
		}
	}
}

evreplace(oldev, newev : ref Event) : ref Event
{
	pick n := newev {
	Emouse =>
		pick o := oldev {
		Emouse =>
			if (n.mtype == o.mtype && (n.mtype == Mmove || n.mtype == Mldrag || n.mtype == Mmdrag || n.mtype == Mrdrag))
				return newev;
		}
	Equit =>
		# always takes precedence
		return newev;
	Ego =>
		pick o := oldev {
		Ego =>
			if (n.target == o.target)
				return newev;
		}
	Escroll =>
		pick o := oldev {
		Escroll =>
			if (n.frameid == o.frameid)
				return newev;
		}
	Escrollr =>
		pick o := oldev {
		Escrollr =>
			if (n.frameid == o.frameid)
				return newev;
		}
	Esettext =>
		pick o := oldev {
		Esettext =>
			if (n.frameid == o.frameid)
				return newev;
		}
	Edismisspopup =>
		if (tagof oldev == tagof Event.Edismisspopup)
			return newev;
	* =>
		return nil;
	}
	return nil;
}

autorepeat(ev : ref Event, idlems, ms : int)
{
	archan <- = (ev, idlems, ms);
}

Event.tostring(ev: self ref Event) : string
{
	s := "?";
	pick e := ev {
		Ekey =>
			t : string;
			case e.keychar {
			' ' =>	 t = "<SP>";
			'\t' => t = "<TAB>";
			'\n' => t = "<NL>";
			'\r' => t = "<CR>";
			'\b' => t = "<BS>";
			16r7F => t = "<DEL>";
			Kup => t = "<UP>";
			Kdown => t = "<DOWN>";
			Khome => t = "<HOME>";
			Kleft => t = "<LEFT>";
			Kright => t = "<RIGHT>";
			Kend => t = "<END>";
			* => t = sys->sprint("%c", e.keychar);
			}
			s = sys->sprint("key %d = %s", e.keychar, t);
		Emouse =>
			t := "?";
			case e.mtype {
			Mmove => t = "move";
			Mlbuttondown => t = "lbuttondown";
			Mlbuttonup => t = "lbuttonup";
			Mldrag => t = "ldrag";
			Mmbuttondown => t = "mbuttondown";
			Mmbuttonup => t = "mbuttonup";
			Mmdrag => t = "mdrag";
			Mrbuttondown => t = "rbuttondown";
			Mrbuttonup => t = "rbuttonup";
			Mrdrag => t = "rdrag";
			}
			s = sys->sprint("mouse (%d,%d) %s", e.p.x, e.p.y, t);
		Emove =>
			s = sys->sprint("move (%d,%d)", e.p.x, e.p.y);
		Ereshape =>
			s = sys->sprint("reshape (%d,%d) (%d,%d)", e.r.min.x, e.r.min.y, e.r.max.x, e.r.max.y);
		Equit =>
			s = "quit";
		Estop =>
			s = "stop";
		Eback =>
			s = "back";
		Efwd =>
			s = "fwd";
		Eform =>
			case e.ftype {
			EFsubmit => s = "form submit";
			EFreset => s = "form reset";
			}
		Eformfield =>
			case e.fftype {
			EFFblur => s = "formfield blur";
			EFFfocus => s = "formfield focus";
			EFFclick => s = "formfield click";
			EFFselect => s = "formfield select";
			EFFredraw => s = "formfield redraw";
			}
		Ego =>
			s = "go(";
			case e.gtype {
			EGlocation or
			EGnormal or
			EGreplace => s += e.url;
			EGreload => s += "RELOAD";
			EGforward => s += "FORWARD";
			EGback => s += "BACK";
			EGdelta => s += "HISTORY[" + string e.delta + "]";
			}
			s += ", " + e.target + ")";
		Esubmit =>
			if(e.subkind == CharonUtils->HGet)
				s = "GET";
			else
				s = "POST";
			s = "submit(" + s;
			s += ", " + e.action.tostring();
			s += ", " + e.target + ")";
		Escroll =>
			s = "scroll(" + string e.frameid + ", (" + string e.pt.x + ", " + string e.pt.y + "))";
		Escrollr =>
			s = "scrollr(" + string e.frameid + ", (" + string e.pt.x + ", " + string e.pt.y + "))";
		Esettext =>
			s = "settext(frameid=" + string e.frameid + ", text=" + e.text + ")";
		Elostfocus =>
			s = "lostfocus";
		Edismisspopup =>
			s = "dismisspopup";
	}
	return s;
}

kill(pid: int)
{
	sys->fprint(sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE), "kill");
}
