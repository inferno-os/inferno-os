#!/dis/sh.dis -n
load std
or {ftest -f /mnt/registry/new} {
	db=()
	and {ftest -f /lib/ndb/registry} {db=(-f /lib/ndb/registry)}
	mount -A -c {ndb/registry $db} /mnt/registry
}
listen -v 'tcp!*!registry' {export /mnt/registry&}	# -n?
