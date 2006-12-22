implement Mpegio;

#
#	MPEG ISO 11172 IO module.
#

include "sys.m";
include "mpegio.m";

sys: Sys;

init()
{
	sys = load Sys Sys->PATH;
}

raisex(s: string)
{
	raise MEXCEPT + s;
}

prepare(fd: ref Sys->FD, name: string): ref Mpegi
{
	m := ref Mpegi;
	m.fd = fd;
	m.name = name;
	m.seek = 0;
	m.looked = 0;
	m.index = 0;
	m.size = 0;
	m.buff = array[MBSZ] of byte;
	return m;
}

Mpegi.startsys(m: self ref Mpegi)
{
	# 2.4.3.2
	m.xnextsc(PACK_SC);
	m.packhdr();
	m.xnextsc(SYSHD_SC);
	m.syssz = m.getw();
	m.boundmr = m.get22("boundmr");
	m.syspar = m.getw();
	if ((m.syspar & 16r20) == 0 || m.getb() != 16rFF)
		m.fmterr("syspar");
	t := m.syssz - 6;
	if (t <= 0 || (t % 3) != 0)
		m.fmterr("syssz");
	t /= 3;
	m.nstream = t;
	m.streams = array[t] of Stream;
	for (i := 0; i < t; i++) {
		v := m.getb();
		if ((v & 16r80) == 0)
			m.fmterr("streamid");
		w := m.getb();
		if ((w & 16rC0) != 16rC0)
			m.fmterr("stream mark");
		m.streams[i] = (byte v, byte ((w >> 5) & 1), ((w & 16r1F) << 8) | m.getb(), nil);
	}
}

Mpegi.packetcp(m: self ref Mpegi): int
{
	while ((c := m.nextsc()) != STREAM_EC) {
		case c {
		PACK_SC =>
			m.packhdr();
		SYSHD_SC =>
			m.syshdr();
		* =>
			if (c < STREAM_BASE)
				m.fmterr(sys->sprint("stream code %x", c));
			# 2.4.3.3
			l := m.getw();
			fd := m.getfd(c);
			if (fd != nil) {
				if (c != PRIVSTREAM2)
					l -= m.stamps();
				if (m.log != nil)
					sys->fprint(m.log, "%x %d %d\n", c & 16rFF, m.tell(), l);
				m.cpn(fd, l);
			} else
				m.skipn(l);
			return 1;
		}
	}
	return 0;
}

Mpegi.getfd(m: self ref Mpegi, c: int): ref Sys->FD
{
	id := byte c;
	n := m.nstream;
	for (i := 0; i < n; i++) {
		if (m.streams[i].id == id)
			return m.streams[i].fd;
	}
	return nil;
}

Mpegi.packhdr(m: self ref Mpegi)
{
	# 2.4.3.2
	t := m.getb();
	if ((t & 16rF1) != 16r21)
		m.fmterr("pack tag");
	m.packt0 = (t >> 1) & 7;
	v := m.getb() << 22;
	t = m.getb();
	if ((t & 1) == 0)
		m.fmterr("packt mark 1");
	v |= ((t & ~1) << 15) | (m.getb() << 7);
	t = m.getb();
	if ((t & 1) == 0)
		m.fmterr("packt mark 2");
	m.packt1 = v | (t >> 1);
	m.packmr = m.get22("packmr");
}

Mpegi.syshdr(m: self ref Mpegi)
{
	l := m.getw();
	if (l != m.syssz)
		m.fmterr("syshdr size mismatch");
	m.skipn(l);
}

Mpegi.stamps(m: self ref Mpegi): int
{
	# 2.4.3.3
	n := 1;
	while ((c := m.getb()) == 16rFF)
		n++;
	if ((c >> 6) == 1) {
		m.getb();
		c = m.getb();
		n += 2;
	}
	case c >> 4 {
	2 =>
		m.skipn(4);
		n += 4;
	3 =>
		m.skipn(9);
		n += 9;
	* =>
		if (c != 16rF)
			m.fmterr("stamps");
	}
	return n;
}

Mpegi.streaminit(m: self ref Mpegi, c: int)
{
	m.inittables();
	m.sid = c;
	s := m.peeksc();
	if (s == PACK_SC) {
		m.startsys();
		f := 0;
		id := byte m.sid;
		for (i := 0; i < m.nstream; i++) {
			if (m.streams[i].id == id) {
				f = 1;
				break;
			}
		}
		if (!f)
			m.fmterr(sys->sprint("%x: stream not found", c));
		m.sseek();
	} else if (s == SEQUENCE_SC) {
		m.sresid = -1;
		m.slim = m.size;
	} else
		m.fmterr(sys->sprint("start code = %x", s));
	m.sbits = 0;
}

Mpegi.sseek(m: self ref Mpegi)
{
	while ((c := m.nextsc()) != STREAM_EC) {
		case c {
		PACK_SC =>
			m.packhdr();
		SYSHD_SC =>
			m.syshdr();
		* =>
			if (c < STREAM_BASE)
				m.fmterr(sys->sprint("stream code %x", c));
			# 2.4.3.3
			l := m.getw();
			if (c == m.sid) {
				if (c != PRIVSTREAM2)
					l -= m.stamps();
				n := m.size - m.index;
				if (l <= n) {
					m.slim = m.index + l;
					m.sresid = 0;
				} else {
					m.slim = m.size;
					m.sresid = l - n;
				}
				return;
			} else
				m.skipn(l);
		}
	}
	m.fmterr("end of stream");
}

Mpegi.getpicture(m: self ref Mpegi, detail: int): ref Picture
{
	g := 0;
	for (;;) {
		case c := m.snextsc() {
		SEQUENCE_SC =>
			m.seqhdr();
		GROUP_SC =>
			m.grphdr();
			g = 1;
		PICTURE_SC =>
			p := m.picture(detail);
			if (g)
				p.flags |= GSTART;
			return p;
		SEQUENCE_EC =>
			return nil;
		* =>
			m.fmterr(sys->sprint("start code %x", c));
		}
	}
}

Mpegi.seqhdr(m: self ref Mpegi)
{
	# 2.4.2.3
	c := m.sgetb();
	d := m.sgetb();
	m.width = (c << 4) | (d >> 4);
	m.height = ((d & 16rF) << 8) | m.sgetb();
	c = m.sgetb();
	m.aspect = c >> 4;
	m.frames = c & 16rF;
	m.rate = m.sgetn(18);
	m.smarker();
	m.vbv = m.sgetn(10);
	m.flags = 0;
	if (m.sgetn(1))
		m.flags |= CONSTRAINED;
	if (m.sgetn(1))
		m.intra = m.getquant();
	if (m.sgetn(1))
		m.nintra = m.getquant();
	if (m.speeksc() == EXTENSION_SC)
		m.sseeksc();
	if (m.speeksc() == USER_SC)
		m.sseeksc();
}

Mpegi.grphdr(m: self ref Mpegi)
{
	# 2.4.2.4
	v := m.sgetb() << 17;
	v |= m.sgetb() << 9;
	v |= m.sgetb() << 1;
	c := m.sgetb();
	m.smpte = v | (c >> 7);
	if (c & (1 << 6))
		m.flags |= CLOSED;
	else
		m.flags &= ~CLOSED;
	if (c & (1 << 5))
		m.flags |= BROKEN;
	else
		m.flags &= ~BROKEN;
	if (m.speeksc() == EXTENSION_SC)
		m.sseeksc();
	if (m.speeksc() == USER_SC)
		m.sseeksc();
}

Mpegi.getquant(m: self ref Mpegi): array of int
{
	a := array[64] of int;
	for (i := 0; i < 64; i++)
		a[i] = m.sgetn(8);
	return a;
}

Mpegi.picture(m: self ref Mpegi, detail: int): ref Picture
{
	# 2.4.2.5
	p := ref Picture;
	p.temporal = m.sgetn(10);
	p.ptype = m.sgetn(3);
	p.vbvdelay = m.sgetn(16);
	p.flags = 0;
	if (p.ptype == PPIC || p.ptype == BPIC) {
		if (m.sgetn(1))
			p.flags |= FPFV;
		p.forwfc = m.sgetn(3);
		if (p.forwfc == 0)
			m.fmterr("forwfc");
		p.forwfc--;
		if (p.ptype == BPIC) {
			if (m.sgetn(1))
				p.flags |= FPBV;
			p.backfc = m.sgetn(3);
			if (p.backfc == 0)
				m.fmterr("backfc");
			p.backfc--;
		} else
			p.backfc = 0;
	} else {
		p.forwfc = 0;
		p.backfc = 0;
	}
	while (m.sgetn(1))
		m.sgetn(8);
	if (m.speeksc() == EXTENSION_SC)
		m.sseeksc();
	if (m.speeksc() == USER_SC)
		m.sseeksc();
	p.seek = m.tell() - 3;
	if (m.sresid < 0)
		p.eos = -1;
	else
		p.eos = m.seek - m.size + m.slim + m.sresid;
	if (detail)
		m.detail(p);
	else
		m.skipdetail();
	return p;
}

Mpegi.detail(m: self ref Mpegi, p: ref Picture)
{
	l: list of ref Slice;
	p.addr = -1;
	while ((c := m.speeksc()) >= SLICE1_SC && c <= SLICEN_SC)
		l = m.slice(p) :: l;
	if (l == nil)
		m.fmterr("slice sc");
	n := len l;
	a := array[n] of ref Slice;
	while (--n >= 0) {
		a[n] = hd l;
		l = tl l;
	}
	p.slices = a;
}

Mpegi.skipdetail(m: self ref Mpegi)
{
	while ((c := m.speeksc()) >= SLICE1_SC && c <= SLICEN_SC) {
		m.looked = 0;
		m.sseeksc();
	}
}

ESC, EOB, C0, C1, C2, C3, C4, C5, C6, C7:	con -(iota + 1);

include	"mai.tab";
include	"mbi.tab";
include	"mbp.tab";
include	"mbb.tab";
include	"motion.tab";
include	"cbp.tab";
include	"cdc.tab";
include	"ydc.tab";
include	"rl0f.tab";
include	"rl0n.tab";
include	"c0.tab";
include	"c1.tab";
include	"c2.tab";
include	"c3.tab";
include	"c4.tab";
include	"c5.tab";
include	"c6.tab";
include	"c7.tab";

mbif := array[] of {
	MB_I,
	MB_I | MB_Q,
};

mbpf := array[] of {
	MB_MF,
	MB_P,
	MB_P | MB_Q,
	MB_P | MB_MF,
	MB_P | MB_MF | MB_Q,
	MB_I,
	MB_I | MB_Q,
};

mbbf := array[] of {
	MB_MF,
	MB_MB,
	MB_MB | MB_MF,
	MB_P | MB_MF,
	MB_P | MB_MF | MB_Q,
	MB_P | MB_MB,
	MB_P | MB_MB | MB_Q,
	MB_P | MB_MB | MB_MF,
	MB_P | MB_MB | MB_MF | MB_Q,
	MB_I,
	MB_I | MB_Q,
};

c_bits := array[] of {
	c1_bits, 
	c2_bits, 
	c3_bits, 
	c4_bits, 
	c5_bits, 
	c6_bits, 
	c7_bits, 
};

c_tables: array of array of Pair;

patcode := array[] of {
	1<<5, 1<<4, 1<<3, 1<<2, 1<<1, 1<<0,
};

Mpegi.inittables()
{
	if (c_tables == nil) {
		c_tables = array[] of {
			c1_table, 
			c2_table, 
			c3_table, 
			c4_table, 
			c5_table, 
			c6_table, 
			c7_table, 
		};
	}
}

Mpegi.slice(m: self ref Mpegi, p: ref Picture): ref Slice
{
	m.snextsc();
	s := ref Slice;
	q := m.sgetn(5);
	while (m.sgetn(1))
		m.sgetn(8);
	x := p.addr;
	l: list of ref MacroBlock;
	while (m.speekn(23) != 0) {
		while (m.speekn(11) == 16rF)
			m.sbits -= 11;
		while (m.speekn(11) == 16r8) {
			x += 33;
			m.sbits -= 11;
		}
		i := m.svlc(mai_table, mai_bits, "mai");
		x += i;
		b := ref MacroBlock;
		b.addr = x;
		case p.ptype {
		IPIC =>
			b.flags = mbif[m.svlc(mbi_table, mbi_bits, "mbi")];
		PPIC =>
			b.flags = mbpf[m.svlc(mbp_table, mbp_bits, "mbp")];
		BPIC =>
			b.flags = mbbf[m.svlc(mbb_table, mbb_bits, "mbb")];
		DPIC =>
			if (!m.sgetn(1))
				m.fmterr("mbd flags");
			b.flags = MB_I;
		* =>
			m.fmterr("ptype");
		}
		if (b.flags & MB_Q)
			q = m.sgetn(5);
		b.qscale = q;
		if (b.flags & MB_MF) {
			i = m.svlc(motion_table, motion_bits, "mhfc");
			b.mhfc = i;
			if (i != 0 && p.forwfc != 0)
				b.mhfr = m.sgetn(p.forwfc);
			i = m.svlc(motion_table, motion_bits, "mvfc");
			b.mvfc = i;
			if (i != 0 && p.forwfc != 0)
				b.mvfr = m.sgetn(p.forwfc);
		}
		if (b.flags & MB_MB) {
			i = m.svlc(motion_table, motion_bits, "mhbc");
			b.mhbc = i;
			if (i != 0 && p.backfc != 0)
				b.mhbr = m.sgetn(p.backfc);
			i = m.svlc(motion_table, motion_bits, "mvbc");
			b.mvbc = i;
			if (i != 0 && p.backfc != 0)
				b.mvbr = m.sgetn(p.backfc);
		}
		if (b.flags & MB_I)
			i = 16r3F;
		else if (b.flags & MB_P)
			i = m.svlc(cbp_table, cbp_bits, "cbp");
		else
			i = 0;
		b.pcode = i;
		if (i != 0) {
			b.rls = array[6] of array of Pair;
			for (j := 0; j < 6; j++) {
				if (i & patcode[j]) {
					rl: list of Pair;
					R, L: int;
					if (b.flags & MB_I) {
						if (j < 4)
							L = m.svlc(ydc_table, ydc_bits, "ydc");
						else
							L = m.svlc(cdc_table, cdc_bits, "cdc");
						if (L != 0)
							L = m.sdiffn(L);
						rl = (0, L) :: nil;
					} else
						rl = m.sdct(rl0f_table, "rl0f") :: nil;
					if (p.ptype != DPIC) {
						for (;;) {
							(R, L) = m.sdct(rl0n_table, "rl0n");
							if (R == EOB)
								break;
							rl = (R, L) :: rl;
						}
					}
					mn := len rl;
					ma := array[mn] of Pair;
					while (--mn >= 0) {
						ma[mn] = hd rl;
						rl = tl rl;
					}
					b.rls[j] = ma;
				}
			}
		}
		l = b :: l;
	}
	p.addr = x;
	if (l == nil)
		m.fmterr("macroblock");
	n := len l;
	a := array[n] of ref MacroBlock;
	while (--n >= 0) {
		a[n] = hd l;
		l = tl l;
	}
	s.blocks = a;
	return s;
}

Mpegi.cpn(m: self ref Mpegi, fd: ref Sys->FD, n: int)
{
	for (;;) {
		r := m.size - m.index;
		if (r >= n) {
			if (sys->write(fd, m.buff[m.index:], n) < 0)
				raisex(X_WRITE);
			m.index += n;
			return;
		}
		if (sys->write(fd, m.buff[m.index:], r) < 0)
			raisex(X_WRITE);
		m.fill();
		n -= r;
	}
}

Mpegi.fill(m: self ref Mpegi)
{
	n := sys->read(m.fd, m.buff, MBSZ);
	if (n < 0) {
		m.error = sys->sprint("%r");
		raisex(X_READ);
	}
	if (n == 0)
		raisex(X_EOF);
	m.seek += n;
	m.index = 0;
	m.size = n;
}

Mpegi.tell(m: self ref Mpegi): int
{
	return m.seek - m.size + m.index;
}

Mpegi.skipn(m: self ref Mpegi, n: int)
{
	for (;;) {
		r := m.size - m.index;
		if (r >= n) {
			m.index += n;
			return;
		}
		n -= r;
		m.fill();
	}
}

Mpegi.getb(m: self ref Mpegi): int
{
	if (m.index == m.size)
		m.fill();
	return int m.buff[m.index++];
}

Mpegi.getw(m: self ref Mpegi): int
{
	t := m.getb();
	return (t << 8) | m.getb();
}

Mpegi.get22(m: self ref Mpegi, s: string): int
{
	u := m.getb();
	if ((u & 16r80) == 0)
		m.fmterr(s + " mark 0");
	v := m.getb();
	w := m.getb();
	if ((w & 1) == 0)
		m.fmterr(s + " mark 1");
	return ((u & 16r7F)  << 15) | (v << 7) | (w >> 1);
}

Mpegi.getsc(m: self ref Mpegi): int
{
	if (m.getb() != 0 || m.getb() != 0)
		m.fmterr("start code 0s");
	while ((c := m.getb()) == 0)
		;
	if (c != 1)
		m.fmterr("start code 1");
	return 16r100 | m.getb();
}

Mpegi.nextsc(m: self ref Mpegi): int
{
	if (m.looked) {
		m.looked = 0;
		return m.value;
	} else
		return m.getsc();
}

Mpegi.peeksc(m: self ref Mpegi): int
{
	if (!m.looked) {
		m.value = m.getsc();
		m.looked = 1;
	}
	return m.value;
}

Mpegi.xnextsc(m: self ref Mpegi, x: int)
{
	c := m.nextsc();
	if (c != x)
		m.fmterr(sys->sprint("startcode %x, got %x", x, c));
}

Mpegi.sfill(m: self ref Mpegi)
{
	r := m.sresid;
	if (r < 0) {
		m.fill();
		m.slim = m.size;
	} else if (r > 0) {
		m.fill();
		if (r <= m.size) {
			m.slim = r;
			m.sresid = 0;
		} else {
			m.slim = m.size;
			m.sresid = r - m.size;
		}
	} else
		m.sseek();
}

bits := array[] of {
	0,
	16r1, 16r3, 16r7, 16rF,
	16r1F, 16r3F, 16r7F, 16rFF,
	16r1FF, 16r3FF, 16r7FF, 16rFFF,
	16r1FFF, 16r3FFF, 16r7FFF, 16rFFFF,
	16r1FFFF, 16r3FFFF, 16r7FFFF, 16rFFFFF,
	16r1FFFFF, 16r3FFFFF, 16r7FFFFF, 16rFFFFFF,
	16r1FFFFFF, 16r3FFFFFF, 16r7FFFFFF, 16rFFFFFFF,
	16r1FFFFFFF, 16r3FFFFFFF, 16r7FFFFFFF, int 16rFFFFFFFF,
};

sign := array[] of {
	0,
	16r1, 16r2, 16r4, 16r8,
	16r10, 16r20, 16r40, 16r80,
};

Mpegi.sgetn(m: self ref Mpegi, n: int): int
{
	b := m.sbits;
	v := m.svalue;
	if (b < n) {
		do {
			v = (v << 8) | m.sgetb();
			b += 8;
		} while (b < n);
		m.svalue = v;
	}
	b -= n;
	m.sbits = b;
	return (v >> b) & bits[n];
}

Mpegi.sdiffn(m: self ref Mpegi, n: int): int
{
	i := m.sgetn(n);
	if (i & sign[n])
		return i;
	else
		return i - bits[n];
}

Mpegi.speekn(m: self ref Mpegi, n: int): int
{
	b := m.sbits;
	v := m.svalue;
	if (b < n) {
		do {
			v = (v << 8) | m.sgetb();
			b += 8;
		} while (b < n);
		m.sbits = b;
		m.svalue = v;
	}
	return (v >> (b - n)) & bits[n];
}

Mpegi.sgetb(m: self ref Mpegi): int
{
	if (m.index == m.slim)
		m.sfill();
	return int m.buff[m.index++];
}

Mpegi.smarker(m: self ref Mpegi)
{
	if (!m.sgetn(1))
		m.fmterr("marker");
}

Mpegi.sgetsc(m: self ref Mpegi): int
{
	b := m.sbits;
	if (b >= 8) {
		if (b >= 16) {
			if (b >= 24) {
				case m.svalue & 16rFFFFFF {
				0 =>
					break;
				1 =>
					m.sbits = 0;
					return 16r100 | m.sgetb();
				* =>
					m.fmterr("start code 0s - 3");
				}
			} else if ((m.svalue & 16rFFFF) != 0)
				m.fmterr("start code 0s - 2");
		} else if ((m.svalue & 16rFF) != 0 || m.sgetb() != 0)
			m.fmterr("start code 0s - 1");
	} else if (m.sgetb() != 0 || m.sgetb() != 0)
		m.fmterr("start code 0s");
	m.sbits = 0;
	while ((c := m.sgetb()) == 0)
		;
	if (c != 1)
		m.fmterr("start code 1");
	return 16r100 | m.sgetb();
}

Mpegi.snextsc(m: self ref Mpegi): int
{
	if (m.looked) {
		m.looked = 0;
		return m.value;
	} else
		return m.sgetsc();
}

Mpegi.speeksc(m: self ref Mpegi): int
{
	if (!m.looked) {
		m.value = m.sgetsc();
		m.looked = 1;
	}
	return m.value;
}

Mpegi.sseeksc(m: self ref Mpegi)
{
	n := 0;
	for (;;) {
		case m.sgetb() {
		0 =>
			n++;
		1 =>
			if (n >= 2) {
				m.value = 16r100 | m.sgetb();
				m.looked = 1;
				return;
			}
			n = 0;
		* =>
			n = 0;
		}
	}
}

Mpegi.svlc(m: self ref Mpegi, a: array of Pair, n: int, s: string): int
{
	(b, v) := a[m.speekn(n)];
	if (v == UNDEF)
		m.fmterr(s + " vlc");
	m.sbits -= b;
	return v;
}

Mpegi.sdct(m: self ref Mpegi, a: array of Triple, s: string): Pair
{
	(b, l, r) := a[m.speekn(rl0f_bits)];
	m.sbits -= b;
	if (r < 0) {
		case r {
		EOB =>
			break;
		ESC =>
			r = m.sgetn(6);
			l = m.sgetn(8);
			if (l == 0) {
				l = m.sgetn(8);
				if (l < 128)
					m.fmterr(s + " esc +7");
			} else if (l == 128) {
				l = m.sgetn(8) - 256;
				if (l > -128)
					m.fmterr(s + " esc -7");
			} else
				l = (l << 24) >> 24;
		C0 =>
			(b, l, r) = c0_table[m.speekn(c0_bits)];
			if (r == UNDEF)
				m.fmterr(s + " c0 vlc");
			m.sbits -= b;
		* =>
			r = C1 - r;
			(l, r) = c_tables[r][m.sgetn(c_bits[r])];
		}
	}
	return (r, l);
}

Mpegi.fmterr(m: self ref Mpegi, s: string)
{
	m.error = s;
	raisex(X_FORMAT);
}
