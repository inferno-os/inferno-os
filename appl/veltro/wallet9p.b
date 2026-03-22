implement Wallet9p;

#
# wallet9p - Wallet Filesystem Service
#
# 9P server exposing cryptocurrency and fiat wallet operations.
# Uses factotum for private key storage, budget enforcement for safety.
#
# Filesystem layout:
#   /n/wallet/
#       ctl          rw: global config ("limit <amount>", "default <name>")
#       accounts     r:  newline-separated account names
#       new          rw: write "eth base myaccount" → read account name
#       {name}/          per-account directory
#           address  r:  public address
#           balance  r:  balance (queries chain/API)
#           chain    rw: chain name
#           sign     rw: write hex hash → read hex signature
#           pay      rw: write "amount recipient" → read txhash
#           ctl      rw: per-account config
#           history  r:  recent transactions (JSON lines)
#
# Usage:
#   wallet9p [-D] [-m mountpt]
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

include "factotum.m";
	factotum: Factotum;

include "keyring.m";
	kr: Keyring;

include "ethcrypto.m";
	ethcrypto: Ethcrypto;

include "wallet.m";
	wallet: Wallet;

include "ethrpc.m";
	ethrpc: Ethrpc;

Wallet9p: module {
	init: fn(nil: ref Draw->Context, nil: list of string);
};

# File types (low byte of qid path)
Qroot:     con 0;
Qctl:      con 1;
Qaccounts: con 2;
Qnew:      con 3;
Qpending:  con 4;
# Per-account files start at 16
Qacctdir:  con 16;
Qaddress:  con 17;
Qbalance:  con 18;
Qchain:    con 19;
Qsign:     con 20;
Qpay:      con 21;
Qacctctl:  con 22;
Qhistory:  con 23;

NACCTFILES: con 7;	# files per account dir

# Account state
AcctState: adt {
	acct:       ref Wallet->Account;
	signresult: array of byte;	# pending sign result
	history:    list of string;	# recent transactions
	requireapproval: int;		# 1 = require GUI approval for payments
};

# Pending payment (awaiting approval)
PendingPay: adt {
	id:        int;
	acct:      string;
	amount:    string;
	recipient: string;
	token:     string;	# "eth" or "usdc"
	agent:     string;	# agent name (if from tool)
	result:    string;	# nil = pending, "approved:txhash" or "denied"
};

pendingpays: list of ref PendingPay;
nextpendingid := 1;

stderr: ref Sys->FD;
user: string;
vers: int;

# Account registry
accounts: list of ref AcctState;

# Global config
defaultacct: string;
globalctl: string;

# Per-fid state for new file
NewState: adt {
	fid:    int;
	result: string;
};
newstates: list of ref NewState;

# Per-fid state for sign file
SignState: adt {
	fid:    int;
	acct:   string;
	result: array of byte;
};
signstates: list of ref SignState;

MKPATH(id, filetype: int): big
{
	return big ((id << 8) | filetype);
}

ACCTID(path: big): int
{
	return (int path >> 8) & 16rFFFFFF;
}

FTYPE(path: big): int
{
	return int path & 16rFF;
}

stderr2(s: string)
{
	sys->fprint(stderr, "wallet9p: %s\n", s);
}

nomod(s: string)
{
	sys->fprint(stderr, "wallet9p: can't load %s: %r\n", s);
	raise "fail:load";
}

# Find account by name
findacct(name: string): ref AcctState
{
	for(l := accounts; l != nil; l = tl l) {
		as := hd l;
		if(as.acct.name == name)
			return as;
	}
	return nil;
}

# Find account by ID (index in list)
findacctbyid(id: int): ref AcctState
{
	i := 0;
	for(l := accounts; l != nil; l = tl l) {
		if(i == id)
			return hd l;
		i++;
	}
	return nil;
}

# Get account ID (index) from name
acctidbyname(name: string): int
{
	i := 0;
	for(l := accounts; l != nil; l = tl l) {
		if((hd l).acct.name == name)
			return i;
		i++;
	}
	return -1;
}

# Number of accounts
naccts(): int
{
	n := 0;
	for(l := accounts; l != nil; l = tl l)
		n++;
	return n;
}

# Per-fid new state management
getnewstate(fid: int): ref NewState
{
	for(l := newstates; l != nil; l = tl l)
		if((hd l).fid == fid)
			return hd l;
	return nil;
}

setnewstate(fid: int, result: string)
{
	ns := getnewstate(fid);
	if(ns != nil) {
		ns.result = result;
		return;
	}
	newstates = ref NewState(fid, result) :: newstates;
}

delnewstate(fid: int)
{
	nl: list of ref NewState;
	for(l := newstates; l != nil; l = tl l)
		if((hd l).fid != fid)
			nl = hd l :: nl;
	newstates = nl;
}

# Per-fid sign state management
getsignstate(fid: int, acctname: string): ref SignState
{
	for(l := signstates; l != nil; l = tl l)
		if((hd l).fid == fid && (hd l).acct == acctname)
			return hd l;
	return nil;
}

setsignstate(fid: int, acctname: string, result: array of byte)
{
	ss := getsignstate(fid, acctname);
	if(ss != nil) {
		ss.result = result;
		return;
	}
	signstates = ref SignState(fid, acctname, result) :: signstates;
}

delsignstate(fid: int)
{
	nl: list of ref SignState;
	for(l := signstates; l != nil; l = tl l)
		if((hd l).fid != fid)
			nl = hd l :: nl;
	signstates = nl;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	stderr = sys->fildes(2);

	styx = load Styx Styx->PATH;
	if(styx == nil) nomod(Styx->PATH);
	styx->init();

	styxservers = load Styxservers Styxservers->PATH;
	if(styxservers == nil) nomod(Styxservers->PATH);
	styxservers->init(styx);

	str = load String String->PATH;
	if(str == nil) nomod(String->PATH);

	kr = load Keyring Keyring->PATH;
	if(kr == nil) nomod(Keyring->PATH);

	factotum = load Factotum Factotum->PATH;
	if(factotum == nil) nomod(Factotum->PATH);
	factotum->init();

	ethcrypto = load Ethcrypto Ethcrypto->PATH;
	if(ethcrypto == nil) nomod(Ethcrypto->PATH);
	err := ethcrypto->init();
	if(err != nil) {
		sys->fprint(stderr, "wallet9p: ethcrypto init: %s\n", err);
		raise "fail:init";
	}

	wallet = load Wallet Wallet->PATH;
	if(wallet == nil) nomod(Wallet->PATH);
	err = wallet->init();
	if(err != nil) {
		sys->fprint(stderr, "wallet9p: wallet init: %s\n", err);
		raise "fail:init";
	}

	ethrpc = load Ethrpc Ethrpc->PATH;
	if(ethrpc == nil) nomod(Ethrpc->PATH);
	initnetworks();
	# Default to first network (Ethereum Sepolia)
	err = ethrpc->init(networks[0].rpcurl);
	if(err != nil) {
		sys->fprint(stderr, "wallet9p: ethrpc init: %s\n", err);
		raise "fail:init";
	}

	mountpt := "/n/wallet";
	debug := 0;

	arg := load Arg Arg->PATH;
	if(arg != nil) {
		arg->init(args);
		while((c := arg->opt()) != 0) {
			case c {
			'D' =>
				debug = 1;
			'm' =>
				mountpt = arg->earg();
			* =>
				sys->fprint(stderr, "Usage: wallet9p [-D] [-m mountpt]\n");
				raise "fail:usage";
			}
		}
	}

	user = readuser();

	# Restore accounts from factotum (persistence across restarts)
	restoreaccounts();

	# Start debounced sync thread
	initsyncthread();

	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);

	navops := chan of ref Navop;
	spawn navigator(navops);

	(tchan, srv) := Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	if(debug)
		styxservers->traceset(1);

	spawn serveloop(tchan, srv);

	# Ensure mount point exists
	(ok, nil) := sys->stat(mountpt);
	if(ok < 0) {
		fd := sys->create(mountpt, Sys->OREAD, Sys->DMDIR | 8r755);
		if(fd != nil)
			fd = nil;
	}

	if(sys->mount(fds[1], nil, mountpt, Sys->MREPL|Sys->MCREATE, nil) < 0) {
		sys->fprint(stderr, "wallet9p: mount %s: %r\n", mountpt);
		raise "fail:mount";
	}
}

readuser(): string
{
	fd := sys->open("/dev/user", Sys->OREAD);
	if(fd == nil)
		return "inferno";
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "inferno";
	return string buf[0:n];
}

# --- Serve loop ---

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver)
{
	while((gm := <-tchan) != nil) {
		pick m := gm {
		Readerror =>
			return;

		Open =>
			c := srv.getfid(m.fid);
			if(c != nil) {
				ft := FTYPE(c.path);
				if(ft == Qnew)
					setnewstate(m.fid, "");
			}
			srv.default(gm);

		Read =>
			doread(srv, m);

		Write =>
			dowrite(srv, m);

		Clunk =>
			delnewstate(m.fid);
			delsignstate(m.fid);
			srv.default(gm);

		* =>
			srv.default(gm);
		}
	}
}

doread(srv: ref Styxserver, m: ref Tmsg.Read)
{
	(c, err) := srv.canread(m);
	if(c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, err));
		return;
	}
	if(c.qtype & Sys->QTDIR) {
		srv.read(m);
		return;
	}

	ft := FTYPE(c.path);
	aid := ACCTID(c.path);

	case ft {
	Qctl =>
		net := getnetwork();
		ctlinfo := "network " + net.name + "\n";
		if(defaultacct != "")
			ctlinfo += "default " + defaultacct + "\n";
		readstr(srv, m, ctlinfo);

	Qaccounts =>
		s := "";
		for(l := accounts; l != nil; l = tl l) {
			s += (hd l).acct.name + "\n";
		}
		readstr(srv, m, s);

	Qnew =>
		ns := getnewstate(m.fid);
		if(ns != nil && ns.result != "")
			readstr(srv, m, ns.result + "\n");
		else
			readstr(srv, m, "");

	Qpending =>
		s := "";
		for(pl := pendingpays; pl != nil; pl = tl pl) {
			pp := hd pl;
			if(pp.result == nil)
				s += sys->sprint("%d %s %s %s %s %s\n",
					pp.id, pp.acct, pp.token, pp.amount,
					pp.recipient, pp.agent);
		}
		if(s == "")
			s = "(none)\n";
		readstr(srv, m, s);

	Qaddress =>
		as := findacctbyid(aid);
		if(as == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			return;
		}
		readstr(srv, m, as.acct.address + "\n");

	Qbalance =>
		as := findacctbyid(aid);
		if(as == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			return;
		}
		bal := querybalance(as);
		readstr(srv, m, bal + "\n");

	Qchain =>
		as := findacctbyid(aid);
		if(as == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			return;
		}
		readstr(srv, m, as.acct.chain + "\n");

	Qsign =>
		as := findacctbyid(aid);
		if(as == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			return;
		}
		ss := getsignstate(m.fid, as.acct.name);
		if(ss != nil && ss.result != nil)
			readstr(srv, m, ethcrypto->hexencode(ss.result) + "\n");
		else
			readstr(srv, m, "");

	Qpay =>
		as := findacctbyid(aid);
		if(as == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			return;
		}
		if(as.signresult != nil)
			readstr(srv, m, string as.signresult + "\n");
		else
			readstr(srv, m, "");

	Qacctctl =>
		as := findacctbyid(aid);
		if(as == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			return;
		}
		# Return budget info if set
		budget := wallet->checkbudget(as.acct, big 0);
		if(budget == nil)
			readstr(srv, m, "no budget\n");
		else
			readstr(srv, m, budget + "\n");

	Qhistory =>
		as := findacctbyid(aid);
		if(as == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			return;
		}
		s := "";
		for(h := as.history; h != nil; h = tl h)
			s += hd h + "\n";
		readstr(srv, m, s);

	* =>
		srv.default(m);
	}
}

dowrite(srv: ref Styxserver, m: ref Tmsg.Write)
{
	(c, werr) := srv.canwrite(m);
	if(c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, werr));
		return;
	}

	ft := FTYPE(c.path);
	aid := ACCTID(c.path);
	data := string m.data;

	case ft {
	Qctl =>
		# Global control commands
		data = str->take(data, "^\n\r");
		(ntoks, toks) := sys->tokenize(data, " \t");
		if(ntoks < 1) {
			srv.reply(ref Rmsg.Error(m.tag, Ebadarg));
			return;
		}
		cmd := hd toks;
		if(cmd == "default" && ntoks >= 2) {
			defaultacct = hd tl toks;
			globalctl = "default " + defaultacct + "\n";
		} else if(cmd == "rpc" && ntoks >= 2) {
			ethrpc->setrpc(hd tl toks);
		} else if(cmd == "network" && ntoks >= 2) {
			# Rejoin remaining tokens as network name (may have spaces)
			nname := "";
			for(nt := tl toks; nt != nil; nt = tl nt) {
				if(nname != "")
					nname += " ";
				nname += hd nt;
			}
			setnetwork(nname);
		} else if(cmd == "approve" && ntoks >= 2) {
			pid := int hd tl toks;
			err := approvepending(pid);
			if(err != nil) {
				srv.reply(ref Rmsg.Error(m.tag, err));
				return;
			}
		} else if(cmd == "deny" && ntoks >= 2) {
			pid := int hd tl toks;
			err := denypending(pid);
			if(err != nil) {
				srv.reply(ref Rmsg.Error(m.tag, err));
				return;
			}
		} else {
			srv.reply(ref Rmsg.Error(m.tag, "unknown ctl command: " + cmd));
			return;
		}
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qnew =>
		# Create new account: "eth base myaccount" or "import eth base myaccount hexkey"
		data = str->take(data, "^\n\r");
		(ntoks, toks) := sys->tokenize(data, " \t");

		if(ntoks >= 1 && hd toks == "import" && ntoks >= 5) {
			# import eth base myaccount hexkey
			toks = tl toks;
			accttype := parsetype(hd toks); toks = tl toks;
			chain := hd toks; toks = tl toks;
			name := hd toks; toks = tl toks;
			hexkey := hd toks;
			privkey := ethcrypto->hexdecode(hexkey);
			if(privkey == nil) {
				srv.reply(ref Rmsg.Error(m.tag, "invalid hex key"));
				return;
			}
			(acct, err) := wallet->importaccount(name, accttype, chain, privkey);
			zeroarray(privkey);
			if(err != nil) {
				srv.reply(ref Rmsg.Error(m.tag, err));
				return;
			}
			as := ref AcctState(acct, nil, nil, 0);
			accounts = as :: accounts;
			setnewstate(m.fid, name);
			syncfactotum();
			vers++;
		} else if(ntoks >= 3) {
			# eth base myaccount
			accttype := parsetype(hd toks); toks = tl toks;
			chain := hd toks; toks = tl toks;
			name := hd toks;
			if(findacct(name) != nil) {
				srv.reply(ref Rmsg.Error(m.tag, "account exists: " + name));
				return;
			}
			(acct, err) := wallet->createaccount(name, accttype, chain);
			if(err != nil) {
				srv.reply(ref Rmsg.Error(m.tag, err));
				return;
			}
			as := ref AcctState(acct, nil, nil, 0);
			accounts = as :: accounts;
			setnewstate(m.fid, name);
			syncfactotum();
			vers++;
		} else {
			srv.reply(ref Rmsg.Error(m.tag, "usage: type chain name"));
			return;
		}
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qchain =>
		as := findacctbyid(aid);
		if(as == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			return;
		}
		as.acct.chain = str->take(data, "^\n\r \t");
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qsign =>
		as := findacctbyid(aid);
		if(as == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			return;
		}
		# Write hex-encoded hash, get signature back on read
		hexhash := str->take(data, "^\n\r \t");
		hash := ethcrypto->hexdecode(hexhash);
		if(hash == nil || len hash != 32) {
			srv.reply(ref Rmsg.Error(m.tag, "sign: need 32-byte hash as hex"));
			return;
		}
		(sig, err) := wallet->signhash(as.acct, hash);
		if(err != nil) {
			srv.reply(ref Rmsg.Error(m.tag, "sign: " + err));
			return;
		}
		setsignstate(m.fid, as.acct.name, sig);
		srv.reply(ref Rmsg.Write(m.tag, len m.data));

	Qpay =>
		as := findacctbyid(aid);
		if(as == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			return;
		}
		# Parse: "amount recipient" (ETH) or "usdc amount recipient" (ERC-20)
		paydata := str->take(data, "^\n\r");
		(ntoks, paytoks) := sys->tokenize(paydata, " \t");
		if(ntoks < 2) {
			srv.reply(ref Rmsg.Error(m.tag, "usage: amount recipient OR usdc amount recipient"));
			return;
		}
		payamt: string;
		payrecip: string;
		paytoken := "eth";
		first := hd paytoks;
		if(first == "usdc" || first == "USDC") {
			if(ntoks < 3) {
				srv.reply(ref Rmsg.Error(m.tag, "usage: usdc amount recipient"));
				return;
			}
			payamt = hd tl paytoks;
			payrecip = hd tl tl paytoks;
			paytoken = "usdc";
		} else {
			payamt = first;
			payrecip = hd tl paytoks;
		}

		# Check if approval is required for this account
		if(as.requireapproval) {
			pp := ref PendingPay(nextpendingid++, as.acct.name,
				payamt, payrecip, paytoken, "agent", nil);
			pendingpays = pp :: pendingpays;
			as.signresult = array of byte ("pending:" + string pp.id);
			srv.reply(ref Rmsg.Write(m.tag, len m.data));
		} else {
			# Execute immediately
			txhash: string;
			payerr: string;
			if(paytoken == "usdc")
				(txhash, payerr) = executeerc20(as, payamt, payrecip);
			else
				(txhash, payerr) = executepayment(as, payamt, payrecip);
			if(payerr != nil) {
				srv.reply(ref Rmsg.Error(m.tag, "pay: " + payerr));
				return;
			}
			# Store result for read-back and add to history
			as.signresult = array of byte txhash;
			as.history = ("pay " + payamt + " " + payrecip + " " + txhash) :: as.history;
			srv.reply(ref Rmsg.Write(m.tag, len m.data));
		}

	Qacctctl =>
		as := findacctbyid(aid);
		if(as == nil) {
			srv.reply(ref Rmsg.Error(m.tag, Enotfound));
			return;
		}
		# Parse budget commands: "budget maxpertx maxpersess currency"
		data = str->take(data, "^\n\r");
		(ntoks, toks) := sys->tokenize(data, " \t");
		if(ntoks >= 1 && hd toks == "budget" && ntoks >= 4) {
			toks = tl toks;
			maxpertx := big hd toks; toks = tl toks;
			maxpersess := big hd toks; toks = tl toks;
			currency := hd toks;
			b := ref Wallet->Budget(maxpertx, maxpersess, big 0, currency);
			wallet->setbudget(as.acct, b);
			srv.reply(ref Rmsg.Write(m.tag, len m.data));
		} else if(ntoks >= 1 && hd toks == "requireapproval") {
			val := 1;
			if(ntoks >= 2 && hd tl toks == "off")
				val = 0;
			as.requireapproval = val;
			srv.reply(ref Rmsg.Write(m.tag, len m.data));
		} else {
			srv.reply(ref Rmsg.Error(m.tag, "usage: budget maxpertx maxpersess currency | requireapproval [off]"));
		}

	* =>
		srv.default(m);
	}
}

parsetype(s: string): int
{
	if(s == "eth" || s == "ethereum")
		return Wallet->ACCT_ETH;
	if(s == "sol" || s == "solana")
		return Wallet->ACCT_SOL;
	if(s == "stripe" || s == "fiat")
		return Wallet->ACCT_STRIPE;
	return Wallet->ACCT_ETH;
}

# --- Pending payment approval/denial ---

approvepending(id: int): string
{
	for(pl := pendingpays; pl != nil; pl = tl pl) {
		pp := hd pl;
		if(pp.id == id && pp.result == nil) {
			# Find the account and execute
			as := findacct(pp.acct);
			if(as == nil)
				return "account not found: " + pp.acct;
			txhash: string;
			payerr: string;
			if(pp.token == "usdc")
				(txhash, payerr) = executeerc20(as, pp.amount, pp.recipient);
			else
				(txhash, payerr) = executepayment(as, pp.amount, pp.recipient);
			if(payerr != nil) {
				pp.result = "error:" + payerr;
				return "pay: " + payerr;
			}
			pp.result = "approved:" + txhash;
			as.signresult = array of byte txhash;
			as.history = ("pay " + pp.amount + " " + pp.recipient + " " + txhash) :: as.history;
			return nil;
		}
	}
	return "pending payment not found: " + string id;
}

denypending(id: int): string
{
	for(pl := pendingpays; pl != nil; pl = tl pl) {
		pp := hd pl;
		if(pp.id == id && pp.result == nil) {
			pp.result = "denied";
			return nil;
		}
	}
	return "pending payment not found: " + string id;
}

readstr(srv: ref Styxserver, m: ref Tmsg.Read, s: string)
{
	data := array of byte s;
	if(m.offset >= big len data) {
		srv.reply(ref Rmsg.Read(m.tag, nil));
		return;
	}
	off := int m.offset;
	end := off + m.count;
	if(end > len data)
		end = len data;
	srv.reply(ref Rmsg.Read(m.tag, data[off:end]));
}

min(a, b: int): int
{
	if(a < b) return a;
	return b;
}

zeroarray(a: array of byte)
{
	if(a == nil)
		return;
	for(i := 0; i < len a; i++)
		a[i] = byte 0;
}

# --- Debounced factotum sync ---
# Coalesces rapid sync requests (e.g. batch account imports)
# to avoid triggering expensive PAK handshake for each operation.

syncdebouncech: chan of int;

initsyncthread()
{
	syncdebouncech = chan of int;
	spawn syncdebouncethread();
}

syncfactotum()
{
	# Signal the debounce thread (non-blocking)
	if(syncdebouncech != nil)
		alt {
		syncdebouncech <-= 1 => ;
		* => ;
		}
}

syncdebouncethread()
{
	DEBOUNCE_MS: con 2000;	# wait 2 seconds for more syncs before committing
	for(;;) {
		<-syncdebouncech;
		# Got a sync request — wait for quiet period
		for(;;) {
			expired := 0;
			timer := chan of int;
			spawn synctimeout(timer, DEBOUNCE_MS);
			alt {
			<-syncdebouncech =>
				;	# another sync arrived, reset timer
			<-timer =>
				expired = 1;
			}
			if(expired)
				break;
		}
		# Quiet period expired — do the actual sync
		dosyncfactotum();
	}
}

synctimeout(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	alt { ch <-= 1 => ; * => ; }
}

dosyncfactotum()
{
	fd := sys->open("/mnt/factotum/ctl", Sys->OWRITE);
	if(fd == nil) {
		sys->fprint(stderr, "wallet9p: sync: cannot open factotum ctl: %r\n");
		return;
	}
	b := array of byte "sync";
	n := sys->write(fd, b, len b);
	if(n < 0)
		sys->fprint(stderr, "wallet9p: sync failed: %r\n");
	else
		sys->fprint(stderr, "wallet9p: sync OK\n");
}

# --- Account restoration from factotum ---

restoreaccounts()
{
	saved := wallet->listaccounts();
	for(; saved != nil; saved = tl saved) {
		acct := hd saved;
		# Skip if already loaded
		if(findacct(acct.name) != nil)
			continue;
		# Load full account info (derives address from factotum key)
		(fullacct, err) := wallet->loadaccount(acct.name);
		if(err != nil || fullacct == nil)
			continue;
		as := ref AcctState(fullacct, nil, nil, 0);
		accounts = as :: accounts;
		sys->fprint(stderr, "wallet9p: restored account: %s (%s)\n",
			fullacct.name, fullacct.address);
	}
}

# --- Network configuration ---

NetworkConfig: adt {
	name:	string;	# display name
	rpcurl:	string;	# JSON-RPC endpoint
	usdc:	string;	# USDC contract address
	chainid: int;	# EIP-155 chain ID
};

networks: array of ref NetworkConfig;
activenetwork := 0;

initnetworks()
{
	networks = array[4] of ref NetworkConfig;
	networks[0] = ref NetworkConfig("Ethereum Sepolia",
		"https://ethereum-sepolia-rpc.publicnode.com",
		"0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
		11155111);
	networks[1] = ref NetworkConfig("Base Sepolia",
		"https://sepolia.base.org",
		"0x036CbD53842c5426634e7929541eC2318f3dCF7e",
		84532);
	networks[2] = ref NetworkConfig("Ethereum Mainnet",
		"https://eth.llamarpc.com",
		"0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
		1);
	networks[3] = ref NetworkConfig("Base",
		"https://mainnet.base.org",
		"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
		8453);
}

getnetwork(): ref NetworkConfig
{
	if(activenetwork >= 0 && activenetwork < len networks)
		return networks[activenetwork];
	return networks[0];
}

setnetwork(name: string)
{
	for(i := 0; i < len networks; i++) {
		if(networks[i].name == name) {
			activenetwork = i;
			ethrpc->setrpc(networks[i].rpcurl);
			sys->fprint(stderr, "wallet9p: network: %s (%s)\n",
				networks[i].name, networks[i].rpcurl);
			return;
		}
	}
	sys->fprint(stderr, "wallet9p: unknown network: %s\n", name);
}

# --- Balance query ---

querybalance(as: ref AcctState): string
{
	if(as.acct.accttype != Wallet->ACCT_ETH)
		return "0";

	addr := as.acct.address;
	if(addr == "" || addr == nil)
		return "0";

	net := getnetwork();

	# Try USDC token balance
	(tokbal, tokerr) := ethrpc->tokenbalance(net.usdc, addr);
	usdcstr := "0";
	if(tokerr != nil) {
		sys->fprint(stderr, "wallet9p: %s USDC balance: %s\n", net.name, tokerr);
		usdcstr = "?";
	} else if(tokbal != nil && tokbal != "0")
		usdcstr = ethrpc->weitotoken(tokbal, 6);	# USDC has 6 decimals

	# Also get native ETH balance
	(ethbal, etherr) := ethrpc->getbalance(addr);
	ethstr := "0";
	if(etherr != nil) {
		sys->fprint(stderr, "wallet9p: %s ETH balance: %s\n", net.name, etherr);
		ethstr = "?";
	} else if(ethbal != nil && ethbal != "0")
		ethstr = ethrpc->weitoeth(ethbal);

	# If both queries failed, report the network error
	if(tokerr != nil && etherr != nil)
		return net.name + ": RPC error";

	result := "";
	if(usdcstr != "0")
		result += usdcstr + " USDC";
	if(ethstr != "0") {
		if(result != "")
			result += ", ";
		result += ethstr + " ETH";
	}
	if(result == "")
		result = "0 USDC, 0 ETH";
	return result;
}

# --- Payment execution ---

executepayment(as: ref AcctState, amount: string, recipient: string): (string, string)
{
	if(as.acct.accttype != Wallet->ACCT_ETH)
		return (nil, "only ETH accounts can send transactions");

	addr := as.acct.address;
	if(addr == "" || addr == nil)
		return (nil, "account has no address");

	# Get nonce
	(nonce, nonceerr) := ethrpc->getnonce(addr);
	if(nonceerr != nil)
		return (nil, "nonce: " + nonceerr);

	# Parse amount as wei (decimal string)
	# For now, amount is in wei directly
	weiamt := amount;

	# Build EIP-155 transaction
	# Query network gas price, fall back to 1 gwei
	gasprice := big 1000000000;	# fallback: 1 gwei
	{
		(gpstr, gperr) := ethrpc->gasprice();
		if(gperr == nil && gpstr != nil && gpstr != "0")
			gasprice = strtobig(gpstr);
	}
	# Cap at 100 gwei to prevent fee spikes
	if(gasprice > big 100000000000)
		gasprice = big 100000000000;
	gaslimit := big 21000;	# standard ETH transfer

	dstaddr := ethcrypto->strtoaddr(recipient);
	if(dstaddr == nil)
		return (nil, "invalid recipient address: " + recipient);

	# Convert wei amount string to big
	weivalue := strtobig(weiamt);

	# Get chain ID
	(chainid, chiderr) := ethrpc->chainid();
	if(chiderr != nil)
		return (nil, "chainid: " + chiderr);

	tx := ref Ethcrypto->EthTx(
		big nonce,
		gasprice,
		gaslimit,
		dstaddr,
		weivalue,
		nil,		# no data (simple transfer)
		chainid
	);

	# Retrieve private key from factotum, sign the full tx, zero key
	svc := "wallet-eth-" + as.acct.name;
	(nil, password) := factotum->getuserpasswd("proto=pass service=" + svc);
	if(password == nil || password == "")
		return (nil, "no key in factotum for " + as.acct.name);

	privkey := ethcrypto->hexdecode(password);
	if(privkey == nil || len privkey != 32)
		return (nil, "invalid key in factotum");

	rawtx := ethcrypto->signtx(tx, privkey);
	# Zero key immediately
	for(i := 0; i < len privkey; i++)
		privkey[i] = byte 0;

	if(rawtx == nil)
		return (nil, "transaction signing failed");

	# Submit to network
	hextx := ethcrypto->hexencode(rawtx);
	(txhash, senderr) := ethrpc->sendrawtx(hextx);
	if(senderr != nil)
		return (nil, "send: " + senderr);

	return (txhash, nil);
}

#
# ERC-20 transfer: sends tokens by calling transfer(address,uint256) on the token contract
#
executeerc20(as: ref AcctState, amount: string, recipient: string): (string, string)
{
	if(as.acct.accttype != Wallet->ACCT_ETH)
		return (nil, "only ETH accounts can send ERC-20");

	addr := as.acct.address;
	if(addr == "" || addr == nil)
		return (nil, "account has no address");

	net := getnetwork();

	# Get nonce
	(nonce, nonceerr) := ethrpc->getnonce(addr);
	if(nonceerr != nil)
		return (nil, "nonce: " + nonceerr);

	# Build transfer(address,uint256) calldata
	# Function selector: 0xa9059cbb
	# address: padded to 32 bytes
	# amount: padded to 32 bytes
	recipaddr := ethcrypto->strtoaddr(recipient);
	if(recipaddr == nil)
		return (nil, "invalid recipient: " + recipient);

	# Amount is in token base units (USDC = 6 decimals, so 1 USDC = 1000000)
	amtbig := strtobig(amount);
	amtbytes := ethcrypto->bigtobytes(amtbig);

	# Build calldata: selector(4) + address(32) + amount(32) = 68 bytes
	calldata := array[68] of byte;
	# Function selector a9059cbb
	calldata[0] = byte 16ra9;
	calldata[1] = byte 16r05;
	calldata[2] = byte 16r9c;
	calldata[3] = byte 16rbb;
	# Pad recipient address to 32 bytes (left-padded with zeros)
	for(i := 0; i < 12; i++)
		calldata[4+i] = byte 0;
	calldata[16:] = recipaddr;
	# Pad amount to 32 bytes (left-padded with zeros)
	for(i = 0; i < 32; i++)
		calldata[36+i] = byte 0;
	off := 68 - len amtbytes;
	if(off < 36) off = 36;
	calldata[off:] = amtbytes;

	# Gas for ERC-20 transfer is higher than simple ETH
	# Query network gas price, fall back to 1 gwei
	gasprice := big 1000000000;	# fallback: 1 gwei
	{
		(gpstr, gperr) := ethrpc->gasprice();
		if(gperr == nil && gpstr != nil && gpstr != "0")
			gasprice = strtobig(gpstr);
	}
	# Cap at 100 gwei to prevent fee spikes
	if(gasprice > big 100000000000)
		gasprice = big 100000000000;
	gaslimit := big 100000;	# ERC-20 transfers need ~65000 gas

	# Get chain ID
	(chainid, chiderr) := ethrpc->chainid();
	if(chiderr != nil)
		return (nil, "chainid: " + chiderr);

	# Transaction goes TO the token contract, with 0 ETH value
	tokenaddr := ethcrypto->strtoaddr(net.usdc);
	if(tokenaddr == nil)
		return (nil, "invalid token contract address");

	tx := ref Ethcrypto->EthTx(
		big nonce,
		gasprice,
		gaslimit,
		tokenaddr,	# send to token contract
		big 0,		# 0 ETH value
		calldata,	# transfer(recipient, amount)
		chainid
	);

	# Sign
	svc := "wallet-eth-" + as.acct.name;
	(nil, password) := factotum->getuserpasswd("proto=pass service=" + svc);
	if(password == nil || password == "")
		return (nil, "no key in factotum for " + as.acct.name);

	privkey := ethcrypto->hexdecode(password);
	if(privkey == nil || len privkey != 32)
		return (nil, "invalid key in factotum");

	rawtx := ethcrypto->signtx(tx, privkey);
	for(i = 0; i < len privkey; i++)
		privkey[i] = byte 0;

	if(rawtx == nil)
		return (nil, "transaction signing failed");

	# Submit
	hextx := ethcrypto->hexencode(rawtx);
	(txhash, senderr) := ethrpc->sendrawtx(hextx);
	if(senderr != nil)
		return (nil, "send: " + senderr);

	return (txhash, nil);
}

strtobig(s: string): big
{
	v := big 0;
	if(s == nil)
		return v;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= '0' && c <= '9')
			v = v * big 10 + big (c - '0');
	}
	return v;
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
			name := n.name;

			if(ft == Qroot) {
				# Root directory entries
				if(name == "ctl")
					n.path = MKPATH(0, Qctl);
				else if(name == "accounts")
					n.path = MKPATH(0, Qaccounts);
				else if(name == "new")
					n.path = MKPATH(0, Qnew);
				else if(name == "pending")
					n.path = MKPATH(0, Qpending);
				else {
					# Look for account name
					id := acctidbyname(name);
					if(id >= 0)
						n.path = MKPATH(id, Qacctdir);
					else {
						n.reply <-= (nil, Enotfound);
						continue;
					}
				}
			} else if(ft == Qacctdir) {
				aid := ACCTID(n.path);
				if(name == "address")
					n.path = MKPATH(aid, Qaddress);
				else if(name == "balance")
					n.path = MKPATH(aid, Qbalance);
				else if(name == "chain")
					n.path = MKPATH(aid, Qchain);
				else if(name == "sign")
					n.path = MKPATH(aid, Qsign);
				else if(name == "pay")
					n.path = MKPATH(aid, Qpay);
				else if(name == "ctl")
					n.path = MKPATH(aid, Qacctctl);
				else if(name == "history")
					n.path = MKPATH(aid, Qhistory);
				else {
					n.reply <-= (nil, Enotfound);
					continue;
				}
			} else if(name == "..") {
				if(ft >= Qacctdir && ft <= Qhistory)
					n.path = MKPATH(ACCTID(n.path), Qacctdir);
				else
					n.path = MKPATH(0, Qroot);
			} else {
				n.reply <-= (nil, Enotfound);
				continue;
			}
			n.reply <-= dirgen(n.path);

		Readdir =>
			ft := FTYPE(n.path);
			entries: list of big;

			if(ft == Qroot) {
				# Root: ctl, accounts, new, pending, then account dirs
				entries = MKPATH(0, Qpending) :: entries;
				entries = MKPATH(0, Qnew) :: entries;
				entries = MKPATH(0, Qaccounts) :: entries;
				entries = MKPATH(0, Qctl) :: entries;
				i := 0;
				for(l := accounts; l != nil; l = tl l) {
					entries = MKPATH(i, Qacctdir) :: entries;
					i++;
				}
			} else if(ft == Qacctdir) {
				aid := ACCTID(n.path);
				entries =
					MKPATH(aid, Qaddress) ::
					MKPATH(aid, Qbalance) ::
					MKPATH(aid, Qchain) ::
					MKPATH(aid, Qsign) ::
					MKPATH(aid, Qpay) ::
					MKPATH(aid, Qacctctl) ::
					MKPATH(aid, Qhistory) ::
					nil;
			}

			# Reverse to correct order
			ordered: list of big;
			for(el := entries; el != nil; el = tl el)
				ordered = hd el :: ordered;

			# Emit entries
			k := 0;
			for(ol := ordered; ol != nil; ol = tl ol) {
				if(k >= n.offset + n.count)
					break;
				if(k >= n.offset) {
					(d, e) := dirgen(hd ol);
					n.reply <-= (d, e);
				}
				k++;
			}
			n.reply <-= (nil, nil);
		}
	}
}

dirgen(p: big): (ref Sys->Dir, string)
{
	ft := FTYPE(p);
	aid := ACCTID(p);

	name := "";
	perm := 8r444;
	qtype := Sys->QTFILE;

	case ft {
	Qroot =>
		name = "/";
		perm = Sys->DMDIR | 8r555;
		qtype = Sys->QTDIR;
	Qctl =>
		name = "ctl";
		perm = 8r666;
	Qaccounts =>
		name = "accounts";
	Qnew =>
		name = "new";
		perm = 8r666;
	Qpending =>
		name = "pending";
		perm = 8r444;
	Qacctdir =>
		as := findacctbyid(aid);
		if(as != nil)
			name = as.acct.name;
		else
			name = string aid;
		perm = Sys->DMDIR | 8r555;
		qtype = Sys->QTDIR;
	Qaddress =>
		name = "address";
	Qbalance =>
		name = "balance";
	Qchain =>
		name = "chain";
		perm = 8r666;
	Qsign =>
		name = "sign";
		perm = 8r666;
	Qpay =>
		name = "pay";
		perm = 8r666;
	Qacctctl =>
		name = "ctl";
		perm = 8r666;
	Qhistory =>
		name = "history";
	* =>
		return (nil, Enotfound);
	}

	d := ref sys->zerodir;
	d.name = name;
	d.uid = user;
	d.gid = user;
	d.qid = Qid(p, vers, qtype);
	d.mode = perm;
	d.length = big 0;

	return (d, nil);
}
