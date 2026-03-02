package main

import "inferno/sys"

func main() {
	fd := sys.Fildes(1)
	sys.Fprint(fd, "hello from fprint\n")
}
