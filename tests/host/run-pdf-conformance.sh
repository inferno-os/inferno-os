#!/bin/sh
#
# Run PDF conformance tests with per-suite process isolation.
# Each suite gets a fresh emu heap to avoid OOM.
#
# Usage: sh tests/host/run-pdf-conformance.sh
#

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EMU="$ROOT/emu/MacOSX/o.emu"
RESULTS="$ROOT/usr/inferno/test-pdfs/results.txt"
HEAP=1024  # MB per process

if [ ! -x "$EMU" ]; then
	echo "error: emu not found at $EMU" >&2
	exit 1
fi

# Truncate results file
: > "$RESULTS"

# Small suites — one emu each
for suite in pdf-differences poppler-test bfo-pdfa pdftest cabinet-of-horrors pdfjs verapdf; do
	echo "--- $suite ---"
	"$EMU" -r"$ROOT" -pheap=${HEAP}M /tests/pdf_conformance_test.dis -suite "$suite" 2>&1
done

# itext — batch in chunks of 1000 (~6,269 PDFs total)
for off in 0 1000 2000 3000 4000 5000 6000; do
	echo "--- itext offset=$off ---"
	"$EMU" -r"$ROOT" -pheap=${HEAP}M /tests/pdf_conformance_test.dis -suite itext -offset $off -limit 1000 2>&1
done

# Compute summary from results.txt
pass=$(grep -c '^PASS' "$RESULTS" 2>/dev/null || echo 0)
warn=$(grep -c '^WARN' "$RESULTS" 2>/dev/null || echo 0)
fail=$(grep -c '^FAIL' "$RESULTS" 2>/dev/null || echo 0)
total=$((pass + warn + fail))

echo ""
echo "=== PDF Conformance Test Results ==="
echo "PDFs:    $total tested"
if [ "$total" -gt 0 ]; then
	echo "PASS:    $pass ($((pass * 100 / total))%)"
	echo "WARN:    $warn ($((warn * 100 / total))%)"
	echo "FAIL:    $fail ($((fail * 100 / total))%)"
fi

# Append summary to results.txt
if [ "$total" -gt 0 ]; then
	cat >> "$RESULTS" <<EOSUMMARY
# === Summary ===
# PDFs: $total tested
# PASS: $pass ($((pass * 100 / total))%)
# WARN: $warn ($((warn * 100 / total))%)
# FAIL: $fail ($((fail * 100 / total))%)
EOSUMMARY
fi
