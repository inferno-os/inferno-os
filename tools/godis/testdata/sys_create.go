package main

import "inferno/sys"

func main() {
	fd := sys.Create("/tmp/godis_test_file", sys.ORDWR, 0666)
	if fd == nil {
		println("nil")
		return
	}
	buf := []byte("hello")
	n := sys.Write(fd, buf, len(buf))
	println(n)
	r := sys.Remove("/tmp/godis_test_file")
	println(r)
}
