package main

type Base struct {
	x int
}

func (b *Base) GetX() int {
	return b.x
}

type Derived struct {
	Base
	y int
}

func main() {
	d := &Derived{Base: Base{x: 10}, y: 20}
	println(d.GetX()) // 10 (promoted method)
	println(d.y)      // 20
}
