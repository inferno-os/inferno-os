package main

type Counter struct {
	n int
}

func (c *Counter) Inc() {
	c.n++
}

func (c *Counter) Get() int {
	return c.n
}

func main() {
	c := &Counter{0}
	c.Inc()
	c.Inc()
	c.Inc()
	println(c.Get())
}
