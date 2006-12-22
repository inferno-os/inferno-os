#!/dis/sh.dis -n
load std
listen -v 'tcp!*!styx' {export /&}	# -n?
#and {ftest -d /net/il} {listen -v 'il!*!styx' {export /&}}	# -n?
