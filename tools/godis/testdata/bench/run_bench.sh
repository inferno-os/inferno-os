#!/bin/bash
# Benchmark: Go-compiled-to-Dis vs Limbo-compiled-to-Dis
# Runs each benchmark 3 times on interpreter (-c0) and JIT (-c1)

ROOT="$(cd ../../../.. && pwd)"
EMU="$ROOT/emu/Linux/o.emu"
BENCHDIR="$ROOT/tools/godis/testdata/bench"
RUNS=3

run_bench() {
    local label="$1"
    local dis="$2"
    local mode="$3"  # -c0 or -c1
    local modename="$4"

    # Copy .dis to a known Inferno path
    cp "$BENCHDIR/$dis" "$ROOT/$dis"

    local times=""
    for i in $(seq 1 $RUNS); do
        # Run with 10s timeout, capture output
        output=$(timeout 120 "$EMU" "-r$ROOT" "$mode" "/$dis" 2>/dev/null)
        # Last line is the time in ms
        ms=$(echo "$output" | tail -1)
        result=$(echo "$output" | head -1)
        times="$times $ms"
    done
    rm -f "$ROOT/$dis"
    printf "%-20s %-6s %-8s  result=%-12s  times=%s ms\n" "$label" "$modename" "$dis" "$result" "$times"
}

echo "=== Benchmark: Go-on-Dis vs Limbo-on-Dis ==="
echo "Platform: $(uname -m), $(nproc) cores"
echo "Runs: $RUNS each"
echo ""

for bench in fib sieve sort loop; do
    case $bench in
        fib)   go_dis="fib_go.dis";    limbo_dis="fib_limbo.dis";;
        sieve) go_dis="sieve_go.dis";  limbo_dis="sieve_limbo.dis";;
        sort)  go_dis="sort_go.dis";   limbo_dis="sort_limbo.dis";;
        loop)  go_dis="loop_go.dis";   limbo_dis="loop_limbo.dis";;
    esac

    echo "--- $bench ---"
    run_bench "Go/godis"  "$go_dis"    "-c0" "interp"
    run_bench "Go/godis"  "$go_dis"    "-c1" "JIT"
    run_bench "Limbo"     "$limbo_dis" "-c0" "interp"
    run_bench "Limbo"     "$limbo_dis" "-c1" "JIT"
    echo ""
done
