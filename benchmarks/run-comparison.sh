#!/bin/bash
#
# run-comparison.sh - Cross-Language Benchmark Comparison
#
# Runs the same 6 benchmarks in C (-O0, -O2), Go, Java, Python, Limbo JIT, and Limbo interpreter.
# Produces a side-by-side comparison table.
#
# Usage: bash benchmarks/run-comparison.sh [runs]
#   runs: number of iterations, best-of-N reported (default: 3)
#
# Run from the infernode root directory.
# Compatible with bash 3.2+ (macOS default).
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNS="${1:-3}"
TIMEOUT_SEC=300

# --- Platform detection (reused from bench.sh) ---

detect_platform() {
    local os arch
    os=$(uname -s)
    arch=$(uname -m)

    case "$os" in
        Darwin) EMUHOST=MacOSX ;;
        Linux)  EMUHOST=Linux ;;
        *)      echo "Unsupported OS: $os"; exit 1 ;;
    esac

    case "$arch" in
        aarch64|arm64) OBJTYPE=arm64 ;;
        x86_64|amd64)  OBJTYPE=amd64 ;;
        *)             echo "Unsupported arch: $arch"; exit 1 ;;
    esac

    PLATFORM="${OBJTYPE}-${EMUHOST}"
}

detect_cpu() {
    case "$(uname -s)" in
        Darwin)
            sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown"
            ;;
        Linux)
            grep -m1 'model name\|Hardware' /proc/cpuinfo 2>/dev/null | sed 's/.*: //' || echo "unknown"
            ;;
    esac
}

find_emulator() {
    EMU=""
    for name in o.emu Infernode; do
        if [ -x "$ROOT/emu/$EMUHOST/$name" ]; then
            EMU="$ROOT/emu/$EMUHOST/$name"
            break
        fi
    done
}

detect_platform

# --- Compiler detection ---

CC="${CC:-cc}"
HAVE_GO=0
if command -v go >/dev/null 2>&1; then
    HAVE_GO=1
fi

HAVE_JAVA=0
if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
    HAVE_JAVA=1
fi

HAVE_PYTHON=0
PYTHON=""
for py in python3 python; do
    if command -v "$py" >/dev/null 2>&1; then
        HAVE_PYTHON=1
        PYTHON="$py"
        break
    fi
done

find_emulator
HAVE_EMU=0
if [ -n "$EMU" ] && [ -f "$ROOT/dis/jitbench.dis" ]; then
    HAVE_EMU=1
fi

# --- Temp directory ---

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# --- Build ---

echo "=== Cross-Language Benchmark Comparison ==="
echo "Platform: $PLATFORM ($(detect_cpu))"
echo "Date:     $(date -Iseconds 2>/dev/null || date)"
echo "Runs:     $RUNS (best-of-N)"
echo ""

echo "--- Compiling ---"

echo -n "C -O0: "
if $CC -O0 -o "$TMPDIR/jitbench_O0" "$SCRIPT_DIR/jitbench.c" 2>/dev/null; then
    echo "OK"
    HAVE_C_O0=1
else
    echo "FAILED"
    HAVE_C_O0=0
fi

echo -n "C -O2: "
if $CC -O2 -o "$TMPDIR/jitbench_O2" "$SCRIPT_DIR/jitbench.c" 2>/dev/null; then
    echo "OK"
    HAVE_C_O2=1
else
    echo "FAILED"
    HAVE_C_O2=0
fi

echo -n "Go:    "
if [ "$HAVE_GO" -eq 1 ]; then
    if go build -o "$TMPDIR/jitbench_go" "$SCRIPT_DIR/jitbench.go" 2>/dev/null; then
        echo "OK"
    else
        echo "FAILED"
        HAVE_GO=0
    fi
else
    echo "SKIPPED (go not found)"
fi

echo -n "Java:  "
if [ "$HAVE_JAVA" -eq 1 ]; then
    if javac -d "$TMPDIR" "$SCRIPT_DIR/JITBench.java" 2>/dev/null; then
        echo "OK"
    else
        echo "FAILED"
        HAVE_JAVA=0
    fi
else
    echo "SKIPPED (javac not found)"
fi

echo -n "Python:"
if [ "$HAVE_PYTHON" -eq 1 ]; then
    echo " OK ($($PYTHON --version 2>&1))"
else
    echo " SKIPPED (python3 not found)"
fi

echo -n "Limbo: "
if [ "$HAVE_EMU" -eq 1 ]; then
    echo "OK ($EMU)"
else
    if [ -z "$EMU" ]; then
        echo "SKIPPED (no emulator binary)"
    else
        echo "SKIPPED (dis/jitbench.dis not found)"
    fi
fi

echo ""

# --- Benchmark names ---

BENCH_COUNT=6

# --- Parse benchmark output to a 7-line file (6 benchmarks + total) ---

parse_to_file() {
    local infile="$1" outfile="$2"
    {
        # Integer Arithmetic
        grep -A1 "Integer Arithmetic" "$infile" | grep "Time:" | grep -o '[0-9]* ms' | grep -o '[0-9]*' || echo "0"
        # Loop with Array Access
        grep -A1 "Loop with Array Access" "$infile" | grep "Time:" | grep -o '[0-9]* ms' | grep -o '[0-9]*' || echo "0"
        # Function Calls
        grep -A1 "Function Calls" "$infile" | grep "Time:" | grep -o '[0-9]* ms' | grep -o '[0-9]*' || echo "0"
        # Fibonacci
        grep -A1 "Fibonacci" "$infile" | grep "Time:" | grep -o '[0-9]* ms' | grep -o '[0-9]*' || echo "0"
        # Sieve of Eratosthenes
        grep -A1 "Sieve of Eratosthenes" "$infile" | grep "Time:" | grep -o '[0-9]* ms' | grep -o '[0-9]*' || echo "0"
        # Nested Loops
        grep -A1 "Nested Loops" "$infile" | grep "Time:" | grep -o '[0-9]* ms' | grep -o '[0-9]*' || echo "0"
        # Total
        grep "Total Time:" "$infile" | grep -o '[0-9]*' || echo "0"
    } > "$outfile"
}

make_empty_vals() {
    local outfile="$1"
    for i in 1 2 3 4 5 6 7; do echo "—"; done > "$outfile"
}

# Read line N (1-indexed) from a file
val() {
    sed -n "${2}p" "$1"
}

# --- Run a contestant multiple times, keep best total ---

run_contestant() {
    local label="$1"
    shift
    local best_total=999999999
    local best_file=""

    for run in $(seq 1 "$RUNS"); do
        local outfile="$TMPDIR/${label}_run${run}.txt"
        echo -n "  $label run $run/$RUNS... "

        timeout "$TIMEOUT_SEC" "$@" > "$outfile" 2>&1 || true

        if grep -q "Total Time:" "$outfile" 2>/dev/null; then
            local total
            total=$(grep "Total Time:" "$outfile" | grep -o '[0-9]*' || echo "999999999")
            echo "${total} ms"
            if [ "$total" -lt "$best_total" ]; then
                best_total=$total
                best_file=$outfile
            fi
        else
            echo "FAILED"
        fi
        sleep 1
    done

    BEST_TOTAL=$best_total
    if [ -n "$best_file" ]; then
        BEST_FILE="$best_file"
    else
        BEST_FILE=""
    fi
}

# --- Run all contestants ---

echo "--- Running Benchmarks ---"
echo ""

C_O0_FILE=""; C_O2_FILE=""; GO_FILE=""; JAVA_FILE=""; PYTHON_FILE=""; JIT_FILE=""; INTERP_FILE=""

if [ "$HAVE_C_O0" -eq 1 ]; then
    run_contestant "C_O0" "$TMPDIR/jitbench_O0"
    C_O0_FILE=$BEST_FILE
    echo ""
fi

if [ "$HAVE_C_O2" -eq 1 ]; then
    run_contestant "C_O2" "$TMPDIR/jitbench_O2"
    C_O2_FILE=$BEST_FILE
    echo ""
fi

if [ "$HAVE_GO" -eq 1 ]; then
    run_contestant "Go" "$TMPDIR/jitbench_go"
    GO_FILE=$BEST_FILE
    echo ""
fi

if [ "$HAVE_JAVA" -eq 1 ]; then
    run_contestant "Java" java -cp "$TMPDIR" JITBench
    JAVA_FILE=$BEST_FILE
    echo ""
fi

if [ "$HAVE_PYTHON" -eq 1 ]; then
    run_contestant "Python" "$PYTHON" "$SCRIPT_DIR/jitbench.py"
    PYTHON_FILE=$BEST_FILE
    echo ""
fi

if [ "$HAVE_EMU" -eq 1 ]; then
    EMUROOT="-r$ROOT"

    # The emulator doesn't exit after running a dis file, so use a shorter
    # timeout. The benchmark completes in well under 60s; timeout then kills
    # the lingering emulator process.
    SAVED_TIMEOUT=$TIMEOUT_SEC
    TIMEOUT_SEC=60

    run_contestant "Limbo_JIT" "$EMU" "$EMUROOT" -c1 dis/jitbench.dis
    JIT_FILE=$BEST_FILE
    echo ""

    run_contestant "Limbo_Interp" "$EMU" "$EMUROOT" -c0 dis/jitbench.dis
    INTERP_FILE=$BEST_FILE
    echo ""

    TIMEOUT_SEC=$SAVED_TIMEOUT
fi

# --- Parse best-run results into per-contestant files ---

C_O0_V="$TMPDIR/vals_c_o0"; C_O2_V="$TMPDIR/vals_c_o2"; GO_V="$TMPDIR/vals_go"
JAVA_V="$TMPDIR/vals_java"; PYTHON_V="$TMPDIR/vals_python"
JIT_V="$TMPDIR/vals_jit"; INTERP_V="$TMPDIR/vals_interp"

if [ -n "$C_O0_FILE" ] && [ -f "$C_O0_FILE" ]; then parse_to_file "$C_O0_FILE" "$C_O0_V"; else make_empty_vals "$C_O0_V"; fi
if [ -n "$C_O2_FILE" ] && [ -f "$C_O2_FILE" ]; then parse_to_file "$C_O2_FILE" "$C_O2_V"; else make_empty_vals "$C_O2_V"; fi
if [ -n "$GO_FILE" ] && [ -f "$GO_FILE" ]; then parse_to_file "$GO_FILE" "$GO_V"; else make_empty_vals "$GO_V"; fi
if [ -n "$JAVA_FILE" ] && [ -f "$JAVA_FILE" ]; then parse_to_file "$JAVA_FILE" "$JAVA_V"; else make_empty_vals "$JAVA_V"; fi
if [ -n "$PYTHON_FILE" ] && [ -f "$PYTHON_FILE" ]; then parse_to_file "$PYTHON_FILE" "$PYTHON_V"; else make_empty_vals "$PYTHON_V"; fi
if [ -n "$JIT_FILE" ] && [ -f "$JIT_FILE" ]; then parse_to_file "$JIT_FILE" "$JIT_V"; else make_empty_vals "$JIT_V"; fi
if [ -n "$INTERP_FILE" ] && [ -f "$INTERP_FILE" ]; then parse_to_file "$INTERP_FILE" "$INTERP_V"; else make_empty_vals "$INTERP_V"; fi

# --- Results table ---

BENCH_NAMES="Integer Arithmetic
Loop with Array Access
Function Calls
Fibonacci
Sieve of Eratosthenes
Nested Loops"

echo "=============================================================="
echo "  Cross-Language Benchmark Comparison (best of $RUNS)"
echo "=============================================================="
echo "Platform: $PLATFORM ($(detect_cpu))"
echo ""

# Header
printf "  %-24s" "Benchmark"
[ "$HAVE_C_O2" -eq 1 ] && printf " %10s" "C -O2"
[ "$HAVE_C_O0" -eq 1 ] && printf " %10s" "C -O0"
[ "$HAVE_GO" -eq 1 ] && printf " %10s" "Go"
[ "$HAVE_JAVA" -eq 1 ] && printf " %10s" "Java"
[ "$HAVE_PYTHON" -eq 1 ] && printf " %10s" "Python"
[ "$HAVE_EMU" -eq 1 ] && printf " %12s %12s" "Limbo JIT" "Limbo Interp"
echo ""

# Separator
printf "  %-24s" "------------------------"
[ "$HAVE_C_O2" -eq 1 ] && printf " %10s" "----------"
[ "$HAVE_C_O0" -eq 1 ] && printf " %10s" "----------"
[ "$HAVE_GO" -eq 1 ] && printf " %10s" "----------"
[ "$HAVE_JAVA" -eq 1 ] && printf " %10s" "----------"
[ "$HAVE_PYTHON" -eq 1 ] && printf " %10s" "----------"
[ "$HAVE_EMU" -eq 1 ] && printf " %12s %12s" "------------" "------------"
echo ""

# Per-benchmark rows (lines 1-6)
line=0
echo "$BENCH_NAMES" | while IFS= read -r bench; do
    line=$((line + 1))
    printf "  %-24s" "$bench"
    [ "$HAVE_C_O2" -eq 1 ] && printf " %8s ms" "$(val "$C_O2_V" $line)"
    [ "$HAVE_C_O0" -eq 1 ] && printf " %8s ms" "$(val "$C_O0_V" $line)"
    [ "$HAVE_GO" -eq 1 ] && printf " %8s ms" "$(val "$GO_V" $line)"
    [ "$HAVE_JAVA" -eq 1 ] && printf " %8s ms" "$(val "$JAVA_V" $line)"
    [ "$HAVE_PYTHON" -eq 1 ] && printf " %8s ms" "$(val "$PYTHON_V" $line)"
    if [ "$HAVE_EMU" -eq 1 ]; then
        printf " %10s ms" "$(val "$JIT_V" $line)"
        printf " %10s ms" "$(val "$INTERP_V" $line)"
    fi
    echo ""
done

# Total row (line 7)
echo ""
printf "  %-24s" "TOTAL"
[ "$HAVE_C_O2" -eq 1 ] && printf " %8s ms" "$(val "$C_O2_V" 7)"
[ "$HAVE_C_O0" -eq 1 ] && printf " %8s ms" "$(val "$C_O0_V" 7)"
[ "$HAVE_GO" -eq 1 ] && printf " %8s ms" "$(val "$GO_V" 7)"
[ "$HAVE_JAVA" -eq 1 ] && printf " %8s ms" "$(val "$JAVA_V" 7)"
[ "$HAVE_PYTHON" -eq 1 ] && printf " %8s ms" "$(val "$PYTHON_V" 7)"
if [ "$HAVE_EMU" -eq 1 ]; then
    printf " %10s ms" "$(val "$JIT_V" 7)"
    printf " %10s ms" "$(val "$INTERP_V" 7)"
fi
echo ""
echo ""

# --- Speedup ratios vs C -O0 (if available) ---

c_o0_total=$(val "$C_O0_V" 7)
if [ "$HAVE_C_O0" -eq 1 ] && [ "$c_o0_total" != "—" ] && [ "$c_o0_total" -gt 0 ] 2>/dev/null; then
    echo "Speedup vs C -O0 (total):"

    v=$(val "$C_O2_V" 7)
    if [ "$HAVE_C_O2" -eq 1 ] && [ "$v" != "—" ] && [ "$v" -gt 0 ] 2>/dev/null; then
        sp=$(( (c_o0_total * 100) / v ))
        printf "  C -O2:        %d.%02dx\n" $((sp / 100)) $((sp % 100))
    fi

    v=$(val "$GO_V" 7)
    if [ "$HAVE_GO" -eq 1 ] && [ "$v" != "—" ] && [ "$v" -gt 0 ] 2>/dev/null; then
        sp=$(( (c_o0_total * 100) / v ))
        printf "  Go:           %d.%02dx\n" $((sp / 100)) $((sp % 100))
    fi

    v=$(val "$JAVA_V" 7)
    if [ "$HAVE_JAVA" -eq 1 ] && [ "$v" != "—" ] && [ "$v" -gt 0 ] 2>/dev/null; then
        sp=$(( (c_o0_total * 100) / v ))
        printf "  Java:         %d.%02dx\n" $((sp / 100)) $((sp % 100))
    fi

    v=$(val "$PYTHON_V" 7)
    if [ "$HAVE_PYTHON" -eq 1 ] && [ "$v" != "—" ] && [ "$v" -gt 0 ] 2>/dev/null; then
        sp=$(( (c_o0_total * 100) / v ))
        printf "  Python:       %d.%02dx\n" $((sp / 100)) $((sp % 100))
    fi

    v=$(val "$JIT_V" 7)
    if [ "$HAVE_EMU" -eq 1 ] && [ "$v" != "—" ] && [ "$v" -gt 0 ] 2>/dev/null; then
        sp=$(( (c_o0_total * 100) / v ))
        printf "  Limbo JIT:    %d.%02dx\n" $((sp / 100)) $((sp % 100))
    fi

    v=$(val "$INTERP_V" 7)
    if [ "$HAVE_EMU" -eq 1 ] && [ "$v" != "—" ] && [ "$v" -gt 0 ] 2>/dev/null; then
        sp=$(( (c_o0_total * 100) / v ))
        printf "  Limbo Interp: %d.%02dx\n" $((sp / 100)) $((sp % 100))
    fi

    echo ""
fi

# --- JIT vs Interpreter speedup ---

jit_total=$(val "$JIT_V" 7)
interp_total=$(val "$INTERP_V" 7)
if [ "$HAVE_EMU" -eq 1 ] && [ "$jit_total" != "—" ] && [ "$interp_total" != "—" ] \
   && [ "$jit_total" -gt 0 ] 2>/dev/null && [ "$interp_total" -gt 0 ] 2>/dev/null; then
    sp=$(( (interp_total * 100) / jit_total ))
    printf "Limbo JIT vs Interpreter: %d.%02dx speedup\n" $((sp / 100)) $((sp % 100))
    echo ""
fi

echo "=============================================================="
