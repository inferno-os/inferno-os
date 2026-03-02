#!/bin/bash
# JIT vs Interpreter comparison test suite
# Runs programs in both -c0 (interpreter) and -c1 (JIT) modes
# and compares output to detect JIT-specific bugs.
#
# Works on all supported platforms:
#   ARM64 Linux, ARM64 macOS, AMD64 Linux, AMD64 macOS
#
# Usage: bash scratchpad/jit_test.sh [--bench] [--stress] [--all]
#   --bench   Run benchmark comparisons (JIT vs interpreter timing)
#   --stress  Run stress tests (large data, edge cases)
#   --all     Run everything
#
# Run from the infernode root directory.
#
# Large-input tests use file arguments rather than stdin piping. Inferno's
# console input queue (kbdq) is 512 bytes — designed for interactive
# keyboard input, not bulk data. Data beyond 512 bytes is silently dropped
# by qproduce(), so programs receive truncated input with piped stdin.
# File arguments bypass the console path entirely (read via devfs), which
# is how batch processing works in Inferno and Plan 9.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Platform detection
_os=$(uname -s)
_arch=$(uname -m)
case "$_os" in
    Darwin) EMUHOST=MacOSX ;;
    Linux)  EMUHOST=Linux ;;
    *)      echo "Unsupported OS: $_os"; exit 1 ;;
esac
case "$_arch" in
    aarch64|arm64) OBJTYPE=arm64 ;;
    x86_64|amd64)  OBJTYPE=amd64 ;;
    *)             echo "Unsupported arch: $_arch"; exit 1 ;;
esac

# Find emulator binary
EMUBIN=""
for name in o.emu Infernode; do
    if [ -x "$ROOT/emu/$EMUHOST/$name" ]; then
        EMUBIN="$ROOT/emu/$EMUHOST/$name"
        break
    fi
done
if [ -z "$EMUBIN" ]; then
    echo "ERROR: No emulator binary found in emu/$EMUHOST/"
    exit 1
fi

cd "$ROOT/emu/$EMUHOST"
EMU="$EMUBIN -r$ROOT"
TIMEOUT_SEC=10
PASS=0
FAIL=0
SKIP=0
HANG=0
TOTAL=0

DO_BENCH=0
DO_STRESS=0
for arg in "$@"; do
    case "$arg" in
        --bench)  DO_BENCH=1 ;;
        --stress) DO_STRESS=1 ;;
        --all)    DO_BENCH=1; DO_STRESS=1 ;;
    esac
done

# Create temp files for output comparison
OUT0=$(mktemp)
OUT1=$(mktemp)
# Temp file for passing large input via file argument (avoids stdin echo)
INFILE="$ROOT/scratchpad/.jit_test_input"
trap "rm -f $OUT0 $OUT1 $INFILE" EXIT

run_test() {
    local desc="$1"
    shift
    local input="$1"
    shift
    local args="$*"
    TOTAL=$((TOTAL+1))

    # Run interpreter mode
    if [ -n "$input" ]; then
        printf '%s\n' "$input" | timeout $TIMEOUT_SEC $EMU -c0 $args >$OUT0 2>/dev/null
        RC0=$?
        printf '%s\n' "$input" | timeout $TIMEOUT_SEC $EMU -c1 $args >$OUT1 2>/dev/null
        RC1=$?
    else
        timeout $TIMEOUT_SEC $EMU -c0 $args >$OUT0 2>/dev/null
        RC0=$?
        timeout $TIMEOUT_SEC $EMU -c1 $args >$OUT1 2>/dev/null
        RC1=$?
    fi

    # Small delay to avoid race conditions between rapid process starts
    sleep 0.2

    # Check for timeouts
    if [ $RC0 -eq 124 ] && [ $RC1 -eq 124 ]; then
        printf "  HANG  %-45s (both modes timeout)\n" "$desc"
        HANG=$((HANG+1))
        return
    fi
    if [ $RC1 -eq 124 ] && [ $RC0 -ne 124 ]; then
        printf "  FAIL  %-45s (JIT hangs, interp ok)\n" "$desc"
        FAIL=$((FAIL+1))
        return
    fi
    if [ $RC0 -eq 124 ] && [ $RC1 -ne 124 ]; then
        printf "  FAIL  %-45s (interp hangs, JIT ok?!)\n" "$desc"
        FAIL=$((FAIL+1))
        return
    fi

    # Compare outputs
    if diff -q $OUT0 $OUT1 >/dev/null 2>&1; then
        printf "  PASS  %-45s\n" "$desc"
        PASS=$((PASS+1))
    else
        printf "  FAIL  %-45s\n" "$desc"
        echo "    --- Interpreter output (first 5 lines) ---"
        head -5 $OUT0 | sed 's/^/    /'
        echo "    --- JIT output (first 5 lines) ---"
        head -5 $OUT1 | sed 's/^/    /'
        FAIL=$((FAIL+1))
    fi
}

# run_test_file: writes input to a file and passes it as a file argument.
# Used for large-input tests that exceed kbdq's 512-byte capacity.
# Programs read via devfs (the normal batch-processing path in Inferno).
run_test_file() {
    local desc="$1"
    shift
    local input="$1"
    shift
    local args="$*"
    TOTAL=$((TOTAL+1))

    printf '%s\n' "$input" > "$INFILE"
    local infpath="../../scratchpad/.jit_test_input"

    timeout $TIMEOUT_SEC $EMU -c0 $args $infpath >$OUT0 2>/dev/null
    RC0=$?
    timeout $TIMEOUT_SEC $EMU -c1 $args $infpath >$OUT1 2>/dev/null
    RC1=$?

    sleep 0.2

    if [ $RC0 -eq 124 ] && [ $RC1 -eq 124 ]; then
        printf "  HANG  %-45s (both modes timeout)\n" "$desc"
        HANG=$((HANG+1))
        return
    fi
    if [ $RC1 -eq 124 ] && [ $RC0 -ne 124 ]; then
        printf "  FAIL  %-45s (JIT hangs, interp ok)\n" "$desc"
        FAIL=$((FAIL+1))
        return
    fi
    if [ $RC0 -eq 124 ] && [ $RC1 -ne 124 ]; then
        printf "  FAIL  %-45s (interp hangs, JIT ok?!)\n" "$desc"
        FAIL=$((FAIL+1))
        return
    fi

    if diff -q $OUT0 $OUT1 >/dev/null 2>&1; then
        printf "  PASS  %-45s\n" "$desc"
        PASS=$((PASS+1))
    else
        printf "  FAIL  %-45s\n" "$desc"
        echo "    --- Interpreter output (first 5 lines) ---"
        head -5 $OUT0 | sed 's/^/    /'
        echo "    --- JIT output (first 5 lines) ---"
        head -5 $OUT1 | sed 's/^/    /'
        FAIL=$((FAIL+1))
    fi
}

# ============================================================
# BENCHMARK: time JIT vs interpreter
# ============================================================
run_bench() {
    local desc="$1"
    shift
    local input="$1"
    shift
    local args="$*"

    local t0 t1

    if [ -n "$input" ]; then
        t0=$( { time printf '%s\n' "$input" | timeout 30 $EMU -c0 $args >/dev/null 2>/dev/null ; } 2>&1 | grep real | awk '{print $2}')
        t1=$( { time printf '%s\n' "$input" | timeout 30 $EMU -c1 $args >/dev/null 2>/dev/null ; } 2>&1 | grep real | awk '{print $2}')
    else
        t0=$( { time timeout 30 $EMU -c0 $args >/dev/null 2>/dev/null ; } 2>&1 | grep real | awk '{print $2}')
        t1=$( { time timeout 30 $EMU -c1 $args >/dev/null 2>/dev/null ; } 2>&1 | grep real | awk '{print $2}')
    fi

    printf "  %-40s  interp=%-10s  jit=%-10s\n" "$desc" "$t0" "$t1"
}

echo "=========================================================="
echo "  JIT vs Interpreter Test Suite ($OBJTYPE $EMUHOST)"
echo "=========================================================="
echo ""

# ============================================================
# SECTION 1: Core functionality (original 26 tests)
# ============================================================
echo "--- Basic: No-input programs ---"
run_test "echo hello"             "" dis/echo.dis hello
run_test "echo multi-word"        "" dis/echo.dis hello world foo
run_test "echo no-args"           "" dis/echo.dis

echo ""
echo "--- Basic: Stdin processing ---"
run_test "calc 2+3"               "2+3"       dis/calc.dis
run_test "calc 100-37"            "100-37"    dis/calc.dis
run_test "calc 6*7"               "6*7"       dis/calc.dis
run_test "calc 144/12"            "144/12"    dis/calc.dis
run_test "calc multi-expr"        "$(printf '1+1\n2+2\n3+3')" dis/calc.dis
run_test "wc stdin"               "$(printf 'hello world\nfoo bar baz')" dis/wc.dis
run_test "cat stdin"              "hello world" dis/cat.dis
run_test "sort stdin"             "$(printf 'cherry\napple\nbanana')" dis/sort.dis
run_test "uniq stdin"             "$(printf 'aaa\naaa\nbbb\nccc\nccc')" dis/uniq.dis
run_test "tr a-z A-Z"             "hello" dis/tr.dis a-z A-Z

echo ""
echo "--- Basic: File system ---"
run_test "ls /dev"                "" dis/ls.dis /dev
run_test "ls -l /dev"             "" dis/ls.dis -l /dev

echo ""
echo "--- Basic: String/text tools ---"
run_test "grep match"             "hello world" dis/grep.dis hello
run_test "grep nomatch"           "hello world" dis/grep.dis zzzzz
run_test "xd stdin"               "ABCDEFGH" dis/xd.dis
run_test "freq stdin"             "aabbccdd" dis/freq.dis
run_test "basename /foo/bar"      "" dis/basename.dis /foo/bar
run_test "cleanname /../foo"      "" dis/cleanname.dis /../foo

echo ""
echo "--- Basic: Data generation ---"
run_test "seq 1 10"               "" dis/seq.dis 1 10
run_test "seq 5 5"                "" dis/seq.dis 5 5
run_test "zeros 16"               "" dis/zeros.dis 16
run_test "date"                   "" dis/date.dis

echo ""
echo "--- Basic: Dis tools ---"
run_test "disdump echo.dis"       "" dis/disdump.dis ../../dis/echo.dis

# ============================================================
# SECTION 2: Extended programs (new)
# ============================================================
echo ""
echo "--- Extended: Crypto/hash ---"
run_test "md5sum stdin"           "hello world test" dis/md5sum.dis
run_test "sha1sum stdin"          "hello world test" dis/sha1sum.dis

echo ""
echo "--- Extended: Text processing ---"
run_test "tail stdin"             "$(printf 'hello world\nfoo bar')" dis/tail.dis
run_test "fmt stdin"              "$(printf 'hello world test\nfoo bar')" dis/fmt.dis
run_test "strings stdin"          "$(printf 'hello world test')" dis/strings.dis

echo ""
echo "--- Extended: System introspection ---"
run_test "ns"                     "" dis/ns.dis

# env: filter out emuargs line since it contains -c0/-c1 which always differs
TOTAL=$((TOTAL+1))
timeout $TIMEOUT_SEC $EMU -c0 dis/env.dis 2>/dev/null | grep -v emuargs >$OUT0
timeout $TIMEOUT_SEC $EMU -c1 dis/env.dis 2>/dev/null | grep -v emuargs >$OUT1
sleep 0.1
if diff -q $OUT0 $OUT1 >/dev/null 2>&1; then
    printf "  PASS  %-45s\n" "env (filtered)"
    PASS=$((PASS+1))
else
    printf "  FAIL  %-45s\n" "env (filtered)"
    echo "    --- Interpreter ---"; head -5 $OUT0 | sed 's/^/    /'
    echo "    --- JIT ---"; head -5 $OUT1 | sed 's/^/    /'
    FAIL=$((FAIL+1))
fi

echo ""
echo "--- Extended: Disdump various ---"
run_test "disdump calc.dis"       "" dis/disdump.dis ../../dis/calc.dis
run_test "disdump wc.dis"         "" dis/disdump.dis ../../dis/wc.dis
run_test "disdump date.dis"       "" dis/disdump.dis ../../dis/date.dis
run_test "disdump sort.dis"       "" dis/disdump.dis ../../dis/sort.dis
run_test "disdump md5sum.dis"     "" dis/disdump.dis ../../dis/md5sum.dis

# ============================================================
# SECTION 3: Edge cases
# ============================================================
echo ""
echo "--- Edge: Arithmetic boundaries ---"
run_test "calc 0+0"               "0+0"           dis/calc.dis
run_test "calc large add"         "999999+1"      dis/calc.dis
run_test "calc negative"          "0-1"           dis/calc.dis
run_test "calc large sub"         "0-999999"      dis/calc.dis
run_test "calc multiply"          "12345*6789"    dis/calc.dis
run_test "calc divide exact"      "100/10"        dis/calc.dis
run_test "calc divide remainder"  "7/3"           dis/calc.dis
run_test "calc large multiply"    "99999*99999"   dis/calc.dis

echo ""
echo "--- Edge: Empty/minimal input ---"
run_test "wc empty"               "" dis/wc.dis
run_test "cat empty"              "" dis/cat.dis
run_test "sort empty"             "" dis/sort.dis
run_test "grep empty input"       "" dis/grep.dis hello
run_test "freq empty"             "" dis/freq.dis
run_test "xd empty"               "" dis/xd.dis
run_test "tr empty"               "" dis/tr.dis a-z A-Z

echo ""
echo "--- Edge: Single character ---"
run_test "cat single char"        "X" dis/cat.dis
run_test "wc single char"         "X" dis/wc.dis
run_test "freq single char"       "X" dis/freq.dis
run_test "xd single byte"         "A" dis/xd.dis
run_test "tr single char"         "a" dis/tr.dis a-z A-Z
run_test "echo single char"       "" dis/echo.dis X

echo ""
echo "--- Edge: Special characters ---"
run_test "echo tab/space"         "" dis/echo.dis "hello	world"
run_test "cat binary-ish"         "$(printf '\x01\x02\x03\xff')" dis/cat.dis
run_test "xd binary"              "$(printf '\x00\x01\x7f\x80\xff')" dis/xd.dis
run_test "grep special regex"     "hello.world" dis/grep.dis "hello"

echo ""
echo "--- Edge: Large data ---"
run_test "sort 100 lines"         "$(seq 100 | sort -R)" dis/sort.dis
run_test "wc 100 lines"           "$(seq 100)" dis/wc.dis
run_test_file "freq alphabet x100" "$(python3 -c "print('abcdefghijklmnopqrstuvwxyz' * 100, end='')" 2>/dev/null || printf '%0.sabcdefghijklmnopqrstuvwxyz' $(seq 100))" dis/freq.dis
run_test_file "grep 50 lines"     "$(seq 50 | sed 's/^/line /')" dis/grep.dis "line 25"
run_test "uniq many dupes"        "$(for i in $(seq 20); do echo aaa; echo aaa; echo bbb; done)" dis/uniq.dis

echo ""
echo "--- Edge: Long strings ---"
run_test "echo long arg"          "" dis/echo.dis "$(python3 -c "print('A'*500)" 2>/dev/null || printf '%0500d' 0 | tr 0 A)"
run_test_file "grep long line"    "$(python3 -c "print('A'*500 + 'NEEDLE' + 'B'*500)" 2>/dev/null || echo ANEEDLEB)" dis/grep.dis NEEDLE

echo ""
echo "--- Edge: Multi-line sort stress ---"
run_test "sort reverse"           "$(seq 50 -1 1)" dis/sort.dis
run_test "sort already sorted"    "$(seq 50)" dis/sort.dis
run_test "sort all same"          "$(yes hello | head -30)" dis/sort.dis
run_test "sort single line"       "only one line" dis/sort.dis

echo ""
echo "--- Edge: Seq boundaries ---"
run_test "seq 0 0"                "" dis/seq.dis 0 0
run_test "seq 1 1"                "" dis/seq.dis 1 1
run_test "seq 1 100"              "" dis/seq.dis 1 100
run_test "seq large range"        "" dis/seq.dis 1 500

echo ""
echo "--- Edge: Multiple calc operations ---"
run_test "calc chain"             "$(printf '1+1\n2*3\n10-4\n100/5\n0+0\n999*0')" dis/calc.dis

echo ""
echo "--- Edge: Complex programs ---"
run_test "md5sum empty"           "" dis/md5sum.dis
run_test "sha1sum empty"          "" dis/sha1sum.dis
run_test_file "md5sum large"      "$(seq 200)" dis/md5sum.dis
run_test_file "sha1sum large"     "$(seq 200)" dis/sha1sum.dis

echo ""
echo "=========================================================="
printf "  PASS: %d  FAIL: %d  HANG: %d  TOTAL: %d\n" $PASS $FAIL $HANG $TOTAL
echo "=========================================================="

# ============================================================
# SECTION 4: Stress tests (--stress flag)
# ============================================================
if [ $DO_STRESS -eq 1 ]; then
    echo ""
    echo "=========================================================="
    echo "  STRESS TESTS"
    echo "=========================================================="
    echo ""

    echo "--- Stress: Repeated execution (5x each) ---"
    STRESS_PASS=0
    STRESS_FAIL=0
    for rep in 1 2 3 4 5; do
        for prog in "echo hello" "calc 2+3" "sort" "wc" "freq" "xd" "md5sum"; do
            case "$prog" in
                "echo hello")
                    timeout 5 $EMU -c1 dis/echo.dis hello >$OUT1 2>/dev/null
                    if grep -q "hello" $OUT1; then STRESS_PASS=$((STRESS_PASS+1)); else STRESS_FAIL=$((STRESS_FAIL+1)); fi
                    ;;
                "calc 2+3")
                    echo "2+3" | timeout 5 $EMU -c1 dis/calc.dis >$OUT1 2>/dev/null
                    if grep -q "5" $OUT1; then STRESS_PASS=$((STRESS_PASS+1)); else STRESS_FAIL=$((STRESS_FAIL+1)); fi
                    ;;
                "sort")
                    printf 'c\na\nb' | timeout 5 $EMU -c1 dis/sort.dis >$OUT1 2>/dev/null
                    if head -1 $OUT1 | grep -q "a"; then STRESS_PASS=$((STRESS_PASS+1)); else STRESS_FAIL=$((STRESS_FAIL+1)); fi
                    ;;
                "wc")
                    echo "hi" | timeout 5 $EMU -c1 dis/wc.dis >$OUT1 2>/dev/null
                    if grep -q "1" $OUT1; then STRESS_PASS=$((STRESS_PASS+1)); else STRESS_FAIL=$((STRESS_FAIL+1)); fi
                    ;;
                "freq")
                    echo "aabb" | timeout 5 $EMU -c1 dis/freq.dis >$OUT1 2>/dev/null
                    if grep -q "2" $OUT1; then STRESS_PASS=$((STRESS_PASS+1)); else STRESS_FAIL=$((STRESS_FAIL+1)); fi
                    ;;
                "xd")
                    echo "AB" | timeout 5 $EMU -c1 dis/xd.dis >$OUT1 2>/dev/null
                    if grep -q "41" $OUT1; then STRESS_PASS=$((STRESS_PASS+1)); else STRESS_FAIL=$((STRESS_FAIL+1)); fi
                    ;;
                "md5sum")
                    echo "test" | timeout 5 $EMU -c1 dis/md5sum.dis >$OUT1 2>/dev/null
                    if [ -n "$(cat $OUT1)" ]; then STRESS_PASS=$((STRESS_PASS+1)); else STRESS_FAIL=$((STRESS_FAIL+1)); fi
                    ;;
            esac
        done
        printf "  Rep %d/5: pass=%d fail=%d\n" $rep $STRESS_PASS $STRESS_FAIL
    done
    echo ""
    printf "  STRESS TOTAL: pass=%d fail=%d (of 35)\n" $STRESS_PASS $STRESS_FAIL

    echo ""
    echo "--- Stress: Large data throughput ---"
    # Generate 10KB of data, pipe through cat
    BIGDATA=$(seq 1000)
    printf '%s' "$BIGDATA" | timeout 15 $EMU -c0 dis/cat.dis >$OUT0 2>/dev/null
    printf '%s' "$BIGDATA" | timeout 15 $EMU -c1 dis/cat.dis >$OUT1 2>/dev/null
    if diff -q $OUT0 $OUT1 >/dev/null 2>&1; then
        echo "  PASS  cat 1000 lines (large throughput)"
    else
        echo "  FAIL  cat 1000 lines (large throughput)"
    fi

    # Sort 200 random-ish lines
    SORTDATA=$(seq 200 | awk 'BEGIN{srand(42)}{print int(rand()*10000), $0}')
    printf '%s' "$SORTDATA" | timeout 15 $EMU -c0 dis/sort.dis >$OUT0 2>/dev/null
    printf '%s' "$SORTDATA" | timeout 15 $EMU -c1 dis/sort.dis >$OUT1 2>/dev/null
    if diff -q $OUT0 $OUT1 >/dev/null 2>&1; then
        echo "  PASS  sort 200 lines"
    else
        echo "  FAIL  sort 200 lines"
    fi
fi

# ============================================================
# SECTION 5: Benchmarks (--bench flag)
# ============================================================
if [ $DO_BENCH -eq 1 ]; then
    echo ""
    echo "=========================================================="
    echo "  BENCHMARK: JIT vs Interpreter"
    echo "=========================================================="
    echo ""
    echo "  Each test runs once. Times include VM startup overhead."
    echo "  Format: real time (smaller = faster)"
    echo ""

    run_bench "echo hello"          "" dis/echo.dis hello
    run_bench "calc 50 exprs"       "$(for i in $(seq 50); do echo "$i+$i"; done)" dis/calc.dis
    run_bench "sort 100 lines"      "$(seq 100 -1 1)" dis/sort.dis
    run_bench "wc 100 lines"        "$(seq 100)" dis/wc.dis
    run_bench "freq large"          "$(python3 -c "print('abcdefghij' * 500, end='')" 2>/dev/null || printf 'abcdefghij%.0s' $(seq 500))" dis/freq.dis
    run_bench "xd 1KB"              "$(python3 -c "import sys; sys.stdout.buffer.write(bytes(range(256))*4)" 2>/dev/null || dd if=/dev/urandom bs=1024 count=1 2>/dev/null)" dis/xd.dis
    run_bench "md5sum 1KB"          "$(seq 100)" dis/md5sum.dis
    run_bench "sha1sum 1KB"         "$(seq 100)" dis/sha1sum.dis
    run_bench "grep 100 lines"      "$(seq 100 | sed 's/^/line /')" dis/grep.dis "line 50"
    run_bench "sort 500 lines"      "$(seq 500 -1 1)" dis/sort.dis
    run_bench "cat 500 lines"       "$(seq 500)" dis/cat.dis
    run_bench "uniq 200 lines"      "$(for i in $(seq 100); do echo aaa; echo bbb; done)" dis/uniq.dis
    run_bench "disdump sort.dis"    "" dis/disdump.dis ../../dis/sort.dis
    run_bench "seq 1 1000"          "" dis/seq.dis 1 1000
    run_bench "date"                "" dis/date.dis
    run_bench "ns"                  "" dis/ns.dis
    run_bench "ls -l /dev"          "" dis/ls.dis -l /dev

    echo ""
    echo "  Note: VM startup dominates for small workloads."
    echo "  JIT advantage shows on computation-heavy programs."
fi

echo ""
echo "Done."
