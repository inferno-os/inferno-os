package main

import "inferno/sys"

func main() {
	stdout := sys.Fildes(1)
	stderr := sys.Fildes(2)
	sys.Fprint(stdout, "writing to stdout\n")
	sys.Fprint(stderr, "writing to stderr\n")
}
