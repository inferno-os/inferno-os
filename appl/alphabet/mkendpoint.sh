#!/dis/sh -n
autoload=std
load std
if{! ~ $#* 1}{
	echo usage: mkendpoint addr >[1=2]
	raise usage
}
addr:=$1
if{! ftest -e /n/endpoint/dsgdsfgeafreqeq}{
	mount {mntgen} /n/endpoint
}
mount {pctl forkns; alphabet/endpointsrv $addr /n; export /n} /n/endpoint/$addr
bind /n/endpoint/$addr /n/endpoint/local
styxlisten -A $addr {export /n/endpoint/local}
