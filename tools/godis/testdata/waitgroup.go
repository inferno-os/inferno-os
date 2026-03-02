package main

type WaitGroup struct {
	ch    chan int
	count int
}

func newWG() *WaitGroup {
	return &WaitGroup{ch: make(chan int, 1), count: 0}
}

func (wg *WaitGroup) Add(n int) {
	wg.count = wg.count + n
}

func (wg *WaitGroup) Done() {
	wg.count = wg.count - 1
	if wg.count == 0 {
		wg.ch <- 1
	}
}

func (wg *WaitGroup) Wait() {
	if wg.count > 0 {
		<-wg.ch
	}
}

func worker(id int, result chan int, wg *WaitGroup) {
	result <- id * 10
	wg.Done()
}

func main() {
	wg := newWG()
	result := make(chan int, 3)
	wg.Add(3)
	go worker(1, result, wg)
	go worker(2, result, wg)
	go worker(3, result, wg)
	wg.Wait()
	sum := 0
	for i := 0; i < 3; i++ {
		sum = sum + <-result
	}
	println(sum)
}
