package main

import "path"

func main() {
	println(path.Base("/foo/bar/baz.txt"))
	println(path.Dir("/foo/bar/baz.txt"))
	println(path.Ext("/foo/bar/baz.txt"))
}
