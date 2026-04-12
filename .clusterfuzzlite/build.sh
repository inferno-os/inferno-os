#!/bin/bash -eu
#
# Build fuzz targets for ClusterFuzzLite.
# Uses the standard OSS-Fuzz environment variables:
#   $CC, $CFLAGS, $LIB_FUZZING_ENGINE, $OUT, $SRC

# Dis bytecode parser fuzz target
$CC $CFLAGS \
    -o "$OUT/fuzz_dis_parser" \
    "$SRC/infernode/.clusterfuzzlite/fuzz_dis_parser.c" \
    $LIB_FUZZING_ENGINE

# Seed corpus: existing .dis bytecode files from the runtime tree
mkdir -p "$OUT/fuzz_dis_parser_seed_corpus"
find "$SRC/infernode/dis" -name '*.dis' -size -64k | head -50 | while read -r f; do
    cp "$f" "$OUT/fuzz_dis_parser_seed_corpus/"
done
