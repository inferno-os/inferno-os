#!/bin/sh
line=`/bin/echo $1 | /bin/sed 's/-//'`
if [ "x$EDITOR" = "x" ] ; then
	vi +$line $2
else
	$EDITOR +$line $2
fi
