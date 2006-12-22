#!/dis/sh
load std
autoload=std
ndb/cs

fn ck {
	or {$*} {
		echo spreeclient: exiting >[1=2]
		raise error
	}
}
user="{cat /dev/user}

fn notice {
	or {~ $#* 1} {
		echo usage: notice arg >[1=2]
		raise usage
	}
	t := $*
	run /lib/sh/win
	tkwin Notice {
		x text .t -yscrollcommand {.s set}
		x scrollbar .s -orient vertical -command {.t yview}
		x pack .s -side left -fill y
		x pack .t -side top -fill both -expand 1
		x .t insert 1.0 ${tkquote $t}
		tk onscreen $wid
		chan c; {} ${recv c}
	}
}

ck mount -A 'tcp!$registry!registry' /mnt/registry
ck /dis/grid/remotelogon wm/wm {
	k = /usr/$user/keyring/default
	addrs=`{ndb/regquery resource spree auth.signer `{getpk -s $k}}
	if{~ $#addrs 0} {
		notice 'No spree servers found'
	}
	if {mount ${hd $addrs} /n/remote} {
		spree/joinsession 0
	} {
		notice 'Cannot access spree server'
	}
}
