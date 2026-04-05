implement RiskGauge;

#
# risk-gauge - Matrix display module for TBL4 risk metrics
#
# Reads /n/tbl4/risk (JSON), /n/tbl4/portfolio/cash,
# /n/tbl4/portfolio/total_value, /n/tbl4/portfolio/defense/status,
# and /n/tbl4/portfolio/risk/var_95.
#
# Displays labeled risk metrics with color-coded status.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	drawm: Draw;
	Display, Font, Image, Point, Rect: import drawm;

include "lucitheme.m";

include "matrix.m";

RiskGauge: module
{
	init:	fn(display: ref Display, font: ref Font, mount: string): string;
	resize:	fn(r: Rect);
	update:	fn(): int;
	draw:	fn(dst: ref Image);
	pointer:	fn(p: ref Draw->Pointer): int;
	key:	fn(k: int): int;
	retheme:	fn(display: ref Display);
	shutdown:	fn();
};

display_g: ref Display;
font_g: ref Font;
mountpath: string;
r_g: Rect;

# Metrics
total_value: string;
cash: string;
unrealized_pnl: string;
portfolio_var: string;
position_count: string;
defense_status: string;
var_95: string;

# Colours
bgcolor: ref Image;
textcol: ref Image;
dimcol: ref Image;
headcol: ref Image;
greencol: ref Image;
redcol: ref Image;
yellowcol: ref Image;
bordercol: ref Image;

ROW_SPACING: con 28;
PAD: con 10;
HDRH: con 28;

init(display: ref Display, font: ref Font, mount: string): string
{
	sys = load Sys Sys->PATH;
	drawm = load Draw Draw->PATH;

	display_g = display;
	font_g = font;
	mountpath = mount;

	total_value = "--";
	cash = "--";
	unrealized_pnl = "--";
	portfolio_var = "--";
	position_count = "--";
	defense_status = "--";
	var_95 = "--";

	loadcolors();
	return nil;
}

loadcolors()
{
	lucitheme := load Lucitheme Lucitheme->PATH;
	if(lucitheme != nil) {
		th := lucitheme->gettheme();
		bgcolor  = display_g.color(th.bg);
		textcol  = display_g.color(th.text);
		dimcol   = display_g.color(th.dim);
		headcol  = display_g.color(th.accent);
		greencol = display_g.color(th.green);
		redcol   = display_g.color(th.red);
		yellowcol= display_g.color(th.yellow);
		bordercol= display_g.color(th.border);
	} else {
		bgcolor  = display_g.color(int 16r1A1A2EFF);
		textcol  = display_g.color(int 16rDDDDDDFF);
		dimcol   = display_g.color(int 16r888888FF);
		headcol  = display_g.color(int 16r60A5FAFF);
		greencol = display_g.color(int 16r44FF44FF);
		redcol   = display_g.color(int 16rFF4444FF);
		yellowcol= display_g.color(int 16rFFFF44FF);
		bordercol= display_g.color(int 16r333355FF);
	}
}

resize(r: Rect) { r_g = r; }

update(): int
{
	readmetrics();
	return 1;
}

draw(dst: ref Image)
{
	if(dst == nil)
		return;

	dst.draw(r_g, bgcolor, nil, (0, 0));

	# Title
	titlept := Point(r_g.min.x + PAD, r_g.min.y + PAD);
	dst.text(titlept, headcol, (0, 0), font_g, "Risk");

	# Header line
	hdry := r_g.min.y + HDRH;
	dst.draw(Rect((r_g.min.x, hdry - 1), (r_g.max.x, hdry)), bordercol, nil, (0, 0));

	# Metrics
	y := hdry + PAD;
	labelx := r_g.min.x + PAD;
	valx := r_g.min.x + r_g.dx() * 55 / 100;

	# Defense Status
	drawmetric(dst, labelx, valx, y, "Defense", defense_status, defensecolor());
	y += ROW_SPACING;

	# Total Value
	drawmetric(dst, labelx, valx, y, "Total Value", "$" + total_value, textcol);
	y += ROW_SPACING;

	# Cash
	drawmetric(dst, labelx, valx, y, "Cash", "$" + cash, textcol);
	y += ROW_SPACING;

	# Unrealized P&L
	pnlcol := textcol;
	if(len unrealized_pnl > 0 && unrealized_pnl[0] == '-')
		pnlcol = redcol;
	else if(unrealized_pnl != "--" && unrealized_pnl != "0")
		pnlcol = greencol;
	drawmetric(dst, labelx, valx, y, "Unrealized P&L", "$" + unrealized_pnl, pnlcol);
	y += ROW_SPACING;

	# VaR (95%)
	drawmetric(dst, labelx, valx, y, "VaR (95%)", var_95, textcol);
	y += ROW_SPACING;

	# Portfolio VaR
	drawmetric(dst, labelx, valx, y, "Portfolio VaR", portfolio_var, textcol);
	y += ROW_SPACING;

	# Position Count
	drawmetric(dst, labelx, valx, y, "Positions", position_count, dimcol);
}

drawmetric(dst: ref Image, labelx, valx, y: int, label, value: string, valcol: ref Image)
{
	pt := Point(labelx, y);
	dst.text(pt, dimcol, (0, 0), font_g, label);
	pt.x = valx;
	dst.text(pt, valcol, (0, 0), font_g, value);
}

defensecolor(): ref Image
{
	if(defense_status == "crisis")
		return redcol;
	if(defense_status == "caution")
		return yellowcol;
	if(defense_status == "normal")
		return greencol;
	return dimcol;
}

pointer(nil: ref Draw->Pointer): int { return 0; }
key(nil: int): int { return 0; }
retheme(display: ref Display) { display_g = display; loadcolors(); }
shutdown() { }

# ── Data ────────────────────────────────────────────────────

# Read Plan 9 text: /risk has space-separated fields on one line
# Format: total_value cash unrealized_pnl portfolio_var position_count
readmetrics()
{
	content := readf(mountpath);
	if(content != nil) {
		line := trim(content);
		(ntoks, toks) := sys->tokenize(line, " \t");
		if(ntoks >= 5) {
			total_value = hd toks; toks = tl toks;
			cash = hd toks; toks = tl toks;
			unrealized_pnl = hd toks; toks = tl toks;
			portfolio_var = hd toks; toks = tl toks;
			position_count = hd toks;
		}
	}

	# Defense status and VaR are at sibling paths
	# Mount is /n/tbl4/risk, base is /n/tbl4
	basepath := mountpath;
	for(i := len basepath - 1; i >= 0; i--)
		if(basepath[i] == '/') {
			basepath = basepath[0:i];
			break;
		}

	ds := readf(basepath + "/portfolio/defense/status");
	if(ds != nil)
		defense_status = trim(ds);

	v95 := readf(basepath + "/portfolio/risk/var_95");
	if(v95 != nil)
		var_95 = trim(v95);
}

readf(path: string): string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	fd = nil;
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

trim(s: string): string
{
	end := len s;
	while(end > 0 && (s[end-1] == '\n' || s[end-1] == ' ' || s[end-1] == '\t'))
		end--;
	start := 0;
	while(start < end && (s[start] == ' ' || s[start] == '\t'))
		start++;
	return s[start:end];
}
