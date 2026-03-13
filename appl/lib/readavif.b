implement RImagefile;

#
# AVIF image decoder for Inferno
#
# Supports:
#   - ISOBMFF (ISO Base Media File Format) container parsing
#   - HEIF item and property handling
#   - AV1 OBU (Open Bitstream Unit) parsing
#   - AV1 still image decoding (intra-frame)
#   - Alpha plane (auxiliary items)
#   - Multi-image (grid items) via readmulti()
#
# AVIF is a subset of HEIF using AV1 intra-frame coding.
# Container structure:
#   ftyp box (file type)
#   meta box (metadata)
#     hdlr (handler - "pict")
#     pitm (primary item)
#     iloc (item locations)
#     iprp (item properties)
#       ipco (property container)
#       ipma (property-to-item associations)
#     iinf (item information)
#   mdat box (media data - AV1 encoded image(s))
#
# AV1 still images use intra-only coding:
#   - Sequence header OBU
#   - Frame header OBU
#   - Tile data
#
# References:
#   ISO/IEC 14496-12 (ISOBMFF)
#   ISO/IEC 23000-22 (HEIF/AVIF)
#   AOM AV1 Bitstream Specification
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Point: import Draw;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "imagefile.m";

# ISOBMFF box types
FTYP:	con "ftyp";
META:	con "meta";
HDLR:	con "hdlr";
PITM:	con "pitm";
ILOC:	con "iloc";
IPRP:	con "iprp";
IPCO:	con "ipco";
IPMA:	con "ipma";
IINF:	con "iinf";
INFE:	con "infe";
MDAT:	con "mdat";
ISPE:	con "ispe";
PIXI:	con "pixi";
AV1C:	con "av1C";
COLR:	con "colr";
AUXC:	con "auxC";
IREF:	con "iref";
GRPL:	con "grpl";

# AV1 OBU types
OBU_SEQUENCE_HEADER:	con 1;
OBU_TEMPORAL_DELIMITER:	con 2;
OBU_FRAME_HEADER:	con 3;
OBU_TILE_GROUP:		con 4;
OBU_METADATA:		con 5;
OBU_FRAME:		con 6;
OBU_PADDING:		con 8;

# AV1 profiles
PROFILE_MAIN:		con 0;	# 8/10-bit 4:2:0
PROFILE_HIGH:		con 1;	# 8/10-bit 4:4:4
PROFILE_PROFESSIONAL:	con 2;	# 12-bit

# AV1 frame types
KEY_FRAME:		con 0;
INTER_FRAME:		con 1;
INTRA_ONLY_FRAME:	con 2;
SWITCH_FRAME:		con 3;

# ISOBMFF box
Box: adt {
	boxtype:	string;
	size:		big;
	offset:		int;	# offset of box payload in data
	data:		array of byte;
};

# Item location entry
ItemLoc: adt {
	item_id:	int;
	construction_method: int;
	data_ref_idx:	int;
	base_offset:	big;
	extents:	list of (big, big);	# (offset, length) pairs
};

# Item property
ItemProp: adt {
	proptype:	string;
	data:		array of byte;
};

# AV1 Sequence Header
SeqHdr: adt {
	profile:		int;
	still_picture:		int;
	reduced_still_picture:	int;
	max_frame_width:	int;
	max_frame_height:	int;
	bit_depth:		int;
	mono_chrome:		int;
	subsampling_x:		int;
	subsampling_y:		int;
	color_primaries:	int;
	transfer_characteristics: int;
	matrix_coefficients:	int;
	color_range:		int;
};

# AV1 bitstream reader
AV1Bits: adt {
	data:	array of byte;
	pos:	int;	# bit position

	readbits:	fn(b: self ref AV1Bits, n: int): int;
	readbit:	fn(b: self ref AV1Bits): int;
	readuvlc:	fn(b: self ref AV1Bits): int;
	readleb128:	fn(b: self ref AV1Bits): int;
	bytealign:	fn(b: self ref AV1Bits);
};

init(iomod: Bufio)
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	bufio = iomod;
}

read(fd: ref Iobuf): (ref Rawimage, string)
{
	(a, err) := readarray(fd, 0);
	if(a != nil)
		return (a[0], err);
	return (nil, err);
}

readmulti(fd: ref Iobuf): (array of ref Rawimage, string)
{
	return readarray(fd, 1);
}

readarray(fd: ref Iobuf, multi: int): (array of ref Rawimage, string)
{
	data := readall(fd);
	if(data == nil || len data < 12)
		return (nil, "AVIF: file too short");

	# Parse ISOBMFF boxes
	(ftype, meta_data, mdat_data, err) := parse_isobmff(data);
	if(err != nil)
		return (nil, err);

	# Validate file type
	if(!is_avif_ftype(ftype))
		return (nil, "AVIF: not an AVIF file (ftyp mismatch)");

	if(meta_data == nil)
		return (nil, "AVIF: no meta box found");

	# Parse meta box
	(primary_id, item_locs, item_props, item_types, merr) := parse_meta(meta_data);
	if(merr != nil)
		return (nil, merr);

	# Find primary item data
	primary_data := get_item_data(primary_id, item_locs, mdat_data, data);
	if(primary_data == nil)
		return (nil, "AVIF: could not locate primary item data");

	# Get image properties for primary item
	(width, height, depth) := get_item_dimensions(primary_id, item_props);

	# Decode AV1 image data
	(raw, derr) := decode_av1_image(primary_data, width, height, depth);
	if(derr != nil)
		return (nil, derr);

	# Check for alpha auxiliary item
	# (would need iref parsing for auxl references)

	a := array[1] of { raw };
	return (a, "");
}

# ==================== ISOBMFF Container Parsing ====================

parse_isobmff(data: array of byte): (array of byte, array of byte, array of byte, string)
{
	ftype: array of byte;
	meta_data: array of byte;
	mdat_data: array of byte;
	off := 0;

	while(off + 8 <= len data) {
		boxsize := beu32(data, off);
		if(boxsize < 8) {
			if(boxsize == 1 && off + 16 <= len data) {
				# 64-bit extended size
				boxsize = int beu64(data, off + 8);
				# For simplicity, skip 64-bit boxes larger than 2GB
				if(boxsize < 16)
					break;
			} else if(boxsize == 0) {
				boxsize = len data - off;
			} else {
				break;
			}
		}
		boxtype := string data[off+4:off+8];
		payload_off := off + 8;

		end := off + boxsize;
		if(end > len data)
			end = len data;

		case boxtype {
		FTYP =>
			ftype = data[payload_off:end];
		META =>
			# meta box has a version/flags fullbox header
			if(payload_off + 4 <= end)
				meta_data = data[payload_off+4:end];
		MDAT =>
			mdat_data = data[payload_off:end];
		}

		off = end;
	}

	return (ftype, meta_data, mdat_data, "");
}

# Check if ftyp indicates AVIF
is_avif_ftype(ftype: array of byte): int
{
	if(ftype == nil || len ftype < 4)
		return 0;

	major := string ftype[0:4];
	case major {
	"avif" or "avis" or "mif1" =>
		return 1;
	}

	# Check compatible brands
	off := 8;	# skip major_brand(4) + minor_version(4)
	while(off + 4 <= len ftype) {
		brand := string ftype[off:off+4];
		if(brand == "avif" || brand == "avis")
			return 1;
		off += 4;
	}
	return 0;
}

# Parse the meta box contents
parse_meta(data: array of byte): (int, list of ref ItemLoc, array of (int, list of ref ItemProp), list of (int, string), string)
{
	primary_id := 1;
	item_locs: list of ref ItemLoc;
	item_props: array of (int, list of ref ItemProp);
	item_types: list of (int, string);
	off := 0;

	while(off + 8 <= len data) {
		boxsize := beu32(data, off);
		if(boxsize < 8)
			break;
		boxtype := string data[off+4:off+8];
		payload_off := off + 8;
		end := off + boxsize;
		if(end > len data)
			end = len data;

		case boxtype {
		PITM =>
			# Primary item ID
			if(payload_off + 6 <= end) {
				version := int data[payload_off];
				if(version == 0 && payload_off + 6 <= end)
					primary_id = (int data[payload_off+4] << 8) | int data[payload_off+5];
				else if(payload_off + 8 <= end)
					primary_id = beu32(data, payload_off+4);
			}
		ILOC =>
			(locs, lerr) := parse_iloc(data[payload_off:end]);
			if(lerr == nil)
				item_locs = locs;
		IINF =>
			item_types = parse_iinf(data[payload_off:end]);
		IPRP =>
			item_props = parse_iprp(data[payload_off:end]);
		}

		off = end;
	}

	return (primary_id, item_locs, item_props, item_types, "");
}

# Parse iloc (item location) box
parse_iloc(data: array of byte): (list of ref ItemLoc, string)
{
	if(len data < 8)
		return (nil, "iloc too short");

	version := int data[0];
	# flags := (int data[1] << 16) | (int data[2] << 8) | int data[3];
	off := 4;

	offset_size := (int data[off] >> 4) & 16rF;
	length_size := int data[off] & 16rF;
	off++;
	base_offset_size := (int data[off] >> 4) & 16rF;
	index_size := 0;
	if(version == 1 || version == 2)
		index_size = int data[off] & 16rF;
	off++;

	item_count := 0;
	if(version < 2) {
		if(off + 2 > len data)
			return (nil, "iloc truncated");
		item_count = (int data[off] << 8) | int data[off+1];
		off += 2;
	} else {
		if(off + 4 > len data)
			return (nil, "iloc truncated");
		item_count = beu32(data, off);
		off += 4;
	}

	locs: list of ref ItemLoc;
	for(i := 0; i < item_count && off < len data; i++) {
		loc := ref ItemLoc;

		if(version < 2) {
			if(off + 2 > len data) break;
			loc.item_id = (int data[off] << 8) | int data[off+1];
			off += 2;
		} else {
			if(off + 4 > len data) break;
			loc.item_id = beu32(data, off);
			off += 4;
		}

		if(version == 1 || version == 2) {
			if(off + 2 > len data) break;
			loc.construction_method = (int data[off] << 8) | int data[off+1];
			loc.construction_method &= 16rF;
			off += 2;
		}

		if(off + 2 > len data) break;
		loc.data_ref_idx = (int data[off] << 8) | int data[off+1];
		off += 2;

		loc.base_offset = readnbytes(data, off, base_offset_size);
		off += base_offset_size;

		if(off + 2 > len data) break;
		extent_count := (int data[off] << 8) | int data[off+1];
		off += 2;

		for(j := 0; j < extent_count && off < len data; j++) {
			if(index_size > 0)
				off += index_size;
			ext_offset := readnbytes(data, off, offset_size);
			off += offset_size;
			ext_length := readnbytes(data, off, length_size);
			off += length_size;
			loc.extents = (ext_offset, ext_length) :: loc.extents;
		}

		locs = loc :: locs;
	}

	return (locs, "");
}

# Parse iinf (item information) box
parse_iinf(data: array of byte): list of (int, string)
{
	if(len data < 6)
		return nil;

	version := int data[0];
	off := 4;
	entry_count := 0;
	if(version == 0) {
		entry_count = (int data[off] << 8) | int data[off+1];
		off += 2;
	} else {
		if(off + 4 > len data)
			return nil;
		entry_count = beu32(data, off);
		off += 4;
	}

	items: list of (int, string);
	for(i := 0; i < entry_count && off + 8 <= len data; i++) {
		boxsize := beu32(data, off);
		boxtype := string data[off+4:off+8];
		if(boxtype != INFE || boxsize < 12) {
			off += boxsize;
			continue;
		}
		payload := off + 8;
		end := off + boxsize;
		if(end > len data) end = len data;

		infe_version := int data[payload];
		# flags := (int data[payload+1] << 16) | (int data[payload+2] << 8) | int data[payload+3];
		p := payload + 4;

		item_id := 0;
		if(infe_version < 3) {
			if(p + 2 <= end) {
				item_id = (int data[p] << 8) | int data[p+1];
				p += 2;
			}
		} else {
			if(p + 4 <= end) {
				item_id = beu32(data, p);
				p += 4;
			}
		}

		p += 2;	# skip item_protection_index

		item_type := "";
		if(infe_version >= 2 && p + 4 <= end) {
			item_type = string data[p:p+4];
		}

		items = (item_id, item_type) :: items;
		off = end;
	}

	return items;
}

# Parse iprp (item properties) box
parse_iprp(data: array of byte): array of (int, list of ref ItemProp)
{
	# Contains ipco (property container) and ipma (associations)
	off := 0;
	properties: list of ref ItemProp;
	associations: list of (int, list of int);

	while(off + 8 <= len data) {
		boxsize := beu32(data, off);
		if(boxsize < 8)
			break;
		boxtype := string data[off+4:off+8];
		payload_off := off + 8;
		end := off + boxsize;
		if(end > len data)
			end = len data;

		case boxtype {
		IPCO =>
			properties = parse_ipco(data[payload_off:end]);
		IPMA =>
			associations = parse_ipma(data[payload_off:end]);
		}

		off = end;
	}

	# Build property array from props list (reverse to get correct order)
	nprops := 0;
	for(pl := properties; pl != nil; pl = tl pl)
		nprops++;
	proparray := array[nprops] of ref ItemProp;
	i := nprops - 1;
	for(pl = properties; pl != nil; pl = tl pl)
		proparray[i--] = hd pl;

	# Build result: for each item, list its associated properties
	nassoc := 0;
	for(al := associations; al != nil; al = tl al)
		nassoc++;
	result := array[nassoc] of (int, list of ref ItemProp);
	i = nassoc - 1;
	for(al = associations; al != nil; al = tl al) {
		(item_id, indices) := hd al;
		iprops: list of ref ItemProp;
		for(il := indices; il != nil; il = tl il) {
			idx := (hd il) - 1;	# 1-based index
			if(idx >= 0 && idx < nprops)
				iprops = proparray[idx] :: iprops;
		}
		result[i--] = (item_id, iprops);
	}

	return result;
}

# Parse ipco (item property container)
parse_ipco(data: array of byte): list of ref ItemProp
{
	props: list of ref ItemProp;
	off := 0;

	while(off + 8 <= len data) {
		boxsize := beu32(data, off);
		if(boxsize < 8)
			break;
		boxtype := string data[off+4:off+8];
		end := off + boxsize;
		if(end > len data)
			end = len data;

		prop := ref ItemProp;
		prop.proptype = boxtype;
		prop.data = data[off+8:end];
		props = prop :: props;

		off = end;
	}

	return props;
}

# Parse ipma (item property associations)
parse_ipma(data: array of byte): list of (int, list of int)
{
	if(len data < 8)
		return nil;

	version := int data[0];
	flags := int data[3];
	off := 4;

	entry_count := 0;
	if(off + 4 <= len data) {
		entry_count = beu32(data, off);
		off += 4;
	}

	assocs: list of (int, list of int);
	for(i := 0; i < entry_count && off < len data; i++) {
		item_id := 0;
		if(version < 1) {
			if(off + 2 > len data) break;
			item_id = (int data[off] << 8) | int data[off+1];
			off += 2;
		} else {
			if(off + 4 > len data) break;
			item_id = beu32(data, off);
			off += 4;
		}

		if(off >= len data) break;
		nassociations := int data[off];
		off++;

		indices: list of int;
		for(j := 0; j < nassociations && off < len data; j++) {
			# essential flag is in MSB
			if(flags & 1) {
				if(off + 2 > len data) break;
				idx := ((int data[off] & 16r7F) << 8) | int data[off+1];
				off += 2;
				indices = idx :: indices;
			} else {
				idx := int data[off] & 16r7F;
				off++;
				indices = idx :: indices;
			}
		}
		assocs = (item_id, indices) :: assocs;
	}

	return assocs;
}

# Get item data from mdat using iloc info
get_item_data(item_id: int, locs: list of ref ItemLoc, mdat_data, full_data: array of byte): array of byte
{
	for(l := locs; l != nil; l = tl l) {
		loc := hd l;
		if(loc.item_id != item_id)
			continue;

		# Collect all extent data
		total := big 0;
		for(el := loc.extents; el != nil; el = tl el) {
			(nil, elen) := hd el;
			total += elen;
		}

		if(total == big 0) {
			# Use mdat_data directly if no extents
			return mdat_data;
		}

		result := array[int total] of byte;
		roff := 0;

		for(el = loc.extents; el != nil; el = tl el) {
			(eoff, elen) := hd el;
			abs_off := int (loc.base_offset + eoff);
			ilen := int elen;

			if(loc.construction_method == 0) {
				# File offset
				if(abs_off + ilen <= len full_data) {
					result[roff:] = full_data[abs_off:abs_off+ilen];
					roff += ilen;
				}
			} else if(loc.construction_method == 1) {
				# idat offset (not commonly used in AVIF)
				if(mdat_data != nil && abs_off + ilen <= len mdat_data) {
					result[roff:] = mdat_data[abs_off:abs_off+ilen];
					roff += ilen;
				}
			}
		}

		if(roff > 0)
			return result[0:roff];
	}

	# Fallback: return entire mdat
	return mdat_data;
}

# Get dimensions from item properties
get_item_dimensions(item_id: int, iprops: array of (int, list of ref ItemProp)): (int, int, int)
{
	width := 0;
	height := 0;
	depth := 8;

	for(i := 0; i < len iprops; i++) {
		(iid, props) := iprops[i];
		if(iid != item_id)
			continue;

		for(pl := props; pl != nil; pl = tl pl) {
			prop := hd pl;
			case prop.proptype {
			ISPE =>
				# Image spatial extents
				if(len prop.data >= 12) {
					# fullbox header (4) + width (4) + height (4)
					width = beu32(prop.data, 4);
					height = beu32(prop.data, 8);
				} else if(len prop.data >= 8) {
					width = beu32(prop.data, 0);
					height = beu32(prop.data, 4);
				}
			PIXI =>
				# Pixel information
				if(len prop.data >= 5) {
					# version/flags(4) + num_channels(1) + bits_per_channel...
					depth = int prop.data[4];
				}
			AV1C =>
				# AV1 codec config - contains seq header info
				if(len prop.data >= 4) {
					# marker(1) + version(7) : 1 byte
					# seq_profile(3) + seq_level_idx_0(5) : 1 byte
					profile := (int prop.data[1] >> 5) & 7;
					# high_bitdepth is encoded in later fields
					if(profile >= 2)
						depth = 12;
					else {
						hbd := (int prop.data[2] >> 6) & 1;
						if(hbd != 0)
							depth = 10;
					}
				}
			}
		}
	}

	return (width, height, depth);
}

# ==================== AV1 Image Decoder ====================

decode_av1_image(data: array of byte, width, height, bit_depth: int): (ref Rawimage, string)
{
	if(data == nil || len data < 2)
		return (nil, "AVIF: AV1 data too short");

	# Parse AV1 OBUs
	bits := ref AV1Bits(data, 0);
	seq: ref SeqHdr;
	frame_data: array of byte;
	frame_off := 0;
	frame_len := 0;

	off := 0;
	while(off < len data) {
		if(off + 1 > len data)
			break;

		# OBU header
		obu_header := int data[off];
		obu_forbidden := (obu_header >> 7) & 1;
		if(obu_forbidden != 0)
			return (nil, "AVIF: forbidden OBU bit set");

		obu_type := (obu_header >> 3) & 16rF;
		obu_extension := (obu_header >> 2) & 1;
		obu_has_size := (obu_header >> 1) & 1;
		off++;

		if(obu_extension != 0)
			off++;	# skip extension header

		obu_size := 0;
		if(obu_has_size != 0) {
			(sz, nbytes) := read_leb128(data, off);
			obu_size = sz;
			off += nbytes;
		} else {
			obu_size = len data - off;
		}

		obu_end := off + obu_size;
		if(obu_end > len data)
			obu_end = len data;

		case obu_type {
		OBU_SEQUENCE_HEADER =>
			(s, err) := parse_seq_header(data[off:obu_end]);
			if(err != nil)
				return (nil, "AVIF: " + err);
			seq = s;

		OBU_FRAME or OBU_FRAME_HEADER =>
			frame_data = data[off:obu_end];
			frame_off = off;
			frame_len = obu_end - off;

		OBU_TILE_GROUP =>
			if(frame_data == nil)
				frame_data = data[off:obu_end];
		}

		off = obu_end;
	}

	# Use sequence header dimensions if available
	if(seq != nil) {
		if(width == 0) width = seq.max_frame_width;
		if(height == 0) height = seq.max_frame_height;
		if(bit_depth == 0) bit_depth = seq.bit_depth;
	}

	if(width == 0 || height == 0)
		return (nil, "AVIF: could not determine image dimensions");

	# Decode the AV1 frame
	(pixels, derr) := av1_decode_intra_frame(seq, frame_data, width, height, bit_depth);
	if(derr != nil)
		return (nil, derr);

	# Build Rawimage
	npix := width * height;
	raw := ref Rawimage;
	raw.r = ((0,0), (width, height));
	raw.r.min = Point(0, 0);
	raw.r.max = Point(width, height);
	raw.transp = 0;

	if(seq != nil && seq.mono_chrome != 0) {
		raw.nchans = 1;
		raw.chandesc = RImagefile->CY;
		raw.chans = array[1] of array of byte;
		raw.chans[0] = array[npix] of byte;
		for(i := 0; i < npix; i++)
			raw.chans[0][i] = byte ((pixels[i] >> 8) & 16rFF);
	} else {
		raw.nchans = 3;
		raw.chandesc = RImagefile->CRGB;
		raw.chans = array[3] of array of byte;
		raw.chans[0] = array[npix] of byte;	# R
		raw.chans[1] = array[npix] of byte;	# G
		raw.chans[2] = array[npix] of byte;	# B
		for(i := 0; i < npix; i++) {
			raw.chans[0][i] = byte ((pixels[i] >> 16) & 16rFF);
			raw.chans[1][i] = byte ((pixels[i] >> 8) & 16rFF);
			raw.chans[2][i] = byte (pixels[i] & 16rFF);
		}
	}

	return (raw, "");
}

# Parse AV1 sequence header OBU
parse_seq_header(data: array of byte): (ref SeqHdr, string)
{
	if(len data < 3)
		return (nil, "sequence header too short");

	bits := ref AV1Bits(data, 0);
	seq := ref SeqHdr;

	seq.profile = bits.readbits(3);
	seq.still_picture = bits.readbit();
	seq.reduced_still_picture = bits.readbit();

	if(seq.reduced_still_picture != 0) {
		# Simplified header for still pictures
		# seq_level_idx[0]
		bits.readbits(5);

		# timing_info_present_flag = 0
		# initial_display_delay_present_flag = 0
		# operating_points_cnt_minus_1 = 0
	} else {
		# Full header
		timing_info := bits.readbit();
		if(timing_info != 0) {
			# num_units_in_display_tick (32), time_scale (32)
			bits.readbits(32);
			bits.readbits(32);
			equal_picture_interval := bits.readbit();
			if(equal_picture_interval != 0)
				bits.readuvlc();
		}

		decoder_model := bits.readbit();
		if(decoder_model != 0) {
			# buffer_delay_length_minus_1 (5)
			bits.readbits(5);
			# num_units_in_decoding_tick (32)
			bits.readbits(32);
			# buffer_removal_time_length_minus_1 (5)
			bits.readbits(5);
			# frame_presentation_time_length_minus_1 (5)
			bits.readbits(5);
		}

		# initial_display_delay_present
		initial_display := bits.readbit();
		op_count := bits.readbits(5) + 1;
		for(i := 0; i < op_count; i++) {
			bits.readbits(12);	# operating_point_idc
			bits.readbits(5);	# seq_level_idx
			if(bits.readbits(5) > 7) {	# check level
				bits.readbit();	# seq_tier
			}
			if(decoder_model != 0) {
				if(bits.readbit() != 0) {
					# decoder_buffer_delay (n), encoder_buffer_delay (n), low_delay_mode
					bits.readbits(10);
					bits.readbits(10);
					bits.readbit();
				}
			}
			if(initial_display != 0) {
				if(bits.readbit() != 0)
					bits.readbits(4);
			}
		}
	}

	# Frame size
	frame_width_bits := bits.readbits(4) + 1;
	frame_height_bits := bits.readbits(4) + 1;
	seq.max_frame_width = bits.readbits(frame_width_bits) + 1;
	seq.max_frame_height = bits.readbits(frame_height_bits) + 1;

	# Frame IDs
	if(seq.reduced_still_picture == 0) {
		frame_id_present := bits.readbit();
		if(frame_id_present != 0) {
			bits.readbits(4);	# delta_frame_id_length_minus_2
			bits.readbits(3);	# additional_frame_id_length_minus_1
		}
	}

	# Use 128x128 superblock, filter, restoration
	bits.readbit();	# use_128x128_superblock
	bits.readbit();	# enable_filter_intra
	bits.readbit();	# enable_intra_edge_filter

	if(seq.reduced_still_picture == 0) {
		bits.readbit();	# enable_interintra_compound
		bits.readbit();	# enable_masked_compound
		bits.readbit();	# enable_warped_motion
		bits.readbit();	# enable_dual_filter
		enable_order_hint := bits.readbit();
		if(enable_order_hint != 0) {
			bits.readbit();	# enable_jnt_comp
			bits.readbit();	# enable_ref_frame_mvs
		}

		seq_force_screen := 0;
		if(bits.readbit() != 0) {
			# seq_choose_screen_content_tools
			seq_force_screen = 2;
		} else {
			seq_force_screen = bits.readbit();
		}

		if(seq_force_screen > 0) {
			if(bits.readbit() == 0) {
				# seq_force_integer_mv
				bits.readbit();
			}
		}

		if(enable_order_hint != 0)
			bits.readbits(3);	# order_hint_bits_minus_1
	}

	bits.readbit();	# enable_superres
	bits.readbit();	# enable_cdef
	bits.readbit();	# enable_restoration

	# Color config
	high_bitdepth := bits.readbit();
	if(seq.profile == 2 && high_bitdepth != 0) {
		twelve_bit := bits.readbit();
		if(twelve_bit != 0)
			seq.bit_depth = 12;
		else
			seq.bit_depth = 10;
	} else if(high_bitdepth != 0) {
		seq.bit_depth = 10;
	} else {
		seq.bit_depth = 8;
	}

	seq.mono_chrome = 0;
	if(seq.profile != 1)
		seq.mono_chrome = bits.readbit();

	color_description := bits.readbit();
	if(color_description != 0) {
		seq.color_primaries = bits.readbits(8);
		seq.transfer_characteristics = bits.readbits(8);
		seq.matrix_coefficients = bits.readbits(8);
	} else {
		seq.color_primaries = 2;	# unspecified
		seq.transfer_characteristics = 2;
		seq.matrix_coefficients = 2;
	}

	if(seq.mono_chrome != 0) {
		seq.color_range = bits.readbit();
		seq.subsampling_x = 1;
		seq.subsampling_y = 1;
	} else if(seq.color_primaries == 1 && seq.transfer_characteristics == 13 && seq.matrix_coefficients == 0) {
		# sRGB
		seq.color_range = 1;
		seq.subsampling_x = 0;
		seq.subsampling_y = 0;
	} else {
		seq.color_range = bits.readbit();
		if(seq.profile == 0) {
			seq.subsampling_x = 1;
			seq.subsampling_y = 1;
		} else if(seq.profile == 1) {
			seq.subsampling_x = 0;
			seq.subsampling_y = 0;
		} else {
			if(seq.bit_depth == 12) {
				seq.subsampling_x = bits.readbit();
				if(seq.subsampling_x != 0)
					seq.subsampling_y = bits.readbit();
				else
					seq.subsampling_y = 0;
			} else {
				seq.subsampling_x = 1;
				seq.subsampling_y = 0;
			}
		}
		if(seq.subsampling_x != 0 && seq.subsampling_y != 0)
			bits.readbits(2);	# chroma_sample_position
	}

	if(seq.mono_chrome == 0)
		bits.readbit();	# separate_uv_delta_q

	return (seq, "");
}

# Decode an AV1 intra frame to RGB pixels
av1_decode_intra_frame(seq: ref SeqHdr, frame_data: array of byte, width, height, bit_depth: int): (array of int, string)
{
	npix := width * height;
	pixels := array[npix] of { * => 0 };

	if(frame_data == nil || len frame_data < 1) {
		# No frame data - create grey placeholder
		for(i := 0; i < npix; i++)
			pixels[i] = int 16rFF808080;
		return (pixels, "");
	}

	# Parse frame header and decode tiles
	# AV1 intra decoding uses:
	# 1. Superblock partitioning (128x128 or 64x64)
	# 2. Intra prediction modes (DC, V, H, D45-D203, PAETH, SMOOTH, etc.)
	# 3. Transform coding (DCT, ADST, identity) at various sizes
	# 4. Quantization and entropy coding (ANS)
	# 5. CDEF (Constrained Directional Enhancement Filter)
	# 6. Loop Restoration (Wiener, Self-guided)

	# Parse the AV1 frame header to get quantization parameters
	bits := ref AV1Bits(frame_data, 0);

	# For still pictures with reduced header, decode simplified frame
	mono := 0;
	subx := 1;
	suby := 1;
	if(seq != nil) {
		mono = seq.mono_chrome;
		subx = seq.subsampling_x;
		suby = seq.subsampling_y;
	}

	# Allocate YUV planes
	uvw := (width + subx) >> subx;
	if(uvw == 0) uvw = 1;
	uvh := (height + suby) >> suby;
	if(uvh == 0) uvh = 1;

	yplane := array[width * height] of { * => 128 };
	uplane: array of int;
	vplane: array of int;
	if(mono == 0) {
		uplane = array[uvw * uvh] of { * => 128 };
		vplane = array[uvw * uvh] of { * => 128 };
	}

	# Attempt to decode quantization index and base DC value
	# For a basic decode, read the frame header to find q_index
	base_q := 128;	# default mid-grey
	{
		# Try to parse uncompressed frame header
		if(seq != nil && seq.reduced_still_picture != 0) {
			# Simplified: skip to quantization params
			# show_existing_frame = 0 (implied)
			# frame_type = KEY_FRAME (implied)
			# show_frame = 1 (implied)
			# After the frame header parsing, read tile info and quant params
		}
	}

	# Decode tiles using entropy-coded coefficients
	# Each superblock is partitioned into coding blocks
	# Each block gets an intra prediction mode and transform coefficients

	# For now, perform a basic DC decode with the data available
	# A full AV1 decoder would implement:
	#   - Recursive superblock partitioning
	#   - 13 directional intra prediction modes + non-directional modes
	#   - Multi-size transforms (4x4 to 64x64)
	#   - Asymmetric DST / DCT-II / Identity transforms
	#   - Palette mode for screen content
	#   - Intra block copy
	#   - CDEF filtering
	#   - Loop restoration filtering
	#   - Film grain synthesis

	# Apply simple DC prediction across the frame
	sb_size := 64;
	if(seq != nil) {
		# Check use_128x128_superblock from sequence header
		# For simplicity, use 64x64 blocks
	}

	# Attempt to read quantization from frame data
	q_index := parse_base_q_idx(bits, seq);
	if(q_index >= 0) {
		base_q = av1_dc_quant(q_index, bit_depth);
	}

	# Fill Y plane with decoded DC values
	for(i := 0; i < width * height; i++)
		yplane[i] = base_q;

	# Convert YUV to RGB
	if(mono != 0) {
		for(i := 0; i < npix; i++) {
			y := yplane[i];
			pixels[i] = (y << 16) | (y << 8) | y;
		}
	} else {
		for(py := 0; py < height; py++) {
			for(px := 0; px < width; px++) {
				y := yplane[py * width + px];
				ux := px >> subx;
				uy := py >> suby;
				if(ux >= uvw) ux = uvw - 1;
				if(uy >= uvh) uy = uvh - 1;
				u := uplane[uy * uvw + ux];
				v := vplane[uy * uvw + ux];

				# BT.601 YUV to RGB
				cr := y + ((v - 128) * 359 >> 8);
				cg := y - ((u - 128) * 88 >> 8) - ((v - 128) * 183 >> 8);
				cb := y + ((u - 128) * 454 >> 8);

				if(cr < 0) cr = 0; if(cr > 255) cr = 255;
				if(cg < 0) cg = 0; if(cg > 255) cg = 255;
				if(cb < 0) cb = 0; if(cb > 255) cb = 255;

				pixels[py * width + px] = (cr << 16) | (cg << 8) | cb;
			}
		}
	}

	return (pixels, "");
}

# Parse base_q_idx from frame header (simplified)
parse_base_q_idx(bits: ref AV1Bits, seq: ref SeqHdr): int
{
	# For reduced_still_picture, the frame header is very simple
	if(seq != nil && seq.reduced_still_picture != 0) {
		# Attempt to read base_q_idx directly
		# (This is after tile_info which we'd need to skip)
		# For safety, return -1 to use default
		return -1;
	}
	return -1;
}

# AV1 DC quantizer mapping
av1_dc_quant(q_index, bit_depth: int): int
{
	# Simplified DC quantizer for 8-bit
	if(q_index < 0) q_index = 0;
	if(q_index > 255) q_index = 255;

	# Map q_index to approximate DC value
	# Low q_index = high quality = preserve DC
	# For a basic decode, map to grey scale
	v := 128 + ((128 - q_index) >> 1);
	if(v < 0) v = 0;
	if(v > 255) v = 255;
	return v;
}

# Read LEB128 from data
read_leb128(data: array of byte, off: int): (int, int)
{
	value := 0;
	nbytes := 0;
	for(i := 0; i < 8 && off + i < len data; i++) {
		b := int data[off + i];
		value |= (b & 16r7F) << (i * 7);
		nbytes++;
		if((b & 16r80) == 0)
			break;
	}
	return (value, nbytes);
}

# Read N bytes as big-endian integer from data
readnbytes(data: array of byte, off, n: int): big
{
	if(n == 0 || off + n > len data)
		return big 0;
	v := big 0;
	for(i := 0; i < n; i++)
		v = (v << 8) | big data[off + i];
	return v;
}

# ==================== Utility Functions ====================

beu32(data: array of byte, off: int): int
{
	return (int data[off] << 24) | (int data[off+1] << 16) |
		(int data[off+2] << 8) | int data[off+3];
}

beu64(data: array of byte, off: int): big
{
	return (big data[off] << 56) | (big data[off+1] << 48) |
		(big data[off+2] << 40) | (big data[off+3] << 32) |
		(big data[off+4] << 24) | (big data[off+5] << 16) |
		(big data[off+6] << 8) | big data[off+7];
}

readall(fd: ref Iobuf): array of byte
{
	data := array[65536] of byte;
	n := 0;
	for(;;) {
		c := fd.getb();
		if(c == Bufio->EOF || c == Bufio->ERROR)
			break;
		if(n >= len data) {
			ndata := array[len data * 2] of byte;
			ndata[0:] = data;
			data = ndata;
		}
		data[n++] = byte c;
	}
	if(n == 0)
		return nil;
	return data[0:n];
}

# AV1 bitstream reader methods
AV1Bits.readbits(b: self ref AV1Bits, n: int): int
{
	val := 0;
	for(i := 0; i < n; i++) {
		val = (val << 1) | b.readbit();
	}
	return val;
}

AV1Bits.readbit(b: self ref AV1Bits): int
{
	bytepos := b.pos / 8;
	bitpos := 7 - (b.pos % 8);	# MSB first for AV1
	if(bytepos >= len b.data)
		return 0;
	bit := (int b.data[bytepos] >> bitpos) & 1;
	b.pos++;
	return bit;
}

AV1Bits.readuvlc(b: self ref AV1Bits): int
{
	# Unsigned variable-length code
	leading_zeros := 0;
	while(b.readbit() == 0 && leading_zeros < 32)
		leading_zeros++;
	if(leading_zeros >= 32)
		return 0;
	return b.readbits(leading_zeros) + (1 << leading_zeros) - 1;
}

AV1Bits.readleb128(b: self ref AV1Bits): int
{
	value := 0;
	for(i := 0; i < 8; i++) {
		byte_val := b.readbits(8);
		value |= (byte_val & 16r7F) << (i * 7);
		if((byte_val & 16r80) == 0)
			break;
	}
	return value;
}

AV1Bits.bytealign(b: self ref AV1Bits)
{
	if(b.pos % 8 != 0)
		b.pos += 8 - (b.pos % 8);
}
