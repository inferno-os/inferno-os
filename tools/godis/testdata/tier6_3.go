package main
type Reader interface{ Read() string }
type Writer interface{ Write(s string) }
type ReadWriter interface{ Reader; Writer }
type File struct{ name string; data string }
func (f *File) Read() string { return f.data }
func (f *File) Write(s string) { f.data = s }
func useRW(rw ReadWriter) {
    rw.Write("hello")
    println(rw.Read())
}
func main() {
    f := &File{name: "test"}
    useRW(f)
}
