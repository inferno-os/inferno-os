#!/dis/sh

mount -A {auxi/odbcmnt -a tcp!200.1.1.113} /mnt/odbc

fn splitrun {
	if {! ~ $#* 0} {
		(hd tl) = $*
		echo Registering $hd
		grid/register -a resource ODBC -a name $hd '{export /mnt/odbc/'^$hd^'}'
		splitrun $tl
	}
}

cd /mnt/odbc
sources=`{ls}
splitrun $sources

