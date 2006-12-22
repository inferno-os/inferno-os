implement Units;
include "sys.m";
	sys: Sys;
include "units.m";

Dpi:	con 100;			# pixels per inch on an average display (pinched from tk)

init()
{
	sys = load Sys Sys->PATH;
}

# return length in pixels, and string equivalent;
# makes sure that string equiv is specified in absolute units
# (not in terms of percentage or font size)
# XXX give this a proper testing.
length(s: string, emsize, xsize: int, relative: string): (int, string)
{
	(n, units) := units(s);
	case units {
	Uem =>
		px := (n * emsize);
		return (px / SCALE, n2s(px) + "px");
	Uex =>
		px := (n * xsize);
		return (px / SCALE, n2s(px) + "px");
	Upx =>
		return (n / SCALE, s);
	Uin =>
		return ((n * Dpi) / SCALE, s);
	Ucm =>
		return ((n * Dpi * 100) / (2540 * SCALE), s);
	Umm =>
		return ((n * Dpi * 10) / (254 * SCALE), s);
	Upt =>
		return ((n * Dpi) / (72 * SCALE), s);
	Upc =>
		return ((n * Dpi * 12) / (72 * SCALE), s);
	Upercent or
	Unone =>
		# treat no units as relative factor.
		# the only place this is used is for "line_height" in css, i believe;
		# otherwise an unadorned number is not legal.
		if (relative == nil)
			return (0, nil);
		(rn, rs) := length(relative, 0, 0, nil);
		px := (n * rn) / SCALE;
		if (units == Upercent)
			px /= 100;
		return (px, string px + "px");
	}
	return (n / SCALE, s);
}

# return non-relative for unadorned numbers, as it's not defined so anything's ok.
isrelative(s: string): int
{
	n := len s;
	if (n < 2)
		return 0;
	if (s[n - 1] == '%')
		return 1;
	case s[n - 2:] {
	"em" or
	"ex" =>
		return 1;
	}
	return 0;
}

n2s(n: int): string
{
	(i, f) := (n / SCALE, n % SCALE);
	if (f == 0)
		return string i;
	if (f < 0)
		f = -f;
	return string i + "." + sys->sprint("%.3d", f);
}

Uem, Uex, Upx, Uin, Ucm, Umm, Upt, Upc, Upercent, Unone: con iota;

SCALE: con 1000;

units(s: string): (int, int)
{
	# XXX what should we do on error?
	if (s == nil)
		return (0, -1);
	i := 0;

	# optional leading sign
	neg := 0;
	if (s[0] == '-' || s[0] == '+') {
		neg = s[0] == '-';
		i++;
	}

	n := 0;
	for (; i < len s; i++) {
		c := s[i];
		if (c < '0' || c > '9')
			break;
		n = (n * 10) + (c - '0');
	}
	n *= SCALE;
	if (i < len s && s[i] == '.') {
		i++;
		mul := 100;
		for (; i < len s; i++) {
			c := s[i];
			if (c < '0' || c > '9')
				break;
			n += (c - '0') * mul;
			mul /= 10;
		}
	}
	units := Unone;
	if (i < len s) {
		case s[i:] {
		"em" =>
			units = Uem;
		"ex" =>
			units = Uex;
		"px" =>
			units = Upx;
		"in" =>
			units = Uin;
		"cm" =>
			units = Ucm;
		"mm" =>
			units = Umm;
		"pt" =>
			units = Upt;
		"pc" =>
			units = Upc;
		"%" =>
			units = Upercent;
		* =>
			return (0, -1);
		}
	}
	if (neg)
		n = -n;
	return (n, units);
}
