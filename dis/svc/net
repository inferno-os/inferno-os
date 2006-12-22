#!/dis/sh.dis -n
load std
or {ftest -e /net/dns} {ftest -e /env/emuhost} {ndb/dns}
or {ftest -e /net/cs} {ndb/cs}
svc/registry
svc/styx
