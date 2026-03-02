package main

import "inferno/sys"

func main() {
	fd := sys.Fildes(1)
	buf := []byte{72, 101, 108, 108, 111, 10} // "Hello\n"
	sys.Write(fd, buf, len(buf))
}
