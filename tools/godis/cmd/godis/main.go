// godis compiles Go source files to Dis bytecode for the Inferno OS VM.
//
// Usage:
//
//	godis [-o output.dis] file1.go [file2.go ...]
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/NERVsystems/infernode/tools/godis/compiler"
)

func main() {
	output := flag.String("o", "", "output .dis file (default: first input basename + .dis)")
	flag.Parse()

	if flag.NArg() < 1 {
		fmt.Fprintf(os.Stderr, "usage: godis [-o output.dis] file1.go [file2.go ...]\n")
		os.Exit(1)
	}

	// Collect all input files
	var filenames []string
	var sources [][]byte
	for i := 0; i < flag.NArg(); i++ {
		inputFile := flag.Arg(i)
		src, err := os.ReadFile(inputFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "godis: %v\n", err)
			os.Exit(1)
		}
		filenames = append(filenames, filepath.Base(inputFile))
		sources = append(sources, src)
	}

	// Default output name from first file
	if *output == "" {
		base := filepath.Base(flag.Arg(0))
		*output = strings.TrimSuffix(base, ".go") + ".dis"
	}

	// Compile
	c := compiler.New()
	c.BaseDir = filepath.Dir(flag.Arg(0))
	mod, err := c.CompileFiles(filenames, sources)
	if err != nil {
		fmt.Fprintf(os.Stderr, "godis: %v\n", err)
		os.Exit(1)
	}

	// Write output
	f, err := os.Create(*output)
	if err != nil {
		fmt.Fprintf(os.Stderr, "godis: %v\n", err)
		os.Exit(1)
	}
	defer f.Close()

	if err := mod.Encode(f); err != nil {
		fmt.Fprintf(os.Stderr, "godis: encode: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("godis: %s → %s (%d instructions, %d types)\n",
		flag.Arg(0), *output, len(mod.Instructions), len(mod.TypeDescs))
}
