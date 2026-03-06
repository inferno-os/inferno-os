package main

import "encoding/json"

func main() {
	data := []byte(`{"key":"value"}`)
	if json.Valid(data) {
		println("valid")
	}
	_, err := json.Marshal("hello")
	_ = err
	println("json ok")
}
