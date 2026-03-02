package main

type Stack struct {
	data []int
}

func NewStack() *Stack {
	return &Stack{data: []int{}}
}

func (s *Stack) Push(v int) {
	s.data = append(s.data, v)
}

func (s *Stack) Pop() int {
	n := len(s.data)
	v := s.data[n-1]
	s.data = s.data[:n-1]
	return v
}

func (s *Stack) Len() int {
	return len(s.data)
}

func main() {
	s := NewStack()
	s.Push(10)
	s.Push(20)
	s.Push(30)
	println(s.Len())
	println(s.Pop())
	println(s.Pop())
	println(s.Len())
}
