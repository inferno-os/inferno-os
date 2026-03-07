package main

import "net/url"

func main() {
	escaped := url.QueryEscape("hello world")
	println(escaped)
	u, err := url.Parse("https://example.com/path?q=test")
	_ = u
	_ = err
	println("url ok")
}
