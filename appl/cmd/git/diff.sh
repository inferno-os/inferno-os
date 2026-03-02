#!/dis/sh.dis
#
# git/diff — show file differences via git/fs
#
# Usage: git/diff [dir]
#
# Runs system diff for each modified tracked file.
#

load std
load expr

fn findgit {
	d=$1
	lim=20
	while {! ftest -d $d/.git} {
		d=$d/..
		lim=${expr $lim 1 -}
		if {~ $lim 0} {
			echo 'not a git repository' >[1=2]
			raise 'fail:not a git repository'
		}
	}
	result=$d/.git
}

fn ensure_fs {
	gdir=$1
	mtpt=$gdir/fs
	if {! ftest -d $mtpt/HEAD} {
		cmd/git/fs $gdir
	}
	result=$mtpt
}

fn treediff {
	fsdir=$1
	prefix=$2
	workdir=$3
	for f in `{ls $fsdir} {
		base=`{basename $f}
		rpath=$prefix^$base
		if {ftest -d $f} {
			treediff $f $rpath/ $workdir
		} {
			if {ftest -e $workdir/$rpath} {
				if {! cmp -s $f $workdir/$rpath} {
					echo '---' a/$rpath
					echo '+++' b/$rpath
					diff $f $workdir/$rpath
				}
			} {
				echo 'deleted:' $rpath
			}
		}
	}
}

dir=.
if {! ~ $#* 0} {
	dir=$1
}

findgit $dir
gitdir=$result

ensure_fs $gitdir
mtpt=$result

if {ftest -d $mtpt/HEAD/tree} {
	treediff $mtpt/HEAD/tree '' $dir
}
~ 1 1
