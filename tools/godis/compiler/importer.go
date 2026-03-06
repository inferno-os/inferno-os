// Package importer provides the stubImporter that resolves Go import paths
// to type-checked package stubs for compilation to Dis bytecode.
package compiler

import (
	"fmt"
	"go/types"
)

// packageRegistry maps Go import paths to builder functions that create
// type-checked package stubs.
var packageRegistry = map[string]func() *types.Package{}

// RegisterPackage registers a package builder for the given import path.
func RegisterPackage(path string, builder func() *types.Package) {
	packageRegistry[path] = builder
}

type stubImporter struct {
	sysPackage *types.Package // cached sys package
}

func (si *stubImporter) Import(path string) (*types.Package, error) {
	// Special case: inferno/sys is cached since it's used frequently
	if path == "inferno/sys" {
		if si.sysPackage != nil {
			return si.sysPackage, nil
		}
		if builder, ok := packageRegistry[path]; ok {
			si.sysPackage = builder()
			return si.sysPackage, nil
		}
		return nil, fmt.Errorf("unsupported import: %q", path)
	}

	if builder, ok := packageRegistry[path]; ok {
		return builder(), nil
	}
	return nil, fmt.Errorf("unsupported import: %q", path)
}
