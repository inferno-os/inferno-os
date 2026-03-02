package main
type Celsius float64
func (c Celsius) ToF() float64 {
    return float64(c)*9/5 + 32
}
func main() {
    t := Celsius(100)
    println(t.ToF())
}
