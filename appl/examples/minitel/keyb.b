#
# Copyright © 1998 Vita Nuova Limited.  All rights reserved.
#

# special keyboard operations
Extend,				# enable cursor and editing keys and control chars
C0keys,				# cursor keys send BS,HT,LF and VT
Invert				# case inversion
	: con 1 << iota;

Keyb: adt {
	m:		ref Module;			# common attributes
	in:		chan of ref Event;

	cmd:		chan of string;			# from Tk (keypresses and focus)
	spec:	int;					# special keyboard extensions

	init:		fn(k: self ref Keyb, toplevel: ref Tk->Toplevel);
	reset:	fn(k: self ref Keyb);
	run:		fn(k: self ref Keyb);
	quit:		fn(k: self ref Keyb);
	map:		fn(k: self ref Keyb, key:int): array of byte;
};

Keyb.init(k: self ref Keyb, toplevel: ref Tk->Toplevel)
{
	k.in = chan of ref Event;
	k.cmd = chan of string;
	tk->namechan(toplevel, k.cmd, "keyb");		# Tk -> keyboard
	k.reset();
}

Keyb.reset(k: self ref Keyb)
{
	k.m = ref Module(Pmodem|Psocket, 0);
}

ask(in: chan of string, out: chan of string)
{
	keys: string;

	T.mode = Videotex;
	S.setmode(Videotex);
#	clear(S);
	prompt: con "Numéroter: ";
	number := M.lastdialstr;
	S.msg(prompt);

Input:
	for(;;) {
		n := len prompt + len number;
		# guard length must be > len prompt
		if (n > 30)
			n -= 30;
		else
			n = 0;
		S.msg(prompt + number[n:]);
		keys = <- in;
		if (keys == nil)
			return;

		keys = canoncmd(keys);

		case keys {
		"connect"  or "send" =>
			break Input;
		"correct" =>
			if(len number > 0)
				number = number[0: len number -1];
		"cancel" =>
			number = "";
			break Input;
		"repeat" or "index" or "guide" or "next" or "previous" =>
			;
		* =>
			number += keys;
		}
	}

	S.msg(nil);
	for (;;) alt {
	out <- = number =>
		return;
	keys = <- in =>
		if (keys == nil)
			return;
	}
}

Keyb.run(k: self ref Keyb)
{
	dontask := chan of string;
	askchan := dontask;
	askkeys := chan of string;
Runloop:
	for(;;){
		alt {
		ev := <- k.in =>
			pick e := ev {
			Equit =>
				break Runloop;
			Eproto =>
				case e.cmd {
				Creset =>
					k.reset();
				Cproto =>
					case e.a0 {
					START =>
						case e.a1 {
						LOWERCASE =>
							k.spec |= Invert;
						}
					STOP =>
						case e.a1 {
						LOWERCASE =>
							k.spec &= ~Invert;
						}
					}
				* => break;
				}
			}
		cmd := <- k.cmd =>
			if(debug['k'] > 0) {
				fprint(stderr, "Tk %s\n", cmd);
			}
			(n, args) := sys->tokenize(cmd, " ");
			if(n >0)
				case hd args {
				"key" =>
					(key, nil) := toint(hd tl args, 16);
					if(askchan != dontask) {
						s := minikey(key);
						if (s == nil)
							s[0] = key;
						askkeys <-= s;
						break;
					}
					keys := k.map(key);
					if(keys != nil) {
						send(ref Event.Edata(k.m.path, Mkeyb, keys));
					}
				"skey" =>		# minitel key hit (soft key)
					if(hd tl args == "Exit") {
						if(askchan != dontask) {
							askchan = dontask;
							askkeys <-= nil;
						}
						if(T.state == Online || T.state == Connecting) {
							seq := keyseq("connect");
							if(seq != nil) {
								send(ref Event.Edata(k.m.path, Mkeyb, seq));
								send(ref Event.Edata(k.m.path, Mkeyb, seq));
							}
							send(ref Event.Eproto(Pmodem, Mkeyb, Cdisconnect, "", 0,0,0));
						}
						send(ref Event.Equit(0, 0));
						break;
					} 
					if(askchan != dontask) {
						askkeys <-= hd tl args;
						break;
					}
					case hd tl args {
					"Connect" =>
						case T.state {
						Local =>
							if(M.connect == Network)
								send(ref Event.Eproto(Pmodem, Mkeyb, Cconnect, "", 0,0,0));
							else {
								askchan = chan of string;
								spawn ask(askkeys, askchan);
							}
						Connecting =>
							send(ref Event.Eproto(Pmodem, Mkeyb, Cdisconnect, "", 0,0,0));
						Online =>
							seq := keyseq("connect");
							if(seq != nil)
								send(ref Event.Edata(k.m.path, Mkeyb, seq));
						}
					* =>
						seq := keyseq(hd tl args);
						if(seq != nil)
							send(ref Event.Edata(k.m.path, Mkeyb, seq));
					}
				"click" =>		# fetch a word from the display
					x := int hd tl args;
					y := int hd tl tl args;
					word := disp->GetWord(Point(x, y));
					if(word != nil) {
						if (askchan != dontask) {
							askkeys <- = word;
							break;
						}
						if (T.state == Local) {
							if (canoncmd(word) == "connect") {
								if(M.connect == Network)
									send(ref Event.Eproto(Pmodem, Mkeyb, Cconnect, "", 0,0,0));
								else {
									askchan = chan of string;
									spawn ask(askkeys, askchan);
								}
								break;
							}
						}
						seq := keyseq(word);
						if(seq != nil)
							send(ref Event.Edata(k.m.path, Mkeyb, seq));
						else {
							send(ref Event.Edata(k.m.path, Mkeyb, array of byte word ));
							send(ref Event.Edata(k.m.path, Mkeyb, keyseq("send")));
						}
					}		
						
				}
		dialstr := <-askchan =>
			askchan = dontask;
			if(dialstr != nil) {
				M.dialstr = dialstr;
				send(ref Event.Eproto(Pmodem, Mkeyb, Cconnect, "", 0,0,0));
			}
		}
	}
	send(nil);	
}


# Perform mode specific key translation
# returns nil on invalid keypress,
Keyb.map(nil: self ref Keyb, key: int): array of byte
{
	# hardware to minitel keyboard mapping
	cmd := minikey(key);
	if (cmd != nil) {
		seq := keyseq(cmd);
		if(seq != nil)
			return seq;
	}

	# alphabetic (with case mapping)
	case T.mode {
	Videotex =>
		if(key >= 'A' && key <= 'Z')
			return array [] of { byte ('a' + (key - 'A'))};
		if(key >= 'a' && key <= 'z')
			return array [] of {byte ('A' + (key - 'a'))};
	Mixed or Ascii =>
		if(key >= 'A' && key <= 'Z' || key >= 'a' && key <= 'z')
			return array [] of {byte key};
	};

	# Numeric
	if(key >= '0' && key <= '9')
		return array [] of {byte key};

	# Control-A -> Control-Z, Esc - columns 0 and 1
	if(key >= 16r00 && key <=16r1f)
		case T.mode {
		Videotex =>
			return nil;
		Mixed or Ascii =>
			return array [] of {byte key};
		}

	# miscellaneous key mapping
	case key {
	16r20	=> ;										# space
	16ra3	=> return array [] of { byte 16r19, byte 16r23 };		# pound
	'!' or '"' or '#' or '$'
	or '%' or '&' or '\'' or '(' or ')' 
	or '*' or '+' or ',' or '-'
	or '.' or ':' or ';' or '<'
	or '=' or '>' or '?' or '@'  => ;
	KF13 =>	# request for error correction - usually Fnct M + C
		if((M.spec&Ecp) == 0 && T.state == Online && T.connect == Direct) {
fprint(stderr, "requesting Ecp\n");
			return array [] of { byte SEP, byte 16r4a };
		}
		return nil;
	*		=> return nil;
	}
	return array [] of {byte key};
}

Keyb.quit(k: self ref Keyb)
{
	if(k==nil);
}

canoncmd(s : string) : string
{
	s = tolower(s);
	case s {
	"connect" or "cx/fin" or
	"connexion" or "fin"		=> return "connect";
	"send" or "envoi" 		=> return "send";
	"repeat" or "repetition"	=> return "repeat";
	"index" or "sommaire" or "somm"
						=> return "index";
	"guide"				=> return "guide";
	"correct" or "correction"	=> return "correct";
	"cancel" or "annulation" or "annul" or "annu"
						=> return "cancel";
	"next" or "suite"		=> return "next";
	"previous" or "retour" or "retou"
						=> return "previous";
	}
	return s;
}

# map softkey names to the appropriate byte sequences
keyseq(skey: string): array of byte
{
	b2 := 0;
	asterisk := 0;
	if(skey == nil || len skey == 0)
		return nil;
	if(skey[0] == '*') {
		asterisk = 1;
		skey = skey[1:];
	}
	skey = canoncmd(skey);
	case skey {
	"connect" 	=> b2 = 16r49;
	"send"  		=> b2 = 16r41;
	"repeat"		=> b2 = 16r43;
	"index"		=> b2 = 16r46;
	"guide"		=> b2 = 16r44;
	"correct"		=> b2 = 16r47;
	"cancel"		=> b2 = 16r45;
	"next"		=> b2 = 16r48;
	"previous" 	=> b2 = 16r42;
	}
	if(b2) {
		if(asterisk)
			return array [] of { byte '*', byte SEP, byte b2};
		else
			return array [] of { byte SEP, byte b2};
	} else
		return nil;
}

# map hardware or software keyboard presses to minitel functions
minikey(key: int): string
{
	case key {
	Kup or KupPC =>
		return"previous";
	Kdown or KdownPC =>
		return "next";
	Kenter =>
		return "send";
	Kback =>
		return "correct";
	Kesc =>
		return "cancel";
	KF1 =>
		return "guide";
	KF2 =>
		return "connect";
	KF3 =>
		return "repeat";
	KF4 =>
		return "index";
	* =>
		return nil;
	}
}