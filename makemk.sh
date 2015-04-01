#!/bin/sh

# this file is used only to bootstrap mk onto a platform
# that currently lacks a binary for mk.  after that, mk can
# look after itself.

#	support@vitanuova.com

# change these defines as appropriate here or in mkconfig
# ROOT should be the root of the Inferno tree
ROOT=/usr/inferno
SYSTARG=FreeBSD
OBJTYPE=386
SYSTYPE=posix

# if you have already changed mkconfig from the distribution, we'll use the definitions from that
grep -s 'SYSTARG=Plan9' mkconfig || . ./mkconfig

PLAT=$ROOT/$SYSTARG/$OBJTYPE

# you might need to adjust the CC, LD, AR, and RANLIB definitions after this point
CC="p gcc -m32 -c -I$PLAT/include -I$ROOT/include -I$ROOT/utils/include"
LD="p gcc -m32"
AR="p ar crvs"
RANLIB=":"	# some systems still require `ranlib'

error() {
	echo $* >&2
	exit 1
}

ofiles() {
	echo $* | sed 's/\.c/.o/g'
}

p() {
	echo $*
	"$@"
}

# make sure we start off clean
echo removing old libraries and binaries
rm -f $PLAT/lib/*.a $PLAT/bin/*
rm -f utils/cc/y.tab.?

# ensure the output directories exist
mkdir -p $PLAT/lib $PLAT/bin

# libregexp
cd $ROOT/utils/libregexp || error cannot find libregexp directory
CFILES="regaux.c regcomp.c regerror.c regexec.c regsub.c rregexec.c rregsub.c"
$CC $CFILES || error libregexp compilation failed
$AR $PLAT/lib/libregexp.a `ofiles $CFILES` || error libregexp ar failed
$RANLIB $PLAT/lib/libregexp.a || error libregexp ranlib failed

# libbio
cd $ROOT/libbio || error cannot find libbio directory
$CC *.c || error libbio compilation failed
$AR $PLAT/lib/libbio.a *.o || error libbio ar failed
$RANLIB $PLAT/lib/libbio.a || error libbio ranlib failed

# lib9
cd $ROOT/lib9 || error cannot find lib9 directory
CFILES="dirstat-$SYSTYPE.c rerrstr.c errstr-$SYSTYPE.c getuser-$SYSTYPE.c"	# system specific
CFILES="$CFILES charstod.c cleanname.c create.c dirwstat.c *print*.c *fmt*.c exits.c getfields.c  pow10.c print.c qsort.c rune.c runestrlen.c seek.c strdup.c strtoll.c utflen.c utfrrune.c utfrune.c utf*.c *str*cpy*.c"
$CC $CFILES || error lib9 compilation failed
$AR $PLAT/lib/lib9.a `ofiles $CFILES` || error lib9 ar failed
$RANLIB $PLAT/lib/lib9.a || error lib9 ranlib failed

# mk itself
cd $ROOT/utils/mk
CFILES="Posix.c sh.c"	# system specific
CFILES="$CFILES arc.c archive.c bufblock.c env.c file.c graph.c job.c lex.c main.c match.c mk.c parse.c recipe.c rule.c run.c shprint.c symtab.c var.c varsub.c word.c"
$CC $CFILES || error mk compilation failed
$LD -o mk `ofiles $CFILES` $PLAT/lib/libregexp.a $PLAT/lib/libbio.a $PLAT/lib/lib9.a || error mk link failed
cp mk $PLAT/bin || error mk binary install failed

echo mk binary built successfully!
