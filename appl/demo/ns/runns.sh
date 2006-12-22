#!/dis/sh
load std
if {~ $#* 0} {
	echo usage: runns path0 path1 ... pathn
	raise usage
}
grid/register -a resource Namespace 'grid/srv/ns '^$"* | grid/srv/monitor 1 'Namespace'
