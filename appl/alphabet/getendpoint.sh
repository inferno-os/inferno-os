#!/dis/sh -n
autoload=std
load std
if{! ~ $#* 1}{
	echo usage: getendpoint addr >[1=2]
	raise usage
}
addr:=$1
if{! ftest -e /n/endpoint/dsgdsfgeafreqeq}{
	mount {mntgen} /n/endpoint
}
mount -A $addr /n/endpoint/$addr
bind /n/endpoint/$addr /n/endpoint/local
