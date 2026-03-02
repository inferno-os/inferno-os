package main

type Counter struct {
	value int
}

func (c *Counter) Inc() {
	c.value++
}

func (c *Counter) Get() int {
	return c.value
}

func main() {
	c := &Counter{value: 0}
	c.Inc()
	c.Inc()
	c.Inc()
	println(c.Get())
}
