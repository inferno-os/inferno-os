package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"go/types"
	"os"

	"golang.org/x/tools/go/ssa"
)

func main() {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, os.Args[1], nil, parser.AllErrors)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	conf := &types.Config{Importer: &ssaDumpImporter{}, Error: func(e error) {}}
	info := &types.Info{
		Types:      make(map[ast.Expr]types.TypeAndValue),
		Defs:       make(map[*ast.Ident]types.Object),
		Uses:       make(map[*ast.Ident]types.Object),
		Implicits:  make(map[ast.Node]types.Object),
		Selections: make(map[*ast.SelectorExpr]*types.Selection),
		Instances:  make(map[*ast.Ident]types.Instance),
	}
	pkg, _ := conf.Check("main", fset, []*ast.File{file}, info)

	ssaProg := ssa.NewProgram(fset, ssa.InstantiateGenerics)
	for _, imp := range pkg.Imports() {
		ssaProg.CreatePackage(imp, nil, nil, true)
	}
	ssaPkg := ssaProg.CreatePackage(pkg, []*ast.File{file}, info, true)
	ssaPkg.Build()

	for _, mem := range ssaPkg.Members {
		if g, ok := mem.(*ssa.Global); ok {
			fmt.Printf("=== GLOBAL: %s (type: %s) ===\n", g.Name(), g.Type())
		}
	}
	// Show all members (including types)
	for name, mem := range ssaPkg.Members {
		switch m := mem.(type) {
		case *ssa.Type:
			fmt.Printf("=== TYPE: %s ===\n", name)
			nt := m.Type().(*types.Named)
			for i := 0; i < nt.NumMethods(); i++ {
				method := ssaProg.FuncValue(nt.Method(i))
				if method != nil && len(method.Blocks) > 0 {
					fmt.Printf("\n=== METHOD %s.%s ===\n", name, method.Name())
					fmt.Printf("  params: ")
					for j, p := range method.Params {
						if j > 0 { fmt.Printf(", ") }
						fmt.Printf("%s %s", p.Name(), p.Type())
					}
					fmt.Println()
					for _, b := range method.Blocks {
						fmt.Printf("  block %d: %s\n", b.Index, b.Comment)
						for _, instr := range b.Instrs {
							fmt.Printf("    %T: %s\n", instr, instr)
							for _, op := range instr.Operands(nil) {
								if *op != nil {
									fmt.Printf("      operand: %T %s (type: %s)\n", *op, (*op).Name(), (*op).Type())
								}
							}
						}
					}
				}
			}
		}
	}

	for _, mem := range ssaPkg.Members {
		if fn, ok := mem.(*ssa.Function); ok {
			if len(fn.Blocks) > 0 {
				fmt.Printf("\n=== %s ===\n", fn.Name())
				for _, b := range fn.Blocks {
					fmt.Printf("  block %d: %s\n", b.Index, b.Comment)
					for _, instr := range b.Instrs {
						fmt.Printf("    %T: %s\n", instr, instr)
						for _, op := range instr.Operands(nil) {
							if *op != nil {
								fmt.Printf("      operand: %T %s (type: %s)\n", *op, (*op).Name(), (*op).Type())
							}
						}
					}
				}
			}
		}
	}
}

type ssaDumpImporter struct{}

func (si *ssaDumpImporter) Import(path string) (*types.Package, error) {
	switch path {
	case "inferno/sys":
		pkg := types.NewPackage("inferno/sys", "sys")
		fdStruct := types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "fd", types.Typ[types.Int], false),
		}, nil)
		fdNamed := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FD", nil), fdStruct, nil)
		fdPtr := types.NewPointer(fdNamed)
		scope := pkg.Scope()
		scope.Insert(fdNamed.Obj())
		scope.Insert(types.NewFunc(token.NoPos, pkg, "Fildes",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "fd", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", fdPtr)), false)))
		scope.Insert(types.NewFunc(token.NoPos, pkg, "Fprint",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "fd", fdPtr),
					types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
		pkg.MarkComplete()
		return pkg, nil
	default:
		return nil, fmt.Errorf("unsupported import: %q", path)
	}
}
