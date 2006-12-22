#!/dis/sh
load tk std
pctl newpgrp
wid=${tk window 'Test lines'}
fn x {tk $wid $*}
x canvas .c
x pack .c
x 'bind .c <ButtonRelease-1> {send b1 %x %y}'
x 'bind .c <ButtonRelease-2> {send b2 %x %y}'
x update
chan b1 b2
tk namechan $wid b1
tk namechan $wid b2
while {} {tk winctl $wid ${recv $wid}} &
chan show
ifs=' 	
'
v1 := 0 0 1 1
v2 := 1 1 2 2
while {} {
	args:=${split ${recv show}}
	(t args) = $args
	$t = $args

	tk 0 .c delete lines
	echo $v1 $v2
	r := `{tstboing $v1 $v2}
	(ap1x ap1y ap2x ap2y bp1x bp1y bp2x bp2y) := $v1 $v2
	tk 0 .c create line $ap1x $ap1y $ap2x $ap2y -tags lines -fill black -width 3 -arrow last
	tk 0 .c create line $bp1x $bp1y $bp2x $bp2y -tags lines -fill red
	and {~ $#r 6} {
		(rp1x rp1y rp2x rp2y sp2x sp2y) := $r
		tk 0 .c create line $ap2x $ap2y $rp1x $rp1y -tags lines -fill black
		tk 0 .c create line $rp1x $rp1y $rp2x $rp2y -tags lines -fill green -arrow last
		tk 0 .c create line $rp1x $rp1y $sp2x $sp2y -tags lines -fill blue -arrow last
	}
	tk 0 update
} &

fn show {
	a:=$*
	if {~ $#a 8} {echo usage} {
		send show ${join ' ' $a}
	}
}

for i in 1 2 {
	while {} {
		p1:=${recv b^$i}
		p2:=${recv b^$i}
		send show ${join ' ' v^$i $p1 $p2}
	} &
}
