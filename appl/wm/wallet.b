implement WmWallet;

#
# wallet - Cryptocurrency & fiat wallet manager for Lucifer
#
# GUI front-end to wallet9p (/n/wallet/) for managing accounts,
# viewing addresses and balances, and setting budgets.
#
# The app does NOT handle private keys directly — all key operations
# go through wallet9p which uses factotum for secure key storage.
#
# Layout:
#   Left pane (35%)   account list
#   Right pane (65%)  account details or import form
#
# Mouse:
#   Button 1     select account / interact with fields
#   Button 3     context menu (new, import, delete, refresh)
#
# Keyboard:
#   Tab          cycle focus between fields
#   Enter        confirm / import
#   Escape       cancel form
#   Ctrl-Q       quit
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect, Pointer: import draw;

include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

include "menu.m";
	menumod: Menu;
	Popup: import menumod;

include "string.m";
	str: String;

include "lucitheme.m";

include "sh.m";

include "widget.m";
	widgetmod: Widget;
	Scrollbar, Statusbar, Textfield, Listbox, Button, Label, Dropdown, Kbdfilter: import widgetmod;

WmWallet: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# ── Account representation ───────────────────────────────────

AcctInfo: adt {
	name:    string;
	chain:   string;
	address: string;
};

# ── View modes ───────────────────────────────────────────────

ModeView, ModeNewETH, ModeImport: con iota;

# ── State ────────────────────────────────────────────────────

w: ref Window;
display_g: ref Display;
font: ref Font;
kf: ref Kbdfilter;
sbar: ref Statusbar;
acctlist: ref Listbox;
mainmenu: ref Popup;
detailmenu: ref Popup;

# Detail pane labels
lbl_name:    ref Label;
lbl_addr:    ref Label;
lbl_chain:   ref Label;
lbl_balance: ref Label;
lbl_addrval: ref Label;
lbl_chainval:ref Label;
lbl_balval:  ref Label;
lbl_balval2: ref Label;

# Network selector
dd_network: ref Dropdown;
networknames: array of string;

# Balance cache (avoid blocking GUI on RPC calls)
cachedbalance: string;
balancefetchactive: int;

# Balance refresh
balancech: chan of int;

# Form fields (import mode)
f_name:   ref Textfield;
f_key:    ref Textfield;
f_chain:  ref Textfield;
btn_ok:   ref Button;
btn_cancel: ref Button;

# Colours
bgcolor:   ref Image;
panebg:    ref Image;
divcolor:  ref Image;

# App state
accounts:   array of ref AcctInfo;
mode:       int;
formfields: array of ref Textfield;
focusidx:   int;
dirty:      int;

stderr: ref Sys->FD;
themech: chan of int;

# ── Layout constants ─────────────────────────────────────────

CAT_WIDTH_FRAC: con 35;
FIELD_SPACING: con 4;
FORM_MARGIN: con 12;
BTN_W: con 90;
LEFT: con 0;

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	menumod = load Menu Menu->PATH;
	str = load String String->PATH;
	stderr = sys->fildes(2);

	if(ctxt == nil) {
		sys->fprint(stderr, "wallet: no window context\n");
		raise "fail:no context";
	}

	sys->pctl(Sys->NEWPGRP, nil);

	# Ensure wallet9p is running
	ensurewallet9p();

	wmclient->init();
	sys->sleep(100);

	w = wmclient->window(ctxt, "Wallet", Wmclient->Appl);
	display_g = w.display;

	font = Font.open(display_g, "/fonts/combined/unicode.sans.14.font");
	if(font == nil)
		font = Font.open(display_g, "*default*");

	loadcolors();

	if(widgetmod == nil)
		widgetmod = load Widget Widget->PATH;
	widgetmod->init(display_g, font);

	if(menumod != nil) {
		menumod->init(display_g, font);
		mainmenu = menumod->new(array[] of {
			"New Ethereum Account",
			"Import Private Key",
			"",
			"Refresh",
		});
		detailmenu = menumod->new(array[] of {
			"Copy Address",
			"Copy Account Name",
			"",
			"Refresh Balance",
		});
	}

	kf = Kbdfilter.new();

	w.reshape(Rect((0, 0), (520, 400)));
	w.startinput("kbd" :: "ptr" :: nil);
	w.onscreen(nil);

	mode = ModeView;
	focusidx = -1;
	sys->sleep(500);	# let wallet9p finish restoring
	refreshaccounts();
	layoutall();
	dirty = 1;

	themech = chan of int;
	spawn themelistener();

	balancech = chan of int;
	spawn balancetimer();

	# Main event loop
	for(;;) {
		if(dirty) {
			redraw();
			dirty = 0;
		}
		alt {
		ctl := <-w.ctl or
		ctl = <-w.ctxt.ctl =>
			if(ctl == nil)
				;
			else if(ctl[0] == '!') {
				w.wmctl(ctl);
				layoutall();
				dirty = 1;
			} else
				w.wmctl(ctl);
		k := <-w.ctxt.kbd =>
			handlekey(k);
		ptr := <-w.ctxt.ptr =>
			if(ptr == nil)
				;
			else if(w.pointer(*ptr))
				;
			else
				handleptr(ptr);
		<-themech =>
			loadcolors();
			widgetmod->retheme(display_g);
			layoutall();
			dirty = 1;
		<-balancech =>
			if(mode == ModeView) {
				layoutall();
				dirty = 1;
			}
		}
	}
}

# ── Colours ──────────────────────────────────────────────────

loadcolors()
{
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor  = display_g.color(th.editbg);
		panebg   = display_g.color(th.bg);
		divcolor = display_g.color(th.editlineno);
	} else {
		bgcolor  = display_g.color(int 16rFFFDF6FF);
		panebg   = display_g.color(int 16rF5F5F0FF);
		divcolor = display_g.color(int 16rBBBBBBFF);
	}
}

# ── Layout ───────────────────────────────────────────────────

layoutall()
{
	wr := w.imager(w.image.r);
	sh := widgetmod->statusheight();
	fh := font.height + 8;
	bh := font.height + 10;

	# Status bar at bottom
	sbr := Rect((wr.min.x, wr.max.y - sh), wr.max);
	if(sbar == nil)
		sbar = Statusbar.new(sbr);
	else
		sbar.resize(sbr);

	# Left pane: account list
	catw := wr.dx() * CAT_WIDTH_FRAC / 100;
	listr := Rect(wr.min, (wr.min.x + catw, wr.max.y - sh));
	if(acctlist == nil)
		acctlist = Listbox.mk(listr);
	else
		acctlist.resize(listr);

	# Right pane: details or form
	rx := wr.min.x + catw + 1;	# +1 for divider
	ry := wr.min.y + FORM_MARGIN;
	rw := wr.max.x - FORM_MARGIN;
	rbottom := wr.max.y - sh - FORM_MARGIN;

	# Network selector at top of right pane
	if(networknames == nil)
		networknames = array[] of {
			"Ethereum Sepolia",
			"Base Sepolia",
			"Ethereum Mainnet",
			"Base",
		};
	ddsel := 0;
	if(dd_network != nil)
		ddsel = dd_network.selected;
	dd_network = Dropdown.mk(Rect((rx + FORM_MARGIN, ry), (rw, ry + fh)),
		networknames, ddsel);
	dd_network.label = "Network:";
	ry += fh + FIELD_SPACING + 4;

	case mode {
	ModeView =>
		layoutdetail(rx + FORM_MARGIN, ry, rw, rbottom, fh);
	ModeNewETH or ModeImport =>
		layoutform(rx + FORM_MARGIN, ry, rw, rbottom, fh, bh);
	}
}

layoutdetail(cx, cy, cw, cbottom, fh: int)
{
	if(cy > cbottom) return;
	# Show account details if one is selected
	sel := -1;
	if(acctlist != nil)
		sel = acctlist.selected;

	if(sel < 0 || sel >= len accounts) {
		lbl_name = Label.mk(Rect((cx, cy), (cw, cy + fh)), "Select an account", 1, LEFT);
		lbl_addr = nil;
		lbl_chain = nil;
		lbl_balance = nil;
		lbl_addrval = nil;
		lbl_chainval = nil;
		lbl_balval = nil;
		lbl_balval2 = nil;
		formfields = nil;
		return;
	}

	acct := accounts[sel];

	lbl_name = Label.mk(Rect((cx, cy), (cw, cy + fh)), acct.name, 0, LEFT);
	cy += fh + FIELD_SPACING + 4;

	lbl_chain = Label.mk(Rect((cx, cy), (cw, cy + fh)), "Chain:", 1, LEFT);
	cy += fh;
	lbl_chainval = Label.mk(Rect((cx, cy), (cw, cy + fh)), acct.chain, 0, LEFT);
	cy += fh + FIELD_SPACING + 4;

	lbl_addr = Label.mk(Rect((cx, cy), (cw, cy + fh)), "Address:", 1, LEFT);
	cy += fh;
	addr := acct.address;
	if(addr == "" || addr == nil)
		addr = "(not available)";
	lbl_addrval = Label.mk(Rect((cx, cy), (cw, cy + fh)), addr, 0, LEFT);
	cy += fh + FIELD_SPACING + 4;

	lbl_balance = Label.mk(Rect((cx, cy), (cw, cy + fh)), "Balance:", 1, LEFT);
	cy += fh;

	# Show cached balance immediately, fetch in background
	bal := cachedbalance;
	if(bal == nil || bal == "")
		bal = "loading...";
	(usdcbal, ethbal) := splitbalance(bal);
	lbl_balval = Label.mk(Rect((cx, cy), (cw, cy + fh)), usdcbal, 0, LEFT);
	cy += fh;
	lbl_balval2 = Label.mk(Rect((cx, cy), (cw, cy + fh)), ethbal, 0, LEFT);

	# Fetch balance in background
	spawn fetchbalance(acct.name);

	formfields = nil;
}

layoutform(cx, cy, cw, cbottom, fh, bh: int)
{
	if(cy > cbottom) return;
	title := "Import Private Key";
	if(mode == ModeNewETH)
		title = "New Ethereum Account";

	lbl_name = Label.mk(Rect((cx, cy), (cw, cy + fh)), title, 0, LEFT);
	cy += fh + FIELD_SPACING + 4;

	lw := widgetmod->labelwidth(array[] of {"Name:", "Chain:", "Key:"});
	f_name = Textfield.mk(Rect((cx, cy), (cw, cy + fh)), "Name:", 0);
	f_name.labelw = lw;
	cy += fh + FIELD_SPACING;

	if(mode == ModeImport) {
		f_chain = Textfield.mk(Rect((cx, cy), (cw, cy + fh)), "Chain:", 0);
		f_chain.labelw = lw;
		f_chain.setval("ethereum");
		cy += fh + FIELD_SPACING;
		f_key = Textfield.mk(Rect((cx, cy), (cw, cy + fh)), "Key:", 1);
		f_key.labelw = lw;
		cy += fh + FIELD_SPACING;
		formfields = array[] of { f_name, f_chain, f_key };
	} else {
		f_chain = Textfield.mk(Rect((cx, cy), (cw, cy + fh)), "Chain:", 0);
		f_chain.labelw = lw;
		f_chain.setval("ethereum");
		cy += fh + FIELD_SPACING;
		f_key = nil;
		formfields = array[] of { f_name, f_chain };
	}

	cy += FIELD_SPACING;

	# Buttons
	btnx := cx;
	btn_ok = Button.mk(Rect((btnx, cy), (btnx + BTN_W, cy + bh)),
		"Create");
	if(mode == ModeImport)
		btn_ok = Button.mk(Rect((btnx, cy), (btnx + BTN_W, cy + bh)),
			"Import");
	btnx += BTN_W + 8;
	btn_cancel = Button.mk(Rect((btnx, cy), (btnx + BTN_W, cy + bh)),
		"Cancel");

	focusidx = 0;
}

# ── Drawing ──────────────────────────────────────────────────

redraw()
{
	wr := w.imager(w.image.r);
	sh := widgetmod->statusheight();
	catw := wr.dx() * CAT_WIDTH_FRAC / 100;

	# Clear right pane background
	rpane := Rect((wr.min.x + catw + 1, wr.min.y), (wr.max.x, wr.max.y - sh));
	w.image.draw(rpane, panebg, nil, Point(0, 0));

	# Draw account list
	acctlist.draw(w.image);

	# Draw divider
	divr := Rect((wr.min.x + catw, wr.min.y), (wr.min.x + catw + 1, wr.max.y - sh));
	w.image.draw(divr, divcolor, nil, Point(0, 0));

	# Draw network selector
	if(dd_network != nil)
		dd_network.draw(w.image);

	# Draw detail pane
	case mode {
	ModeView =>
		drawdetail();
	ModeNewETH or ModeImport =>
		drawform();
	}

	# Status bar
	naccts := len accounts;
	sbar.left = sys->sprint("%d account%s", naccts, plural(naccts));
	sbar.right = "B3: menu";
	sbar.draw(w.image);

	w.image.flush(Draw->Flushnow);
}

drawdetail()
{
	if(lbl_name != nil)
		lbl_name.draw(w.image);
	if(lbl_chain != nil)
		lbl_chain.draw(w.image);
	if(lbl_chainval != nil)
		lbl_chainval.draw(w.image);
	if(lbl_addr != nil)
		lbl_addr.draw(w.image);
	if(lbl_addrval != nil)
		lbl_addrval.draw(w.image);
	if(lbl_balance != nil)
		lbl_balance.draw(w.image);
	if(lbl_balval != nil)
		lbl_balval.draw(w.image);
	if(lbl_balval2 != nil)
		lbl_balval2.draw(w.image);
}

drawform()
{
	if(lbl_name != nil)
		lbl_name.draw(w.image);
	if(formfields != nil) {
		for(i := 0; i < len formfields; i++) {
			formfields[i].focused = (i == focusidx);
			formfields[i].draw(w.image);
		}
	}
	if(btn_ok != nil)
		btn_ok.draw(w.image);
	if(btn_cancel != nil)
		btn_cancel.draw(w.image);
}

# ── Keyboard handling ────────────────────────────────────────

handlekey(raw: int)
{
	k := kf.filter(raw);
	if(k == 0)
		return;

	case k {
	'q' - 'a' + 1 =>	# Ctrl-Q
		cleanup();
	27 =>			# Escape
		if(mode != ModeView) {
			mode = ModeView;
			focusidx = -1;
			layoutall();
		}
		dirty = 1;
	'\t' =>
		if(formfields != nil && len formfields > 0) {
			focusidx = (focusidx + 1) % len formfields;
			dirty = 1;
		}
	'\n' =>
		if(mode == ModeNewETH)
			donewaccount();
		else if(mode == ModeImport)
			doimport();
	* =>
		if(formfields != nil && focusidx >= 0 && focusidx < len formfields) {
			formfields[focusidx].key(k);
			dirty = 1;
		}
	}
}

# ── Pointer handling ─────────────────────────────────────────

handleptr(ptr: ref Pointer)
{
	if(ptr.buttons == 0)
		return;

	# Button 3: context menu
	if(ptr.buttons & 4) {
		# Detail pane right-click: show detail menu if account selected
		if(mode == ModeView && acctlist != nil && acctlist.selected >= 0 &&
		   !acctlist.contains(ptr.xy)) {
			if(detailmenu != nil) {
				sel := detailmenu.show(w.image, ptr.xy, w.ctxt.ptr);
				handledetailmenu(sel);
				dirty = 1;
				return;
			}
		}
		# Otherwise: main menu
		if(mainmenu == nil)
			return;
		sel := mainmenu.show(w.image, ptr.xy, w.ctxt.ptr);
		handlemenu(sel);
		dirty = 1;
		return;
	}

	if(!(ptr.buttons & 1))
		return;

	# Scrollbar tracking (continuous drag)
	if(acctlist != nil && acctlist.scroll.isactive()) {
		newo := acctlist.scroll.track(ptr);
		if(newo >= 0) {
			acctlist.top = newo;
			dirty = 1;
		}
		return;
	}

	# Account list click (Listbox.click handles scrollbar internally)
	if(acctlist != nil && acctlist.contains(ptr.xy)) {
		if(ptr.buttons & 8 || ptr.buttons & 16) {
			acctlist.wheel(ptr.buttons);
			dirty = 1;
			return;
		}
		sel := acctlist.click(ptr.xy);
		if(sel >= 0) {
			mode = ModeView;
			layoutall();
			dirty = 1;
		}
		return;
	}

	# Network dropdown click
	if(dd_network != nil && dd_network.contains(ptr.xy)) {
		oldnet := dd_network.selected;
		dd_network.click(w.image, w.ctxt.ptr);
		if(dd_network.selected != oldnet) {
			# Write network change to wallet9p
			writewalletctl("ctl", "network " + dd_network.value());
			layoutall();
			setstatus("Network: " + dd_network.value());
		}
		dirty = 1;
		return;
	}

	# Form field clicks
	if(formfields != nil) {
		for(i := 0; i < len formfields; i++) {
			if(formfields[i].contains(ptr.xy)) {
				focusidx = i;
				formfields[i].click(ptr.xy);
				dirty = 1;
				return;
			}
		}
	}

	# Button clicks
	if(btn_ok != nil && btn_ok.contains(ptr.xy)) {
		btn_ok.pressed = 1;
		dirty = 1;
		# Wait for release
		for(;;) {
			p := <-w.ctxt.ptr;
			if(p == nil || !(p.buttons & 1)) {
				btn_ok.pressed = 0;
				if(p != nil && btn_ok.contains(p.xy)) {
					if(mode == ModeNewETH)
						donewaccount();
					else if(mode == ModeImport)
						doimport();
				}
				dirty = 1;
				return;
			}
		}
	}

	if(btn_cancel != nil && btn_cancel.contains(ptr.xy)) {
		btn_cancel.pressed = 1;
		dirty = 1;
		for(;;) {
			p := <-w.ctxt.ptr;
			if(p == nil || !(p.buttons & 1)) {
				btn_cancel.pressed = 0;
				if(p != nil && btn_cancel.contains(p.xy)) {
					mode = ModeView;
					focusidx = -1;
					layoutall();
				}
				dirty = 1;
				return;
			}
		}
	}
}

handlemenu(sel: int)
{
	case sel {
	0 =>	# New Ethereum Account
		mode = ModeNewETH;
		layoutall();
	1 =>	# Import Private Key
		mode = ModeImport;
		layoutall();
	3 =>	# Refresh
		refreshaccounts();
		if(mode == ModeView)
			layoutall();
	}
}

# ── Account operations ───────────────────────────────────────

donewaccount()
{
	name := f_name.value();
	if(name == "") {
		setstatus("Name is required");
		return;
	}

	chain := "ethereum";
	if(f_chain != nil) {
		v := f_chain.value();
		if(v != "")
			chain = v;
	}

	cmd := "eth " + chain + " " + name;
	n := writewalletctl("new", cmd);
	if(n <= 0) {
		errmsg := sys->sprint("%r");
		if(errmsg == "" || errmsg == "no error")
			errmsg = "create failed";
		setstatus(errmsg);
		# Stay in form mode so user sees the error
		dirty = 1;
		return;
	}

	mode = ModeView;
	focusidx = -1;
	refreshaccounts();
	# Select the new account
	for(i := 0; i < len accounts; i++)
		if(accounts[i].name == name)
			acctlist.selected = i;
	layoutall();
	setstatus("Account created: " + name);
	dirty = 1;
}

doimport()
{
	name := f_name.value();
	if(name == "") {
		setstatus("Name is required");
		return;
	}

	chain := "ethereum";
	if(f_chain != nil) {
		v := f_chain.value();
		if(v != "")
			chain = v;
	}

	hexkey := "";
	if(f_key != nil)
		hexkey = f_key.value();
	if(hexkey == "") {
		setstatus("Private key is required");
		return;
	}

	cmd := "import eth " + chain + " " + name + " " + hexkey;
	n := writewalletctl("new", cmd);
	if(n <= 0) {
		setstatus(sys->sprint("import failed: %r"));
		return;
	}

	mode = ModeView;
	focusidx = -1;
	refreshaccounts();
	for(i := 0; i < len accounts; i++)
		if(accounts[i].name == name)
			acctlist.selected = i;
	layoutall();
	setstatus("Account imported: " + name);
	dirty = 1;
}

refreshaccounts()
{
	# Read account list from wallet9p
	s := readwalletfile(nil, "accounts");
	if(s == nil || s == "") {
		accounts = array[0] of ref AcctInfo;
		if(acctlist != nil)
			acctlist.setitems(nil);
		return;
	}

	# Parse newline-separated names
	names: list of string;
	(nil, toks) := sys->tokenize(s, "\n");
	for(; toks != nil; toks = tl toks) {
		n := hd toks;
		if(n != "")
			names = n :: names;
	}

	# Reverse to preserve order
	rnames: list of string;
	for(; names != nil; names = tl names)
		rnames = hd names :: rnames;

	# Build account info array
	n := 0;
	for(l := rnames; l != nil; l = tl l)
		n++;

	accounts = array[n] of ref AcctInfo;
	items := array[n] of string;
	i := 0;
	for(l = rnames; l != nil; l = tl l) {
		name := hd l;
		chain := stripnl(readwalletfile(name, "chain"));
		addr := stripnl(readwalletfile(name, "address"));
		accounts[i] = ref AcctInfo(name, chain, addr);
		# List display: "name (chain)"
		items[i] = name;
		if(chain != nil && chain != "")
			items[i] += "  " + chain;
		i++;
	}

	if(acctlist != nil)
		acctlist.setitems(items);
}

# ── Wallet9p file helpers ────────────────────────────────────

readwalletfile(acct: string, file: string): string
{
	path: string;
	if(acct == nil || acct == "")
		path = "/n/wallet/" + file;
	else
		path = "/n/wallet/" + acct + "/" + file;

	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

writewalletctl(file: string, data: string): int
{
	path := "/n/wallet/" + file;
	fd := sys->open(path, Sys->OWRITE);
	if(fd == nil) {
		sys->fprint(stderr, "wallet: cannot open %s: %r\n", path);
		return -1;
	}
	b := array of byte data;
	n := sys->write(fd, b, len b);
	if(n < 0)
		sys->fprint(stderr, "wallet: write %s failed: %r\n", path);
	return n;
}

# ── Utilities ────────────────────────────────────────────────

setstatus(msg: string)
{
	if(sbar != nil)
		sbar.left = msg;
	dirty = 1;
}

stripnl(s: string): string
{
	if(s == nil)
		return "";
	while(len s > 0 && (s[len s - 1] == '\n' || s[len s - 1] == '\r'))
		s = s[0:len s - 1];
	return s;
}

plural(n: int): string
{
	if(n == 1)
		return "";
	return "s";
}

# Split "X USDC, Y ETH" into two lines
splitbalance(bal: string): (string, string)
{
	# Find comma separator
	for(i := 0; i < len bal; i++) {
		if(bal[i] == ',') {
			usdcpart := strip(bal[0:i]);
			ethpart := strip(bal[i+1:]);
			return (usdcpart, ethpart);
		}
	}
	# No comma — single value
	return (bal, "");
}

handledetailmenu(sel: int)
{
	if(acctlist == nil || acctlist.selected < 0 || acctlist.selected >= len accounts)
		return;
	acct := accounts[acctlist.selected];

	case sel {
	0 =>	# Copy Address
		copytoclip(acct.address);
		setstatus("Address copied");
	1 =>	# Copy Account Name
		copytoclip(acct.name);
		setstatus("Account name copied");
	3 =>	# Refresh Balance
		layoutall();
		setstatus("Balance refreshed");
	}
}

copytoclip(s: string)
{
	fd := sys->open("/dev/snarf", Sys->OWRITE);
	if(fd == nil)
		return;
	b := array of byte s;
	sys->write(fd, b, len b);
}

fetchbalance(acctname: string)
{
	if(balancefetchactive)
		return;
	balancefetchactive = 1;
	bal := stripnl(readwalletfile(acctname, "balance"));
	if(bal != nil && bal != "")
		cachedbalance = bal;
	balancefetchactive = 0;
	alt {
	balancech <-= 1 => ;
	* => ;
	}
}

balancetimer()
{
	for(;;) {
		sys->sleep(30000);	# refresh every 30 seconds
		alt {
		balancech <-= 1 => ;
		* => ;
		}
	}
}

# strip leading/trailing whitespace
strip(s: string): string
{
	if(s == nil)
		return "";
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

ensurewallet9p()
{
	# Check if wallet9p is already mounted
	(ok, nil) := sys->stat("/n/wallet/accounts");
	if(ok >= 0)
		return;

	sys->fprint(stderr, "wallet: starting wallet9p...\n");

	# Start wallet9p in background
	mod := load Command "/dis/veltro/wallet9p.dis";
	if(mod == nil) {
		sys->fprint(stderr, "wallet: cannot load wallet9p: %r\n");
		return;
	}
	spawn mod->init(nil, "wallet9p" :: nil);

	# Wait for mount (poll up to 5 seconds)
	for(i := 0; i < 50; i++) {
		sys->sleep(100);
		(ok2, nil) := sys->stat("/n/wallet/accounts");
		if(ok2 >= 0) {
			sys->sleep(200);	# let serveloop start processing
			sys->fprint(stderr, "wallet: wallet9p ready\n");
			return;
		}
	}
	sys->fprint(stderr, "wallet: wallet9p failed to start\n");
}

cleanup()
{
	raise "fail:exit";
}

themelistener()
{
	fd := sys->open("/n/ui/event", Sys->OREAD);
	if(fd == nil)
		return;
	buf := array[256] of byte;
	for(;;) {
		n := sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		ev := string buf[0:n];
		if(len ev >= 6 && ev[0:6] == "theme ")
			alt {
			themech <-= 1 => ;
			* => ;
			}
	}
}
