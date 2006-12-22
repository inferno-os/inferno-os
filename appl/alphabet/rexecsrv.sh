#!/dis/sh
if{! ~ $#* 2}{
	echo usage rexecsrv net!addr decls >[1=2]
	raise usage
}
(addr decls) := $*
/appl/alphabet/mkendpoint.sh $addr!2222
alphabet/rexecsrv /n/cd $decls
listen -v $addr!2223 {export /n/cd&}
