#!/bin/sh
#
# Fetch curated PDF test suites for conformance testing.
#
# Clones open-source PDF test repositories into usr/inferno/test-pdfs/.
# Idempotent: skips repos that are already cloned.
# Uses shallow clones (--depth 1) for speed.
#

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/usr/inferno/test-pdfs"

# Use system git to avoid Inferno's git on PATH
GIT=/usr/bin/git

echo "=== Fetching PDF Test Suites ==="
echo "Destination: $DEST"
echo ""

mkdir -p "$DEST"

clone_repo() {
	name="$1"
	url="$2"
	dir="$DEST/$name"

	if [ -d "$dir/.git" ]; then
		echo "  $name: already cloned, skipping"
		return 0
	fi

	echo "  $name: cloning $url ..."
	if $GIT clone --depth 1 "$url" "$dir" 2>&1; then
		echo "  $name: done"
	else
		echo "  $name: FAILED (skipping)"
		rm -rf "$dir"
	fi
}

# 1. pdf-differences — PDF interoperability edge cases (blend modes, fonts, clipping, etc.)
clone_repo "pdf-differences" "https://github.com/pdf-association/pdf-differences.git"

# 2. Poppler test — rendering correctness tests with reference PNGs
clone_repo "poppler-test" "https://gitlab.freedesktop.org/poppler/test.git"

# 3. BFO PDF/A suite — PDF/A-2 conformance (pass/fail labeled by ISO section)
clone_repo "bfo-pdfa" "https://github.com/bfocom/pdfa-testsuite.git"

# 4. PDFTest — reader capabilities (fonts, encryption, content commands)
clone_repo "pdftest" "https://github.com/sambitdash/PDFTest.git"

# 5. PDF Cabinet of Horrors — edge cases from format-corpus (sparse checkout)
CABINET_DIR="$DEST/cabinet-of-horrors"
if [ -d "$CABINET_DIR/.git" ]; then
	echo "  cabinet-of-horrors: already cloned, skipping"
else
	echo "  cabinet-of-horrors: sparse checkout from format-corpus ..."
	if $GIT clone --depth 1 --filter=blob:none --sparse \
		"https://github.com/openpreserve/format-corpus.git" "$CABINET_DIR" 2>&1; then
		cd "$CABINET_DIR"
		$GIT sparse-checkout set pdfCabinetOfHorrors 2>&1
		cd "$ROOT"
		echo "  cabinet-of-horrors: done"
	else
		echo "  cabinet-of-horrors: FAILED (skipping)"
		rm -rf "$CABINET_DIR"
	fi
fi

# 6. iText Java — font, layout, forms, signing, PDF/A, PDF/UA test resources
ITEXT_DIR="$DEST/itext-pdfs"
if [ -d "$ITEXT_DIR/.git" ]; then
	echo "  itext-pdfs: already cloned, skipping"
else
	echo "  itext-pdfs: sparse checkout from itext-java ..."
	if $GIT clone --depth 1 --filter=blob:none --no-checkout \
		"https://github.com/itext/itext-java.git" "$ITEXT_DIR" 2>&1; then
		cd "$ITEXT_DIR"
		$GIT sparse-checkout init --cone 2>&1
		$GIT sparse-checkout set \
			layout/src/test/resources \
			kernel/src/test/resources \
			svg/src/test/resources \
			forms/src/test/resources \
			sign/src/test/resources \
			pdfa/src/test/resources \
			barcodes/src/test/resources \
			pdfua/src/test/resources 2>&1
		$GIT checkout 2>&1
		cd "$ROOT"
		echo "  itext-pdfs: done"
	else
		echo "  itext-pdfs: FAILED (skipping)"
		rm -rf "$ITEXT_DIR"
	fi
fi

# 7. pdf.js — Mozilla's PDF viewer test corpus (sparse checkout of test/pdfs)
PDFJS_DIR="$DEST/pdfjs-pdfs"
if [ -d "$PDFJS_DIR/.git" ]; then
	echo "  pdfjs-pdfs: already cloned, skipping"
else
	echo "  pdfjs-pdfs: sparse checkout from mozilla/pdf.js ..."
	if $GIT clone --depth 1 --filter=blob:none --no-checkout \
		"https://github.com/mozilla/pdf.js.git" "$PDFJS_DIR" 2>&1; then
		cd "$PDFJS_DIR"
		$GIT sparse-checkout init --cone 2>&1
		$GIT sparse-checkout set test/pdfs 2>&1
		$GIT checkout 2>&1
		cd "$ROOT"
		echo "  pdfjs-pdfs: done"
	else
		echo "  pdfjs-pdfs: FAILED (skipping)"
		rm -rf "$PDFJS_DIR"
	fi
fi

# 8. veraPDF corpus — PDF/A validation corpus (all PDF/A flavours)
clone_repo "verapdf-corpus" "https://github.com/veraPDF/veraPDF-corpus.git"

echo ""

# Count PDFs in each suite
total=0
for dir in "$DEST"/*/; do
	name="$(basename "$dir")"
	count=$(find "$dir" -iname '*.pdf' 2>/dev/null | wc -l | tr -d ' ')
	total=$((total + count))
	echo "  $name: $count PDFs"
done

echo ""
echo "Total: $total PDFs"
echo "=== Done ==="
