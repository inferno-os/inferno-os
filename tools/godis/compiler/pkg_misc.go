// Package type stubs for all remaining packages: reflect, runtime, testing,
// os/exec, os/signal, io/ioutil, io/fs, regexp, log/slog, text/template,
// unicode, path, slices, maps, cmp, hash, archive, compress, html, mime,
// container, image, debug, go/*, syscall, expvar, and more.
package compiler

import (
	"go/constant"
	"go/token"
	"go/types"
)

func init() {
	RegisterPackage("archive/tar", buildArchiveTarPackage)
	RegisterPackage("archive/zip", buildArchiveZipPackage)
	RegisterPackage("cmp", buildCmpPackage)
	RegisterPackage("compress/bzip2", buildCompressBzip2Package)
	RegisterPackage("compress/flate", buildCompressFlatePackage)
	RegisterPackage("compress/gzip", buildCompressGzipPackage)
	RegisterPackage("compress/lzw", buildCompressLzwPackage)
	RegisterPackage("compress/zlib", buildCompressZlibPackage)
	RegisterPackage("container/heap", buildContainerHeapPackage)
	RegisterPackage("container/list", buildContainerListPackage)
	RegisterPackage("container/ring", buildContainerRingPackage)
	RegisterPackage("debug/buildinfo", buildDebugBuildInfoPackage)
	RegisterPackage("debug/dwarf", buildDebugDwarfPackage)
	RegisterPackage("debug/elf", buildDebugElfPackage)
	RegisterPackage("debug/gosym", buildDebugGosymPackage)
	RegisterPackage("debug/macho", buildDebugMachoPackage)
	RegisterPackage("debug/pe", buildDebugPEPackage)
	RegisterPackage("debug/plan9obj", buildDebugPlan9objPackage)
	RegisterPackage("expvar", buildExpvarPackage)
	RegisterPackage("path/filepath", buildFilepathPackage)
	RegisterPackage("go/ast", buildGoASTPackage)
	RegisterPackage("go/build/constraint", buildGoBuildConstraintPackage)
	RegisterPackage("go/build", buildGoBuildPackage)
	RegisterPackage("go/constant", buildGoConstantPackage)
	RegisterPackage("go/doc/comment", buildGoDocCommentPackage)
	RegisterPackage("go/doc", buildGoDocPackage)
	RegisterPackage("go/format", buildGoFormatPackage)
	RegisterPackage("go/importer", buildGoImporterPackage)
	RegisterPackage("go/parser", buildGoParserPackage)
	RegisterPackage("go/printer", buildGoPrinterPackage)
	RegisterPackage("go/scanner", buildGoScannerPackage)
	RegisterPackage("go/token", buildGoTokenPackage)
	RegisterPackage("go/types", buildGoTypesPackage)
	RegisterPackage("go/version", buildGoVersionPackage)
	RegisterPackage("html", buildHTMLPackage)
	RegisterPackage("html/template", buildHTMLTemplatePackage)
	RegisterPackage("hash/adler32", buildHashAdler32Package)
	RegisterPackage("hash/crc32", buildHashCRC32Package)
	RegisterPackage("hash/crc64", buildHashCRC64Package)
	RegisterPackage("hash/fnv", buildHashFNVPackage)
	RegisterPackage("hash/maphash", buildHashMaphashPackage)
	RegisterPackage("hash", buildHashPackage)
	RegisterPackage("io/fs", buildIOFSPackage)
	RegisterPackage("io/ioutil", buildIOUtilPackage)
	RegisterPackage("image/color", buildImageColorPackage)
	RegisterPackage("image/color/palette", buildImageColorPalettePackage)
	RegisterPackage("image/draw", buildImageDrawPackage)
	RegisterPackage("image/gif", buildImageGIFPackage)
	RegisterPackage("image/jpeg", buildImageJPEGPackage)
	RegisterPackage("image/png", buildImagePNGPackage)
	RegisterPackage("image", buildImagePackage)
	RegisterPackage("index/suffixarray", buildIndexSuffixarrayPackage)
	RegisterPackage("iter", buildIterPackage)
	RegisterPackage("log/slog", buildLogSlogPackage)
	RegisterPackage("log/syslog", buildLogSyslogPackage)
	RegisterPackage("mime/multipart", buildMIMEMultipartPackage)
	RegisterPackage("mime", buildMIMEPackage)
	RegisterPackage("maps", buildMapsPackage)
	RegisterPackage("mime/quotedprintable", buildMimeQuotedprintablePackage)
	RegisterPackage("os/exec", buildOsExecPackage)
	RegisterPackage("os/signal", buildOsSignalPackage)
	RegisterPackage("os/user", buildOsUserPackage)
	RegisterPackage("path", buildPathPackage)
	RegisterPackage("plugin", buildPluginPackage)
	RegisterPackage("reflect", buildReflectPackage)
	RegisterPackage("regexp", buildRegexpPackage)
	RegisterPackage("regexp/syntax", buildRegexpSyntaxPackage)
	RegisterPackage("runtime/cgo", buildRuntimeCgoPackage)
	RegisterPackage("runtime/coverage", buildRuntimeCoveragePackage)
	RegisterPackage("runtime/debug", buildRuntimeDebugPackage)
	RegisterPackage("runtime/metrics", buildRuntimeMetricsPackage)
	RegisterPackage("runtime", buildRuntimePackage)
	RegisterPackage("runtime/pprof", buildRuntimePprofPackage)
	RegisterPackage("runtime/trace", buildRuntimeTracePackage)
	RegisterPackage("slices", buildSlicesPackage)
	RegisterPackage("structs", buildStructsPackage)
	RegisterPackage("sync/atomic", buildSyncAtomicPackage)
	RegisterPackage("sync/errgroup", buildSyncErrgroupPackage)
	RegisterPackage("syscall/js", buildSyscallJSPackage)
	RegisterPackage("syscall", buildSyscallPackage)
	RegisterPackage("testing/cryptotest", buildTestingCryptotestPackage)
	RegisterPackage("testing/fstest", buildTestingFstestPackage)
	RegisterPackage("testing/iotest", buildTestingIotestPackage)
	RegisterPackage("testing", buildTestingPackage)
	RegisterPackage("testing/quick", buildTestingQuickPackage)
	RegisterPackage("testing/slogtest", buildTestingSlogtestPackage)
	RegisterPackage("testing/synctest", buildTestingSynctestPackage)
	RegisterPackage("text/scanner", buildTextScannerPackage)
	RegisterPackage("text/tabwriter", buildTextTabwriterPackage)
	RegisterPackage("text/template", buildTextTemplatePackage)
	RegisterPackage("text/template/parse", buildTextTemplateParsePackage)
	RegisterPackage("time/tzdata", buildTimeTzdataPackage)
	RegisterPackage("unicode/utf8", buildUTF8Package)
	RegisterPackage("unicode", buildUnicodePackage)
	RegisterPackage("unicode/utf16", buildUnicodeUTF16Package)
	RegisterPackage("unique", buildUniquePackage)
	RegisterPackage("weak", buildWeakPackage)
}

// buildArchiveTarPackage creates the type-checked archive/tar package stub.
func buildArchiveTarPackage() *types.Package {
	pkg := types.NewPackage("archive/tar", "tar")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface { Read(p []byte) (n int, err error) }
	ioReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderIface.Complete()

	// io.Writer interface { Write(p []byte) (n int, err error) }
	ioWriterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterIface.Complete()

	// time.Time stand-in (int64)
	timeType := types.Typ[types.Int64]
	mapStringString := types.NewMap(types.Typ[types.String], types.Typ[types.String])

	// type Format int
	formatType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Format", nil), types.Typ[types.Int], nil)
	scope.Insert(formatType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "FormatUnknown", formatType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FormatUSTAR", formatType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FormatPAX", formatType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FormatGNU", formatType, constant.MakeInt64(3)))

	// Header struct with all fields
	headerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Typeflag", types.Typ[types.Byte], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Linkname", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Mode", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Uid", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Gid", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Uname", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Gname", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "ModTime", timeType, false),
		types.NewField(token.NoPos, pkg, "AccessTime", timeType, false),
		types.NewField(token.NoPos, pkg, "ChangeTime", timeType, false),
		types.NewField(token.NoPos, pkg, "Devmajor", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Devminor", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Xattrs", mapStringString, false),
		types.NewField(token.NoPos, pkg, "PAXRecords", mapStringString, false),
		types.NewField(token.NoPos, pkg, "Format", formatType, false),
	}, nil)
	headerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Header", nil),
		headerStruct, nil)
	scope.Insert(headerType.Obj())
	headerPtr := types.NewPointer(headerType)

	// os.FileInfo stand-in interface
	fileInfoIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, nil, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "ModTime",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)), false)),
		types.NewFunc(token.NoPos, nil, "Mode",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)),
		types.NewFunc(token.NoPos, nil, "Sys",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)),
	}, nil)
	fileInfoIface.Complete()

	// Header.FileInfo() os.FileInfo
	headerType.AddMethod(types.NewFunc(token.NoPos, pkg, "FileInfo",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "h", headerPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fileInfoIface)), false)))

	// func FileInfoHeader(fi os.FileInfo, link string) (*Header, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FileInfoHeader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fi", fileInfoIface),
				types.NewVar(token.NoPos, pkg, "link", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", headerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Typeflag constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeReg", types.Typ[types.Byte], constant.MakeInt64('0')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeRegA", types.Typ[types.Byte], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeLink", types.Typ[types.Byte], constant.MakeInt64('1')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeSymlink", types.Typ[types.Byte], constant.MakeInt64('2')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeChar", types.Typ[types.Byte], constant.MakeInt64('3')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeBlock", types.Typ[types.Byte], constant.MakeInt64('4')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeDir", types.Typ[types.Byte], constant.MakeInt64('5')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeFifo", types.Typ[types.Byte], constant.MakeInt64('6')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeCont", types.Typ[types.Byte], constant.MakeInt64('7')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeXHeader", types.Typ[types.Byte], constant.MakeInt64('x')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeXGlobalHeader", types.Typ[types.Byte], constant.MakeInt64('g')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeGNUSparse", types.Typ[types.Byte], constant.MakeInt64('S')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeGNULongName", types.Typ[types.Byte], constant.MakeInt64('L')))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeGNULongLink", types.Typ[types.Byte], constant.MakeInt64('K')))

	// Error variables
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrHeader", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrWriteTooLong", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrFieldTooLong", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrWriteAfterClose", errType))

	// Reader type
	readerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "r", ioReaderIface, false),
	}, nil)
	readerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		readerStruct, nil)
	scope.Insert(readerType.Obj())
	readerPtr := types.NewPointer(readerType)
	readerRecv := types.NewVar(token.NoPos, nil, "tr", readerPtr)

	// Reader.Next() (*Header, error)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(readerRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", headerPtr),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Reader.Read(b []byte) (int, error)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(readerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// Writer type
	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "w", ioWriterIface, false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())
	writerPtr := types.NewPointer(writerType)
	writerRecv := types.NewVar(token.NoPos, nil, "tw", writerPtr)

	// Writer.WriteHeader(hdr *Header) error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteHeader",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "hdr", headerPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Writer.Write(b []byte) (int, error)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Writer.Flush() error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(writerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Writer.Close() error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(writerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func NewReader(r io.Reader) *Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReaderIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", readerPtr)),
			false)))

	// func NewWriter(w io.Writer) *Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", writerPtr)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildArchiveZipPackage creates the type-checked archive/zip package stub.
func buildArchiveZipPackage() *types.Package {
	pkg := types.NewPackage("archive/zip", "zip")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface { Read(p []byte) (n int, err error) }
	ioReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderIface.Complete()

	// io.Writer interface { Write(p []byte) (n int, err error) }
	ioWriterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterIface.Complete()

	// Compression method constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "Store", types.Typ[types.Uint16], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Deflate", types.Typ[types.Uint16], constant.MakeInt64(8)))

	// Error variables
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrFormat", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrAlgorithm", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrChecksum", errType))

	// time.Time stand-in (int64)
	timeType := types.Typ[types.Int64]

	// type FileHeader struct
	fileHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Comment", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Method", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "Modified", timeType, false),
		types.NewField(token.NoPos, pkg, "CRC32", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "CompressedSize64", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "UncompressedSize64", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "ExternalAttrs", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "CreatorVersion", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "ReaderVersion", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "Flags", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "Extra", byteSlice, false),
	}, nil)
	fileHeaderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FileHeader", nil),
		fileHeaderStruct, nil)
	scope.Insert(fileHeaderType.Obj())
	fhPtr := types.NewPointer(fileHeaderType)

	// FileHeader.FileInfo() os.FileInfo
	fiIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, nil, "Mode",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)),
		types.NewFunc(token.NoPos, nil, "ModTime",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)), false)),
		types.NewFunc(token.NoPos, nil, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Sys",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)),
	}, nil)
	fiIface.Complete()
	fileHeaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "FileInfo",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "fh", fhPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fiIface)), false)))
	// FileHeader.ModTime() time.Time
	fileHeaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "ModTime",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "fh", fhPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", timeType)), false)))
	// FileHeader.SetModTime(t time.Time)
	fileHeaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetModTime",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "fh", fhPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", timeType)), nil, false)))
	// FileHeader.Mode() os.FileMode
	fileHeaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Mode",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "fh", fhPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)))
	// FileHeader.SetMode(mode os.FileMode)
	fileHeaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetMode",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "fh", fhPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "mode", types.Typ[types.Uint32])), nil, false)))

	// type File struct (embeds FileHeader)
	fileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Comment", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Method", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "CompressedSize64", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "UncompressedSize64", types.Typ[types.Uint64], false),
	}, nil)
	fileType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "File", nil),
		fileStruct, nil)
	scope.Insert(fileType.Obj())
	filePtr := types.NewPointer(fileType)

	// File.Open() (io.ReadCloser, error)
	rcIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	rcIface.Complete()
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "f", filePtr), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", rcIface),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// type Reader struct
	readerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "File", types.NewSlice(filePtr), false),
		types.NewField(token.NoPos, pkg, "Comment", types.Typ[types.String], false),
	}, nil)
	readerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		readerStruct, nil)
	scope.Insert(readerType.Obj())
	readerPtr := types.NewPointer(readerType)

	// Reader.Close() error
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", readerPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// type Writer struct
	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "w", ioWriterIface, false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())
	writerPtr := types.NewPointer(writerType)
	writerRecv := types.NewVar(token.NoPos, nil, "w", writerPtr)

	// Writer.Create(name string) (io.Writer, error)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Create",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", ioWriterIface),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Writer.CreateHeader(fh *FileHeader) (io.Writer, error)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "CreateHeader",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "fh", types.NewPointer(fileHeaderType))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", ioWriterIface),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Writer.Close() error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(writerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Writer.Flush() error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(writerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Writer.SetComment(comment string) error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetComment",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "comment", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func OpenReader(name string) (*ReadCloser, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OpenReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", readerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewWriter(w io.Writer) *Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", writerPtr)),
			false)))

	// func FileInfoHeader(fi os.FileInfo) (*FileHeader, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FileInfoHeader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fi", fiIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", fhPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewReader(r io.ReaderAt, size int64) (*Reader, error)
	ioReaderAtIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSlice),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderAtIface.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", ioReaderAtIface),
				types.NewVar(token.NoPos, pkg, "size", types.Typ[types.Int64])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", readerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// File.DataOffset() (int64, error)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "DataOffset",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "f", filePtr), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// Writer.CreateRaw(fh *FileHeader) (io.Writer, error)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "CreateRaw",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "fh", fhPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", ioWriterIface),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// Writer.Copy(f *File) error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Copy",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f", filePtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// Writer.SetOffset(n int64)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetOffset",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int64])),
			nil, false)))

	// Writer.RegisterCompressor(method uint16, comp func(io.Writer) (io.WriteCloser, error))
	wcIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	wcIface.Complete()
	compFunc := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "w", ioWriterIface)),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", wcIface),
			types.NewVar(token.NoPos, nil, "", errType)), false)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "RegisterCompressor",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "method", types.Typ[types.Uint16]),
				types.NewVar(token.NoPos, nil, "comp", compFunc)),
			nil, false)))

	// type Compressor func(w io.Writer) (io.WriteCloser, error)
	compressorType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Compressor", nil),
		compFunc, nil)
	scope.Insert(compressorType.Obj())

	// type Decompressor func(r io.Reader) io.ReadCloser
	decompFunc := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "r", ioReaderIface)),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", rcIface)),
		false)
	decompressorType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Decompressor", nil),
		decompFunc, nil)
	scope.Insert(decompressorType.Obj())

	// func RegisterDecompressor(method uint16, dcomp Decompressor)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RegisterDecompressor",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "method", types.Typ[types.Uint16]),
				types.NewVar(token.NoPos, pkg, "dcomp", decompFunc)),
			nil, false)))

	// func RegisterCompressor(method uint16, comp Compressor)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RegisterCompressor",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "method", types.Typ[types.Uint16]),
				types.NewVar(token.NoPos, pkg, "comp", compFunc)),
			nil, false)))

	// var ErrInsecurePath error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrInsecurePath", errType))

	pkg.MarkComplete()
	return pkg
}

// buildCmpPackage creates the type-checked cmp package stub (Go 1.21+).
func buildCmpPackage() *types.Package {
	pkg := types.NewPackage("cmp", "cmp")
	scope := pkg.Scope()

	// type Ordered = comparable (simplified as interface{})
	orderedType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Ordered", nil),
		types.NewInterfaceType(nil, nil), nil)
	scope.Insert(orderedType.Obj())

	// func Compare[T Ordered](x, y T) int
	anyType := types.NewInterfaceType(nil, nil)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", anyType),
				types.NewVar(token.NoPos, pkg, "y", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Less[T Ordered](x, y T) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Less",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", anyType),
				types.NewVar(token.NoPos, pkg, "y", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Or[T comparable](vals ...T) T
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Or",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "vals",
				types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			true)))

	pkg.MarkComplete()
	return pkg
}

func buildCompressBzip2Package() *types.Package {
	pkg := types.NewPackage("compress/bzip2", "bzip2")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// func NewReader(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// type StructuralError string
	structuralErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "StructuralError", nil),
		types.Typ[types.String], nil)
	structuralErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", structuralErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(structuralErrType.Obj())
	_ = errType

	pkg.MarkComplete()
	return pkg
}

// buildCompressFlatePackage creates the type-checked compress/flate package stub.
func buildCompressFlatePackage() *types.Package {
	pkg := types.NewPackage("compress/flate", "flate")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	scope.Insert(types.NewConst(token.NoPos, pkg, "NoCompression", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BestSpeed", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BestCompression", types.Typ[types.Int], constant.MakeInt64(9)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultCompression", types.Typ[types.Int], constant.MakeInt64(-1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "HuffmanOnly", types.Typ[types.Int], constant.MakeInt64(-2)))

	// io.Reader interface { Read(p []byte) (n int, err error) }
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()
	// io.Writer interface { Write(p []byte) (n int, err error) }
	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriter.Complete()

	// io.ReadCloser interface for NewReader returns
	ioReadCloser := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioReadCloser.Complete()

	// type Reader — io.ReadCloser
	readerIface := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		ioReadCloser, nil)
	scope.Insert(readerIface.Obj())

	// Resetter interface
	resetterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Reset",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", ioReader),
					types.NewVar(token.NoPos, nil, "dict", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	resetterIface.Complete()
	resetterType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Resetter", nil),
		resetterIface, nil)
	scope.Insert(resetterType.Obj())

	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReadCloser)),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReaderDict",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", ioReader),
				types.NewVar(token.NoPos, pkg, "dict", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReadCloser)),
			false)))

	// type Writer struct
	writerStruct := types.NewStruct(nil, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())
	writerPtr := types.NewPointer(writerType)

	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "level", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", writerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriterDict",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "level", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "dict", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", writerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dst", ioWriter)),
			nil, false)))

	// type CorruptInputError int64
	corruptType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CorruptInputError", nil),
		types.Typ[types.Int64], nil)
	corruptType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", corruptType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(corruptType.Obj())

	// type InternalError string
	internalType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "InternalError", nil),
		types.Typ[types.String], nil)
	internalType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", internalType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(internalType.Obj())

	// type ReadError struct { Offset int64; Err error } (deprecated but still in API)
	readErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	readErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReadError", nil),
		readErrStruct, nil)
	readErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(readErrType)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(readErrType.Obj())

	// type WriteError struct { Offset int64; Err error } (deprecated but still in API)
	writeErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	writeErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WriteError", nil),
		writeErrStruct, nil)
	writeErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(writeErrType)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(writeErrType.Obj())

	pkg.MarkComplete()
	return pkg
}

// buildCompressGzipPackage creates the type-checked compress/gzip package stub.
func buildCompressGzipPackage() *types.Package {
	pkg := types.NewPackage("compress/gzip", "gzip")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type Header struct
	headerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Comment", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Extra", byteSlice, false),
		types.NewField(token.NoPos, pkg, "ModTime", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "OS", types.Typ[types.Byte], false),
	}, nil)
	headerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Header", nil),
		headerStruct, nil)
	scope.Insert(headerType.Obj())

	readerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Header", headerType, false),
	}, nil)
	readerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		readerStruct, nil)
	scope.Insert(readerType.Obj())
	readerPtr := types.NewPointer(readerType)

	// io.Reader interface { Read(p []byte) (n int, err error) }
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()
	// io.Writer interface { Write(p []byte) (n int, err error) }
	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriter.Complete()

	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", readerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Reader methods
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "z", readerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "z", readerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "z", readerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Multistream",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "z", readerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ok", types.Typ[types.Bool])),
			nil, false)))

	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Header", headerType, false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())
	writerPtr := types.NewPointer(writerType)

	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriter)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", writerPtr)),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriterLevel",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "level", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", writerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Writer methods
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "z", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "z", writerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "z", writerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "z", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriter)),
			nil, false)))

	// var ErrChecksum, ErrHeader error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrChecksum", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrHeader", errType))

	// Compression constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "NoCompression", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BestSpeed", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BestCompression", types.Typ[types.Int], constant.MakeInt64(9)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultCompression", types.Typ[types.Int], constant.MakeInt64(-1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "HuffmanOnly", types.Typ[types.Int], constant.MakeInt64(-2)))

	pkg.MarkComplete()
	return pkg
}

func buildCompressLzwPackage() *types.Package {
	pkg := types.NewPackage("compress/lzw", "lzw")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.ReadCloser interface
	ioReadCloser := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioReadCloser.Complete()

	// io.WriteCloser interface
	ioWriteCloser := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioWriteCloser.Complete()

	// io.Reader interface
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// io.Writer interface
	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriter.Complete()

	// type Order int
	orderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Order", nil), types.Typ[types.Int], nil)
	scope.Insert(orderType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "LSB", orderType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MSB", orderType, constant.MakeInt64(1)))

	// func NewReader(r io.Reader, order Order, litWidth int) io.ReadCloser
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", ioReader),
				types.NewVar(token.NoPos, pkg, "order", orderType),
				types.NewVar(token.NoPos, pkg, "litWidth", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReadCloser)),
			false)))

	// func NewWriter(w io.Writer, order Order, litWidth int) io.WriteCloser
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "order", orderType),
				types.NewVar(token.NoPos, pkg, "litWidth", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioWriteCloser)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildCompressZlibPackage() *types.Package {
	pkg := types.NewPackage("compress/zlib", "zlib")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// io.Writer interface
	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriter.Complete()

	// io.ReadCloser interface
	ioReadCloser := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioReadCloser.Complete()

	// Resetter interface
	resetterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Reset",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", ioReader),
					types.NewVar(token.NoPos, nil, "dict", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	resetterIface.Complete()
	resetterType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Resetter", nil),
		resetterIface, nil)
	scope.Insert(resetterType.Obj())

	// type Writer struct
	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())
	writerPtr := types.NewPointer(writerType)

	writerRecv := types.NewVar(token.NoPos, nil, "z", writerPtr)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(writerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(writerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", ioWriter)),
			nil, false)))

	// func NewReader(r io.Reader) (io.ReadCloser, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ioReadCloser),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewWriter(w io.Writer) *Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriter)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", writerPtr)),
			false)))

	scope.Insert(types.NewConst(token.NoPos, pkg, "NoCompression", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BestSpeed", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BestCompression", types.Typ[types.Int], constant.MakeInt64(9)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultCompression", types.Typ[types.Int], constant.MakeInt64(-1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "HuffmanOnly", types.Typ[types.Int], constant.MakeInt64(-2)))

	// func NewWriterLevel(w io.Writer, level int) (*Writer, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriterLevel",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "level", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", writerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewReaderDict(r io.Reader, dict []byte) (io.ReadCloser, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReaderDict",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", ioReader),
				types.NewVar(token.NoPos, pkg, "dict", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ioReadCloser),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewWriterLevelDict(w io.Writer, level int, dict []byte) (*Writer, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriterLevelDict",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "level", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "dict", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", writerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// var ErrChecksum, ErrDictionary, ErrHeader error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrChecksum", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrDictionary", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrHeader", errType))

	pkg.MarkComplete()
	return pkg
}

func buildContainerHeapPackage() *types.Package {
	pkg := types.NewPackage("container/heap", "heap")
	scope := pkg.Scope()
	anyType := types.Universe.Lookup("any").Type()

	// type Interface interface { Len() int; Less(i, j int) bool; Swap(i, j int); Push(x any); Pop() any }
	heapIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Len",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "Less",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Swap",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
				nil, false)),
		types.NewFunc(token.NoPos, pkg, "Push",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "x", anyType)),
				nil, false)),
		types.NewFunc(token.NoPos, pkg, "Pop",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyType)), false)),
	}, nil)
	heapIface.Complete()
	heapIfaceType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Interface", nil), heapIface, nil)
	scope.Insert(heapIfaceType.Obj())

	// func Init(h Interface)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "h", heapIfaceType)),
			nil, false)))

	// func Push(h Interface, x any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Push",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", heapIfaceType),
				types.NewVar(token.NoPos, pkg, "x", anyType)),
			nil, false)))

	// func Pop(h Interface) any
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pop",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "h", heapIfaceType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func Fix(h Interface, i int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", heapIfaceType),
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int])),
			nil, false)))

	// func Remove(h Interface, i int) any
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Remove",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", heapIfaceType),
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildContainerListPackage() *types.Package {
	pkg := types.NewPackage("container/list", "list")
	scope := pkg.Scope()
	anyType := types.Universe.Lookup("any").Type()

	// type Element struct { Value any }
	elemStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Value", anyType, false),
	}, nil)
	elemType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Element", nil),
		elemStruct, nil)
	scope.Insert(elemType.Obj())
	elemPtr := types.NewPointer(elemType)

	// type List struct
	listStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "len", types.Typ[types.Int], false),
	}, nil)
	listType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "List", nil),
		listStruct, nil)
	scope.Insert(listType.Obj())
	listPtr := types.NewPointer(listType)

	// func New() *List
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", listPtr)),
			false)))

	// func (l *List) PushBack(v any) *Element
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "PushBack",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) PushFront(v any) *Element
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "PushFront",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) Len() int
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func (l *List) Front() *Element
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "Front",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) Remove(e *Element) any
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "Remove",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "e", elemPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func (e *Element) Next() *Element
	elemType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", elemPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (e *Element) Prev() *Element
	elemType.AddMethod(types.NewFunc(token.NoPos, pkg, "Prev",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", elemPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) Back() *Element
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "Back",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) Init() *List
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", listPtr)),
			false)))

	// func (l *List) InsertBefore(v any, mark *Element) *Element
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "InsertBefore",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "v", anyType),
				types.NewVar(token.NoPos, pkg, "mark", elemPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) InsertAfter(v any, mark *Element) *Element
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "InsertAfter",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "v", anyType),
				types.NewVar(token.NoPos, pkg, "mark", elemPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", elemPtr)),
			false)))

	// func (l *List) MoveToFront(e *Element)
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "MoveToFront",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "e", elemPtr)),
			nil, false)))

	// func (l *List) MoveToBack(e *Element)
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "MoveToBack",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "e", elemPtr)),
			nil, false)))

	// func (l *List) MoveBefore(e, mark *Element)
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "MoveBefore",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "e", elemPtr),
				types.NewVar(token.NoPos, pkg, "mark", elemPtr)),
			nil, false)))

	// func (l *List) MoveAfter(e, mark *Element)
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "MoveAfter",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "e", elemPtr),
				types.NewVar(token.NoPos, pkg, "mark", elemPtr)),
			nil, false)))

	// func (l *List) PushBackList(other *List)
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "PushBackList",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "other", listPtr)),
			nil, false)))

	// func (l *List) PushFrontList(other *List)
	listType.AddMethod(types.NewFunc(token.NoPos, pkg, "PushFrontList",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", listPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "other", listPtr)),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildContainerRingPackage() *types.Package {
	pkg := types.NewPackage("container/ring", "ring")
	scope := pkg.Scope()

	ringStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Value", types.Universe.Lookup("any").Type(), false),
	}, nil)
	ringType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Ring", nil),
		ringStruct, nil)
	scope.Insert(ringType.Obj())
	ringPtr := types.NewPointer(ringType)

	// func New(n int) *Ring
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ringPtr)),
			false)))

	// func (r *Ring) Len() int
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func (r *Ring) Next() *Ring
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ringPtr)),
			false)))

	// func (r *Ring) Prev() *Ring
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Prev",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ringPtr)),
			false)))

	// func (r *Ring) Move(n int) *Ring
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Move",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ringPtr)),
			false)))

	// func (r *Ring) Link(s *Ring) *Ring
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Link",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", ringPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ringPtr)),
			false)))

	// func (r *Ring) Unlink(n int) *Ring
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unlink",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ringPtr)),
			false)))

	// func (r *Ring) Do(f func(any))
	ringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Do",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", ringPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("any").Type())),
					nil, false))),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildDebugBuildInfoPackage() *types.Package {
	pkg := types.NewPackage("debug/buildinfo", "buildinfo")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type BuildInfo = debug.BuildInfo (same as runtime/debug.BuildInfo)
	// type BuildInfo struct { GoVersion string; Path string; Main Module; Deps []*Module; Settings []BuildSetting }
	moduleStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Sum", types.Typ[types.String], false),
	}, nil)
	moduleType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Module", nil), moduleStruct, nil)

	buildSettingStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Key", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.String], false),
	}, nil)
	buildSettingType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BuildSetting", nil), buildSettingStruct, nil)

	infoStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "GoVersion", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Main", moduleType, false),
		types.NewField(token.NoPos, pkg, "Deps", types.NewSlice(types.NewPointer(moduleType)), false),
		types.NewField(token.NoPos, pkg, "Settings", types.NewSlice(buildSettingType), false),
	}, nil)
	infoType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BuildInfo", nil), infoStruct, nil)
	scope.Insert(infoType.Obj())
	infoPtr := types.NewPointer(infoType)
	infoType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "bi", infoPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// func ReadFile(name string) (*BuildInfo, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", infoPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.ReaderAt interface for Read
	byteSliceBI := types.NewSlice(types.Typ[types.Byte])
	readerAtBI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSliceBI),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerAtBI.Complete()

	// func Read(r io.ReaderAt) (*BuildInfo, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerAtBI)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", infoPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildDebugDwarfPackage() *types.Package {
	pkg := types.NewPackage("debug/dwarf", "dwarf")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Tag uint32
	tagType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Tag", nil), types.Typ[types.Uint32], nil)
	scope.Insert(tagType.Obj())
	tagType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "t", tagType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Attr uint32
	attrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Attr", nil), types.Typ[types.Uint32], nil)
	scope.Insert(attrType.Obj())
	attrType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "a", attrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// Some common tag/attr constants
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"TagCompileUnit", 0x11}, {"TagSubprogram", 0x2e}, {"TagVariable", 0x34},
		{"TagFormalParameter", 0x05}, {"TagMember", 0x0d}, {"TagBaseType", 0x24},
		{"TagStructType", 0x13}, {"TagTypedef", 0x16}, {"TagPointerType", 0x0f},
		{"AttrName", 0x03}, {"AttrType", 0x49}, {"AttrByteSize", 0x0b},
		{"AttrLocation", 0x02}, {"AttrLowpc", 0x11}, {"AttrHighpc", 0x12},
		{"AttrLanguage", 0x13}, {"AttrCompDir", 0x1b},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, types.Typ[types.Int], constant.MakeInt64(c.val)))
	}

	// type Offset uint32
	offsetType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Offset", nil), types.Typ[types.Uint32], nil)
	scope.Insert(offsetType.Obj())

	// type Field struct { Attr Attr; Val interface{}; Class Class }
	fieldStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Attr", attrType, false),
		types.NewField(token.NoPos, pkg, "Val", types.NewInterfaceType(nil, nil), false),
		types.NewField(token.NoPos, pkg, "Class", types.Typ[types.Int], false),
	}, nil)
	fieldType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Field", nil), fieldStruct, nil)
	scope.Insert(fieldType.Obj())

	// type Entry struct
	entryStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Offset", offsetType, false),
		types.NewField(token.NoPos, pkg, "Tag", tagType, false),
		types.NewField(token.NoPos, pkg, "Children", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Field", types.NewSlice(fieldType), false),
	}, nil)
	entryType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Entry", nil), entryStruct, nil)
	scope.Insert(entryType.Obj())
	entryPtr := types.NewPointer(entryType)
	entryRecv := types.NewVar(token.NoPos, nil, "e", entryPtr)
	entryType.AddMethod(types.NewFunc(token.NoPos, pkg, "Val",
		types.NewSignatureType(entryRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "a", attrType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)))
	entryType.AddMethod(types.NewFunc(token.NoPos, pkg, "AttrField",
		types.NewSignatureType(entryRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "a", attrType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(fieldType))), false)))

	// type Reader struct (opaque)
	readerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Reader", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(readerType.Obj())
	readerPtr := types.NewPointer(readerType)
	readerRecv := types.NewVar(token.NoPos, nil, "r", readerPtr)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(readerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", entryPtr), types.NewVar(token.NoPos, nil, "", errType)), false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seek",
		types.NewSignatureType(readerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "off", offsetType)), nil, false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "SkipChildren",
		types.NewSignatureType(readerRecv, nil, nil, nil, nil, false)))

	// type LineReader struct (opaque)
	lineReaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "LineReader", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(lineReaderType.Obj())

	// type LineFile struct { Name string; Mtime uint64; Length int }
	lineFileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Mtime", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Length", types.Typ[types.Int], false),
	}, nil)
	lineFileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "LineFile", nil), lineFileStruct, nil)
	scope.Insert(lineFileType.Obj())

	// type LineEntry struct
	lineEntryStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Address", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "File", types.NewPointer(lineFileType), false),
		types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Column", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "IsStmt", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "EndSequence", types.Typ[types.Bool], false),
	}, nil)
	lineEntryType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "LineEntry", nil), lineEntryStruct, nil)
	scope.Insert(lineEntryType.Obj())

	lineReaderPtr := types.NewPointer(lineReaderType)
	lineReaderRecv := types.NewVar(token.NoPos, nil, "r", lineReaderPtr)
	lineReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(lineReaderRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "entry", types.NewPointer(lineEntryType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	lineReaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(lineReaderRecv, nil, nil, nil, nil, false)))

	// type CommonType struct { ByteSize int64; Name string }
	commonTypeStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ByteSize", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
	}, nil)
	commonTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CommonType", nil), commonTypeStruct, nil)
	scope.Insert(commonTypeType.Obj())
	commonTypePtr := types.NewPointer(commonTypeType)

	// type Type interface { Common() *CommonType; String() string; Size() int64 }
	typeIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Common",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", commonTypePtr)), false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
	}, nil)
	typeIface.Complete()
	dwarfTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Type", nil), typeIface, nil)
	scope.Insert(dwarfTypeType.Obj())

	// type Data struct (opaque)
	dataType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Data", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(dataType.Obj())
	dataPtr := types.NewPointer(dataType)
	dataRecv := types.NewVar(token.NoPos, nil, "d", dataPtr)
	dataType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reader",
		types.NewSignatureType(dataRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", readerPtr)), false)))
	dataType.AddMethod(types.NewFunc(token.NoPos, pkg, "Type",
		types.NewSignatureType(dataRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "off", offsetType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", dwarfTypeType), types.NewVar(token.NoPos, nil, "", errType)), false)))
	dataType.AddMethod(types.NewFunc(token.NoPos, pkg, "LineReader",
		types.NewSignatureType(dataRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "cu", entryPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", lineReaderPtr), types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func New(abbrev, aranges, frame, info, line, pubnames, ranges, str []byte) (*Data, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "abbrev", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "aranges", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "frame", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "info", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "line", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "pubnames", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "ranges", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "str", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", dataPtr), types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildDebugElfPackage() *types.Package {
	pkg := types.NewPackage("debug/elf", "elf")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// Type aliases for ELF header fields
	for _, name := range []string{"Class", "Data", "OSABI", "Type", "Machine"} {
		t := types.NewNamed(types.NewTypeName(token.NoPos, pkg, name, nil), types.Typ[types.Int], nil)
		t.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "i", t), nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
		scope.Insert(t.Obj())
	}

	// Section type enums
	sectionTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SectionType", nil), types.Typ[types.Uint32], nil)
	scope.Insert(sectionTypeType.Obj())
	sectionFlagType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SectionFlag", nil), types.Typ[types.Uint32], nil)
	scope.Insert(sectionFlagType.Obj())
	progTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ProgType", nil), types.Typ[types.Int], nil)
	scope.Insert(progTypeType.Obj())
	progFlagType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ProgFlag", nil), types.Typ[types.Uint32], nil)
	scope.Insert(progFlagType.Obj())
	symBindType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SymBind", nil), types.Typ[types.Int], nil)
	scope.Insert(symBindType.Obj())
	symTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SymType", nil), types.Typ[types.Int], nil)
	scope.Insert(symTypeType.Obj())
	symVisType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SymVis", nil), types.Typ[types.Int], nil)
	scope.Insert(symVisType.Obj())

	// type SectionHeader struct
	sectionHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Type", sectionTypeType, false),
		types.NewField(token.NoPos, pkg, "Flags", sectionFlagType, false),
		types.NewField(token.NoPos, pkg, "Addr", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Link", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Info", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Addralign", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Entsize", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "FileSize", types.Typ[types.Uint64], false),
	}, nil)
	sectionHeaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SectionHeader", nil), sectionHeaderStruct, nil)
	scope.Insert(sectionHeaderType.Obj())

	// type Section struct { SectionHeader; ... }
	sectionStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "SectionHeader", sectionHeaderType, true),
	}, nil)
	sectionType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Section", nil), sectionStruct, nil)
	scope.Insert(sectionType.Obj())
	sectionPtr := types.NewPointer(sectionType)
	sectionRecv := types.NewVar(token.NoPos, nil, "s", sectionPtr)
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Data",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice), types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Open returns io.ReadSeeker { Read([]byte) (int, error); Seek(int64, int) (int64, error) }
	ioReaderOpen := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Seek",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioReaderOpen.Complete()
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ioReaderOpen)), false)))

	// type Symbol struct
	symbolStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Info", types.Typ[types.Byte], false),
		types.NewField(token.NoPos, pkg, "Other", types.Typ[types.Byte], false),
		types.NewField(token.NoPos, pkg, "Section", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Library", types.Typ[types.String], false),
	}, nil)
	symbolType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Symbol", nil), symbolStruct, nil)
	scope.Insert(symbolType.Obj())

	// type Prog struct
	progHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Type", progTypeType, false),
		types.NewField(token.NoPos, pkg, "Flags", progFlagType, false),
		types.NewField(token.NoPos, pkg, "Off", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Vaddr", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Paddr", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Filesz", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Memsz", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Align", types.Typ[types.Uint64], false),
	}, nil)
	progHeaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ProgHeader", nil), progHeaderStruct, nil)
	scope.Insert(progHeaderType.Obj())

	progStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ProgHeader", progHeaderType, true),
	}, nil)
	progType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Prog", nil), progStruct, nil)
	scope.Insert(progType.Obj())

	// type FileHeader struct
	fileHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Class", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Data", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "OSABI", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "ABIVersion", types.Typ[types.Byte], false),
		types.NewField(token.NoPos, pkg, "Type", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Machine", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Entry", types.Typ[types.Uint64], false),
	}, nil)
	fileHeaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FileHeader", nil), fileHeaderStruct, nil)
	scope.Insert(fileHeaderType.Obj())

	// type File struct
	fileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "FileHeader", fileHeaderType, true),
		types.NewField(token.NoPos, pkg, "Sections", types.NewSlice(sectionPtr), false),
		types.NewField(token.NoPos, pkg, "Progs", types.NewSlice(types.NewPointer(progType)), false),
	}, nil)
	fileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "File", nil), fileStruct, nil)
	scope.Insert(fileType.Obj())
	filePtr := types.NewPointer(fileType)
	fileRecv := types.NewVar(token.NoPos, nil, "f", filePtr)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Section",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", sectionPtr)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Symbols",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(symbolType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "DynamicSymbols",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(symbolType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// type ImportedSymbol struct { Name, Version, Library string }
	importedSymStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Library", types.Typ[types.String], false),
	}, nil)
	importedSymType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ImportedSymbol", nil), importedSymStruct, nil)
	scope.Insert(importedSymType.Obj())

	// *dwarf.Data opaque pointer stand-in
	dwarfDataPtrElf := types.NewPointer(types.NewStruct(nil, nil))

	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportedSymbols",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(importedSymType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportedLibraries",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "DWARF",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", dwarfDataPtrElf),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func Open(name string) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.ReaderAt interface for NewFile
	readerAtIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSlice),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerAtIface.Complete()

	// func NewFile(r io.ReaderAt) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerAtIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Some ELF constants
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"ELFCLASS32", 1}, {"ELFCLASS64", 2},
		{"ELFDATA2LSB", 1}, {"ELFDATA2MSB", 2},
		{"ET_NONE", 0}, {"ET_REL", 1}, {"ET_EXEC", 2}, {"ET_DYN", 3}, {"ET_CORE", 4},
		{"EM_386", 3}, {"EM_ARM", 40}, {"EM_X86_64", 62}, {"EM_AARCH64", 183}, {"EM_RISCV", 243},
		{"SHT_NULL", 0}, {"SHT_PROGBITS", 1}, {"SHT_SYMTAB", 2}, {"SHT_STRTAB", 3},
		{"SHT_NOTE", 7}, {"SHT_NOBITS", 8}, {"SHT_DYNSYM", 11},
		{"SHF_WRITE", 1}, {"SHF_ALLOC", 2}, {"SHF_EXECINSTR", 4},
		{"PT_NULL", 0}, {"PT_LOAD", 1}, {"PT_DYNAMIC", 2}, {"PT_INTERP", 3}, {"PT_NOTE", 4},
		{"STB_LOCAL", 0}, {"STB_GLOBAL", 1}, {"STB_WEAK", 2},
		{"STT_NOTYPE", 0}, {"STT_OBJECT", 1}, {"STT_FUNC", 2}, {"STT_SECTION", 3}, {"STT_FILE", 4},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, types.Typ[types.Int], constant.MakeInt64(c.val)))
	}

	// FormatError
	formatErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FormatError", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Msg", types.Typ[types.String], false),
		}, nil), nil)
	formatErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(formatErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(formatErrType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildDebugGosymPackage() *types.Package {
	pkg := types.NewPackage("debug/gosym", "gosym")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Sym struct { Value uint64; Type byte; Name string; GoType uint64; Func *Func }
	// Forward declare Func
	funcType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Func", nil), types.NewStruct(nil, nil), nil)

	symStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Type", types.Typ[types.Byte], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "GoType", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Func", types.NewPointer(funcType), false),
	}, nil)
	symType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Sym", nil), symStruct, nil)
	scope.Insert(symType.Obj())

	// type Obj struct { Funcs []Func; Paths []Sym }
	objStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Funcs", types.NewSlice(funcType), false),
	}, nil)
	objType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Obj", nil), objStruct, nil)
	scope.Insert(objType.Obj())

	// Now set up Func struct properly
	funcStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Sym", symType, true),
		types.NewField(token.NoPos, pkg, "End", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Obj", types.NewPointer(objType), false),
	}, nil)
	funcType.SetUnderlying(funcStruct)
	scope.Insert(funcType.Obj())

	// type Table struct
	tableStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Syms", types.NewSlice(symType), false),
		types.NewField(token.NoPos, pkg, "Funcs", types.NewSlice(funcType), false),
		types.NewField(token.NoPos, pkg, "Files", types.NewMap(types.Typ[types.String], types.NewPointer(objType)), false),
		types.NewField(token.NoPos, pkg, "Objs", types.NewSlice(objType), false),
	}, nil)
	tableType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Table", nil), tableStruct, nil)
	scope.Insert(tableType.Obj())
	tablePtr := types.NewPointer(tableType)
	tableRecv := types.NewVar(token.NoPos, nil, "t", tablePtr)
	tableType.AddMethod(types.NewFunc(token.NoPos, pkg, "PCToFunc",
		types.NewSignatureType(tableRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pc", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(funcType))), false)))
	tableType.AddMethod(types.NewFunc(token.NoPos, pkg, "PCToLine",
		types.NewSignatureType(tableRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pc", types.Typ[types.Uint64])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", types.NewPointer(funcType))), false)))
	tableType.AddMethod(types.NewFunc(token.NoPos, pkg, "LineToPC",
		types.NewSignatureType(tableRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "file", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "line", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, nil, "", types.NewPointer(funcType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	tableType.AddMethod(types.NewFunc(token.NoPos, pkg, "LookupSym",
		types.NewSignatureType(tableRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(symType))), false)))
	tableType.AddMethod(types.NewFunc(token.NoPos, pkg, "LookupFunc",
		types.NewSignatureType(tableRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(funcType))), false)))

	// type LineTable struct (opaque)
	lineTableType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "LineTable", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(lineTableType.Obj())

	// func NewTable(symtab []byte, pcln *LineTable) (*Table, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTable",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "symtab", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "pcln", types.NewPointer(lineTableType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tablePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewLineTable(data []byte, text uint64) *LineTable
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewLineTable",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "text", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(lineTableType))),
			false)))

	// type UnknownFileError string
	unknownFileErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UnknownFileError", nil), types.Typ[types.String], nil)
	unknownFileErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownFileErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(unknownFileErrType.Obj())

	// type UnknownLineError struct
	unknownLineErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UnknownLineError", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "File", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
		}, nil), nil)
	unknownLineErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(unknownLineErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(unknownLineErrType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildDebugMachoPackage() *types.Package {
	pkg := types.NewPackage("debug/macho", "macho")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Cpu uint32
	cpuType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Cpu", nil), types.Typ[types.Uint32], nil)
	scope.Insert(cpuType.Obj())
	cpuType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "i", cpuType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"Cpu386", 7}, {"CpuAmd64", 0x01000007}, {"CpuArm", 12}, {"CpuArm64", 0x0100000c}, {"CpuPpc", 18}, {"CpuPpc64", 0x01000012},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, cpuType, constant.MakeInt64(c.val)))
	}

	// type Type uint32
	typeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Type", nil), types.Typ[types.Uint32], nil)
	scope.Insert(typeType.Obj())
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"TypeObj", 1}, {"TypeExec", 2}, {"TypeDylib", 6}, {"TypeBundle", 8},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, typeType, constant.MakeInt64(c.val)))
	}

	// type Section struct
	sectionStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Seg", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Addr", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Align", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Reloff", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Nreloc", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Flags", types.Typ[types.Uint32], false),
	}, nil)
	sectionType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Section", nil), sectionStruct, nil)
	scope.Insert(sectionType.Obj())
	sectionPtr := types.NewPointer(sectionType)
	sectionRecv := types.NewVar(token.NoPos, nil, "s", sectionPtr)
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Data",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Open returns io.ReadSeeker { Read([]byte) (int, error); Seek(int64, int) (int64, error) }
	ioReaderOpen := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Seek",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioReaderOpen.Complete()
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ioReaderOpen)), false)))

	// type Symbol struct
	symbolStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Type", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Sect", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Desc", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.Uint64], false),
	}, nil)
	symbolType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Symbol", nil), symbolStruct, nil)
	scope.Insert(symbolType.Obj())

	// type Segment struct
	segmentStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Addr", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Memsz", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Filesz", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Maxprot", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Prot", types.Typ[types.Uint32], false),
	}, nil)
	segmentType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Segment", nil), segmentStruct, nil)
	scope.Insert(segmentType.Obj())

	// type FileHeader struct
	fileHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Magic", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Cpu", cpuType, false),
		types.NewField(token.NoPos, pkg, "SubCpu", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Type", typeType, false),
		types.NewField(token.NoPos, pkg, "Flags", types.Typ[types.Uint32], false),
	}, nil)
	fileHeaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FileHeader", nil), fileHeaderStruct, nil)
	scope.Insert(fileHeaderType.Obj())

	// type Symtab struct { Syms []Symbol } (simplified)
	symtabStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Syms", types.NewSlice(symbolType), false),
	}, nil)
	symtabType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Symtab", nil), symtabStruct, nil)
	scope.Insert(symtabType.Obj())

	// Load interface { Raw() []byte }
	loadIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Raw",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte]))),
				false)),
	}, nil)
	loadIface.Complete()
	loadType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Load", nil), loadIface, nil)
	scope.Insert(loadType.Obj())

	// *dwarf.Data opaque pointer stand-in
	dwarfDataPtrMacho := types.NewPointer(types.NewStruct(nil, nil))

	// type File struct
	fileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "FileHeader", fileHeaderType, true),
		types.NewField(token.NoPos, pkg, "Sections", types.NewSlice(sectionPtr), false),
		types.NewField(token.NoPos, pkg, "Symtab", types.NewPointer(symtabType), false),
		types.NewField(token.NoPos, pkg, "Loads", types.NewSlice(loadType), false),
	}, nil)
	fileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "File", nil), fileStruct, nil)
	scope.Insert(fileType.Obj())
	filePtr := types.NewPointer(fileType)
	fileRecv := types.NewVar(token.NoPos, nil, "f", filePtr)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Section",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", sectionPtr)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Segment",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(segmentType))), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "DWARF",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", dwarfDataPtrMacho),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportedSymbols",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportedLibraries",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func Open(name string) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.ReaderAt interface for NewFile
	byteSliceMacho := types.NewSlice(types.Typ[types.Byte])
	readerAtMacho := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSliceMacho),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerAtMacho.Complete()

	// func NewFile(r io.ReaderAt) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerAtMacho)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Magic constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "Magic32", types.Typ[types.Uint32], constant.MakeUint64(0xfeedface)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Magic64", types.Typ[types.Uint32], constant.MakeUint64(0xfeedfacf)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MagicFat", types.Typ[types.Uint32], constant.MakeUint64(0xcafebabe)))

	pkg.MarkComplete()
	return pkg
}

func buildDebugPEPackage() *types.Package {
	pkg := types.NewPackage("debug/pe", "pe")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type FileHeader struct
	fileHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Machine", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "NumberOfSections", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "TimeDateStamp", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "PointerToSymbolTable", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "NumberOfSymbols", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "SizeOfOptionalHeader", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "Characteristics", types.Typ[types.Uint16], false),
	}, nil)
	fileHeaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FileHeader", nil), fileHeaderStruct, nil)
	scope.Insert(fileHeaderType.Obj())

	// type SectionHeader32 struct
	sectionHeader32Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.NewArray(types.Typ[types.Uint8], 8), false),
		types.NewField(token.NoPos, pkg, "VirtualSize", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "VirtualAddress", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "SizeOfRawData", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "PointerToRawData", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Characteristics", types.Typ[types.Uint32], false),
	}, nil)
	sectionHeader32Type := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SectionHeader32", nil), sectionHeader32Struct, nil)
	scope.Insert(sectionHeader32Type.Obj())

	// type Section struct
	sectionStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "VirtualSize", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "VirtualAddress", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Characteristics", types.Typ[types.Uint32], false),
	}, nil)
	sectionType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Section", nil), sectionStruct, nil)
	scope.Insert(sectionType.Obj())
	sectionPtr := types.NewPointer(sectionType)
	sectionRecv := types.NewVar(token.NoPos, nil, "s", sectionPtr)
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Data",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Open returns io.ReadSeeker { Read([]byte) (int, error); Seek(int64, int) (int64, error) }
	ioReaderOpen := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Seek",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioReaderOpen.Complete()
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ioReaderOpen)), false)))

	// type Symbol struct
	symbolStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "SectionNumber", types.Typ[types.Int16], false),
		types.NewField(token.NoPos, pkg, "Type", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "StorageClass", types.Typ[types.Uint8], false),
	}, nil)
	symbolType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Symbol", nil), symbolStruct, nil)
	scope.Insert(symbolType.Obj())

	// type File struct
	fileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "FileHeader", fileHeaderType, true),
		types.NewField(token.NoPos, pkg, "OptionalHeader", types.NewInterfaceType(nil, nil), false),
		types.NewField(token.NoPos, pkg, "Sections", types.NewSlice(sectionPtr), false),
		types.NewField(token.NoPos, pkg, "Symbols", types.NewSlice(types.NewPointer(symbolType)), false),
	}, nil)
	fileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "File", nil), fileStruct, nil)
	scope.Insert(fileType.Obj())
	filePtr := types.NewPointer(fileType)
	fileRecv := types.NewVar(token.NoPos, nil, "f", filePtr)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Section",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", sectionPtr)), false)))
	// *dwarf.Data opaque pointer stand-in
	dwarfDataPtrPE := types.NewPointer(types.NewStruct(nil, nil))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "DWARF",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", dwarfDataPtrPE),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportedSymbols",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportedLibraries",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func Open(name string) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.ReaderAt interface for NewFile
	byteSlicePE := types.NewSlice(types.Typ[types.Byte])
	readerAtIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSlicePE),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerAtIface.Complete()

	// func NewFile(r io.ReaderAt) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerAtIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Machine constants
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"IMAGE_FILE_MACHINE_UNKNOWN", 0}, {"IMAGE_FILE_MACHINE_AM33", 0x1d3},
		{"IMAGE_FILE_MACHINE_AMD64", 0x8664}, {"IMAGE_FILE_MACHINE_ARM", 0x1c0},
		{"IMAGE_FILE_MACHINE_ARM64", 0xaa64}, {"IMAGE_FILE_MACHINE_I386", 0x14c},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, types.Typ[types.Uint16], constant.MakeInt64(c.val)))
	}

	pkg.MarkComplete()
	return pkg
}

func buildDebugPlan9objPackage() *types.Package {
	pkg := types.NewPackage("debug/plan9obj", "plan9obj")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type FileHeader struct
	fileHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Magic", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Bss", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Entry", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "PtrSize", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "LoadAddress", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "HdrSize", types.Typ[types.Uint64], false),
	}, nil)
	fileHeaderType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FileHeader", nil), fileHeaderStruct, nil)
	scope.Insert(fileHeaderType.Obj())

	// type Section struct
	sectionStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Uint32], false),
	}, nil)
	sectionType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Section", nil), sectionStruct, nil)
	scope.Insert(sectionType.Obj())
	sectionPtr := types.NewPointer(sectionType)
	sectionRecv := types.NewVar(token.NoPos, nil, "s", sectionPtr)
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Data",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Open returns io.ReadSeeker { Read([]byte) (int, error); Seek(int64, int) (int64, error) }
	ioReaderOpen := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Seek",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	ioReaderOpen.Complete()
	sectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(sectionRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ioReaderOpen)), false)))

	// type Sym struct
	symStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Type", types.Typ[types.Rune], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
	}, nil)
	symType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Sym", nil), symStruct, nil)
	scope.Insert(symType.Obj())

	// type File struct
	fileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "FileHeader", fileHeaderType, true),
		types.NewField(token.NoPos, pkg, "Sections", types.NewSlice(sectionPtr), false),
	}, nil)
	fileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "File", nil), fileStruct, nil)
	scope.Insert(fileType.Obj())
	filePtr := types.NewPointer(fileType)
	fileRecv := types.NewVar(token.NoPos, nil, "f", filePtr)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Section",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", sectionPtr)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Symbols",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(symType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func Open(name string) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.ReaderAt interface for NewFile
	byteSliceP9 := types.NewSlice(types.Typ[types.Byte])
	readerAtP9 := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSliceP9),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerAtP9.Complete()

	// func NewFile(r io.ReaderAt) (*File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerAtP9)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", filePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Magic constants
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"Magic386", 0x01EB}, {"MagicAMD64", 0x8A97}, {"MagicARM", 0x0104},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, types.Typ[types.Uint32], constant.MakeInt64(c.val)))
	}

	pkg.MarkComplete()
	return pkg
}

func buildExpvarPackage() *types.Package {
	pkg := types.NewPackage("expvar", "expvar")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// Var interface { String() string }
	varIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	varIface.Complete()
	varType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Var", nil),
		varIface, nil)
	scope.Insert(varType.Obj())

	// Int type (struct) with methods: Value, String, Add, Set
	intTypeName := types.NewTypeName(token.NoPos, pkg, "Int", nil)
	intNamed := types.NewNamed(intTypeName, types.NewStruct(nil, nil), nil)
	intPtr := types.NewPointer(intNamed)
	intRecv := types.NewVar(token.NoPos, pkg, "", intPtr)
	intNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)))
	intNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(intRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	intNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Int64])),
			nil, false)))
	intNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(intRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.Int64])),
			nil, false)))
	scope.Insert(intTypeName)

	// Float type (struct) with methods: Value, String, Add, Set
	floatTypeName := types.NewTypeName(token.NoPos, pkg, "Float", nil)
	floatNamed := types.NewNamed(floatTypeName, types.NewStruct(nil, nil), nil)
	floatPtr := types.NewPointer(floatNamed)
	floatRecv := types.NewVar(token.NoPos, pkg, "", floatPtr)
	floatNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])), false)))
	floatNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(floatRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	floatNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Float64])),
			nil, false)))
	floatNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(floatRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.Float64])),
			nil, false)))
	scope.Insert(floatTypeName)

	// String type (named struct) with methods: Value, String, Set
	stringTypeName := types.NewTypeName(token.NoPos, pkg, "String", nil)
	stringNamed := types.NewNamed(stringTypeName, types.NewStruct(nil, nil), nil)
	stringPtr := types.NewPointer(stringNamed)
	stringRecv := types.NewVar(token.NoPos, pkg, "", stringPtr)
	stringNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(stringRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	stringNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(stringRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	stringNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(stringRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			nil, false)))
	scope.Insert(stringTypeName)

	// KeyValue struct
	kvStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Key", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", varType, false),
	}, nil)
	kvType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "KeyValue", nil),
		kvStruct, nil)
	scope.Insert(kvType.Obj())

	// callback func(KeyValue) used by Do and Map.Do
	doFuncSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "kv", kvType)),
		nil, false)

	// Map type (struct) with methods: String, Init, Get, Set, Add, AddFloat, Delete, Do
	mapTypeName := types.NewTypeName(token.NoPos, pkg, "Map", nil)
	mapNamed := types.NewNamed(mapTypeName, types.NewStruct(nil, nil), nil)
	mapPtr := types.NewPointer(mapNamed)
	mapRecv := types.NewVar(token.NoPos, pkg, "", mapPtr)
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(mapRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(mapRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", mapPtr)), false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(mapRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varType)), false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(mapRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "av", varType)),
			nil, false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(mapRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Int64])),
			nil, false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "AddFloat",
		types.NewSignatureType(mapRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Float64])),
			nil, false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Delete",
		types.NewSignatureType(mapRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			nil, false)))
	mapNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Do",
		types.NewSignatureType(mapRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f", doFuncSig)),
			nil, false)))
	scope.Insert(mapTypeName)

	// Func type: func() any, with String() method
	funcTypeName := types.NewTypeName(token.NoPos, pkg, "Func", nil)
	funcUnderlying := types.NewSignatureType(nil, nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
		false)
	funcNamed := types.NewNamed(funcTypeName, funcUnderlying, nil)
	funcRecv := types.NewVar(token.NoPos, pkg, "", funcNamed)
	funcNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(funcRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)))
	funcNamed.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(funcRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(funcTypeName)

	// func NewInt(name string) *Int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewInt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", intPtr)),
			false)))

	// func NewFloat(name string) *Float
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFloat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", floatPtr)),
			false)))

	// func NewString(name string) *String
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", stringPtr)),
			false)))

	// func NewMap(name string) *Map
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewMap",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", mapPtr)),
			false)))

	// func Get(name string) Var
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", varType)),
			false)))

	// func Publish(name string, v Var)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Publish",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "v", varType)),
			nil, false)))

	// func Do(f func(KeyValue))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Do",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f", doFuncSig)),
			nil, false)))

	// func Handler() http.Handler
	headerMap := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))
	rwIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerMap)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "WriteHeader",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "statusCode", types.Typ[types.Int])),
				nil, false)),
	}, nil)
	rwIface.Complete()
	reqPtr := types.NewPointer(types.NewStruct(nil, nil))
	handlerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ServeHTTP",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "w", rwIface),
					types.NewVar(token.NoPos, nil, "r", reqPtr)),
				nil, false)),
	}, nil)
	handlerIface.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Handler",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handlerIface)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildFilepathPackage creates the type-checked path/filepath package stub.
func buildFilepathPackage() *types.Package {
	pkg := types.NewPackage("path/filepath", "filepath")
	scope := pkg.Scope()

	// func Join(elem ...string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Join",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "elem",
				types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			true)))

	// func Base(path string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Base",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Dir(path string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Ext(path string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Ext",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Clean(path string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Clean",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Abs(path string) (string, error)
	errType := types.Universe.Lookup("error").Type()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Abs",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Rel(basepath, targpath string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Rel",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "basepath", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "targpath", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func IsAbs(path string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsAbs",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// const Separator = '/'
	scope.Insert(types.NewConst(token.NoPos, pkg, "Separator", types.Typ[types.UntypedRune],
		constant.MakeInt64('/')))

	// const ListSeparator = ':'
	scope.Insert(types.NewConst(token.NoPos, pkg, "ListSeparator", types.Typ[types.UntypedRune],
		constant.MakeInt64(':')))

	// func Split(path string) (dir, file string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Split",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "file", types.Typ[types.String])),
			false)))

	// func ToSlash(path string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToSlash",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func FromSlash(path string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FromSlash",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Match(pattern, name string) (matched bool, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Match",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "matched", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func Glob(pattern string) (matches []string, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Glob",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "matches", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func EvalSymlinks(path string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EvalSymlinks",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func VolumeName(path string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "VolumeName",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func SplitList(path string) []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SplitList",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// os.FileInfo stand-in for WalkFunc
	fileInfoIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, nil, "Mode",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)),
		types.NewFunc(token.NoPos, nil, "ModTime",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, nil, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Sys",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)),
	}, nil)
	fileInfoIface.Complete()

	// type WalkFunc func(path string, info os.FileInfo, err error) error
	walkFuncSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
			types.NewVar(token.NoPos, pkg, "info", fileInfoIface),
			types.NewVar(token.NoPos, pkg, "err", errType)),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
		false)
	walkFuncType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WalkFunc", nil),
		walkFuncSig, nil)
	scope.Insert(walkFuncType.Obj())

	// func Walk(root string, fn WalkFunc) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Walk",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "root", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "fn", walkFuncType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// fs.DirEntry stand-in for WalkDir
	dirEntryIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Type",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)),
		types.NewFunc(token.NoPos, nil, "Info",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fileInfoIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	dirEntryIface.Complete()

	// func WalkDir(root string, fn fs.WalkDirFunc) error
	walkDirFuncSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
			types.NewVar(token.NoPos, pkg, "d", dirEntryIface),
			types.NewVar(token.NoPos, pkg, "err", errType)),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WalkDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "root", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "fn", walkDirFuncSig)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// var ErrBadPattern error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrBadPattern", errType))

	// var SkipDir error
	scope.Insert(types.NewVar(token.NoPos, pkg, "SkipDir", errType))

	// var SkipAll error
	scope.Insert(types.NewVar(token.NoPos, pkg, "SkipAll", errType))

	// func HasPrefix(p, prefix string) bool — deprecated but still used
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HasPrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IsLocal(path string) bool — Go 1.20+
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsLocal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Localize(path string) (string, error) — Go 1.23+
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Localize",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoASTPackage() *types.Package {
	pkg := types.NewPackage("go/ast", "ast")
	scope := pkg.Scope()

	// Pos type (simplified as int, same underlying type as token.Pos)
	posType := types.Typ[types.Int]

	// type Node interface { Pos() token.Pos; End() token.Pos }
	nodeIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
		types.NewFunc(token.NoPos, pkg, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
	}, nil)
	nodeIface.Complete()
	nodeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Node", nil), nodeIface, nil)
	scope.Insert(nodeType.Obj())

	// type Expr interface { Node; exprNode() }
	exprIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
		types.NewFunc(token.NoPos, pkg, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
	}, nil)
	exprIface.Complete()
	exprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Expr", nil), exprIface, nil)
	scope.Insert(exprType.Obj())

	// type Stmt interface { Node; stmtNode() }
	stmtIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
		types.NewFunc(token.NoPos, pkg, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
	}, nil)
	stmtIface.Complete()
	stmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Stmt", nil), stmtIface, nil)
	scope.Insert(stmtType.Obj())

	// type Decl interface { Node; declNode() }
	declIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
		types.NewFunc(token.NoPos, pkg, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
	}, nil)
	declIface.Complete()
	declType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Decl", nil), declIface, nil)
	scope.Insert(declType.Obj())

	// type Spec interface (same shape as Node)
	specIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
		types.NewFunc(token.NoPos, pkg, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
	}, nil)
	specIface.Complete()
	specType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Spec", nil), specIface, nil)
	scope.Insert(specType.Obj())

	// type Object struct { Kind ObjKind; Name string; Decl interface{}; Data interface{}; Type interface{} }
	objKindType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ObjKind", nil), types.Typ[types.Int], nil)
	scope.Insert(objKindType.Obj())
	for i, name := range []string{"Bad", "Pkg", "Con", "Typ", "Var", "Fun", "Lbl"} {
		scope.Insert(types.NewConst(token.NoPos, pkg, name, objKindType, constant.MakeInt64(int64(i))))
	}

	anyType := types.NewInterfaceType(nil, nil)
	objectStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Kind", objKindType, false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Decl", anyType, false),
		types.NewField(token.NoPos, pkg, "Data", anyType, false),
		types.NewField(token.NoPos, pkg, "Type", anyType, false),
	}, nil)
	objectType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Object", nil), objectStruct, nil)
	scope.Insert(objectType.Obj())
	objectPtr := types.NewPointer(objectType)

	// type Ident struct { NamePos token.Pos; Name string; Obj *Object }
	identStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "NamePos", posType, false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Obj", objectPtr, false),
	}, nil)
	identType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Ident", nil), identStruct, nil)
	scope.Insert(identType.Obj())
	identPtr := types.NewPointer(identType)

	// type Scope struct { Outer *Scope; Objects map[string]*Object }
	scopeObjType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Scope", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(scopeObjType.Obj())
	scopePtr := types.NewPointer(scopeObjType)
	scopeRecv := types.NewVar(token.NoPos, nil, "s", scopePtr)
	scopeObjType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", objectPtr)), false)))
	scopeObjType.AddMethod(types.NewFunc(token.NoPos, pkg, "Insert",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "obj", objectPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", objectPtr)), false)))
	scopeObjType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewScope",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "outer", scopePtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtr)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewObj",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "kind", objKindType),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", objectPtr)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewIdent",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", identPtr)), false)))

	// type BasicLit struct { ValuePos token.Pos; Kind token.Token; Value string }
	basicLitStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ValuePos", posType, false),
		types.NewField(token.NoPos, pkg, "Kind", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.String], false),
	}, nil)
	basicLitType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BasicLit", nil), basicLitStruct, nil)
	scope.Insert(basicLitType.Obj())

	// type CommentGroup struct { List []*Comment }
	commentStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Slash", posType, false),
		types.NewField(token.NoPos, pkg, "Text", types.Typ[types.String], false),
	}, nil)
	commentType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Comment", nil), commentStruct, nil)
	scope.Insert(commentType.Obj())

	commentGroupStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "List", types.NewSlice(types.NewPointer(commentType)), false),
	}, nil)
	commentGroupType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CommentGroup", nil), commentGroupStruct, nil)
	scope.Insert(commentGroupType.Obj())
	commentGroupPtr := types.NewPointer(commentGroupType)
	commentGroupType.AddMethod(types.NewFunc(token.NoPos, pkg, "Text",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "g", commentGroupPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type FieldList struct { Opening token.Pos; List []*Field; Closing token.Pos }
	fieldStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Names", types.NewSlice(identPtr), false),
		types.NewField(token.NoPos, pkg, "Type", exprType, false),
		types.NewField(token.NoPos, pkg, "Tag", types.NewPointer(basicLitType), false),
		types.NewField(token.NoPos, pkg, "Comment", commentGroupPtr, false),
	}, nil)
	fieldType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Field", nil), fieldStruct, nil)
	scope.Insert(fieldType.Obj())
	fieldListStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Opening", posType, false),
		types.NewField(token.NoPos, pkg, "List", types.NewSlice(types.NewPointer(fieldType)), false),
		types.NewField(token.NoPos, pkg, "Closing", posType, false),
	}, nil)
	fieldListType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FieldList", nil), fieldListStruct, nil)
	scope.Insert(fieldListType.Obj())
	fieldListPtr := types.NewPointer(fieldListType)
	fieldListType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumFields",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "f", fieldListPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// type FuncType struct { Func token.Pos; Params, Results *FieldList }
	funcTypeStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Func", posType, false),
		types.NewField(token.NoPos, pkg, "Params", fieldListPtr, false),
		types.NewField(token.NoPos, pkg, "Results", fieldListPtr, false),
	}, nil)
	funcTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FuncType", nil), funcTypeStruct, nil)
	scope.Insert(funcTypeType.Obj())

	// type FuncDecl struct { Doc *CommentGroup; Recv *FieldList; Name *Ident; Type *FuncType; Body *BlockStmt }
	blockStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BlockStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Lbrace", posType, false),
			types.NewField(token.NoPos, pkg, "List", types.NewSlice(stmtType), false),
			types.NewField(token.NoPos, pkg, "Rbrace", posType, false),
		}, nil), nil)
	scope.Insert(blockStmtType.Obj())

	funcDeclStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Doc", commentGroupPtr, false),
		types.NewField(token.NoPos, pkg, "Recv", fieldListPtr, false),
		types.NewField(token.NoPos, pkg, "Name", identPtr, false),
		types.NewField(token.NoPos, pkg, "Type", types.NewPointer(funcTypeType), false),
		types.NewField(token.NoPos, pkg, "Body", types.NewPointer(blockStmtType), false),
	}, nil)
	funcDeclType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FuncDecl", nil), funcDeclStruct, nil)
	scope.Insert(funcDeclType.Obj())

	// type GenDecl struct { Doc *CommentGroup; TokPos token.Pos; Tok token.Token; Specs []Spec }
	genDeclStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Doc", commentGroupPtr, false),
		types.NewField(token.NoPos, pkg, "TokPos", posType, false),
		types.NewField(token.NoPos, pkg, "Tok", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Lparen", posType, false),
		types.NewField(token.NoPos, pkg, "Specs", types.NewSlice(specType), false),
		types.NewField(token.NoPos, pkg, "Rparen", posType, false),
	}, nil)
	genDeclType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "GenDecl", nil), genDeclStruct, nil)
	scope.Insert(genDeclType.Obj())

	// type ImportSpec struct { Doc *CommentGroup; Name *Ident; Path *BasicLit; Comment *CommentGroup }
	importSpecStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Doc", commentGroupPtr, false),
		types.NewField(token.NoPos, pkg, "Name", identPtr, false),
		types.NewField(token.NoPos, pkg, "Path", types.NewPointer(basicLitType), false),
		types.NewField(token.NoPos, pkg, "Comment", commentGroupPtr, false),
	}, nil)
	importSpecType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ImportSpec", nil), importSpecStruct, nil)
	scope.Insert(importSpecType.Obj())

	// type File struct
	fileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Doc", commentGroupPtr, false),
		types.NewField(token.NoPos, pkg, "Package", posType, false),
		types.NewField(token.NoPos, pkg, "Name", identPtr, false),
		types.NewField(token.NoPos, pkg, "Decls", types.NewSlice(declType), false),
		types.NewField(token.NoPos, pkg, "Scope", scopePtr, false),
		types.NewField(token.NoPos, pkg, "Imports", types.NewSlice(types.NewPointer(importSpecType)), false),
		types.NewField(token.NoPos, pkg, "Unresolved", types.NewSlice(identPtr), false),
		types.NewField(token.NoPos, pkg, "Comments", types.NewSlice(commentGroupPtr), false),
	}, nil)
	fileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "File", nil), fileStruct, nil)
	scope.Insert(fileType.Obj())

	// type Package struct { Name string; Scope *Scope; Imports map[string]*Object; Files map[string]*File }
	packageStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Scope", scopePtr, false),
		types.NewField(token.NoPos, pkg, "Files", types.NewMap(types.Typ[types.String], types.NewPointer(fileType)), false),
	}, nil)
	packageType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Package", nil), packageStruct, nil)
	scope.Insert(packageType.Obj())

	// Helper functions
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Inspect",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "node", nodeType),
				types.NewVar(token.NoPos, nil, "f", types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "node", nodeType)),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false))),
			nil, false)))

	// type Visitor interface { Visit(node Node) (w Visitor) }
	// Self-referential: create named type first, then set underlying interface
	visitorType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Visitor", nil), types.NewInterfaceType(nil, nil), nil)
	visitorIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Visit",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "node", nodeType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "w", visitorType)), false)),
	}, nil)
	visitorIface.Complete()
	visitorType.SetUnderlying(visitorIface)
	scope.Insert(visitorType.Obj())

	scope.Insert(types.NewFunc(token.NoPos, pkg, "Walk",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "v", visitorType),
				types.NewVar(token.NoPos, nil, "node", nodeType)),
			nil, false)))

	// *token.FileSet stand-in for Print/Fprint
	fsetPtr := types.NewPointer(types.NewStruct(nil, nil))
	errTypeAST := types.Universe.Lookup("error").Type()

	scope.Insert(types.NewFunc(token.NoPos, pkg, "Print",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fset", fsetPtr),
				types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errTypeAST)), false)))

	// io.Writer for Fprint
	byteSliceAST := types.NewSlice(types.Typ[types.Byte])
	ioWriterAST := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceAST)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errTypeAST)),
				false)),
	}, nil)
	ioWriterAST.Complete()

	// FieldFilter func(name string, value reflect.Value) bool — simplified as any
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fprint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "w", ioWriterAST),
				types.NewVar(token.NoPos, nil, "fset", fsetPtr),
				types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, nil, "f", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errTypeAST)), false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsExported",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// token.Token stand-in
	tokenIntType := types.Typ[types.Int]

	// --- Expression node types ---

	// type BadExpr struct { From, To token.Pos }
	badExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BadExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "From", posType, false),
			types.NewField(token.NoPos, pkg, "To", posType, false),
		}, nil), nil)
	scope.Insert(badExprType.Obj())

	// type Ellipsis struct { Ellipsis token.Pos; Elt Expr }
	ellipsisType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Ellipsis", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Ellipsis", posType, false),
			types.NewField(token.NoPos, pkg, "Elt", exprType, false),
		}, nil), nil)
	scope.Insert(ellipsisType.Obj())

	// type UnaryExpr struct { OpPos token.Pos; Op token.Token; X Expr }
	unaryExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UnaryExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "OpPos", posType, false),
			types.NewField(token.NoPos, pkg, "Op", tokenIntType, false),
			types.NewField(token.NoPos, pkg, "X", exprType, false),
		}, nil), nil)
	scope.Insert(unaryExprType.Obj())

	// type BinaryExpr struct { X Expr; OpPos token.Pos; Op token.Token; Y Expr }
	binaryExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BinaryExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "OpPos", posType, false),
			types.NewField(token.NoPos, pkg, "Op", tokenIntType, false),
			types.NewField(token.NoPos, pkg, "Y", exprType, false),
		}, nil), nil)
	scope.Insert(binaryExprType.Obj())

	// type StarExpr struct { Star token.Pos; X Expr }
	starExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "StarExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Star", posType, false),
			types.NewField(token.NoPos, pkg, "X", exprType, false),
		}, nil), nil)
	scope.Insert(starExprType.Obj())

	// type CallExpr struct { Fun Expr; Lparen token.Pos; Args []Expr; Ellipsis token.Pos; Rparen token.Pos }
	callExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CallExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Fun", exprType, false),
			types.NewField(token.NoPos, pkg, "Lparen", posType, false),
			types.NewField(token.NoPos, pkg, "Args", types.NewSlice(exprType), false),
			types.NewField(token.NoPos, pkg, "Ellipsis", posType, false),
			types.NewField(token.NoPos, pkg, "Rparen", posType, false),
		}, nil), nil)
	scope.Insert(callExprType.Obj())

	// type SelectorExpr struct { X Expr; Sel *Ident }
	selectorExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SelectorExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Sel", identPtr, false),
		}, nil), nil)
	scope.Insert(selectorExprType.Obj())

	// type IndexExpr struct { X Expr; Lbrack token.Pos; Index Expr; Rbrack token.Pos }
	indexExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "IndexExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Lbrack", posType, false),
			types.NewField(token.NoPos, pkg, "Index", exprType, false),
			types.NewField(token.NoPos, pkg, "Rbrack", posType, false),
		}, nil), nil)
	scope.Insert(indexExprType.Obj())

	// type IndexListExpr struct { X Expr; Lbrack token.Pos; Indices []Expr; Rbrack token.Pos }
	indexListExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "IndexListExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Lbrack", posType, false),
			types.NewField(token.NoPos, pkg, "Indices", types.NewSlice(exprType), false),
			types.NewField(token.NoPos, pkg, "Rbrack", posType, false),
		}, nil), nil)
	scope.Insert(indexListExprType.Obj())

	// type SliceExpr struct { X Expr; Lbrack token.Pos; Low, High, Max Expr; Slice3 bool; Rbrack token.Pos }
	sliceExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SliceExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Lbrack", posType, false),
			types.NewField(token.NoPos, pkg, "Low", exprType, false),
			types.NewField(token.NoPos, pkg, "High", exprType, false),
			types.NewField(token.NoPos, pkg, "Max", exprType, false),
			types.NewField(token.NoPos, pkg, "Slice3", types.Typ[types.Bool], false),
			types.NewField(token.NoPos, pkg, "Rbrack", posType, false),
		}, nil), nil)
	scope.Insert(sliceExprType.Obj())

	// type TypeAssertExpr struct { X Expr; Lparen token.Pos; Type Expr; Rparen token.Pos }
	typeAssertExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TypeAssertExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Lparen", posType, false),
			types.NewField(token.NoPos, pkg, "Type", exprType, false),
			types.NewField(token.NoPos, pkg, "Rparen", posType, false),
		}, nil), nil)
	scope.Insert(typeAssertExprType.Obj())

	// type ParenExpr struct { Lparen token.Pos; X Expr; Rparen token.Pos }
	parenExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ParenExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Lparen", posType, false),
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Rparen", posType, false),
		}, nil), nil)
	scope.Insert(parenExprType.Obj())

	// type FuncLit struct { Type *FuncType; Body *BlockStmt }
	funcLitType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "FuncLit", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Type", types.NewPointer(funcTypeType), false),
			types.NewField(token.NoPos, pkg, "Body", types.NewPointer(blockStmtType), false),
		}, nil), nil)
	scope.Insert(funcLitType.Obj())

	// type CompositeLit struct { Type Expr; Lbrace token.Pos; Elts []Expr; Rbrace token.Pos; Incomplete bool }
	compositeLitType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CompositeLit", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Type", exprType, false),
			types.NewField(token.NoPos, pkg, "Lbrace", posType, false),
			types.NewField(token.NoPos, pkg, "Elts", types.NewSlice(exprType), false),
			types.NewField(token.NoPos, pkg, "Rbrace", posType, false),
			types.NewField(token.NoPos, pkg, "Incomplete", types.Typ[types.Bool], false),
		}, nil), nil)
	scope.Insert(compositeLitType.Obj())

	// type KeyValueExpr struct { Key Expr; Colon token.Pos; Value Expr }
	keyValueExprType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "KeyValueExpr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Key", exprType, false),
			types.NewField(token.NoPos, pkg, "Colon", posType, false),
			types.NewField(token.NoPos, pkg, "Value", exprType, false),
		}, nil), nil)
	scope.Insert(keyValueExprType.Obj())

	// --- Type expression node types ---

	// type ArrayType struct { Lbrack token.Pos; Len Expr; Elt Expr }
	arrayTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ArrayType", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Lbrack", posType, false),
			types.NewField(token.NoPos, pkg, "Len", exprType, false),
			types.NewField(token.NoPos, pkg, "Elt", exprType, false),
		}, nil), nil)
	scope.Insert(arrayTypeType.Obj())

	// type StructType struct { Struct token.Pos; Fields *FieldList; Incomplete bool }
	structTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "StructType", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Struct", posType, false),
			types.NewField(token.NoPos, pkg, "Fields", fieldListPtr, false),
			types.NewField(token.NoPos, pkg, "Incomplete", types.Typ[types.Bool], false),
		}, nil), nil)
	scope.Insert(structTypeType.Obj())

	// type InterfaceType struct { Interface token.Pos; Methods *FieldList; Incomplete bool }
	interfaceTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "InterfaceType", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Interface", posType, false),
			types.NewField(token.NoPos, pkg, "Methods", fieldListPtr, false),
			types.NewField(token.NoPos, pkg, "Incomplete", types.Typ[types.Bool], false),
		}, nil), nil)
	scope.Insert(interfaceTypeType.Obj())

	// type MapType struct { Map token.Pos; Key Expr; Value Expr }
	mapTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "MapType", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Map", posType, false),
			types.NewField(token.NoPos, pkg, "Key", exprType, false),
			types.NewField(token.NoPos, pkg, "Value", exprType, false),
		}, nil), nil)
	scope.Insert(mapTypeType.Obj())

	// type ChanDir int; const SEND, RECV, SEND|RECV
	chanDirType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ChanDir", nil), types.Typ[types.Int], nil)
	scope.Insert(chanDirType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "SEND", chanDirType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RECV", chanDirType, constant.MakeInt64(2)))

	// type ChanType struct { Begin token.Pos; Arrow token.Pos; Dir ChanDir; Value Expr }
	chanTypeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ChanType", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Begin", posType, false),
			types.NewField(token.NoPos, pkg, "Arrow", posType, false),
			types.NewField(token.NoPos, pkg, "Dir", chanDirType, false),
			types.NewField(token.NoPos, pkg, "Value", exprType, false),
		}, nil), nil)
	scope.Insert(chanTypeType.Obj())

	// --- Statement node types ---

	// type BadStmt struct { From, To token.Pos }
	badStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BadStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "From", posType, false),
			types.NewField(token.NoPos, pkg, "To", posType, false),
		}, nil), nil)
	scope.Insert(badStmtType.Obj())

	// type EmptyStmt struct { Semicolon token.Pos; Implicit bool }
	emptyStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "EmptyStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Semicolon", posType, false),
			types.NewField(token.NoPos, pkg, "Implicit", types.Typ[types.Bool], false),
		}, nil), nil)
	scope.Insert(emptyStmtType.Obj())

	// type ExprStmt struct { X Expr }
	exprStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ExprStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
		}, nil), nil)
	scope.Insert(exprStmtType.Obj())

	// type SendStmt struct { Chan Expr; Arrow token.Pos; Value Expr }
	sendStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SendStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Chan", exprType, false),
			types.NewField(token.NoPos, pkg, "Arrow", posType, false),
			types.NewField(token.NoPos, pkg, "Value", exprType, false),
		}, nil), nil)
	scope.Insert(sendStmtType.Obj())

	// type IncDecStmt struct { X Expr; TokPos token.Pos; Tok token.Token }
	incDecStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "IncDecStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "TokPos", posType, false),
			types.NewField(token.NoPos, pkg, "Tok", tokenIntType, false),
		}, nil), nil)
	scope.Insert(incDecStmtType.Obj())

	// type AssignStmt struct { Lhs []Expr; TokPos token.Pos; Tok token.Token; Rhs []Expr }
	assignStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "AssignStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Lhs", types.NewSlice(exprType), false),
			types.NewField(token.NoPos, pkg, "TokPos", posType, false),
			types.NewField(token.NoPos, pkg, "Tok", tokenIntType, false),
			types.NewField(token.NoPos, pkg, "Rhs", types.NewSlice(exprType), false),
		}, nil), nil)
	scope.Insert(assignStmtType.Obj())

	// type GoStmt struct { Go token.Pos; Call *CallExpr }
	goStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "GoStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Go", posType, false),
			types.NewField(token.NoPos, pkg, "Call", types.NewPointer(callExprType), false),
		}, nil), nil)
	scope.Insert(goStmtType.Obj())

	// type DeferStmt struct { Defer token.Pos; Call *CallExpr }
	deferStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "DeferStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Defer", posType, false),
			types.NewField(token.NoPos, pkg, "Call", types.NewPointer(callExprType), false),
		}, nil), nil)
	scope.Insert(deferStmtType.Obj())

	// type ReturnStmt struct { Return token.Pos; Results []Expr }
	returnStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ReturnStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Return", posType, false),
			types.NewField(token.NoPos, pkg, "Results", types.NewSlice(exprType), false),
		}, nil), nil)
	scope.Insert(returnStmtType.Obj())

	// type BranchStmt struct { TokPos token.Pos; Tok token.Token; Label *Ident }
	branchStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BranchStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "TokPos", posType, false),
			types.NewField(token.NoPos, pkg, "Tok", tokenIntType, false),
			types.NewField(token.NoPos, pkg, "Label", identPtr, false),
		}, nil), nil)
	scope.Insert(branchStmtType.Obj())

	blockStmtPtr := types.NewPointer(blockStmtType)

	// type IfStmt struct { If token.Pos; Init Stmt; Cond Expr; Body *BlockStmt; Else Stmt }
	ifStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "IfStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "If", posType, false),
			types.NewField(token.NoPos, pkg, "Init", stmtType, false),
			types.NewField(token.NoPos, pkg, "Cond", exprType, false),
			types.NewField(token.NoPos, pkg, "Body", blockStmtPtr, false),
			types.NewField(token.NoPos, pkg, "Else", stmtType, false),
		}, nil), nil)
	scope.Insert(ifStmtType.Obj())

	// type CaseClause struct { Case token.Pos; List []Expr; Colon token.Pos; Body []Stmt }
	caseClauseType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CaseClause", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Case", posType, false),
			types.NewField(token.NoPos, pkg, "List", types.NewSlice(exprType), false),
			types.NewField(token.NoPos, pkg, "Colon", posType, false),
			types.NewField(token.NoPos, pkg, "Body", types.NewSlice(stmtType), false),
		}, nil), nil)
	scope.Insert(caseClauseType.Obj())

	// type SwitchStmt struct { Switch token.Pos; Init Stmt; Tag Expr; Body *BlockStmt }
	switchStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SwitchStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Switch", posType, false),
			types.NewField(token.NoPos, pkg, "Init", stmtType, false),
			types.NewField(token.NoPos, pkg, "Tag", exprType, false),
			types.NewField(token.NoPos, pkg, "Body", blockStmtPtr, false),
		}, nil), nil)
	scope.Insert(switchStmtType.Obj())

	// type TypeSwitchStmt struct { Switch token.Pos; Init Stmt; Assign Stmt; Body *BlockStmt }
	typeSwitchStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TypeSwitchStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Switch", posType, false),
			types.NewField(token.NoPos, pkg, "Init", stmtType, false),
			types.NewField(token.NoPos, pkg, "Assign", stmtType, false),
			types.NewField(token.NoPos, pkg, "Body", blockStmtPtr, false),
		}, nil), nil)
	scope.Insert(typeSwitchStmtType.Obj())

	// type CommClause struct { Case token.Pos; Comm Stmt; Colon token.Pos; Body []Stmt }
	commClauseType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CommClause", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Case", posType, false),
			types.NewField(token.NoPos, pkg, "Comm", stmtType, false),
			types.NewField(token.NoPos, pkg, "Colon", posType, false),
			types.NewField(token.NoPos, pkg, "Body", types.NewSlice(stmtType), false),
		}, nil), nil)
	scope.Insert(commClauseType.Obj())

	// type SelectStmt struct { Select token.Pos; Body *BlockStmt }
	selectStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SelectStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Select", posType, false),
			types.NewField(token.NoPos, pkg, "Body", blockStmtPtr, false),
		}, nil), nil)
	scope.Insert(selectStmtType.Obj())

	// type ForStmt struct { For token.Pos; Init Stmt; Cond Expr; Post Stmt; Body *BlockStmt }
	forStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ForStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "For", posType, false),
			types.NewField(token.NoPos, pkg, "Init", stmtType, false),
			types.NewField(token.NoPos, pkg, "Cond", exprType, false),
			types.NewField(token.NoPos, pkg, "Post", stmtType, false),
			types.NewField(token.NoPos, pkg, "Body", blockStmtPtr, false),
		}, nil), nil)
	scope.Insert(forStmtType.Obj())

	// type RangeStmt struct { For token.Pos; Key, Value Expr; TokPos token.Pos; Tok token.Token; X Expr; Body *BlockStmt }
	rangeStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "RangeStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "For", posType, false),
			types.NewField(token.NoPos, pkg, "Key", exprType, false),
			types.NewField(token.NoPos, pkg, "Value", exprType, false),
			types.NewField(token.NoPos, pkg, "TokPos", posType, false),
			types.NewField(token.NoPos, pkg, "Tok", tokenIntType, false),
			types.NewField(token.NoPos, pkg, "X", exprType, false),
			types.NewField(token.NoPos, pkg, "Body", blockStmtPtr, false),
		}, nil), nil)
	scope.Insert(rangeStmtType.Obj())

	// type LabeledStmt struct { Label *Ident; Colon token.Pos; Stmt Stmt }
	labeledStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "LabeledStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Label", identPtr, false),
			types.NewField(token.NoPos, pkg, "Colon", posType, false),
			types.NewField(token.NoPos, pkg, "Stmt", stmtType, false),
		}, nil), nil)
	scope.Insert(labeledStmtType.Obj())

	// type DeclStmt struct { Decl Decl }
	declStmtType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "DeclStmt", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Decl", declType, false),
		}, nil), nil)
	scope.Insert(declStmtType.Obj())

	// --- Declaration/Spec node types ---

	// type BadDecl struct { From, To token.Pos }
	badDeclType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "BadDecl", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "From", posType, false),
			types.NewField(token.NoPos, pkg, "To", posType, false),
		}, nil), nil)
	scope.Insert(badDeclType.Obj())

	// type ValueSpec struct { Doc *CommentGroup; Names []*Ident; Type Expr; Values []Expr; Comment *CommentGroup }
	valueSpecType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ValueSpec", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Doc", commentGroupPtr, false),
			types.NewField(token.NoPos, pkg, "Names", types.NewSlice(identPtr), false),
			types.NewField(token.NoPos, pkg, "Type", exprType, false),
			types.NewField(token.NoPos, pkg, "Values", types.NewSlice(exprType), false),
			types.NewField(token.NoPos, pkg, "Comment", commentGroupPtr, false),
		}, nil), nil)
	scope.Insert(valueSpecType.Obj())

	// type TypeSpec struct { Doc *CommentGroup; Name *Ident; TypeParams *FieldList; Assign token.Pos; Type Expr; Comment *CommentGroup }
	typeSpecType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TypeSpec", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Doc", commentGroupPtr, false),
			types.NewField(token.NoPos, pkg, "Name", identPtr, false),
			types.NewField(token.NoPos, pkg, "TypeParams", fieldListPtr, false),
			types.NewField(token.NoPos, pkg, "Assign", posType, false),
			types.NewField(token.NoPos, pkg, "Type", exprType, false),
			types.NewField(token.NoPos, pkg, "Comment", commentGroupPtr, false),
		}, nil), nil)
	scope.Insert(typeSpecType.Obj())

	// --- Additional utility functions ---

	// func FilterDecl(decl Decl, f Filter) bool
	// type Filter = func(string) bool
	filterType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FilterDecl",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "decl", declType),
				types.NewVar(token.NoPos, nil, "f", filterType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "FilterFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "src", types.NewPointer(fileType)),
				types.NewVar(token.NoPos, nil, "f", filterType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "FilterPackage",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pkg", types.NewPointer(packageType)),
				types.NewVar(token.NoPos, nil, "f", filterType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func NotNilFilter(_ string, v reflect.Value) bool — exported as simple func
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NotNilFilter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "v", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func FileExports(src *File) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FileExports",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "src", types.NewPointer(fileType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func PackageExports(pkg *Package) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PackageExports",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pkg", types.NewPointer(packageType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func MergePackageFiles(pkg *Package, mode MergeMode) *File
	// type MergeMode uint
	mergeModeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "MergeMode", nil), types.Typ[types.Uint], nil)
	scope.Insert(mergeModeType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "FilterFuncDuplicates", mergeModeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FilterUnassociatedComments", mergeModeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FilterImportDuplicates", mergeModeType, constant.MakeInt64(4)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "MergePackageFiles",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pkg", types.NewPointer(packageType)),
				types.NewVar(token.NoPos, nil, "mode", mergeModeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(fileType))), false)))

	// Suppress unused variable warnings
	_ = badExprType
	_ = ellipsisType
	_ = unaryExprType
	_ = binaryExprType
	_ = starExprType
	_ = callExprType
	_ = selectorExprType
	_ = indexExprType
	_ = indexListExprType
	_ = sliceExprType
	_ = typeAssertExprType
	_ = parenExprType
	_ = funcLitType
	_ = compositeLitType
	_ = keyValueExprType
	_ = arrayTypeType
	_ = structTypeType
	_ = interfaceTypeType
	_ = mapTypeType
	_ = chanTypeType
	_ = badStmtType
	_ = emptyStmtType
	_ = exprStmtType
	_ = sendStmtType
	_ = incDecStmtType
	_ = assignStmtType
	_ = goStmtType
	_ = deferStmtType
	_ = returnStmtType
	_ = branchStmtType
	_ = ifStmtType
	_ = caseClauseType
	_ = switchStmtType
	_ = typeSwitchStmtType
	_ = commClauseType
	_ = selectStmtType
	_ = forStmtType
	_ = rangeStmtType
	_ = labeledStmtType
	_ = declStmtType
	_ = badDeclType
	_ = valueSpecType
	_ = typeSpecType

	// func SortImports(fset *token.FileSet, f *File)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SortImports",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fset", fsetPtr),
				types.NewVar(token.NoPos, nil, "f", types.NewPointer(fileType))),
			nil, false)))

	// func Unparen(e Expr) Expr
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unparen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "e", exprType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", exprType)), false)))

	// func IsGenerated(file *File) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsGenerated",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "file", types.NewPointer(fileType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// type Filter func(string) bool
	astFilterTypeName := types.NewTypeName(token.NoPos, pkg, "Filter", nil)
	astFilterNamed := types.NewNamed(astFilterTypeName, filterType, nil)
	_ = astFilterNamed
	scope.Insert(astFilterTypeName)

	// type CommentMap map[Node][]*CommentGroup
	commentMapType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CommentMap", nil),
		types.NewMap(nodeType, types.NewSlice(types.NewPointer(commentGroupType))), nil)
	scope.Insert(commentMapType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildGoBuildConstraintPackage() *types.Package {
	pkg := types.NewPackage("go/build/constraint", "constraint")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Expr interface { Eval(ok func(tag string) bool) bool; String() string }
	exprIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Eval",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "ok",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "tag", types.Typ[types.String])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
						false))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
				false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
	}, nil)
	exprIface.Complete()
	exprType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Expr", nil),
		exprIface, nil)
	scope.Insert(exprType.Obj())

	// type TagExpr struct { Tag string }
	tagExprStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Tag", types.Typ[types.String], false),
	}, nil)
	tagExprType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "TagExpr", nil),
		tagExprStruct, nil)
	scope.Insert(tagExprType.Obj())

	// type NotExpr struct { X Expr }
	notExprStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "X", exprIface, false),
	}, nil)
	notExprType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NotExpr", nil),
		notExprStruct, nil)
	scope.Insert(notExprType.Obj())

	// type AndExpr struct { X, Y Expr }
	andExprStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "X", exprIface, false),
		types.NewField(token.NoPos, pkg, "Y", exprIface, false),
	}, nil)
	andExprType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "AndExpr", nil),
		andExprStruct, nil)
	scope.Insert(andExprType.Obj())

	// type OrExpr struct { X, Y Expr }
	orExprStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "X", exprIface, false),
		types.NewField(token.NoPos, pkg, "Y", exprIface, false),
	}, nil)
	orExprType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "OrExpr", nil),
		orExprStruct, nil)
	scope.Insert(orExprType.Obj())

	// type SyntaxError struct { ... }
	syntaxErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Err", types.Typ[types.String], false),
	}, nil)
	syntaxErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SyntaxError", nil),
		syntaxErrStruct, nil)
	scope.Insert(syntaxErrType.Obj())
	syntaxErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(syntaxErrType)), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))

	// func Parse(line string) (Expr, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "line", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", exprIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func IsGoBuild(line string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsGoBuild",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "line", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IsPlusBuild(line string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsPlusBuild",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "line", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func PlusBuildLines(x Expr) ([]string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PlusBuildLines",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", exprIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func GoVersion(x Expr) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GoVersion",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", exprIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoBuildPackage() *types.Package {
	pkg := types.NewPackage("go/build", "build")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Package struct
	buildPkgStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dir", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "ImportComment", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Doc", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "ImportPath", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Root", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "SrcRoot", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "PkgRoot", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "BinDir", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Goroot", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "PkgObj", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "GoFiles", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "CgoFiles", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "IgnoredGoFiles", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "TestGoFiles", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "XTestGoFiles", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Imports", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "TestImports", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "XTestImports", types.NewSlice(types.Typ[types.String]), false),
	}, nil)
	buildPkgType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Package", nil), buildPkgStruct, nil)
	scope.Insert(buildPkgType.Obj())

	// type Context struct
	contextStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "GOARCH", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "GOOS", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "GOROOT", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "GOPATH", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "CgoEnabled", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Compiler", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "BuildTags", types.NewSlice(types.Typ[types.String]), false),
	}, nil)
	contextType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Context", nil), contextStruct, nil)
	scope.Insert(contextType.Obj())
	contextPtr := types.NewPointer(contextType)
	contextRecv := types.NewVar(token.NoPos, nil, "ctxt", contextPtr)

	// var Default Context
	scope.Insert(types.NewVar(token.NoPos, pkg, "Default", contextType))

	// Context.ImportDir(dir string, mode ImportMode) (*Package, error)
	importModeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ImportMode", nil), types.Typ[types.Uint], nil)
	scope.Insert(importModeType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "FindOnly", importModeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AllowBinary", importModeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ImportComment", importModeType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "IgnoreVendor", importModeType, constant.MakeInt64(8)))

	contextType.AddMethod(types.NewFunc(token.NoPos, pkg, "Import",
		types.NewSignatureType(contextRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "srcDir", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "mode", importModeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewPointer(buildPkgType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	contextType.AddMethod(types.NewFunc(token.NoPos, pkg, "ImportDir",
		types.NewSignatureType(contextRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "mode", importModeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewPointer(buildPkgType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func Import(path, srcDir string, mode ImportMode) (*Package, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Import",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "srcDir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", importModeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(buildPkgType)),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func ImportDir(dir string, mode ImportMode) (*Package, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ImportDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", importModeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(buildPkgType)),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// type NoGoError struct { Dir string }
	noGoErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dir", types.Typ[types.String], false),
	}, nil)
	noGoErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "NoGoError", nil), noGoErrStruct, nil)
	noGoErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(noGoErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(noGoErrType.Obj())

	// type MultiplePackageError struct
	multiPkgErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dir", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Packages", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Files", types.NewSlice(types.Typ[types.String]), false),
	}, nil)
	multiPkgErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "MultiplePackageError", nil), multiPkgErrStruct, nil)
	multiPkgErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(multiPkgErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(multiPkgErrType.Obj())

	// func IsLocalImport(path string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsLocalImport",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoConstantPackage() *types.Package {
	pkg := types.NewPackage("go/constant", "constant")
	scope := pkg.Scope()
	kindType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Kind", nil), types.Typ[types.Int], nil)
	scope.Insert(kindType.Obj())
	for _, kv := range []struct {
		name string
		val  int64
	}{{"Unknown", 0}, {"Bool", 1}, {"String", 2}, {"Int", 3}, {"Float", 4}, {"Complex", 5}} {
		scope.Insert(types.NewConst(token.NoPos, pkg, kv.name, kindType, constant.MakeInt64(kv.val)))
	}
	valueIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Kind",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", kindType)), false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "ExactString",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	valueIface.Complete()
	valueType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Value", nil), valueIface, nil)
	scope.Insert(valueType.Obj())
	for _, name := range []string{"MakeBool"} {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Bool])),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))
	}
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeInt64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeFloat64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BoolVal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StringVal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int64Val",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "exact", types.Typ[types.Bool])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float64Val",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, pkg, "exact", types.Typ[types.Bool])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x_", valueType),
				types.NewVar(token.NoPos, pkg, "op", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "y_", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))

	anyType := types.Universe.Lookup("any").Type()
	byteSliceConst := types.NewSlice(types.Typ[types.Byte])

	// func MakeUint64(x uint64) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeUint64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func MakeImag(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeImag",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func MakeUnknown() Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeUnknown",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Make(x any) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Make",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func MakeFromLiteral(lit string, tok token.Token, zero uint) Value
	// token.Token is int stand-in
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeFromLiteral",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "lit", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "tok", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "zero", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func MakeFromBytes(bytes []byte) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeFromBytes",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "bytes", byteSliceConst)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Val(x Value) any
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Val",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)), false)))

	// func Uint64Val(x Value) (uint64, bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint64Val",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "exact", types.Typ[types.Bool])), false)))

	// func Float32Val(x Value) (float32, bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float32Val",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float32]),
				types.NewVar(token.NoPos, pkg, "exact", types.Typ[types.Bool])), false)))

	// func Num(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Num",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Denom(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Denom",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Real(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Real",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Imag(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Imag",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Sign(x Value) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sign",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))

	// func BitLen(x Value) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BitLen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))

	// func Bytes(x Value) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", byteSliceConst)), false)))

	// func ToInt(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToInt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func ToFloat(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToFloat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func ToComplex(x Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToComplex",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func BinaryOp(x_ Value, op token.Token, y_ Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BinaryOp",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x_", valueType),
				types.NewVar(token.NoPos, pkg, "op", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "y_", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func UnaryOp(op token.Token, y Value, prec uint) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UnaryOp",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "op", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "y", valueType),
				types.NewVar(token.NoPos, pkg, "prec", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	// func Shift(x Value, op token.Token, s uint) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Shift",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", valueType),
				types.NewVar(token.NoPos, pkg, "op", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)), false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoDocCommentPackage() *types.Package {
	pkg := types.NewPackage("go/doc/comment", "comment")
	scope := pkg.Scope()

	// type Doc struct { Content []Block; Links []*LinkDef }
	docStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Content", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Links", types.Typ[types.Int], false),
	}, nil)
	docType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Doc", nil),
		docStruct, nil)
	scope.Insert(docType.Obj())

	// type Parser struct { ... }
	parserStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Words", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "LookupPackage", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "LookupSym", types.Typ[types.Int], false),
	}, nil)
	parserType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Parser", nil),
		parserStruct, nil)
	scope.Insert(parserType.Obj())

	// Parser.Parse(text string) *Doc
	parserType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(parserType)), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(docType))),
			false)))

	// type Printer struct { ... }
	printerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "DocLinkURL", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "DocLinkBaseURL", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "HeadingLevel", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "HeadingID", types.Typ[types.Int], false),
	}, nil)
	printerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Printer", nil),
		printerStruct, nil)
	scope.Insert(printerType.Obj())

	// Printer methods
	for _, m := range []string{"HTML", "Markdown", "Text", "Comment"} {
		printerType.AddMethod(types.NewFunc(token.NoPos, pkg, m,
			types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(printerType)), nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "d", types.NewPointer(docType))),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
				false)))
	}

	// type LinkDef, DocLink, etc.
	linkDefStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Text", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "URL", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Used", types.Typ[types.Bool], false),
	}, nil)
	linkDefType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "LinkDef", nil),
		linkDefStruct, nil)
	scope.Insert(linkDefType.Obj())

	// DefaultLookupPackage
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DefaultLookupPackage",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoDocPackage() *types.Package {
	pkg := types.NewPackage("go/doc", "doc")
	scope := pkg.Scope()

	// type Package struct
	pkgStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "ImportPath", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Doc", types.Typ[types.String], false),
	}, nil)
	pkgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Package", nil),
		pkgStruct, nil)
	scope.Insert(pkgType.Obj())

	// type Type, Func, Value, Note structs
	for _, name := range []string{"Type", "Func", "Value", "Note"} {
		s := types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Doc", types.Typ[types.String], false),
		}, nil)
		t := types.NewNamed(types.NewTypeName(token.NoPos, pkg, name, nil), s, nil)
		scope.Insert(t.Obj())
	}

	// type Mode int
	modeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Mode", nil),
		types.Typ[types.Int], nil)
	scope.Insert(modeType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "AllDecls", modeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AllMethods", modeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "PreserveAST", modeType, constant.MakeInt64(4)))

	// func New(...) *Package — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pkg_", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "importPath", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", modeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(pkgType))),
			false)))

	// func Synopsis(text string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Synopsis",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ToHTML / ToText — no-op stubs
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToHTML",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "words", types.Typ[types.Int])),
			nil, false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "ToText",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "indent", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "preIndent", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "width", types.Typ[types.Int])),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoFormatPackage() *types.Package {
	pkg := types.NewPackage("go/format", "format")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Writer interface for Node dst
	ioWriterFmt := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterFmt.Complete()

	// func Source(src []byte) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Source",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "src", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Node(dst io.Writer, fset *token.FileSet, node interface{}) error
	fsetPtrFmt := types.NewPointer(types.NewStruct(nil, nil)) // *token.FileSet stand-in
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Node",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", ioWriterFmt),
				types.NewVar(token.NoPos, pkg, "fset", fsetPtrFmt),
				types.NewVar(token.NoPos, pkg, "node", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoImporterPackage() *types.Package {
	pkg := types.NewPackage("go/importer", "importer")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// types.Importer stand-in interface { Import(path string) (*types.Package, error) }
	// *types.Package simplified as opaque struct pointer
	typesPkgPtr := types.NewPointer(types.NewStruct(nil, nil))
	importerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Import",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "path", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", typesPkgPtr),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	importerIface.Complete()

	// *token.FileSet stand-in
	fsetPtrImp := types.NewPointer(types.NewStruct(nil, nil))

	// func Default() types.Importer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Default",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", importerIface)),
			false)))

	// func For(compiler string, lookup Lookup) types.Importer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "For",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "compiler", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "lookup", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", importerIface)),
			false)))

	// func ForCompiler(fset *token.FileSet, compiler string, lookup Lookup) types.Importer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ForCompiler",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fset", fsetPtrImp),
				types.NewVar(token.NoPos, pkg, "compiler", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "lookup", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", importerIface)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoParserPackage() *types.Package {
	pkg := types.NewPackage("go/parser", "parser")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anyType := types.Universe.Lookup("any").Type()

	// type Mode uint
	modeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Mode", nil), types.Typ[types.Uint], nil)
	scope.Insert(modeType.Obj())

	// Mode constants
	for i, name := range []string{"PackageClauseOnly", "ImportsOnly", "ParseComments",
		"Trace", "DeclarationErrors", "SpuriousErrors", "SkipObjectResolution", "AllErrors"} {
		val := int64(1 << i)
		if name == "AllErrors" {
			val = 1 << 5 // same as SpuriousErrors
		}
		scope.Insert(types.NewConst(token.NoPos, pkg, name, modeType, constant.MakeInt64(val)))
	}

	// Opaque fset and file types (cross-package references simplified)
	fsetType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "fset", nil), types.NewStruct(nil, nil), nil)
	fileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "file", nil), types.NewStruct(nil, nil), nil)

	// func ParseFile(fset *token.FileSet, filename string, src any, mode Mode) (*ast.File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fset", types.NewPointer(fsetType)),
				types.NewVar(token.NoPos, pkg, "filename", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "src", anyType),
				types.NewVar(token.NoPos, pkg, "mode", modeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(fileType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// *ast.Package opaque pointer for ParseDir return
	astPkgPtr := types.NewPointer(types.NewStruct(nil, nil))

	// ast.Expr stand-in interface (has Pos/End methods like all ast.Node types)
	astExprIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
		types.NewFunc(token.NoPos, nil, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	astExprIface.Complete()

	// filter is func(fs.FileInfo) bool — fs.FileInfo has Name/Size/Mode/ModTime/IsDir/Sys
	filterFuncType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "info", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, nil, "Name",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
			types.NewFunc(token.NoPos, nil, "IsDir",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		}, nil))),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
		false)

	// func ParseDir(fset *token.FileSet, path string, filter func(fs.FileInfo) bool, mode Mode) (map[string]*ast.Package, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fset", types.NewPointer(fsetType)),
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "filter", filterFuncType),
				types.NewVar(token.NoPos, pkg, "mode", modeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewMap(types.Typ[types.String], astPkgPtr)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseExprFrom(fset *token.FileSet, filename string, src any, mode Mode) (ast.Expr, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseExprFrom",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fset", types.NewPointer(fsetType)),
				types.NewVar(token.NoPos, pkg, "filename", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "src", anyType),
				types.NewVar(token.NoPos, pkg, "mode", modeType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", astExprIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseExpr(x string) (ast.Expr, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseExpr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", astExprIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoPrinterPackage() *types.Package {
	pkg := types.NewPackage("go/printer", "printer")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anyType := types.Universe.Lookup("any").Type()

	// type Mode uint
	modeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Mode", nil), types.Typ[types.Uint], nil)
	scope.Insert(modeType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "RawFormat", modeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TabIndent", modeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "UseSpaces", modeType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SourcePos", modeType, constant.MakeInt64(8)))

	// type Config struct { Mode Mode; Tabwidth int; Indent int }
	configStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Mode", modeType, false),
		types.NewField(token.NoPos, pkg, "Tabwidth", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Indent", types.Typ[types.Int], false),
	}, nil)
	configType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Config", nil), configStruct, nil)
	scope.Insert(configType.Obj())
	configPtr := types.NewPointer(configType)

	// io.Writer for Fprint output
	byteSlicePr := types.NewSlice(types.Typ[types.Byte])
	ioWriterPr := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlicePr)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterPr.Complete()

	// *token.FileSet stand-in
	fsetPtrPr := types.NewPointer(types.NewStruct(nil, nil))

	// Config.Fprint(output io.Writer, fset *token.FileSet, node any) error
	configType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fprint",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "cfg", configPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "output", ioWriterPr),
				types.NewVar(token.NoPos, nil, "fset", fsetPtrPr),
				types.NewVar(token.NoPos, nil, "node", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func Fprint(output io.Writer, fset *token.FileSet, node any) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fprint",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "output", ioWriterPr),
				types.NewVar(token.NoPos, pkg, "fset", fsetPtrPr),
				types.NewVar(token.NoPos, pkg, "node", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type CommentedNode struct { Node any; Comments []*ast.CommentGroup }
	// *ast.CommentGroup stand-in as opaque pointer
	commentGroupPtr := types.NewPointer(types.NewStruct(nil, nil))
	commentedNodeStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Node", anyType, false),
		types.NewField(token.NoPos, pkg, "Comments", types.NewSlice(commentGroupPtr), false),
	}, nil)
	commentedNodeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "CommentedNode", nil), commentedNodeStruct, nil)
	scope.Insert(commentedNodeType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildGoScannerPackage() *types.Package {
	pkg := types.NewPackage("go/scanner", "scanner")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Error struct { Pos token.Position; Msg string }
	errorStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Msg", types.Typ[types.String], false),
	}, nil)
	errorType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Error", nil), errorStruct, nil)
	scope.Insert(errorType.Obj())
	errorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", errorType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type ErrorList []*Error
	errorListType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ErrorList", nil),
		types.NewSlice(types.NewPointer(errorType)), nil)
	scope.Insert(errorListType.Obj())
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// ErrorHandler func type: func(pos token.Position, msg string)
	// token.Position stand-in as struct
	tokenPositionStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, nil, "Filename", types.Typ[types.String], false),
		types.NewField(token.NoPos, nil, "Offset", types.Typ[types.Int], false),
		types.NewField(token.NoPos, nil, "Line", types.Typ[types.Int], false),
		types.NewField(token.NoPos, nil, "Column", types.Typ[types.Int], false),
	}, nil)
	errorHandlerType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "pos", tokenPositionStruct),
			types.NewVar(token.NoPos, nil, "msg", types.Typ[types.String])),
		nil, false)

	// type ErrorHandler func(pos token.Position, msg string)
	ehNamed := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ErrorHandler", nil), errorHandlerType, nil)
	scope.Insert(ehNamed.Obj())

	// type Scanner struct { ErrorCount int; Mode Mode }
	scannerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ErrorCount", types.Typ[types.Int], false),
	}, nil)
	scannerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Scanner", nil), scannerStruct, nil)
	scope.Insert(scannerType.Obj())
	scannerPtr := types.NewPointer(scannerType)

	// type Mode uint
	modeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Mode", nil), types.Typ[types.Uint], nil)
	scope.Insert(modeType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanComments", modeType, constant.MakeInt64(1)))

	// *token.FileSet stand-in
	fsetPtrGS := types.NewPointer(types.NewStruct(nil, nil))
	// *token.File stand-in
	filePtrGS := types.NewPointer(types.NewStruct(nil, nil))

	// Scanner.Init(file *token.File, src []byte, err ErrorHandler, mode Mode)
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "s", scannerPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "file", filePtrGS),
				types.NewVar(token.NoPos, nil, "src", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "err", ehNamed),
				types.NewVar(token.NoPos, nil, "mode", modeType)),
			nil, false)))

	// token.Pos stand-in = int
	// token.Token stand-in = int
	// Scanner.Scan() (pos token.Pos, tok token.Token, lit string)
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Scan",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "s", scannerPtr), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "tok", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "lit", types.Typ[types.String])),
			false)))

	// ErrorList methods
	errorListPtr := types.NewPointer(errorListType)

	// ErrorList.Add(pos token.Position, msg string)
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", tokenPositionStruct),
				types.NewVar(token.NoPos, nil, "msg", types.Typ[types.String])),
			nil, false)))

	// ErrorList.Reset()
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListPtr), nil, nil, nil, nil, false)))

	// ErrorList.Sort()
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sort",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListType), nil, nil, nil, nil, false)))

	// ErrorList.Error() string (implements error)
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// ErrorList.Err() error
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Err",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// ErrorList.RemoveMultiples()
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "RemoveMultiples",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListPtr), nil, nil, nil, nil, false)))

	// ErrorList.Swap(i, j int) - sort.Interface
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListType), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
			nil, false)))

	// ErrorList.Less(i, j int) bool - sort.Interface
	errorListType.AddMethod(types.NewFunc(token.NoPos, pkg, "Less",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", errorListType), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func PrintError(w io.Writer, err error)
	byteSliceGS := types.NewSlice(types.Typ[types.Byte])
	ioWriterGS := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceGS)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterGS.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PrintError",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriterGS),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			nil, false)))

	_ = fsetPtrGS

	pkg.MarkComplete()
	return pkg
}

func buildGoTokenPackage() *types.Package {
	pkg := types.NewPackage("go/token", "token")
	scope := pkg.Scope()

	// type Token int
	tokenType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Token", nil),
		types.Typ[types.Int], nil)
	scope.Insert(tokenType.Obj())
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "tok", tokenType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsLiteral",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "tok", tokenType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsOperator",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "tok", tokenType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsKeyword",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "tok", tokenType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	tokenType.AddMethod(types.NewFunc(token.NoPos, pkg, "Precedence",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "tok", tokenType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// Token constants
	for i, name := range []string{
		"ILLEGAL", "EOF", "COMMENT",
		"IDENT", "INT", "FLOAT", "IMAG", "CHAR", "STRING",
		"ADD", "SUB", "MUL", "QUO", "REM",
		"AND", "OR", "XOR", "SHL", "SHR", "AND_NOT",
		"ADD_ASSIGN", "SUB_ASSIGN", "MUL_ASSIGN", "QUO_ASSIGN", "REM_ASSIGN",
		"LAND", "LOR", "ARROW", "INC", "DEC",
		"EQL", "LSS", "GTR", "ASSIGN", "NOT",
		"NEQ", "LEQ", "GEQ", "DEFINE", "ELLIPSIS",
		"LPAREN", "LBRACK", "LBRACE", "COMMA", "PERIOD",
		"RPAREN", "RBRACK", "RBRACE", "SEMICOLON", "COLON",
		"BREAK", "CASE", "CHAN", "CONST", "CONTINUE",
		"DEFAULT", "DEFER", "ELSE", "FALLTHROUGH", "FOR",
		"FUNC", "GO", "GOTO", "IF", "IMPORT",
		"INTERFACE", "MAP", "PACKAGE", "RANGE", "RETURN",
		"SELECT", "STRUCT", "SWITCH", "TYPE", "VAR",
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, name, tokenType, constant.MakeInt64(int64(i))))
	}

	// func Lookup(ident string) Token
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ident", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tokenType)), false)))

	// type Pos int
	posType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Pos", nil),
		types.Typ[types.Int], nil)
	scope.Insert(posType.Obj())
	posType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", posType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NoPos", posType, constant.MakeInt64(0)))

	// type Position struct
	positionStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Filename", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Column", types.Typ[types.Int], false),
	}, nil)
	positionType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Position", nil),
		positionStruct, nil)
	scope.Insert(positionType.Obj())
	positionType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "pos", positionType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	positionType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "pos", positionType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type File struct (opaque)
	fileType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "File", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(fileType.Obj())
	filePtr := types.NewPointer(fileType)
	fileRecv := types.NewVar(token.NoPos, nil, "f", filePtr)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Base",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "LineCount",
		types.NewSignatureType(fileRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pos",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Offset",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", posType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Position",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", posType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", positionType)), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Line",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", posType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddLine",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int])),
			nil, false)))

	// type FileSet struct (opaque)
	fsetType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FileSet", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(fsetType.Obj())
	fsetPtr := types.NewPointer(fsetType)
	fsetRecv := types.NewVar(token.NoPos, nil, "s", fsetPtr)

	// func NewFileSet() *FileSet
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFileSet",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", fsetPtr)),
			false)))

	// FileSet methods
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddFile",
		types.NewSignatureType(fsetRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "filename", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "base", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "size", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", filePtr)), false)))
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Position",
		types.NewSignatureType(fsetRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", posType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", positionType)), false)))
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "File",
		types.NewSignatureType(fsetRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", posType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", filePtr)), false)))
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Base",
		types.NewSignatureType(fsetRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// FileSet.Iterate(f func(*File) bool)
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Iterate",
		types.NewSignatureType(fsetRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", filePtr)),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false))),
			nil, false)))

	// File.SetLines(lines []int) bool
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetLines",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "lines", types.NewSlice(types.Typ[types.Int]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// File.SetLinesForContent(content []byte)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetLinesForContent",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "content", types.NewSlice(types.Typ[types.Byte]))),
			nil, false)))

	// File.MergeLine(line int)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "MergeLine",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "line", types.Typ[types.Int])),
			nil, false)))

	// File.LineStart(line int) Pos
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "LineStart",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "line", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)))

	// File.PositionFor(p Pos, adjusted bool) Position
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "PositionFor",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", posType),
				types.NewVar(token.NoPos, nil, "adjusted", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", positionType)), false)))

	// FileSet.PositionFor(p Pos, adjusted bool) Position
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "PositionFor",
		types.NewSignatureType(fsetRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "p", posType),
				types.NewVar(token.NoPos, nil, "adjusted", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", positionType)), false)))

	// File.AddLineColumnInfo(offset, line, column int)
	fileType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddLineColumnInfo",
		types.NewSignatureType(fileRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "filename", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "line", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "column", types.Typ[types.Int])),
			nil, false)))

	// Precedence constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "LowestPrec", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "UnaryPrec", types.Typ[types.Int], constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "HighestPrec", types.Typ[types.Int], constant.MakeInt64(7)))

	// func IsKeyword(name string) bool (package-level)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsKeyword",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func IsExported(name string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsExported",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func IsIdentifier(name string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsIdentifier",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// FileSet.Read and FileSet.Write for serialization
	readFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "decode",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())), false))),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())), false)
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read", types.NewSignatureType(fsetRecv, nil, nil,
		readFn.Params(), readFn.Results(), false)))
	fsetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write", types.NewSignatureType(fsetRecv, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "encode",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewInterfaceType(nil, nil))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())), false))),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())), false)))

	pkg.MarkComplete()
	return pkg
}

func buildGoTypesPackage() *types.Package {
	pkg := types.NewPackage("go/types", "types")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Type interface { Underlying() Type; String() string } — self-referential
	typeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Type", nil), types.NewInterfaceType(nil, nil), nil)
	typeIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Underlying",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	typeIface.Complete()
	typeType.SetUnderlying(typeIface)
	scope.Insert(typeType.Obj())

	// type Object interface { Name() string; Type() Type; Pos() token.Pos; Id() string; Parent() *Scope; Exported() bool; Pkg() *Package; String() string }
	objectIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Type",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)),
		types.NewFunc(token.NoPos, pkg, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "Id",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Exported",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	objectIface.Complete()
	objectType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Object", nil), objectIface, nil)
	scope.Insert(objectType.Obj())

	// type Package struct (opaque)
	pkgType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Package", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(pkgType.Obj())
	pkgPtr := types.NewPointer(pkgType)
	pkgRecv := types.NewVar(token.NoPos, nil, "pkg", pkgPtr)
	pkgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Path",
		types.NewSignatureType(pkgRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	pkgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(pkgRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	// *Scope opaque stand-in
	scopePtr := types.NewPointer(types.NewStruct(nil, nil))
	pkgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Scope",
		types.NewSignatureType(pkgRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtr)), false)))
	pkgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Imports",
		types.NewSignatureType(pkgRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(pkgPtr))), false)))
	pkgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Complete",
		types.NewSignatureType(pkgRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	pkgType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(pkgRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// ast.Expr stand-in interface (Pos/End methods)
	astExprIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Pos",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, nil, "End",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
	}, nil)
	astExprIface.Complete()

	// TypeAndValue struct stand-in { Mode int; Type Type; Value constant.Value }
	typeAndValueStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Type", typeType, false),
	}, nil)
	typeAndValueType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TypeAndValue", nil), typeAndValueStruct, nil)
	scope.Insert(typeAndValueType.Obj())

	// *ast.Ident opaque pointer for Defs/Uses map keys
	astIdentPtr := types.NewPointer(types.NewStruct(nil, nil))

	// type Info struct
	infoStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Types", types.NewMap(astExprIface, typeAndValueType), false),
		types.NewField(token.NoPos, pkg, "Defs", types.NewMap(astIdentPtr, objectType), false),
		types.NewField(token.NoPos, pkg, "Uses", types.NewMap(astIdentPtr, objectType), false),
	}, nil)
	infoType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Info", nil), infoStruct, nil)
	scope.Insert(infoType.Obj())

	// Importer interface { Import(path string) (*Package, error) }
	importerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Import",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "path", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", pkgPtr),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	importerIface.Complete()
	importerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Importer", nil), importerIface, nil)
	scope.Insert(importerType.Obj())

	// *token.FileSet and *ast.File stand-ins
	fsetPtrTypes := types.NewPointer(types.NewStruct(nil, nil))
	astFilePtr := types.NewPointer(types.NewStruct(nil, nil))

	// type Config struct
	configStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "GoVersion", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Error", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "err", errType)), nil, false), false),
		types.NewField(token.NoPos, pkg, "Importer", importerType, false),
	}, nil)
	configType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Config", nil), configStruct, nil)
	scope.Insert(configType.Obj())
	configPtr := types.NewPointer(configType)
	configType.AddMethod(types.NewFunc(token.NoPos, pkg, "Check",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "conf", configPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "fset", fsetPtrTypes),
				types.NewVar(token.NoPos, nil, "files", types.NewSlice(astFilePtr)),
				types.NewVar(token.NoPos, nil, "info", types.NewPointer(infoType))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", pkgPtr),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// type Sizes interface { Alignof(T Type) int64; Offsetsof(fields []*Var) []int64; Sizeof(T Type) int64 }
	sizesIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Alignof",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "T", typeType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, pkg, "Sizeof",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "T", typeType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
	}, nil)
	sizesIface.Complete()
	sizesType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Sizes", nil), sizesIface, nil)
	scope.Insert(sizesType.Obj())

	// func SizesFor(compiler, arch string) Sizes
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SizesFor",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "compiler", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "arch", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", sizesType)), false)))

	// type Error struct { Fset *token.FileSet; Pos token.Pos; Msg string; Soft bool }
	typesErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Fset", fsetPtrTypes, false),
		types.NewField(token.NoPos, pkg, "Pos", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Msg", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Soft", types.Typ[types.Bool], false),
	}, nil)
	typesErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Error", nil), typesErrStruct, nil)
	typesErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "err", typesErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(typesErrType.Obj())

	// Importer already defined above

	// func ExprString(x ast.Expr) string — use ast.Expr stand-in
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ExprString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", astExprIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))

	// --- Scope type ---
	// type Scope struct (with proper methods)
	scopeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Scope", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(scopeType.Obj())
	scopePtrT := types.NewPointer(scopeType)
	scopeRecv := types.NewVar(token.NoPos, nil, "s", scopePtrT)
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Names",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String]))), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumChildren",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Child",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", objectType)), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Insert",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "obj", objectType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", objectType)), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pos",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "End",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Contains",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pos", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Innermost",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pos", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(scopeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scopeType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteTo",
		types.NewSignatureType(scopeRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "w", types.NewInterfaceType([]*types.Func{
					types.NewFunc(token.NoPos, nil, "Write",
						types.NewSignatureType(nil, nil, nil,
							types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
							types.NewTuple(
								types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
								types.NewVar(token.NoPos, nil, "err", errType)),
							false)),
				}, nil)),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "recurse", types.Typ[types.Bool])),
			nil, false)))

	// --- Concrete Object subtypes (implement Object interface) ---
	posType := types.Typ[types.Int] // token.Pos stand-in

	// type Var struct (opaque - satisfies Object)
	varType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Var", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(varType.Obj())
	varPtr := types.NewPointer(varType)
	varRecv := types.NewVar(token.NoPos, nil, "v", varPtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		varType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(varRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	varType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(varRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	varType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(varRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))
	varType.AddMethod(types.NewFunc(token.NoPos, pkg, "Anonymous",
		types.NewSignatureType(varRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	varType.AddMethod(types.NewFunc(token.NoPos, pkg, "Embedded",
		types.NewSignatureType(varRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	varType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsField",
		types.NewSignatureType(varRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	varType.AddMethod(types.NewFunc(token.NoPos, pkg, "Origin",
		types.NewSignatureType(varRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varPtr)), false)))

	// type Const struct (opaque - satisfies Object)
	constType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Const", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(constType.Obj())
	constPtr := types.NewPointer(constType)
	constRecv := types.NewVar(token.NoPos, nil, "c", constPtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		constType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(constRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	constType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(constRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	constType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(constRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))
	// Val() constant.Value — simplify to any
	constType.AddMethod(types.NewFunc(token.NoPos, pkg, "Val",
		types.NewSignatureType(constRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)))

	// type Func struct (opaque - satisfies Object)
	funcType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Func", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(funcType.Obj())
	funcPtr := types.NewPointer(funcType)
	funcRecv := types.NewVar(token.NoPos, nil, "f", funcPtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
		{"FullName", types.Typ[types.String]},
	} {
		funcType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(funcRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	funcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(funcRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	funcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(funcRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))
	funcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Origin",
		types.NewSignatureType(funcRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", funcPtr)), false)))

	// type TypeName struct (opaque - satisfies Object)
	typeNameType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TypeName", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(typeNameType.Obj())
	typeNamePtr := types.NewPointer(typeNameType)
	typeNameRecv := types.NewVar(token.NoPos, nil, "t", typeNamePtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		typeNameType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(typeNameRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	typeNameType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(typeNameRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	typeNameType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(typeNameRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))
	typeNameType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsAlias",
		types.NewSignatureType(typeNameRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// type Label struct (opaque - satisfies Object)
	labelType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Label", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(labelType.Obj())
	labelPtr := types.NewPointer(labelType)
	labelRecv := types.NewVar(token.NoPos, nil, "l", labelPtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		labelType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(labelRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	labelType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(labelRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	labelType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(labelRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))

	// type PkgName struct (opaque - satisfies Object)
	pkgNameType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "PkgName", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(pkgNameType.Obj())
	pkgNamePtr := types.NewPointer(pkgNameType)
	pkgNameRecv := types.NewVar(token.NoPos, nil, "p", pkgNamePtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		pkgNameType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(pkgNameRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	pkgNameType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(pkgNameRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	pkgNameType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(pkgNameRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))
	pkgNameType.AddMethod(types.NewFunc(token.NoPos, pkg, "Imported",
		types.NewSignatureType(pkgNameRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))

	// type Builtin struct (opaque - satisfies Object)
	builtinType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Builtin", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(builtinType.Obj())
	builtinPtr := types.NewPointer(builtinType)
	builtinRecv := types.NewVar(token.NoPos, nil, "b", builtinPtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		builtinType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(builtinRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	builtinType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(builtinRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	builtinType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(builtinRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))

	// type Nil struct (opaque - satisfies Object)
	nilObjType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Nil", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(nilObjType.Obj())
	nilObjPtr := types.NewPointer(nilObjType)
	nilObjRecv := types.NewVar(token.NoPos, nil, "n", nilObjPtr)
	for _, m := range []struct{ name string; retType types.Type }{
		{"Name", types.Typ[types.String]}, {"Type", typeType}, {"Pos", posType},
		{"Id", types.Typ[types.String]}, {"Exported", types.Typ[types.Bool]}, {"String", types.Typ[types.String]},
	} {
		nilObjType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(nilObjRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", m.retType)), false)))
	}
	nilObjType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parent",
		types.NewSignatureType(nilObjRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))
	nilObjType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pkg",
		types.NewSignatureType(nilObjRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))

	// --- Constructor functions for Object subtypes ---
	// func NewVar(pos token.Pos, pkg *Package, name string, typ Type) *Var
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewVar",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "typ", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varPtr)), false)))

	// func NewConst(pos token.Pos, pkg *Package, name string, typ Type, val constant.Value) *Const
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewConst",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "typ", typeType),
				types.NewVar(token.NoPos, nil, "val", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", constPtr)), false)))

	// func NewFunc(pos token.Pos, pkg *Package, name string, sig *Signature) *Func
	// *Signature stand-in
	sigPtr := types.NewPointer(types.NewStruct(nil, nil))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "sig", sigPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", funcPtr)), false)))

	// func NewTypeName(pos token.Pos, pkg *Package, name string, typ Type) *TypeName
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTypeName",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "typ", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeNamePtr)), false)))

	// func NewLabel(pos token.Pos, pkg *Package, name string) *Label
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewLabel",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", labelPtr)), false)))

	// func NewPkgName(pos token.Pos, pkg *Package, name string, imported *Package) *PkgName
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewPkgName",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "imported", pkgPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgNamePtr)), false)))

	// func NewField(pos token.Pos, pkg *Package, name string, typ Type, embedded bool) *Var
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewField",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "typ", typeType),
				types.NewVar(token.NoPos, nil, "embedded", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varPtr)), false)))

	// --- Concrete Type types ---

	// type Basic struct (opaque)
	basicType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Basic", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(basicType.Obj())
	basicPtr := types.NewPointer(basicType)
	basicRecv := types.NewVar(token.NoPos, nil, "b", basicPtr)
	basicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Kind",
		types.NewSignatureType(basicRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	basicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Info",
		types.NewSignatureType(basicRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	basicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(basicRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	basicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(basicRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	basicType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(basicRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Named struct (opaque)
	namedType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Named", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(namedType.Obj())
	namedPtr := types.NewPointer(namedType)
	namedRecv := types.NewVar(token.NoPos, nil, "n", namedPtr)
	namedType.AddMethod(types.NewFunc(token.NoPos, pkg, "Obj",
		types.NewSignatureType(namedRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeNamePtr)), false)))
	namedType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumMethods",
		types.NewSignatureType(namedRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	namedType.AddMethod(types.NewFunc(token.NoPos, pkg, "Method",
		types.NewSignatureType(namedRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", funcPtr)), false)))
	namedType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(namedRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	namedType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(namedRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Pointer struct (opaque)
	pointerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Pointer", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(pointerType.Obj())
	pointerPtr := types.NewPointer(pointerType)
	pointerRecv := types.NewVar(token.NoPos, nil, "p", pointerPtr)
	pointerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Elem",
		types.NewSignatureType(pointerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	pointerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(pointerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	pointerType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(pointerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Array struct (opaque)
	arrayType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Array", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(arrayType.Obj())
	arrayPtr := types.NewPointer(arrayType)
	arrayRecv := types.NewVar(token.NoPos, nil, "a", arrayPtr)
	arrayType.AddMethod(types.NewFunc(token.NoPos, pkg, "Elem",
		types.NewSignatureType(arrayRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	arrayType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(arrayRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)))
	arrayType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(arrayRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	arrayType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(arrayRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Slice struct (opaque)
	sliceType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Slice", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(sliceType.Obj())
	slicePtr := types.NewPointer(sliceType)
	sliceRecv := types.NewVar(token.NoPos, nil, "s", slicePtr)
	sliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Elem",
		types.NewSignatureType(sliceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	sliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(sliceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	sliceType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(sliceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Map struct (opaque)
	mapType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Map", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(mapType.Obj())
	mapPtr := types.NewPointer(mapType)
	mapRecv := types.NewVar(token.NoPos, nil, "m", mapPtr)
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "Key",
		types.NewSignatureType(mapRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "Elem",
		types.NewSignatureType(mapRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(mapRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	mapType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(mapRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Chan struct (opaque)
	chanType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Chan", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(chanType.Obj())
	chanPtr := types.NewPointer(chanType)
	chanRecv := types.NewVar(token.NoPos, nil, "c", chanPtr)
	chanType.AddMethod(types.NewFunc(token.NoPos, pkg, "Dir",
		types.NewSignatureType(chanRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	chanType.AddMethod(types.NewFunc(token.NoPos, pkg, "Elem",
		types.NewSignatureType(chanRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	chanType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(chanRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	chanType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(chanRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type ChanDir int
	chanDirType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ChanDir", nil), types.Typ[types.Int], nil)
	scope.Insert(chanDirType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "SendRecv", chanDirType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SendOnly", chanDirType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RecvOnly", chanDirType, constant.MakeInt64(2)))

	// type Struct struct (opaque)
	structType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Struct", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(structType.Obj())
	structPtr := types.NewPointer(structType)
	structRecv := types.NewVar(token.NoPos, nil, "s", structPtr)
	structType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumFields",
		types.NewSignatureType(structRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	structType.AddMethod(types.NewFunc(token.NoPos, pkg, "Field",
		types.NewSignatureType(structRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varPtr)), false)))
	structType.AddMethod(types.NewFunc(token.NoPos, pkg, "Tag",
		types.NewSignatureType(structRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	structType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(structRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	structType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(structRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Signature struct (opaque)
	signatureType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Signature", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(signatureType.Obj())
	signaturePtr := types.NewPointer(signatureType)
	signatureRecv := types.NewVar(token.NoPos, nil, "s", signaturePtr)
	// type Tuple struct (opaque)
	tupleType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Tuple", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(tupleType.Obj())
	tuplePtr := types.NewPointer(tupleType)
	tupleRecv := types.NewVar(token.NoPos, nil, "t", tuplePtr)
	tupleType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(tupleRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	tupleType.AddMethod(types.NewFunc(token.NoPos, pkg, "At",
		types.NewSignatureType(tupleRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varPtr)), false)))

	signatureType.AddMethod(types.NewFunc(token.NoPos, pkg, "Recv",
		types.NewSignatureType(signatureRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", varPtr)), false)))
	signatureType.AddMethod(types.NewFunc(token.NoPos, pkg, "Params",
		types.NewSignatureType(signatureRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", tuplePtr)), false)))
	signatureType.AddMethod(types.NewFunc(token.NoPos, pkg, "Results",
		types.NewSignatureType(signatureRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", tuplePtr)), false)))
	signatureType.AddMethod(types.NewFunc(token.NoPos, pkg, "Variadic",
		types.NewSignatureType(signatureRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	signatureType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(signatureRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	signatureType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(signatureRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Interface struct (opaque)
	ifaceType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Interface", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(ifaceType.Obj())
	ifacePtr := types.NewPointer(ifaceType)
	ifaceRecv := types.NewVar(token.NoPos, nil, "i", ifacePtr)
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumMethods",
		types.NewSignatureType(ifaceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Method",
		types.NewSignatureType(ifaceRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", funcPtr)), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumEmbeddeds",
		types.NewSignatureType(ifaceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "EmbeddedType",
		types.NewSignatureType(ifaceRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Empty",
		types.NewSignatureType(ifaceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Complete",
		types.NewSignatureType(ifaceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ifacePtr)), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Underlying",
		types.NewSignatureType(ifaceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(ifaceRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// --- Type assertion functions ---

	// func Implements(V Type, T *Interface) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Implements",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "V", typeType),
				types.NewVar(token.NoPos, nil, "T", ifacePtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func AssignableTo(V, T Type) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AssignableTo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "V", typeType),
				types.NewVar(token.NoPos, nil, "T", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func ConvertibleTo(V, T Type) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ConvertibleTo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "V", typeType),
				types.NewVar(token.NoPos, nil, "T", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func Identical(x, y Type) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Identical",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", typeType),
				types.NewVar(token.NoPos, nil, "y", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func IdenticalIgnoreTags(x, y Type) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IdenticalIgnoreTags",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", typeType),
				types.NewVar(token.NoPos, nil, "y", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func Comparable(T Type) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Comparable",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "T", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func Default(typ Type) Type
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Default",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "typ", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))

	// --- Type constructor functions ---

	// func NewArray(elem Type, len int64) *Array
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewArray",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "elem", typeType),
				types.NewVar(token.NoPos, nil, "len", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", arrayPtr)), false)))

	// func NewSlice(elem Type) *Slice
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewSlice",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "elem", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", slicePtr)), false)))

	// func NewMap(key, elem Type) *Map
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewMap",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", typeType),
				types.NewVar(token.NoPos, nil, "elem", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", mapPtr)), false)))

	// func NewChan(dir ChanDir, elem Type) *Chan
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewChan",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dir", chanDirType),
				types.NewVar(token.NoPos, nil, "elem", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", chanPtr)), false)))

	// func NewPointer(elem Type) *Pointer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewPointer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "elem", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pointerPtr)), false)))

	// func NewStruct(fields []*Var, tags []string) *Struct
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewStruct",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "fields", types.NewSlice(varPtr)),
				types.NewVar(token.NoPos, nil, "tags", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", structPtr)), false)))

	// func NewTuple(x ...*Var) *Tuple
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTuple",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewSlice(varPtr))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", tuplePtr)), true)))

	// func NewSignature(recv *Var, params, results *Tuple, variadic bool) *Signature
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewSignature",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "recv", varPtr),
				types.NewVar(token.NoPos, nil, "params", tuplePtr),
				types.NewVar(token.NoPos, nil, "results", tuplePtr),
				types.NewVar(token.NoPos, nil, "variadic", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", signaturePtr)), false)))

	// func NewSignatureType(recv *Var, recvTypeParams, typeParams []*TypeParam, params, results *Tuple, variadic bool) *Signature
	typeParamSlice := types.NewSlice(types.NewPointer(types.NewStruct(nil, nil)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewSignatureType",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "recv", varPtr),
				types.NewVar(token.NoPos, nil, "recvTypeParams", typeParamSlice),
				types.NewVar(token.NoPos, nil, "typeParams", typeParamSlice),
				types.NewVar(token.NoPos, nil, "params", tuplePtr),
				types.NewVar(token.NoPos, nil, "results", tuplePtr),
				types.NewVar(token.NoPos, nil, "variadic", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", signaturePtr)), false)))

	// func NewInterfaceType(methods []*Func, embeddeds []Type) *Interface
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewInterfaceType",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "methods", types.NewSlice(funcPtr)),
				types.NewVar(token.NoPos, nil, "embeddeds", types.NewSlice(typeType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ifacePtr)), false)))

	// func NewNamed(obj *TypeName, underlying Type, methods []*Func) *Named
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewNamed",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "obj", typeNamePtr),
				types.NewVar(token.NoPos, nil, "underlying", typeType),
				types.NewVar(token.NoPos, nil, "methods", types.NewSlice(funcPtr))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", namedPtr)), false)))

	// func NewPackage(path, name string) *Package
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewPackage",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)), false)))

	// func NewScope(parent *Scope, pos, end token.Pos, comment string) *Scope
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewScope",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "parent", scopePtrT),
				types.NewVar(token.NoPos, nil, "pos", posType),
				types.NewVar(token.NoPos, nil, "end", posType),
				types.NewVar(token.NoPos, nil, "comment", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", scopePtrT)), false)))

	// --- Type utility functions ---

	// func ObjectString(obj Object, qf Qualifier) string
	// type Qualifier = func(*Package) string
	qualifierType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "", pkgPtr)),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ObjectString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "obj", objectType),
				types.NewVar(token.NoPos, nil, "qf", qualifierType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// func TypeString(typ Type, qf Qualifier) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TypeString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "typ", typeType),
				types.NewVar(token.NoPos, nil, "qf", qualifierType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// func SelectionString(s *Selection, qf Qualifier) string — *Selection opaque
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SelectionString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "s", types.NewPointer(types.NewStruct(nil, nil))),
				types.NewVar(token.NoPos, nil, "qf", qualifierType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// func RelativeTo(pkg *Package) Qualifier
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RelativeTo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pkg", pkgPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", qualifierType)), false)))

	// func WriteType(buf *bytes.Buffer, typ Type, qf Qualifier) — buf simplified to io.Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteType",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "buf", types.NewPointer(types.NewStruct(nil, nil))),
				types.NewVar(token.NoPos, nil, "typ", typeType),
				types.NewVar(token.NoPos, nil, "qf", qualifierType)),
			nil, false)))

	// func WriteSignature(buf *bytes.Buffer, sig *Signature, qf Qualifier)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteSignature",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "buf", types.NewPointer(types.NewStruct(nil, nil))),
				types.NewVar(token.NoPos, nil, "sig", signaturePtr),
				types.NewVar(token.NoPos, nil, "qf", qualifierType)),
			nil, false)))

	// func Id(pkg *Package, name string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Id",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// func LookupFieldOrMethod(T Type, addressable bool, pkg *Package, name string) (obj Object, index []int, indirect bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupFieldOrMethod",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "T", typeType),
				types.NewVar(token.NoPos, nil, "addressable", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, nil, "pkg", pkgPtr),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "obj", objectType),
				types.NewVar(token.NoPos, nil, "index", types.NewSlice(types.Typ[types.Int])),
				types.NewVar(token.NoPos, nil, "indirect", types.Typ[types.Bool])), false)))

	// func MissingMethod(V Type, T *Interface, static bool) (method *Func, wrongType bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MissingMethod",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "V", typeType),
				types.NewVar(token.NoPos, nil, "T", ifacePtr),
				types.NewVar(token.NoPos, nil, "static", types.Typ[types.Bool])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "method", funcPtr),
				types.NewVar(token.NoPos, nil, "wrongType", types.Typ[types.Bool])), false)))

	// type Selection struct (opaque)
	selectionType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Selection", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(selectionType.Obj())
	selPtr := types.NewPointer(selectionType)
	selRecv := types.NewVar(token.NoPos, nil, "s", selPtr)
	// type SelectionKind int
	selKindType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SelectionKind", nil), types.Typ[types.Int], nil)
	scope.Insert(selKindType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "FieldVal", selKindType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodVal", selKindType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodExpr", selKindType, constant.MakeInt64(2)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Kind",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", selKindType)), false)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Recv",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Obj",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", objectType)), false)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Type",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Int]))), false)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "Indirect",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	selectionType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(selRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// Add Selections and Scopes and Instances to Info struct - update it
	// Info.Selections map[*ast.SelectorExpr]*Selection  -- we already have Types, Defs, Uses
	// Info.Scopes map[ast.Node]*Scope
	// Info.Implicits map[ast.Node]Object
	// These are already covered by the opaque pattern - for now the existing Info fields suffice

	// type TypeAndValue — add Mode and Value fields (currently only has Type)
	// TypeAndValue.IsVoid, IsType, IsBuiltin, IsValue, IsNil, IsAddressable, IsAssignable, HasOk
	tavRecv := types.NewVar(token.NoPos, nil, "tv", typeAndValueType)
	for _, m := range []string{"IsVoid", "IsType", "IsBuiltin", "IsValue", "IsNil", "IsAddressable", "IsAssignable", "HasOk"} {
		typeAndValueType.AddMethod(types.NewFunc(token.NoPos, pkg, m,
			types.NewSignatureType(tavRecv, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	}

	pkg.MarkComplete()
	return pkg
}

func buildGoVersionPackage() *types.Package {
	pkg := types.NewPackage("go/version", "version")
	scope := pkg.Scope()

	// func Compare(x, y string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func IsValid(x string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Lang(x string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lang",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildHTMLPackage creates the type-checked html package stub.
func buildHTMLPackage() *types.Package {
	pkg := types.NewPackage("html", "html")
	scope := pkg.Scope()

	scope.Insert(types.NewFunc(token.NoPos, pkg, "EscapeString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "UnescapeString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildHTMLTemplatePackage creates the type-checked html/template package stub.
func buildHTMLTemplatePackage() *types.Package {
	pkg := types.NewPackage("html/template", "template")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anyType := types.Universe.Lookup("any").Type()

	tmplStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "name", types.Typ[types.String], false),
	}, nil)
	tmplType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Template", nil),
		tmplStruct, nil)
	scope.Insert(tmplType.Obj())
	tmplPtr := types.NewPointer(tmplType)

	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))

	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "t", tmplPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type FuncMap map[string]any
	funcMapType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FuncMap", nil),
		types.NewMap(types.Typ[types.String], anyType), nil)
	scope.Insert(funcMapType.Obj())

	// io.Writer for template Execute
	htmlByteSlice := types.NewSlice(types.Typ[types.Byte])
	htmlWriterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", htmlByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	htmlWriterIface.Complete()

	tmplRecv := types.NewVar(token.NoPos, nil, "t", tmplPtr)
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Execute",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "wr", htmlWriterIface),
				types.NewVar(token.NoPos, pkg, "data", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExecuteTemplate",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "wr", htmlWriterIface),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "data", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Funcs",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "funcMap", funcMapType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(tmplRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Option",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "opt", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			true)))
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(tmplRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Delims",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "left", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "right", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "ParseFiles",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "filenames", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "ParseGlob",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// AddParseTree(name string, tree *parse.Tree) (*Template, error)
	parseTreePtr := types.NewPointer(types.NewStruct(nil, nil))
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddParseTree",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "tree", parseTreePtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Templates() []*Template
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Templates",
		types.NewSignatureType(tmplRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(tmplPtr))),
			false)))

	// DefinedTemplates() string
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "DefinedTemplates",
		types.NewSignatureType(tmplRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Package-level functions
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Must",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "t", tmplPtr),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseFiles",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "filenames", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseGlob",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// HTML escaping functions
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HTMLEscapeString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func HTMLEscape(w io.Writer, b []byte)
	htmlIoWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	htmlIoWriter.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HTMLEscape",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", htmlIoWriter),
				types.NewVar(token.NoPos, pkg, "b", types.NewSlice(types.Typ[types.Byte]))),
			nil, false)))

	// func JSEscape(w io.Writer, b []byte)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "JSEscape",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", htmlIoWriter),
				types.NewVar(token.NoPos, pkg, "b", types.NewSlice(types.Typ[types.Byte]))),
			nil, false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "HTMLEscaper",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			true)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "JSEscapeString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "JSEscaper",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			true)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "URLQueryEscaper",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			true)))

	// Content types
	htmlType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "HTML", nil),
		types.Typ[types.String], nil)
	scope.Insert(htmlType.Obj())
	cssType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CSS", nil),
		types.Typ[types.String], nil)
	scope.Insert(cssType.Obj())
	jsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "JS", nil),
		types.Typ[types.String], nil)
	scope.Insert(jsType.Obj())
	jsStrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "JSStr", nil),
		types.Typ[types.String], nil)
	scope.Insert(jsStrType.Obj())
	urlType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "URL", nil),
		types.Typ[types.String], nil)
	scope.Insert(urlType.Obj())
	srcsetType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Srcset", nil),
		types.Typ[types.String], nil)
	scope.Insert(srcsetType.Obj())
	htmlAttrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "HTMLAttr", nil),
		types.Typ[types.String], nil)
	scope.Insert(htmlAttrType.Obj())

	// type Error struct
	// parse.Node stand-in interface (from text/template/parse)
	parseNodeIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "Type",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
	}, nil)
	parseNodeIface.Complete()

	tplErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ErrorCode", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Node", parseNodeIface, false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Description", types.Typ[types.String], false),
	}, nil)
	tplErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Error", nil),
		tplErrStruct, nil)
	tplErrPtr := types.NewPointer(tplErrType)
	tplErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", tplErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(tplErrType.Obj())

	// ErrorCode constants
	errCodeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ErrorCode", nil),
		types.Typ[types.Int], nil)
	scope.Insert(errCodeType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "OK", errCodeType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ErrAmbigContext", errCodeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ErrBadHTML", errCodeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ErrBranchEnd", errCodeType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ErrEndContext", errCodeType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ErrNoSuchTemplate", errCodeType, constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ErrOutputContext", errCodeType, constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ErrPartialCharset", errCodeType, constant.MakeInt64(7)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ErrPartialEscape", errCodeType, constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ErrRangeLoopReentry", errCodeType, constant.MakeInt64(9)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ErrSlashAmbig", errCodeType, constant.MakeInt64(10)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ErrPredefinedEscaper", errCodeType, constant.MakeInt64(11)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ErrJSTemplate", errCodeType, constant.MakeInt64(12)))

	// Templates() []*Template method
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Templates",
		types.NewSignatureType(tmplRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(tmplPtr))),
			false)))

	// DefinedTemplates() string method
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "DefinedTemplates",
		types.NewSignatureType(tmplRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// fs.FS stand-in interface for ParseFS
	htmlFsIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil)),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	htmlFsIface.Complete()

	// ParseFS package-level function
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseFS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fsys", htmlFsIface),
				types.NewVar(token.NoPos, pkg, "patterns", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// ParseFS method on Template
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "ParseFS",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fsys", htmlFsIface),
				types.NewVar(token.NoPos, pkg, "patterns", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// IsTrue function
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsTrue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "val", anyType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "truth", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, pkg, "ok", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildHashAdler32Package() *types.Package {
	pkg := types.NewPackage("hash/adler32", "adler32")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// hash.Hash32 interface (embeds hash.Hash + Sum32)
	hashIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Sum",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
				false)),
		types.NewFunc(token.NoPos, nil, "Reset",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
		types.NewFunc(token.NoPos, nil, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	hashIface.Complete()

	scope.Insert(types.NewConst(token.NoPos, pkg, "Size", types.Typ[types.Int], constant.MakeInt64(4)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Checksum",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])), false)))
	pkg.MarkComplete()
	return pkg
}

// buildHashCRC32Package creates the type-checked hash/crc32 package stub.
func buildHashCRC32Package() *types.Package {
	pkg := types.NewPackage("hash/crc32", "crc32")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// const Size = 4
	scope.Insert(types.NewConst(token.NoPos, pkg, "Size", types.Typ[types.Int],
		constant.MakeInt64(4)))

	// type Table [256]uint32
	tableType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Table", nil),
		types.NewArray(types.Typ[types.Uint32], 256), nil)
	scope.Insert(tableType.Obj())
	tablePtr := types.NewPointer(tableType)

	// Predefined polynomial constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "IEEE", types.Typ[types.Uint32], constant.MakeUint64(0xedb88320)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Castagnoli", types.Typ[types.Uint32], constant.MakeUint64(0x82f63b78)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Koopman", types.Typ[types.Uint32], constant.MakeUint64(0xeb31d82e)))

	// var IEEETable *Table
	scope.Insert(types.NewVar(token.NoPos, pkg, "IEEETable", tablePtr))

	// var CastagnoliTable *Table
	scope.Insert(types.NewVar(token.NoPos, pkg, "CastagnoliTable", tablePtr))

	// var KoopmanTable *Table
	scope.Insert(types.NewVar(token.NoPos, pkg, "KoopmanTable", tablePtr))

	// func MakeTable(poly uint32) *Table
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeTable",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "poly", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tablePtr)),
			false)))

	// hash.Hash32 interface
	hashIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", types.Universe.Lookup("error").Type())),
				false)),
		types.NewFunc(token.NoPos, nil, "Sum",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
				false)),
		types.NewFunc(token.NoPos, nil, "Reset",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
		types.NewFunc(token.NoPos, nil, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	hashIface.Complete()

	// func New(tab *Table) hash.Hash32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "tab", tablePtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)),
			false)))

	// func NewIEEE() hash.Hash32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewIEEE",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)),
			false)))

	// func ChecksumIEEE(data []byte) uint32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ChecksumIEEE",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])),
			false)))

	// func Checksum(data []byte, tab *Table) uint32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Checksum",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", byteSlice),
				types.NewVar(token.NoPos, pkg, "tab", tablePtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])),
			false)))

	// func Update(crc uint32, tab *Table, p []byte) uint32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Update",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "crc", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, pkg, "tab", tablePtr),
				types.NewVar(token.NoPos, pkg, "p", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildHashCRC64Package() *types.Package {
	pkg := types.NewPackage("hash/crc64", "crc64")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// hash.Hash64 interface
	hashIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Sum",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
				false)),
		types.NewFunc(token.NoPos, nil, "Reset",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
		types.NewFunc(token.NoPos, nil, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	hashIface.Complete()

	tableType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Table", nil),
		types.NewArray(types.Typ[types.Uint64], 256), nil)
	scope.Insert(tableType.Obj())
	tablePtr := types.NewPointer(tableType)

	scope.Insert(types.NewConst(token.NoPos, pkg, "Size", types.Typ[types.Int], constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ISO", types.Typ[types.Uint64], constant.MakeUint64(0xD800000000000000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ECMA", types.Typ[types.Uint64], constant.MakeUint64(0x42F0E1EBA9EA3693)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "tab", tablePtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeTable",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "poly", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tablePtr)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Checksum",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "data", byteSlice),
				types.NewVar(token.NoPos, pkg, "tab", tablePtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Update",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "crc", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "tab", tablePtr),
				types.NewVar(token.NoPos, pkg, "p", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])), false)))

	pkg.MarkComplete()
	return pkg
}

func buildHashFNVPackage() *types.Package {
	pkg := types.NewPackage("hash/fnv", "fnv")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// hash.Hash interface
	hashIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Sum",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
				false)),
		types.NewFunc(token.NoPos, nil, "Reset",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
		types.NewFunc(token.NoPos, nil, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	hashIface.Complete()

	// New32, New32a return hash.Hash32 (use hash.Hash)
	// New64, New64a return hash.Hash64 (use hash.Hash)
	// New128, New128a return hash.Hash (use hash.Hash)
	for _, name := range []string{"New32", "New32a", "New64", "New64a", "New128", "New128a"} {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", hashIface)),
				false)))
	}

	pkg.MarkComplete()
	return pkg
}

func buildHashMaphashPackage() *types.Package {
	pkg := types.NewPackage("hash/maphash", "maphash")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type Seed struct (opaque)
	seedType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Seed", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(seedType.Obj())

	// func MakeSeed() Seed
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeSeed",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", seedType)),
			false)))

	// type Hash struct (opaque)
	hashType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Hash", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(hashType.Obj())
	hashPtr := types.NewPointer(hashType)
	hashRecv := types.NewVar(token.NoPos, nil, "h", hashPtr)

	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(hashRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteByte",
		types.NewSignatureType(hashRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.Typ[types.Byte])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteString",
		types.NewSignatureType(hashRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sum64",
		types.NewSignatureType(hashRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seed",
		types.NewSignatureType(hashRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", seedType)), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetSeed",
		types.NewSignatureType(hashRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "seed", seedType)),
			nil, false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(hashRecv, nil, nil, nil, nil, false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(hashRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "BlockSize",
		types.NewSignatureType(hashRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	hashType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sum",
		types.NewSignatureType(hashRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)))

	// func Bytes(seed Seed, b []byte) uint64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "seed", seedType),
				types.NewVar(token.NoPos, pkg, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))

	// func String(seed Seed, s string) uint64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "seed", seedType),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildHashPackage creates the type-checked hash package stub.
func buildHashPackage() *types.Package {
	pkg := types.NewPackage("hash", "hash")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type Hash interface {
	//   io.Writer (Write(p []byte) (n int, err error))
	//   Sum(b []byte) []byte
	//   Reset()
	//   Size() int
	//   BlockSize() int
	// }
	hashIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Sum",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Reset",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, pkg, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
		types.NewFunc(token.NoPos, pkg, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	hashIface.Complete()
	hashType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Hash", nil),
		hashIface, nil)
	scope.Insert(hashType.Obj())

	// type Hash32 interface {
	//   Hash
	//   Sum32() uint32
	// }
	hash32Iface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Sum32",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])),
				false)),
	}, []types.Type{hashType})
	hash32Iface.Complete()
	hash32Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Hash32", nil),
		hash32Iface, nil)
	scope.Insert(hash32Type.Obj())

	// type Hash64 interface {
	//   Hash
	//   Sum64() uint64
	// }
	hash64Iface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Sum64",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])),
				false)),
	}, []types.Type{hashType})
	hash64Iface.Complete()
	hash64Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Hash64", nil),
		hash64Iface, nil)
	scope.Insert(hash64Type.Obj())

	// type Cloner interface { Clone() (Hash, error) } (Go 1.25+)
	clonerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Clone",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", hashType),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	clonerIface.Complete()
	clonerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Cloner", nil),
		clonerIface, nil)
	scope.Insert(clonerType.Obj())

	// type XOF interface (Go 1.25+) — extendable output function
	xofIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Reset",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, pkg, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	xofIface.Complete()
	xofType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "XOF", nil),
		xofIface, nil)
	scope.Insert(xofType.Obj())

	pkg.MarkComplete()
	return pkg
}

// buildIOFSPackage creates the type-checked io/fs package stub.
func buildIOFSPackage() *types.Package {
	pkg := types.NewPackage("io/fs", "fs")
	scope := pkg.Scope()

	// type FileMode uint32
	fileModeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FileMode", nil),
		types.Typ[types.Uint32], nil)
	scope.Insert(fileModeType.Obj())

	errType := types.Universe.Lookup("error").Type()

	// type FileInfo interface { Name() string; Size() int64; Mode() FileMode; ModTime() int64; IsDir() bool; Sys() any }
	fileInfoIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, pkg, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
				false)),
		types.NewFunc(token.NoPos, pkg, "Mode",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", fileModeType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "ModTime",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
				false)),
		types.NewFunc(token.NoPos, pkg, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
				false)),
		types.NewFunc(token.NoPos, pkg, "Sys",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
				false)),
	}, nil)
	fileInfoIface.Complete()
	fileInfoType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FileInfo", nil),
		fileInfoIface, nil)
	scope.Insert(fileInfoType.Obj())

	// type DirEntry interface { Name() string; IsDir() bool; Type() FileMode; Info() (FileInfo, error) }
	dirEntryIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, pkg, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
				false)),
		types.NewFunc(token.NoPos, pkg, "Type",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", fileModeType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Info",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fileInfoType),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	dirEntryIface.Complete()
	dirEntryType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "DirEntry", nil),
		dirEntryIface, nil)
	scope.Insert(dirEntryType.Obj())

	// FileMode constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeDir", fileModeType, constant.MakeUint64(1<<31)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeAppend", fileModeType, constant.MakeUint64(1<<30)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeExclusive", fileModeType, constant.MakeUint64(1<<29)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeTemporary", fileModeType, constant.MakeUint64(1<<28)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeSymlink", fileModeType, constant.MakeUint64(1<<27)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeDevice", fileModeType, constant.MakeUint64(1<<26)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeNamedPipe", fileModeType, constant.MakeUint64(1<<25)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeSocket", fileModeType, constant.MakeUint64(1<<24)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeSetuid", fileModeType, constant.MakeUint64(1<<23)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeSetgid", fileModeType, constant.MakeUint64(1<<22)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeCharDevice", fileModeType, constant.MakeUint64(1<<21)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeSticky", fileModeType, constant.MakeUint64(1<<20)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeIrregular", fileModeType, constant.MakeUint64(1<<19)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModeType", fileModeType, constant.MakeUint64(0xFFFF0000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ModePerm", fileModeType, constant.MakeUint64(0777)))

	// FileMode methods
	fileModeType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsDir",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", fileModeType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	fileModeType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsRegular",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", fileModeType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	fileModeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Perm",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", fileModeType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fileModeType)),
			false)))
	fileModeType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", fileModeType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	fileModeType.AddMethod(types.NewFunc(token.NoPos, pkg, "Type",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", fileModeType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fileModeType)),
			false)))

	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type File interface { Stat() (FileInfo, error); Read([]byte) (int, error); Close() error }
	fileIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Stat",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fileInfoType),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	fileIface.Complete()
	fileType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "File", nil),
		fileIface, nil)
	scope.Insert(fileType.Obj())

	// type ReadDirFile interface { File + ReadDir(n int) ([]DirEntry, error) }
	readDirFileIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ReadDir",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.NewSlice(dirEntryIface)),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, []types.Type{fileType})
	readDirFileIface.Complete()
	readDirFileType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReadDirFile", nil),
		readDirFileIface, nil)
	scope.Insert(readDirFileType.Obj())

	// type FS interface { Open(name string) (File, error) }
	fsIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fileType),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	fsIface.Complete()
	fsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FS", nil),
		fsIface, nil)
	scope.Insert(fsType.Obj())

	// type StatFS interface { FS + Stat(name) (FileInfo, error) }
	statFSIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Stat",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fileInfoType),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, []types.Type{fsType})
	statFSIface.Complete()
	statFSType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "StatFS", nil),
		statFSIface, nil)
	scope.Insert(statFSType.Obj())

	// type ReadFileFS interface { FS + ReadFile(name) ([]byte, error) }
	readFileFSIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ReadFile",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", byteSlice),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, []types.Type{fsType})
	readFileFSIface.Complete()
	readFileFSType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReadFileFS", nil),
		readFileFSIface, nil)
	scope.Insert(readFileFSType.Obj())

	// type ReadDirFS interface { FS + ReadDir(name) ([]DirEntry, error) }
	readDirFSIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ReadDir",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.NewSlice(dirEntryIface)),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, []types.Type{fsType})
	readDirFSIface.Complete()
	readDirFSType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReadDirFS", nil),
		readDirFSIface, nil)
	scope.Insert(readDirFSType.Obj())

	// type GlobFS interface { FS + Glob(pattern) ([]string, error) }
	globFSIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Glob",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "pattern", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, []types.Type{fsType})
	globFSIface.Complete()
	globFSType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "GlobFS", nil),
		globFSIface, nil)
	scope.Insert(globFSType.Obj())

	// type SubFS interface { FS + Sub(dir) (FS, error) }
	subFSIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Sub",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "dir", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fsIface),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, []types.Type{fsType})
	subFSIface.Complete()
	subFSType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SubFS", nil),
		subFSIface, nil)
	scope.Insert(subFSType.Obj())

	// type ReadLinkFS interface { FS + ReadLink(name) (string, error) } (Go 1.25+)
	readLinkFSIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ReadLink",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.String]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, []types.Type{fsType})
	readLinkFSIface.Complete()
	readLinkFSType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReadLinkFS", nil),
		readLinkFSIface, nil)
	scope.Insert(readLinkFSType.Obj())

	// type WalkDirFunc
	walkDirFuncType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WalkDirFunc", nil),
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "d", dirEntryIface),
				types.NewVar(token.NoPos, nil, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false), nil)
	scope.Insert(walkDirFuncType.Obj())

	// type PathError struct
	pathErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Op", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	pathErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PathError", nil),
		pathErrStruct, nil)
	pathErrPtr := types.NewPointer(pathErrType)
	pathErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", pathErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	pathErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", pathErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	scope.Insert(pathErrType.Obj())

	// var ErrNotExist, ErrExist, ErrPermission, ErrInvalid, ErrClosed error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNotExist", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrExist", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrPermission", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrInvalid", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrClosed", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SkipDir", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SkipAll", errType))

	// Package functions
	// func ReadFile(fsys FS, name string) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fsys", fsIface),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ReadDir(fsys FS, name string) ([]DirEntry, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fsys", fsIface),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(dirEntryIface)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Stat(fsys FS, name string) (FileInfo, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Stat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fsys", fsIface),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", fileInfoIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func WalkDir(fsys FS, root string, fn WalkDirFunc) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WalkDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fsys", fsIface),
				types.NewVar(token.NoPos, pkg, "root", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "fn", walkDirFuncType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Sub(fsys FS, dir string) (FS, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sub",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fsys", fsIface),
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", fsIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Glob(fsys FS, pattern string) ([]string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Glob",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fsys", fsIface),
				types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ValidPath(name string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ValidPath",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func FormatFileInfo(info FileInfo) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FormatFileInfo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "info", fileInfoIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func FormatDirEntry(dir DirEntry) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FormatDirEntry",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dir", dirEntryIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func FileInfoToDirEntry(info FileInfo) DirEntry
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FileInfoToDirEntry",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "info", fileInfoIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", dirEntryIface)),
			false)))

	// PathError.Timeout() bool
	pathErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", pathErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildIOUtilPackage creates the type-checked io/ioutil package stub (deprecated).
func buildIOUtilPackage() *types.Package {
	pkg := types.NewPackage("io/ioutil", "ioutil")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// func ReadFile(filename string) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "filename", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func WriteFile(filename string, data []byte, perm uint32) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "filename", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "data", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "perm", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ReadAll(r io.Reader) ([]byte, error)
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	readerType := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerType.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadAll",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func TempDir(dir, pattern string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TempDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// var Discard io.Writer
	writerType := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	writerType.Complete()
	scope.Insert(types.NewVar(token.NoPos, pkg, "Discard", writerType))

	// io.ReadCloser stand-in
	readCloserIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	readCloserIface.Complete()

	// func NopCloser(r io.Reader) io.ReadCloser
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NopCloser",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", readerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", readCloserIface)),
			false)))

	// *os.File stand-in for TempFile return
	osFilePtr := types.NewPointer(types.NewStruct(nil, nil))

	// func TempFile(dir, pattern string) (*os.File, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TempFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", osFilePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// fs.FileInfo stand-in for ReadDir
	fileInfoIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, nil, "Mode",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)),
		types.NewFunc(token.NoPos, nil, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
	}, nil)
	fileInfoIface.Complete()

	// func ReadDir(dirname string) ([]os.FileInfo, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dirname", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(fileInfoIface)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildImageColorPackage() *types.Package {
	pkg := types.NewPackage("image/color", "color")
	scope := pkg.Scope()

	// type RGBA struct { R, G, B, A uint8 }
	rgbaStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "R", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "G", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "B", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint8], false),
	}, nil)
	rgbaType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RGBA", nil),
		rgbaStruct, nil)
	scope.Insert(rgbaType.Obj())

	// type NRGBA struct { R, G, B, A uint8 }
	nrgbaStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "R", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "G", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "B", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint8], false),
	}, nil)
	nrgbaType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NRGBA", nil),
		nrgbaStruct, nil)
	scope.Insert(nrgbaType.Obj())

	// type Gray struct { Y uint8 }
	grayStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Uint8], false),
	}, nil)
	grayType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Gray", nil),
		grayStruct, nil)
	scope.Insert(grayType.Obj())

	// type Alpha struct { A uint8 }
	alphaStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint8], false),
	}, nil)
	alphaType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Alpha", nil),
		alphaStruct, nil)
	scope.Insert(alphaType.Obj())

	// type RGBA64 struct { R, G, B, A uint16 }
	rgba64Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "R", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "G", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "B", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint16], false),
	}, nil)
	rgba64Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RGBA64", nil),
		rgba64Struct, nil)
	scope.Insert(rgba64Type.Obj())

	// Color interface { RGBA() (r, g, b, a uint32) }
	colorIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIface.Complete()
	colorType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Color", nil),
		colorIface, nil)
	scope.Insert(colorType.Obj())

	// Add RGBA() method to concrete color types
	rgbaMethod := types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", rgbaType), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
			false))
	rgbaType.AddMethod(rgbaMethod)
	nrgbaType.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", nrgbaType), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
			false)))
	grayType.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", grayType), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
			false)))
	alphaType.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", alphaType), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
			false)))
	rgba64Type.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", rgba64Type), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
			false)))

	// Model interface { Convert(c Color) Color }
	modelIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Convert",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorType)),
				false)),
	}, nil)
	modelIface.Complete()
	modelType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Model", nil),
		modelIface, nil)
	scope.Insert(modelType.Obj())

	// Model vars
	scope.Insert(types.NewVar(token.NoPos, pkg, "RGBAModel", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "RGBA64Model", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "NRGBAModel", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "GrayModel", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "AlphaModel", modelType))

	// func ModelFunc(f func(Color) Color) Model
	modelFuncSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorType)),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", colorType)),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ModelFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f", modelFuncSig)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", modelType)),
			false)))

	// type NRGBA64 struct { R, G, B, A uint16 }
	nrgba64Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "R", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "G", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "B", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint16], false),
	}, nil)
	nrgba64Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NRGBA64", nil),
		nrgba64Struct, nil)
	scope.Insert(nrgba64Type.Obj())

	// type Gray16 struct { Y uint16 }
	gray16Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Uint16], false),
	}, nil)
	gray16Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Gray16", nil),
		gray16Struct, nil)
	scope.Insert(gray16Type.Obj())

	// type Alpha16 struct { A uint16 }
	alpha16Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint16], false),
	}, nil)
	alpha16Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Alpha16", nil),
		alpha16Struct, nil)
	scope.Insert(alpha16Type.Obj())

	// Add RGBA() method to new color types
	rgbaTuple := types.NewTuple(
		types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
		types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
		types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
		types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32]))
	nrgba64Type.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", nrgba64Type), nil, nil, nil, rgbaTuple, false)))
	gray16Type.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", gray16Type), nil, nil, nil, rgbaTuple, false)))
	alpha16Type.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", alpha16Type), nil, nil, nil, rgbaTuple, false)))

	// type YCbCr struct { Y, Cb, Cr uint8 }
	ycbcrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Cb", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Cr", types.Typ[types.Uint8], false),
	}, nil)
	ycbcrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "YCbCr", nil),
		ycbcrStruct, nil)
	scope.Insert(ycbcrType.Obj())
	ycbcrType.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", ycbcrType), nil, nil, nil, rgbaTuple, false)))

	// type NYCbCrA struct { Y, Cb, Cr, A uint8 }
	nycbcraStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Cb", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Cr", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "A", types.Typ[types.Uint8], false),
	}, nil)
	nycbcraType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NYCbCrA", nil),
		nycbcraStruct, nil)
	scope.Insert(nycbcraType.Obj())
	nycbcraType.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", nycbcraType), nil, nil, nil, rgbaTuple, false)))

	// type CMYK struct { C, M, Y, K uint8 }
	cmykStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "C", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "M", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Uint8], false),
		types.NewField(token.NoPos, pkg, "K", types.Typ[types.Uint8], false),
	}, nil)
	cmykType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CMYK", nil),
		cmykStruct, nil)
	scope.Insert(cmykType.Obj())
	cmykType.AddMethod(types.NewFunc(token.NoPos, pkg, "RGBA",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", cmykType), nil, nil, nil, rgbaTuple, false)))

	// type Palette []Color
	paletteType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Palette", nil),
		types.NewSlice(colorType), nil)
	scope.Insert(paletteType.Obj())
	palRecv := types.NewVar(token.NoPos, nil, "p", paletteType)
	paletteType.AddMethod(types.NewFunc(token.NoPos, pkg, "Convert",
		types.NewSignatureType(palRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", colorType)), false)))
	paletteType.AddMethod(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(palRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// Additional Model vars
	scope.Insert(types.NewVar(token.NoPos, pkg, "NRGBA64Model", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Gray16Model", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Alpha16Model", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "YCbCrModel", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "NYCbCrAModel", modelType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "CMYKModel", modelType))

	// Color conversion functions
	// func RGBToYCbCr(r, g, b uint8) (uint8, uint8, uint8)
	u8Tuple := types.NewTuple(
		types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8]),
		types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8]),
		types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8]))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RGBToYCbCr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "g", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Uint8])),
			u8Tuple, false)))
	// func YCbCrToRGB(y, cb, cr uint8) (uint8, uint8, uint8)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "YCbCrToRGB",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "cb", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "cr", types.Typ[types.Uint8])),
			u8Tuple, false)))
	// func RGBToCMYK(r, g, b uint8) (uint8, uint8, uint8, uint8)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RGBToCMYK",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "g", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Uint8])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint8])), false)))
	// func CMYKToRGB(c, m, y, k uint8) (uint8, uint8, uint8)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CMYKToRGB",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "m", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "y", types.Typ[types.Uint8]),
				types.NewVar(token.NoPos, pkg, "k", types.Typ[types.Uint8])),
			u8Tuple, false)))

	// var White, Black, Transparent, Opaque
	scope.Insert(types.NewVar(token.NoPos, pkg, "White", rgbaType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Black", rgbaType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Transparent", alphaType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "Opaque", alphaType))

	pkg.MarkComplete()
	return pkg
}

func buildImageColorPalettePackage() *types.Package {
	pkg := types.NewPackage("image/color/palette", "palette")
	scope := pkg.Scope()

	// color.Color interface { RGBA() (r, g, b, a uint32) }
	colorIfacePal := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIfacePal.Complete()

	// Palette type = []color.Color
	paletteType := types.NewSlice(colorIfacePal)

	// var Plan9 []color.Color
	scope.Insert(types.NewVar(token.NoPos, pkg, "Plan9", paletteType))
	// var WebSafe []color.Color
	scope.Insert(types.NewVar(token.NoPos, pkg, "WebSafe", paletteType))

	pkg.MarkComplete()
	return pkg
}

func buildImageDrawPackage() *types.Package {
	pkg := types.NewPackage("image/draw", "draw")
	scope := pkg.Scope()

	// type Op int
	opType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Op", nil),
		types.Typ[types.Int], nil)
	scope.Insert(opType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "Over", opType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Src", opType, constant.MakeInt64(1)))


	// image.Rectangle stand-in
	rectStruct := types.NewStruct([]*types.Var{
		types.NewVar(token.NoPos, nil, "Min", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
		types.NewVar(token.NoPos, nil, "Max", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
	}, nil)

	// image.Point stand-in
	pointStruct := types.NewStruct([]*types.Var{
		types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
		types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
	}, nil)

	// color.Color stand-in interface { RGBA() (r, g, b, a uint32) }
	colorIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIface.Complete()

	// color.Model stand-in interface { Convert(c Color) Color }
	colorModelIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Convert",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorIface)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIface)),
				false)),
	}, nil)
	colorModelIface.Complete()

	// image.Image stand-in interface { ColorModel() color.Model; Bounds() Rectangle; At(x, y int) color.Color }
	srcIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelIface)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectStruct)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIface)),
				false)),
	}, nil)
	srcIface.Complete()

	// draw.Image interface — extends image.Image with Set(x, y int, c color.Color)
	imgIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelIface)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectStruct)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIface)),
				false)),
		types.NewFunc(token.NoPos, nil, "Set",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "c", colorIface)),
				nil, false)),
	}, nil)
	imgIface.Complete()
	imgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Image", nil),
		imgIface, nil)
	scope.Insert(imgType.Obj())

	// Drawer interface { Draw(dst Image, r image.Rectangle, src image.Image, sp image.Point) }
	drawerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Draw",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", imgType),
					types.NewVar(token.NoPos, nil, "r", rectStruct),
					types.NewVar(token.NoPos, nil, "src", srcIface),
					types.NewVar(token.NoPos, nil, "sp", pointStruct)),
				nil, false)),
	}, nil)
	drawerIface.Complete()
	drawerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Drawer", nil),
		drawerIface, nil)
	scope.Insert(drawerType.Obj())

	// color.Palette stand-in: []color.Color
	paletteSlice := types.NewSlice(colorIface)

	// Quantizer interface { Quantize(p color.Palette, m image.Image) color.Palette }
	quantizerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Quantize",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", paletteSlice),
					types.NewVar(token.NoPos, nil, "m", srcIface)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", paletteSlice)),
				false)),
	}, nil)
	quantizerIface.Complete()
	quantizerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Quantizer", nil),
		quantizerIface, nil)
	scope.Insert(quantizerType.Obj())

	// var FloydSteinberg Drawer
	scope.Insert(types.NewVar(token.NoPos, pkg, "FloydSteinberg", drawerType))

	// func Draw(dst Image, r Rectangle, src image.Image, sp Point, op Op)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Draw",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", imgType),
				types.NewVar(token.NoPos, pkg, "r", rectStruct),
				types.NewVar(token.NoPos, pkg, "src", srcIface),
				types.NewVar(token.NoPos, pkg, "sp", pointStruct),
				types.NewVar(token.NoPos, pkg, "op", opType)),
			nil, false)))

	// func DrawMask(dst Image, r Rectangle, src image.Image, sp Point, mask image.Image, mp Point, op Op)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DrawMask",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", imgType),
				types.NewVar(token.NoPos, pkg, "r", rectStruct),
				types.NewVar(token.NoPos, pkg, "src", srcIface),
				types.NewVar(token.NoPos, pkg, "sp", pointStruct),
				types.NewVar(token.NoPos, pkg, "mask", srcIface),
				types.NewVar(token.NoPos, pkg, "mp", pointStruct),
				types.NewVar(token.NoPos, pkg, "op", opType)),
			nil, false)))

	// RGBA64Image interface — extends draw.Image with RGBA64At
	// color.RGBA64 stand-in struct
	rgba64Struct := types.NewStruct([]*types.Var{
		types.NewVar(token.NoPos, nil, "R", types.Typ[types.Uint16]),
		types.NewVar(token.NoPos, nil, "G", types.Typ[types.Uint16]),
		types.NewVar(token.NoPos, nil, "B", types.Typ[types.Uint16]),
		types.NewVar(token.NoPos, nil, "A", types.Typ[types.Uint16]),
	}, nil)

	rgba64ImgIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelIface)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectStruct)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIface)),
				false)),
		types.NewFunc(token.NoPos, nil, "Set",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "c", colorIface)),
				nil, false)),
		types.NewFunc(token.NoPos, nil, "SetRGBA64",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "c", rgba64Struct)),
				nil, false)),
		types.NewFunc(token.NoPos, nil, "RGBA64At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rgba64Struct)),
				false)),
	}, nil)
	rgba64ImgIface.Complete()
	rgba64ImgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RGBA64Image", nil),
		rgba64ImgIface, nil)
	scope.Insert(rgba64ImgType.Obj())

	// Op.Draw(dst Image, r image.Rectangle, src image.Image, sp image.Point)
	opType.AddMethod(types.NewFunc(token.NoPos, pkg, "Draw",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "op", opType),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", imgType),
				types.NewVar(token.NoPos, nil, "r", rectStruct),
				types.NewVar(token.NoPos, nil, "src", srcIface),
				types.NewVar(token.NoPos, nil, "sp", pointStruct)),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildImageGIFPackage() *types.Package {
	pkg := types.NewPackage("image/gif", "gif")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// io.Writer interface
	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriter.Complete()

	// image.Image stand-in interface { ColorModel(); Bounds(); At() }
	colorIfaceGIF := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIfaceGIF.Complete()
	colorModelGIF := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Convert",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorIfaceGIF)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfaceGIF)),
				false)),
	}, nil)
	colorModelGIF.Complete()
	rectStructGIF := types.NewStruct([]*types.Var{
		types.NewVar(token.NoPos, nil, "Min", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
		types.NewVar(token.NoPos, nil, "Max", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
	}, nil)
	imageIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelGIF)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectStructGIF)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfaceGIF)),
				false)),
	}, nil)
	imageIface.Complete()

	// type Options struct { NumColors int, Quantizer, Drawer }
	optionsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "NumColors", types.Typ[types.Int], false),
	}, nil)
	optionsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Options", nil),
		optionsStruct, nil)
	scope.Insert(optionsType.Obj())

	// type GIF struct
	gifStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Image", types.NewSlice(imageIface), false),
		types.NewField(token.NoPos, pkg, "Delay", types.NewSlice(types.Typ[types.Int]), false),
		types.NewField(token.NoPos, pkg, "LoopCount", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Disposal", types.NewSlice(types.Typ[types.Byte]), false),
		types.NewField(token.NoPos, pkg, "BackgroundIndex", types.Typ[types.Byte], false),
	}, nil)
	gifType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "GIF", nil),
		gifStruct, nil)
	scope.Insert(gifType.Obj())
	gifPtr := types.NewPointer(gifType)

	// func Decode(r io.Reader) (image.Image, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DecodeAll(r io.Reader) (*GIF, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeAll",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", gifPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DecodeConfig(r io.Reader) (image.Config, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeConfig",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Encode(w io.Writer, m image.Image, o *Options) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "m", imageIface),
				types.NewVar(token.NoPos, pkg, "o", types.NewPointer(optionsType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func EncodeAll(w io.Writer, g *GIF) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EncodeAll",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "g", gifPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Disposal constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "DisposalNone", types.Typ[types.Byte], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DisposalBackground", types.Typ[types.Byte], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DisposalPrevious", types.Typ[types.Byte], constant.MakeInt64(3)))

	pkg.MarkComplete()
	return pkg
}

func buildImageJPEGPackage() *types.Package {
	pkg := types.NewPackage("image/jpeg", "jpeg")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriter.Complete()
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// image.Image stand-in interface { ColorModel(); Bounds(); At() }
	colorIfaceJPG := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIfaceJPG.Complete()
	colorModelJPG := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Convert",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorIfaceJPG)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfaceJPG)),
				false)),
	}, nil)
	colorModelJPG.Complete()
	rectStructJPG := types.NewStruct([]*types.Var{
		types.NewVar(token.NoPos, nil, "Min", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
		types.NewVar(token.NoPos, nil, "Max", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
	}, nil)
	imageIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelJPG)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectStructJPG)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfaceJPG)),
				false)),
	}, nil)
	imageIface.Complete()

	// type Options struct { Quality int }
	optionsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Quality", types.Typ[types.Int], false),
	}, nil)
	optionsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Options", nil),
		optionsStruct, nil)
	scope.Insert(optionsType.Obj())

	// type FormatError string
	formatErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FormatError", nil),
		types.Typ[types.String], nil)
	formatErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", formatErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(formatErrType.Obj())

	// type UnsupportedError string
	unsupportedErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnsupportedError", nil),
		types.Typ[types.String], nil)
	unsupportedErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unsupportedErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unsupportedErrType.Obj())

	// func Encode(w io.Writer, m image.Image, o *Options) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "m", imageIface),
				types.NewVar(token.NoPos, pkg, "o", types.NewPointer(optionsType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Decode(r io.Reader) (image.Image, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DecodeConfig(r io.Reader) (image.Config, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeConfig",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultQuality", types.Typ[types.Int], constant.MakeInt64(75)))

	pkg.MarkComplete()
	return pkg
}

func buildImagePNGPackage() *types.Package {
	pkg := types.NewPackage("image/png", "png")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriter.Complete()
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// image.Image stand-in interface { ColorModel() color.Model; Bounds() Rectangle; At(x, y int) color.Color }
	colorIfacePNG := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIfacePNG.Complete()
	colorModelPNG := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Convert",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorIfacePNG)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfacePNG)),
				false)),
	}, nil)
	colorModelPNG.Complete()
	rectStructPNG := types.NewStruct([]*types.Var{
		types.NewVar(token.NoPos, nil, "Min", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
		types.NewVar(token.NoPos, nil, "Max", types.NewStruct([]*types.Var{
			types.NewVar(token.NoPos, nil, "X", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "Y", types.Typ[types.Int]),
		}, nil)),
	}, nil)
	imageIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelPNG)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectStructPNG)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfacePNG)),
				false)),
	}, nil)
	imageIface.Complete()

	// type CompressionLevel int
	compType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CompressionLevel", nil),
		types.Typ[types.Int], nil)
	scope.Insert(compType.Obj())

	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultCompression", compType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NoCompression", compType, constant.MakeInt64(-1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BestSpeed", compType, constant.MakeInt64(-2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BestCompression", compType, constant.MakeInt64(-3)))

	// type Encoder struct { CompressionLevel CompressionLevel }
	encoderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "CompressionLevel", compType, false),
	}, nil)
	encoderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Encoder", nil),
		encoderStruct, nil)
	scope.Insert(encoderType.Obj())
	encoderPtr := types.NewPointer(encoderType)

	// func (enc *Encoder) Encode(w io.Writer, m image.Image) error
	encoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "enc", encoderPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "m", imageIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type FormatError string
	formatErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FormatError", nil),
		types.Typ[types.String], nil)
	formatErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", formatErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(formatErrType.Obj())

	// type UnsupportedError string
	unsupportedErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnsupportedError", nil),
		types.Typ[types.String], nil)
	unsupportedErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unsupportedErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unsupportedErrType.Obj())

	// func Encode(w io.Writer, m image.Image) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "m", imageIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Decode(r io.Reader) (image.Image, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DecodeConfig(r io.Reader) (image.Config, error)
	configStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Width", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Height", types.Typ[types.Int], false),
	}, nil)
	configType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Config", nil),
		configStruct, nil)
	_ = configType
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeConfig",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildImagePackage() *types.Package {
	pkg := types.NewPackage("image", "image")
	scope := pkg.Scope()

	// type Point struct { X, Y int }
	pointStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "X", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Y", types.Typ[types.Int], false),
	}, nil)
	pointType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Point", nil),
		pointStruct, nil)
	scope.Insert(pointType.Obj())

	// func Pt(X, Y int) Point
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "X", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "Y", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointType)),
			false)))

	// type Rectangle struct { Min, Max Point }
	rectStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Min", pointType, false),
		types.NewField(token.NoPos, pkg, "Max", pointType, false),
	}, nil)
	rectType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Rectangle", nil),
		rectStruct, nil)
	scope.Insert(rectType.Obj())

	// func Rect(x0, y0, x1, y1 int) Rectangle
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Rect",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x0", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "y0", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "x1", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "y1", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))

	// Forward-declare Image type (will be set to real interface after all structs are defined)
	imageType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Image", nil),
		types.NewInterfaceType(nil, nil), nil)

	// type RGBA struct
	rgbaStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", types.NewSlice(types.Typ[types.Uint8]), false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	rgbaType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RGBA", nil),
		rgbaStruct, nil)
	scope.Insert(rgbaType.Obj())

	// func NewRGBA(r Rectangle) *RGBA
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRGBA",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(rgbaType))),
			false)))

	rgbaPtr := types.NewPointer(rgbaType)

	// color.Color stand-in interface (defined early for use in At/Set methods)
	colorIfaceLocal := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIfaceLocal.Complete()

	// Helper to add standard image type methods
	addImageMethods := func(imgType *types.Named, imgPtr *types.Pointer) {
		imgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bounds",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", imgPtr),
				nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
				false)))
		imgType.AddMethod(types.NewFunc(token.NoPos, pkg, "At",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", imgPtr),
				nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIfaceLocal)),
				false)))
		imgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", imgPtr),
				nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "c", colorIfaceLocal)),
				nil, false)))
		imgType.AddMethod(types.NewFunc(token.NoPos, pkg, "SubImage",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", imgPtr),
				nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", imageType)),
				false)))
		imgType.AddMethod(types.NewFunc(token.NoPos, pkg, "PixOffset",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", imgPtr),
				nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)))
		imgType.AddMethod(types.NewFunc(token.NoPos, pkg, "Opaque",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", imgPtr),
				nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
				false)))
	}

	// RGBA methods
	addImageMethods(rgbaType, rgbaPtr)

	pixSlice := types.NewSlice(types.Typ[types.Uint8])

	// type NRGBA struct { Pix, Stride, Rect }
	nrgbaStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	nrgbaType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NRGBA", nil),
		nrgbaStruct, nil)
	scope.Insert(nrgbaType.Obj())
	nrgbaPtr := types.NewPointer(nrgbaType)
	addImageMethods(nrgbaType, nrgbaPtr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewNRGBA",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", nrgbaPtr)),
			false)))

	// type Gray struct
	grayStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	grayType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Gray", nil),
		grayStruct, nil)
	scope.Insert(grayType.Obj())
	grayPtr := types.NewPointer(grayType)
	addImageMethods(grayType, grayPtr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewGray",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", grayPtr)),
			false)))

	// type Alpha struct
	alphaStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	alphaType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Alpha", nil),
		alphaStruct, nil)
	scope.Insert(alphaType.Obj())
	alphaPtr := types.NewPointer(alphaType)
	addImageMethods(alphaType, alphaPtr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewAlpha",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", alphaPtr)),
			false)))

	// type RGBA64 struct { Pix, Stride, Rect }
	rgba64Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	rgba64Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RGBA64", nil),
		rgba64Struct, nil)
	scope.Insert(rgba64Type.Obj())
	rgba64Ptr := types.NewPointer(rgba64Type)
	addImageMethods(rgba64Type, rgba64Ptr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRGBA64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rgba64Ptr)),
			false)))

	// type NRGBA64 struct { Pix, Stride, Rect }
	nrgba64Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	nrgba64Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NRGBA64", nil),
		nrgba64Struct, nil)
	scope.Insert(nrgba64Type.Obj())
	nrgba64Ptr := types.NewPointer(nrgba64Type)
	addImageMethods(nrgba64Type, nrgba64Ptr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewNRGBA64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", nrgba64Ptr)),
			false)))

	// type Gray16 struct { Pix, Stride, Rect }
	gray16Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
	}, nil)
	gray16Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Gray16", nil),
		gray16Struct, nil)
	scope.Insert(gray16Type.Obj())
	gray16Ptr := types.NewPointer(gray16Type)
	addImageMethods(gray16Type, gray16Ptr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewGray16",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", gray16Ptr)),
			false)))

	// type Paletted struct { Pix, Stride, Rect, Palette }
	palettedStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Pix", pixSlice, false),
		types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Rect", rectType, false),
		types.NewField(token.NoPos, pkg, "Palette", types.NewSlice(colorIfaceLocal), false),
	}, nil)
	palettedType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Paletted", nil),
		palettedStruct, nil)
	scope.Insert(palettedType.Obj())
	palettedPtr := types.NewPointer(palettedType)
	addImageMethods(palettedType, palettedPtr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewPaletted",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", rectType),
				types.NewVar(token.NoPos, pkg, "p", types.NewSlice(colorIfaceLocal))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", palettedPtr)),
			false)))

	// color.Color interface — RGBA() (r, g, b, a uint32)
	colorIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "RGBA",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "g", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "b", types.Typ[types.Uint32]),
					types.NewVar(token.NoPos, nil, "a", types.Typ[types.Uint32])),
				false)),
	}, nil)
	colorIface.Complete()

	// color.Model interface
	colorModelIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Convert",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "c", colorIface)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIface)),
				false)),
	}, nil)
	colorModelIface.Complete()

	// type Uniform struct { C color.Color }
	uniformStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "C", colorIface, false),
	}, nil)
	uniformType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Uniform", nil),
		uniformStruct, nil)
	scope.Insert(uniformType.Obj())

	// func NewUniform(c color.Color) *Uniform
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewUniform",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "c", colorIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(uniformType))),
			false)))

	// type Config struct { ColorModel color.Model, Width int, Height int }
	configStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ColorModel", colorModelIface, false),
		types.NewField(token.NoPos, pkg, "Width", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Height", types.Typ[types.Int], false),
	}, nil)
	configType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Config", nil),
		configStruct, nil)
	scope.Insert(configType.Obj())

	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// Image interface
	imageIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ColorModel",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorModelIface)),
				false)),
		types.NewFunc(token.NoPos, nil, "Bounds",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", rectType)),
				false)),
		types.NewFunc(token.NoPos, nil, "At",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "y", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", colorIface)),
				false)),
	}, nil)
	imageIface.Complete()
	imageType.SetUnderlying(imageIface)
	scope.Insert(imageType.Obj())

	// func DecodeConfig(r io.Reader) (Config, string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeConfig",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", configType),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Decode(r io.Reader) (Image, string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", imageIface),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// decode func type: func(io.Reader) (Image, error)
	decodeFuncType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "r", ioReader)),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", imageIface),
			types.NewVar(token.NoPos, nil, "", errType)),
		false)
	// decodeConfig func type: func(io.Reader) (Config, error)
	decodeConfigFuncType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "r", ioReader)),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", configType),
			types.NewVar(token.NoPos, nil, "", errType)),
		false)

	// func RegisterFormat(name, magic string, decode func(io.Reader)(Image, error), decodeConfig func(io.Reader)(Config, error))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RegisterFormat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "magic", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "decode", decodeFuncType),
				types.NewVar(token.NoPos, pkg, "decodeConfig", decodeConfigFuncType)),
			nil, false)))

	// Point methods
	pointPtr := types.NewPointer(pointType)
	_ = pointPtr
	// func (p Point) Add(q Point) Point
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "q", pointType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointType)),
			false)))
	// func (p Point) Sub(q Point) Point
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sub",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "q", pointType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointType)),
			false)))
	// func (p Point) Mul(k int) Point
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "Mul",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "k", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointType)),
			false)))
	// func (p Point) Div(k int) Point
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "Div",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "k", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointType)),
			false)))
	// func (p Point) In(r Rectangle) bool
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "In",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	// func (p Point) Eq(q Point) bool
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "Eq",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "q", pointType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	// func (p Point) String() string
	pointType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", pointType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Rectangle methods
	// func (r Rectangle) Dx() int
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Dx",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	// func (r Rectangle) Dy() int
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Dy",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	// func (r Rectangle) Size() Point
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", pointType)),
			false)))
	// func (r Rectangle) Empty() bool
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Empty",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	// func (r Rectangle) Eq(s Rectangle) bool
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Eq",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	// func (r Rectangle) Overlaps(s Rectangle) bool
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Overlaps",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	// func (r Rectangle) In(s Rectangle) bool
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "In",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	// func (r Rectangle) Intersect(s Rectangle) Rectangle
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Intersect",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))
	// func (r Rectangle) Union(s Rectangle) Rectangle
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Union",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", rectType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))
	// func (r Rectangle) Add(p Point) Rectangle
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", pointType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))
	// func (r Rectangle) Sub(p Point) Rectangle
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sub",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", pointType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))
	// func (r Rectangle) Inset(n int) Rectangle
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Inset",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))
	// func (r Rectangle) Canon() Rectangle
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "Canon",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rectType)),
			false)))
	// func (r Rectangle) String() string
	rectType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rectType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// var ZP Point (deprecated but still used)
	scope.Insert(types.NewVar(token.NoPos, pkg, "ZP", pointType))
	// var ZR Rectangle (deprecated but still used)
	scope.Insert(types.NewVar(token.NoPos, pkg, "ZR", rectType))

	pkg.MarkComplete()
	return pkg
}

func buildIndexSuffixarrayPackage() *types.Package {
	pkg := types.NewPackage("index/suffixarray", "suffixarray")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type Index struct (opaque)
	indexType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Index", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(indexType.Obj())
	indexPtr := types.NewPointer(indexType)
	indexRecv := types.NewVar(token.NoPos, nil, "x", indexPtr)

	// func New(data []byte) *Index
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", indexPtr)),
			false)))

	// Index.Bytes() int
	indexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(indexRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// Index.Lookup(s []byte, n int) []int
	indexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(indexRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "s", byteSlice),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Int]))), false)))

	// Index.FindAllIndex(r *regexp.Regexp, n int) [][]int
	// *regexp.Regexp stand-in as opaque struct pointer
	regexpPtr := types.NewPointer(types.NewStruct(nil, nil))
	indexType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindAllIndex",
		types.NewSignatureType(indexRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "r", regexpPtr),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.NewSlice(types.Typ[types.Int])))), false)))

	// io.Reader interface for Index.Read
	ioReaderSA := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderSA.Complete()

	// io.Writer interface for Index.Write
	ioWriterSA := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterSA.Complete()

	// Index.Read/Write
	indexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(indexRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", ioReaderSA)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	indexType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(indexRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", ioWriterSA)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	pkg.MarkComplete()
	return pkg
}

func buildIterPackage() *types.Package {
	pkg := types.NewPackage("iter", "iter")
	scope := pkg.Scope()

	// type Seq[V any] func(yield func(V) bool) — simplified as func(func(int) bool)
	seqType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Seq", nil),
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "yield",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
					types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
					false))),
			nil, false), nil)
	scope.Insert(seqType.Obj())

	// type Seq2[K, V any] func(yield func(K, V) bool) — simplified as func(func(int, int) bool)
	seq2Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Seq2", nil),
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "yield",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
						types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
					types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
					false))),
			nil, false), nil)
	scope.Insert(seq2Type.Obj())

	// func Pull[V any](seq Seq[V]) (next func() (V, bool), stop func()) — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pull",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seq", seqType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "next",
					types.NewSignatureType(nil, nil, nil, nil,
						types.NewTuple(
							types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
							types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
						false)),
				types.NewVar(token.NoPos, pkg, "stop",
					types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			false)))

	// func Pull2[K, V any](seq Seq2[K, V]) (next func() (K, V, bool), stop func()) — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pull2",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seq", seq2Type)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "next",
					types.NewSignatureType(nil, nil, nil, nil,
						types.NewTuple(
							types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
							types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
							types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
						false)),
				types.NewVar(token.NoPos, pkg, "stop",
					types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildLogSlogPackage creates the type-checked log/slog package stub.
func buildLogSlogPackage() *types.Package {
	pkg := types.NewPackage("log/slog", "slog")
	scope := pkg.Scope()

	anySlice := types.NewSlice(types.NewInterfaceType(nil, nil))

	// func Info(msg string, args ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Info",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "msg", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", anySlice)),
			nil, true)))

	// func Warn(msg string, args ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Warn",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "msg", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", anySlice)),
			nil, true)))

	// func Error(msg string, args ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "msg", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", anySlice)),
			nil, true)))

	// func Debug(msg string, args ...any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Debug",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "msg", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", anySlice)),
			nil, true)))

	// type Level int
	levelType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Level", nil),
		types.Typ[types.Int], nil)
	scope.Insert(levelType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelDebug", levelType, constant.MakeInt64(-4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelInfo", levelType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelWarn", levelType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelError", levelType, constant.MakeInt64(8)))

	// Level methods
	levelType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", levelType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// type Value struct (simplified)
	valueStruct := types.NewStruct(nil, nil)
	valueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Value", nil),
		valueStruct, nil)
	scope.Insert(valueType.Obj())
	valRecv := types.NewVar(token.NoPos, nil, "v", valueType)
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(valRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Any",
		types.NewSignatureType(valRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int64",
		types.NewSignatureType(valRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bool",
		types.NewSignatureType(valRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// type Attr struct { Key string; Value Value }
	attrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Key", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", valueType, false),
	}, nil)
	attrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Attr", nil),
		attrStruct, nil)
	scope.Insert(attrType.Obj())
	attrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "a", attrType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", attrType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// type Record struct (simplified)
	errTypeSlog := types.Universe.Lookup("error").Type()
	recordStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Message", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Level", levelType, false),
	}, nil)
	recordType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Record", nil),
		recordStruct, nil)
	scope.Insert(recordType.Obj())

	// context.Context stand-in for Handler and Logger methods
	ctxForHandler := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Deadline",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Done",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewChan(types.RecvOnly, types.NewStruct(nil, nil)))), false)),
		types.NewFunc(token.NoPos, nil, "Err",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errTypeSlog)), false)),
		types.NewFunc(token.NoPos, nil, "Value",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.NewInterfaceType(nil, nil))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)),
	}, nil)
	ctxForHandler.Complete()
	handlerIface := types.NewInterfaceType(nil, nil) // forward decl
	handlerIface.Complete()
	handlerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Handler", nil),
		handlerIface, nil)

	// Now create the real interface with methods that reference handlerType
	attrSlice := types.NewSlice(attrType)
	handlerIfaceReal := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Enabled",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "ctx", ctxForHandler),
					types.NewVar(token.NoPos, nil, "level", levelType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Handle",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "ctx", ctxForHandler),
					types.NewVar(token.NoPos, nil, "r", recordType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errTypeSlog)), false)),
		types.NewFunc(token.NoPos, pkg, "WithAttrs",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "attrs", attrSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", handlerType)), false)),
		types.NewFunc(token.NoPos, pkg, "WithGroup",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", handlerType)), false)),
	}, nil)
	handlerIfaceReal.Complete()
	handlerType.SetUnderlying(handlerIfaceReal)
	scope.Insert(handlerType.Obj())

	// type Logger struct
	loggerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "handler", handlerIfaceReal, false),
	}, nil)
	loggerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Logger", nil),
		loggerStruct, nil)
	scope.Insert(loggerType.Obj())
	loggerPtr := types.NewPointer(loggerType)

	// Logger methods
	logRecv := types.NewVar(token.NoPos, nil, "l", loggerPtr)
	for _, mname := range []string{"Info", "Warn", "Error", "Debug"} {
		loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, mname,
			types.NewSignatureType(logRecv, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, pkg, "msg", types.Typ[types.String]),
					types.NewVar(token.NoPos, pkg, "args", anySlice)),
				nil, true)))
	}
	for _, mname := range []string{"InfoContext", "WarnContext", "ErrorContext", "DebugContext"} {
		loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, mname,
			types.NewSignatureType(logRecv, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, pkg, "ctx", ctxForHandler),
					types.NewVar(token.NoPos, pkg, "msg", types.Typ[types.String]),
					types.NewVar(token.NoPos, pkg, "args", anySlice)),
				nil, true)))
	}
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "With",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", loggerPtr)),
			true)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "WithGroup",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", loggerPtr)),
			false)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Enabled",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxForHandler),
				types.NewVar(token.NoPos, pkg, "level", levelType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Handler",
		types.NewSignatureType(logRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handlerType)),
			false)))

	// Package-level functions
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "h", handlerIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", loggerPtr)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Default",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", loggerPtr)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetDefault",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "l", loggerPtr)),
			nil, false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "With",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", loggerPtr)),
			true)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Group",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", attrType)),
			true)))

	// Attr constructors
	scope.Insert(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", attrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", attrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", attrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", attrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Bool",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", attrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Any",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", attrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Duration",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", attrType)),
			false)))

	// type HandlerOptions struct
	handlerOptsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "AddSource", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Level", levelType, false),
		types.NewField(token.NoPos, pkg, "ReplaceAttr", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "groups", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "a", attrType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", attrType)),
			false), false),
	}, nil)
	handlerOptsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "HandlerOptions", nil),
		handlerOptsStruct, nil)
	scope.Insert(handlerOptsType.Obj())
	handlerOptsPtr := types.NewPointer(handlerOptsType)

	// io.Writer interface for handler constructors
	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errTypeSlog)),
				false)),
	}, nil)
	ioWriter.Complete()

	// Handler implementations
	// type TextHandler struct
	textHandlerStruct := types.NewStruct(nil, nil)
	textHandlerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "TextHandler", nil),
		textHandlerStruct, nil)
	scope.Insert(textHandlerType.Obj())
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTextHandler",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "opts", handlerOptsPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(textHandlerType))),
			false)))

	// type JSONHandler struct
	jsonHandlerStruct := types.NewStruct(nil, nil)
	jsonHandlerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "JSONHandler", nil),
		jsonHandlerStruct, nil)
	scope.Insert(jsonHandlerType.Obj())
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewJSONHandler",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "opts", handlerOptsPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(jsonHandlerType))),
			false)))

	// type LevelVar struct
	levelVarStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "val", types.Typ[types.Int64], false),
	}, nil)
	levelVarType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "LevelVar", nil),
		levelVarStruct, nil)
	scope.Insert(levelVarType.Obj())
	lvRecv := types.NewVar(token.NoPos, nil, "v", types.NewPointer(levelVarType))
	levelVarType.AddMethod(types.NewFunc(token.NoPos, pkg, "Level",
		types.NewSignatureType(lvRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", levelType)),
			false)))
	levelVarType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(lvRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "l", levelType)),
			nil, false)))
	levelVarType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(lvRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	levelVarType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(lvRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errTypeSlog)),
			false)))
	levelVarType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(lvRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errTypeSlog)),
			false)))

	// ---- Kind type ----
	kindType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Kind", nil),
		types.Typ[types.Int], nil)
	scope.Insert(kindType.Obj())
	kindType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", kindType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KindAny", kindType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KindBool", kindType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KindDuration", kindType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KindFloat64", kindType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KindInt64", kindType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KindString", kindType, constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KindTime", kindType, constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KindUint64", kindType, constant.MakeInt64(7)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KindGroup", kindType, constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "KindLogValuer", kindType, constant.MakeInt64(9)))

	// ---- Additional Value methods ----
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(valRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(valRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Duration",
		types.NewSignatureType(valRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Time",
		types.NewSignatureType(valRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Group",
		types.NewSignatureType(valRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(attrType))), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Kind",
		types.NewSignatureType(valRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", kindType)), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(valRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Resolve",
		types.NewSignatureType(valRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "LogValuer",
		types.NewSignatureType(valRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)))

	// ---- Value constructor functions ----
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StringValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IntValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Int64Value",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Float64Value",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BoolValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TimeValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DurationValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint64Value",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GroupValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "as", types.NewSlice(attrType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)), true)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AnyValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)), false)))

	// ---- Attr.String() method ----
	attrType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "a", attrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// ---- Record additional fields and methods ----
	recordRecv := types.NewVar(token.NoPos, nil, "r", types.NewPointer(recordType))
	recordType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(recordRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "attrs", types.NewSlice(attrType))),
			nil, true)))
	recordType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumAttrs",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", recordType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	recordType.AddMethod(types.NewFunc(token.NoPos, pkg, "Attrs",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", recordType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f", types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "a", attrType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false))),
			nil, false)))
	recordType.AddMethod(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", recordType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", recordType)), false)))
	recordType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddAttrs",
		types.NewSignatureType(recordRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "attrs", types.NewSlice(attrType))),
			nil, true)))

	// Record.Time, Record.Level, Record.Message are already struct fields

	// ---- Level additional methods ----
	levelRecv := types.NewVar(token.NoPos, nil, "l", levelType)
	levelType.AddMethod(types.NewFunc(token.NoPos, pkg, "Level",
		types.NewSignatureType(levelRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", levelType)), false)))
	levelType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalJSON",
		types.NewSignatureType(levelRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errTypeSlog)), false)))
	levelType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(levelRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, nil, "", errTypeSlog)), false)))
	levelPtrRecv := types.NewVar(token.NoPos, nil, "l", types.NewPointer(levelType))
	levelType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalJSON",
		types.NewSignatureType(levelPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errTypeSlog)), false)))
	levelType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(levelPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "data", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errTypeSlog)), false)))

	// ---- Logger additional methods ----
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Log",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxForHandler),
				types.NewVar(token.NoPos, nil, "level", levelType),
				types.NewVar(token.NoPos, nil, "msg", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anySlice)),
			nil, true)))
	loggerType.AddMethod(types.NewFunc(token.NoPos, pkg, "LogAttrs",
		types.NewSignatureType(logRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxForHandler),
				types.NewVar(token.NoPos, nil, "level", levelType),
				types.NewVar(token.NoPos, nil, "msg", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "attrs", types.NewSlice(attrType))),
			nil, true)))

	// ---- Package-level context functions ----
	for _, fname := range []string{"InfoContext", "WarnContext", "ErrorContext", "DebugContext"} {
		scope.Insert(types.NewFunc(token.NoPos, pkg, fname,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "ctx", ctxForHandler),
					types.NewVar(token.NoPos, nil, "msg", types.Typ[types.String]),
					types.NewVar(token.NoPos, nil, "args", anySlice)),
				nil, true)))
	}
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Log",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxForHandler),
				types.NewVar(token.NoPos, nil, "level", levelType),
				types.NewVar(token.NoPos, nil, "msg", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anySlice)),
			nil, true)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LogAttrs",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxForHandler),
				types.NewVar(token.NoPos, nil, "level", levelType),
				types.NewVar(token.NoPos, nil, "msg", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "attrs", types.NewSlice(attrType))),
			nil, true)))

	// ---- LogValuer interface ----
	logValuerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "LogValue",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)), false)),
	}, nil)
	logValuerIface.Complete()
	logValuerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "LogValuer", nil),
		logValuerIface, nil)
	scope.Insert(logValuerType.Obj())

	// ---- Time attr constructor ----
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Time",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "v", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", attrType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "v", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", attrType)), false)))

	// func NewRecord(t time.Time, level Level, msg string, pc uintptr) Record
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRecord",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "level", levelType),
				types.NewVar(token.NoPos, nil, "msg", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "pc", types.Typ[types.Uintptr])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", recordType)), false)))

	// ---- TextHandler and JSONHandler need Handler interface methods ----
	textHandlerPtrRecv := types.NewVar(token.NoPos, nil, "h", types.NewPointer(textHandlerType))
	textHandlerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Enabled",
		types.NewSignatureType(textHandlerPtrRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxForHandler),
				types.NewVar(token.NoPos, nil, "level", levelType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	textHandlerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Handle",
		types.NewSignatureType(textHandlerPtrRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxForHandler),
				types.NewVar(token.NoPos, nil, "r", recordType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errTypeSlog)), false)))
	textHandlerType.AddMethod(types.NewFunc(token.NoPos, pkg, "WithAttrs",
		types.NewSignatureType(textHandlerPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "attrs", attrSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", handlerType)), false)))
	textHandlerType.AddMethod(types.NewFunc(token.NoPos, pkg, "WithGroup",
		types.NewSignatureType(textHandlerPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", handlerType)), false)))

	jsonHandlerPtrRecv := types.NewVar(token.NoPos, nil, "h", types.NewPointer(jsonHandlerType))
	jsonHandlerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Enabled",
		types.NewSignatureType(jsonHandlerPtrRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxForHandler),
				types.NewVar(token.NoPos, nil, "level", levelType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	jsonHandlerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Handle",
		types.NewSignatureType(jsonHandlerPtrRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxForHandler),
				types.NewVar(token.NoPos, nil, "r", recordType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errTypeSlog)), false)))
	jsonHandlerType.AddMethod(types.NewFunc(token.NoPos, pkg, "WithAttrs",
		types.NewSignatureType(jsonHandlerPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "attrs", attrSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", handlerType)), false)))
	jsonHandlerType.AddMethod(types.NewFunc(token.NoPos, pkg, "WithGroup",
		types.NewSignatureType(jsonHandlerPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", handlerType)), false)))

	// ---- Default key constants ----
	scope.Insert(types.NewConst(token.NoPos, pkg, "TimeKey", types.Typ[types.String], constant.MakeString("time")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelKey", types.Typ[types.String], constant.MakeString("level")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MessageKey", types.Typ[types.String], constant.MakeString("msg")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SourceKey", types.Typ[types.String], constant.MakeString("source")))

	// type Leveler interface { Level() Level }
	levelerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Level",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", levelType)), false)),
	}, nil)
	levelerIface.Complete()
	levelerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Leveler", nil),
		levelerIface, nil)
	scope.Insert(levelerType.Obj())

	// type Source struct { Function string; File string; Line int }
	sourceStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Function", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "File", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
	}, nil)
	sourceType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Source", nil),
		sourceStruct, nil)
	scope.Insert(sourceType.Obj())

	// func SetLogLoggerLevel(level Level) Level — Go 1.22+
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetLogLoggerLevel",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "level", levelType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", levelType)),
			false)))

	// func NewLogLogger(h Handler, level Level) *log.Logger — return *log.Logger as opaque
	logLoggerPtr := types.NewPointer(types.NewStruct(nil, nil))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewLogLogger",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "h", handlerType),
				types.NewVar(token.NoPos, nil, "level", levelType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", logLoggerPtr)),
			false)))

	_ = levelerType

	// var DiscardHandler Handler (Go 1.24+)
	scope.Insert(types.NewVar(token.NoPos, pkg, "DiscardHandler", handlerType))

	pkg.MarkComplete()
	return pkg
}

func buildLogSyslogPackage() *types.Package {
	pkg := types.NewPackage("log/syslog", "syslog")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())

	// func New(priority Priority, tag string) (*Writer, error) — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "priority", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "tag", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(writerType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type Priority int
	priorityType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Priority", nil),
		types.Typ[types.Int], nil)
	scope.Insert(priorityType.Obj())

	// Priority constants - severity
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_EMERG", priorityType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_ALERT", priorityType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_CRIT", priorityType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_ERR", priorityType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_WARNING", priorityType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_NOTICE", priorityType, constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_INFO", priorityType, constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_DEBUG", priorityType, constant.MakeInt64(7)))

	// Priority constants - facility
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_KERN", priorityType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_USER", priorityType, constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_MAIL", priorityType, constant.MakeInt64(16)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_DAEMON", priorityType, constant.MakeInt64(24)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_AUTH", priorityType, constant.MakeInt64(32)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_SYSLOG", priorityType, constant.MakeInt64(40)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_LOCAL0", priorityType, constant.MakeInt64(128)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LOG_LOCAL7", priorityType, constant.MakeInt64(184)))

	// func Dial(network, raddr string, priority Priority, tag string) (*Writer, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "raddr", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "priority", priorityType),
				types.NewVar(token.NoPos, pkg, "tag", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(writerType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Writer methods
	writerPtr := types.NewPointer(writerType)

	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	for _, name := range []string{"Emerg", "Alert", "Crit", "Err", "Warning", "Notice", "Info", "Debug"} {
		writerType.AddMethod(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
				nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "m", types.Typ[types.String])),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
				false)))
	}

	pkg.MarkComplete()
	return pkg
}

// buildMIMEMultipartPackage creates the type-checked mime/multipart package stub.
func buildMIMEMultipartPackage() *types.Package {
	pkg := types.NewPackage("mime/multipart", "multipart")
	scope := pkg.Scope()

	errTypeMp := types.Universe.Lookup("error").Type()
	byteSliceMp := types.NewSlice(types.Typ[types.Byte])

	// io.Writer interface { Write(p []byte) (n int, err error) }
	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceMp)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errTypeMp)),
				false)),
	}, nil)
	ioWriter.Complete()
	// io.Reader interface { Read(p []byte) (n int, err error) }
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceMp)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errTypeMp)),
				false)),
	}, nil)
	ioReader.Complete()

	writerStruct := types.NewStruct(nil, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())

	// func NewWriter(w io.Writer) *Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriter)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(writerType))),
			false)))

	readerStruct := types.NewStruct(nil, nil)
	readerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		readerStruct, nil)
	scope.Insert(readerType.Obj())

	// func NewReader(r io.Reader, boundary string) *Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", ioReader),
				types.NewVar(token.NoPos, pkg, "boundary", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(readerType))),
			false)))

	errType := types.Universe.Lookup("error").Type()
	writerPtr := types.NewPointer(writerType)
	readerPtr := types.NewPointer(readerType)
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	strSlice := types.NewSlice(types.Typ[types.String])

	// Writer methods
	// func (w *Writer) Boundary() string
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Boundary",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))
	// func (w *Writer) SetBoundary(boundary string) error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetBoundary",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "boundary", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	// func (w *Writer) FormDataContentType() string
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "FormDataContentType",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))
	// MIMEHeader stand-in (map[string][]string)
	mimeHeader := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))

	// func (w *Writer) CreatePart(header textproto.MIMEHeader) (io.Writer, error)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "CreatePart",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "header", mimeHeader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ioWriter),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	// func (w *Writer) CreateFormFile(fieldname, filename string) (io.Writer, error)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "CreateFormFile",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fieldname", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "filename", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ioWriter),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	// func (w *Writer) CreateFormField(fieldname string) (io.Writer, error)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "CreateFormField",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fieldname", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ioWriter),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	// func (w *Writer) WriteField(fieldname, value string) error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteField",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fieldname", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	// func (w *Writer) Close() error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "w", writerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type Part struct { Header textproto.MIMEHeader }
	partStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Header", mimeHeader, false),
	}, nil)
	partType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Part", nil),
		partStruct, nil)
	scope.Insert(partType.Obj())
	partPtr := types.NewPointer(partType)

	// func (p *Part) Read(d []byte) (n int, err error)
	partType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", partPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "d", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))
	// func (p *Part) Close() error
	partType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", partPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	// func (p *Part) FileName() string
	partType.AddMethod(types.NewFunc(token.NoPos, pkg, "FileName",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", partPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))
	// func (p *Part) FormName() string
	partType.AddMethod(types.NewFunc(token.NoPos, pkg, "FormName",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", partPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Reader methods
	// func (r *Reader) NextPart() (*Part, error)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "NextPart",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", partPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	// func (r *Reader) NextRawPart() (*Part, error)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "NextRawPart",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", partPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// multipart.File interface (io.Reader + io.ReaderAt + io.Seeker + io.Closer)
	mpFileIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "ReadAt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSlice),
					types.NewVar(token.NoPos, nil, "off", types.Typ[types.Int64])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Seek",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "offset", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "whence", types.Typ[types.Int])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	mpFileIface.Complete()
	mpFileType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "File", nil), mpFileIface, nil)
	scope.Insert(mpFileType.Obj())

	// type FileHeader struct
	fileHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Filename", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Header", mimeHeader, false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Int64], false),
	}, nil)
	fileHeaderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FileHeader", nil),
		fileHeaderStruct, nil)
	scope.Insert(fileHeaderType.Obj())
	fileHeaderPtr := types.NewPointer(fileHeaderType)

	// func (fh *FileHeader) Open() (File, error)
	fileHeaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "fh", fileHeaderPtr),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", mpFileType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type Form struct { Value map[string][]string; File map[string][]*FileHeader }
	formStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Value", types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String])), false),
		types.NewField(token.NoPos, pkg, "File", types.NewMap(types.Typ[types.String], types.NewSlice(fileHeaderPtr)), false),
	}, nil)
	formType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Form", nil),
		formStruct, nil)
	scope.Insert(formType.Obj())
	formPtr := types.NewPointer(formType)

	// func (f *Form) RemoveAll() error
	formType.AddMethod(types.NewFunc(token.NoPos, pkg, "RemoveAll",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "f", formPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (r *Reader) ReadForm(maxMemory int64) (*Form, error)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadForm",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", readerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "maxMemory", types.Typ[types.Int64])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", formPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// var ErrMessageTooLarge error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrMessageTooLarge", errType))

	_ = strSlice

	pkg.MarkComplete()
	return pkg
}

// buildMIMEPackage creates the type-checked mime package stub.
func buildMIMEPackage() *types.Package {
	pkg := types.NewPackage("mime", "mime")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	scope.Insert(types.NewFunc(token.NoPos, pkg, "TypeByExtension",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ext", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "ExtensionsByType",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "typ", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	mapStringString := types.NewMap(types.Typ[types.String], types.Typ[types.String])

	// func FormatMediaType(t string, param map[string]string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FormatMediaType",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "t", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "param", mapStringString)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ParseMediaType(v string) (mediatype string, params map[string]string, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseMediaType",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "mediatype", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "params", mapStringString),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func AddExtensionType(ext, typ string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddExtensionType",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ext", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "typ", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// var ErrInvalidMediaParameter error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrInvalidMediaParameter", errType))

	// type WordEncoder byte
	wordEncoderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WordEncoder", nil),
		types.Typ[types.Byte], nil)
	scope.Insert(wordEncoderType.Obj())
	// func (e WordEncoder) Encode(charset, s string) string
	wordEncoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", wordEncoderType), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "charset", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	// const BEncoding, QEncoding WordEncoder
	scope.Insert(types.NewConst(token.NoPos, pkg, "BEncoding", wordEncoderType, constant.MakeInt64(int64('b'))))
	scope.Insert(types.NewConst(token.NoPos, pkg, "QEncoding", wordEncoderType, constant.MakeInt64(int64('q'))))

	// type WordDecoder struct { CharsetReader func(charset string, input io.Reader) (io.Reader, error) }
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	ioReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
	}, nil)
	ioReaderIface.Complete()
	charsetReaderFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "charset", types.Typ[types.String]),
			types.NewVar(token.NoPos, nil, "input", ioReaderIface)),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", ioReaderIface),
			types.NewVar(token.NoPos, nil, "", errType)),
		false)
	wordDecoderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "CharsetReader", charsetReaderFn, false),
	}, nil)
	wordDecoderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WordDecoder", nil),
		wordDecoderStruct, nil)
	scope.Insert(wordDecoderType.Obj())
	wdPtr := types.NewPointer(wordDecoderType)
	wdRecv := types.NewVar(token.NoPos, nil, "d", wdPtr)
	// func (d *WordDecoder) Decode(word string) (string, error)
	wordDecoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(wdRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "word", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	// func (d *WordDecoder) DecodeHeader(header string) (string, error)
	wordDecoderType.AddMethod(types.NewFunc(token.NoPos, pkg, "DecodeHeader",
		types.NewSignatureType(wdRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "header", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildMapsPackage creates the type-checked maps package stub (Go 1.21+).
func buildMapsPackage() *types.Package {
	pkg := types.NewPackage("maps", "maps")
	scope := pkg.Scope()

	// Stubbed with interface types for generic functions
	anyType := types.NewInterfaceType(nil, nil)
	anySlice := types.NewSlice(anyType)
	anyMap := types.NewMap(anyType, anyType)

	// func Keys[M ~map[K]V, K comparable, V any](m M) []K
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Keys",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "m", anyMap)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func Values[M ~map[K]V, K comparable, V any](m M) []V
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Values",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "m", anyMap)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func Clone[M ~map[K]V, K comparable, V any](m M) M
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "m", anyMap)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyMap)),
			false)))

	// func Equal[M1, M2 ~map[K]V, K, V comparable](m1 M1, m2 M2) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "m1", anyMap),
				types.NewVar(token.NoPos, pkg, "m2", anyMap)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Copy[M1 ~map[K]V, M2 ~map[K]V, K comparable, V any](dst M1, src M2)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Copy",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", anyMap),
				types.NewVar(token.NoPos, pkg, "src", anyMap)),
			nil, false)))

	// func DeleteFunc[M ~map[K]V, K comparable, V any](m M, del func(K, V) bool)
	delFunc := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "k", anyType),
			types.NewVar(token.NoPos, nil, "v", anyType)),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DeleteFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "m", anyMap),
				types.NewVar(token.NoPos, pkg, "del", delFunc)),
			nil, false)))

	// func EqualFunc[M1 ~map[K]V1, M2 ~map[K]V2, K comparable, V1, V2 any](m1 M1, m2 M2, eq func(V1, V2) bool) bool
	eqFunc := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "a", anyType),
			types.NewVar(token.NoPos, nil, "b", anyType)),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EqualFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "m1", anyMap),
				types.NewVar(token.NoPos, pkg, "m2", anyMap),
				types.NewVar(token.NoPos, pkg, "eq", eqFunc)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Collect[K comparable, V any](seq iter.Seq2[K, V]) map[K]V
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Collect",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seq", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyMap)),
			false)))

	// func All[M ~map[K]V, K comparable, V any](m M) iter.Seq2[K, V]
	scope.Insert(types.NewFunc(token.NoPos, pkg, "All",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "m", anyMap)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func Insert[M ~map[K]V, K comparable, V any](m M, seq iter.Seq2[K, V])
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Insert",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "m", anyMap),
				types.NewVar(token.NoPos, pkg, "seq", anyType)),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildMimeQuotedprintablePackage() *types.Package {
	pkg := types.NewPackage("mime/quotedprintable", "quotedprintable")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSliceQP := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
	ioReaderQP := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceQP)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderQP.Complete()

	// io.Writer interface
	ioWriterQP := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceQP)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterQP.Complete()

	// type Reader struct { ... }
	readerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	readerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		readerStruct, nil)
	scope.Insert(readerType.Obj())

	// func NewReader(r io.Reader) *Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReaderQP)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(readerType))),
			false)))

	// Reader.Read(p []byte) (int, error)
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(readerType)), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type Writer struct { Binary bool }
	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Binary", types.Typ[types.Bool], false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())

	// func NewWriter(w io.Writer) *Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterQP)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(writerType))),
			false)))

	// Writer.Write(p []byte) (int, error)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(writerType)), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", byteSliceQP)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Writer.Close() error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(writerType)), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildOsExecPackage creates the type-checked os/exec package stub.
func buildOsExecPackage() *types.Package {
	pkg := types.NewPackage("os/exec", "exec")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	byteSliceExec := types.NewSlice(types.Typ[types.Byte])

	// io.Writer interface
	writerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceExec)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	writerIface.Complete()

	// io.Reader interface
	readerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceExec)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	readerIface.Complete()

	// io.WriteCloser interface (for StdinPipe)
	writeCloserIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceExec)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	writeCloserIface.Complete()

	// io.ReadCloser interface (for StdoutPipe, StderrPipe)
	readCloserIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceExec)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	readCloserIface.Complete()

	// os.File stand-in (opaque pointer)
	osFileStandin := types.NewPointer(types.NewStruct(nil, nil))

	// os.Process stand-in (opaque pointer)
	osProcessStandin := types.NewPointer(types.NewStruct(nil, nil))

	// os.ProcessState stand-in (opaque pointer)
	osProcessStateStandin := types.NewPointer(types.NewStruct(nil, nil))

	// syscall.SysProcAttr stand-in (opaque pointer)
	sysProcAttrStandin := types.NewPointer(types.NewStruct(nil, nil))

	// type Cmd struct
	cmdStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Dir", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Args", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Env", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Stdin", readerIface, false),
		types.NewField(token.NoPos, pkg, "Stdout", writerIface, false),
		types.NewField(token.NoPos, pkg, "Stderr", writerIface, false),
		types.NewField(token.NoPos, pkg, "ExtraFiles", types.NewSlice(osFileStandin), false),
		types.NewField(token.NoPos, pkg, "Process", osProcessStandin, false),
		types.NewField(token.NoPos, pkg, "ProcessState", osProcessStateStandin, false),
		types.NewField(token.NoPos, pkg, "SysProcAttr", sysProcAttrStandin, false),
		types.NewField(token.NoPos, pkg, "WaitDelay", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Cancel", types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false), false),
	}, nil)
	cmdType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Cmd", nil),
		cmdStruct, nil)
	scope.Insert(cmdType.Obj())
	cmdPtr := types.NewPointer(cmdType)

	// func Command(name string, arg ...string) *Cmd
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Command",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "arg", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", cmdPtr)),
			true)))

	// func LookPath(file string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookPath",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "file", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// context.Context stand-in for CommandContext
	ctxIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Deadline",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Done",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewChan(types.RecvOnly, types.NewStruct(nil, nil)))), false)),
		types.NewFunc(token.NoPos, nil, "Err",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Value",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.NewInterfaceType(nil, nil))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))), false)),
	}, nil)
	ctxIface.Complete()

	// func CommandContext(ctx context.Context, name string, arg ...string) *Cmd
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CommandContext",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIface),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "arg", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", cmdPtr)),
			true)))

	// Cmd methods
	cmdRecv := types.NewVar(token.NoPos, pkg, "c", cmdPtr)
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// (*Cmd).Run() error
	cmdType.AddMethod(types.NewFunc(token.NoPos, pkg, "Run",
		types.NewSignatureType(cmdRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Cmd).Start() error
	cmdType.AddMethod(types.NewFunc(token.NoPos, pkg, "Start",
		types.NewSignatureType(cmdRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Cmd).Wait() error
	cmdType.AddMethod(types.NewFunc(token.NoPos, pkg, "Wait",
		types.NewSignatureType(cmdRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Cmd).Output() ([]byte, error)
	cmdType.AddMethod(types.NewFunc(token.NoPos, pkg, "Output",
		types.NewSignatureType(cmdRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Cmd).CombinedOutput() ([]byte, error)
	cmdType.AddMethod(types.NewFunc(token.NoPos, pkg, "CombinedOutput",
		types.NewSignatureType(cmdRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Cmd).StdinPipe() (io.WriteCloser, error)
	cmdType.AddMethod(types.NewFunc(token.NoPos, pkg, "StdinPipe",
		types.NewSignatureType(cmdRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", writeCloserIface),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Cmd).StdoutPipe() (io.ReadCloser, error)
	cmdType.AddMethod(types.NewFunc(token.NoPos, pkg, "StdoutPipe",
		types.NewSignatureType(cmdRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", readCloserIface),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Cmd).StderrPipe() (io.ReadCloser, error)
	cmdType.AddMethod(types.NewFunc(token.NoPos, pkg, "StderrPipe",
		types.NewSignatureType(cmdRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", readCloserIface),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Cmd).String() string
	cmdType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(cmdRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// (*Cmd).Environ() []string
	cmdType.AddMethod(types.NewFunc(token.NoPos, pkg, "Environ",
		types.NewSignatureType(cmdRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// type Error struct
	errStruct := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Error", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		}, nil), nil)
	scope.Insert(errStruct.Obj())
	// Error.Error() string
	errStruct.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(errStruct)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	// Error.Unwrap() error
	errStruct.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(errStruct)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// type ExitError struct { Stderr []byte }
	exitErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ExitError", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Stderr", byteSlice, false),
		}, nil), nil)
	scope.Insert(exitErrType.Obj())
	exitErrPtr := types.NewPointer(exitErrType)
	// ExitError.Error() string
	exitErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", exitErrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	// ExitError.ExitCode() int
	exitErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExitCode",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", exitErrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	// ExitError.Unwrap() error
	exitErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", exitErrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// var ErrNotFound error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNotFound", errType))
	// var ErrDot error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrDot", errType))
	// var ErrWaitDelay error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrWaitDelay", errType))

	pkg.MarkComplete()
	return pkg
}

// buildOsSignalPackage creates the type-checked os/signal package stub.
func buildOsSignalPackage() *types.Package {
	pkg := types.NewPackage("os/signal", "signal")
	scope := pkg.Scope()

	// os.Signal interface (Signal() + String())
	sigIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Signal",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	sigIface.Complete()
	sigType := sigIface
	sigChan := types.NewChan(types.SendOnly, sigType)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Notify",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", sigChan),
				types.NewVar(token.NoPos, pkg, "sig", types.NewSlice(sigType))),
			nil, true)))

	// func Stop(c chan<- os.Signal)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Stop",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "c", sigChan)),
			nil, false)))

	// func Reset(sig ...os.Signal)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "sig", types.NewSlice(sigType))),
			nil, true)))

	// func Ignore(sig ...os.Signal)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Ignore",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "sig", types.NewSlice(sigType))),
			nil, true)))

	// func Ignored(sig os.Signal) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Ignored",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "sig", sigType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// context.Context stand-in for NotifyContext
	errType := types.Universe.Lookup("error").Type()
	anyTypeSignal := types.NewInterfaceType(nil, nil)
	anyTypeSignal.Complete()
	ctxIfaceSignal := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Deadline",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Done",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "",
					types.NewChan(types.RecvOnly, types.NewStruct(nil, nil)))), false)),
		types.NewFunc(token.NoPos, nil, "Err",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Value",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyTypeSignal)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyTypeSignal)), false)),
	}, nil)
	ctxIfaceSignal.Complete()
	cancelFunc := types.NewSignatureType(nil, nil, nil, nil, nil, false)

	// func NotifyContext(parent context.Context, signals ...os.Signal) (ctx context.Context, stop context.CancelFunc)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NotifyContext",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "parent", ctxIfaceSignal),
				types.NewVar(token.NoPos, pkg, "signals", types.NewSlice(sigType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIfaceSignal),
				types.NewVar(token.NoPos, pkg, "stop", cancelFunc)),
			true)))

	pkg.MarkComplete()
	return pkg
}

func buildOsUserPackage() *types.Package {
	pkg := types.NewPackage("os/user", "user")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	userStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Uid", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Gid", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Username", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "HomeDir", types.Typ[types.String], false),
	}, nil)
	userType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "User", nil),
		userStruct, nil)
	scope.Insert(userType.Obj())
	userPtr := types.NewPointer(userType)

	// func Current() (*User, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Current",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", userPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Lookup(username string) (*User, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "username", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", userPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func LookupId(uid string) (*User, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupId",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "uid", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", userPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// User.GroupIds() ([]string, error)
	userType.AddMethod(types.NewFunc(token.NoPos, pkg, "GroupIds",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "u", userPtr),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type Group struct
	groupStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Gid", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
	}, nil)
	groupType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Group", nil),
		groupStruct, nil)
	scope.Insert(groupType.Obj())
	groupPtr := types.NewPointer(groupType)

	// func LookupGroup(name string) (*Group, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupGroup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", groupPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func LookupGroupId(gid string) (*Group, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupGroupId",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "gid", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", groupPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type UnknownUserError string
	unknownUserType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnknownUserError", nil),
		types.Typ[types.String], nil)
	unknownUserType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownUserType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unknownUserType.Obj())

	// type UnknownUserIdError int
	unknownUserIdType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnknownUserIdError", nil),
		types.Typ[types.Int], nil)
	unknownUserIdType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownUserIdType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unknownUserIdType.Obj())

	// type UnknownGroupError string
	unknownGroupType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnknownGroupError", nil),
		types.Typ[types.String], nil)
	unknownGroupType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownGroupType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unknownGroupType.Obj())

	// type UnknownGroupIdError string
	unknownGroupIdType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnknownGroupIdError", nil),
		types.Typ[types.String], nil)
	unknownGroupIdType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownGroupIdType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(unknownGroupIdType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildPathPackage() *types.Package {
	pkg := types.NewPackage("path", "path")
	scope := pkg.Scope()

	ss := func(name string) {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
				false)))
	}
	ss("Base")
	ss("Dir")
	ss("Ext")
	ss("Clean")

	// func IsAbs(path string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsAbs",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Join(elem ...string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Join",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "elem", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			true)))

	// func Split(path string) (dir, file string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Split",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "file", types.Typ[types.String])),
			false)))

	// func Match(pattern, name string) (bool, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Match",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, pkg, "", types.Universe.Lookup("error").Type())),
			false)))

	// var ErrBadPattern error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrBadPattern",
		types.Universe.Lookup("error").Type()))

	pkg.MarkComplete()
	return pkg
}

func buildPluginPackage() *types.Package {
	pkg := types.NewPackage("plugin", "plugin")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Plugin struct { ... }
	pluginStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	pluginType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Plugin", nil),
		pluginStruct, nil)
	scope.Insert(pluginType.Obj())

	// func Open(path string) (*Plugin, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(pluginType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Plugin.Lookup(symName string) (Symbol, error)
	symbolType := types.NewInterfaceType(nil, nil)
	symbolType.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Symbol", symbolType))

	pluginType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(pluginType)), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "symName", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", symbolType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildReflectPackage creates a minimal type-checked reflect package stub.
func buildReflectPackage() *types.Package {
	pkg := types.NewPackage("reflect", "reflect")
	scope := pkg.Scope()

	// type Kind uint
	kindType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Kind", nil),
		types.Typ[types.Uint], nil)
	scope.Insert(kindType.Obj())
	kindType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "k", kindType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// Forward-declare Type interface (populated via SetUnderlying later)
	typeIface := types.NewInterfaceType(nil, nil)
	typeIface.Complete()
	typeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Type", nil),
		typeIface, nil)

	// type StructField struct
	structFieldType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "StructField", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "PkgPath", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Type", typeType, false),
			types.NewField(token.NoPos, pkg, "Tag", types.NewNamed(
				types.NewTypeName(token.NoPos, pkg, "StructTag", nil),
				types.Typ[types.String], nil), false),
			types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Uintptr], false),
			types.NewField(token.NoPos, pkg, "Index", types.NewSlice(types.Typ[types.Int]), false),
			types.NewField(token.NoPos, pkg, "Anonymous", types.Typ[types.Bool], false),
		}, nil), nil)
	scope.Insert(structFieldType.Obj())

	// type StructTag string (already nested above, define separately too)
	structTagType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "StructTag", nil),
		types.Typ[types.String], nil)
	scope.Insert(structTagType.Obj())
	structTagType.AddMethod(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "tag", structTagType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	structTagType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "tag", structTagType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// type ChanDir int
	chanDirType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ChanDir", nil),
		types.Typ[types.Int], nil)
	scope.Insert(chanDirType.Obj())

	// ChanDir.String() string
	chanDirType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "d", chanDirType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// type Method struct
	methodStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "PkgPath", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Type", typeType, false),
		types.NewField(token.NoPos, pkg, "Func", types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, nil, "val", types.Typ[types.Int], false),
		}, nil), false),
		types.NewField(token.NoPos, pkg, "Index", types.Typ[types.Int], false),
	}, nil)
	methodType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Method", nil),
		methodStruct, nil)
	scope.Insert(methodType.Obj())

	// Populate Type interface with methods (forward-declared earlier)

	typeIfaceReal := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Align",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "FieldAlign",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "Method",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", methodType)), false)),
		types.NewFunc(token.NoPos, pkg, "MethodByName",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", methodType),
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "NumMethod",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "PkgPath",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uintptr])), false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Kind",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", kindType)), false)),
		types.NewFunc(token.NoPos, pkg, "Implements",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "u", typeType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "AssignableTo",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "u", typeType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "ConvertibleTo",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "u", typeType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Comparable",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Bits",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "ChanDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", chanDirType)), false)),
		types.NewFunc(token.NoPos, pkg, "IsVariadic",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Elem",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)),
		types.NewFunc(token.NoPos, pkg, "Field",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", structFieldType)), false)),
		types.NewFunc(token.NoPos, pkg, "FieldByIndex",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "index", types.NewSlice(types.Typ[types.Int]))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", structFieldType)), false)),
		types.NewFunc(token.NoPos, pkg, "FieldByName",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", structFieldType),
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "NumField",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "In",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)),
		types.NewFunc(token.NoPos, pkg, "Key",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)),
		types.NewFunc(token.NoPos, pkg, "Len",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "NumIn",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "NumOut",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "Out",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)), false)),
	}, nil)
	typeIfaceReal.Complete()
	typeType.SetUnderlying(typeIfaceReal)
	scope.Insert(typeType.Obj())

	// type Value struct { ... }
	valueStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "val", types.Typ[types.Int], false),
	}, nil)
	valueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Value", nil),
		valueStruct, nil)
	scope.Insert(valueType.Obj())

	// func TypeOf(i any) Type
	anyType := types.NewInterfaceType(nil, nil)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TypeOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "i", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", typeType)),
			false)))

	// func ValueOf(i any) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ValueOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "i", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func DeepEqual(x, y any) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DeepEqual",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "x", anyType),
				types.NewVar(token.NoPos, pkg, "y", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Zero(typ Type) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Zero",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "typ", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func New(typ Type) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "typ", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func MakeSlice(typ Type, len, cap int) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeSlice",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "typ", typeType),
				types.NewVar(token.NoPos, pkg, "len", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "cap", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func MakeMap(typ Type) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeMap",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "typ", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func MakeMapWithSize(typ Type, n int) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeMapWithSize",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "typ", typeType),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func MakeChan(typ Type, buffer int) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeChan",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "typ", typeType),
				types.NewVar(token.NoPos, pkg, "buffer", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func Indirect(v Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Indirect",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func Append(s Value, x ...Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Append",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", valueType),
				types.NewVar(token.NoPos, pkg, "x", types.NewSlice(valueType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			true)))

	// func AppendSlice(s, t Value) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendSlice",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", valueType),
				types.NewVar(token.NoPos, pkg, "t", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func Copy(dst, src Value) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Copy",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", valueType),
				types.NewVar(token.NoPos, pkg, "src", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Swapper(slice any) func(i, j int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Swapper",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "slice", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
						types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
					nil, false))),
			false)))

	// func PtrTo(t Type) Type (deprecated alias for PointerTo)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PtrTo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "t", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", typeType)),
			false)))

	// func PointerTo(t Type) Type
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PointerTo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "t", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", typeType)),
			false)))

	// func SliceOf(t Type) Type
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SliceOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "t", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", typeType)),
			false)))

	// func MapOf(key, elem Type) Type
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MapOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", typeType),
				types.NewVar(token.NoPos, pkg, "elem", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", typeType)),
			false)))

	// func ChanOf(dir ChanDir, t Type) Type — ChanDir is int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ChanOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "t", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", typeType)),
			false)))

	// Value methods
	valuePtr := types.NewPointer(valueType)
	_ = valuePtr
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Float64])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bool",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bytes",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Interface",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", anyType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Kind",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", kindType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Type",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", typeType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsNil",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsZero",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Elem",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Field",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "FieldByName",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Len",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cap",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "MapKeys",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(valueType))),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "MapIndex",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumField",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumMethod",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", valueType)),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetInt",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int64])),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetString",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.String])),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetFloat",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Float64])),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetBool",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Bool])),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetBytes",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.NewSlice(types.Typ[types.Byte]))),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "CanSet",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "CanInterface",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "CanAddr",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Addr",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pointer",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uintptr])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetMapIndex",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", valueType),
				types.NewVar(token.NoPos, nil, "elem", valueType)),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Slice",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "j", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Call",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "in", types.NewSlice(valueType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(valueType))),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "CallSlice",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "in", types.NewSlice(valueType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(valueType))),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetUint",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Uint64])),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Convert",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	// Forward-declare MapIter for MapRange return type
	mapIterTypeName := types.NewTypeName(token.NoPos, pkg, "MapIter", nil)
	mapIterType := types.NewNamed(mapIterTypeName, nil, nil)
	mapIterPtr := types.NewPointer(mapIterType)
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "MapRange",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", mapIterPtr)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetLen",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetCap",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			nil, false)))

	// More Value methods
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "FieldByIndex",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "index", types.NewSlice(types.Typ[types.Int]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "FieldByNameFunc",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "match",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
					false))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Method",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "MethodByName",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", valueType),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Recv",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", valueType),
				types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Send",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", valueType)),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "TrySend",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "TryRecv",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "x", valueType),
				types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil, nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetPointer",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.UnsafePointer])),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnsafeAddr",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uintptr])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnsafePointer",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.UnsafePointer])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "OverflowFloat",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Float64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "OverflowInt",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "OverflowUint",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Complex",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Complex128])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetComplex",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", types.Typ[types.Complex128])),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Comparable",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "u", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Grow",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetZero",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil, nil, false)))

	// Value predicate methods (Go 1.20+)
	for _, name := range []string{"CanComplex", "CanFloat", "CanInt", "CanUint"} {
		valueType.AddMethod(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(
				types.NewVar(token.NoPos, nil, "v", valueType),
				nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
				false)))
	}

	// Value.Seq and Value.Seq2 (Go 1.23+ range-over-func)
	// func (v Value) Seq() iter.Seq[Value]  — simplified as func() func(func(Value) bool)
	yieldValFunc := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)
	seqFunc := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "yield", yieldValFunc)),
		nil, false)
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seq",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", seqFunc)),
			false)))
	yieldVal2Func := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", valueType),
			types.NewVar(token.NoPos, nil, "", valueType)),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)
	seq2Func := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "yield", yieldVal2Func)),
		nil, false)
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Seq2",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "v", valueType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", seq2Func)),
			false)))

	// type SelectDir int
	selectDirType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SelectDir", nil),
		types.Typ[types.Int], nil)
	scope.Insert(selectDirType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "SelectSend", selectDirType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SelectRecv", selectDirType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SelectDefault", selectDirType, constant.MakeInt64(3)))

	// type SelectCase struct { Dir SelectDir; Chan Value; Send Value }
	selectCaseStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dir", selectDirType, false),
		types.NewField(token.NoPos, pkg, "Chan", valueType, false),
		types.NewField(token.NoPos, pkg, "Send", valueType, false),
	}, nil)
	selectCaseType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SelectCase", nil),
		selectCaseStruct, nil)
	scope.Insert(selectCaseType.Obj())

	// func Select(cases []SelectCase) (chosen int, value Value, ok bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Select",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "cases", types.NewSlice(selectCaseType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "chosen", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "value", valueType),
				types.NewVar(token.NoPos, pkg, "ok", types.Typ[types.Bool])),
			false)))

	// func FuncOf(in, out []Type, variadic bool) Type
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FuncOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "in", types.NewSlice(typeType)),
				types.NewVar(token.NoPos, pkg, "out", types.NewSlice(typeType)),
				types.NewVar(token.NoPos, pkg, "variadic", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", typeType)),
			false)))

	// func StructOf(fields []StructField) Type
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StructOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fields", types.NewSlice(structFieldType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", typeType)),
			false)))

	// func ArrayOf(length int, elem Type) Type
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ArrayOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "length", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "elem", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", typeType)),
			false)))

	// func MakeFunc(typ Type, fn func(args []Value) (results []Value)) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MakeFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "typ", typeType),
				types.NewVar(token.NoPos, pkg, "fn",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "args", types.NewSlice(valueType))),
						types.NewTuple(types.NewVar(token.NoPos, nil, "results", types.NewSlice(valueType))),
						false))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func NewAt(typ Type, p unsafe.Pointer) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewAt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "typ", typeType),
				types.NewVar(token.NoPos, pkg, "p", types.Typ[types.UnsafePointer])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// MapIter underlying + methods (forward-declared above)
	mapIterType.SetUnderlying(types.NewStruct(nil, nil))
	scope.Insert(mapIterTypeName)
	mapIterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Key",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "it", mapIterPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	mapIterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "it", mapIterPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", valueType)),
			false)))
	mapIterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "it", mapIterPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	mapIterType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "it", mapIterPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "m", valueType)),
			nil, false)))

	// type SliceHeader struct { Data uintptr; Len int; Cap int }
	sliceHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Data", types.Typ[types.Uintptr], false),
		types.NewField(token.NoPos, pkg, "Len", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Cap", types.Typ[types.Int], false),
	}, nil)
	sliceHeaderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SliceHeader", nil),
		sliceHeaderStruct, nil)
	scope.Insert(sliceHeaderType.Obj())

	// type StringHeader struct { Data uintptr; Len int }
	stringHeaderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Data", types.Typ[types.Uintptr], false),
		types.NewField(token.NoPos, pkg, "Len", types.Typ[types.Int], false),
	}, nil)
	stringHeaderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "StringHeader", nil),
		stringHeaderStruct, nil)
	scope.Insert(stringHeaderType.Obj())

	// Kind constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "Invalid", kindType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Bool", kindType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Int", kindType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Int8", kindType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Int16", kindType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Int32", kindType, constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Int64", kindType, constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Uint", kindType, constant.MakeInt64(7)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Uint8", kindType, constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Uint16", kindType, constant.MakeInt64(9)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Uint32", kindType, constant.MakeInt64(10)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Uint64", kindType, constant.MakeInt64(11)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Uintptr", kindType, constant.MakeInt64(12)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Float32", kindType, constant.MakeInt64(13)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Float64", kindType, constant.MakeInt64(14)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Complex64", kindType, constant.MakeInt64(15)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Complex128", kindType, constant.MakeInt64(16)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Array", kindType, constant.MakeInt64(17)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Chan", kindType, constant.MakeInt64(18)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Func", kindType, constant.MakeInt64(19)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Interface", kindType, constant.MakeInt64(20)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Map", kindType, constant.MakeInt64(21)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Pointer", kindType, constant.MakeInt64(22)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Slice", kindType, constant.MakeInt64(23)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "String", kindType, constant.MakeInt64(24)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Struct", kindType, constant.MakeInt64(25)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "UnsafePointer", kindType, constant.MakeInt64(26)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Ptr", kindType, constant.MakeInt64(22))) // alias for Pointer

	// ChanDir type defined earlier for Type interface; add constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "RecvDir", chanDirType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SendDir", chanDirType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "BothDir", chanDirType, constant.MakeInt64(3)))

	// func VisibleFields(t Type) []StructField
	scope.Insert(types.NewFunc(token.NoPos, pkg, "VisibleFields",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "t", typeType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(structFieldType))),
			false)))

	// func TypeAssert[T any](v Value) (T, bool) — Go 1.25+
	// Stubbed as TypeAssert(v Value) (any, bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TypeAssert",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", valueType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildRegexpPackage creates the type-checked regexp package stub.
func buildRegexpPackage() *types.Package {
	pkg := types.NewPackage("regexp", "regexp")
	scope := pkg.Scope()

	// type Regexp struct { ... }
	regexpStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "pattern", types.Typ[types.String], false),
	}, nil)
	regexpType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Regexp", nil),
		regexpStruct, nil)
	scope.Insert(regexpType.Obj())
	regexpPtr := types.NewPointer(regexpType)

	// func Compile(expr string) (*Regexp, error)
	errType := types.Universe.Lookup("error").Type()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "expr", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", regexpPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func MustCompile(str string) *Regexp
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MustCompile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "str", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", regexpPtr)),
			false)))

	// func MatchString(pattern string, s string) (bool, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MatchString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func QuoteMeta(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "QuoteMeta",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Match(pattern string, b []byte) (matched bool, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Match",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "b", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func CompilePOSIX(expr string) (*Regexp, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CompilePOSIX",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "expr", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", regexpPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func MustCompilePOSIX(str string) *Regexp
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MustCompilePOSIX",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "str", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", regexpPtr)),
			false)))

	// Regexp methods
	regexpRecv := types.NewVar(token.NoPos, pkg, "re", regexpPtr)
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// (*Regexp).MatchString(s string) bool
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "MatchString",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// (*Regexp).Match(b []byte) bool
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "Match",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// (*Regexp).FindString(s string) string
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindString",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// (*Regexp).FindStringIndex(s string) []int
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindStringIndex",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Int]))),
			false)))

	// (*Regexp).FindStringSubmatch(s string) []string
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindStringSubmatch",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// (*Regexp).FindAllString(s string, n int) []string
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindAllString",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// (*Regexp).FindAllStringSubmatch(s string, n int) [][]string
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindAllStringSubmatch",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.NewSlice(types.Typ[types.String])))),
			false)))

	// (*Regexp).ReplaceAllString(src, repl string) string
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReplaceAllString",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "src", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "repl", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// (*Regexp).ReplaceAllStringFunc(src string, repl func(string) string) string
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReplaceAllStringFunc",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "src", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "repl",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
						false))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// (*Regexp).Split(s string, n int) []string
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "Split",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// (*Regexp).String() string
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// (*Regexp).SubexpNames() []string
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "SubexpNames",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	// (*Regexp).NumSubexp() int
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "NumSubexp",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// (*Regexp).Find(b []byte) []byte
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "Find",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))

	// (*Regexp).FindIndex(b []byte) []int
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindIndex",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Int]))),
			false)))

	// (*Regexp).FindSubmatch(b []byte) [][]byte
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindSubmatch",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(byteSlice))),
			false)))

	// (*Regexp).FindSubmatchIndex(b []byte) []int
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindSubmatchIndex",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Int]))),
			false)))

	// (*Regexp).FindAll(b []byte, n int) [][]byte
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindAll",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "b", byteSlice),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(byteSlice))),
			false)))

	// (*Regexp).FindAllIndex(b []byte, n int) [][]int
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindAllIndex",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "b", byteSlice),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.NewSlice(types.Typ[types.Int])))),
			false)))

	// (*Regexp).FindAllSubmatch(b []byte, n int) [][][]byte
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindAllSubmatch",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "b", byteSlice),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.NewSlice(byteSlice)))),
			false)))

	// (*Regexp).FindAllSubmatchIndex(b []byte, n int) [][]int
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindAllSubmatchIndex",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "b", byteSlice),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.NewSlice(types.Typ[types.Int])))),
			false)))

	// (*Regexp).FindStringSubmatchIndex(s string) []int
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindStringSubmatchIndex",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Int]))),
			false)))

	// (*Regexp).FindAllStringIndex(s string, n int) [][]int
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindAllStringIndex",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.NewSlice(types.Typ[types.Int])))),
			false)))

	// (*Regexp).FindAllStringSubmatchIndex(s string, n int) [][]int
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindAllStringSubmatchIndex",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.NewSlice(types.Typ[types.Int])))),
			false)))

	// (*Regexp).ReplaceAll(src, repl []byte) []byte
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReplaceAll",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "src", byteSlice),
				types.NewVar(token.NoPos, nil, "repl", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))

	// (*Regexp).ReplaceAllFunc(src []byte, repl func([]byte) []byte) []byte
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReplaceAllFunc",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "src", byteSlice),
				types.NewVar(token.NoPos, nil, "repl",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
						false))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))

	// (*Regexp).ReplaceAllLiteral(src, repl []byte) []byte
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReplaceAllLiteral",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "src", byteSlice),
				types.NewVar(token.NoPos, nil, "repl", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))

	// (*Regexp).ReplaceAllLiteralString(src, repl string) string
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReplaceAllLiteralString",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "src", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "repl", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// (*Regexp).Expand(dst []byte, template []byte, src []byte, match []int) []byte
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "Expand",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", byteSlice),
				types.NewVar(token.NoPos, nil, "template", byteSlice),
				types.NewVar(token.NoPos, nil, "src", byteSlice),
				types.NewVar(token.NoPos, nil, "match", types.NewSlice(types.Typ[types.Int]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))

	// (*Regexp).ExpandString(dst []byte, template string, src string, match []int) []byte
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExpandString",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "dst", byteSlice),
				types.NewVar(token.NoPos, nil, "template", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "src", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "match", types.NewSlice(types.Typ[types.Int]))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
			false)))

	// (*Regexp).Longest()
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "Longest",
		types.NewSignatureType(regexpRecv, nil, nil, nil, nil, false)))

	// (*Regexp).SubexpIndex(name string) int
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "SubexpIndex",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// (*Regexp).Copy() *Regexp (deprecated but still used)
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "Copy",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", regexpPtr)),
			false)))

	// (*Regexp).LiteralPrefix() (prefix string, complete bool)
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "LiteralPrefix",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "complete", types.Typ[types.Bool])),
			false)))

	// io.RuneReader interface for MatchReader
	runeReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ReadRune",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "r", types.Typ[types.Rune]),
					types.NewVar(token.NoPos, nil, "size", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", types.Universe.Lookup("error").Type())),
				false)),
	}, nil)
	runeReaderIface.Complete()

	// (*Regexp).MatchReader(r io.RuneReader) bool
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "MatchReader",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", runeReaderIface)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func MatchReader(pattern string, r io.RuneReader) (matched bool, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MatchReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "r", runeReaderIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "matched", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// (*Regexp).FindReaderIndex(r io.RuneReader) (loc []int)
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindReaderIndex",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", runeReaderIface)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Int]))),
			false)))

	// (*Regexp).FindReaderSubmatchIndex(r io.RuneReader) []int
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "FindReaderSubmatchIndex",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", runeReaderIface)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Int]))),
			false)))

	// (*Regexp).MarshalText() ([]byte, error)
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// (*Regexp).UnmarshalText(text []byte) error
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(regexpRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "text", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildRegexpSyntaxPackage() *types.Package {
	pkg := types.NewPackage("regexp/syntax", "syntax")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Flags uint16
	flagsType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Flags", nil), types.Typ[types.Uint16], nil)
	scope.Insert(flagsType.Obj())
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"FoldCase", 1}, {"Literal", 2}, {"ClassNL", 4}, {"DotNL", 8},
		{"OneLine", 16}, {"NonGreedy", 32}, {"PerlX", 64}, {"UnicodeGroups", 128},
		{"WasDollar", 256}, {"Simple", 512},
		{"MatchNL", 4 | 8}, {"Perl", 0xD2}, {"POSIX", 0},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, flagsType, constant.MakeInt64(c.val)))
	}

	// type Op uint8
	opType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Op", nil), types.Typ[types.Uint8], nil)
	scope.Insert(opType.Obj())
	opType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "i", opType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	for i, name := range []string{
		"OpNoMatch", "OpEmptyMatch", "OpLiteral", "OpCharClass", "OpAnyCharNotNL",
		"OpAnyChar", "OpBeginLine", "OpEndLine", "OpBeginText", "OpEndText",
		"OpWordBoundary", "OpNoWordBoundary", "OpCapture", "OpStar", "OpPlus",
		"OpQuest", "OpRepeat", "OpConcat", "OpAlternate",
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, name, opType, constant.MakeInt64(int64(i+1))))
	}

	// type Regexp struct
	regexpType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Regexp", nil), types.NewStruct(nil, nil), nil)
	regexpStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Op", opType, false),
		types.NewField(token.NoPos, pkg, "Flags", flagsType, false),
		types.NewField(token.NoPos, pkg, "Sub", types.NewSlice(types.NewPointer(regexpType)), false),
		types.NewField(token.NoPos, pkg, "Rune", types.NewSlice(types.Typ[types.Rune]), false),
		types.NewField(token.NoPos, pkg, "Min", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Max", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Cap", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
	}, nil)
	regexpType.SetUnderlying(regexpStruct)
	scope.Insert(regexpType.Obj())
	regexpPtr := types.NewPointer(regexpType)
	regexpRecv := types.NewVar(token.NoPos, nil, "re", regexpPtr)
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "x", regexpPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "y", regexpPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "Simplify",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", regexpPtr)), false)))
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "MaxCap",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	regexpType.AddMethod(types.NewFunc(token.NoPos, pkg, "CapNames",
		types.NewSignatureType(regexpRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String]))), false)))

	// type Inst struct
	instOpType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "InstOp", nil), types.Typ[types.Uint8], nil)
	scope.Insert(instOpType.Obj())
	instStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Op", instOpType, false),
		types.NewField(token.NoPos, pkg, "Out", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Arg", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Rune", types.NewSlice(types.Typ[types.Rune]), false),
	}, nil)
	instType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Inst", nil), instStruct, nil)
	scope.Insert(instType.Obj())
	instType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "i", types.NewPointer(instType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Prog struct
	progStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Inst", types.NewSlice(instType), false),
		types.NewField(token.NoPos, pkg, "Start", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "NumCap", types.Typ[types.Int], false),
	}, nil)
	progType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Prog", nil), progStruct, nil)
	scope.Insert(progType.Obj())
	progPtr := types.NewPointer(progType)
	progType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", progPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type EmptyOp uint8
	emptyOpType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "EmptyOp", nil), types.Typ[types.Uint8], nil)
	scope.Insert(emptyOpType.Obj())
	for _, c := range []struct {
		name string
		val  int64
	}{
		{"EmptyBeginLine", 1}, {"EmptyEndLine", 2}, {"EmptyBeginText", 4},
		{"EmptyEndText", 8}, {"EmptyWordBoundary", 16}, {"EmptyNoWordBoundary", 32},
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, c.name, emptyOpType, constant.MakeInt64(c.val)))
	}

	// type Error struct { Code ErrorCode; Expr string }
	errorCodeType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ErrorCode", nil), types.Typ[types.String], nil)
	scope.Insert(errorCodeType.Obj())
	for _, name := range []string{
		"ErrInternalError", "ErrInvalidCharClass", "ErrInvalidCharRange",
		"ErrInvalidEscape", "ErrInvalidNamedCapture", "ErrInvalidPerlOp",
		"ErrInvalidRepeatOp", "ErrInvalidRepeatSize", "ErrInvalidUTF8",
		"ErrMissingBracket", "ErrMissingParen", "ErrMissingRepeatArgument",
		"ErrNestingDepth", "ErrUnexpectedParen",
	} {
		scope.Insert(types.NewConst(token.NoPos, pkg, name, errorCodeType, constant.MakeString(name)))
	}

	syntaxErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Code", errorCodeType, false),
		types.NewField(token.NoPos, pkg, "Expr", types.Typ[types.String], false),
	}, nil)
	syntaxErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Error", nil), syntaxErrStruct, nil)
	syntaxErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(syntaxErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	scope.Insert(syntaxErrType.Obj())

	// func Parse(s string, flags Flags) (*Regexp, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "flags", flagsType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", regexpPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Compile(re *Regexp) (*Prog, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "re", regexpPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", progPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func IsWordChar(r rune) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsWordChar",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func EmptyOpContext(r1, r2 rune) EmptyOp
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EmptyOpContext",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r1", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, pkg, "r2", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", emptyOpType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildRuntimeCgoPackage() *types.Package {
	pkg := types.NewPackage("runtime/cgo", "cgo")
	scope := pkg.Scope()

	// type Handle uintptr
	handleType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Handle", nil),
		types.Typ[types.Uintptr], nil)
	scope.Insert(handleType.Obj())

	handleRecv := types.NewVar(token.NoPos, pkg, "", handleType)
	emptyIface := types.NewInterfaceType(nil, nil)
	emptyIface.Complete()

	// Handle.Value() any
	handleType.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(handleRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", emptyIface)),
			false)))

	// Handle.Delete()
	handleType.AddMethod(types.NewFunc(token.NoPos, pkg, "Delete",
		types.NewSignatureType(handleRecv, nil, nil, nil, nil, false)))

	// func NewHandle(v any) Handle
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewHandle",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", emptyIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handleType)),
			false)))

	// type Incomplete struct — incomplete C type marker
	incompleteStruct := types.NewStruct(nil, nil)
	incompleteType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Incomplete", nil),
		incompleteStruct, nil)
	scope.Insert(incompleteType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildRuntimeCoveragePackage() *types.Package {
	pkg := types.NewPackage("runtime/coverage", "coverage")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSliceCov := types.NewSlice(types.Typ[types.Byte])

	// io.Writer interface
	ioWriterCov := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceCov)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterCov.Complete()

	// func WriteCountersDir(dir string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteCountersDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func WriteCounters(w io.Writer) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteCounters",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterCov)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func WriteMetaDir(dir string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteMetaDir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func WriteMeta(w io.Writer) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteMeta",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterCov)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ClearCounters() error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ClearCounters",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildRuntimeDebugPackage() *types.Package {
	pkg := types.NewPackage("runtime/debug", "debug")
	scope := pkg.Scope()

	// Module type — use forward declaration for self-referential Replace *Module field
	moduleType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Module", nil),
		types.NewStruct(nil, nil), nil) // placeholder
	moduleStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Sum", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Replace", types.NewPointer(moduleType), false),
	}, nil)
	moduleType.SetUnderlying(moduleStruct)
	scope.Insert(moduleType.Obj())

	// BuildSetting type
	buildSettingStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Key", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", types.Typ[types.String], false),
	}, nil)
	buildSettingType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "BuildSetting", nil),
		buildSettingStruct, nil)
	scope.Insert(buildSettingType.Obj())

	// BuildInfo type
	buildInfoStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "GoVersion", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Main", moduleType, false),
		types.NewField(token.NoPos, pkg, "Deps", types.NewSlice(types.NewPointer(moduleType)), false),
		types.NewField(token.NoPos, pkg, "Settings", types.NewSlice(buildSettingType), false),
	}, nil)
	buildInfoType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "BuildInfo", nil),
		buildInfoStruct, nil)
	scope.Insert(buildInfoType.Obj())
	buildInfoPtr := types.NewPointer(buildInfoType)

	// BuildInfo.String() method
	buildInfoType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "bi", buildInfoPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Stack() []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Stack",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func PrintStack()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PrintStack",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func FreeOSMemory()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FreeOSMemory",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func SetGCPercent(percent int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetGCPercent",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "percent", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func SetMaxStack(bytes int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetMaxStack",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "bytes", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func SetMaxThreads(threads int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetMaxThreads",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "threads", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func SetPanicOnFault(enabled bool) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetPanicOnFault",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "enabled", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func SetTraceback(level string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetTraceback",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "level", types.Typ[types.String])),
			nil, false)))

	// func ReadBuildInfo() (*BuildInfo, bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadBuildInfo",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", buildInfoPtr),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// GCStats type
	// time.Duration is int64, time.Time is int64 stand-in
	gcStatsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "LastGC", types.Typ[types.Int64], false),    // time.Time
		types.NewField(token.NoPos, pkg, "NumGC", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "PauseTotal", types.Typ[types.Int64], false), // time.Duration
		types.NewField(token.NoPos, pkg, "Pause", types.NewSlice(types.Typ[types.Int64]), false), // []time.Duration
		types.NewField(token.NoPos, pkg, "PauseEnd", types.NewSlice(types.Typ[types.Int64]), false), // []time.Time
		types.NewField(token.NoPos, pkg, "PauseQuantiles", types.NewSlice(types.Typ[types.Int64]), false), // []time.Duration
	}, nil)
	gcStatsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "GCStats", nil),
		gcStatsStruct, nil)
	scope.Insert(gcStatsType.Obj())

	// func ReadGCStats(stats *GCStats)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadGCStats",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "stats", types.NewPointer(gcStatsType))),
			nil, false)))

	// func ParseBuildInfo(data string) (bi *BuildInfo, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseBuildInfo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", buildInfoPtr),
				types.NewVar(token.NoPos, pkg, "", types.Universe.Lookup("error").Type())),
			false)))

	// func SetMemoryLimit(limit int64) int64 — Go 1.19+
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetMemoryLimit",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "limit", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))

	// func WriteHeapDump(fd uintptr)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteHeapDump",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Uintptr])),
			nil, false)))

	// func SetCrashOutput(f *os.File, opts CrashOptions) error — Go 1.23+
	// Simplified with opaque *os.File stand-in
	errType := types.Universe.Lookup("error").Type()
	osFileStandin := types.NewPointer(types.NewStruct(nil, nil))
	crashOptsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CrashOptions", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(crashOptsType.Obj())
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetCrashOutput",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "f", osFileStandin),
				types.NewVar(token.NoPos, pkg, "opts", crashOptsType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildRuntimeMetricsPackage() *types.Package {
	pkg := types.NewPackage("runtime/metrics", "metrics")
	scope := pkg.Scope()

	// type Description struct { ... }
	descStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Description", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Kind", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Cumulative", types.Typ[types.Bool], false),
	}, nil)
	descType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Description", nil),
		descStruct, nil)
	scope.Insert(descType.Obj())

	// type ValueKind int
	valueKindType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ValueKind", nil),
		types.Typ[types.Int], nil)
	scope.Insert(valueKindType.Obj())

	// ValueKind constants
	for i, name := range []string{"KindBad", "KindUint64", "KindFloat64", "KindFloat64Histogram"} {
		scope.Insert(types.NewConst(token.NoPos, pkg, name, valueKindType, constant.MakeInt64(int64(i))))
	}

	// type Value struct { ... }
	valueStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "kind", valueKindType, false),
		types.NewField(token.NoPos, pkg, "scalar", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "pointer", types.Typ[types.Int], false),
	}, nil)
	valueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Value", nil),
		valueStruct, nil)
	scope.Insert(valueType.Obj())

	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Kind",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", valueType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueKindType)), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Uint64",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", valueType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", valueType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])), false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float64Histogram",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", valueType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))

	// type Float64Histogram struct { ... }
	histStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Counts", types.NewSlice(types.Typ[types.Uint64]), false),
		types.NewField(token.NoPos, pkg, "Buckets", types.NewSlice(types.Typ[types.Float64]), false),
	}, nil)
	histType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Float64Histogram", nil),
		histStruct, nil)
	scope.Insert(histType.Obj())

	// type Sample struct { Name string; Value Value }
	sampleStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", valueType, false),
	}, nil)
	sampleType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Sample", nil),
		sampleStruct, nil)
	scope.Insert(sampleType.Obj())

	// func All() []Description
	scope.Insert(types.NewFunc(token.NoPos, pkg, "All",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(descType))),
			false)))

	// func Read(m []Sample)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "m", types.NewSlice(sampleType))),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

// buildRuntimePackage creates the type-checked runtime package stub.
func buildRuntimePackage() *types.Package {
	pkg := types.NewPackage("runtime", "runtime")
	scope := pkg.Scope()

	// func GOMAXPROCS(n int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GOMAXPROCS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func SetDefaultGOMAXPROCS() (Go 1.25+)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetDefaultGOMAXPROCS",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func NumCPU() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NumCPU",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func NumGoroutine() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NumGoroutine",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Gosched()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Gosched",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func GC()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GC",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func Goexit()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Goexit",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// var GOOS string
	scope.Insert(types.NewVar(token.NoPos, pkg, "GOOS", types.Typ[types.String]))

	// var GOARCH string
	scope.Insert(types.NewVar(token.NoPos, pkg, "GOARCH", types.Typ[types.String]))

	// func Caller(skip int) (pc uintptr, file string, line int, ok bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Caller",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "skip", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pc", types.Typ[types.Uintptr]),
				types.NewVar(token.NoPos, pkg, "file", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "line", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "ok", types.Typ[types.Bool])),
			false)))

	// func Callers(skip int, pc []uintptr) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Callers",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "skip", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "pc", types.NewSlice(types.Typ[types.Uintptr]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func GOROOT() string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GOROOT",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Version() string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Version",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func SetFinalizer(obj any, finalizer any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetFinalizer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "obj", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "finalizer", types.NewInterfaceType(nil, nil))),
			nil, false)))

	// func KeepAlive(x any)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "KeepAlive",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", types.NewInterfaceType(nil, nil))),
			nil, false)))

	// func AddCleanup(ptr, cleanup, arg any) Cleanup (Go 1.24+)
	cleanupStruct := types.NewStruct(nil, nil)
	cleanupType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Cleanup", nil),
		cleanupStruct, nil)
	scope.Insert(cleanupType.Obj())
	cleanupType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stop",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", cleanupType), nil, nil, nil, nil, false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddCleanup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ptr", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "cleanup", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "arg", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", cleanupType)),
			false)))

	// func LockOSThread()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LockOSThread",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func UnlockOSThread()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UnlockOSThread",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func Stack(buf []byte, all bool) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Stack",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "all", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// type MemStats struct { ... }
	memStatsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Alloc", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "TotalAlloc", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Sys", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Lookups", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Mallocs", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Frees", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "HeapAlloc", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "HeapSys", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "HeapIdle", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "HeapInuse", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "HeapReleased", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "HeapObjects", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "NumGC", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "GCCPUFraction", types.Typ[types.Float64], false),
	}, nil)
	memStatsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "MemStats", nil),
		memStatsStruct, nil)
	scope.Insert(memStatsType.Obj())

	// func ReadMemStats(m *MemStats)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadMemStats",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "m", types.NewPointer(memStatsType))),
			nil, false)))

	// type Frame struct { PC uintptr; Func *Func; Function string; File string; Line int; Entry uintptr }
	// type Func struct {}
	funcStruct := types.NewStruct(nil, nil)
	funcType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Func", nil),
		funcStruct, nil)
	scope.Insert(funcType.Obj())
	funcPtr := types.NewPointer(funcType)

	funcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "f", funcPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	funcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Entry",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "f", funcPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uintptr])),
			false)))
	funcType.AddMethod(types.NewFunc(token.NoPos, pkg, "FileLine",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "f", funcPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "pc", types.Typ[types.Uintptr])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "file", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "line", types.Typ[types.Int])),
			false)))

	// func FuncForPC(pc uintptr) *Func
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FuncForPC",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "pc", types.Typ[types.Uintptr])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", funcPtr)),
			false)))

	// type Frames struct {}
	framesStruct := types.NewStruct(nil, nil)
	framesType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Frames", nil),
		framesStruct, nil)
	scope.Insert(framesType.Obj())
	framesPtr := types.NewPointer(framesType)

	frameStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "PC", types.Typ[types.Uintptr], false),
		types.NewField(token.NoPos, pkg, "Func", funcPtr, false),
		types.NewField(token.NoPos, pkg, "Function", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "File", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Entry", types.Typ[types.Uintptr], false),
	}, nil)
	frameType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Frame", nil),
		frameStruct, nil)
	scope.Insert(frameType.Obj())

	// (*Frames).Next() (frame Frame, more bool)
	framesType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "ci", framesPtr),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "frame", frameType),
				types.NewVar(token.NoPos, nil, "more", types.Typ[types.Bool])),
			false)))

	// func CallersFrames(callers []uintptr) *Frames
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CallersFrames",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "callers", types.NewSlice(types.Typ[types.Uintptr]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", framesPtr)),
			false)))

	// type Error interface { RuntimeError(); Error() string }
	runtimeErrorIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "RuntimeError",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, pkg, "Error",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
	}, nil)
	runtimeErrorIface.Complete()
	runtimeErrorType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Error", nil),
		runtimeErrorIface, nil)
	scope.Insert(runtimeErrorType.Obj())

	// Compiler variable
	scope.Insert(types.NewVar(token.NoPos, pkg, "Compiler", types.Typ[types.String]))

	// type BlockProfileRecord struct
	blockProfileRecordStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Count", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Cycles", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "StackRecord", types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Stack0", types.NewArray(types.Typ[types.Uintptr], 32), false),
		}, nil), true),
	}, nil)
	blockProfileRecordType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "BlockProfileRecord", nil),
		blockProfileRecordStruct, nil)
	scope.Insert(blockProfileRecordType.Obj())

	// type StackRecord struct { Stack0 [32]uintptr }
	stackRecordStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Stack0", types.NewArray(types.Typ[types.Uintptr], 32), false),
	}, nil)
	stackRecordType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "StackRecord", nil),
		stackRecordStruct, nil)
	scope.Insert(stackRecordType.Obj())
	stackRecordType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stack",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", types.NewPointer(stackRecordType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Uintptr]))),
			false)))

	// func BlockProfile(p []BlockProfileRecord) (n int, ok bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BlockProfile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(blockProfileRecordType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "ok", types.Typ[types.Bool])),
			false)))

	// func SetBlockProfileRate(rate int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetBlockProfileRate",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "rate", types.Typ[types.Int])),
			nil, false)))

	// func SetMutexProfileFraction(rate int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetMutexProfileFraction",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "rate", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func MutexProfile(p []BlockProfileRecord) (n int, ok bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MutexProfile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(blockProfileRecordType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "ok", types.Typ[types.Bool])),
			false)))

	// type MemProfileRecord struct
	memProfileRecordStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "AllocBytes", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "FreeBytes", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "AllocObjects", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "FreeObjects", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Stack0", types.NewArray(types.Typ[types.Uintptr], 32), false),
	}, nil)
	memProfileRecordType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "MemProfileRecord", nil),
		memProfileRecordStruct, nil)
	scope.Insert(memProfileRecordType.Obj())
	memProfileRecordType.AddMethod(types.NewFunc(token.NoPos, pkg, "InUseBytes",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", types.NewPointer(memProfileRecordType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	memProfileRecordType.AddMethod(types.NewFunc(token.NoPos, pkg, "InUseObjects",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", types.NewPointer(memProfileRecordType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	memProfileRecordType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stack",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "r", types.NewPointer(memProfileRecordType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.Uintptr]))),
			false)))

	// func MemProfile(p []MemProfileRecord, inuseZero bool) (n int, ok bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MemProfile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", types.NewSlice(memProfileRecordType)),
				types.NewVar(token.NoPos, pkg, "inuseZero", types.Typ[types.Bool])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "ok", types.Typ[types.Bool])),
			false)))

	// func GoroutineProfile(p []StackRecord) (n int, ok bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GoroutineProfile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(stackRecordType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "ok", types.Typ[types.Bool])),
			false)))

	// func SetCPUProfileRate(hz int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetCPUProfileRate",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "hz", types.Typ[types.Int])),
			nil, false)))

	// func CPUProfile() []byte (deprecated but still in API)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CPUProfile",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// func NumCgoCall() int64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NumCgoCall",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))

	// func ThreadCreateProfile(p []StackRecord) (n int, ok bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ThreadCreateProfile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(stackRecordType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "ok", types.Typ[types.Bool])),
			false)))

	// func Breakpoint()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Breakpoint",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// var MemProfileRate int
	scope.Insert(types.NewVar(token.NoPos, pkg, "MemProfileRate", types.Typ[types.Int]))

	pkg.MarkComplete()
	return pkg
}

func buildRuntimePprofPackage() *types.Package {
	pkg := types.NewPackage("runtime/pprof", "pprof")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlicePP := types.NewSlice(types.Typ[types.Byte])

	// io.Writer interface for WriteTo, StartCPUProfile, WriteHeapProfile
	ioWriterPP := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlicePP)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterPP.Complete()

	anyType := types.NewInterfaceType(nil, nil)
	anyType.Complete()

	// Profile type
	profileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	profileType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Profile", nil),
		profileStruct, nil)
	scope.Insert(profileType.Obj())
	profilePtr := types.NewPointer(profileType)

	// Profile.Name() string
	profileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "p", profilePtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Profile.Count() int
	profileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Count",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "p", profilePtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// Profile.Add(value any, skip int)
	profileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "p", profilePtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "value", anyType),
				types.NewVar(token.NoPos, pkg, "skip", types.Typ[types.Int])),
			nil, false)))

	// Profile.Remove(value any)
	profileType.AddMethod(types.NewFunc(token.NoPos, pkg, "Remove",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "p", profilePtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "value", anyType)),
			nil, false)))

	// Profile.WriteTo(w io.Writer, debug int) error
	profileType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteTo",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "p", profilePtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriterPP),
				types.NewVar(token.NoPos, pkg, "debug", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Lookup(name string) *Profile
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", profilePtr)),
			false)))

	// func NewProfile(name string) *Profile
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewProfile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", profilePtr)),
			false)))

	// func Profiles() []*Profile
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Profiles",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(profilePtr))),
			false)))

	// func StartCPUProfile(w io.Writer) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StartCPUProfile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterPP)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func StopCPUProfile()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StopCPUProfile",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func WriteHeapProfile(w io.Writer) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WriteHeapProfile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterPP)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// context.Context stand-in for label functions
	ctxIfacePP := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Deadline",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Done",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewChan(types.RecvOnly, types.NewStruct(nil, nil)))), false)),
		types.NewFunc(token.NoPos, nil, "Err",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Value",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyType)), false)),
	}, nil)
	ctxIfacePP.Complete()

	// type LabelSet struct{}
	labelSetType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "LabelSet", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(labelSetType.Obj())

	// func SetGoroutineLabels(ctx context.Context)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetGoroutineLabels",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ctx", ctxIfacePP)),
			nil, false)))

	// func Labels(args ...string) LabelSet
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Labels",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", labelSetType)),
			true))) // variadic

	// func Label(ctx context.Context, key string) (string, bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Label",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIfacePP),
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func ForLabels(ctx context.Context, fn func(key, value string) bool)
	forLabelsFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
			types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ForLabels",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIfacePP),
				types.NewVar(token.NoPos, pkg, "fn", forLabelsFn)),
			nil, false)))

	// func WithLabels(ctx context.Context, labels LabelSet) context.Context
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithLabels",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIfacePP),
				types.NewVar(token.NoPos, pkg, "labels", labelSetType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ctxIfacePP)),
			false)))

	// func Do(ctx context.Context, labels LabelSet, f func(context.Context))
	doFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", ctxIfacePP)),
		nil, false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Do",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIfacePP),
				types.NewVar(token.NoPos, pkg, "labels", labelSetType),
				types.NewVar(token.NoPos, pkg, "f", doFn)),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildRuntimeTracePackage() *types.Package {
	pkg := types.NewPackage("runtime/trace", "trace")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	// context.Context interface { Deadline() (int64, bool); Done() <-chan struct{}; Err() error; Value(key any) any }
	anyCtx := types.NewInterfaceType(nil, nil)
	anyCtx.Complete()
	ctxType := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Deadline",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "deadline", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
				false)),
		types.NewFunc(token.NoPos, nil, "Done",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "",
					types.NewChan(types.RecvOnly, types.NewStruct(nil, nil)))),
				false)),
		types.NewFunc(token.NoPos, nil, "Err",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Value",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyCtx)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyCtx)),
				false)),
	}, nil)
	ctxType.Complete()
	byteSliceTrace := types.NewSlice(types.Typ[types.Byte])

	// io.Writer interface for Start
	ioWriterTrace := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceTrace)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterTrace.Complete()

	// func Start(w io.Writer) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Start",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", ioWriterTrace)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func Stop()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Stop",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func IsEnabled() bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsEnabled",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))

	// type Task struct (opaque)
	taskType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Task", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(taskType.Obj())
	taskPtr := types.NewPointer(taskType)
	taskType.AddMethod(types.NewFunc(token.NoPos, pkg, "End",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "t", taskPtr), nil, nil, nil, nil, false)))

	// func NewTask(pctx context.Context, taskType string) (context.Context, *Task)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTask",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pctx", ctxType),
				types.NewVar(token.NoPos, pkg, "taskType", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ctxType),
				types.NewVar(token.NoPos, pkg, "", taskPtr)), false)))

	// type Region struct (opaque)
	regionType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Region", nil), types.NewStruct(nil, nil), nil)
	scope.Insert(regionType.Obj())
	regionPtr := types.NewPointer(regionType)
	regionType.AddMethod(types.NewFunc(token.NoPos, pkg, "End",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", regionPtr), nil, nil, nil, nil, false)))

	// func StartRegion(ctx context.Context, regionType string) *Region
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StartRegion",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "regionType", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", regionPtr)), false)))

	// func WithRegion(ctx context.Context, regionType string, fn func())
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithRegion",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "regionType", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "fn", types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			nil, false)))

	// func Log(ctx context.Context, category, message string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Log",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "category", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "message", types.Typ[types.String])),
			nil, false)))

	// func Logf(ctx context.Context, category, format string, args ...interface{})
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Logf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "category", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(types.NewInterfaceType(nil, nil)))),
			nil, true)))

	pkg.MarkComplete()
	return pkg
}

// buildSlicesPackage creates the type-checked slices package stub (Go 1.21+).
func buildSlicesPackage() *types.Package {
	pkg := types.NewPackage("slices", "slices")
	scope := pkg.Scope()

	// Note: slices functions are generic in real Go, but we stub them with
	// concrete types. The compiler handles type specialization at call sites.

	// func Contains[S ~[]E, E comparable](s S, v E) bool
	// Stubbed as Contains([]any, any) bool
	anySlice := types.NewSlice(types.NewInterfaceType(nil, nil))
	anyType := types.NewInterfaceType(nil, nil)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Contains",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Index[S ~[]E, E comparable](s S, v E) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Reverse[S ~[]E, E any](s S)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Reverse",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", anySlice)),
			nil, false)))

	// func Sort[S ~[]E, E cmp.Ordered](s S)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sort",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", anySlice)),
			nil, false)))

	// func Compact[S ~[]E, E comparable](s S) S
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compact",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func Equal[S ~[]E, E comparable](s1, s2 S) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s1", anySlice),
				types.NewVar(token.NoPos, pkg, "s2", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Clone[S ~[]E, E any](s S) S
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func Clip[S ~[]E, E any](s S) S
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Clip",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func Grow[S ~[]E, E any](s S, n int) S
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Grow",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func Concat[S ~[]E, E any](slices ...S) S
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Concat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "slices", types.NewSlice(anySlice))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			true)))

	// func Delete[S ~[]E, E any](s S, i, j int) S
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Delete",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "j", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func Insert[S ~[]E, E any](s S, i int, v ...E) S
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Insert",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "v", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			true)))

	// func Replace[S ~[]E, E any](s S, i, j int, v ...E) S
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Replace",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "j", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "v", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			true)))

	// func IsSorted[S ~[]E, E cmp.Ordered](s S) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsSorted",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Min[S ~[]E, E cmp.Ordered](s S) E
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Min",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func Max[S ~[]E, E cmp.Ordered](s S) E
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Max",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func BinarySearch[S ~[]E, E cmp.Ordered](s S, target E) (int, bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BinarySearch",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "target", anyType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// Func-parameterized variants (use func(E,E) types)
	cmpFunc := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "a", anyType),
			types.NewVar(token.NoPos, nil, "b", anyType)),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
		false)
	boolFunc := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "v", anyType)),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
		false)

	// func SortFunc[S ~[]E, E any](s S, cmp func(a, b E) int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SortFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "cmp", cmpFunc)),
			nil, false)))

	// func SortStableFunc[S ~[]E, E any](s S, cmp func(a, b E) int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SortStableFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "cmp", cmpFunc)),
			nil, false)))

	// func IsSortedFunc[S ~[]E, E any](s S, cmp func(a, b E) int) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsSortedFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "cmp", cmpFunc)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func BinarySearchFunc[S ~[]E, E, T any](s S, target T, cmp func(E, T) int) (int, bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BinarySearchFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "target", anyType),
				types.NewVar(token.NoPos, pkg, "cmp", cmpFunc)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func ContainsFunc[S ~[]E, E any](s S, f func(E) bool) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ContainsFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "f", boolFunc)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IndexFunc[S ~[]E, E any](s S, f func(E) bool) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IndexFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "f", boolFunc)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func DeleteFunc[S ~[]E, E any](s S, del func(E) bool) S
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DeleteFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "del", boolFunc)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func CompactFunc[S ~[]E, E any](s S, eq func(E, E) bool) S
	eqFunc := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "a", anyType),
			types.NewVar(token.NoPos, nil, "b", anyType)),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CompactFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "eq", eqFunc)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func EqualFunc[S1 ~[]E1, S2 ~[]E2, E1, E2 any](s1 S1, s2 S2, eq func(E1, E2) bool) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EqualFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s1", anySlice),
				types.NewVar(token.NoPos, pkg, "s2", anySlice),
				types.NewVar(token.NoPos, pkg, "eq", eqFunc)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Compare[S ~[]E, E cmp.Ordered](s1, s2 S) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s1", anySlice),
				types.NewVar(token.NoPos, pkg, "s2", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func CompareFunc[S1 ~[]E1, S2 ~[]E2, E1, E2 any](s1 S1, s2 S2, cmp func(E1, E2) int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CompareFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s1", anySlice),
				types.NewVar(token.NoPos, pkg, "s2", anySlice),
				types.NewVar(token.NoPos, pkg, "cmp", cmpFunc)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func MinFunc[S ~[]E, E any](s S, cmp func(a, b E) int) E
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MinFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "cmp", cmpFunc)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func MaxFunc[S ~[]E, E any](s S, cmp func(a, b E) int) E
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MaxFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "cmp", cmpFunc)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func Repeat[S ~[]E, E any](s S, count int) S
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Repeat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "count", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func Chunk[S ~[]E, E any](s S, n int) iter.Seq[S]
	// Simplified: returns a function type
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chunk",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func All[S ~[]E, E any](s S) iter.Seq2[int, E]
	scope.Insert(types.NewFunc(token.NoPos, pkg, "All",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func Values[S ~[]E, E any](s S) iter.Seq[E]
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Values",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func Backward[S ~[]E, E any](s S) iter.Seq2[int, E]
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Backward",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anyType)),
			false)))

	// func Collect[E any](seq iter.Seq[E]) []E
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Collect",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seq", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func AppendSeq[S ~[]E, E any](s S, seq iter.Seq[E]) S
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendSeq",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", anySlice),
				types.NewVar(token.NoPos, pkg, "seq", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func Sorted[E cmp.Ordered](seq iter.Seq[E]) []E
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Sorted",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "seq", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func SortedFunc[E any](seq iter.Seq[E], cmp func(a, b E) int) []E
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SortedFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "seq", anyType),
				types.NewVar(token.NoPos, pkg, "cmp", cmpFunc)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	// func SortedStableFunc[E any](seq iter.Seq[E], cmp func(a, b E) int) []E
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SortedStableFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "seq", anyType),
				types.NewVar(token.NoPos, pkg, "cmp", cmpFunc)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", anySlice)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildStructsPackage() *types.Package {
	pkg := types.NewPackage("structs", "structs")
	scope := pkg.Scope()

	// type HostLayout struct{}
	hostLayoutType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "HostLayout", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(hostLayoutType.Obj())

	pkg.MarkComplete()
	return pkg
}

// buildSyncAtomicPackage creates the type-checked sync/atomic package stub.
func buildSyncAtomicPackage() *types.Package {
	pkg := types.NewPackage("sync/atomic", "atomic")
	scope := pkg.Scope()

	// func AddInt32(addr *int32, delta int32) int32
	int32Ptr := types.NewPointer(types.Typ[types.Int32])
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddInt32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", int32Ptr),
				types.NewVar(token.NoPos, pkg, "delta", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))

	// func AddInt64(addr *int64, delta int64) int64
	int64Ptr := types.NewPointer(types.Typ[types.Int64])
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddInt64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", int64Ptr),
				types.NewVar(token.NoPos, pkg, "delta", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))

	// func LoadInt32(addr *int32) int32
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LoadInt32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", int32Ptr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))

	// func LoadInt64(addr *int64) int64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LoadInt64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", int64Ptr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))

	// func StoreInt32(addr *int32, val int32)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StoreInt32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", int32Ptr),
				types.NewVar(token.NoPos, pkg, "val", types.Typ[types.Int32])),
			nil, false)))

	// func StoreInt64(addr *int64, val int64)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StoreInt64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", int64Ptr),
				types.NewVar(token.NoPos, pkg, "val", types.Typ[types.Int64])),
			nil, false)))

	// func CompareAndSwapInt32(addr *int32, old, new int32) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CompareAndSwapInt32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", int32Ptr),
				types.NewVar(token.NoPos, pkg, "old", types.Typ[types.Int32]),
				types.NewVar(token.NoPos, pkg, "new_", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func CompareAndSwapInt64(addr *int64, old, new int64) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CompareAndSwapInt64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", int64Ptr),
				types.NewVar(token.NoPos, pkg, "old", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "new_", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// uint variants
	uint32Ptr := types.NewPointer(types.Typ[types.Uint32])
	uint64Ptr := types.NewPointer(types.Typ[types.Uint64])
	uintptrPtr := types.NewPointer(types.Typ[types.Uintptr])

	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddUint32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uint32Ptr),
				types.NewVar(token.NoPos, pkg, "delta", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddUint64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uint64Ptr),
				types.NewVar(token.NoPos, pkg, "delta", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddUintptr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uintptrPtr),
				types.NewVar(token.NoPos, pkg, "delta", types.Typ[types.Uintptr])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uintptr])),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "LoadUint32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", uint32Ptr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LoadUint64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", uint64Ptr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LoadUintptr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", uintptrPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uintptr])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LoadPointer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", types.NewPointer(types.Typ[types.UnsafePointer]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.UnsafePointer])),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "StoreUint32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uint32Ptr),
				types.NewVar(token.NoPos, pkg, "val", types.Typ[types.Uint32])),
			nil, false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StoreUint64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uint64Ptr),
				types.NewVar(token.NoPos, pkg, "val", types.Typ[types.Uint64])),
			nil, false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StoreUintptr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uintptrPtr),
				types.NewVar(token.NoPos, pkg, "val", types.Typ[types.Uintptr])),
			nil, false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StorePointer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", types.NewPointer(types.Typ[types.UnsafePointer])),
				types.NewVar(token.NoPos, pkg, "val", types.Typ[types.UnsafePointer])),
			nil, false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "SwapInt32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", int32Ptr),
				types.NewVar(token.NoPos, pkg, "new_", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SwapInt64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", int64Ptr),
				types.NewVar(token.NoPos, pkg, "new_", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SwapUint32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uint32Ptr),
				types.NewVar(token.NoPos, pkg, "new_", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SwapUint64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uint64Ptr),
				types.NewVar(token.NoPos, pkg, "new_", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SwapUintptr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uintptrPtr),
				types.NewVar(token.NoPos, pkg, "new_", types.Typ[types.Uintptr])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uintptr])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SwapPointer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", types.NewPointer(types.Typ[types.UnsafePointer])),
				types.NewVar(token.NoPos, pkg, "new_", types.Typ[types.UnsafePointer])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.UnsafePointer])),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "CompareAndSwapUint32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uint32Ptr),
				types.NewVar(token.NoPos, pkg, "old", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, pkg, "new_", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CompareAndSwapUint64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uint64Ptr),
				types.NewVar(token.NoPos, pkg, "old", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, pkg, "new_", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CompareAndSwapUintptr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uintptrPtr),
				types.NewVar(token.NoPos, pkg, "old", types.Typ[types.Uintptr]),
				types.NewVar(token.NoPos, pkg, "new_", types.Typ[types.Uintptr])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CompareAndSwapPointer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", types.NewPointer(types.Typ[types.UnsafePointer])),
				types.NewVar(token.NoPos, pkg, "old", types.Typ[types.UnsafePointer]),
				types.NewVar(token.NoPos, pkg, "new_", types.Typ[types.UnsafePointer])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// type Value struct {}
	valueStruct := types.NewStruct(nil, nil)
	valueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Value", nil),
		valueStruct, nil)
	scope.Insert(valueType.Obj())
	valuePtr := types.NewPointer(valueType)
	vRecv := types.NewVar(token.NoPos, nil, "v", valuePtr)
	anyType := types.NewInterfaceType(nil, nil)
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Load",
		types.NewSignatureType(vRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", anyType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Store",
		types.NewSignatureType(vRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "val", anyType)),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(vRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "new_", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", anyType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "CompareAndSwap",
		types.NewSignatureType(vRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "old", anyType),
				types.NewVar(token.NoPos, nil, "new_", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// type Bool struct {}
	boolStruct := types.NewStruct(nil, nil)
	boolType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Bool", nil),
		boolStruct, nil)
	scope.Insert(boolType.Obj())
	boolPtr := types.NewPointer(boolType)
	bRecv := types.NewVar(token.NoPos, nil, "x", boolPtr)
	boolType.AddMethod(types.NewFunc(token.NoPos, pkg, "Load",
		types.NewSignatureType(bRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	boolType.AddMethod(types.NewFunc(token.NoPos, pkg, "Store",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "val", types.Typ[types.Bool])),
			nil, false)))
	boolType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	boolType.AddMethod(types.NewFunc(token.NoPos, pkg, "CompareAndSwap",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "old", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// type Int32 struct {}
	int32AtomicStruct := types.NewStruct(nil, nil)
	int32AtomicType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Int32", nil),
		int32AtomicStruct, nil)
	scope.Insert(int32AtomicType.Obj())
	int32AtomicPtr := types.NewPointer(int32AtomicType)
	i32Recv := types.NewVar(token.NoPos, nil, "x", int32AtomicPtr)
	int32AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Load",
		types.NewSignatureType(i32Recv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int32])),
			false)))
	int32AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Store",
		types.NewSignatureType(i32Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "val", types.Typ[types.Int32])),
			nil, false)))
	int32AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(i32Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int32])),
			false)))
	int32AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(i32Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int32])),
			false)))
	int32AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "CompareAndSwap",
		types.NewSignatureType(i32Recv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "old", types.Typ[types.Int32]),
				types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// type Int64 struct {}
	int64AtomicStruct := types.NewStruct(nil, nil)
	int64AtomicType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Int64", nil),
		int64AtomicStruct, nil)
	scope.Insert(int64AtomicType.Obj())
	int64AtomicPtr := types.NewPointer(int64AtomicType)
	i64Recv := types.NewVar(token.NoPos, nil, "x", int64AtomicPtr)
	int64AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Load",
		types.NewSignatureType(i64Recv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	int64AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Store",
		types.NewSignatureType(i64Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "val", types.Typ[types.Int64])),
			nil, false)))
	int64AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(i64Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	int64AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(i64Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	int64AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "CompareAndSwap",
		types.NewSignatureType(i64Recv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "old", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// type Uint32 struct {}
	uint32AtomicType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Uint32", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(uint32AtomicType.Obj())
	u32AtomicPtr := types.NewPointer(uint32AtomicType)
	u32Recv := types.NewVar(token.NoPos, nil, "x", u32AtomicPtr)
	uint32AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Load",
		types.NewSignatureType(u32Recv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)))
	uint32AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Store",
		types.NewSignatureType(u32Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "val", types.Typ[types.Uint32])),
			nil, false)))
	uint32AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(u32Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)))
	uint32AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(u32Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)))
	uint32AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "CompareAndSwap",
		types.NewSignatureType(u32Recv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "old", types.Typ[types.Uint32]),
				types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	uint32AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "And",
		types.NewSignatureType(u32Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "mask", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)))
	uint32AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Or",
		types.NewSignatureType(u32Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "mask", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint32])), false)))

	// type Uint64 struct {}
	uint64AtomicType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Uint64", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(uint64AtomicType.Obj())
	u64AtomicPtr := types.NewPointer(uint64AtomicType)
	u64Recv := types.NewVar(token.NoPos, nil, "x", u64AtomicPtr)
	uint64AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Load",
		types.NewSignatureType(u64Recv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))
	uint64AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Store",
		types.NewSignatureType(u64Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "val", types.Typ[types.Uint64])),
			nil, false)))
	uint64AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(u64Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))
	uint64AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(u64Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))
	uint64AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "CompareAndSwap",
		types.NewSignatureType(u64Recv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "old", types.Typ[types.Uint64]),
				types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	uint64AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "And",
		types.NewSignatureType(u64Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "mask", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))
	uint64AtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Or",
		types.NewSignatureType(u64Recv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "mask", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint64])), false)))

	// type Uintptr struct {}
	uintptrAtomicType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Uintptr", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(uintptrAtomicType.Obj())
	upAtomicPtr := types.NewPointer(uintptrAtomicType)
	upRecv := types.NewVar(token.NoPos, nil, "x", upAtomicPtr)
	uintptrAtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Load",
		types.NewSignatureType(upRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uintptr])), false)))
	uintptrAtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Store",
		types.NewSignatureType(upRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "val", types.Typ[types.Uintptr])),
			nil, false)))
	uintptrAtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(upRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "delta", types.Typ[types.Uintptr])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uintptr])), false)))
	uintptrAtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(upRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Uintptr])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uintptr])), false)))
	uintptrAtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "CompareAndSwap",
		types.NewSignatureType(upRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "old", types.Typ[types.Uintptr]),
				types.NewVar(token.NoPos, nil, "new_", types.Typ[types.Uintptr])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// type Pointer[T any] struct {} — simplified
	pointerAtomicType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Pointer", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(pointerAtomicType.Obj())
	pAtomicPtr := types.NewPointer(pointerAtomicType)
	pRecv := types.NewVar(token.NoPos, nil, "x", pAtomicPtr)
	ptrType := types.Typ[types.UnsafePointer]
	pointerAtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Load",
		types.NewSignatureType(pRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ptrType)), false)))
	pointerAtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Store",
		types.NewSignatureType(pRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "val", ptrType)),
			nil, false)))
	pointerAtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "Swap",
		types.NewSignatureType(pRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "new_", ptrType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ptrType)), false)))
	pointerAtomicType.AddMethod(types.NewFunc(token.NoPos, pkg, "CompareAndSwap",
		types.NewSignatureType(pRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "old", ptrType),
				types.NewVar(token.NoPos, nil, "new_", ptrType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// And/Or functions — Go 1.23+
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AndInt32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", int32Ptr),
				types.NewVar(token.NoPos, pkg, "mask", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OrInt32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", int32Ptr),
				types.NewVar(token.NoPos, pkg, "mask", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AndInt64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", int64Ptr),
				types.NewVar(token.NoPos, pkg, "mask", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OrInt64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", int64Ptr),
				types.NewVar(token.NoPos, pkg, "mask", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AndUint32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uint32Ptr),
				types.NewVar(token.NoPos, pkg, "mask", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OrUint32",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uint32Ptr),
				types.NewVar(token.NoPos, pkg, "mask", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint32])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AndUint64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uint64Ptr),
				types.NewVar(token.NoPos, pkg, "mask", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OrUint64",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uint64Ptr),
				types.NewVar(token.NoPos, pkg, "mask", types.Typ[types.Uint64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint64])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AndUintptr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uintptrPtr),
				types.NewVar(token.NoPos, pkg, "mask", types.Typ[types.Uintptr])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uintptr])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OrUintptr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", uintptrPtr),
				types.NewVar(token.NoPos, pkg, "mask", types.Typ[types.Uintptr])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uintptr])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildSyncErrgroupPackage() *types.Package {
	pkg := types.NewPackage("sync/errgroup", "errgroup")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Group struct
	groupType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Group", nil), types.NewStruct(nil, nil), nil)
	groupPtr := types.NewPointer(groupType)
	scope.Insert(groupType.Obj())

	groupRecv := types.NewVar(token.NoPos, pkg, "g", groupPtr)

	// func (g *Group) Go(f func() error)
	groupType.AddMethod(types.NewFunc(token.NoPos, pkg, "Go",
		types.NewSignatureType(groupRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
					false))),
			nil, false)))

	// func (g *Group) Wait() error
	groupType.AddMethod(types.NewFunc(token.NoPos, pkg, "Wait",
		types.NewSignatureType(groupRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (g *Group) SetLimit(n int)
	groupType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetLimit",
		types.NewSignatureType(groupRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			nil, false)))

	// func (g *Group) TryGo(f func() error) bool
	groupType.AddMethod(types.NewFunc(token.NoPos, pkg, "TryGo",
		types.NewSignatureType(groupRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
					false))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func WithContext(ctx context.Context) (*Group, context.Context)
	// context.Context stand-in { Deadline(); Done(); Err(); Value() }
	anyCtxEG := types.NewInterfaceType(nil, nil)
	anyCtxEG.Complete()
	ctxType := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Deadline",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "deadline", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
				false)),
		types.NewFunc(token.NoPos, nil, "Done",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "",
					types.NewChan(types.RecvOnly, types.NewStruct(nil, nil)))),
				false)),
		types.NewFunc(token.NoPos, nil, "Err",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Value",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyCtxEG)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyCtxEG)),
				false)),
	}, nil)
	ctxType.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithContext",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ctx", ctxType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", groupPtr),
				types.NewVar(token.NoPos, pkg, "", ctxType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildSyscallJSPackage() *types.Package {
	pkg := types.NewPackage("syscall/js", "js")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	emptyIface := types.NewInterfaceType(nil, nil)
	emptyIface.Complete()

	// type Type int
	typeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Type", nil),
		types.Typ[types.Int], nil)
	scope.Insert(typeType.Obj())

	typeRecv := types.NewVar(token.NoPos, pkg, "", typeType)
	typeType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(typeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Type constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeUndefined", typeType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeNull", typeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeBoolean", typeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeNumber", typeType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeString", typeType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeSymbol", typeType, constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeObject", typeType, constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TypeFunction", typeType, constant.MakeInt64(7)))

	// type Value struct — opaque
	valueStruct := types.NewStruct(nil, nil)
	valueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Value", nil),
		valueStruct, nil)
	scope.Insert(valueType.Obj())

	valueRecv := types.NewVar(token.NoPos, pkg, "", valueType)
	anySlice := types.NewSlice(emptyIface)

	// Value methods
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bool",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Float",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Int",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Truthy",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsNull",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsUndefined",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsNaN",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Type",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", typeType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "x", emptyIface)),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Delete",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.Typ[types.String])),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetIndex",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "i", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "x", emptyIface)),
			nil, false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Length",
		types.NewSignatureType(valueRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Call",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "m", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			true)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Invoke",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			true)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", anySlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			true)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	valueType.AddMethod(types.NewFunc(token.NoPos, pkg, "InstanceOf",
		types.NewSignatureType(valueRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "t", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// type Error struct { Value Value }
	errorStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Value", valueType, false),
	}, nil)
	errorType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Error", nil),
		errorStruct, nil)
	scope.Insert(errorType.Obj())

	errorPtrRecv := types.NewVar(token.NoPos, pkg, "", types.NewPointer(errorType))
	errorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(errorPtrRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// type ValueError struct — opaque
	valueErrorStruct := types.NewStruct(nil, nil)
	valueErrorType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ValueError", nil),
		valueErrorStruct, nil)
	scope.Insert(valueErrorType.Obj())

	valueErrorPtrRecv := types.NewVar(token.NoPos, pkg, "", types.NewPointer(valueErrorType))
	valueErrorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(valueErrorPtrRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// type Func struct — opaque
	funcStruct := types.NewStruct(nil, nil)
	funcType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Func", nil),
		funcStruct, nil)
	scope.Insert(funcType.Obj())

	funcRecv := types.NewVar(token.NoPos, pkg, "", funcType)
	funcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Release",
		types.NewSignatureType(funcRecv, nil, nil, nil, nil, false)))

	// func FuncOf(fn func(this Value, args []Value) any) Func
	valueSlice := types.NewSlice(valueType)
	fnType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, pkg, "this", valueType),
			types.NewVar(token.NoPos, pkg, "args", valueSlice)),
		types.NewTuple(types.NewVar(token.NoPos, pkg, "", emptyIface)),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FuncOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fn", fnType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", funcType)),
			false)))

	// func Global() Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Global",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func Null() Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Null",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func Undefined() Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Undefined",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func ValueOf(x any) Value
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ValueOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "x", emptyIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valueType)),
			false)))

	// func CopyBytesToGo(dst []byte, src Value) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CopyBytesToGo",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", byteSlice),
				types.NewVar(token.NoPos, pkg, "src", valueType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func CopyBytesToJS(dst Value, src []byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CopyBytesToJS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dst", valueType),
				types.NewVar(token.NoPos, pkg, "src", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildSyscallPackage() *types.Package {
	pkg := types.NewPackage("syscall", "syscall")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()

	// type Errno uintptr — implements error
	errnoType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Errno", nil),
		types.Typ[types.Uintptr], nil)
	scope.Insert(errnoType.Obj())

	// type Signal int
	signalType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Signal", nil),
		types.Typ[types.Int], nil)
	scope.Insert(signalType.Obj())

	// Errno methods
	errnoRecv := types.NewVar(token.NoPos, nil, "e", errnoType)
	errnoType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(errnoRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	errnoType.AddMethod(types.NewFunc(token.NoPos, pkg, "Is",
		types.NewSignatureType(errnoRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "target", errType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	errnoType.AddMethod(types.NewFunc(token.NoPos, pkg, "Temporary",
		types.NewSignatureType(errnoRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	errnoType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(errnoRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// Signal methods
	sigRecv := types.NewVar(token.NoPos, nil, "s", signalType)
	signalType.AddMethod(types.NewFunc(token.NoPos, pkg, "Signal",
		types.NewSignatureType(sigRecv, nil, nil, nil, nil, false)))
	signalType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(sigRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Credential struct { Uid, Gid uint32; Groups []uint32; NoSetGroups bool }
	credentialStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Uid", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Gid", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Groups", types.NewSlice(types.Typ[types.Uint32]), false),
		types.NewField(token.NoPos, pkg, "NoSetGroups", types.Typ[types.Bool], false),
	}, nil)
	credentialType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Credential", nil),
		credentialStruct, nil)
	scope.Insert(credentialType.Obj())

	// type SysProcAttr struct { ... }
	sysProcAttrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Chroot", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Credential", types.NewPointer(credentialType), false),
		types.NewField(token.NoPos, pkg, "Ptrace", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Setsid", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Setpgid", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Setctty", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Noctty", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Ctty", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Foreground", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Pgid", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Pdeathsig", signalType, false),
		types.NewField(token.NoPos, pkg, "Cloneflags", types.Typ[types.Uintptr], false),
		types.NewField(token.NoPos, pkg, "UidMappings", types.NewSlice(types.NewStruct(nil, nil)), false),
		types.NewField(token.NoPos, pkg, "GidMappings", types.NewSlice(types.NewStruct(nil, nil)), false),
		types.NewField(token.NoPos, pkg, "GidMappingsEnableSetgroups", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "AmbientCaps", types.NewSlice(types.Typ[types.Uintptr]), false),
	}, nil)
	sysProcAttrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SysProcAttr", nil),
		sysProcAttrStruct, nil)
	scope.Insert(sysProcAttrType.Obj())

	// type WaitStatus uint32
	waitStatusType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WaitStatus", nil),
		types.Typ[types.Uint32], nil)
	scope.Insert(waitStatusType.Obj())
	wsRecv := types.NewVar(token.NoPos, nil, "w", waitStatusType)
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "Exited",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExitStatus",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "Signaled",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "Signal",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", signalType)), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stopped",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "StopSignal",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", signalType)), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "CoreDump",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "Continued",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	waitStatusType.AddMethod(types.NewFunc(token.NoPos, pkg, "TrapCause",
		types.NewSignatureType(wsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// type Rusage struct (simplified)
	rusageStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Utime", types.NewStruct(nil, nil), false),
		types.NewField(token.NoPos, pkg, "Stime", types.NewStruct(nil, nil), false),
		types.NewField(token.NoPos, pkg, "Maxrss", types.Typ[types.Int64], false),
	}, nil)
	rusageType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Rusage", nil),
		rusageStruct, nil)
	scope.Insert(rusageType.Obj())

	// type ProcAttr struct
	procAttrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dir", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Env", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Files", types.NewSlice(types.Typ[types.Uintptr]), false),
		types.NewField(token.NoPos, pkg, "Sys", types.NewPointer(sysProcAttrType), false),
	}, nil)
	procAttrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ProcAttr", nil),
		procAttrStruct, nil)
	scope.Insert(procAttrType.Obj())

	// type SysProcIDMap struct { ContainerID, HostID, Size int }
	idmapStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ContainerID", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "HostID", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Int], false),
	}, nil)
	idmapType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SysProcIDMap", nil),
		idmapStruct, nil)
	scope.Insert(idmapType.Obj())

	// Error constants
	scope.Insert(types.NewVar(token.NoPos, pkg, "EINVAL", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENOENT", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EEXIST", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EPERM", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EACCES", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EAGAIN", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENOSYS", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENOTDIR", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EISDIR", errnoType))

	// Signal constants
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGINT", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGTERM", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGKILL", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGHUP", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGPIPE", signalType))

	// Constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_RDONLY", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_WRONLY", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_RDWR", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_CREAT", types.Typ[types.Int], constant.MakeInt64(0100)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_TRUNC", types.Typ[types.Int], constant.MakeInt64(01000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_APPEND", types.Typ[types.Int], constant.MakeInt64(02000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_EXCL", types.Typ[types.Int], constant.MakeInt64(0200)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_SYNC", types.Typ[types.Int], constant.MakeInt64(04010000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_NONBLOCK", types.Typ[types.Int], constant.MakeInt64(04000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "O_CLOEXEC", types.Typ[types.Int], constant.MakeInt64(02000000)))

	scope.Insert(types.NewConst(token.NoPos, pkg, "STDIN_FILENO", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "STDOUT_FILENO", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "STDERR_FILENO", types.Typ[types.Int], constant.MakeInt64(2)))

	// func Getenv(key string) (value string, found bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getenv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "found", types.Typ[types.Bool])),
			false)))

	// func Getpid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getpid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getuid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getgid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func Exit(code int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Exit",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "code", types.Typ[types.Int])),
			nil, false)))

	// func Open(path string, mode int, perm uint32) (fd int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "perm", types.Typ[types.Uint32])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func Close(fd int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Read(fd int, p []byte) (n int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func Write(fd int, p []byte) (n int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// Additional error codes
	scope.Insert(types.NewVar(token.NoPos, pkg, "EBUSY", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENODEV", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENOMEM", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EFAULT", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EBADF", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ERANGE", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ECONNRESET", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ECONNREFUSED", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ECONNABORTED", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ETIMEDOUT", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EADDRINUSE", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EADDRNOTAVAIL", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENETUNREACH", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EPIPE", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENOTSOCK", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EINTR", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ENFILE", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EMFILE", errnoType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "EAFNOSUPPORT", errnoType))

	// Additional signal constants
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGQUIT", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGABRT", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGALRM", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGUSR1", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGUSR2", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGCHLD", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGCONT", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGSTOP", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGTSTP", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGTTIN", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGTTOU", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGURG", signalType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "SIGWINCH", signalType))

	// Socket constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "AF_UNIX", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AF_INET", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AF_INET6", types.Typ[types.Int], constant.MakeInt64(10)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SOCK_STREAM", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SOCK_DGRAM", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SOCK_RAW", types.Typ[types.Int], constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "IPPROTO_TCP", types.Typ[types.Int], constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "IPPROTO_UDP", types.Typ[types.Int], constant.MakeInt64(17)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SOL_SOCKET", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SO_REUSEADDR", types.Typ[types.Int], constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SO_KEEPALIVE", types.Typ[types.Int], constant.MakeInt64(9)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TCP_NODELAY", types.Typ[types.Int], constant.MakeInt64(1)))

	// File mode constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFMT", types.Typ[types.Uint32], constant.MakeInt64(0170000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFREG", types.Typ[types.Uint32], constant.MakeInt64(0100000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFDIR", types.Typ[types.Uint32], constant.MakeInt64(040000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFLNK", types.Typ[types.Uint32], constant.MakeInt64(0120000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFCHR", types.Typ[types.Uint32], constant.MakeInt64(020000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFBLK", types.Typ[types.Uint32], constant.MakeInt64(060000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFIFO", types.Typ[types.Uint32], constant.MakeInt64(010000)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "S_IFSOCK", types.Typ[types.Uint32], constant.MakeInt64(0140000)))

	// Wait constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "WNOHANG", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "WUNTRACED", types.Typ[types.Int], constant.MakeInt64(2)))

	// type Stat_t struct (simplified)
	statStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Dev", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Ino", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Mode", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Nlink", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Uid", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Gid", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "Rdev", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Size", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Blksize", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Blocks", types.Typ[types.Int64], false),
	}, nil)
	statType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Stat_t", nil),
		statStruct, nil)
	scope.Insert(statType.Obj())

	// type Sockaddr interface
	sockaddrIface := types.NewInterfaceType(nil, nil)
	sockaddrIface.Complete()

	// type RawSockaddrAny struct
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "RawSockaddrAny",
		types.NewStruct(nil, nil)))

	// func Stat(path string, stat *Stat_t) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Stat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "stat", types.NewPointer(statType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Lstat(path string, stat *Stat_t) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Lstat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "stat", types.NewPointer(statType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Fstat(fd int, stat *Stat_t) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fstat",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "stat", types.NewPointer(statType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func Mkdir(path string, mode uint32) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Mkdir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Rmdir(path string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Rmdir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Unlink(path string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unlink",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Rename(oldpath, newpath string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Rename",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "oldpath", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "newpath", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Link(oldpath, newpath string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Link",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "oldpath", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "newpath", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Symlink(oldpath, newpath string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Symlink",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "oldpath", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "newpath", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Readlink(path string, buf []byte) (n int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Readlink",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "buf", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Chmod(path string, mode uint32) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chmod",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "mode", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Chown(path string, uid, gid int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chown",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "uid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "gid", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Fchmod(fd int, mode uint32) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fchmod",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "mode", types.Typ[types.Uint32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Fchown(fd int, uid, gid int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Fchown",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "uid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "gid", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Ftruncate(fd int, length int64) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Ftruncate",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "length", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Truncate(path string, length int64) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Truncate",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "length", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Seek(fd int, offset int64, whence int) (off int64, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Seek",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "offset", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "whence", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "off", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Dup(oldfd int) (fd int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dup",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "oldfd", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Dup2(oldfd, newfd int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dup2",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "oldfd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "newfd", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Pipe(p []int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pipe",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Int]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Socket(domain, typ, proto int) (fd int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Socket",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "domain", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "typ", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "proto", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Bind(fd int, sa Sockaddr) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Bind",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "sa", sockaddrIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Listen(s int, backlog int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Listen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "s", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "backlog", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Accept(fd int) (nfd int, sa Sockaddr, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Accept",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "nfd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "sa", sockaddrIface),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Connect(fd int, sa Sockaddr) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Connect",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "sa", sockaddrIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Setsockopt(fd, level, opt int, value unsafe.Pointer, vallen uintptr) error — simplified
	// func SetsockoptInt(fd, level, opt int, value int) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetsockoptInt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "level", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "opt", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func GetsockoptInt(fd, level, opt int) (value int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "GetsockoptInt",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fd", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "level", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "opt", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Getwd() (dir string, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getwd",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Chdir(path string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Chdir",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Umask(mask int) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Umask",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "mask", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	// func Kill(pid int, sig Signal) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Kill",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "sig", signalType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Wait4(pid int, wstatus *WaitStatus, options int, rusage *Rusage) (wpid int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Wait4",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "wstatus", types.NewPointer(waitStatusType)),
				types.NewVar(token.NoPos, pkg, "options", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "rusage", types.NewPointer(rusageType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "wpid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func Geteuid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Geteuid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	// func Getegid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getegid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	// func Getppid() int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getppid",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	// func Getgroups() ([]int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Getgroups",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Int])),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Setenv(key, value string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Setenv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Unsetenv(key string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Unsetenv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func Clearenv()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Clearenv",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))
	// func Environ() []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Environ",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))), false)))
	// func Exec(argv0 string, argv []string, envv []string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Exec",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "argv0", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "argv", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "envv", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func ForkExec(argv0 string, argv []string, attr *ProcAttr) (pid int, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ForkExec",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "argv0", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "argv", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "attr", types.NewPointer(procAttrType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))
	// func StartProcess(argv0 string, argv []string, attr *ProcAttr) (pid int, handle uintptr, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StartProcess",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "argv0", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "argv", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "attr", types.NewPointer(procAttrType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pid", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "handle", types.Typ[types.Uintptr]),
				types.NewVar(token.NoPos, pkg, "err", errType)), false)))

	// type SyscallError struct { Syscall string; Err error }
	syscallErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Syscall", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	syscallErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SyscallError", nil),
		syscallErrStruct, nil)
	scope.Insert(syscallErrType.Obj())
	seRecv := types.NewVar(token.NoPos, nil, "e", types.NewPointer(syscallErrType))
	syscallErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(seRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	syscallErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(seRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	syscallErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(seRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// func ByteSliceFromString(s string) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ByteSliceFromString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))
	// func BytePtrFromString(s string) (*byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "BytePtrFromString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// type RawConn interface { Control; Read; Write }
	rawConnIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Control",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "fd", types.Typ[types.Uintptr])),
						nil, false))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "fd", types.Typ[types.Uintptr])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
						false))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "fd", types.Typ[types.Uintptr])),
						types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
						false))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	rawConnIface.Complete()
	rawConnType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RawConn", nil),
		rawConnIface, nil)
	scope.Insert(rawConnType.Obj())

	// type Conn interface { SyscallConn() (RawConn, error) }
	connIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "SyscallConn",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", rawConnType),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	connIface.Complete()
	connType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Conn", nil),
		connIface, nil)
	scope.Insert(connType.Obj())

	pkg.MarkComplete()
	return pkg
}

func buildTestingCryptotestPackage() *types.Package {
	pkg := types.NewPackage("testing/cryptotest", "cryptotest")
	scope := pkg.Scope()
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	errType := types.Universe.Lookup("error").Type()

	// testing.TB stand-in interface
	emptyIface := types.NewInterfaceType(nil, nil)
	emptyIface.Complete()
	tbIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Error",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "args",
					types.NewSlice(emptyIface))),
				nil, true)),
		types.NewFunc(token.NoPos, nil, "Fatal",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "args",
					types.NewSlice(emptyIface))),
				nil, true)),
		types.NewFunc(token.NoPos, nil, "Helper",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
	}, nil)
	tbIface.Complete()

	// hash.Hash stand-in interface
	hashIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Sum",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)),
				false)),
		types.NewFunc(token.NoPos, nil, "Reset",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
		types.NewFunc(token.NoPos, nil, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
	}, nil)
	hashIface.Complete()

	// hash function type: func() hash.Hash
	hashFuncType := types.NewSignatureType(nil, nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "", hashIface)),
		false)

	// func TestHash(t testing.TB, newHash func() hash.Hash)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TestHash",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "t", tbIface),
				types.NewVar(token.NoPos, pkg, "newHash", hashFuncType)),
			nil, false)))

	// cipher.Block stand-in interface
	blockIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "BlockSize",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
				false)),
		types.NewFunc(token.NoPos, nil, "Encrypt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", byteSlice),
					types.NewVar(token.NoPos, nil, "src", byteSlice)),
				nil, false)),
		types.NewFunc(token.NoPos, nil, "Decrypt",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "dst", byteSlice),
					types.NewVar(token.NoPos, nil, "src", byteSlice)),
				nil, false)),
	}, nil)
	blockIface.Complete()

	// block function type: func(key []byte) (cipher.Block, error)
	blockFuncType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "key", byteSlice)),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", blockIface),
			types.NewVar(token.NoPos, nil, "", errType)),
		false)

	// func TestBlock(t testing.TB, keySize int, newBlock func(key []byte) (cipher.Block, error))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TestBlock",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "t", tbIface),
				types.NewVar(token.NoPos, pkg, "keySize", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "newBlock", blockFuncType)),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildTestingFstestPackage() *types.Package {
	pkg := types.NewPackage("testing/fstest", "fstest")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type MapFile struct
	mapFileStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Data", types.NewSlice(types.Typ[types.Byte]), false),
		types.NewField(token.NoPos, pkg, "Mode", types.Typ[types.Uint32], false),
		types.NewField(token.NoPos, pkg, "ModTime", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Sys", types.NewInterfaceType(nil, nil), false),
	}, nil)
	mapFileType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "MapFile", nil),
		mapFileStruct, nil)
	scope.Insert(mapFileType.Obj())

	// type MapFS map[string]*MapFile
	mapFSType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "MapFS", nil),
		types.NewMap(types.Typ[types.String], types.NewPointer(mapFileType)), nil)
	scope.Insert(mapFSType.Obj())

	// fs.FileMode stand-in
	fileModeFS := types.Typ[types.Uint32]
	anyFS := types.NewInterfaceType(nil, nil)
	anyFS.Complete()

	// fs.FileInfo interface { Name() string; Size() int64; Mode() FileMode; ModTime() int64; IsDir() bool; Sys() any }
	fileInfoIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "Size",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, nil, "Mode",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", fileModeFS)), false)),
		types.NewFunc(token.NoPos, nil, "ModTime",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])), false)),
		types.NewFunc(token.NoPos, nil, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Sys",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyFS)), false)),
	}, nil)
	fileInfoIface.Complete()

	// fs.DirEntry interface { Name() string; IsDir() bool; Type() FileMode; Info() (FileInfo, error) }
	dirEntryIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "IsDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, nil, "Type",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", fileModeFS)), false)),
		types.NewFunc(token.NoPos, nil, "Info",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fileInfoIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	dirEntryIface.Complete()

	// fs.File interface { Stat() (FileInfo, error); Read([]byte) (int, error); Close() error }
	fsFileIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Stat",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fileInfoIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	fsFileIface.Complete()

	// fs.FS interface { Open(name string) (File, error) }
	fsIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", fsFileIface),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	fsIface.Complete()

	// MapFS.Open(name string) (fs.File, error)
	mapFSType.AddMethod(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "fsys", mapFSType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", fsFileIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// MapFS.ReadFile(name string) ([]byte, error)
	mapFSType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadFile",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "fsys", mapFSType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// MapFS.Stat(name string) (fs.FileInfo, error)
	mapFSType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stat",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "fsys", mapFSType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", fileInfoIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// MapFS.ReadDir(name string) ([]fs.DirEntry, error)
	mapFSType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadDir",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "fsys", mapFSType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(dirEntryIface)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// MapFS.Sub(dir string) (fs.FS, error)
	mapFSType.AddMethod(types.NewFunc(token.NoPos, pkg, "Sub",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "fsys", mapFSType),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dir", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", fsIface),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func TestFS(fsys fs.FS, expected ...string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TestFS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fsys", fsIface),
				types.NewVar(token.NoPos, pkg, "expected", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	pkg.MarkComplete()
	return pkg
}

func buildTestingIotestPackage() *types.Package {
	pkg := types.NewPackage("testing/iotest", "iotest")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// io.Writer interface
	ioWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriter.Complete()

	// func ErrReader(err error) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ErrReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// func TestReader(r io.Reader, content []byte) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TestReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", ioReader),
				types.NewVar(token.NoPos, pkg, "content", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func HalfReader(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HalfReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// func DataErrReader(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DataErrReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// func OneByteReader(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OneByteReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// func TimeoutReader(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TimeoutReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// func TruncateWriter(w io.Writer, n int64) io.Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TruncateWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", ioWriter),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioWriter)),
			false)))

	// func NewReadLogger(prefix string, r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReadLogger",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "r", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReader)),
			false)))

	// func NewWriteLogger(prefix string, w io.Writer) io.Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriteLogger",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "w", ioWriter)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioWriter)),
			false)))

	// var ErrTimeout error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrTimeout", errType))

	pkg.MarkComplete()
	return pkg
}

// buildTestingPackage creates a minimal type-checked testing package stub.
func buildTestingPackage() *types.Package {
	pkg := types.NewPackage("testing", "testing")
	scope := pkg.Scope()
	anyType := types.NewInterfaceType(nil, nil)

	// type TB interface (common interface for T and B)
	anySliceTB := types.NewSlice(anyType)
	tbIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Error",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "args", anySliceTB)),
				nil, true)),
		types.NewFunc(token.NoPos, pkg, "Errorf",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
					types.NewVar(token.NoPos, nil, "args", anySliceTB)),
				nil, true)),
		types.NewFunc(token.NoPos, pkg, "Fail",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, pkg, "FailNow",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, pkg, "Failed",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "Fatal",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "args", anySliceTB)),
				nil, true)),
		types.NewFunc(token.NoPos, pkg, "Fatalf",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
					types.NewVar(token.NoPos, nil, "args", anySliceTB)),
				nil, true)),
		types.NewFunc(token.NoPos, pkg, "Helper",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, pkg, "Log",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "args", anySliceTB)),
				nil, true)),
		types.NewFunc(token.NoPos, pkg, "Logf",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
					types.NewVar(token.NoPos, nil, "args", anySliceTB)),
				nil, true)),
		types.NewFunc(token.NoPos, pkg, "Name",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Skip",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "args", anySliceTB)),
				nil, true)),
		types.NewFunc(token.NoPos, pkg, "SkipNow",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
		types.NewFunc(token.NoPos, pkg, "Skipf",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
					types.NewVar(token.NoPos, nil, "args", anySliceTB)),
				nil, true)),
		types.NewFunc(token.NoPos, pkg, "Skipped",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		types.NewFunc(token.NoPos, pkg, "TempDir",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Cleanup",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil, nil, nil, false))),
				nil, false)),
	}, nil)
	tbIface.Complete()
	tbType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "TB", nil),
		tbIface, nil)
	scope.Insert(tbType.Obj())

	// type T struct { ... }
	tStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "name", types.Typ[types.String], false),
	}, nil)
	tType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "T", nil),
		tStruct, nil)
	scope.Insert(tType.Obj())
	tPtr := types.NewPointer(tType)
	tRecv := types.NewVar(token.NoPos, nil, "t", tPtr)

	// T methods (common with B)
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(tRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Errorf",
		types.NewSignatureType(tRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fail",
		types.NewSignatureType(tRecv, nil, nil, nil, nil, false)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "FailNow",
		types.NewSignatureType(tRecv, nil, nil, nil, nil, false)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Failed",
		types.NewSignatureType(tRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fatal",
		types.NewSignatureType(tRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fatalf",
		types.NewSignatureType(tRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Helper",
		types.NewSignatureType(tRecv, nil, nil, nil, nil, false)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Log",
		types.NewSignatureType(tRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Logf",
		types.NewSignatureType(tRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(tRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Skip",
		types.NewSignatureType(tRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "SkipNow",
		types.NewSignatureType(tRecv, nil, nil, nil, nil, false)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Skipf",
		types.NewSignatureType(tRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Skipped",
		types.NewSignatureType(tRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "TempDir",
		types.NewSignatureType(tRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cleanup",
		types.NewSignatureType(tRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f",
				types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			nil, false)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Setenv",
		types.NewSignatureType(tRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			nil, false)))
	// T-specific methods
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Run",
		types.NewSignatureType(tRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "t", tPtr)),
						nil, false))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parallel",
		types.NewSignatureType(tRecv, nil, nil, nil, nil, false)))
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Deadline",
		types.NewSignatureType(tRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "deadline", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
			false)))

	// type B struct { ... }
	bStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "N", types.Typ[types.Int], false),
	}, nil)
	bType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "B", nil),
		bStruct, nil)
	scope.Insert(bType.Obj())
	bPtr := types.NewPointer(bType)
	bRecv := types.NewVar(token.NoPos, nil, "b", bPtr)

	// B methods (common)
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Errorf",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fail",
		types.NewSignatureType(bRecv, nil, nil, nil, nil, false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "FailNow",
		types.NewSignatureType(bRecv, nil, nil, nil, nil, false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Failed",
		types.NewSignatureType(bRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fatal",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fatalf",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Helper",
		types.NewSignatureType(bRecv, nil, nil, nil, nil, false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Log",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Logf",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(bRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Skip",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "SkipNow",
		types.NewSignatureType(bRecv, nil, nil, nil, nil, false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Skipf",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Skipped",
		types.NewSignatureType(bRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "TempDir",
		types.NewSignatureType(bRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cleanup",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f",
				types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			nil, false)))
	// B-specific methods
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Run",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "f",
					types.NewSignatureType(nil, nil, nil,
						types.NewTuple(types.NewVar(token.NoPos, nil, "b", bPtr)),
						nil, false))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "ResetTimer",
		types.NewSignatureType(bRecv, nil, nil, nil, nil, false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "StartTimer",
		types.NewSignatureType(bRecv, nil, nil, nil, nil, false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "StopTimer",
		types.NewSignatureType(bRecv, nil, nil, nil, nil, false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReportAllocs",
		types.NewSignatureType(bRecv, nil, nil, nil, nil, false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetBytes",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int64])),
			nil, false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReportMetric",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Float64]),
				types.NewVar(token.NoPos, nil, "unit", types.Typ[types.String])),
			nil, false)))

	// type PB struct {}
	pbStruct := types.NewStruct(nil, nil)
	pbType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PB", nil),
		pbStruct, nil)
	scope.Insert(pbType.Obj())
	pbPtr := types.NewPointer(pbType)
	pbType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "pb", pbPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// B.RunParallel(body func(*PB))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "RunParallel",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "body",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "pb", pbPtr)),
					nil, false))),
			nil, false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetParallelism",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.Typ[types.Int])),
			nil, false)))
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Elapsed",
		types.NewSignatureType(bRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))

	// type M struct {}
	mStruct := types.NewStruct(nil, nil)
	mType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "M", nil),
		mStruct, nil)
	scope.Insert(mType.Obj())
	mPtr := types.NewPointer(mType)
	mType.AddMethod(types.NewFunc(token.NoPos, pkg, "Run",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "m", mPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// func Short() bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Short",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// func Verbose() bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Verbose",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// type BenchmarkResult struct { N int; T time.Duration; Bytes int64; MemAllocs uint64; MemBytes uint64 }
	benchResultStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "N", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "T", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Bytes", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "MemAllocs", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "MemBytes", types.Typ[types.Uint64], false),
	}, nil)
	benchResultType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "BenchmarkResult", nil),
		benchResultStruct, nil)
	scope.Insert(benchResultType.Obj())

	// BenchmarkResult methods
	brRecv := types.NewVar(token.NoPos, nil, "r", benchResultType)
	benchResultType.AddMethod(types.NewFunc(token.NoPos, pkg, "NsPerOp",
		types.NewSignatureType(brRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	benchResultType.AddMethod(types.NewFunc(token.NoPos, pkg, "AllocsPerOp",
		types.NewSignatureType(brRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	benchResultType.AddMethod(types.NewFunc(token.NoPos, pkg, "AllocedBytesPerOp",
		types.NewSignatureType(brRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64])),
			false)))
	benchResultType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(brRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	benchResultType.AddMethod(types.NewFunc(token.NoPos, pkg, "MemString",
		types.NewSignatureType(brRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// func AllocsPerRun(runs int, f func()) float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AllocsPerRun",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "runs", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "f",
					types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// func Benchmark(f func(b *B)) BenchmarkResult
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Benchmark",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "b", bPtr)),
					nil, false))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", benchResultType)),
			false)))

	// T.Context() context.Context — returns opaque interface
	contextIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Deadline",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "deadline", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
				false)),
		types.NewFunc(token.NoPos, nil, "Done",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewChan(types.RecvOnly, types.NewStruct(nil, nil)))),
				false)),
		types.NewFunc(token.NoPos, nil, "Err",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
				false)),
		types.NewFunc(token.NoPos, nil, "Value",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyType)),
				false)),
	}, nil)
	contextIface.Complete()

	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Context",
		types.NewSignatureType(tRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", contextIface)),
			false)))
	// T.Chdir(dir string)
	tType.AddMethod(types.NewFunc(token.NoPos, pkg, "Chdir",
		types.NewSignatureType(tRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "dir", types.Typ[types.String])),
			nil, false)))

	// B.Loop() bool
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Loop",
		types.NewSignatureType(bRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	// B.Setenv(key, value string)
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Setenv",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			nil, false)))
	// B.Context() context.Context
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Context",
		types.NewSignatureType(bRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", contextIface)),
			false)))
	// B.Chdir(dir string)
	bType.AddMethod(types.NewFunc(token.NoPos, pkg, "Chdir",
		types.NewSignatureType(bRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "dir", types.Typ[types.String])),
			nil, false)))

	// type F struct {} — fuzz testing type
	fStruct := types.NewStruct(nil, nil)
	fType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "F", nil),
		fStruct, nil)
	scope.Insert(fType.Obj())
	fPtr := types.NewPointer(fType)
	fRecv := types.NewVar(token.NoPos, nil, "f", fPtr)

	// F common methods (inherited from TB pattern)
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(fRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Errorf",
		types.NewSignatureType(fRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fail",
		types.NewSignatureType(fRecv, nil, nil, nil, nil, false)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "FailNow",
		types.NewSignatureType(fRecv, nil, nil, nil, nil, false)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Failed",
		types.NewSignatureType(fRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fatal",
		types.NewSignatureType(fRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fatalf",
		types.NewSignatureType(fRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Helper",
		types.NewSignatureType(fRecv, nil, nil, nil, nil, false)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Log",
		types.NewSignatureType(fRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Logf",
		types.NewSignatureType(fRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(fRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Skip",
		types.NewSignatureType(fRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "SkipNow",
		types.NewSignatureType(fRecv, nil, nil, nil, nil, false)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Skipf",
		types.NewSignatureType(fRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Skipped",
		types.NewSignatureType(fRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "TempDir",
		types.NewSignatureType(fRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cleanup",
		types.NewSignatureType(fRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "fn",
				types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			nil, false)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Setenv",
		types.NewSignatureType(fRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			nil, false)))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Context",
		types.NewSignatureType(fRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", contextIface)),
			false)))
	// F-specific methods
	// F.Add(args ...any)
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(fRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "args", anyType)),
			nil, true)))
	// F.Fuzz(ff func(*T))
	fType.AddMethod(types.NewFunc(token.NoPos, pkg, "Fuzz",
		types.NewSignatureType(fRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "ff", anyType)),
			nil, false)))

	// func Init()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// func Testing() bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Testing",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func CoverMode() string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CoverMode",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func Coverage() float64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Coverage",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Float64])),
			false)))

	// type InternalTest struct { Name string; F func(*T) }
	itStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "F", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", tPtr)), nil, false), false),
	}, nil)
	itType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "InternalTest", nil),
		itStruct, nil)
	scope.Insert(itType.Obj())

	// type InternalBenchmark struct { Name string; F func(*B) }
	ibStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "F", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", bPtr)), nil, false), false),
	}, nil)
	ibType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "InternalBenchmark", nil),
		ibStruct, nil)
	scope.Insert(ibType.Obj())

	// type InternalExample struct { Name string; F func(); Output string; Unordered bool }
	ieStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "F", types.NewSignatureType(nil, nil, nil, nil, nil, false), false),
		types.NewField(token.NoPos, pkg, "Output", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Unordered", types.Typ[types.Bool], false),
	}, nil)
	ieType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "InternalExample", nil),
		ieStruct, nil)
	scope.Insert(ieType.Obj())

	// type InternalFuzzTarget struct { Name string; Fn func(*F) }
	iftStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Fn", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", fPtr)), nil, false), false),
	}, nil)
	iftType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "InternalFuzzTarget", nil),
		iftStruct, nil)
	scope.Insert(iftType.Obj())

	// func Main(matchString func(pat, str string) (bool, error), tests []InternalTest, benchmarks []InternalBenchmark, examples []InternalExample)
	matchFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "pat", types.Typ[types.String]),
			types.NewVar(token.NoPos, nil, "str", types.Typ[types.String])),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool]),
			types.NewVar(token.NoPos, nil, "", types.Universe.Lookup("error").Type())),
		false)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Main",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "matchString", matchFn),
				types.NewVar(token.NoPos, pkg, "tests", types.NewSlice(itType)),
				types.NewVar(token.NoPos, pkg, "benchmarks", types.NewSlice(ibType)),
				types.NewVar(token.NoPos, pkg, "examples", types.NewSlice(ieType))),
			nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildTestingQuickPackage() *types.Package {
	pkg := types.NewPackage("testing/quick", "quick")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Config struct { ... }
	configStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "MaxCount", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "MaxCountScale", types.Typ[types.Float64], false),
		types.NewField(token.NoPos, pkg, "Rand", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Values", types.Typ[types.Int], false),
	}, nil)
	configType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Config", nil),
		configStruct, nil)
	scope.Insert(configType.Obj())

	// type CheckError struct { ... }
	checkErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Count", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "In", types.NewSlice(types.NewInterfaceType(nil, nil)), false),
	}, nil)
	checkErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CheckError", nil),
		checkErrStruct, nil)
	scope.Insert(checkErrType.Obj())
	checkErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(checkErrType)), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))

	// type CheckEqualError struct { ... }
	checkEqErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "CheckError", checkErrType, true),
		types.NewField(token.NoPos, pkg, "Out1", types.NewSlice(types.NewInterfaceType(nil, nil)), false),
		types.NewField(token.NoPos, pkg, "Out2", types.NewSlice(types.NewInterfaceType(nil, nil)), false),
	}, nil)
	checkEqErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CheckEqualError", nil),
		checkEqErrStruct, nil)
	scope.Insert(checkEqErrType.Obj())
	checkEqErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(checkEqErrType)), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))

	// func Check(f any, config *Config) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Check",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "f", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "config", types.NewPointer(configType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func CheckEqual(f, g any, config *Config) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CheckEqual",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "f", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "g", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "config", types.NewPointer(configType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Value(t reflect.Type, rand *rand.Rand) (reflect.Value, bool) — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "t", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "rand", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewInterfaceType(nil, nil)),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildTestingSlogtestPackage() *types.Package {
	pkg := types.NewPackage("testing/slogtest", "slogtest")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// func Run(t *testing.T, newHandler func(*testing.T) slog.Handler, opts ...Option) — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Run",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "t", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "newHandler", types.Typ[types.Int])),
			nil, false)))

	// slog.Handler stand-in interface { Enabled(ctx, level); Handle(ctx, record); WithAttrs(attrs); WithGroup(name) }
	slogHandlerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Enabled",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "ctx", types.NewInterfaceType(nil, nil)),
					types.NewVar(token.NoPos, nil, "level", types.Typ[types.Int])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
	}, nil)
	slogHandlerIface.Complete()

	// func TestHandler(h slog.Handler, results func() []map[string]any) error — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TestHandler",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", slogHandlerIface),
				types.NewVar(token.NoPos, pkg, "results", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildTestingSynctestPackage() *types.Package {
	pkg := types.NewPackage("testing/synctest", "synctest")
	scope := pkg.Scope()

	// func Test(f func()) — runs f in an isolated bubble
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Test",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			nil, false)))

	// func Wait() — waits for goroutines in bubble to block
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Wait",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	pkg.MarkComplete()
	return pkg
}

func buildTextScannerPackage() *types.Package {
	pkg := types.NewPackage("text/scanner", "scanner")
	scope := pkg.Scope()

	// Position type
	posStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Filename", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Offset", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Line", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Column", types.Typ[types.Int], false),
	}, nil)
	posType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Position", nil),
		posStruct, nil)
	scope.Insert(posType.Obj())

	// Position.IsValid() bool
	posType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "pos", types.NewPointer(posType)),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// Position.String() string
	posType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "pos", posType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func(s *Scanner, msg string) type for Error field — use forward ref via scannerPtr
	// We need scannerPtr for the function type, but Scanner hasn't been declared yet.
	// Use a *struct{} stand-in for the Error callback's *Scanner param.
	scannerStandIn := types.NewPointer(types.NewStruct(nil, nil))
	errorFuncType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "s", scannerStandIn),
			types.NewVar(token.NoPos, nil, "msg", types.Typ[types.String])),
		nil, false)

	// func(ch rune, i int) bool type for IsIdentRune field
	isIdentRuneType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "ch", types.Typ[types.Int32]),
			types.NewVar(token.NoPos, nil, "i", types.Typ[types.Int])),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
		false)

	// Scanner type
	scannerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Mode", types.Typ[types.Uint], false),
		types.NewField(token.NoPos, pkg, "Whitespace", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "Position", posType, true), // embedded
		types.NewField(token.NoPos, pkg, "IsIdentRune", isIdentRuneType, false),
		types.NewField(token.NoPos, pkg, "Error", errorFuncType, false),
		types.NewField(token.NoPos, pkg, "ErrorCount", types.Typ[types.Int], false),
	}, nil)
	scannerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Scanner", nil),
		scannerStruct, nil)
	scope.Insert(scannerType.Obj())
	scannerPtr := types.NewPointer(scannerType)

	// io.Reader stand-in for Init
	errType := types.Universe.Lookup("error").Type()
	ioReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderIface.Complete()

	// Scanner.Init(src io.Reader) *Scanner
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "s", scannerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "src", ioReaderIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", scannerPtr)),
			false)))

	// Scanner.Scan() rune
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Scan",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "s", scannerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))

	// Scanner.Peek() rune
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Peek",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "s", scannerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))

	// Scanner.Next() rune
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "s", scannerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int32])),
			false)))

	// Scanner.TokenText() string
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "TokenText",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "s", scannerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Scanner.Pos() Position
	scannerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Pos",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "s", scannerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", posType)),
			false)))

	// func TokenString(tok rune) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TokenString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "tok", types.Typ[types.Int32])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "EOF", types.Typ[types.Int32], constant.MakeInt64(-1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Ident", types.Typ[types.Int32], constant.MakeInt64(-2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Int", types.Typ[types.Int32], constant.MakeInt64(-3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Float", types.Typ[types.Int32], constant.MakeInt64(-4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Char", types.Typ[types.Int32], constant.MakeInt64(-5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "String", types.Typ[types.Int32], constant.MakeInt64(-6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RawString", types.Typ[types.Int32], constant.MakeInt64(-7)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Comment", types.Typ[types.Int32], constant.MakeInt64(-8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanIdents", types.Typ[types.Uint], constant.MakeUint64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanInts", types.Typ[types.Uint], constant.MakeUint64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanFloats", types.Typ[types.Uint], constant.MakeUint64(16)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanChars", types.Typ[types.Uint], constant.MakeUint64(32)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanStrings", types.Typ[types.Uint], constant.MakeUint64(64)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanRawStrings", types.Typ[types.Uint], constant.MakeUint64(128)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ScanComments", types.Typ[types.Uint], constant.MakeUint64(256)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SkipComments", types.Typ[types.Uint], constant.MakeUint64(512)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "GoTokens", types.Typ[types.Uint], constant.MakeUint64(1012)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "GoWhitespace", types.Typ[types.Uint64], constant.MakeUint64(1<<'\t'|1<<'\n'|1<<'\r'|1<<' ')))

	pkg.MarkComplete()
	return pkg
}

func buildTextTabwriterPackage() *types.Package {
	pkg := types.NewPackage("text/tabwriter", "tabwriter")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSliceTW := types.NewSlice(types.Typ[types.Byte])

	// io.Writer interface for output parameter
	ioWriterTW := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceTW)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterTW.Complete()

	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())
	writerPtr := types.NewPointer(writerType)

	// func NewWriter(output io.Writer, minwidth, tabwidth, padding int, padchar byte, flags uint) *Writer
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "output", ioWriterTW),
				types.NewVar(token.NoPos, pkg, "minwidth", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "tabwidth", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "padding", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "padchar", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "flags", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", writerPtr)),
			false)))

	// Writer.Init(output io.Writer, minwidth, tabwidth, padding int, padchar byte, flags uint) *Writer
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Init",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "w", writerPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "output", ioWriterTW),
				types.NewVar(token.NoPos, pkg, "minwidth", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "tabwidth", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "padding", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "padchar", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "flags", types.Typ[types.Uint])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", writerPtr)),
			false)))

	// Writer.Write(buf []byte) (n int, err error)
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "w", writerPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "buf", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Writer.Flush() error
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "w", writerPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Constants for flags
	scope.Insert(types.NewConst(token.NoPos, pkg, "FilterHTML", types.Typ[types.Uint], constant.MakeUint64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StripEscape", types.Typ[types.Uint], constant.MakeUint64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "AlignRight", types.Typ[types.Uint], constant.MakeUint64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DiscardEmptyColumns", types.Typ[types.Uint], constant.MakeUint64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TabIndent", types.Typ[types.Uint], constant.MakeUint64(16)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Debug", types.Typ[types.Uint], constant.MakeUint64(32)))

	// Escape constant
	scope.Insert(types.NewConst(token.NoPos, pkg, "Escape", types.Typ[types.Byte], constant.MakeInt64(0xff)))

	pkg.MarkComplete()
	return pkg
}

// buildTextTemplatePackage creates the type-checked text/template package stub.
func buildTextTemplatePackage() *types.Package {
	pkg := types.NewPackage("text/template", "template")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Template struct { ... }
	tmplStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "name", types.Typ[types.String], false),
	}, nil)
	tmplType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Template", nil),
		tmplStruct, nil)
	scope.Insert(tmplType.Obj())
	tmplPtr := types.NewPointer(tmplType)

	// func New(name string) *Template
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))

	// func Must(t *Template, err error) *Template
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Must",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "t", tmplPtr),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))

	// func ParseFiles(filenames ...string) (*Template, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseFiles",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "filenames", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func ParseGlob(pattern string) (*Template, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseGlob",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type FuncMap map[string]any
	funcMapType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FuncMap", nil),
		types.NewMap(types.Typ[types.String], types.NewInterfaceType(nil, nil)), nil)
	scope.Insert(funcMapType.Obj())

	// io.Writer for template Execute
	tmplByteSlice := types.NewSlice(types.Typ[types.Byte])
	tmplWriterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", tmplByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	tmplWriterIface.Complete()
	anyType := types.NewInterfaceType(nil, nil)

	// Template methods
	tmplRecv := types.NewVar(token.NoPos, nil, "t", tmplPtr)

	// func (*Template) Parse(text string) (*Template, error)
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (*Template) Execute(wr io.Writer, data any) error
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Execute",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "wr", tmplWriterIface),
				types.NewVar(token.NoPos, pkg, "data", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (*Template) ExecuteTemplate(wr io.Writer, name string, data any) error
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExecuteTemplate",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "wr", tmplWriterIface),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "data", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (*Template) Funcs(funcMap FuncMap) *Template
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Funcs",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "funcMap", funcMapType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))

	// func (*Template) ParseFiles(filenames ...string) (*Template, error)
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "ParseFiles",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "filenames", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func (*Template) ParseGlob(pattern string) (*Template, error)
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "ParseGlob",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (*Template) Name() string
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(tmplRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (*Template) New(name string) *Template
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))

	// func (*Template) Lookup(name string) *Template
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Lookup",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))

	// func (*Template) Option(opt ...string) *Template
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Option",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "opt", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))

	// func (*Template) Clone() (*Template, error)
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(tmplRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (*Template) AddParseTree(name string, tree *parse.Tree) (*Template, error)
	// parse.Tree stand-in as opaque pointer
	parseTreePtr := types.NewPointer(types.NewStruct(nil, nil))
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddParseTree",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "tree", parseTreePtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (*Template) Templates() []*Template
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Templates",
		types.NewSignatureType(tmplRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(tmplPtr))),
			false)))

	// func (*Template) DefinedTemplates() string
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "DefinedTemplates",
		types.NewSignatureType(tmplRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (*Template) Delims(left, right string) *Template
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "Delims",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "left", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "right", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", tmplPtr)),
			false)))

	// fs.FS stand-in for ParseFS
	fsIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil)),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	fsIface.Complete()

	// func ParseFS(fsys fs.FS, patterns ...string) (*Template, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseFS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fsys", fsIface),
				types.NewVar(token.NoPos, pkg, "patterns", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func (*Template) ParseFS(fsys fs.FS, patterns ...string) (*Template, error)
	tmplType.AddMethod(types.NewFunc(token.NoPos, pkg, "ParseFS",
		types.NewSignatureType(tmplRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "fsys", fsIface),
				types.NewVar(token.NoPos, pkg, "patterns", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tmplPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// func HTMLEscapeString(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HTMLEscapeString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func JSEscapeString(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "JSEscapeString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func URLQueryEscaper(args ...any) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "URLQueryEscaper",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			true)))

	// func HTMLEscaper(args ...any) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HTMLEscaper",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			true)))

	// func JSEscaper(args ...any) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "JSEscaper",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			true)))

	// func IsTrue(val any) (truth, ok bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsTrue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "val", anyType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "truth", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, pkg, "ok", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildTextTemplateParsePackage() *types.Package {
	pkg := types.NewPackage("text/template/parse", "parse")
	scope := pkg.Scope()

	// type NodeType int (defined before Node so it can be referenced)
	nodeTypeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NodeType", nil),
		types.Typ[types.Int], nil)
	scope.Insert(nodeTypeType.Obj())

	// NodeType constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "NodeText", nodeTypeType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NodeAction", nodeTypeType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NodeList", nodeTypeType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NodePipe", nodeTypeType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "NodeTemplate", nodeTypeType, constant.MakeInt64(4)))

	// type Pos int
	posType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Pos", nil),
		types.Typ[types.Int], nil)
	scope.Insert(posType.Obj())

	// type Node interface { Type() NodeType; String() string; Position() Pos }
	nodeIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Type",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", nodeTypeType)), false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, pkg, "Position",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", posType)), false)),
	}, nil)
	nodeIface.Complete()
	nodeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Node", nil),
		nodeIface, nil)
	scope.Insert(nodeType.Obj())

	// type Tree struct { ... }
	treeStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Root", nodeType, false),
	}, nil)
	treeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Tree", nil),
		treeStruct, nil)
	scope.Insert(treeType.Obj())
	_ = treeType

	pkg.MarkComplete()
	return pkg
}

func buildTimeTzdataPackage() *types.Package {
	pkg := types.NewPackage("time/tzdata", "tzdata")
	// This package is imported for its side effect of embedding timezone data.
	// No exported functions or types.
	pkg.MarkComplete()
	return pkg
}

func buildUTF8Package() *types.Package {
	pkg := types.NewPackage("unicode/utf8", "utf8")
	scope := pkg.Scope()

	// func RuneLen(r rune) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RuneLen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func RuneCountInString(s string) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RuneCountInString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func RuneCount(p []byte) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RuneCount",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func ValidString(s string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ValidString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func Valid(p []byte) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Valid",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func DecodeRuneInString(s string) (rune, int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeRuneInString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func EncodeRune(p []byte, r rune) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EncodeRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func DecodeRune(p []byte) (rune, int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func DecodeLastRune(p []byte) (rune, int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeLastRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func DecodeLastRuneInString(s string) (rune, int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeLastRuneInString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func ValidRune(r rune) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ValidRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func FullRune(p []byte) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FullRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func FullRuneInString(s string) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FullRuneInString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func AppendRune(p []byte, r rune) []byte
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "p", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))

	// Constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "RuneSelf", types.Typ[types.Int], constant.MakeInt64(0x80)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxRune", types.Typ[types.Rune], constant.MakeInt64(0x10FFFF)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "UTFMax", types.Typ[types.Int], constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "RuneError", types.Typ[types.Rune], constant.MakeInt64(0xFFFD)))

	pkg.MarkComplete()
	return pkg
}

func buildUnicodePackage() *types.Package {
	pkg := types.NewPackage("unicode", "unicode")
	scope := pkg.Scope()

	runeBool := func(name string) {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
				false)))
	}
	runeBool("IsLetter")
	runeBool("IsDigit")
	runeBool("IsSpace")
	runeBool("IsUpper")
	runeBool("IsLower")
	runeBool("IsPunct")
	runeBool("IsControl")
	runeBool("IsGraphic")
	runeBool("IsPrint")
	runeBool("IsNumber")
	runeBool("IsTitle")
	runeBool("IsSymbol")
	runeBool("IsMark")

	runeRune := func(name string) {
		scope.Insert(types.NewFunc(token.NoPos, pkg, name,
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
				types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Rune])),
				false)))
	}
	runeRune("ToUpper")
	runeRune("ToLower")
	runeRune("ToTitle")
	runeRune("SimpleFold")

	// type RangeTable struct { R16 []Range16; R32 []Range32; LatinOffset int }
	// Simplified as opaque struct since users mostly pass predefined tables
	rangeTableType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RangeTable", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "LatinOffset", types.Typ[types.Int], false),
		}, nil), nil)
	scope.Insert(rangeTableType.Obj())
	rtPtr := types.NewPointer(rangeTableType)

	// type Range16 struct { Lo, Hi uint16; Stride uint16 }
	range16Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Range16", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Lo", types.Typ[types.Uint16], false),
			types.NewField(token.NoPos, pkg, "Hi", types.Typ[types.Uint16], false),
			types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Uint16], false),
		}, nil), nil)
	scope.Insert(range16Type.Obj())

	// type Range32 struct { Lo, Hi uint32; Stride uint32 }
	range32Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Range32", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Lo", types.Typ[types.Uint32], false),
			types.NewField(token.NoPos, pkg, "Hi", types.Typ[types.Uint32], false),
			types.NewField(token.NoPos, pkg, "Stride", types.Typ[types.Uint32], false),
		}, nil), nil)
	scope.Insert(range32Type.Obj())

	// func In(r rune, ranges ...*RangeTable) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "In",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, pkg, "ranges", types.NewSlice(rtPtr))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			true)))

	// func Is(rangeTab *RangeTable, r rune) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Is",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rangeTab", rtPtr),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IsOneOf(ranges []*RangeTable, r rune) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsOneOf",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ranges", types.NewSlice(rtPtr)),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func To(_case int, r rune) rune
	scope.Insert(types.NewFunc(token.NoPos, pkg, "To",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "_case", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Rune])),
			false)))

	// type SpecialCase []CaseRange — simplified as named slice of struct
	caseRangeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CaseRange", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Lo", types.Typ[types.Uint32], false),
			types.NewField(token.NoPos, pkg, "Hi", types.Typ[types.Uint32], false),
			types.NewField(token.NoPos, pkg, "Delta", types.NewArray(types.Typ[types.Rune], 3), false),
		}, nil), nil)
	scope.Insert(caseRangeType.Obj())

	specialCaseType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "SpecialCase", nil),
		types.NewSlice(caseRangeType), nil)
	scope.Insert(specialCaseType.Obj())
	// SpecialCase.ToUpper, ToLower, ToTitle methods
	specialCaseType.AddMethod(types.NewFunc(token.NoPos, pkg, "ToUpper",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "special", specialCaseType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Rune])), false)))
	specialCaseType.AddMethod(types.NewFunc(token.NoPos, pkg, "ToLower",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "special", specialCaseType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Rune])), false)))
	specialCaseType.AddMethod(types.NewFunc(token.NoPos, pkg, "ToTitle",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "special", specialCaseType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Rune])), false)))

	// Case constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "UpperCase", types.Typ[types.Int], constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LowerCase", types.Typ[types.Int], constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "TitleCase", types.Typ[types.Int], constant.MakeInt64(2)))

	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxRune", types.Typ[types.Rune], constant.MakeInt64(0x10FFFF)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "ReplacementChar", types.Typ[types.Rune], constant.MakeInt64(0xFFFD)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxASCII", types.Typ[types.Rune], constant.MakeInt64(0x7F)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxLatin1", types.Typ[types.Rune], constant.MakeInt64(0xFF)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MaxCase", types.Typ[types.Int], constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "Version", types.Typ[types.String], constant.MakeString("15.0.0")))

	// Predefined RangeTable variables for common categories
	for _, name := range []string{
		"Letter", "Lu", "Ll", "Lt", "Lm", "Lo",
		"Mark", "Mn", "Mc", "Me",
		"Number", "Nd", "Nl", "No",
		"Punct", "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po",
		"Symbol", "Sm", "Sc", "Sk", "So",
		"Separator", "Zs", "Zl", "Zp",
		"Control", "Cc",
		"Space", "White_Space",
		"Digit",
		"Title",
		"Upper", "Lower",
		"Graphic", "Print",
	} {
		scope.Insert(types.NewVar(token.NoPos, pkg, name, rtPtr))
	}

	// Predefined script tables
	for _, name := range []string{
		"Latin", "Greek", "Cyrillic", "Arabic", "Hebrew", "Han",
		"Hiragana", "Katakana", "Hangul", "Thai", "Devanagari",
		"Bengali", "Tamil", "Telugu", "Kannada", "Malayalam",
		"Georgian", "Armenian", "Ethiopic", "Tibetan", "Mongolian",
		"Cherokee", "Canadian_Aboriginal", "Runic", "Ogham",
		"Common", "Inherited",
	} {
		scope.Insert(types.NewVar(token.NoPos, pkg, name, rtPtr))
	}

	// var TurkishCase, AzeriCase SpecialCase
	scope.Insert(types.NewVar(token.NoPos, pkg, "TurkishCase", specialCaseType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "AzeriCase", specialCaseType))

	pkg.MarkComplete()
	return pkg
}

// buildUnicodeUTF16Package creates the type-checked unicode/utf16 package stub.
func buildUnicodeUTF16Package() *types.Package {
	pkg := types.NewPackage("unicode/utf16", "utf16")
	scope := pkg.Scope()

	// func Encode(s []rune) []uint16
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.NewSlice(types.Typ[types.Rune]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Uint16]))),
			false)))

	// func Decode(s []uint16) []rune
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Decode",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.NewSlice(types.Typ[types.Uint16]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Rune]))),
			false)))

	// func IsSurrogate(r rune) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsSurrogate",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func DecodeRune(r1, r2 rune) rune
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DecodeRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r1", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, pkg, "r2", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Rune])),
			false)))

	// func EncodeRune(r rune) (r1, r2 rune)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "EncodeRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r1", types.Typ[types.Rune]),
				types.NewVar(token.NoPos, pkg, "r2", types.Typ[types.Rune])),
			false)))

	// func RuneLen(r rune) int
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RuneLen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	// func AppendRune(a []uint16, r rune) []uint16
	uint16Slice := types.NewSlice(types.Typ[types.Uint16])
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AppendRune",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "a", uint16Slice),
				types.NewVar(token.NoPos, pkg, "r", types.Typ[types.Rune])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", uint16Slice)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildUniquePackage() *types.Package {
	pkg := types.NewPackage("unique", "unique")
	scope := pkg.Scope()

	// type Handle[T comparable] struct { ... } — simplified as struct with value
	handleStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "value", types.Typ[types.Int], false),
	}, nil)
	handleType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Handle", nil),
		handleStruct, nil)
	scope.Insert(handleType.Obj())

	// func Make[T comparable](value T) Handle[T] — simplified
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Make",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "value", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handleType)),
			false)))

	// Handle.Value() T
	handleType.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", handleType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildWeakPackage() *types.Package {
	pkg := types.NewPackage("weak", "weak")
	scope := pkg.Scope()

	// type Pointer struct — opaque (generic Pointer[T] simplified)
	ptrStruct := types.NewStruct(nil, nil)
	ptrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Pointer", nil),
		ptrStruct, nil)
	scope.Insert(ptrType.Obj())

	ptrRecv := types.NewVar(token.NoPos, pkg, "", ptrType)

	// Pointer.Value() unsafe.Pointer — simplified; real API returns *T
	unsafePtrType := types.Typ[types.UnsafePointer]
	ptrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(ptrRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", unsafePtrType)),
			false)))

	// func Make(ptr unsafe.Pointer) Pointer — simplified; real API is Make[T](*T)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Make",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ptr", unsafePtrType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ptrType)),
			false)))

	pkg.MarkComplete()
	return pkg
}
