package compiler

import (
	"fmt"
	"go/ast"
	"go/constant"
	"go/parser"
	"go/token"
	"go/types"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/NERVsystems/infernode/tools/godis/dis"
	"golang.org/x/tools/go/ssa"
	"golang.org/x/tools/go/ssa/ssautil"
)

// ifaceImpl records one concrete implementation of an interface method.
type ifaceImpl struct {
	tag int32         // type tag ID for the concrete type
	fn  *ssa.Function // the concrete method
}

// Compiler compiles Go source to Dis bytecode.
type Compiler struct {
	strings      map[string]int32        // string literal → MP offset (deduplicating)
	reals        map[float64]int32       // float literal → MP offset (deduplicating)
	globals      map[string]int32        // global variable name → MP offset
	sysUsed      map[string]int          // Sys function name → LDT index
	mod          *ModuleData
	sysMPOff     int32
	errors       []string
	closureMap   map[ssa.Value]*ssa.Function // MakeClosure result → inner function
	closureRetFn map[*ssa.Function]*ssa.Function // func that returns a closure → inner fn
	// Interface dispatch: method name → concrete method function.
	methodMap    map[string]*ssa.Function // "TypeName.MethodName" → *ssa.Function
	// Type tag registry for tagged interface dispatch.
	typeTagMap    map[string]int32   // concrete type name → tag ID (starts at 1)
	typeTagNext   int32              // next tag to allocate
	ifaceDispatch map[string][]ifaceImpl // method name → [{tag, fn}, ...]
	excGlobalOff int32 // MP offset for exception bridge slot (lazy-allocated, 0 = not allocated)
	embedInits   []embedInit // go:embed entries to initialize at module load
	initFuncs    []*ssa.Function // user-defined init functions (init#1, init#2, ...) to call before main
	closureFuncTags    map[*ssa.Function]int32 // inner function → unique tag for dynamic dispatch
	closureFuncTagNext int32                   // next tag to allocate (starts at 1)
	BaseDir      string // directory containing main package (for resolving local imports)
}

// New creates a new Compiler.
func New() *Compiler {
	return &Compiler{
		strings:       make(map[string]int32),
		reals:         make(map[float64]int32),
		globals:       make(map[string]int32),
		sysUsed:       make(map[string]int),
		closureMap:    make(map[ssa.Value]*ssa.Function),
		closureRetFn:  make(map[*ssa.Function]*ssa.Function),
		methodMap:     make(map[string]*ssa.Function),
		typeTagMap:    make(map[string]int32),
		typeTagNext:   1, // tag 0 = nil interface
		ifaceDispatch:      make(map[string][]ifaceImpl),
		closureFuncTags:    make(map[*ssa.Function]int32),
		closureFuncTagNext: 1, // tag 0 = reserved
	}
}

// AllocTypeTag returns (or allocates) a unique integer tag for a concrete type name.
// Tag 0 is reserved for nil interfaces.
func (c *Compiler) AllocTypeTag(typeName string) int32 {
	if tag, ok := c.typeTagMap[typeName]; ok {
		return tag
	}
	tag := c.typeTagNext
	c.typeTagNext++
	c.typeTagMap[typeName] = tag
	return tag
}

// AllocClosureTag returns (or allocates) a unique integer tag for an inner function.
// Used for dynamic closure dispatch.
func (c *Compiler) AllocClosureTag(fn *ssa.Function) int32 {
	if tag, ok := c.closureFuncTags[fn]; ok {
		return tag
	}
	tag := c.closureFuncTagNext
	c.closureFuncTagNext++
	c.closureFuncTags[fn] = tag
	return tag
}

// registerClosure records that a MakeClosure instruction creates a closure for innerFn.
func (c *Compiler) registerClosure(mc *ssa.MakeClosure, innerFn *ssa.Function) {
	c.closureMap[mc] = innerFn
	// Also track the parent function's return: if this MakeClosure is returned,
	// callers of the parent can resolve the closure target.
	if mc.Parent() != nil {
		c.closureRetFn[mc.Parent()] = innerFn
	}
}

// resolveClosureTarget traces an SSA value back to determine which inner function
// a closure refers to. Returns nil if it cannot be statically resolved.
func (c *Compiler) resolveClosureTarget(v ssa.Value) *ssa.Function {
	// Direct MakeClosure result
	if fn, ok := c.closureMap[v]; ok {
		return fn
	}
	// Return value of a function that always returns a specific closure
	if call, ok := v.(*ssa.Call); ok {
		if callee, ok := call.Call.Value.(*ssa.Function); ok {
			if fn, ok := c.closureRetFn[callee]; ok {
				return fn
			}
		}
	}
	return nil
}

// ResolveInterfaceMethods finds all concrete implementations for a method name
// called on an interface. Returns a list of {tag, fn} pairs — one per concrete type.
func (c *Compiler) ResolveInterfaceMethods(methodName string) []ifaceImpl {
	if impls, ok := c.ifaceDispatch[methodName]; ok && len(impls) > 0 {
		return impls
	}
	return nil
}

// AllocGlobal allocates storage for a global variable in the module data section.
// Returns the MP offset. Pointer-typed globals are tracked for GC.
func (c *Compiler) AllocGlobal(name string, isPtr bool) int32 {
	if off, ok := c.globals[name]; ok {
		return off
	}
	var off int32
	if isPtr {
		off = c.mod.AllocPointer("global:" + name)
	} else {
		off = c.mod.AllocWord("global:" + name)
	}
	c.globals[name] = off
	return off
}

// GlobalOffset returns the MP offset for a global variable, or -1 if not allocated.
func (c *Compiler) GlobalOffset(name string) (int32, bool) {
	off, ok := c.globals[name]
	return off, ok
}

// AllocString allocates a string literal in the module data section,
// deduplicating identical strings. Returns the MP offset.
func (c *Compiler) AllocString(s string) int32 {
	if off, ok := c.strings[s]; ok {
		return off
	}
	off := c.mod.AllocPointer("str")
	c.strings[s] = off
	return off
}

// AllocReal allocates a float64 literal in the module data section,
// deduplicating identical values. Returns the MP offset.
func (c *Compiler) AllocReal(val float64) int32 {
	if off, ok := c.reals[val]; ok {
		return off
	}
	off := c.mod.AllocWord("real")
	c.reals[val] = off
	return off
}

// AllocExcGlobal lazily allocates the exception bridge slot in module data.
// This is a WORD (not pointer) used to pass exception values from handler to deferred closures.
func (c *Compiler) AllocExcGlobal() int32 {
	if c.excGlobalOff == 0 {
		c.excGlobalOff = c.mod.AllocWord("excval")
	}
	return c.excGlobalOff
}

// compiledFunc holds the compilation result for a single function.
type compiledFunc struct {
	fn     *ssa.Function
	result *lowerResult
}

// CompileFile compiles a single Go source file to a Dis module.
func (c *Compiler) CompileFile(filename string, src []byte) (*dis.Module, error) {
	return c.CompileFiles([]string{filename}, [][]byte{src})
}

// importResult holds the parsed/type-checked result of a local package import.
type importResult struct {
	pkg   *types.Package
	files []*ast.File
	info  *types.Info
}

// localImporter resolves imports: first checking known stubs, then looking for
// local package directories relative to baseDir.
type localImporter struct {
	stub    stubImporter
	baseDir string              // directory containing main package source
	fset    *token.FileSet      // shared fileset
	cache   map[string]*importResult // import path → result
	errors  *[]string           // shared error list
}

func (li *localImporter) Import(path string) (*types.Package, error) {
	// Try stub first (fmt, strings, math, etc.)
	pkg, err := li.stub.Import(path)
	if err == nil {
		return pkg, nil
	}

	// Check cache
	if result, ok := li.cache[path]; ok {
		return result.pkg, nil
	}

	// Resolve from disk: baseDir/path/
	dir := filepath.Join(li.baseDir, path)
	entries, dirErr := os.ReadDir(dir)
	if dirErr != nil {
		return nil, fmt.Errorf("unsupported import: %q (not a stub and directory %s not found)", path, dir)
	}

	// Parse all .go files in the directory
	var files []*ast.File
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".go") {
			continue
		}
		// Skip test files
		if strings.HasSuffix(entry.Name(), "_test.go") {
			continue
		}
		filePath := filepath.Join(dir, entry.Name())
		src, readErr := os.ReadFile(filePath)
		if readErr != nil {
			return nil, fmt.Errorf("read %s: %w", filePath, readErr)
		}
		f, parseErr := parser.ParseFile(li.fset, entry.Name(), src, parser.AllErrors)
		if parseErr != nil {
			return nil, fmt.Errorf("parse %s: %w", filePath, parseErr)
		}
		files = append(files, f)
	}
	if len(files) == 0 {
		return nil, fmt.Errorf("no .go files in %s", dir)
	}

	// Type-check with recursive import resolution
	info := &types.Info{
		Types:      make(map[ast.Expr]types.TypeAndValue),
		Defs:       make(map[*ast.Ident]types.Object),
		Uses:       make(map[*ast.Ident]types.Object),
		Implicits:  make(map[ast.Node]types.Object),
		Selections: make(map[*ast.SelectorExpr]*types.Selection),
		Instances:  make(map[*ast.Ident]types.Instance),
	}
	conf := &types.Config{
		Importer: li, // recursive: local packages can import other local packages
		Error: func(err error) {
			*li.errors = append(*li.errors, err.Error())
		},
	}
	// Determine package name from first file
	pkgName := files[0].Name.Name
	typePkg, checkErr := conf.Check(path, li.fset, files, info)
	if checkErr != nil {
		return nil, fmt.Errorf("typecheck %s: %w", pkgName, checkErr)
	}

	li.cache[path] = &importResult{pkg: typePkg, files: files, info: info}
	return typePkg, nil
}

// localPackages returns all locally-resolved packages (not stubs) in dependency order.
func (li *localImporter) localPackages() []*importResult {
	// Return in sorted order for determinism
	var paths []string
	for path := range li.cache {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	var results []*importResult
	for _, p := range paths {
		results = append(results, li.cache[p])
	}
	return results
}

// CompileFiles compiles one or more Go source files to a Dis module.
// All files must declare the same package (typically "main").
func (c *Compiler) CompileFiles(filenames []string, sources [][]byte) (*dis.Module, error) {
	fset := token.NewFileSet()

	// Parse all files (ParseComments needed for //go:embed directives)
	var files []*ast.File
	for i, filename := range filenames {
		file, err := parser.ParseFile(fset, filename, sources[i], parser.AllErrors|parser.ParseComments)
		if err != nil {
			return nil, fmt.Errorf("parse %s: %w", filename, err)
		}
		files = append(files, file)
	}

	// Verify all files declare the same package
	if len(files) > 1 {
		pkgName := files[0].Name.Name
		for i := 1; i < len(files); i++ {
			if files[i].Name.Name != pkgName {
				return nil, fmt.Errorf("multiple packages: %s and %s", pkgName, files[i].Name.Name)
			}
		}
	}

	// Set up importer
	importer := &localImporter{
		baseDir: c.BaseDir,
		fset:    fset,
		cache:   make(map[string]*importResult),
		errors:  &c.errors,
	}

	// Type-check
	conf := &types.Config{
		Importer: importer,
		Error: func(err error) {
			c.errors = append(c.errors, err.Error())
		},
	}
	info := &types.Info{
		Types:      make(map[ast.Expr]types.TypeAndValue),
		Defs:       make(map[*ast.Ident]types.Object),
		Uses:       make(map[*ast.Ident]types.Object),
		Implicits:  make(map[ast.Node]types.Object),
		Selections: make(map[*ast.SelectorExpr]*types.Selection),
		Instances:  make(map[*ast.Ident]types.Instance),
	}

	pkg, err := conf.Check("main", fset, files, info)
	if err != nil {
		return nil, fmt.Errorf("typecheck: %w", err)
	}

	// Build SSA with InstantiateGenerics to monomorphize generic functions.
	// This creates specialized copies for each concrete type instantiation.
	ssaProg := ssa.NewProgram(fset, ssa.InstantiateGenerics)

	// Create SSA packages for all imports
	localPkgs := make(map[string]*importResult) // path → result for local packages
	for _, imp := range pkg.Imports() {
		if result, ok := importer.cache[imp.Path()]; ok {
			// Local package — build with real AST
			ssaProg.CreatePackage(imp, result.files, result.info, true)
			localPkgs[imp.Path()] = result
		} else {
			// Stub package — no AST needed
			ssaProg.CreatePackage(imp, nil, nil, true)
		}
	}

	// Also create SSA packages for transitive local imports
	// (local packages may import other local packages)
	for path, result := range importer.cache {
		if _, ok := localPkgs[path]; ok {
			continue // already handled
		}
		// This is a transitively imported local package
		ssaProg.CreatePackage(result.pkg, result.files, result.info, true)
		localPkgs[path] = result
		// Also create SSA packages for ITS imports
		for _, transImp := range result.pkg.Imports() {
			if _, ok2 := importer.cache[transImp.Path()]; ok2 {
				continue // will be handled by outer loop or already done
			}
			// Stub import from a local package
			if ssaProg.Package(transImp) == nil {
				ssaProg.CreatePackage(transImp, nil, nil, true)
			}
		}
	}

	ssaPkg := ssaProg.CreatePackage(pkg, files, info, true)
	ssaPkg.Build()

	// Build local packages too
	for _, result := range localPkgs {
		ssaImpPkg := ssaProg.Package(result.pkg)
		if ssaImpPkg != nil {
			ssaImpPkg.Build()
		}
	}

	// Find the main function
	mainFn := ssaPkg.Func("main")
	if mainFn == nil {
		return nil, fmt.Errorf("no main function found")
	}

	// Set up module data
	c.mod = NewModuleData()
	c.sysMPOff = c.mod.AllocPointer("sys") // Sys module ref at MP+0

	// Pre-register Sys functions (scan all user packages)
	userPkgs := map[*ssa.Package]bool{ssaPkg: true}
	for _, result := range localPkgs {
		ssaImpPkg := ssaProg.Package(result.pkg)
		if ssaImpPkg != nil {
			userPkgs[ssaImpPkg] = true
		}
	}
	c.scanSysCallsMulti(ssaProg, userPkgs)

	// Allocate "$Sys" path string in module data
	sysPathOff := c.AllocString("$Sys")

	// Allocate storage for package-level global variables in MP (main package)
	for _, mem := range ssaPkg.Members {
		if g, ok := mem.(*ssa.Global); ok {
			elemType := g.Type().(*types.Pointer).Elem()
			dt := GoTypeToDis(elemType)
			c.AllocGlobal(g.Name(), dt.IsPtr)
		}
	}

	// Allocate globals from local imported packages (prefixed to avoid collisions)
	for path, result := range localPkgs {
		ssaImpPkg := ssaProg.Package(result.pkg)
		if ssaImpPkg == nil {
			continue
		}
		for _, mem := range ssaImpPkg.Members {
			if g, ok := mem.(*ssa.Global); ok {
				elemType := g.Type().(*types.Pointer).Elem()
				dt := GoTypeToDis(elemType)
				globalName := path + "." + g.Name()
				c.AllocGlobal(globalName, dt.IsPtr)
			}
		}
	}

	// Process //go:embed directives: scan AST for embedded file references
	// and pre-initialize the corresponding global variables in the data section.
	c.processEmbedDirectives(files, fset)

	// Collect all functions to compile: main first, then others alphabetically.
	// This includes both package-level functions and methods on named types.
	allFuncs := []*ssa.Function{mainFn}
	seen := map[*ssa.Function]bool{mainFn: true}

	// Collect from main package
	c.collectPackageFuncs(ssaProg, ssaPkg, &allFuncs, seen)

	// Collect from local imported packages (dependency order: imports first)
	for _, result := range importer.localPackages() {
		ssaImpPkg := ssaProg.Package(result.pkg)
		if ssaImpPkg != nil {
			c.collectPackageFuncs(ssaProg, ssaImpPkg, &allFuncs, seen)
		}
	}

	// Register synthetic errorString type for error interface dispatch.
	// Must happen after named type method scanning so it doesn't conflict.
	c.RegisterErrorString()

	// Discover monomorphized generic instances (e.g. Min[int], Min[string]).
	// These have pkg=nil and are found via ssautil.AllFunctions.
	for fn := range ssautil.AllFunctions(ssaProg) {
		if !seen[fn] && len(fn.Blocks) > 0 && len(fn.TypeArgs()) > 0 {
			// This is a monomorphized generic instance
			allFuncs = append(allFuncs, fn)
			seen[fn] = true
		}
	}

	// Recursively discover anonymous/inner functions (closures)
	for i := 0; i < len(allFuncs); i++ {
		for _, anon := range allFuncs[i].AnonFuncs {
			if !seen[anon] && len(anon.Blocks) > 0 {
				allFuncs = append(allFuncs, anon)
				seen[anon] = true
			}
		}
	}

	sort.Slice(allFuncs[1:], func(i, j int) bool {
		return allFuncs[1+i].Name() < allFuncs[1+j].Name()
	})

	// Pre-scan: discover closure relationships before compilation
	// This is needed because main is compiled first but may call closures
	// created by functions compiled later.
	c.scanClosures(allFuncs)

	// Discover bound method wrappers (e.g. (*T).Method$bound) from MakeClosure targets.
	// These are synthetic functions created by SSA that aren't package members or AnonFuncs.
	for _, innerFn := range c.closureMap {
		if !seen[innerFn] && len(innerFn.Blocks) > 0 {
			allFuncs = append(allFuncs, innerFn)
			seen[innerFn] = true
			// Also discover their anonymous functions recursively
			for i := len(allFuncs) - 1; i < len(allFuncs); i++ {
				for _, anon := range allFuncs[i].AnonFuncs {
					if !seen[anon] && len(anon.Blocks) > 0 {
						allFuncs = append(allFuncs, anon)
						seen[anon] = true
					}
				}
			}
		}
	}

	// Phase 1: Compile all functions
	var compiled []compiledFunc
	for _, fn := range allFuncs {
		fl := newFuncLowerer(fn, c, c.sysMPOff, c.sysUsed)
		result, err := fl.lower()
		if err != nil {
			return nil, fmt.Errorf("compile %s: %w", fn.Name(), err)
		}
		compiled = append(compiled, compiledFunc{fn, result})
	}

	// Phase 2: Assign type descriptor IDs
	// TD 0 = module data (MP)
	// TD 1..N = function frame type descriptors (main=1, then others)
	// TD N+1.. = call-site type descriptors
	funcTDID := make(map[*ssa.Function]int)
	nextTD := 1
	for _, cf := range compiled {
		funcTDID[cf.fn] = nextTD
		nextTD++
	}
	callTDBase := nextTD

	// Phase 3: Compute function start PCs
	// Layout: [LOAD preamble] [main insts] [func1 insts] [func2 insts] ...
	entryLen := int32(1) // just the LOAD instruction
	funcStartPC := make(map[*ssa.Function]int32)
	offset := entryLen
	for _, cf := range compiled {
		funcStartPC[cf.fn] = offset
		offset += int32(len(cf.result.insts))
	}

	// Phase 4: Patch all instructions
	callTDOffset := callTDBase
	for _, cf := range compiled {
		startPC := funcStartPC[cf.fn]

		// Build set of instruction indices that have funcCallPatches
		patchedInsts := make(map[int]bool)
		for _, p := range cf.result.funcCallPatches {
			patchedInsts[p.instIdx] = true
			inst := &cf.result.insts[p.instIdx]
			switch p.patchKind {
			case patchIFRAME:
				inst.Src = dis.Imm(int32(funcTDID[p.callee]))
			case patchICALL:
				inst.Dst = dis.Imm(funcStartPC[p.callee])
			}
		}

		for i := range cf.result.insts {
			if patchedInsts[i] {
				continue // already patched above
			}
			inst := &cf.result.insts[i]

			// Patch call-site type descriptor IDs
			// IFRAME/INEW: TD ID is in src operand
			if (inst.Op == dis.IFRAME || inst.Op == dis.INEW) && inst.Src.Mode == dis.AIMM {
				inst.Src.Val += int32(callTDOffset)
			}
			// NEWA: element TD ID is in mid operand
			if inst.Op == dis.INEWA && inst.Mid.Mode == dis.AIMM {
				inst.Mid.Val += int32(callTDOffset)
			}

			// Patch intra-function branch targets to global PCs
			if inst.Op.IsBranch() && inst.Dst.Mode == dis.AIMM {
				inst.Dst.Val += startPC
			}
		}

		callTDOffset += len(cf.result.callTypeDescs)
	}

	// Phase 5: Build type descriptor array
	var allTypeDescs []dis.TypeDesc
	allTypeDescs = append(allTypeDescs, dis.TypeDesc{}) // TD 0 = MP (filled in later)

	for _, cf := range compiled {
		allTypeDescs = append(allTypeDescs, cf.result.frame.TypeDesc(funcTDID[cf.fn]))
	}

	// Add call-site type descriptors
	tdID := callTDBase
	for _, cf := range compiled {
		for i := range cf.result.callTypeDescs {
			cf.result.callTypeDescs[i].ID = tdID + i
		}
		allTypeDescs = append(allTypeDescs, cf.result.callTypeDescs...)
		tdID += len(cf.result.callTypeDescs)
	}

	allTypeDescs[0] = c.mod.TypeDesc(0)

	// Phase 5.5: Collect exception handlers from all functions
	var allHandlers []dis.Handler
	for _, cf := range compiled {
		startPC := funcStartPC[cf.fn]
		for _, h := range cf.result.handlers {
			allHandlers = append(allHandlers, dis.Handler{
				EOffset: h.eoff,
				PC1:     h.pc1 + startPC,
				PC2:     h.pc2 + startPC,
				DescID:  -1, // string-only exceptions
				NE:      0,
				Etab:    nil,
				WildPC:  h.wildPC + startPC,
			})
		}
	}

	// Phase 6: Concatenate instructions
	var allInsts []dis.Inst
	allInsts = append(allInsts,
		dis.NewInst(dis.ILOAD, dis.MP(sysPathOff), dis.Imm(0), dis.MP(c.sysMPOff)),
	)
	for _, cf := range compiled {
		allInsts = append(allInsts, cf.result.insts...)
	}

	// Ensure last instruction is RET
	if len(allInsts) == 0 || allInsts[len(allInsts)-1].Op != dis.IRET {
		allInsts = append(allInsts, dis.Inst0(dis.IRET))
	}

	// Build module name from first filename
	moduleName := strings.TrimSuffix(filenames[0], ".go")
	if len(moduleName) > 0 {
		moduleName = strings.ToUpper(moduleName[:1]) + moduleName[1:]
	}

	mainTDID := int32(funcTDID[mainFn])

	m := dis.NewModule(moduleName)
	m.RuntimeFlags = dis.HASLDT
	if len(allHandlers) > 0 {
		m.RuntimeFlags |= dis.HASEXCEPT
		m.Handlers = allHandlers
	}
	m.Instructions = allInsts
	m.TypeDescs = allTypeDescs
	m.DataSize = c.mod.Size()
	m.EntryPC = 0
	m.EntryType = mainTDID

	// Build data section with all string literals
	m.Data = c.buildDataSection()

	// Build links (exported functions)
	// Signature 0x4244b354 is for init(ctxt: ref Draw->Context, args: list of string)
	m.Links = []dis.Link{
		{PC: 0, DescID: mainTDID, Sig: 0x4244b354, Name: "init"},
	}

	// Build LDT
	m.LDT = c.buildLDT()

	m.SrcPath = filenames[0]

	_ = ssautil.AllFunctions(ssaProg) // for future use

	return m, nil
}

// collectPackageFuncs collects functions, methods, and init funcs from an SSA package.
func (c *Compiler) collectPackageFuncs(ssaProg *ssa.Program, ssaPkg *ssa.Package, allFuncs *[]*ssa.Function, seen map[*ssa.Function]bool) {
	for _, mem := range ssaPkg.Members {
		switch m := mem.(type) {
		case *ssa.Function:
			// Skip generic template functions (typeParams > 0, typeArgs = 0);
			// only their monomorphized instances are compiled.
			if m.TypeParams().Len() > 0 && len(m.TypeArgs()) == 0 {
				seen[m] = true
				break
			}
			if !seen[m] && m.Name() != "init" && len(m.Blocks) > 0 {
				*allFuncs = append(*allFuncs, m)
				seen[m] = true
				// User-defined init functions appear as init#1, init#2, etc.
				if strings.HasPrefix(m.Name(), "init#") {
					c.initFuncs = append(c.initFuncs, m)
				}
			}
		case *ssa.Type:
			// Collect methods on named types
			nt, ok := m.Type().(*types.Named)
			if !ok {
				continue
			}
			for i := 0; i < nt.NumMethods(); i++ {
				method := ssaProg.FuncValue(nt.Method(i))
				if method != nil && !seen[method] && len(method.Blocks) > 0 {
					*allFuncs = append(*allFuncs, method)
					seen[method] = true
					// Register in methodMap for interface dispatch
					typeName := nt.Obj().Name()
					key := typeName + "." + method.Name()
					c.methodMap[key] = method
					// Register in ifaceDispatch with type tag
					tag := c.AllocTypeTag(typeName)
					c.ifaceDispatch[method.Name()] = append(
						c.ifaceDispatch[method.Name()],
						ifaceImpl{tag: tag, fn: method})
				}
			}
		}
	}
}

// scanClosures pre-scans all functions to discover closure relationships.
// For each function that contains a MakeClosure instruction, record:
// 1. The MakeClosure value → inner function mapping
// 2. If the function returns a MakeClosure, record parent → inner function
// 3. Allocate function tags for dynamic dispatch
func (c *Compiler) scanClosures(allFuncs []*ssa.Function) {
	for _, fn := range allFuncs {
		for _, block := range fn.Blocks {
			for _, instr := range block.Instrs {
				if mc, ok := instr.(*ssa.MakeClosure); ok {
					innerFn := mc.Fn.(*ssa.Function)
					c.closureMap[mc] = innerFn
					c.closureRetFn[fn] = innerFn
					// Pre-allocate function tag for dynamic dispatch
					c.AllocClosureTag(innerFn)
				}
			}
		}
	}
}

func (c *Compiler) scanSysCalls(ssaProg *ssa.Program, pkg *ssa.Package) {
	c.scanSysCallsMulti(ssaProg, map[*ssa.Package]bool{pkg: true})
}

// scanSysCallsMulti scans all functions in the given user packages for Sys module calls.
func (c *Compiler) scanSysCallsMulti(ssaProg *ssa.Program, userPkgs map[*ssa.Package]bool) {
	// Always register print at index 0 (used by println builtin)
	c.sysUsed["print"] = 0

	// Scan all functions (including methods) for sys module calls
	allFns := ssautil.AllFunctions(ssaProg)
	for fn := range allFns {
		if fn.Package() == nil || !userPkgs[fn.Package()] {
			continue
		}
		for _, block := range fn.Blocks {
			for _, instr := range block.Instrs {
				call, ok := instr.(*ssa.Call)
				if !ok {
					continue
				}
				callee, ok := call.Call.Value.(*ssa.Function)
				if !ok {
					continue
				}
				if callee.Package() != nil && callee.Package().Pkg.Path() == "inferno/sys" {
					disName, ok := sysGoToDisName[callee.Name()]
					if ok {
						if _, exists := c.sysUsed[disName]; !exists {
							c.sysUsed[disName] = len(c.sysUsed)
						}
					}
				}
			}
		}
	}
}

func (c *Compiler) buildDataSection() []dis.DataItem {
	var items []dis.DataItem

	type strEntry struct {
		s   string
		off int32
	}
	var entries []strEntry
	for s, off := range c.strings {
		entries = append(entries, strEntry{s, off})
	}
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].off < entries[j].off
	})

	for _, e := range entries {
		items = append(items, dis.DefString(e.off, e.s))
	}

	// Float constants
	type realEntry struct {
		val float64
		off int32
	}
	var realEntries []realEntry
	for val, off := range c.reals {
		realEntries = append(realEntries, realEntry{val, off})
	}
	sort.Slice(realEntries, func(i, j int) bool {
		return realEntries[i].off < realEntries[j].off
	})
	for _, e := range realEntries {
		items = append(items, dis.DefReal(e.off, e.val))
	}

	return items
}

func (c *Compiler) buildLDT() [][]dis.Import {
	if len(c.sysUsed) == 0 {
		return nil
	}

	type entry struct {
		name string
		idx  int
	}
	var entries []entry
	for name, idx := range c.sysUsed {
		entries = append(entries, entry{name, idx})
	}
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].idx < entries[j].idx
	})

	var imports []dis.Import
	for _, e := range entries {
		sf := LookupSysFunc(e.name)
		if sf != nil {
			imports = append(imports, dis.Import{
				Sig:  sf.Sig,
				Name: sf.Name,
			})
		}
	}
	return [][]dis.Import{imports}
}

type stubImporter struct {
	sysPackage *types.Package // cached sys package
}

func (si *stubImporter) Import(path string) (*types.Package, error) {
	switch path {
	case "fmt":
		return buildFmtPackage(), nil
	case "strconv":
		return buildStrconvPackage(), nil
	case "errors":
		return buildErrorsPackage(), nil
	case "strings":
		return buildStringsPackage(), nil
	case "math":
		return buildMathPackage(), nil
	case "os":
		return buildOsPackage(), nil
	case "time":
		return buildTimePackage(), nil
	case "sync":
		return buildSyncPackage(), nil
	case "sort":
		return buildSortPackage(), nil
	case "io":
		return buildIOPackage(), nil
	case "log":
		return buildLogPackage(), nil
	case "embed":
		return buildEmbedPackage(), nil
	case "unsafe":
		return buildUnsafePackage(), nil
	case "math/cmplx":
		return buildCmplxPackage(), nil
	case "inferno/sys":
		if si.sysPackage != nil {
			return si.sysPackage, nil
		}
		si.sysPackage = buildSysPackage()
		return si.sysPackage, nil
	default:
		return nil, fmt.Errorf("unsupported import: %q", path)
	}
}

// buildErrorsPackage creates the type-checked errors package stub
// with the signature for New(text string) error.
func buildErrorsPackage() *types.Package {
	pkg := types.NewPackage("errors", "errors")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// func New(text string) error
	newSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String])),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New", newSig))

	pkg.MarkComplete()
	return pkg
}

// RegisterErrorString registers the synthetic errorString type in the
// interface dispatch table. errorString.Error() is handled inline (fn=nil)
// rather than calling a real function.
func (c *Compiler) RegisterErrorString() {
	tag := c.AllocTypeTag("errorString")
	c.ifaceDispatch["Error"] = append(
		c.ifaceDispatch["Error"],
		ifaceImpl{tag: tag, fn: nil})
}

// buildStrconvPackage creates the type-checked strconv package stub
// with signatures for Itoa, Atoi, and FormatInt.
func buildStrconvPackage() *types.Package {
	pkg := types.NewPackage("strconv", "strconv")
	scope := pkg.Scope()

	// func Itoa(i int) string
	itoaSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int])),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Itoa", itoaSig))

	// func Atoi(s string) (int, error)
	errType := types.Universe.Lookup("error").Type()
	atoiSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
			types.NewVar(token.NoPos, pkg, "", errType),
		),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Atoi", atoiSig))

	// func FormatInt(i int64, base int) string
	formatIntSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int64]),
			types.NewVar(token.NoPos, pkg, "base", types.Typ[types.Int]),
		),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FormatInt", formatIntSig))

	pkg.MarkComplete()
	return pkg
}

// buildFmtPackage creates the type-checked fmt package stub
// with signatures for Sprintf, Printf, and Println.
func buildFmtPackage() *types.Package {
	pkg := types.NewPackage("fmt", "fmt")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anySlice := types.NewSlice(types.NewInterfaceType(nil, nil))

	// func Sprintf(format string, a ...any) string
	sprintfSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
			types.NewVar(token.NoPos, pkg, "a", anySlice),
		),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sprintf", sprintfSig))

	// func Printf(format string, a ...any) (int, error)
	printfSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
			types.NewVar(token.NoPos, pkg, "a", anySlice),
		),
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
			types.NewVar(token.NoPos, pkg, "", errType),
		),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Printf", printfSig))

	// func Println(a ...any) (int, error)
	printlnSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, pkg, "a", anySlice)),
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
			types.NewVar(token.NoPos, pkg, "", errType),
		),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Println", printlnSig))

	// func Errorf(format string, a ...any) error
	errorfSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
			types.NewVar(token.NoPos, pkg, "a", anySlice),
		),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
		true)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Errorf", errorfSig))

	pkg.MarkComplete()
	return pkg
}

// buildSysPackage creates the type-checked inferno/sys package with
// FD type and function signatures matching the Inferno Sys module.
func buildSysPackage() *types.Package {
	pkg := types.NewPackage("inferno/sys", "sys")

	// FD type: opaque struct wrapping a file descriptor
	fdStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "fd", types.Typ[types.Int], false),
	}, nil)
	fdNamed := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FD", nil), fdStruct, nil)
	fdPtr := types.NewPointer(fdNamed)

	scope := pkg.Scope()
	scope.Insert(fdNamed.Obj())

	// Fildes(fd int) *FD
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fildes",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "fd", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fdPtr)),
			false)))

	// Open(name string, mode int) *FD
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "mode", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fdPtr)),
			false)))

	// Write(fd *FD, buf []byte, n int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fd", fdPtr),
				types.NewVar(token.NoPos, nil, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Read(fd *FD, buf []byte, n int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fd", fdPtr),
				types.NewVar(token.NoPos, nil, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Fprint(fd *FD, s string, args ...any) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fprint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fd", fdPtr),
				types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Sleep(ms int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sleep",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "ms", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Millisec() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Millisec",
		types.NewSignatureType(nil, nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Create(name string, mode int, perm int) *FD
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Create",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "mode", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "perm", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fdPtr)),
			false)))

	// Seek(fd *FD, off int, start int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Seek",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fd", fdPtr),
				types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "start", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Bind(name string, old string, flags int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Bind",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "old", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "flags", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Chdir(path string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chdir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Remove(name string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Remove",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Pipe(fds []FD) int — simplified: takes slice of *FD, returns int
	// In Limbo: pipe(fds: array of ref FD): int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pipe",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "fds", types.NewSlice(fdPtr))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Dup(old int, new int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "old", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Pctl(flags int, movefd []int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pctl",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "flags", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "movefd", types.NewSlice(types.Typ[types.Int]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// Constants: OREAD=0, OWRITE=1, ORDWR=2, OTRUNC=16, ORCLOSE=64, OEXCL=4096
	scope.Insert(types.NewConst(token.NoPos, pkg, "OREAD", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "OWRITE", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ORDWR", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "OTRUNC", types.Typ[types.Int], constant.MakeInt64(16)))

	// Bind flags
	scope.Insert(types.NewConst(token.NoPos, pkg, "MREPL", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MBEFORE", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MAFTER", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MCREATE", types.Typ[types.Int], constant.MakeInt64(4)))

	// Pctl flags
	scope.Insert(types.NewConst(token.NoPos, pkg, "NEWPGRP", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FORKNS", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FORKFD", types.Typ[types.Int], constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NEWFD", types.Typ[types.Int], constant.MakeInt64(8)))

	// Seek constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "SEEKSTART", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SEEKRELA", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SEEKEND", types.Typ[types.Int], constant.MakeInt64(2)))

	pkg.MarkComplete()
	return pkg
}

// buildStringsPackage creates the type-checked strings package stub.
func buildStringsPackage() *types.Package {
	pkg := types.NewPackage("strings", "strings")
	scope := pkg.Scope()

	// func Contains(s, substr string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Contains",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "substr", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func HasPrefix(s, prefix string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HasPrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func HasSuffix(s, suffix string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HasSuffix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "suffix", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Index(s, substr string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "substr", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func TrimSpace(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimSpace",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Split(s, sep string) []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Split",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "sep", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// func Join(elems []string, sep string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Join",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "elems", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "sep", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Replace(s, old, new string, n int) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Replace",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "old", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "new", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ToUpper(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToUpper",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ToLower(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToLower",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Repeat(s string, count int) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Repeat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "count", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildMathPackage creates the type-checked math package stub.
func buildMathPackage() *types.Package {
	pkg := types.NewPackage("math", "math")
	scope := pkg.Scope()

	// func Abs(x float64) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Abs",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Sqrt(x float64) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sqrt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Min(x, y float64) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Min",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Max(x, y float64) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Max",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildOsPackage creates the type-checked os package stub.
func buildOsPackage() *types.Package {
	pkg := types.NewPackage("os", "os")
	scope := pkg.Scope()

	// func Exit(code int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Exit",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "code", types.Typ[types.Int])),
			nil,
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildTimePackage creates the type-checked time package stub.
// Duration is int64 (nanoseconds). Time is a struct wrapping milliseconds.
func buildTimePackage() *types.Package {
	pkg := types.NewPackage("time", "time")
	scope := pkg.Scope()

	// type Duration int64 (nanoseconds)
	durationType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Duration", nil),
		types.Typ[types.Int64], nil)
	scope.Insert(durationType.Obj())

	// type Time struct { msec int }
	timeStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "msec", types.Typ[types.Int], false),
	}, nil)
	timeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Time", nil),
		timeStruct, nil)
	scope.Insert(timeType.Obj())

	// func Now() Time
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Now",
		types.NewSignatureType(nil, nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)),
			false)))

	// func Since(t Time) Duration
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Since",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", timeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", durationType)),
			false)))

	// func Sleep(d Duration)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sleep",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", durationType)),
			nil,
			false)))

	// func After(d Duration) <-chan Time
	chanType := types.NewChan(types.RecvOnly, timeType)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "After",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", durationType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", chanType)),
			false)))

	// Duration constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "Nanosecond", durationType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Microsecond", durationType, constant.MakeInt64(1000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Millisecond", durationType, constant.MakeInt64(1000000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Second", durationType, constant.MakeInt64(1000000000)))

	// func (d Duration) Milliseconds() int64
	durationType.AddMethod(types.NewFunc(token.NoPos, pkg, "Milliseconds",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "d", durationType),
			nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))

	// func (t Time) Sub(u Time) Duration
	timeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sub",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "t", timeType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "u", timeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", durationType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildSyncPackage() *types.Package {
	pkg := types.NewPackage("sync", "sync")
	scope := pkg.Scope()

	// type Mutex struct{ locked int }
	mutexStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "locked", types.Typ[types.Int], false),
	}, nil)
	mutexType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Mutex", nil),
		mutexStruct, nil)
	scope.Insert(mutexType.Obj())

	mutexPtr := types.NewPointer(mutexType)
	mutexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lock",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "m", mutexPtr),
			nil, nil, nil, nil, false)))
	mutexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unlock",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "m", mutexPtr),
			nil, nil, nil, nil, false)))

	// type WaitGroup struct{ count int; ch chan int }
	wgStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "count", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "ch", types.NewChan(types.SendRecv, types.Typ[types.Int]), false),
	}, nil)
	wgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WaitGroup", nil),
		wgStruct, nil)
	scope.Insert(wgType.Obj())

	wgPtr := types.NewPointer(wgType)
	wgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "wg", wgPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Int])),
			nil, false)))
	wgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Done",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "wg", wgPtr),
			nil, nil, nil, nil, false)))
	wgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Wait",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "wg", wgPtr),
			nil, nil, nil, nil, false)))

	// type Once struct{ done int }
	onceStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "done", types.Typ[types.Int], false),
	}, nil)
	onceType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Once", nil),
		onceStruct, nil)
	scope.Insert(onceType.Obj())

	oncePtr := types.NewPointer(onceType)
	onceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Do",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "o", oncePtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f",
				types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildSortPackage() *types.Package {
	pkg := types.NewPackage("sort", "sort")
	scope := pkg.Scope()

	// func Ints(x []int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Ints",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x",
				types.NewSlice(types.Typ[types.Int]))),
			nil, false)))

	// func Strings(x []string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Strings",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x",
				types.NewSlice(types.Typ[types.String]))),
			nil, false)))

	// func Slice(x any, less func(i, j int) bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Slice",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, nil, "less",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(
							types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
							types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
						false))),
			nil, false)))

	// func IntsAreSorted(x []int) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IntsAreSorted",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x",
				types.NewSlice(types.Typ[types.Int]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildIOPackage() *types.Package {
	pkg := types.NewPackage("io", "io")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Reader interface { Read(p []byte) (n int, err error) }
	readerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerIface.Complete()
	readerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		readerIface, nil)
	scope.Insert(readerType.Obj())

	// type Writer interface { Write(p []byte) (n int, err error) }
	writerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	writerIface.Complete()
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerIface, nil)
	scope.Insert(writerType.Obj())

	// var EOF error
	scope.Insert(types.NewVar(token.NoPos, pkg, "EOF", errType))

	pkg.MarkComplete()
	return pkg
}

func buildLogPackage() *types.Package {
	pkg := types.NewPackage("log", "log")
	scope := pkg.Scope()

	// func Println(v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Println",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v",
				types.NewSlice(types.NewInterfaceType(nil, nil)))),
			nil, true)))

	// func Printf(format string, v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Printf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "v",
					types.NewSlice(types.NewInterfaceType(nil, nil)))),
			nil, true)))

	// func Fatal(v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fatal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v",
				types.NewSlice(types.NewInterfaceType(nil, nil)))),
			nil, true)))

	// func Fatalf(format string, v ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fatalf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "v",
					types.NewSlice(types.NewInterfaceType(nil, nil)))),
			nil, true)))

	pkg.MarkComplete()
	return pkg
}

// buildEmbedPackage creates a stub for the embed package.
// The embed package just provides the FS type; //go:embed directives
// are handled by the compiler, not the package itself.
func buildEmbedPackage() *types.Package {
	pkg := types.NewPackage("embed", "embed")
	// embed.FS type — simplified as an opaque struct
	fsStruct := types.NewStruct(nil, nil)
	fsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FS", nil),
		fsStruct, nil)
	pkg.Scope().Insert(fsType.Obj())
	pkg.MarkComplete()
	return pkg
}

// buildUnsafePackage creates a stub for the unsafe package.
func buildUnsafePackage() *types.Package {
	// go/types has built-in support for unsafe
	return types.Unsafe
}

// buildCmplxPackage creates the type-checked math/cmplx package stub
// with commonly used complex math functions.
func buildCmplxPackage() *types.Package {
	pkg := types.NewPackage("math/cmplx", "cmplx")
	scope := pkg.Scope()

	c128 := types.Typ[types.Complex128]
	f64 := types.Typ[types.Float64]

	// func Abs(x complex128) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Abs",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", c128)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", f64)),
			false)))

	// func Phase(x complex128) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Phase",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", c128)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", f64)),
			false)))

	// func Sqrt(x complex128) complex128
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sqrt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", c128)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", c128)),
			false)))

	// func Conj(x complex128) complex128
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Conj",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", c128)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", c128)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// embedInit records a //go:embed directive to initialize at module load.
type embedInit struct {
	globalName string // name of the global variable
	content    string // embedded file content (string value)
}

// processEmbedDirectives scans AST comments for //go:embed directives and
// reads the referenced files from disk. For each embedded variable, records
// the content so it can be initialized in the data section.
func (c *Compiler) processEmbedDirectives(files []*ast.File, fset *token.FileSet) {
	for _, file := range files {
		for _, decl := range file.Decls {
			gd, ok := decl.(*ast.GenDecl)
			if !ok || gd.Tok != token.VAR {
				continue
			}
			// Check comment group directly above this declaration
			if gd.Doc == nil {
				continue
			}
			for _, comment := range gd.Doc.List {
				text := comment.Text
				if !strings.HasPrefix(text, "//go:embed ") {
					continue
				}
				pattern := strings.TrimPrefix(text, "//go:embed ")
				pattern = strings.TrimSpace(pattern)

				// Read the embedded file
				filePath := filepath.Join(c.BaseDir, pattern)
				data, err := os.ReadFile(filePath)
				if err != nil {
					c.errors = append(c.errors, fmt.Sprintf("go:embed: %v", err))
					continue
				}

				// Get the variable name from the spec
				for _, spec := range gd.Specs {
					vs, ok := spec.(*ast.ValueSpec)
					if !ok {
						continue
					}
					for _, ident := range vs.Names {
						content := string(data)
						c.AllocString(content)
						c.embedInits = append(c.embedInits, embedInit{
							globalName: ident.Name,
							content:    content,
						})
					}
				}
			}
		}
	}
}

