#!/bin/bash
#
# Publication-quality benchmark runner for Go-on-Dis vs Limbo vs Native Go
#
# Compares 5 execution modes:
#   1. Native Go        (compiled with go build)
#   2. Go-on-Dis JIT    (compiled with godis, run with emu -c1)
#   3. Go-on-Dis Interp (compiled with godis, run with emu -c0)
#   4. Limbo JIT        (compiled with limbo, run with emu -c1)
#   5. Limbo Interp     (compiled with limbo, run with emu -c0)
#
# Methodology:
#   - WARMUP_RUNS warmup runs discarded per benchmark/mode (JIT warmup, cache)
#   - TIMED_RUNS  timed runs collected per benchmark/mode
#   - Statistics: mean, stddev, min, max
#   - Results saved to CSV for analysis
#
# Usage:
#   ./run.sh                    # Run all benchmarks
#   ./run.sh fib sieve          # Run specific benchmarks
#   TIMED_RUNS=10 ./run.sh      # Override number of timed runs
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
WARMUP_RUNS=${WARMUP_RUNS:-1}
TIMED_RUNS=${TIMED_RUNS:-5}
EMU_TIMEOUT="${EMU_TIMEOUT:-300}"

# Auto-detect platform
if [ -f "$ROOT/emu/Linux/o.emu" ]; then
    EMU="$ROOT/emu/Linux/o.emu"
elif [ -f "$ROOT/emu/MacOSX/o.emu" ]; then
    EMU="$ROOT/emu/MacOSX/o.emu"
else
    echo "ERROR: No emu binary found"
    exit 1
fi

if [ -x "$ROOT/Linux/arm64/bin/limbo" ]; then
    LIMBO="$ROOT/Linux/arm64/bin/limbo"
elif [ -x "$ROOT/Linux/amd64/bin/limbo" ]; then
    LIMBO="$ROOT/Linux/amd64/bin/limbo"
elif [ -x "$ROOT/MacOSX/arm64/bin/limbo" ]; then
    LIMBO="$ROOT/MacOSX/arm64/bin/limbo"
else
    echo "ERROR: Cannot find limbo compiler"
    exit 1
fi

GODIS="$ROOT/tools/godis/godis"

# Full benchmark list
ALL_BENCHMARKS="fib sieve qsort strcat matrix channel nbody spawn bsearch closure interface map_ops binary_trees spectral_norm fannkuch mandelbrot"

BENCHMARKS="$ALL_BENCHMARKS"
if [ -n "$1" ]; then
    BENCHMARKS="$*"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Output directories
OUTDIR="$SCRIPT_DIR/_build"
RESULTSDIR="$SCRIPT_DIR/_results"
mkdir -p "$OUTDIR" "$RESULTSDIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="$RESULTSDIR/bench_${TIMESTAMP}.csv"
echo "benchmark,mode,run,ms,checksum" > "$CSV_FILE"

# Result storage
declare -A MEAN STDDEV RMIN RMAX

echo "============================================================"
echo "  Go-on-Dis Benchmark Suite"
echo "  $(date)"
echo "  Platform: $(uname -m) $(uname -s) $(uname -r)"
echo "  Warmup: $WARMUP_RUNS  Timed: $TIMED_RUNS"
echo "============================================================"
echo ""

# ── Prerequisites ──────────────────────────────────────────────

ERRORS=0
if [ ! -x "$EMU" ]; then
    echo -e "${RED}ERROR: emu not found at $EMU${NC}"
    ERRORS=1
fi
if [ ! -f "$GODIS" ]; then
    echo -e "${YELLOW}Building godis compiler...${NC}"
    (cd "$ROOT/tools/godis" && go build ./cmd/godis/) || { echo -e "${RED}ERROR: failed to build godis${NC}"; ERRORS=1; }
fi
if [ ! -x "$LIMBO" ]; then
    echo -e "${RED}ERROR: limbo not found at $LIMBO${NC}"
    ERRORS=1
fi
if ! command -v go &> /dev/null; then
    echo -e "${RED}ERROR: go not found${NC}"
    ERRORS=1
fi
if [ $ERRORS -ne 0 ]; then
    echo "Fix errors above before running benchmarks."
    exit 1
fi

# ── Compilation Phase ──────────────────────────────────────────

echo -e "${BOLD}Compiling benchmarks...${NC}"

compile_errors=""

for bench in $BENCHMARKS; do
    # Native Go
    native_src="$SCRIPT_DIR/native/$bench.go"
    if [ -f "$native_src" ]; then
        if ! go build -o "$OUTDIR/${bench}_native" "$native_src" 2>/dev/null; then
            echo -e "  ${RED}FAIL${NC} native/$bench.go"
            compile_errors="$compile_errors ${bench}:native"
        fi
    fi

    # Go-on-Dis
    go_src="$SCRIPT_DIR/go/$bench.go"
    if [ -f "$go_src" ]; then
        if ! "$GODIS" -o "$OUTDIR/${bench}_go.dis" "$go_src" 2>/dev/null; then
            echo -e "  ${RED}FAIL${NC} go/$bench.go"
            compile_errors="$compile_errors ${bench}:godis"
        fi
    fi

    # Limbo
    limbo_src="$SCRIPT_DIR/limbo/$bench.b"
    if [ -f "$limbo_src" ]; then
        if ! "$LIMBO" -I "$ROOT/module" -o "$OUTDIR/${bench}_limbo.dis" "$limbo_src" 2>/dev/null; then
            echo -e "  ${RED}FAIL${NC} limbo/$bench.b"
            compile_errors="$compile_errors ${bench}:limbo"
        fi
    fi
done

if [ -n "$compile_errors" ]; then
    echo -e "${RED}Compilation failures:${NC}$compile_errors"
    echo ""
fi

echo -e "${GREEN}Compilation done.${NC}"
echo ""

# ── Helper Functions ───────────────────────────────────────────

# Extract ms and checksum from BENCH output line
# Returns "ms checksum" or empty string on error
parse_bench_line() {
    local output="$1"
    local line
    line=$(echo "$output" | grep '^BENCH ' | head -1)
    if [ -z "$line" ]; then
        echo ""
        return
    fi
    local ms=$(echo "$line" | awk '{print $3}')
    local cksum=$(echo "$line" | awk '{print $NF}')
    echo "$ms $cksum"
}

# Run emu once with a dis file
run_emu_once() {
    local dis_path="$1"
    local mode="$2"
    local inferno_path="${dis_path#$ROOT}"
    local output
    output=$(cd "$ROOT" && timeout -k 10 "$EMU_TIMEOUT" "$EMU" "-r." "$mode" "$inferno_path" 2>&1) || true
    parse_bench_line "$output"
}

# Run native binary once
run_native_once() {
    local bin="$1"
    local output
    output=$("$bin" 2>&1) || true
    parse_bench_line "$output"
}

# Run a benchmark repeatedly, return space-separated ms values
# Usage: run_repeated bench_name mode_name runner arg1 [arg2]
run_repeated() {
    local bench="$1"
    local mode_name="$2"
    local runner="$3"
    local arg1="$4"
    local arg2="$5"
    local total=$((WARMUP_RUNS + TIMED_RUNS))
    local times=""

    for ((r=0; r<total; r++)); do
        local result
        result=$($runner "$arg1" "$arg2")
        if [ -z "$result" ]; then
            echo "ERROR"
            return 1
        fi
        local ms=$(echo "$result" | awk '{print $1}')
        local cksum=$(echo "$result" | awk '{print $2}')

        if [ $r -ge $WARMUP_RUNS ]; then
            times="$times $ms"
            echo "$bench,$mode_name,$((r - WARMUP_RUNS + 1)),$ms,$cksum" >> "$CSV_FILE"
        fi
    done
    echo "$times"
}

# Compute statistics: "mean stddev min max"
compute_stats() {
    echo "$1" | tr ' ' '\n' | awk '
    NF > 0 && $1 != "" {
        v = $1 + 0
        sum += v; sumsq += v*v; n++
        if (n==1 || v < min) min = v
        if (n==1 || v > max) max = v
    }
    END {
        if (n == 0) { print "- - - -"; exit }
        mean = sum / n
        if (n > 1) { var = (sumsq - sum*sum/n) / (n-1); if (var < 0) var = 0 }
        else var = 0
        printf "%.1f %.1f %d %d\n", mean, sqrt(var), min, max
    }'
}

# Format a result cell for the summary table: "mean±sd"
fmt_cell() {
    local key="$1"
    local m="${MEAN[$key]:-}"
    local s="${STDDEV[$key]:-}"
    if [ -z "$m" ] || [ "$m" = "-" ]; then
        echo "-"
    else
        local mi=$(echo "$m" | awk '{printf "%d", $1+0.5}')
        local si=$(echo "$s" | awk '{printf "%d", $1+0.5}')
        if [ "$si" = "0" ]; then
            echo "$mi"
        else
            echo "${mi}±${si}"
        fi
    fi
}

# Run one mode of a benchmark and store results
run_mode() {
    local bench="$1"
    local mode_label="$2"
    local mode_key="$3"
    local runner="$4"
    local arg1="$5"
    local arg2="$6"

    printf "  %-22s " "$mode_label"
    times=$(run_repeated "$bench" "$mode_key" "$runner" "$arg1" "$arg2" 2>/dev/null) || true
    if [ "$times" = "ERROR" ] || [ -z "$times" ]; then
        echo -e "${RED}ERROR${NC}"
        FAILURES="$FAILURES ${bench}:${mode_key}"
        return
    fi
    stats=$(compute_stats "$times")
    m=$(echo "$stats" | awk '{print $1}')
    s=$(echo "$stats" | awk '{print $2}')
    mn=$(echo "$stats" | awk '{print $3}')
    mx=$(echo "$stats" | awk '{print $4}')
    MEAN["${bench}_${mode_key}"]="$m"
    STDDEV["${bench}_${mode_key}"]="$s"
    RMIN["${bench}_${mode_key}"]="$mn"
    RMAX["${bench}_${mode_key}"]="$mx"
    printf "%6s ± %-4s ms  ${DIM}(min=%s max=%s)${NC}\n" "$m" "$s" "$mn" "$mx"
}

# ── Benchmark Execution ───────────────────────────────────────

FAILURES=""

for bench in $BENCHMARKS; do
    echo -e "${CYAN}─── $bench ───${NC}"

    native_bin="$OUTDIR/${bench}_native"
    go_dis="$OUTDIR/${bench}_go.dis"
    limbo_dis="$OUTDIR/${bench}_limbo.dis"

    [ -f "$native_bin" ] && run_mode "$bench" "Native Go" "native" "run_native_once" "$native_bin"
    [ -f "$go_dis" ]     && run_mode "$bench" "Go-on-Dis JIT" "godis_jit" "run_emu_once" "$go_dis" "-c1"
    [ -f "$go_dis" ]     && run_mode "$bench" "Go-on-Dis Interp" "godis_interp" "run_emu_once" "$go_dis" "-c0"
    [ -f "$limbo_dis" ]  && run_mode "$bench" "Limbo JIT" "limbo_jit" "run_emu_once" "$limbo_dis" "-c1"
    [ -f "$limbo_dis" ]  && run_mode "$bench" "Limbo Interp" "limbo_interp" "run_emu_once" "$limbo_dis" "-c0"

    echo ""
done

# ── Summary Table ──────────────────────────────────────────────

echo "============================================================"
echo "  SUMMARY (mean ± stddev, milliseconds)"
echo "============================================================"
printf "${BOLD}%-16s %10s %10s %10s %10s %10s${NC}\n" \
    "Benchmark" "Native" "GoDis JIT" "GoDis Int" "Limbo JIT" "Limbo Int"
printf "%-16s %10s %10s %10s %10s %10s\n" \
    "────────────" "────────" "────────" "────────" "────────" "────────"

for bench in $BENCHMARKS; do
    c_native=$(fmt_cell "${bench}_native")
    c_gj=$(fmt_cell "${bench}_godis_jit")
    c_gi=$(fmt_cell "${bench}_godis_interp")
    c_lj=$(fmt_cell "${bench}_limbo_jit")
    c_li=$(fmt_cell "${bench}_limbo_interp")
    printf "%-16s %10s %10s %10s %10s %10s\n" \
        "$bench" "$c_native" "$c_gj" "$c_gi" "$c_lj" "$c_li"
done

echo ""

# ── Speedup Ratios ─────────────────────────────────────────────

echo "============================================================"
echo "  SPEEDUP vs Go-on-Dis Interpreter (higher = faster)"
echo "============================================================"
printf "${BOLD}%-16s %10s %10s %10s %10s${NC}\n" \
    "Benchmark" "Native" "GoDis JIT" "Limbo JIT" "Limbo Int"
printf "%-16s %10s %10s %10s %10s\n" \
    "────────────" "────────" "────────" "────────" "────────"

for bench in $BENCHMARKS; do
    gi="${MEAN[${bench}_godis_interp]:-}"
    if [ -z "$gi" ] || [ "$gi" = "-" ]; then
        printf "%-16s %10s %10s %10s %10s\n" "$bench" "-" "-" "-" "-"
        continue
    fi

    fmt_ratio() {
        local val="$1"
        if [ -z "$val" ] || [ "$val" = "-" ]; then
            echo "-"
        else
            echo "$gi $val" | awk '{if($2+0>0) printf "%.1fx", $1/$2; else print "-"}'
        fi
    }

    r_native=$(fmt_ratio "${MEAN[${bench}_native]:-}")
    r_gj=$(fmt_ratio "${MEAN[${bench}_godis_jit]:-}")
    r_lj=$(fmt_ratio "${MEAN[${bench}_limbo_jit]:-}")
    r_li=$(fmt_ratio "${MEAN[${bench}_limbo_interp]:-}")

    printf "%-16s %10s %10s %10s %10s\n" "$bench" "$r_native" "$r_gj" "$r_lj" "$r_li"
done

echo ""

# ── JIT Speedup ────────────────────────────────────────────────

echo "============================================================"
echo "  JIT SPEEDUP (JIT / Interpreter, <1.0 = JIT faster)"
echo "============================================================"
printf "${BOLD}%-16s %12s %12s${NC}\n" "Benchmark" "GoDis JIT/Int" "Limbo JIT/Int"
printf "%-16s %12s %12s\n" "────────────" "───────────" "───────────"

for bench in $BENCHMARKS; do
    gj="${MEAN[${bench}_godis_jit]:-}"
    gi="${MEAN[${bench}_godis_interp]:-}"
    lj="${MEAN[${bench}_limbo_jit]:-}"
    li="${MEAN[${bench}_limbo_interp]:-}"

    fmt_jit() {
        local jit="$1"
        local interp="$2"
        if [ -z "$jit" ] || [ "$jit" = "-" ] || [ -z "$interp" ] || [ "$interp" = "-" ]; then
            echo "-"
        else
            echo "$jit $interp" | awk '{if($2+0>0) printf "%.2f", $1/$2; else print "-"}'
        fi
    }

    r_go=$(fmt_jit "$gj" "$gi")
    r_limbo=$(fmt_jit "$lj" "$li")
    printf "%-16s %12s %12s\n" "$bench" "$r_go" "$r_limbo"
done

echo ""

# ── Output ─────────────────────────────────────────────────────

if [ -n "$FAILURES" ]; then
    echo -e "${RED}FAILURES:${NC}$FAILURES"
    echo ""
fi

echo -e "CSV results: ${GREEN}$CSV_FILE${NC}"
echo ""
echo "Done."
