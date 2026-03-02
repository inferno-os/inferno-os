#!/dis/sh.dis
#
# git/log — display commit history via git/fs
#
# Usage: git/log [-n count] [dir]
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

dir=.
limit=0
args=$*

# Parse arguments
while {! ~ $#args 0} {
	a=${hd $args}
	args=${tl $args}
	if {~ $a -n} {
		if {~ $#args 0} {
			echo 'git/log: -n requires argument' >[1=2]
			raise 'fail:usage'
		}
		limit=${hd $args}
		args=${tl $args}
	} {
		dir=$a
	}
}

findgit $dir
gitdir=$result

ensure_fs $gitdir
mtpt=$result

hash=`{cat $mtpt/HEAD/hash}
count=0

while {! ~ $#hash 0} {
	if {! ~ $limit 0} {
		if {~ $count $limit} {
			exit
		}
	}

	if {! ftest -d $mtpt/object/$hash} {
		exit
	}

	echo 'commit' $hash
	echo 'Author:' `{cat $mtpt/object/$hash/author}
	echo ''
	cat $mtpt/object/$hash/msg | sed 's/^/    /'
	echo ''

	# Follow first parent
	if {ftest -f $mtpt/object/$hash/parent} {
		hash=`{sed 1q $mtpt/object/$hash/parent}
	} {
		hash=()
	}
	count=${expr $count 1 +}
}
