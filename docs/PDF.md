# PDF Module

Infernode includes a native PDF parser and renderer written entirely in Limbo.
It can open PDF files, extract text, and render pages to Draw images — all
within the Inferno environment with no external dependencies (aside from an
optional host-side `pdftoppm` fallback in the Xenith integration).

The implementation spans two modules with no external dependencies:

- **`pdf.b`** (6,300 lines) — PDF parser, content stream interpreter, page
  renderer, text extractor, encryption/decryption
- **`outlinefont.b`** (2,400 lines) — CFF/Type 2 and TrueType font parser,
  charstring interpreter, glyph rasterizer

## API

### PDF Module

```
include "pdf.m";
    pdf: PDF;
    Doc: import pdf;

pdf = load PDF PDF->PATH;
pdf->init(display);

(doc, err) := pdf->open(data, nil);       # nil = try empty password
if(doc == nil)
    sys->fprint(stderr, "open: %s\n", err);

n := doc.pagecount();
(w, h) := doc.pagesize(1);            # points (1/72 inch)
(img, err) := doc.renderpage(1, 72);   # render at 72 DPI
text := doc.extracttext(1);            # page 1 text
alltext := doc.extractall();           # all pages

doc.close();                           # release resources
```

**`Doc` methods:**

| Method | Description |
|--------|-------------|
| `close()` | Release internal state (xref, object graph, raw data). Callers should always close when done. Methods on a closed Doc return zero/nil safely. |
| `pagecount()` | Number of pages in the document. |
| `pagesize(page)` | Width and height in PDF points (72 points = 1 inch). Pages are 1-indexed. |
| `renderpage(page, dpi)` | Render a page to a `Draw->Image` (RGB24). DPI controls resolution: 72 for screen, 150+ for print. Returns `(nil, error)` on failure. |
| `extracttext(page)` | Extract Unicode text from a single page via content stream analysis and ToUnicode CMap mapping. |
| `extractall()` | Concatenate text from all pages. |
| `dumppage(page)` | Dump page object tree for debugging. |

### OutlineFont Module

```
include "outlinefont.m";
    outlinefont: OutlineFont;

outlinefont = load OutlineFont OutlineFont->PATH;
outlinefont->init(display);

(face, err) := outlinefont->open(fontdata, "cff");   # or "ttf"

gid := face.chartogid(charcode);       # encoding lookup
adv := face.drawglyph(gid, 12.0, dst, point, src);   # render at 12pt
w := face.glyphwidth(gid, 12.0);       # advance width in pixels
(h, asc, desc) := face.metrics(12.0);  # scaled metrics
```

## What It Supports

### PDF Structure
- Cross-reference tables (traditional and fallback keyword scan)
- Incremental updates (`/Prev` trailer chaining)
- Indirect object references with generation numbers
- Page tree traversal with cycle detection (depth limit 64)

### Content Streams
- Path construction: `m`, `l`, `c`, `v`, `y`, `h`, `re`
- Path painting: `f`, `f*`, `S`, `s`, `B`, `B*`, `b`, `b*`, `n`
- Clipping: `W`, `W*`
- Text: `BT`/`ET`, `Tf`, `Tm`, `Td`, `TD`, `T*`, `Tj`, `TJ`, `'`, `"`
- Color: `g`, `G`, `rg`, `RG`, `k`, `K`, `cs`, `CS`, `sc`, `SC`, `scn`, `SCN`
- Graphics state: `q`, `Q`, `cm`, `gs`, `w`, `J`, `j`, `M`, `d`
- XObjects: `Do` (Form XObjects and Image XObjects)
- Inline images: `BI`/`ID`/`EI`

### Color Spaces
- DeviceRGB, DeviceGray, DeviceCMYK (converted to RGB)
- Indexed (palette lookup)
- CalRGB (treated as sRGB)

### Fonts
- Type1 standard fonts (Times, Helvetica, Courier, Symbol, ZapfDingbats)
  mapped to built-in Vera bitmap fonts
- CFF / Type1C embedded fonts (FontFile3) — parsed and rasterized natively
  via OutlineFont module with Type 2 charstring interpreter
- TrueType embedded fonts (FontFile2) — glyf/loca/hmtx/cmap tables
- CID-keyed fonts with CIDToGIDMap
- ToUnicode CMap for text extraction (bfchar, bfrange)
- CFF Encoding tables (Format 0 and Format 1)
- Ligature expansion (fi, fl, ff, ffi, ffl)

### Encryption
- Standard security handler (RC4 and AES password-based decryption)
- V=1 (RC4, 40-bit key), V=2 (RC4, 128-bit key), V=4 (AES-128), V=5 (AES-256)
- Automatic empty-password trial (most encrypted PDFs use permissions-only encryption)
- User password authentication; owner password not needed for decryption
- Crypt filters: V2 (RC4), AESV2 (AES-128), AESV3 (AES-256)
- Object stream (ObjStm) decryption at the container level
- `open(data, "secret")` to supply a password; `open(data, nil)` tries empty

### Filters / Decompression
- FlateDecode (zlib) with PNG predictors (None, Sub, Up, Average, Paeth)
- ASCII85Decode
- ASCIIHexDecode
- DCTDecode / JPEGDecode (via Inferno's `readjpg`)

### Rendering Features
- Affine transforms (CTM composition)
- Fill and stroke with configurable colors and opacity
- Even-odd and winding number fill rules
- Clipping paths (computed as GREY8 masks)
- Soft masks (SMask from ExtGState) for non-binary transparency
- Fill and stroke opacity (`ca`, `CA` from ExtGState)
- Gradient shading (axial and radial)
- Rotated text detection and rendering (90-degree chart labels)
- Image XObjects (JPEG, raw RGB/Gray, with color space conversion)
- Form XObjects (nested content streams with independent resources)

## Known Limitations

### Not Implemented
- **Certificate-based encryption** — PDFs using `/Filter/Adobe.PubSec`
  (public-key / certificate encryption) are not supported. These are rare
  outside enterprise document management systems.
- **Blend modes** — `ColorBurn`, `ColorDodge`, `Overlay`, `Multiply`, etc.
  are parsed from ExtGState but rendered as normal (opaque compositing).
  Visual fidelity is reduced for PDFs that rely on blend effects.
- **LZW and CCITTFax filters** — streams using these older compression
  methods are silently skipped (produces blank areas).
- **Type3 fonts** — user-defined glyph procedures are not executed.
- **Annotations and forms** — AcroForm fields, widget annotations, and
  digital signatures are ignored.
- **JavaScript and actions** — no execution environment for embedded scripts.
- **Linearized PDF** — the linearization hint tables are not used; parsing
  starts from `startxref` like a non-linearized file.
- **JBIG2 image filter** — not supported (rare outside scanned documents).

### Practical Limits
- Images with raw decompressed size > 128 MB are skipped to prevent heap
  exhaustion.
- Default heap pool is 256 MB (`-pheap=256M`). Very large PDFs with many
  high-resolution images may need `-pheap=512M` or larger.
- Glyph rasterization uses `fillpoly` — complex glyphs with many control
  points are accurate but not fast.

## Conformance Testing

### Test Corpus

The test suite covers 10,302 PDFs drawn from 8 open-source repositories.
These are fetched once by `tests/host/fetch-test-pdfs.sh` (~2 GB on disk):

| Suite | Source | PDFs | Focus |
|-------|--------|------|-------|
| pdf-differences | [PDF Association](https://github.com/pdf-association/pdf-differences) | 34 | Interop edge cases: blend modes, fonts, clipping, dashing |
| poppler-test | [Poppler](https://gitlab.freedesktop.org/poppler/test) | 80 | Rendering correctness (has reference PNGs) |
| bfo-pdfa | [BFO](https://github.com/bfocom/pdfa-testsuite) | 33 | PDF/A-2 conformance, accessibility |
| pdftest | [PDFTest](https://github.com/sambitdash/PDFTest) | 58 | Reader capabilities, fonts, encryption |
| cabinet-of-horrors | [Open Preserve](https://github.com/openpreserve/format-corpus) | 24 | Degenerate streams, malformed structure |
| itext-pdfs | [iText](https://github.com/itext/itext-java) | 6,269 | Layout, forms, signing, PDF/A, PDF/UA, barcodes |
| pdfjs-pdfs | [Mozilla pdf.js](https://github.com/mozilla/pdf.js) | 897 | Mozilla's PDF viewer test corpus |
| verapdf-corpus | [veraPDF](https://github.com/veraPDF/veraPDF-corpus) | 2,907 | PDF/A validation, ISO 32000 compliance |

### Running Tests

```sh
# One-time: fetch all test suites
sh tests/host/fetch-test-pdfs.sh

# Full conformance run (runs each suite in its own emu process)
sh tests/host/run-pdf-conformance.sh

# Single suite
./emu/MacOSX/o.emu -r. -pheap=1024M \
    /tests/pdf_conformance_test.dis -suite pdfjs-pdfs

# Verbose (prints per-PDF status)
./emu/MacOSX/o.emu -r. -pheap=1024M \
    /tests/pdf_conformance_test.dis -v -suite cabinet-of-horrors
```

### Test Methodology

For each PDF, the conformance test:

1. Reads the file into a byte array
2. Calls `pdf->open(data, nil)` — parses xref, trailer, object graph; tries empty password for encrypted PDFs
3. Calls `doc.pagecount()` — fails if 0 (encrypted or unparseable)
4. Calls `doc.renderpage(1, 72)` — renders page 1 at screen resolution
5. Samples the rendered image on a 4x4 grid for non-white pixels
6. Calls `doc.extracttext(1)` — extracts text via content stream + CMap
7. Classifies result: **PASS** (rendered with content), **WARN** (rendered
   but blank), or **FAIL** (error during any step)
8. Calls `doc.close()` — releases document state

Each suite runs in a separate `emu` process with a 1 GB heap. The itext
suite (6,269 PDFs) is further batched into groups of 1,000 to stay within
memory limits. Results are written to `usr/inferno/test-pdfs/results.txt`.

### Current Results (February 2026)

```
Total:  10,302 PDFs
PASS:    9,762 (94.8%)
FAIL:      540 (5.2%)
```

**Failure breakdown:**

| Count | Category | Notes |
|------:|----------|-------|
| 206 | Password required | Encrypted PDFs requiring a non-empty password |
| 200 | Out of memory | Large images exceeding 1 GB heap (mostly itext GetImageBytesTest) |
| 46 | 0 pages | Unsupported structure or corrupted page tree |
| 45 | Unsupported encryption | Certificate-based (Adobe.PubSec) or misspelled filter |
| 14 | Corrupt xref | Fuzzed or intentionally corrupted files |
| 8 | Not a PDF | Test files that aren't actually PDFs |
| 8 | No startxref | Genuinely broken — no cross-reference table at all |
| 6 | Unsupported V=6 | Encryption revision 6 (extended AES-256) not yet implemented |
| 4 | Cannot parse Encrypt | Malformed or unusual encryption dictionaries |
| 2 | Empty file | Zero-byte test files |
| 1 | Other | Edge cases |

All 540 failures are clean error returns — no crashes, no hangs, no
undefined behavior.

**Encryption impact:** With encryption support, 51 previously-failing PDFs
(those with empty/permissions-only passwords) now open correctly. The raw
pass count decreased from 10,123 to 9,762 because 261 encrypted PDFs that
previously produced **garbled output** are now correctly **rejected** with
meaningful error messages ("password required", "unsupported filter").
This is the correct behavior — silent garbled rendering is worse than an
explicit error.

### What the Tests Do NOT Cover

- **Visual correctness** — the test checks that *something* rendered (non-white
  pixels exist), not that the output matches a reference image. A page could
  render with wrong colors or missing elements and still pass.
- **Multi-page rendering** — only page 1 is rendered. Bugs that appear on
  later pages (different fonts, images, structure) are not caught.
- **Text extraction accuracy** — the test checks that `extracttext` does not
  crash, but does not verify the extracted text against ground truth.
- **Performance** — no timing benchmarks. Some PDFs with thousands of path
  segments render slowly but correctly.

## Architecture Notes

### Document Lifecycle

`pdf->open()` parses the entire PDF into memory: the raw byte array, the
cross-reference table, and the trailer object graph are stored in a
module-global `doctab` array indexed by `Doc.idx`. The refcount GC handles
object lifetimes, but without `doc.close()` the entire document stays live
for the lifetime of the process.

Always call `doc.close()` when done — it nils the `doctab` slot, allowing
the GC to free the raw data, xref, and object graph immediately.

### Font Caching

Embedded fonts are cached in a module-global `fontcache` (by font name)
and a `facetab` in OutlineFont (by data identity). Parsed CFF/TrueType
faces are reused across pages within the same document and even across
documents if the same font appears. The glyph rasterizer maintains a
per-face, per-size cache of rendered GREY8 masks.

### Coordinate System

PDF uses a bottom-left origin with y-axis pointing up. The renderer
constructs a CTM that maps PDF coordinates to pixel coordinates (top-left
origin, y-down). The page's `MediaBox` (or `CropBox`) defines the visible
area. All rendering operations go through the CTM, so rotated pages and
non-standard coordinate systems work correctly.

### Error Recovery

The parser is designed to handle malformed PDFs gracefully:

- **Invalid startxref offset**: falls back to scanning backward for the
  `xref` keyword
- **Fuzzed xref entries**: validates object numbers and counts against file
  size
- **Circular page trees**: depth limit of 64 prevents infinite recursion
- **Corrupt fonts**: bounds-checks array indices in hmtx, cmap, and glyph
  tables
- **Decompression errors**: caught and reported without crashing

## Reproducing the Conformance Tests

The test PDFs are **not** included in the Infernode distribution — they are
fetched from upstream open-source repositories on demand. The full corpus is
~1.8 GB on disk (10,302 files). To reproduce:

```sh
# 1. Set up build environment
export ROOT=$PWD
export PATH=$PWD/MacOSX/arm64/bin:$PATH

# 2. Build the PDF module and test programs
cd appl/lib && mk install
cd ../../tests && mk install

# 3. Fetch all 8 test suites (one-time, requires git, ~1.8 GB)
sh tests/host/fetch-test-pdfs.sh

# 4. Run the full conformance suite
sh tests/host/run-pdf-conformance.sh

# 5. Inspect results
cat usr/inferno/test-pdfs/results.txt | grep '^FAIL'
```

The fetch script clones each repository with `--depth 1` (shallow) and uses
sparse checkout where possible to minimize download size. It is idempotent —
running it again skips already-cloned suites.

Test PDFs are stored under `usr/inferno/test-pdfs/` which is in `.gitignore`.
Results are written to `usr/inferno/test-pdfs/results.txt` (one line per PDF).

## Code Size

| File | Lines | Role |
|------|------:|------|
| `appl/lib/pdf.b` | 6,326 | PDF parser, renderer, text extractor, encryption |
| `appl/lib/outlinefont.b` | 2,427 | CFF + TrueType font parser, rasterizer |
| `tests/pdf_conformance_test.b` | 598 | Conformance test harness |
| `tests/pdf_test.b` | 629 | Unit tests |
| `appl/cmd/fontprobe.b` | 293 | Font inspection tool |
| `appl/cmd/pdfdiag.b` | 222 | PDF diagnostic tool |
| `tests/pdf_render_test.b` | 165 | Render integration test |
| `tests/host/fetch-test-pdfs.sh` | 135 | Corpus fetch script |
| `tests/host/run-pdf-conformance.sh` | 58 | Test orchestrator |
| `module/outlinefont.m` | 45 | Font module interface |
| `module/pdf.m` | 24 | PDF module interface |
| **Total** | **10,922** | |

The core implementation is **8,753 lines** of Limbo (pdf.b + outlinefont.b).
With tests, tools, and shell scripts the full PDF subsystem is **10,922
lines**.

## Files

| File | Description |
|------|-------------|
| `module/pdf.m` | Public API interface |
| `module/outlinefont.m` | Font module interface |
| `appl/lib/pdf.b` | PDF implementation (6,326 lines) |
| `appl/lib/outlinefont.b` | Font implementation (2,427 lines) |
| `dis/lib/pdf.dis` | Compiled PDF module |
| `dis/lib/outlinefont.dis` | Compiled font module |
| `tests/pdf_conformance_test.b` | Conformance test (discovery-based) |
| `tests/pdf_test.b` | Unit tests (parsing, object resolution) |
| `tests/pdf_render_test.b` | Render integration tests |
| `appl/cmd/pdfdiag.b` | PDF diagnostic/inspection tool |
| `appl/cmd/fontprobe.b` | Font introspection tool |
| `tests/host/run-pdf-conformance.sh` | Test orchestrator (per-suite isolation) |
| `tests/host/fetch-test-pdfs.sh` | Downloads 8 test corpora (~1.8 GB) |
