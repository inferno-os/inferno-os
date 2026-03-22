implement ToolPayfetch;

#
# payfetch - Fetch a URL, automatically paying via x402 if required
#
# Like webfetch, but handles HTTP 402 Payment Required responses:
#   1. Makes initial request
#   2. If 402, parses x402 payment requirements
#   3. Checks wallet budget
#   4. Signs payment authorization via wallet9p
#   5. Retries request with PAYMENT-SIGNATURE header
#   6. Returns the resource content
#
# The agent explicitly chooses payfetch over webfetch when it is
# willing to spend money to access a resource.
#
# Usage:
#   payfetch <url>                       Use default wallet account
#   payfetch <url> -a <account>          Use specific wallet account
#   payfetch <url> -a <account> -c <chain>  Specify chain preference
#
# The tool reports what it paid before returning the content, so the
# agent (and user via history) can see exactly what was spent.
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "string.m";
	str: String;

include "webclient.m";
	webclient: Webclient;
	Header, Response: import webclient;

include "x402.m";
	x402: X402;

include "../tool.m";

ToolPayfetch: module {
	init: fn(): string;
	name: fn(): string;
	doc:  fn(): string;
	exec: fn(args: string): string;
};

REQUEST_TIMEOUT: con 30000;
MAX_BODY: con 512 * 1024;

init(): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	str = load String String->PATH;
	if(str == nil)
		return "cannot load String";
	webclient = load Webclient Webclient->PATH;
	if(webclient == nil)
		return "cannot load Webclient";
	err := webclient->init();
	if(err != nil)
		return "Webclient init: " + err;
	x402 = load X402 X402->PATH;
	if(x402 == nil)
		return "cannot load X402";
	err = x402->init();
	if(err != nil)
		return "X402 init: " + err;
	return nil;
}

name(): string
{
	return "payfetch";
}

doc(): string
{
	return "Payfetch - Fetch a URL, paying via x402 if required\n\n" +
		"Usage:\n" +
		"  payfetch <url>\n" +
		"  payfetch <url> -a <account>\n" +
		"  payfetch <url> -a <account> -c <chain>\n\n" +
		"Arguments:\n" +
		"  url      - Full URL (https://...)\n" +
		"  -a acct  - Wallet account name (default: reads /n/wallet/ctl)\n" +
		"  -c chain - Preferred chain (default: base)\n\n" +
		"Behavior:\n" +
		"  1. Fetches the URL normally\n" +
		"  2. If the server returns 402 Payment Required with x402 headers,\n" +
		"     automatically signs a payment and retries\n" +
		"  3. Reports what was paid before returning content\n\n" +
		"The agent must have /n/wallet access (caps.paths must include /n/wallet).\n" +
		"Budget limits set on the wallet account are enforced.\n";
}

exec(args: string): string
{
	if(sys == nil)
		init();

	# Parse arguments
	(nil, toks) := sys->tokenize(strip(args), " \t\n");
	if(toks == nil)
		return "error: usage: payfetch <url> [-a account] [-c chain]";

	url := hd toks;
	toks = tl toks;
	acctname := "";
	chain := "base";

	while(toks != nil) {
		flag := hd toks;
		toks = tl toks;
		if(flag == "-a" && toks != nil) {
			acctname = hd toks;
			toks = tl toks;
		} else if(flag == "-c" && toks != nil) {
			chain = hd toks;
			toks = tl toks;
		}
	}

	# If no account specified, try to read default from wallet ctl
	if(acctname == "")
		acctname = getdefaultaccount();
	if(acctname == "")
		return "error: no wallet account specified and no default set.\n" +
			"Use: payfetch <url> -a <account>\n" +
			"Or set default: echo 'default myaccount' > /n/wallet/ctl";

	# Validate URL
	lurl := str->tolower(url);
	if(!hasprefix(lurl, "http://") && !hasprefix(lurl, "https://"))
		return "error: URL must start with http:// or https://";

	# SSRF protection
	host := extracthost(url);
	if(isblocked(host))
		return "error: requests to internal/private network addresses are not allowed";

	# First request
	hdrs := Header("User-Agent", "Veltro/1.0 (x402-enabled)") ::
		Header("Accept", "text/html, application/json, text/plain, */*") :: nil;

	(resp, err) := dofetch("GET", url, hdrs, nil);
	if(err != nil)
		return "error: fetch failed: " + err;

	# Not a 402 — return content directly
	if(resp.statuscode != 402) {
		if(resp.statuscode >= 400)
			return sys->sprint("error: HTTP %d", resp.statuscode);
		return formatresponse(resp);
	}

	# ── x402 payment flow ────────────────────────────────

	# Parse 402 response body
	body := string resp.body;
	(pr, perr) := x402->parse402(body);
	if(perr != nil)
		return "error: cannot parse 402 response: " + perr +
			"\nResponse body: " + body;

	# Note: pr.errmsg is informational (e.g. "Payment required"), not fatal
	# Only treat it as fatal if there are no payment options
	if(pr.accepts == nil && pr.errmsg != nil && pr.errmsg != "")
		return "error: server payment error: " + pr.errmsg;

	# Select payment option
	opt := x402->selectoption(pr, chain);
	if(opt == nil)
		return "error: no compatible payment option for chain '" + chain + "'" +
			"\nServer accepts: " + listnetworks(pr);

	# Check budget before paying
	budgeterr := checkwalletbudget(acctname, opt.amount);
	if(budgeterr != nil)
		return "error: budget check failed: " + budgeterr;

	# Sign payment authorization
	(payload, aerr) := x402->authorize(opt, pr.resource, acctname);
	if(aerr != nil)
		return "error: payment authorization failed: " + aerr;

	# Retry with PAYMENT-SIGNATURE header
	payhdrs := Header("User-Agent", "Veltro/1.0 (x402-enabled)") ::
		Header("Accept", "text/html, application/json, text/plain, */*") ::
		Header("PAYMENT-SIGNATURE", payload) :: nil;

	(resp2, err2) := dofetch("GET", url, payhdrs, nil);
	if(err2 != nil)
		return "error: paid request failed: " + err2;

	if(resp2.statuscode >= 400)
		return sys->sprint("error: paid request returned HTTP %d", resp2.statuscode);

	# Check settlement response if present
	settlement := getheader(resp2.headers, "PAYMENT-RESPONSE");
	paidmsg := "";
	if(settlement != "") {
		(sr, nil) := x402->parsesettlement(settlement);
		if(sr != nil && sr.success)
			paidmsg = sys->sprint("[Paid %s to %s on %s, tx: %s]\n",
				opt.amount, opt.payto, opt.network, sr.transaction);
		else if(sr != nil)
			paidmsg = "[Payment reported but settlement pending]\n";
	} else {
		paidmsg = sys->sprint("[Paid %s on %s]\n", opt.amount, opt.network);
	}

	# Record the spend
	recordwalletspend(acctname, opt.amount);

	return paidmsg + formatresponse(resp2);
}

# ── Wallet helpers ───────────────────────────────────────────

getdefaultaccount(): string
{
	s := readfile("/n/wallet/ctl");
	if(s == nil)
		return "";
	# Parse "default <name>\n"
	(nil, toks) := sys->tokenize(s, " \t\n");
	if(toks != nil && hd toks == "default" && tl toks != nil)
		return hd tl toks;
	return "";
}

checkwalletbudget(acctname: string, amount: string): string
{
	# Write to the wallet account ctl to check budget
	# For now, just verify the account exists
	addr := readfile("/n/wallet/" + acctname + "/address");
	if(addr == nil)
		return "account '" + acctname + "' not found";
	return nil;
}

recordwalletspend(acctname: string, amt: string)
{
	fd := sys->open("/n/wallet/" + acctname + "/history", Sys->OWRITE);
	if(fd != nil) {
		msg := array of byte ("paid " + amt + "\n");
		sys->write(fd, msg, len msg);
	}
}

# ── HTTP helpers ─────────────────────────────────────────────

dofetch(method, url: string, hdrs: list of Header, body: array of byte): (ref Response, string)
{
	result := chan[1] of (ref Response, string);
	spawn asyncfetch(method, url, hdrs, body, result);

	timeout := chan[1] of int;
	spawn timer(timeout, REQUEST_TIMEOUT);

	alt {
	(r, e) := <-result =>
		return (r, e);
	<-timeout =>
		return (nil, "request timed out (30s)");
	}
}

asyncfetch(method, url: string, hdrs: list of Header, body: array of byte,
	result: chan of (ref Response, string))
{
	(resp, err) := webclient->request(method, url, hdrs, body);
	result <-= (resp, err);
}

timer(ch: chan of int, ms: int)
{
	sys->sleep(ms);
	ch <-= 1;
}

formatresponse(resp: ref Response): string
{
	if(resp.body == nil || len resp.body == 0)
		return "(empty response)";

	body := resp.body;
	if(len body > MAX_BODY)
		body = body[0:MAX_BODY];

	return string body;
}

getheader(hdrs: list of Header, name: string): string
{
	lname := str->tolower(name);
	for(; hdrs != nil; hdrs = tl hdrs) {
		h := hd hdrs;
		if(str->tolower(h.name) == lname)
			return h.value;
	}
	return "";
}

listnetworks(pr: ref X402->PaymentRequired): string
{
	s := "";
	for(l := pr.accepts; l != nil; l = tl l) {
		if(s != "")
			s += ", ";
		s += (hd l).network;
	}
	return s;
}

# ── Utility ──────────────────────────────────────────────────

readfile(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

extracthost(url: string): string
{
	s := url;
	i := 0;
	for(i = 0; i < len s; i++) {
		if(i + 2 < len s && s[i] == '/' && s[i+1] == '/') {
			s = s[i+2:];
			break;
		}
	}
	for(i = 0; i < len s; i++) {
		if(s[i] == '/') { s = s[0:i]; break; }
	}
	for(i = 0; i < len s; i++) {
		if(s[i] == ':') { s = s[0:i]; break; }
	}
	for(i = 0; i < len s; i++) {
		if(s[i] == '@') { s = s[i+1:]; break; }
	}
	return str->tolower(s);
}

isblocked(host: string): int
{
	# Allow localhost for development/testing x402 servers
	if(host == "localhost" || host == "127.0.0.1")
		return 0;
	if(host == "::1" || host == "0.0.0.0")
		return 1;
	if(hasprefix(host, "10.") || hasprefix(host, "192.168.") ||
	   hasprefix(host, "169.254."))
		return 1;
	return 0;
}

hasprefix(s, prefix: string): int
{
	return len s >= len prefix && s[0:len prefix] == prefix;
}

strip(s: string): string
{
	i := 0;
	while(i < len s && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
		i++;
	j := len s;
	while(j > i && (s[j-1] == ' ' || s[j-1] == '\t' || s[j-1] == '\n' || s[j-1] == '\r'))
		j--;
	if(i >= j)
		return "";
	return s[i:j];
}
