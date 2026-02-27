package main

import "log/slog"

func main() {
	slog.Info("starting up")
	slog.Warn("something happened")
	println("slog ok")
}
