// Map-based dispatch registry for stdlib lowering. Each stdlib package
// registers a lowering function that handles calls to that package.
package compiler

import "golang.org/x/tools/go/ssa"

// stdlibLowerer is the signature for a per-package lowering function.
type stdlibLowerer func(fl *funcLowerer, instr *ssa.Call, callee *ssa.Function) (bool, error)

// stdlibRegistry maps Go import paths to lowering functions.
var stdlibRegistry = map[string]stdlibLowerer{}

// RegisterStdlibLowerer registers a lowering function for the given import path.
func RegisterStdlibLowerer(path string, fn stdlibLowerer) {
	stdlibRegistry[path] = fn
}
