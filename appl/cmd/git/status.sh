#!/dis/sh.dis
#
# git/status — show working tree status via git/fs
#
# Usage: git/status [dir]
#
# Compares files served by git/fs HEAD/tree/ with working directory.
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

# Walk git/fs tree, compare each blob with working copy
fn treestatus {
	fsdir=$1
	prefix=$2
	workdir=$3
	for f in `{ls $fsdir} {
		base=`{basename $f}
		rpath=$prefix^$base
		if {ftest -d $f} {
			treestatus $f $rpath/ $workdir
		} {
			if {! ftest -e $workdir/$rpath} {
				echo ' D' $rpath
			} {
				if {! cmp -s $f $workdir/$rpath} {
					echo ' M' $rpath
				}
			}
		}
	}
}

# Walk working dir, check for untracked files
fn finduntracked {
	wdir=$1
	prefix=$2
	treedir=$3
	for f in `{ls $wdir} {
		base=`{basename $f}
		if {! ~ $base .git} {
			rpath=$prefix^$base
			if {ftest -d $wdir/$base} {
				finduntracked $wdir/$base $rpath/ $treedir
			} {
				if {! ftest -e $treedir/$rpath} {
					echo '??' $rpath
				}
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
	treestatus $mtpt/HEAD/tree '' $dir
	finduntracked $dir '' $mtpt/HEAD/tree
}
~ 1 1
