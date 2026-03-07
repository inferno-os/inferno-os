package main

import "path/filepath"

func main() {
	println(filepath.Base("/foo/bar/baz.txt"))
	println(filepath.Dir("/foo/bar/baz.txt"))
	println(filepath.Ext("/foo/bar/baz.txt"))
	println(filepath.Clean("/foo/bar/../baz"))
	println(filepath.Join("foo", "bar", "baz"))
	if filepath.IsAbs("/absolute") {
		println("abs")
	}
	if !filepath.IsAbs("relative") {
		println("rel")
	}
}
