#!/dis/sh
fn bindfs {
	# this may be useful as a general purpose cmd
	(mntpt dirs)=$*
	memfs $mntpt
	for d in $dirs {
		parts=${split / $d}
		fpath=''
		for p in $parts {
			fpath=$fpath^/^$p
			if {! ftest -e $mntpt^$fpath} {
				if {ftest -d $fpath} {
					mkdir $mntpt^$fpath
				} {
					if {! ftest -e $fpath} {
						echo $fpath does not exist >[1=2]
						raise 'fail:errors'
					}
				}
			}
		}
		if {! ftest -d $d} {
			touch $mntpt/$d
		}
		bind $d $mntpt^$d
	}
}

fn x {
	echo tcp!^$2
}

bindfs /tmp /dis /n/client /dev /prog
listen -A  `{x `{ndb/csquery tcp!^`{cat /dev/sysname}^!rstyx}} {
		@{
			load std
			pctl forkns nodevs
			bind /tmp /
			runas rstyx {auxi/rstyxd}
		}&
	}

while {} {
	demo/cpupool/regpoll tcp!200.1.1.104!6676 up
	echo Registering Rstyx service
	mount -A 'tcp!200.1.1.104!6676' /mnt/registry
	echo `{x `{ndb/csquery tcp!^`{cat /dev/sysname}^!rstyx}} proto styx auth none persist 1 resource '''Rstyx resource''' name `{cat /dev/sysname} > /mnt/registry/new
	demo/cpupool/regpoll tcp!200.1.1.104!6676 down
	echo Registry gone down
}