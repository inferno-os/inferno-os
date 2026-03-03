/*
 * ttf2subfont.c — render a TTF/OTF font range to an Inferno k8 subfont
 *
 * Uses FreeType2 FT_RENDER_MODE_NORMAL for 256-level greyscale antialiasing.
 * Output is a "new-format" Inferno k8 image + subfont header + Fontchar table,
 * identical in layout to bdf2subfont's k8 output but with real antialiasing.
 *
 * Usage:
 *   ttf2subfont -p PTSIZE -r DPI -start N -end N [-info] font.ttf output.subfont
 *
 * Compile:
 *   cc -O2 -o ttf2subfont ttf2subfont.c $(pkg-config --cflags --libs freetype2)
 *
 * Binary layout written:
 *   60 bytes:  Inferno image header  "k8          " + rect fields (5×12 bytes)
 *   W×H bytes: greyscale pixel strip, 1 byte/pixel, row-major, 255=ink 0=bg
 *   36 bytes:  subfont info header   "%11d %11d %11d " n height ascent
 *   6*(n+1) bytes: Fontchar table    x_lo x_hi top bottom left width
 *     x     = uint16 LE  x-offset of glyph strip region
 *     top   = uint8      first ink row from strip top
 *     bottom= uint8      first row past ink (exclusive)
 *     left  = int8       left bearing (signed, pen-to-left-edge-of-ink)
 *     width = uint8      advance width in pixels
 */

#include <ft2build.h>
#include FT_FREETYPE_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* ---- helpers ------------------------------------------------------------ */

static void
die(const char *msg)
{
	fprintf(stderr, "ttf2subfont: %s\n", msg);
	exit(1);
}

static int
parsenum(const char *s)
{
	if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
		return (int)strtol(s, NULL, 16);
	return atoi(s);
}

static void
writeall(FILE *f, const void *buf, size_t n, const char *path)
{
	if (fwrite(buf, 1, n, f) != n) {
		fprintf(stderr, "ttf2subfont: write error: %s\n", path);
		exit(1);
	}
}

/* ---- main --------------------------------------------------------------- */

int
main(int argc, char **argv)
{
	int ptsize = 0, dpi = 72, start_cp = -1, end_cp = -1, infoonly = 0;
	const char *fontpath = NULL, *outpath = NULL;
	FT_Library  library;
	FT_Face     face;
	int         i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-p") == 0 && i+1 < argc)
			ptsize = atoi(argv[++i]);
		else if (strcmp(argv[i], "-r") == 0 && i+1 < argc)
			dpi = atoi(argv[++i]);
		else if (strcmp(argv[i], "-start") == 0 && i+1 < argc)
			start_cp = parsenum(argv[++i]);
		else if (strcmp(argv[i], "-end") == 0 && i+1 < argc)
			end_cp = parsenum(argv[++i]);
		else if (strcmp(argv[i], "-info") == 0)
			infoonly = 1;
		else if (argv[i][0] != '-') {
			if (!fontpath)     fontpath = argv[i];
			else if (!outpath) outpath  = argv[i];
		} else {
			fprintf(stderr, "ttf2subfont: unknown flag: %s\n", argv[i]);
			fprintf(stderr,
				"usage: ttf2subfont -p SIZE -r DPI "
				"-start N -end N [-info] font.ttf output\n");
			exit(1);
		}
	}

	if (ptsize <= 0 || start_cp < 0 || end_cp < start_cp || !fontpath) {
		fprintf(stderr,
			"usage: ttf2subfont -p SIZE -r DPI "
			"-start N -end N [-info] font.ttf [output]\n"
			"  N may be decimal or 0x hex\n");
		exit(1);
	}

	if (FT_Init_FreeType(&library))
		die("cannot init FreeType");
	if (FT_New_Face(library, fontpath, 0, &face))
		die("cannot load font");
	if (FT_Set_Char_Size(face, 0, (FT_F26Dot6)(ptsize * 64), dpi, dpi))
		die("cannot set char size");

	/*
	 * Derive ascent/descent using the same design-unit ratio that otf2bdf
	 * uses, so our metrics match the existing unicode.*.font manifests:
	 *
	 *   ascent  = face->ascender  × y_ppem / units_per_EM  (integer floor)
	 *   descent = (-face->descender) × y_ppem / units_per_EM
	 *
	 * face->size->metrics.ascender (scaled 26.6) gives 13 for DejaVuSans at
	 * 14pt/72DPI, but the design-unit ratio gives 12, matching FONT_ASCENT
	 * in the BDF files and the "16\t12" manifest entries.
	 */
	int ppem    = (int)face->size->metrics.y_ppem;
	int ascent  = (int)((long)face->ascender  * ppem / face->units_per_EM);
	int descent = (int)((long)(-face->descender) * ppem / face->units_per_EM);
	int height  = ascent + descent;

	fprintf(stderr,
		"ttf2subfont: range 0x%04X-0x%04X ptsize=%d dpi=%d "
		"height=%d ascent=%d\n",
		start_cp, end_cp, ptsize, dpi, height, ascent);

	if (infoonly) {
		FT_Done_Face(face);
		FT_Done_FreeType(library);
		return 0;
	}
	if (!outpath)
		die("output path required");

	int n = end_cp - start_cp + 1;

	/* ---- per-glyph data ------------------------------------------------- */

	typedef struct {
		int      valid;
		int      dwidth;   /* advance width in pixels */
		int      bbw;      /* bitmap width in pixels */
		int      bbh;      /* bitmap rows */
		int      bbx;      /* bitmap_left: pen-origin to left-edge (signed) */
		int      bby;      /* baseline to bottom-of-ink = bitmap_top - bbh */
		uint8_t *pix;      /* grey pixels, bbw×bbh, row-major, top-to-bottom */
	} Glyph;

	Glyph *glyphs = calloc(n, sizeof(Glyph));
	if (!glyphs)
		die("out of memory");

	int ngot = 0;
	for (i = 0; i < n; i++) {
		FT_UInt gi = FT_Get_Char_Index(face, (FT_ULong)(start_cp + i));
		if (gi == 0)
			continue;  /* codepoint not in this font */

		if (FT_Load_Glyph(face, gi, FT_LOAD_TARGET_MONO))
			continue;
		/*
		 * Render with greyscale antialiasing (256-level coverage).
		 * FT_LOAD_TARGET_MONO uses the mono-optimised TrueType hinting
		 * algorithm, which snaps stems aggressively to pixel boundaries.
		 * The subsequent FT_RENDER_MODE_NORMAL call still produces full
		 * 8-bit greyscale AA — the combination gives well-positioned stems
		 * with smooth AA edges rather than stems that straddle pixel rows.
		 * Empirically this roughly doubles the full-ink pixel ratio and
		 * reduces the grey-halo area by ~20%, producing visibly crisper text.
		 */
		if (FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL))
			continue;

		FT_GlyphSlot slot = face->glyph;
		FT_Bitmap   *bm   = &slot->bitmap;

		if (bm->pixel_mode != FT_PIXEL_MODE_GRAY)
			continue;  /* should never happen with NORMAL mode */

		glyphs[i].valid  = 1;
		glyphs[i].dwidth = (int)((slot->advance.x + 32) >> 6);
		glyphs[i].bbw    = (int)bm->width;
		glyphs[i].bbh    = (int)bm->rows;
		glyphs[i].bbx    = slot->bitmap_left;
		/*
		 * bitmap_top: rows from baseline to top of bitmap (positive = above
		 * baseline).  Bottom of ink = bitmap_top - rows.
		 */
		glyphs[i].bby = slot->bitmap_top - (int)bm->rows;

		ngot++;

		if (bm->width > 0 && bm->rows > 0) {
			glyphs[i].pix = malloc((size_t)bm->width * bm->rows);
			if (!glyphs[i].pix)
				die("out of memory");
			/*
			 * Copy rows; pitch may be > width or negative (bottom-up).
			 * For FT_RENDER_MODE_NORMAL pitch is almost always positive
			 * (top-to-bottom), but handle the negative case defensively.
			 */
			for (int row = 0; row < (int)bm->rows; row++) {
				uint8_t *src;
				if (bm->pitch >= 0)
					src = bm->buffer + row * bm->pitch;
				else
					src = bm->buffer + (bm->rows - 1 - row) * (-bm->pitch);
				memcpy(glyphs[i].pix + row * bm->width, src, bm->width);
			}
		}
	}

	fprintf(stderr, "ttf2subfont: %d/%d glyphs rendered\n", ngot, n);

	/* ---- strip x positions ---------------------------------------------- */

	int *xpos = calloc(n + 1, sizeof(int));
	if (!xpos)
		die("out of memory");
	xpos[0] = 0;
	for (i = 0; i < n; i++)
		xpos[i+1] = xpos[i] + (glyphs[i].valid ? glyphs[i].bbw : 0);
	int stripw = xpos[n];
	if (stripw <= 0)
		stripw = 1;  /* image must be at least 1 pixel wide */

	/* ---- build greyscale pixel strip ------------------------------------ */

	uint8_t *strip = calloc((size_t)height * stripw, 1);
	if (!strip)
		die("out of memory");

	for (i = 0; i < n; i++) {
		Glyph *g = &glyphs[i];
		if (!g->valid || !g->pix || g->bbw <= 0 || g->bbh <= 0)
			continue;

		/*
		 * Row in strip where the top of this glyph's ink lands.
		 *   top = ascent - bitmap_top = ascent - (bby + bbh)
		 * Clamp to 0 in case a glyph overshoots the ascender line.
		 */
		int top = ascent - (g->bby + g->bbh);
		if (top < 0)
			top = 0;
		int gx = xpos[i];

		for (int row = 0; row < g->bbh; row++) {
			int srow = top + row;
			if (srow >= height)
				break;
			for (int col = 0; col < g->bbw; col++)
				strip[srow * stripw + gx + col] =
					g->pix[row * g->bbw + col];
		}
	}

	/* ---- write Inferno subfont ------------------------------------------ */

	FILE *out = fopen(outpath, "wb");
	if (!out) {
		fprintf(stderr, "ttf2subfont: cannot create %s\n", outpath);
		exit(1);
	}

	/* Image header: exactly 60 bytes ("%-11s %11d %11d %11d %11d ") */
	{
		char hdr[61];
		snprintf(hdr, sizeof(hdr), "%-11s %11d %11d %11d %11d ",
			"k8", 0, 0, stripw, height);
		writeall(out, hdr, 60, outpath);
	}

	/* Greyscale pixel data */
	writeall(out, strip, (size_t)height * stripw, outpath);

	/* Subfont header: exactly 36 bytes ("%11d %11d %11d ") */
	{
		char sfhdr[37];
		snprintf(sfhdr, sizeof(sfhdr), "%11d %11d %11d ", n, height, ascent);
		writeall(out, sfhdr, 36, outpath);
	}

	/* Fontchar table: 6 bytes × (n+1) entries; entry n is the sentinel */
	{
		uint8_t *fc = calloc(6 * (n + 1), 1);
		if (!fc)
			die("out of memory");

		for (i = 0; i <= n; i++) {
			int x = xpos[i];
			int top = 0, bot = 0, left = 0, width = 0;

			if (i < n && glyphs[i].valid) {
				Glyph *g = &glyphs[i];
				top   = ascent - (g->bby + g->bbh);
				bot   = ascent - g->bby;
				left  = g->bbx;
				width = g->dwidth;
				if (top  < 0)      top  = 0;
				if (bot  > height) bot  = height;
				if (bot  < top)    bot  = top;
				/* Clamp to field widths */
				if (left  < -128) left  = -128;
				if (left  >  127) left  =  127;
				if (width <    0) width =    0;
				if (width >  255) width =  255;
			}

			int off = i * 6;
			fc[off+0] = (uint8_t)(x     & 0xFF);
			fc[off+1] = (uint8_t)((x >> 8) & 0xFF);
			fc[off+2] = (uint8_t)(top   & 0xFF);
			fc[off+3] = (uint8_t)(bot   & 0xFF);
			fc[off+4] = (uint8_t)(left  & 0xFF);  /* signed 2-complement */
			fc[off+5] = (uint8_t)(width & 0xFF);
		}

		writeall(out, fc, 6 * (n + 1), outpath);
		free(fc);
	}

	fclose(out);

	/* cleanup */
	for (i = 0; i < n; i++)
		free(glyphs[i].pix);
	free(glyphs);
	free(xpos);
	free(strip);
	FT_Done_Face(face);
	FT_Done_FreeType(library);

	return 0;
}
