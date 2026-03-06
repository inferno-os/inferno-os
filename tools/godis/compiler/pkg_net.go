// Package type stubs for net and database packages: net, net/url,
// net/http, net/http/httputil, net/mail, net/textproto, net/smtp, net/rpc,
// net/netip, database/sql, database/sql/driver.
package compiler

import (
	"go/constant"
	"go/token"
	"go/types"
)

func init() {
	RegisterPackage("database/sql/driver", buildDatabaseSQLDriverPackage)
	RegisterPackage("database/sql", buildDatabaseSQLPackage)
	RegisterPackage("net/http/cgi", buildNetHTTPCgiPackage)
	RegisterPackage("net/http/cookiejar", buildNetHTTPCookiejarPackage)
	RegisterPackage("net/http/fcgi", buildNetHTTPFcgiPackage)
	RegisterPackage("net/http/httptrace", buildNetHTTPHttptracePackage)
	RegisterPackage("net/http", buildNetHTTPPackage)
	RegisterPackage("net/http/pprof", buildNetHTTPPprofPackage)
	RegisterPackage("net/http/httptest", buildNetHTTPTestPackage)
	RegisterPackage("net/http/httputil", buildNetHTTPUtilPackage)
	RegisterPackage("net/mail", buildNetMailPackage)
	RegisterPackage("net/netip", buildNetNetipPackage)
	RegisterPackage("net", buildNetPackage)
	RegisterPackage("net/rpc/jsonrpc", buildNetRPCJSONRPCPackage)
	RegisterPackage("net/rpc", buildNetRPCPackage)
	RegisterPackage("net/smtp", buildNetSMTPPackage)
	RegisterPackage("net/textproto", buildNetTextprotoPackage)
	RegisterPackage("net/url", buildNetURLPackage)
}

func buildDatabaseSQLDriverPackage() *types.Package {
	pkg := types.NewPackage("database/sql/driver", "driver")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anyType := types.NewInterfaceType(nil, nil)

	// type Value interface{}
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Value", anyType))

	// type NamedValue struct
	namedValueStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Ordinal", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Value", anyType, false),
	}, nil)
	namedValueType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NamedValue", nil),
		namedValueStruct, nil)
	scope.Insert(namedValueType.Obj())

	// type IsolationLevel int
	isolationType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "IsolationLevel", nil),
		types.Typ[types.Int], nil)
	scope.Insert(isolationType.Obj())

	// type TxOptions struct
	txOptsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Isolation", isolationType, false),
		types.NewField(token.NoPos, pkg, "ReadOnly", types.Typ[types.Bool], false),
	}, nil)
	txOptsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "TxOptions", nil),
		txOptsStruct, nil)
	scope.Insert(txOptsType.Obj())

	valueSlice := types.NewSlice(anyType)
	stringSlice := types.NewSlice(types.Typ[types.String])

	// Result interface: LastInsertId() (int64, error); RowsAffected() (int64, error)
	resultIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "LastInsertId",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "RowsAffected",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	resultIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Result", resultIface))

	// Rows interface: Columns() []string; Close() error; Next(dest []Value) error
	rowsIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Columns",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", stringSlice)), false)),
		types.NewFunc(token.NoPos, pkg, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "Next",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "dest", valueSlice)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	rowsIface.Complete()
	rowsType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Rows", nil), rowsIface, nil)
	scope.Insert(rowsType.Obj())

	// Stmt interface: Close() error; NumInput() int; Exec(args []Value) (Result, error); Query(args []Value) (Rows, error)
	stmtIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "NumInput",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)),
		types.NewFunc(token.NoPos, pkg, "Exec",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "args", valueSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", resultIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "Query",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "args", valueSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", rowsType),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	stmtIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Stmt", stmtIface))

	// Tx interface: Commit() error; Rollback() error
	txIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Commit",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "Rollback",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	txIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Tx", txIface))

	// Conn interface: Prepare(query string) (Stmt, error); Close() error; Begin() (Tx, error)
	connIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Prepare",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "query", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", stmtIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, pkg, "Begin",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", txIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	connIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Conn", connIface))

	// Driver interface: Open(name string) (Conn, error)
	driverIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", connIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	driverIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Driver", driverIface))

	// Valuer interface: Value() (Value, error)
	valuerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Value",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", anyType),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	valuerIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Valuer", valuerIface))

	// ValueConverter interface: ConvertValue(v any) (Value, error)
	valueConverterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ConvertValue",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "v", anyType)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", anyType),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	valueConverterIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "ValueConverter", valueConverterIface))

	// context.Context stand-in { Deadline(); Done(); Err(); Value() }
	anyCtxDB := types.NewInterfaceType(nil, nil)
	anyCtxDB.Complete()
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
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyCtxDB)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyCtxDB)),
				false)),
	}, nil)
	ctxType.Complete()
	namedValueSlice := types.NewSlice(types.NewPointer(namedValueType))
	for _, def := range []struct {
		name  string
		iface *types.Interface
	}{
		{"DriverContext", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "OpenConnector",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", anyType),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"ConnPrepareContext", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "PrepareContext",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "ctx", ctxType),
						types.NewVar(token.NoPos, nil, "query", types.Typ[types.String])),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", stmtIface),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"ConnBeginTx", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "BeginTx",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "ctx", ctxType),
						types.NewVar(token.NoPos, nil, "opts", txOptsType)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", txIface),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"Pinger", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "Ping",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", ctxType)),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"SessionResetter", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ResetSession",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", ctxType)),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"Validator", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "IsValid",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
		}, nil)},
	} {
		def.iface.Complete()
		scope.Insert(types.NewTypeName(token.NoPos, pkg, def.name, def.iface))
	}

	// reflect.Type stand-in for RowsColumnTypeScanType
	reflectTypeIfaceDB := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	reflectTypeIfaceDB.Complete()

	// Extension interfaces with proper method signatures
	for _, def := range []struct {
		name  string
		iface *types.Interface
	}{
		{"StmtExecContext", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ExecContext",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "ctx", ctxType),
						types.NewVar(token.NoPos, nil, "args", namedValueSlice)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", resultIface),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"StmtQueryContext", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "QueryContext",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "ctx", ctxType),
						types.NewVar(token.NoPos, nil, "args", namedValueSlice)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", rowsType),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"RowsNextResultSet", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "HasNextResultSet",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)),
			types.NewFunc(token.NoPos, pkg, "NextResultSet",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"Execer", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "Exec",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "query", types.Typ[types.String]),
						types.NewVar(token.NoPos, nil, "args", valueSlice)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", resultIface),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"ExecerContext", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ExecContext",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "ctx", ctxType),
						types.NewVar(token.NoPos, nil, "query", types.Typ[types.String]),
						types.NewVar(token.NoPos, nil, "args", namedValueSlice)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", resultIface),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"Queryer", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "Query",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "query", types.Typ[types.String]),
						types.NewVar(token.NoPos, nil, "args", valueSlice)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", rowsType),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"QueryerContext", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "QueryContext",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "ctx", ctxType),
						types.NewVar(token.NoPos, nil, "query", types.Typ[types.String]),
						types.NewVar(token.NoPos, nil, "args", namedValueSlice)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", rowsType),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
		}, nil)},
		{"Connector", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "Connect",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", ctxType)),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "", connIface),
						types.NewVar(token.NoPos, nil, "", errType)), false)),
			types.NewFunc(token.NoPos, pkg, "Driver",
				types.NewSignatureType(nil, nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "", driverIface)), false)),
		}, nil)},
		{"RowsColumnTypeScanType", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ColumnTypeScanType",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "index", types.Typ[types.Int])),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", reflectTypeIfaceDB)), false)),
		}, nil)},
		{"RowsColumnTypeDatabaseTypeName", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ColumnTypeDatabaseTypeName",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "index", types.Typ[types.Int])),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		}, nil)},
		{"RowsColumnTypeLength", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ColumnTypeLength",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "index", types.Typ[types.Int])),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "length", types.Typ[types.Int64]),
						types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])), false)),
		}, nil)},
		{"RowsColumnTypeNullable", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ColumnTypeNullable",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "index", types.Typ[types.Int])),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "nullable", types.Typ[types.Bool]),
						types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])), false)),
		}, nil)},
		{"RowsColumnTypePrecisionScale", types.NewInterfaceType([]*types.Func{
			types.NewFunc(token.NoPos, pkg, "ColumnTypePrecisionScale",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "index", types.Typ[types.Int])),
					types.NewTuple(
						types.NewVar(token.NoPos, nil, "precision", types.Typ[types.Int64]),
						types.NewVar(token.NoPos, nil, "scale", types.Typ[types.Int64]),
						types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])), false)),
		}, nil)},
	} {
		def.iface.Complete()
		scope.Insert(types.NewTypeName(token.NoPos, pkg, def.name, def.iface))
	}
	_ = namedValueSlice

	// type NotNull, Null structs
	for _, name := range []string{"NotNull", "Null"} {
		s := types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Converter", anyType, false),
		}, nil)
		t := types.NewNamed(types.NewTypeName(token.NoPos, pkg, name, nil), s, nil)
		scope.Insert(t.Obj())
	}

	// var Int32, String, Bool, DefaultParameterConverter
	for _, name := range []string{"Int32", "String", "Bool", "DefaultParameterConverter"} {
		scope.Insert(types.NewVar(token.NoPos, pkg, name, anyType))
	}

	// var ErrSkip, ErrBadConn, ErrRemoveArgument error
	for _, name := range []string{"ErrSkip", "ErrBadConn", "ErrRemoveArgument"} {
		scope.Insert(types.NewVar(token.NoPos, pkg, name, errType))
	}

	// func IsScanValue(v Value) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsScanValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func IsValue(v any) bool
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IsValue",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "v", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildDatabaseSQLPackage creates the type-checked database/sql package stub.
func buildDatabaseSQLPackage() *types.Package {
	pkg := types.NewPackage("database/sql", "sql")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	anyType := types.Universe.Lookup("any").Type()

	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type RawBytes []byte
	rawBytesType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RawBytes", nil),
		byteSlice, nil)
	scope.Insert(rawBytesType.Obj())

	dbStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "fd", types.Typ[types.Int], false),
	}, nil)
	dbType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "DB", nil),
		dbStruct, nil)
	scope.Insert(dbType.Obj())
	dbPtr := types.NewPointer(dbType)

	// type Result interface { LastInsertId() (int64, error); RowsAffected() (int64, error) }
	resultIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "LastInsertId",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "RowsAffected",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	resultIface.Complete()
	resultType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Result", nil),
		resultIface, nil)
	scope.Insert(resultType.Obj())

	rowStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	rowType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Row", nil),
		rowStruct, nil)
	scope.Insert(rowType.Obj())
	rowPtr := types.NewPointer(rowType)

	scope.Insert(types.NewFunc(token.NoPos, pkg, "Open",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "driverName", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "dataSourceName", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", dbPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func OpenDB(c driver.Connector) *DB
	// driver.Connector is an interface with Connect and Driver methods
	connectorIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Connect",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", types.NewInterfaceType(nil, nil))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil)),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Driver",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
				false)),
	}, nil)
	connectorIface.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "OpenDB",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "c", connectorIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", dbPtr)),
			false)))

	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "db", dbPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "QueryRow",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "db", dbPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rowPtr)),
			true)))

	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "Exec",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "db", dbPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", resultType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	rowType.AddMethod(types.NewFunc(token.NoPos, pkg, "Scan",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rowPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dest", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNoRows", errType))

	// Rows type
	rowsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	rowsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Rows", nil),
		rowsStruct, nil)
	scope.Insert(rowsType.Obj())
	rowsPtr := types.NewPointer(rowsType)
	rowsRecv := types.NewVar(token.NoPos, nil, "rs", rowsPtr)

	// Rows.Next() bool
	rowsType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(rowsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	// Rows.Scan(dest ...any) error
	rowsType.AddMethod(types.NewFunc(token.NoPos, pkg, "Scan",
		types.NewSignatureType(rowsRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "dest", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			true)))
	// Rows.Close() error
	rowsType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(rowsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	// Rows.Err() error
	rowsType.AddMethod(types.NewFunc(token.NoPos, pkg, "Err",
		types.NewSignatureType(rowsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	// Rows.Columns() ([]string, error)
	rowsType.AddMethod(types.NewFunc(token.NoPos, pkg, "Columns",
		types.NewSignatureType(rowsRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Stmt type
	stmtStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "fd", types.Typ[types.Int], false),
	}, nil)
	stmtType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Stmt", nil),
		stmtStruct, nil)
	scope.Insert(stmtType.Obj())
	stmtPtr := types.NewPointer(stmtType)

	// Tx type
	txStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "fd", types.Typ[types.Int], false),
	}, nil)
	txType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Tx", nil),
		txStruct, nil)
	scope.Insert(txType.Obj())
	txPtr := types.NewPointer(txType)

	// TxOptions type
	txOptsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Isolation", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "ReadOnly", types.Typ[types.Bool], false),
	}, nil)
	txOptsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "TxOptions", nil),
		txOptsStruct, nil)
	scope.Insert(txOptsType.Obj())

	// NullString type
	nullStringStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "String", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Valid", types.Typ[types.Bool], false),
	}, nil)
	nullStringType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NullString", nil),
		nullStringStruct, nil)
	scope.Insert(nullStringType.Obj())

	// NullString Scan/Value methods
	nullStringPtr := types.NewPointer(nullStringType)
	nullStringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Scan",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ns", nullStringPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "value", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	nullStringType.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ns", nullStringType), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", anyType),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// NullInt64 type
	nullInt64Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Int64", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Valid", types.Typ[types.Bool], false),
	}, nil)
	nullInt64Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NullInt64", nil),
		nullInt64Struct, nil)
	scope.Insert(nullInt64Type.Obj())

	// NullBool type
	nullBoolStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Bool", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Valid", types.Typ[types.Bool], false),
	}, nil)
	nullBoolType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NullBool", nil),
		nullBoolStruct, nil)
	scope.Insert(nullBoolType.Obj())

	// DB.Query(query string, args ...any) (*Rows, error)
	dbRecv := types.NewVar(token.NoPos, nil, "db", dbPtr)
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "Query",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", rowsPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// DB.Prepare(query string) (*Stmt, error)
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "Prepare",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", stmtPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// DB.Begin() (*Tx, error)
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "Begin",
		types.NewSignatureType(dbRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", txPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// context.Context stand-in for BeginTx, PingContext (reused later for *Context methods)
	anyCtxSQL := types.NewInterfaceType(nil, nil)
	anyCtxSQL.Complete()
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
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyCtxSQL)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyCtxSQL)),
				false)),
	}, nil)
	ctxType.Complete()

	// DB.BeginTx(ctx context.Context, opts *TxOptions) (*Tx, error)
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "BeginTx",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "opts", types.NewPointer(txOptsType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", txPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// DB.Ping() error
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "Ping",
		types.NewSignatureType(dbRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// DB.PingContext(ctx context.Context) error
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "PingContext",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ctx", ctxType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// DB.SetMaxOpenConns(n int)
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetMaxOpenConns",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			nil, false)))

	// DB.SetMaxIdleConns(n int)
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetMaxIdleConns",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int])),
			nil, false)))

	// DB.SetConnMaxLifetime(d time.Duration)
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetConnMaxLifetime",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "d", types.Typ[types.Int64])),
			nil, false)))

	// DB.SetConnMaxIdleTime(d time.Duration)
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetConnMaxIdleTime",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "d", types.Typ[types.Int64])),
			nil, false)))

	// Context-aware methods (ctxType defined above with BeginTx/PingContext)

	// DB.QueryContext(ctx, query, args...) (*Rows, error)
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "QueryContext",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", rowsPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// DB.ExecContext(ctx, query, args...) (Result, error)
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExecContext",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", resultType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// DB.QueryRowContext(ctx, query, args...) *Row
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "QueryRowContext",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rowPtr)),
			true)))

	// DB.PrepareContext(ctx, query) (*Stmt, error)
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "PrepareContext",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", stmtPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// DB.Stats() DBStats
	dbStatsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "MaxOpenConnections", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "OpenConnections", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "InUse", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Idle", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "WaitCount", types.Typ[types.Int64], false),
	}, nil)
	dbStatsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "DBStats", nil),
		dbStatsStruct, nil)
	scope.Insert(dbStatsType.Obj())
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stats",
		types.NewSignatureType(dbRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", dbStatsType)),
			false)))

	// NullFloat64, NullInt32, NullInt16, NullByte, NullTime types
	nullFloat64Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Float64", types.Typ[types.Float64], false),
		types.NewField(token.NoPos, pkg, "Valid", types.Typ[types.Bool], false),
	}, nil)
	nullFloat64Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NullFloat64", nil),
		nullFloat64Struct, nil)
	scope.Insert(nullFloat64Type.Obj())

	nullInt32Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Int32", types.Typ[types.Int32], false),
		types.NewField(token.NoPos, pkg, "Valid", types.Typ[types.Bool], false),
	}, nil)
	nullInt32Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NullInt32", nil),
		nullInt32Struct, nil)
	scope.Insert(nullInt32Type.Obj())

	nullInt16Struct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Int16", types.Typ[types.Int16], false),
		types.NewField(token.NoPos, pkg, "Valid", types.Typ[types.Bool], false),
	}, nil)
	nullInt16Type := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NullInt16", nil),
		nullInt16Struct, nil)
	scope.Insert(nullInt16Type.Obj())

	nullByteStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Byte", types.Typ[types.Byte], false),
		types.NewField(token.NoPos, pkg, "Valid", types.Typ[types.Bool], false),
	}, nil)
	nullByteType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NullByte", nil),
		nullByteStruct, nil)
	scope.Insert(nullByteType.Obj())

	// NullTime — time.Time as int64 stand-in
	nullTimeStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Time", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Valid", types.Typ[types.Bool], false),
	}, nil)
	nullTimeType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "NullTime", nil),
		nullTimeStruct, nil)
	scope.Insert(nullTimeType.Obj())

	// Add Scan/Value methods to all Null* types
	for _, nullInfo := range []struct {
		typ  *types.Named
		name string
	}{
		{nullInt64Type, "NullInt64"},
		{nullBoolType, "NullBool"},
		{nullFloat64Type, "NullFloat64"},
		{nullInt32Type, "NullInt32"},
		{nullInt16Type, "NullInt16"},
		{nullByteType, "NullByte"},
		{nullTimeType, "NullTime"},
	} {
		nPtr := types.NewPointer(nullInfo.typ)
		nullInfo.typ.AddMethod(types.NewFunc(token.NoPos, pkg, "Scan",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "n", nPtr), nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "value", anyType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)))
		nullInfo.typ.AddMethod(types.NewFunc(token.NoPos, pkg, "Value",
			types.NewSignatureType(types.NewVar(token.NoPos, nil, "n", nullInfo.typ), nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", anyType),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)))
	}

	// IsolationLevel type
	isolationLevelType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "IsolationLevel", nil),
		types.Typ[types.Int], nil)
	scope.Insert(isolationLevelType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelDefault", isolationLevelType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelReadUncommitted", isolationLevelType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelReadCommitted", isolationLevelType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelWriteCommitted", isolationLevelType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelRepeatableRead", isolationLevelType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelSnapshot", isolationLevelType, constant.MakeInt64(5)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelSerializable", isolationLevelType, constant.MakeInt64(6)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "LevelLinearizable", isolationLevelType, constant.MakeInt64(7)))

	// Tx context-aware methods
	txRecv := types.NewVar(token.NoPos, nil, "tx", txPtr)
	txType.AddMethod(types.NewFunc(token.NoPos, pkg, "QueryContext",
		types.NewSignatureType(txRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", rowsPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))
	txType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExecContext",
		types.NewSignatureType(txRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", resultType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))
	txType.AddMethod(types.NewFunc(token.NoPos, pkg, "QueryRowContext",
		types.NewSignatureType(txRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rowPtr)),
			true)))
	txType.AddMethod(types.NewFunc(token.NoPos, pkg, "Exec",
		types.NewSignatureType(txRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", resultType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))
	txType.AddMethod(types.NewFunc(token.NoPos, pkg, "Query",
		types.NewSignatureType(txRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", rowsPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))
	txType.AddMethod(types.NewFunc(token.NoPos, pkg, "QueryRow",
		types.NewSignatureType(txRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rowPtr)),
			true)))
	txType.AddMethod(types.NewFunc(token.NoPos, pkg, "Prepare",
		types.NewSignatureType(txRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", stmtPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	txType.AddMethod(types.NewFunc(token.NoPos, pkg, "Stmt",
		types.NewSignatureType(txRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "stmt", stmtPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", stmtPtr)),
			false)))

	// Tx methods
	txType.AddMethod(types.NewFunc(token.NoPos, pkg, "Commit",
		types.NewSignatureType(txRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	txType.AddMethod(types.NewFunc(token.NoPos, pkg, "Rollback",
		types.NewSignatureType(txRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Tx.PrepareContext(ctx context.Context, query string) (*Stmt, error)
	txType.AddMethod(types.NewFunc(token.NoPos, pkg, "PrepareContext",
		types.NewSignatureType(txRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", stmtPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Tx.StmtContext(ctx context.Context, stmt *Stmt) *Stmt
	txType.AddMethod(types.NewFunc(token.NoPos, pkg, "StmtContext",
		types.NewSignatureType(txRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "stmt", stmtPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", stmtPtr)),
			false)))

	// Stmt methods
	stmtRecv := types.NewVar(token.NoPos, nil, "s", stmtPtr)
	stmtType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(stmtRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	stmtType.AddMethod(types.NewFunc(token.NoPos, pkg, "Exec",
		types.NewSignatureType(stmtRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", resultType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))
	stmtType.AddMethod(types.NewFunc(token.NoPos, pkg, "QueryRow",
		types.NewSignatureType(stmtRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rowPtr)),
			true)))
	stmtType.AddMethod(types.NewFunc(token.NoPos, pkg, "Query",
		types.NewSignatureType(stmtRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", rowsPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))
	stmtType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExecContext",
		types.NewSignatureType(stmtRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", resultType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))
	stmtType.AddMethod(types.NewFunc(token.NoPos, pkg, "QueryContext",
		types.NewSignatureType(stmtRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", rowsPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))
	stmtType.AddMethod(types.NewFunc(token.NoPos, pkg, "QueryRowContext",
		types.NewSignatureType(stmtRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rowPtr)),
			true)))

	// Row.Err() error
	rowType.AddMethod(types.NewFunc(token.NoPos, pkg, "Err",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", rowPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Conn type
	connStruct := types.NewStruct(nil, nil)
	connType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Conn", nil), connStruct, nil)
	scope.Insert(connType.Obj())
	connPtr := types.NewPointer(connType)
	connRecv := types.NewVar(token.NoPos, nil, "c", connPtr)
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(connRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "BeginTx",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "opts", types.NewPointer(txOptsType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", txPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "ExecContext",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", resultType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "QueryContext",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", rowsPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "QueryRowContext",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "args", types.NewSlice(anyType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rowPtr)),
			true)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "PrepareContext",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", stmtPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "PingContext",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ctx", ctxType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "Raw",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f",
				types.NewSignatureType(nil, nil, nil,
					types.NewTuple(types.NewVar(token.NoPos, nil, "driverConn", anyType)),
					types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
					false))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// DB.Conn(ctx context.Context) (*Conn, error)
	dbType.AddMethod(types.NewFunc(token.NoPos, pkg, "Conn",
		types.NewSignatureType(dbRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ctx", ctxType)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", connPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// ColumnType
	colTypeStruct := types.NewStruct(nil, nil)
	colType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ColumnType", nil), colTypeStruct, nil)
	scope.Insert(colType.Obj())
	colTypePtr := types.NewPointer(colType)
	colTypeRecv := types.NewVar(token.NoPos, nil, "ci", colTypePtr)
	colType.AddMethod(types.NewFunc(token.NoPos, pkg, "Name",
		types.NewSignatureType(colTypeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	colType.AddMethod(types.NewFunc(token.NoPos, pkg, "DatabaseTypeName",
		types.NewSignatureType(colTypeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	colType.AddMethod(types.NewFunc(token.NoPos, pkg, "Nullable",
		types.NewSignatureType(colTypeRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "nullable", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
			false)))
	colType.AddMethod(types.NewFunc(token.NoPos, pkg, "Length",
		types.NewSignatureType(colTypeRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "length", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
			false)))
	colType.AddMethod(types.NewFunc(token.NoPos, pkg, "ScanType",
		types.NewSignatureType(colTypeRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
			false)))
	colType.AddMethod(types.NewFunc(token.NoPos, pkg, "DecimalSize",
		types.NewSignatureType(colTypeRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "precision", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "scale", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
			false)))

	// Rows.ColumnTypes() ([]*ColumnType, error)
	rowsType.AddMethod(types.NewFunc(token.NoPos, pkg, "ColumnTypes",
		types.NewSignatureType(rowsRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(colTypePtr)),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Rows.NextResultSet() bool
	rowsType.AddMethod(types.NewFunc(token.NoPos, pkg, "NextResultSet",
		types.NewSignatureType(rowsRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// Named parameter
	namedArgStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Value", anyType, false),
	}, nil)
	namedArgType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "NamedArg", nil), namedArgStruct, nil)
	scope.Insert(namedArgType.Obj())
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Named",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", namedArgType)),
			false)))

	// Scanner interface
	scannerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Scan",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "src", anyType)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	scannerIface.Complete()
	scannerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Scanner", nil), scannerIface, nil)
	scope.Insert(scannerType.Obj())

	// var ErrConnDone, ErrTxDone error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrConnDone", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrTxDone", errType))

	// driver.Driver interface { Open(name string) (driver.Conn, error) }
	driverConnIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	driverConnIface.Complete()
	driverIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", driverConnIface),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	driverIface.Complete()

	// func Register(name string, driver driver.Driver)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Register",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "driver", driverIface)),
			nil, false)))

	// func Drivers() []string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Drivers",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String]))),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildNetHTTPCgiPackage() *types.Package {
	pkg := types.NewPackage("net/http/cgi", "cgi")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// *log.Logger (opaque)
	loggerStruct := types.NewStruct(nil, nil)
	loggerPtr := types.NewPointer(loggerStruct)

	// http.ResponseWriter interface { Header(); Write(); WriteHeader() }
	headerMapCGI := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))
	responseWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerMapCGI)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "WriteHeader",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "statusCode", types.Typ[types.Int])),
				nil, false)),
	}, nil)
	responseWriter.Complete()

	// io.Writer interface for Stderr field
	ioWriterCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterCGI.Complete()

	// *http.Request (opaque)
	requestStruct := types.NewStruct(nil, nil)
	requestPtr := types.NewPointer(requestStruct)

	// type Handler struct { ... }
	handlerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Root", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Dir", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Env", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "InheritEnv", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Logger", loggerPtr, false),
		types.NewField(token.NoPos, pkg, "Args", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Stderr", ioWriterCGI, false),
	}, nil)
	handlerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Handler", nil),
		handlerStruct, nil)
	scope.Insert(handlerType.Obj())

	// Handler.ServeHTTP(rw http.ResponseWriter, req *http.Request)
	handlerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ServeHTTP",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", types.NewPointer(handlerType)), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "rw", responseWriter),
				types.NewVar(token.NoPos, pkg, "req", requestPtr)),
			nil, false)))

	// func Request() (*http.Request, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Request",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", requestPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func RequestFromMap(params map[string]string) (*http.Request, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RequestFromMap",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "params",
				types.NewMap(types.Typ[types.String], types.Typ[types.String]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", requestPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Serve(handler http.Handler) error — simplified
	// http.Handler with ServeHTTP method
	rwIfaceCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerMapCGI)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "WriteHeader",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "statusCode", types.Typ[types.Int])),
				nil, false)),
	}, nil)
	rwIfaceCGI.Complete()
	reqPtrCGI := types.NewPointer(types.NewStruct(nil, nil))
	httpHandlerCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ServeHTTP",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "w", rwIfaceCGI),
					types.NewVar(token.NoPos, nil, "r", reqPtrCGI)),
				nil, false)),
	}, nil)
	httpHandlerCGI.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Serve",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "handler", httpHandlerCGI)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildNetHTTPCookiejarPackage() *types.Package {
	pkg := types.NewPackage("net/http/cookiejar", "cookiejar")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// PublicSuffixList interface
	pslIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "PublicSuffix",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "domain", types.Typ[types.String])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
	}, nil)
	pslIface.Complete()
	pslType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PublicSuffixList", nil),
		pslIface, nil)
	scope.Insert(pslType.Obj())

	// type Options struct { PublicSuffixList PublicSuffixList }
	optionsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "PublicSuffixList", pslType, false),
	}, nil)
	optionsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Options", nil),
		optionsStruct, nil)
	scope.Insert(optionsType.Obj())

	// *url.URL (opaque)
	urlStruct := types.NewStruct(nil, nil)
	urlPtr := types.NewPointer(urlStruct)

	// *http.Cookie (opaque)
	cookieStruct := types.NewStruct(nil, nil)
	cookiePtr := types.NewPointer(cookieStruct)

	// type Jar struct {}
	jarStruct := types.NewStruct(nil, nil)
	jarType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Jar", nil),
		jarStruct, nil)
	scope.Insert(jarType.Obj())
	jarPtr := types.NewPointer(jarType)

	jarRecv := types.NewVar(token.NoPos, nil, "j", jarPtr)
	// func (j *Jar) Cookies(u *url.URL) []*http.Cookie
	jarType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cookies",
		types.NewSignatureType(jarRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "u", urlPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(cookiePtr))),
			false)))

	// func (j *Jar) SetCookies(u *url.URL, cookies []*http.Cookie)
	jarType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetCookies",
		types.NewSignatureType(jarRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "u", urlPtr),
				types.NewVar(token.NoPos, nil, "cookies", types.NewSlice(cookiePtr))),
			nil, false)))

	// func New(o *Options) (*Jar, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "New",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "o", types.NewPointer(optionsType))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", jarPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildNetHTTPFcgiPackage() *types.Package {
	pkg := types.NewPackage("net/http/fcgi", "fcgi")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// var ErrRequestAborted, ErrConnClosed
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrRequestAborted", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrConnClosed", errType))

	// net.Listener interface
	byteSliceFCGI := types.NewSlice(types.Typ[types.Byte])
	netConnFCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceFCGI)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceFCGI)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	netConnFCGI.Complete()
	netAddrFCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Network",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
	}, nil)
	netAddrFCGI.Complete()
	listenerFCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Accept",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", netConnFCGI),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Addr",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", netAddrFCGI)),
				false)),
	}, nil)
	listenerFCGI.Complete()
	// http.Handler interface
	// http.ResponseWriter { Header(); Write(); WriteHeader() }
	headerMapFCGI := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))
	rwIfaceFCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerMapFCGI)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "WriteHeader",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "statusCode", types.Typ[types.Int])),
				nil, false)),
	}, nil)
	rwIfaceFCGI.Complete()
	reqPtrFCGI := types.NewPointer(types.NewStruct(nil, nil))
	httpHandlerFCGI := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ServeHTTP",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "w", rwIfaceFCGI),
					types.NewVar(token.NoPos, nil, "r", reqPtrFCGI)),
				nil, false)),
	}, nil)
	httpHandlerFCGI.Complete()
	// func Serve(l net.Listener, handler http.Handler) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Serve",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "l", listenerFCGI),
				types.NewVar(token.NoPos, pkg, "handler", httpHandlerFCGI)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// *http.Request (opaque)
	requestStruct := types.NewStruct(nil, nil)
	requestPtr := types.NewPointer(requestStruct)

	// func ProcessEnv(r *http.Request) map[string]string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ProcessEnv",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", requestPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "",
				types.NewMap(types.Typ[types.String], types.Typ[types.String]))),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildNetHTTPHttptracePackage() *types.Package {
	pkg := types.NewPackage("net/http/httptrace", "httptrace")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()

	// Define info structs first so ClientTrace callbacks can reference them

	// net.Conn stand-in for GotConnInfo
	byteSliceHT := types.NewSlice(types.Typ[types.Byte])
	netConnIfaceHT := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceHT)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceHT)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	netConnIfaceHT.Complete()

	// type GotConnInfo struct { ... }
	gotConnInfoStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Conn", netConnIfaceHT, false),
		types.NewField(token.NoPos, pkg, "Reused", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "WasIdle", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "IdleTime", types.Typ[types.Int64], false),
	}, nil)
	gotConnInfoType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "GotConnInfo", nil),
		gotConnInfoStruct, nil)
	scope.Insert(gotConnInfoType.Obj())

	// type DNSStartInfo struct { Host string }
	dnsStartStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Host", types.Typ[types.String], false),
	}, nil)
	dnsStartType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "DNSStartInfo", nil),
		dnsStartStruct, nil)
	scope.Insert(dnsStartType.Obj())

	// type DNSDoneInfo struct { Addrs []net.IPAddr; Err error }
	// net.IPAddr simplified as struct { IP string }
	ipAddrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "IP", types.Typ[types.String], false),
	}, nil)
	dnsDoneStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Addrs", types.NewSlice(ipAddrStruct), false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
		types.NewField(token.NoPos, pkg, "Coalesced", types.Typ[types.Bool], false),
	}, nil)
	dnsDoneType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "DNSDoneInfo", nil),
		dnsDoneStruct, nil)
	scope.Insert(dnsDoneType.Obj())

	// type WroteRequestInfo struct { Err error }
	wroteReqStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	wroteReqType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "WroteRequestInfo", nil),
		wroteReqStruct, nil)
	scope.Insert(wroteReqType.Obj())

	// tls.ConnectionState simplified stand-in
	tlsConnStateStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Version", types.Typ[types.Uint16], false),
		types.NewField(token.NoPos, pkg, "HandshakeComplete", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "ServerName", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "NegotiatedProtocol", types.Typ[types.String], false),
	}, nil)

	// Callback function signatures for ClientTrace
	// func(hostPort string)
	hostPortFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "hostPort", types.Typ[types.String])),
		nil, false)
	// func()
	voidFn := types.NewSignatureType(nil, nil, nil, nil, nil, false)
	// func(err error)
	errFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "err", errType)),
		nil, false)
	// func(network, addr string)
	netAddrFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "network", types.Typ[types.String]),
			types.NewVar(token.NoPos, nil, "addr", types.Typ[types.String])),
		nil, false)
	// func(network, addr string, err error)
	netAddrErrFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "network", types.Typ[types.String]),
			types.NewVar(token.NoPos, nil, "addr", types.Typ[types.String]),
			types.NewVar(token.NoPos, nil, "err", errType)),
		nil, false)
	// func(GotConnInfo)
	gotConnFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "info", gotConnInfoType)),
		nil, false)
	// func(code int, header http.Header) error — Got1xxResponse callback
	got1xxFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "code", types.Typ[types.Int]),
			types.NewVar(token.NoPos, nil, "header", types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String])))),
		types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
		false)
	// func(DNSStartInfo)
	dnsStartFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "info", dnsStartType)),
		nil, false)
	// func(DNSDoneInfo)
	dnsDoneFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "info", dnsDoneType)),
		nil, false)
	// func(tls.ConnectionState, error)
	tlsDoneFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "state", tlsConnStateStruct),
			types.NewVar(token.NoPos, nil, "err", errType)),
		nil, false)
	// func(WroteRequestInfo)
	wroteReqFn := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "info", wroteReqType)),
		nil, false)

	// type ClientTrace struct { ... }
	clientTraceStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "GetConn", hostPortFn, false),
		types.NewField(token.NoPos, pkg, "GotConn", gotConnFn, false),
		types.NewField(token.NoPos, pkg, "PutIdleConn", errFn, false),
		types.NewField(token.NoPos, pkg, "GotFirstResponseByte", voidFn, false),
		types.NewField(token.NoPos, pkg, "Got100Continue", voidFn, false),
		types.NewField(token.NoPos, pkg, "Got1xxResponse", got1xxFn, false),
		types.NewField(token.NoPos, pkg, "DNSStart", dnsStartFn, false),
		types.NewField(token.NoPos, pkg, "DNSDone", dnsDoneFn, false),
		types.NewField(token.NoPos, pkg, "ConnectStart", netAddrFn, false),
		types.NewField(token.NoPos, pkg, "ConnectDone", netAddrErrFn, false),
		types.NewField(token.NoPos, pkg, "TLSHandshakeStart", voidFn, false),
		types.NewField(token.NoPos, pkg, "TLSHandshakeDone", tlsDoneFn, false),
		types.NewField(token.NoPos, pkg, "WroteHeaderField", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.NewSlice(types.Typ[types.String]))),
			nil, false), false),
		types.NewField(token.NoPos, pkg, "WroteHeaders", voidFn, false),
		types.NewField(token.NoPos, pkg, "Wait100Continue", voidFn, false),
		types.NewField(token.NoPos, pkg, "WroteRequest", wroteReqFn, false),
	}, nil)
	clientTraceType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ClientTrace", nil),
		clientTraceStruct, nil)
	scope.Insert(clientTraceType.Obj())

	// context.Context stand-in for WithClientTrace/ContextClientTrace
	anyHTCtx := types.NewInterfaceType(nil, nil)
	anyHTCtx.Complete()
	ctxIfaceHT := types.NewInterfaceType([]*types.Func{
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
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyHTCtx)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyHTCtx)),
				false)),
	}, nil)
	ctxIfaceHT.Complete()

	// func WithClientTrace(ctx context.Context, trace *ClientTrace) context.Context
	scope.Insert(types.NewFunc(token.NoPos, pkg, "WithClientTrace",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIfaceHT),
				types.NewVar(token.NoPos, pkg, "trace", types.NewPointer(clientTraceType))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ctxIfaceHT)),
			false)))

	// func ContextClientTrace(ctx context.Context) *ClientTrace
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ContextClientTrace",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ctx", ctxIfaceHT)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(clientTraceType))),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildNetHTTPPackage creates a minimal type-checked net/http package stub.
func buildNetHTTPPackage() *types.Package {
	pkg := types.NewPackage("net/http", "http")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSliceHTTP := types.NewSlice(types.Typ[types.Byte])

	// context.Context stand-in
	ctxType := types.NewInterfaceType([]*types.Func{
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
	ctxType.Complete()

	// net.Conn stand-in
	netConnIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceHTTP)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSliceHTTP)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	netConnIface.Complete()

	// net.Addr stand-in
	netAddrIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Network",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	netAddrIface.Complete()

	// net.Listener stand-in
	listenerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Accept",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", netConnIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)),
		types.NewFunc(token.NoPos, nil, "Addr",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", netAddrIface)), false)),
	}, nil)
	listenerIface.Complete()

	// io.ReadSeeker stand-in
	ioReadSeekerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceHTTP)),
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
	}, nil)
	ioReadSeekerIface.Complete()

	// type Header map[string][]string
	headerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Header", nil),
		types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String])), nil)
	scope.Insert(headerType.Obj())

	// *url.URL stand-in struct
	urlStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, nil, "Scheme", types.Typ[types.String], false),
		types.NewField(token.NoPos, nil, "Opaque", types.Typ[types.String], false),
		types.NewField(token.NoPos, nil, "Host", types.Typ[types.String], false),
		types.NewField(token.NoPos, nil, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, nil, "RawPath", types.Typ[types.String], false),
		types.NewField(token.NoPos, nil, "RawQuery", types.Typ[types.String], false),
		types.NewField(token.NoPos, nil, "Fragment", types.Typ[types.String], false),
	}, nil)
	urlType := types.NewNamed(types.NewTypeName(token.NoPos, nil, "URL", nil), urlStruct, nil)
	urlPtr := types.NewPointer(urlType)

	// io.ReadCloser stand-in
	ioReadCloser := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
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

	// *tls.Config stand-in
	tlsConfigStruct := types.NewStruct(nil, nil)
	tlsConfigType := types.NewNamed(types.NewTypeName(token.NoPos, nil, "Config", nil), tlsConfigStruct, nil)
	tlsConfigPtr := types.NewPointer(tlsConfigType)

	// type Request struct { Method string; URL *url.URL; Proto string; Header Header; Body io.ReadCloser; ... }
	reqStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Method", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "URL", urlPtr, false),
		types.NewField(token.NoPos, pkg, "Proto", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "ProtoMajor", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "ProtoMinor", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Header", headerType, false),
		types.NewField(token.NoPos, pkg, "Body", ioReadCloser, false),
		types.NewField(token.NoPos, pkg, "ContentLength", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Host", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Form", types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String])), false),
		types.NewField(token.NoPos, pkg, "PostForm", types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String])), false),
		types.NewField(token.NoPos, pkg, "RemoteAddr", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "RequestURI", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "TLS", tlsConfigPtr, false),
		types.NewField(token.NoPos, pkg, "Trailer", headerType, false),
		types.NewField(token.NoPos, pkg, "TransferEncoding", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Close", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Pattern", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "GetBody", types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", ioReadCloser),
				types.NewVar(token.NoPos, nil, "", errType)),
			false), false),
		types.NewField(token.NoPos, pkg, "Response", types.NewPointer(types.NewStruct(nil, nil)), false),
	}, nil)
	reqType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Request", nil),
		reqStruct, nil)
	scope.Insert(reqType.Obj())

	// type Response struct { Status string; StatusCode int; Proto string; Header Header; Body io.ReadCloser; ContentLength int64; ... }
	respStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Status", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "StatusCode", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Proto", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "ProtoMajor", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "ProtoMinor", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Header", headerType, false),
		types.NewField(token.NoPos, pkg, "Body", ioReadCloser, false),
		types.NewField(token.NoPos, pkg, "ContentLength", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Uncompressed", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Trailer", headerType, false),
		types.NewField(token.NoPos, pkg, "TransferEncoding", types.NewSlice(types.Typ[types.String]), false),
		types.NewField(token.NoPos, pkg, "Close", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Request", types.NewPointer(reqType), false),
		types.NewField(token.NoPos, pkg, "TLS", tlsConfigPtr, false),
	}, nil)
	respType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Response", nil),
		respStruct, nil)
	scope.Insert(respType.Obj())
	respPtr := types.NewPointer(respType)

	// func Get(url string) (*Response, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "url", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", respPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.Reader interface for body parameters
	ioReaderHTTP := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderHTTP.Complete()

	// func Post(url, contentType string, body io.Reader) (*Response, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Post",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "url", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "contentType", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "body", ioReaderHTTP)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", respPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Status codes
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusOK", types.Typ[types.Int],
		constant.MakeInt64(200)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusNotFound", types.Typ[types.Int],
		constant.MakeInt64(404)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusInternalServerError", types.Typ[types.Int],
		constant.MakeInt64(500)))

	// type ResponseWriter interface
	rwIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "WriteHeader",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "statusCode", types.Typ[types.Int])),
				nil, false)),
		types.NewFunc(token.NoPos, pkg, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerType)),
				false)),
	}, nil)
	rwIface.Complete()
	responseWriterType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ResponseWriter", nil),
		rwIface, nil)
	scope.Insert(responseWriterType.Obj())

	// type HandlerFunc func(ResponseWriter, *Request)
	handlerFuncSig := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "w", responseWriterType),
			types.NewVar(token.NoPos, nil, "r", types.NewPointer(reqType))),
		nil, false)
	handlerFuncType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "HandlerFunc", nil),
		handlerFuncSig, nil)
	scope.Insert(handlerFuncType.Obj())

	// type Handler interface
	handlerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ServeHTTP",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "w", responseWriterType),
					types.NewVar(token.NoPos, nil, "r", types.NewPointer(reqType))),
				nil, false)),
	}, nil)
	handlerIface.Complete()
	handlerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Handler", nil),
		handlerIface, nil)
	scope.Insert(handlerType.Obj())

	// type ServeMux struct
	muxType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ServeMux", nil), types.NewStruct(nil, nil), nil)
	muxPtr := types.NewPointer(muxType)
	scope.Insert(muxType.Obj())

	// func NewServeMux() *ServeMux
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewServeMux",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", muxPtr)),
			false)))

	// func Handle(pattern string, handler Handler)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Handle",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "handler", handlerType)),
			nil, false)))

	// func HandleFunc(pattern string, handler func(ResponseWriter, *Request))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HandleFunc",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "pattern", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "handler", handlerFuncSig)),
			nil, false)))

	// func ListenAndServe(addr string, handler Handler) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ListenAndServe",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "handler", handlerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ListenAndServeTLS(addr, certFile, keyFile string, handler Handler) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ListenAndServeTLS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "certFile", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "keyFile", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "handler", handlerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewRequest(method, url string, body io.Reader) (*Request, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRequest",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "method", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "url", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "body", ioReaderHTTP)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(reqType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Error(w ResponseWriter, error string, code int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriterType),
				types.NewVar(token.NoPos, pkg, "error", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "code", types.Typ[types.Int])),
			nil, false)))

	// func NotFound(w ResponseWriter, r *Request)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NotFound",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriterType),
				types.NewVar(token.NoPos, pkg, "r", types.NewPointer(reqType))),
			nil, false)))

	// func Redirect(w ResponseWriter, r *Request, url string, code int)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Redirect",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriterType),
				types.NewVar(token.NoPos, pkg, "r", types.NewPointer(reqType)),
				types.NewVar(token.NoPos, pkg, "url", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "code", types.Typ[types.Int])),
			nil, false)))

	// func StatusText(code int) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StatusText",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "code", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// type ConnState int
	connStateType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ConnState", nil),
		types.Typ[types.Int], nil)
	scope.Insert(connStateType.Obj())
	connStateType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", connStateType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StateNew", connStateType, constant.MakeInt64(0)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StateActive", connStateType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StateIdle", connStateType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StateHijacked", connStateType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StateClosed", connStateType, constant.MakeInt64(4)))

	// type Server struct
	serverType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Server", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Addr", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Handler", handlerType, false),
			types.NewField(token.NoPos, pkg, "TLSConfig", tlsConfigPtr, false),
			types.NewField(token.NoPos, pkg, "ReadTimeout", types.Typ[types.Int64], false),
			types.NewField(token.NoPos, pkg, "ReadHeaderTimeout", types.Typ[types.Int64], false),
			types.NewField(token.NoPos, pkg, "WriteTimeout", types.Typ[types.Int64], false),
			types.NewField(token.NoPos, pkg, "IdleTimeout", types.Typ[types.Int64], false),
			types.NewField(token.NoPos, pkg, "MaxHeaderBytes", types.Typ[types.Int], false),
			types.NewField(token.NoPos, pkg, "ConnState", types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "conn", netConnIface),
					types.NewVar(token.NoPos, nil, "state", connStateType)),
				nil, false), false),
			types.NewField(token.NoPos, pkg, "BaseContext", types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "l", listenerIface)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", ctxType)),
				false), false),
			types.NewField(token.NoPos, pkg, "ConnContext", types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "ctx", ctxType),
					types.NewVar(token.NoPos, nil, "c", netConnIface)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", ctxType)),
				false), false),
			types.NewField(token.NoPos, pkg, "ErrorLog", types.NewPointer(types.NewStruct(nil, nil)), false),
		}, nil), nil)
	scope.Insert(serverType.Obj())

	// type RoundTripper interface
	roundTripperIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "RoundTrip",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "req", types.NewPointer(reqType))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", respPtr),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	roundTripperIface.Complete()
	roundTripperType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RoundTripper", nil),
		roundTripperIface, nil)
	scope.Insert(roundTripperType.Obj())

	// CookieJar interface — forward declared, populated later with proper methods
	cookieJarType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CookieJar", nil),
		types.NewInterfaceType(nil, nil), nil)
	scope.Insert(cookieJarType.Obj())

	// type Client struct
	clientType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Client", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Transport", roundTripperType, false),
			types.NewField(token.NoPos, pkg, "CheckRedirect", types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "req", types.NewPointer(reqType)),
					types.NewVar(token.NoPos, nil, "via", types.NewSlice(types.NewPointer(reqType)))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false), false),
			types.NewField(token.NoPos, pkg, "Jar", cookieJarType, false),
			types.NewField(token.NoPos, pkg, "Timeout", types.Typ[types.Int64], false),
		}, nil), nil)
	scope.Insert(clientType.Obj())

	// Proxy func(*Request) (*url.URL, error)
	proxyFuncType := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(types.NewVar(token.NoPos, nil, "req", types.NewPointer(reqType))),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", urlPtr),
			types.NewVar(token.NoPos, nil, "", errType)),
		false)

	// DialContext func signature: func(ctx context.Context, network, addr string) (net.Conn, error)
	dialContextFunc := types.NewSignatureType(nil, nil, nil,
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "ctx", ctxType),
			types.NewVar(token.NoPos, nil, "network", types.Typ[types.String]),
			types.NewVar(token.NoPos, nil, "addr", types.Typ[types.String])),
		types.NewTuple(
			types.NewVar(token.NoPos, nil, "", netConnIface),
			types.NewVar(token.NoPos, nil, "", errType)),
		false)

	// type Transport struct
	transportType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Transport", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "TLSClientConfig", tlsConfigPtr, false),
			types.NewField(token.NoPos, pkg, "DisableKeepAlives", types.Typ[types.Bool], false),
			types.NewField(token.NoPos, pkg, "DisableCompression", types.Typ[types.Bool], false),
			types.NewField(token.NoPos, pkg, "MaxIdleConns", types.Typ[types.Int], false),
			types.NewField(token.NoPos, pkg, "MaxIdleConnsPerHost", types.Typ[types.Int], false),
			types.NewField(token.NoPos, pkg, "MaxConnsPerHost", types.Typ[types.Int], false),
			types.NewField(token.NoPos, pkg, "IdleConnTimeout", types.Typ[types.Int64], false),
			types.NewField(token.NoPos, pkg, "Proxy", proxyFuncType, false),
			types.NewField(token.NoPos, pkg, "DialContext", dialContextFunc, false),
			types.NewField(token.NoPos, pkg, "DialTLSContext", dialContextFunc, false),
			types.NewField(token.NoPos, pkg, "TLSHandshakeTimeout", types.Typ[types.Int64], false),
			types.NewField(token.NoPos, pkg, "ResponseHeaderTimeout", types.Typ[types.Int64], false),
			types.NewField(token.NoPos, pkg, "ExpectContinueTimeout", types.Typ[types.Int64], false),
			types.NewField(token.NoPos, pkg, "MaxResponseHeaderBytes", types.Typ[types.Int64], false),
			types.NewField(token.NoPos, pkg, "WriteBufferSize", types.Typ[types.Int], false),
			types.NewField(token.NoPos, pkg, "ReadBufferSize", types.Typ[types.Int], false),
			types.NewField(token.NoPos, pkg, "ForceAttemptHTTP2", types.Typ[types.Bool], false),
		}, nil), nil)
	scope.Insert(transportType.Obj())

	// type Cookie struct
	cookieType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Cookie", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Value", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Domain", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Expires", types.Typ[types.Int64], false),
			types.NewField(token.NoPos, pkg, "MaxAge", types.Typ[types.Int], false),
			types.NewField(token.NoPos, pkg, "Secure", types.Typ[types.Bool], false),
			types.NewField(token.NoPos, pkg, "HttpOnly", types.Typ[types.Bool], false),
			types.NewField(token.NoPos, pkg, "SameSite", types.Typ[types.Int], false),
			types.NewField(token.NoPos, pkg, "Raw", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Unparsed", types.NewSlice(types.Typ[types.String]), false),
		}, nil), nil)
	scope.Insert(cookieType.Obj())

	// HTTP method constants
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodGet", types.Typ[types.String], constant.MakeString("GET")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodPost", types.Typ[types.String], constant.MakeString("POST")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodPut", types.Typ[types.String], constant.MakeString("PUT")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodDelete", types.Typ[types.String], constant.MakeString("DELETE")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodHead", types.Typ[types.String], constant.MakeString("HEAD")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodPatch", types.Typ[types.String], constant.MakeString("PATCH")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodOptions", types.Typ[types.String], constant.MakeString("OPTIONS")))

	// More status codes
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusContinue", types.Typ[types.Int], constant.MakeInt64(100)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusMovedPermanently", types.Typ[types.Int], constant.MakeInt64(301)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusFound", types.Typ[types.Int], constant.MakeInt64(302)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusBadRequest", types.Typ[types.Int], constant.MakeInt64(400)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusUnauthorized", types.Typ[types.Int], constant.MakeInt64(401)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusForbidden", types.Typ[types.Int], constant.MakeInt64(403)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusMethodNotAllowed", types.Typ[types.Int], constant.MakeInt64(405)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusConflict", types.Typ[types.Int], constant.MakeInt64(409)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusGone", types.Typ[types.Int], constant.MakeInt64(410)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusTeapot", types.Typ[types.Int], constant.MakeInt64(418)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusTooManyRequests", types.Typ[types.Int], constant.MakeInt64(429)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusServiceUnavailable", types.Typ[types.Int], constant.MakeInt64(503)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusGatewayTimeout", types.Typ[types.Int], constant.MakeInt64(504)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusCreated", types.Typ[types.Int], constant.MakeInt64(201)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusAccepted", types.Typ[types.Int], constant.MakeInt64(202)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusNoContent", types.Typ[types.Int], constant.MakeInt64(204)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusNotModified", types.Typ[types.Int], constant.MakeInt64(304)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusUnprocessableEntity", types.Typ[types.Int], constant.MakeInt64(422)))

	// Default HTTP client/transport
	scope.Insert(types.NewVar(token.NoPos, pkg, "DefaultClient", types.NewPointer(clientType)))
	scope.Insert(types.NewVar(token.NoPos, pkg, "DefaultTransport", types.NewPointer(transportType)))
	scope.Insert(types.NewVar(token.NoPos, pkg, "DefaultServeMux", muxPtr))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrBodyNotAllowed", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrContentLength", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrMissingFile", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNotSupported", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrServerClosed", errType))

	// func Head(url string) (resp *Response, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Head",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "url", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", respPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func PostForm(url string, data url.Values) (resp *Response, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PostForm",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "url", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "data", types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String])))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", respPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NotFoundHandler() Handler
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NotFoundHandler",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handlerType)),
			false)))

	// func StripPrefix(prefix string, h Handler) Handler
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StripPrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "h", handlerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handlerType)),
			false)))

	// os.FileInfo stand-in for http.File.Stat return
	httpFileInfoIface := types.NewInterfaceType([]*types.Func{
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
	httpFileInfoIface.Complete()

	// type File interface (http.File - Read, Seek, Close, Readdir, Stat)
	httpFileIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceHTTP)),
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
		types.NewFunc(token.NoPos, nil, "Stat",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", httpFileInfoIface),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	httpFileIface.Complete()
	httpFileType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "File", nil),
		httpFileIface, nil)
	scope.Insert(httpFileType.Obj())

	// type FileSystem interface { Open(name string) (File, error) }
	fileSystemIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", httpFileType),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	fileSystemIface.Complete()
	fileSystemType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "FileSystem", nil),
		fileSystemIface, nil)
	scope.Insert(fileSystemType.Obj())

	// type Dir string
	dirType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Dir", nil),
		types.Typ[types.String], nil)
	scope.Insert(dirType.Obj())

	scope.Insert(types.NewFunc(token.NoPos, pkg, "FileServer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "root", fileSystemType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handlerType)),
			false)))

	// func MaxBytesReader(w ResponseWriter, r io.ReadCloser, n int64) io.ReadCloser
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MaxBytesReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriterType),
				types.NewVar(token.NoPos, pkg, "r", ioReadCloser),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ioReadCloser)),
			false)))

	reqPtr := types.NewPointer(reqType)
	serverPtr := types.NewPointer(serverType)
	clientPtr := types.NewPointer(clientType)
	cookiePtr := types.NewPointer(cookieType)
	byteSlice := types.NewSlice(types.Typ[types.Byte])
	ioReader := ioReaderHTTP

	// io.Writer interface for Write methods
	ioWriterHTTP := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterHTTP.Complete()

	// ---- Header methods ----
	headerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "h", headerType), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			nil, false)))
	headerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "h", headerType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	headerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "h", headerType), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			nil, false)))
	headerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Del",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "h", headerType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			nil, false)))
	headerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Values",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "h", headerType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String]))),
			false)))
	headerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "h", headerType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", headerType)),
			false)))
	headerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "h", headerType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", ioWriterHTTP)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// ---- Request methods ----
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "FormValue",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "PostFormValue",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "UserAgent",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "Referer",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "Context",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ctxType)),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", ctxType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", reqPtr)),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cookie",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", cookiePtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cookies",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(cookiePtr))),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddCookie",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "c", cookiePtr)),
			nil, false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "BasicAuth",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "username", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "password", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "ok", types.Typ[types.Bool])),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetBasicAuth",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "username", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "password", types.Typ[types.String])),
			nil, false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "ParseForm",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "ParseMultipartForm",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "maxMemory", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "ProtoAtLeast",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "major", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "minor", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", ioWriterHTTP)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "WithContext",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", ctxType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", reqPtr)),
			false)))
	// *multipart.Reader stand-in
	multipartReaderPtr := types.NewPointer(types.NewStruct(nil, nil))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "MultipartReader",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", multipartReaderPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Request.FormFile(key string) (multipart.File, *multipart.FileHeader, error)
	multipartFileIface := types.NewInterfaceType([]*types.Func{
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
	multipartFileIface.Complete()
	multipartFileHeaderPtr := types.NewPointer(types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, nil, "Filename", types.Typ[types.String], false),
		types.NewField(token.NoPos, nil, "Size", types.Typ[types.Int64], false),
	}, nil))
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "FormFile",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", multipartFileIface),
				types.NewVar(token.NoPos, nil, "", multipartFileHeaderPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Request.WriteProxy(w io.Writer) error
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteProxy",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", ioWriterHTTP)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Request.PathValue(name string) string — Go 1.22+
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "PathValue",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// Request.SetPathValue(name, value string) — Go 1.22+
	reqType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetPathValue",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", reqPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			nil, false)))

	// ---- Response methods ----
	respType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cookies",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", respPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewSlice(cookiePtr))),
			false)))
	respType.AddMethod(types.NewFunc(token.NoPos, pkg, "Location",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", respPtr), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", urlPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	respType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", respPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", ioWriterHTTP)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	respType.AddMethod(types.NewFunc(token.NoPos, pkg, "ProtoAtLeast",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", respPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "major", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "minor", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))

	// ---- Client methods ----
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Do",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", clientPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "req", reqPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", respPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", clientPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "url", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", respPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Post",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", clientPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "url", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "contentType", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "body", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", respPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Head",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", clientPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "url", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", respPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	clientType.AddMethod(types.NewFunc(token.NoPos, nil, "PostForm",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", clientPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "url", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "data", types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String])))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", respPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "CloseIdleConnections",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", clientPtr), nil, nil, nil, nil, false)))

	// ---- Server methods ----
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "ListenAndServe",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "srv", serverPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "ListenAndServeTLS",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "srv", serverPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "certFile", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "keyFile", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Shutdown",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "srv", serverPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "ctx", ctxType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "srv", serverPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Serve",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "srv", serverPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "l", listenerIface)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "ServeTLS",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "srv", serverPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "l", listenerIface),
				types.NewVar(token.NoPos, nil, "certFile", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "keyFile", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "RegisterOnShutdown",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "srv", serverPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "f", types.NewSignatureType(nil, nil, nil, nil, nil, false))),
			nil, false)))
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetKeepAlivesEnabled",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "srv", serverPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "v", types.Typ[types.Bool])),
			nil, false)))

	// ---- ServeMux methods ----
	muxType.AddMethod(types.NewFunc(token.NoPos, pkg, "Handle",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "mux", muxPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pattern", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "handler", handlerType)),
			nil, false)))
	muxType.AddMethod(types.NewFunc(token.NoPos, pkg, "HandleFunc",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "mux", muxPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "pattern", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "handler", handlerFuncSig)),
			nil, false)))
	muxType.AddMethod(types.NewFunc(token.NoPos, pkg, "ServeHTTP",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "mux", muxPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "w", responseWriterType),
				types.NewVar(token.NoPos, nil, "r", reqPtr)),
			nil, false)))
	muxType.AddMethod(types.NewFunc(token.NoPos, pkg, "Handler",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "mux", muxPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", reqPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "h", handlerType),
				types.NewVar(token.NoPos, nil, "pattern", types.Typ[types.String])),
			false)))

	// HandlerFunc.ServeHTTP
	handlerFuncType.AddMethod(types.NewFunc(token.NoPos, pkg, "ServeHTTP",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "f", handlerFuncType), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "w", responseWriterType),
				types.NewVar(token.NoPos, nil, "r", reqPtr)),
			nil, false)))

	// ---- Cookie methods ----
	cookieType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", cookiePtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	cookieType.AddMethod(types.NewFunc(token.NoPos, pkg, "Valid",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", cookiePtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// ---- Additional package functions ----
	// func NewRequestWithContext(ctx context.Context, method, url string, body io.Reader) (*Request, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRequestWithContext",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxType),
				types.NewVar(token.NoPos, pkg, "method", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "url", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "body", ioReader)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", reqPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func SetCookie(w ResponseWriter, cookie *Cookie)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SetCookie",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriterType),
				types.NewVar(token.NoPos, pkg, "cookie", cookiePtr)),
			nil, false)))

	// func CanonicalHeaderKey(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CanonicalHeaderKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func DetectContentType(data []byte) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DetectContentType",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "data", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func ProxyFromEnvironment(req *Request) (*url.URL, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ProxyFromEnvironment",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "req", reqPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", urlPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ProxyURL(fixedURL *url.URL) func(*Request) (*url.URL, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ProxyURL",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fixedURL", urlPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", proxyFuncType)),
			false)))

	// func TimeoutHandler(h Handler, dt time.Duration, msg string) Handler
	scope.Insert(types.NewFunc(token.NoPos, pkg, "TimeoutHandler",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", handlerType),
				types.NewVar(token.NoPos, pkg, "dt", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "msg", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handlerType)),
			false)))

	// func AllowQuerySemicolons(h Handler) Handler
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AllowQuerySemicolons",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "h", handlerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handlerType)),
			false)))

	// type Flusher interface { Flush() }
	flusherIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Flush",
			types.NewSignatureType(nil, nil, nil, nil, nil, false)),
	}, nil)
	flusherIface.Complete()
	scope.Insert(types.NewTypeName(token.NoPos, pkg, "Flusher",
		types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Flusher", nil), flusherIface, nil)))

	// type SameSite int
	sameSiteType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SameSite", nil), types.Typ[types.Int], nil)
	scope.Insert(sameSiteType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "SameSiteDefaultMode", sameSiteType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SameSiteLaxMode", sameSiteType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SameSiteStrictMode", sameSiteType, constant.MakeInt64(3)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "SameSiteNoneMode", sameSiteType, constant.MakeInt64(4)))

	// More status codes
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusSwitchingProtocols", types.Typ[types.Int], constant.MakeInt64(101)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusResetContent", types.Typ[types.Int], constant.MakeInt64(205)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusPartialContent", types.Typ[types.Int], constant.MakeInt64(206)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusTemporaryRedirect", types.Typ[types.Int], constant.MakeInt64(307)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusPermanentRedirect", types.Typ[types.Int], constant.MakeInt64(308)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusRequestEntityTooLarge", types.Typ[types.Int], constant.MakeInt64(413)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusRequestURITooLong", types.Typ[types.Int], constant.MakeInt64(414)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusUnsupportedMediaType", types.Typ[types.Int], constant.MakeInt64(415)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusNotImplemented", types.Typ[types.Int], constant.MakeInt64(501)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusBadGateway", types.Typ[types.Int], constant.MakeInt64(502)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusSeeOther", types.Typ[types.Int], constant.MakeInt64(303)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusUseProxy", types.Typ[types.Int], constant.MakeInt64(305)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusPaymentRequired", types.Typ[types.Int], constant.MakeInt64(402)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusNotAcceptable", types.Typ[types.Int], constant.MakeInt64(406)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusProxyAuthRequired", types.Typ[types.Int], constant.MakeInt64(407)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusRequestTimeout", types.Typ[types.Int], constant.MakeInt64(408)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusLengthRequired", types.Typ[types.Int], constant.MakeInt64(411)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusPreconditionFailed", types.Typ[types.Int], constant.MakeInt64(412)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusExpectationFailed", types.Typ[types.Int], constant.MakeInt64(417)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusMisdirectedRequest", types.Typ[types.Int], constant.MakeInt64(421)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusLocked", types.Typ[types.Int], constant.MakeInt64(423)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusUpgradeRequired", types.Typ[types.Int], constant.MakeInt64(426)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusPreconditionRequired", types.Typ[types.Int], constant.MakeInt64(428)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusRequestHeaderFieldsTooLarge", types.Typ[types.Int], constant.MakeInt64(431)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusUnavailableForLegalReasons", types.Typ[types.Int], constant.MakeInt64(451)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusInsufficientStorage", types.Typ[types.Int], constant.MakeInt64(507)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusLoopDetected", types.Typ[types.Int], constant.MakeInt64(508)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusNetworkAuthenticationRequired", types.Typ[types.Int], constant.MakeInt64(511)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusMultiStatus", types.Typ[types.Int], constant.MakeInt64(207)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusAlreadyReported", types.Typ[types.Int], constant.MakeInt64(208)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusIMUsed", types.Typ[types.Int], constant.MakeInt64(226)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusMultipleChoices", types.Typ[types.Int], constant.MakeInt64(300)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusNonAuthoritativeInfo", types.Typ[types.Int], constant.MakeInt64(203)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusProcessing", types.Typ[types.Int], constant.MakeInt64(102)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "StatusEarlyHints", types.Typ[types.Int], constant.MakeInt64(103)))

	// MethodConnect, MethodTrace
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodConnect", types.Typ[types.String], constant.MakeString("CONNECT")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "MethodTrace", types.Typ[types.String], constant.MakeString("TRACE")))

	// var ErrAbortHandler, ErrHandlerTimeout, ErrLineTooLong, ErrNoCookie, ErrNoLocation
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrAbortHandler", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrHandlerTimeout", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrLineTooLong", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNoCookie", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNoLocation", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrUseLastResponse", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrBodyNotAllowed", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrContentLength", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrBodyReadAfterClose", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrHijacked", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrMissingFile", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNotMultipart", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrNotSupported", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrServerClosed", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrSkipAltProtocol", errType))

	// const DefaultMaxHeaderBytes int
	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultMaxHeaderBytes", types.Typ[types.Int], constant.MakeInt64(1<<20)))
	// const TrailerPrefix string
	scope.Insert(types.NewConst(token.NoPos, pkg, "TrailerPrefix", types.Typ[types.String], constant.MakeString("Trailer:")))
	// const DefaultMaxIdleConnsPerHost int
	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultMaxIdleConnsPerHost", types.Typ[types.Int], constant.MakeInt64(2)))

	// func ParseHTTPVersion(vers string) (major, minor int, ok bool)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseHTTPVersion",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "vers", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "major", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "minor", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "ok", types.Typ[types.Bool])),
			false)))

	// func ParseTime(text string) (t time.Time, err error) — time.Time as int64
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseTime",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "text", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func MaxBytesHandler(h Handler, n int64) Handler
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MaxBytesHandler",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "h", handlerType),
				types.NewVar(token.NoPos, pkg, "n", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handlerType)),
			false)))

	// func RedirectHandler(url string, code int) Handler
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RedirectHandler",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "url", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "code", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handlerType)),
			false)))

	// func StripPrefix(prefix string, h Handler) Handler
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StripPrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "prefix", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "h", handlerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handlerType)),
			false)))

	// func StatusText(code int) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "StatusText",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "code", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// fs.FS stand-in (interface with Open method)
	fsIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Open",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil)),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	fsIface.Complete()

	// func FileServerFS(root fs.FS) Handler — Go 1.22+
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FileServerFS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "root", fsIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", handlerType)),
			false)))

	// func ServeFileFS(w ResponseWriter, r *Request, fsys fs.FS, name string) — Go 1.22+
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ServeFileFS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriterType),
				types.NewVar(token.NoPos, pkg, "r", reqPtr),
				types.NewVar(token.NoPos, pkg, "fsys", fsIface),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			nil, false)))

	// func FS(fsys fs.FS) FileSystem — Go 1.16+
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "fsys", fsIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", fileSystemType)),
			false)))

	// func ParseCookie(line string) ([]*Cookie, error) — Go 1.23+
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseCookie",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "line", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(cookiePtr)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseSetCookie(line string) (*Cookie, error) — Go 1.23+
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseSetCookie",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "line", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", cookiePtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// ---- Transport methods ----
	transportPtr := types.NewPointer(transportType)
	transportType.AddMethod(types.NewFunc(token.NoPos, pkg, "RoundTrip",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "t", transportPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "req", reqPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", respPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	transportType.AddMethod(types.NewFunc(token.NoPos, pkg, "CloseIdleConnections",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "t", transportPtr), nil, nil, nil, nil, false)))
	transportType.AddMethod(types.NewFunc(token.NoPos, pkg, "Clone",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "t", transportPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", transportPtr)),
			false)))

	// ---- Additional package-level functions ----
	// func ServeFile(w ResponseWriter, r *Request, name string)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ServeFile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriterType),
				types.NewVar(token.NoPos, pkg, "r", reqPtr),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			nil, false)))

	// func ServeContent(w ResponseWriter, req *Request, name string, modtime time.Time, content io.ReadSeeker)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ServeContent",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriterType),
				types.NewVar(token.NoPos, pkg, "req", reqPtr),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "modtime", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "content", ioReadSeekerIface)),
			nil, false)))

	// func Serve(l net.Listener, handler Handler) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Serve",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "l", listenerIface),
				types.NewVar(token.NoPos, pkg, "handler", handlerType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ServeTLS(l net.Listener, handler Handler, certFile, keyFile string) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ServeTLS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "l", listenerIface),
				types.NewVar(token.NoPos, pkg, "handler", handlerType),
				types.NewVar(token.NoPos, pkg, "certFile", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "keyFile", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// *bufio.Reader stand-in (opaque struct pointer with Read method)
	bufioReaderStruct := types.NewStruct(nil, nil)
	bufioReaderType := types.NewNamed(types.NewTypeName(token.NoPos, nil, "Reader", nil), bufioReaderStruct, nil)
	bufioReaderPtr := types.NewPointer(bufioReaderType)

	// func ReadRequest(b *bufio.Reader) (*Request, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadRequest",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", bufioReaderPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", reqPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ReadResponse(r *bufio.Reader, req *Request) (*Response, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadResponse",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "r", bufioReaderPtr),
				types.NewVar(token.NoPos, pkg, "req", reqPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", respPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type RoundTripper interface { RoundTrip(*Request) (*Response, error) }
	rtIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "RoundTrip",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "req", reqPtr)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", respPtr),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	rtIface.Complete()
	rtType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "RoundTripper", nil),
		rtIface, nil)
	scope.Insert(rtType.Obj())

	// type CookieJar interface { SetCookies, Cookies }
	cookieSlice := types.NewSlice(types.NewPointer(cookieType))
	// Reuse urlPtr (*url.URL) defined above
	cjIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "SetCookies",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "u", urlPtr),
					types.NewVar(token.NoPos, nil, "cookies", cookieSlice)),
				nil, false)),
		types.NewFunc(token.NoPos, pkg, "Cookies",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "u", urlPtr)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", cookieSlice)), false)),
	}, nil)
	cjIface.Complete()
	// Update the forward-declared CookieJar with proper interface methods
	cookieJarType.SetUnderlying(cjIface)

	// type Flusher interface { Flush() } - already defined above
	// type Hijacker interface { Hijack() (net.Conn, *bufio.ReadWriter, error) }
	// *bufio.ReadWriter stand-in for Hijacker
	bufioRWPtr := types.NewPointer(types.NewStruct(nil, nil))
	hijackerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Hijack",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", netConnIface),
					types.NewVar(token.NoPos, nil, "", bufioRWPtr),
					types.NewVar(token.NoPos, nil, "", errType)), false)),
	}, nil)
	hijackerIface.Complete()
	hijackerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Hijacker", nil),
		hijackerIface, nil)
	scope.Insert(hijackerType.Obj())

	// type CloseNotifier interface { CloseNotify() <-chan bool } (deprecated but still used)
	closeNotifierIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "CloseNotify",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "",
					types.NewChan(types.RecvOnly, types.Typ[types.Bool]))), false)),
	}, nil)
	closeNotifierIface.Complete()
	closeNotifierType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CloseNotifier", nil),
		closeNotifierIface, nil)
	scope.Insert(closeNotifierType.Obj())

	// type PushOptions struct { Method string; Header Header }
	pushOptsStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Method", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Header", headerType, false),
	}, nil)
	pushOptsType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "PushOptions", nil),
		pushOptsStruct, nil)
	scope.Insert(pushOptsType.Obj())
	pushOptsPtr := types.NewPointer(pushOptsType)

	// type Pusher interface { Push(target string, opts *PushOptions) error }
	pusherIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Push",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "target", types.Typ[types.String]),
					types.NewVar(token.NoPos, nil, "opts", pushOptsPtr)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	pusherIface.Complete()
	pusherType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Pusher", nil),
		pusherIface, nil)
	scope.Insert(pusherType.Obj())

	_ = byteSlice

	// type CrossOriginProtection struct (Go 1.25+)
	copStruct := types.NewStruct(nil, nil)
	copType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "CrossOriginProtection", nil),
		copStruct, nil)
	scope.Insert(copType.Obj())
	copPtr := types.NewPointer(copType)
	copRecv := types.NewVar(token.NoPos, nil, "c", copPtr)
	// (*CrossOriginProtection).Handler(h Handler) Handler
	copType.AddMethod(types.NewFunc(token.NoPos, pkg, "Handler",
		types.NewSignatureType(copRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "h", handlerType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", handlerType)),
			false)))

	// type MaxBytesError struct { Limit int64 } (Go 1.19+)
	maxBytesErrorStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Limit", types.Typ[types.Int64], false),
	}, nil)
	maxBytesErrorType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "MaxBytesError", nil),
		maxBytesErrorStruct, nil)
	scope.Insert(maxBytesErrorType.Obj())
	maxBytesErrorPtr := types.NewPointer(maxBytesErrorType)
	maxBytesErrorRecv := types.NewVar(token.NoPos, nil, "e", maxBytesErrorPtr)
	maxBytesErrorType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(maxBytesErrorRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// type ResponseController struct (Go 1.20+)
	rcStruct := types.NewStruct(nil, nil)
	rcType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ResponseController", nil),
		rcStruct, nil)
	scope.Insert(rcType.Obj())
	rcPtr := types.NewPointer(rcType)
	rcRecv := types.NewVar(token.NoPos, nil, "c", rcPtr)

	// func NewResponseController(rw ResponseWriter) *ResponseController
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewResponseController",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "rw", responseWriterType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", rcPtr)),
			false)))

	// ResponseController methods
	rcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(rcRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	rcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Hijack",
		types.NewSignatureType(rcRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", netConnIface),
				types.NewVar(token.NoPos, nil, "", bufioRWPtr),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	// time.Time stand-in for SetReadDeadline/SetWriteDeadline
	timeStandIn := types.Typ[types.Int64]
	rcType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetReadDeadline",
		types.NewSignatureType(rcRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "deadline", timeStandIn)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	rcType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetWriteDeadline",
		types.NewSignatureType(rcRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "deadline", timeStandIn)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildNetHTTPPprofPackage() *types.Package {
	pkg := types.NewPackage("net/http/pprof", "pprof")
	scope := pkg.Scope()

	// http.ResponseWriter interface { Header() Header; Write([]byte) (int, error); WriteHeader(statusCode int) }
	errTypePprof := types.Universe.Lookup("error").Type()
	headerMapType := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))
	responseWriter := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerMapType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte]))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errTypePprof)),
				false)),
		types.NewFunc(token.NoPos, nil, "WriteHeader",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "statusCode", types.Typ[types.Int])),
				nil, false)),
	}, nil)
	responseWriter.Complete()
	// *http.Request (simplified as pointer to empty struct)
	requestStruct := types.NewStruct(nil, nil)
	requestPtr := types.NewPointer(requestStruct)

	// func Index(w http.ResponseWriter, r *http.Request)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Index",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriter),
				types.NewVar(token.NoPos, pkg, "r", requestPtr)),
			nil, false)))

	// func Cmdline(w http.ResponseWriter, r *http.Request)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Cmdline",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriter),
				types.NewVar(token.NoPos, pkg, "r", requestPtr)),
			nil, false)))

	// func Profile(w http.ResponseWriter, r *http.Request)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Profile",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriter),
				types.NewVar(token.NoPos, pkg, "r", requestPtr)),
			nil, false)))

	// func Symbol(w http.ResponseWriter, r *http.Request)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Symbol",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriter),
				types.NewVar(token.NoPos, pkg, "r", requestPtr)),
			nil, false)))

	// func Trace(w http.ResponseWriter, r *http.Request)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Trace",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "w", responseWriter),
				types.NewVar(token.NoPos, pkg, "r", requestPtr)),
			nil, false)))

	// func Handler(name string) http.Handler
	// http.Handler: interface with ServeHTTP(ResponseWriter, *Request)
	httpHandlerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ServeHTTP",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "w", responseWriter),
					types.NewVar(token.NoPos, nil, "r", requestPtr)),
				nil, false)),
	}, nil)
	httpHandlerIface.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Handler",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", httpHandlerIface)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildNetHTTPTestPackage() *types.Package {
	pkg := types.NewPackage("net/http/httptest", "httptest")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// http.Handler interface with ServeHTTP(ResponseWriter, *Request)
	// http.ResponseWriter interface { Header(); Write(); WriteHeader() }
	headerMapHT := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))
	rwIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Header",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", headerMapHT)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", types.NewSlice(types.Typ[types.Byte]))),
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
	reqPtrHandler := types.NewPointer(types.NewStruct(nil, nil)) // simplified *Request
	handlerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "ServeHTTP",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "w", rwIface),
					types.NewVar(token.NoPos, nil, "r", reqPtrHandler)),
				nil, false)),
	}, nil)
	handlerIface.Complete()

	// net.Listener interface with Accept, Close, Addr
	netAddrIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Network",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
	}, nil)
	netAddrIface.Complete()
	// net.Conn interface for Accept return
	netConnIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
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
	netConnIface.Complete()
	listenerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Accept",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", netConnIface),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Addr",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", netAddrIface)),
				false)),
	}, nil)
	listenerIface.Complete()

	// *tls.Config (opaque)
	tlsConfigStruct := types.NewStruct(nil, nil)
	tlsConfigPtr := types.NewPointer(tlsConfigStruct)

	// *http.Server (opaque)
	httpServerStruct := types.NewStruct(nil, nil)
	httpServerPtr := types.NewPointer(httpServerStruct)

	// *http.Client (opaque)
	httpClientStruct := types.NewStruct(nil, nil)
	httpClientPtr := types.NewPointer(httpClientStruct)

	// *x509.Certificate (opaque)
	certStruct := types.NewStruct(nil, nil)
	certPtr := types.NewPointer(certStruct)

	// *http.Response (opaque)
	responseStruct := types.NewStruct(nil, nil)
	responsePtr := types.NewPointer(responseStruct)

	// *http.Request (opaque)
	requestStruct := types.NewStruct(nil, nil)
	requestPtr := types.NewPointer(requestStruct)

	// http.Header type (map[string][]string)
	headerType := types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String]))

	// io.Reader interface
	byteSliceHTTPUtil := types.NewSlice(types.Typ[types.Byte])
	ioReader := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceHTTPUtil)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReader.Complete()

	// *bytes.Buffer
	bufferStruct := types.NewStruct(nil, nil)
	bufferPtr := types.NewPointer(bufferStruct)

	// type Server struct
	serverStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "URL", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Listener", listenerIface, false),
		types.NewField(token.NoPos, pkg, "EnableHTTP2", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "TLS", tlsConfigPtr, false),
		types.NewField(token.NoPos, pkg, "Config", httpServerPtr, false),
	}, nil)
	serverType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Server", nil),
		serverStruct, nil)
	scope.Insert(serverType.Obj())
	serverPtr := types.NewPointer(serverType)

	// func NewServer(handler http.Handler) *Server
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewServer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "handler", handlerIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", serverPtr)),
			false)))

	// func NewTLSServer(handler http.Handler) *Server
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewTLSServer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "handler", handlerIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", serverPtr)),
			false)))

	// func NewUnstartedServer(handler http.Handler) *Server
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewUnstartedServer",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "handler", handlerIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", serverPtr)),
			false)))

	// Server methods
	srvRecv := types.NewVar(token.NoPos, nil, "s", serverPtr)
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(srvRecv, nil, nil, nil, nil, false)))

	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "CloseClientConnections",
		types.NewSignatureType(srvRecv, nil, nil, nil, nil, false)))

	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Start",
		types.NewSignatureType(srvRecv, nil, nil, nil, nil, false)))

	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "StartTLS",
		types.NewSignatureType(srvRecv, nil, nil, nil, nil, false)))

	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Client",
		types.NewSignatureType(srvRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", httpClientPtr)),
			false)))

	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Certificate",
		types.NewSignatureType(srvRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", certPtr)),
			false)))

	// type ResponseRecorder struct
	recorderStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Code", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "HeaderMap", headerType, false),
		types.NewField(token.NoPos, pkg, "Body", bufferPtr, false),
		types.NewField(token.NoPos, pkg, "Flushed", types.Typ[types.Bool], false),
	}, nil)
	recorderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ResponseRecorder", nil),
		recorderStruct, nil)
	scope.Insert(recorderType.Obj())
	recorderPtr := types.NewPointer(recorderType)

	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRecorder",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", recorderPtr)),
			false)))

	// ResponseRecorder methods
	rwRecv := types.NewVar(token.NoPos, nil, "rw", recorderPtr)
	recorderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Header",
		types.NewSignatureType(rwRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", headerType)),
			false)))

	recorderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(rwRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "buf", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	recorderType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteString",
		types.NewSignatureType(rwRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "str", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	recorderType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteHeader",
		types.NewSignatureType(rwRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "code", types.Typ[types.Int])),
			nil, false)))

	recorderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Flush",
		types.NewSignatureType(rwRecv, nil, nil, nil, nil, false)))

	recorderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Result",
		types.NewSignatureType(rwRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", responsePtr)),
			false)))

	// func NewRequest(method, target string, body io.Reader) *http.Request
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRequest",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "method", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "target", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "body", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", requestPtr)),
			false)))

	// NewRequestWithContext(ctx context.Context, method, target string, body io.Reader) *http.Request
	ctxIface := types.NewInterfaceType([]*types.Func{
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
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Value",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.NewInterfaceType(nil, nil))),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewInterfaceType(nil, nil))),
				false)),
	}, nil)
	ctxIface.Complete()
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewRequestWithContext",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ctx", ctxIface),
				types.NewVar(token.NoPos, pkg, "method", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "target", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "body", ioReader)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", requestPtr)),
			false)))

	// DefaultRemoteAddr constant
	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultRemoteAddr",
		types.Typ[types.String], constant.MakeString("1.2.3.4")))

	pkg.MarkComplete()
	return pkg
}

// buildNetHTTPUtilPackage creates the type-checked net/http/httputil package stub.
func buildNetHTTPUtilPackage() *types.Package {
	pkg := types.NewPackage("net/http/httputil", "httputil")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// io types for BufferPool
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// BufferPool interface
	bufferPoolIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Get", types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)),
		types.NewFunc(token.NoPos, pkg, "Put", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "buf", byteSlice)), nil, false)),
	}, nil)
	bufferPoolIface.Complete()
	bufferPoolType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "BufferPool", nil),
		bufferPoolIface, nil)
	scope.Insert(bufferPoolType.Obj())

	// *http.Request opaque pointer stand-in
	httpReqPtr := types.NewPointer(types.NewStruct(nil, nil))

	// ProxyRequest type
	proxyReqStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "In", httpReqPtr, false),
		types.NewField(token.NoPos, pkg, "Out", httpReqPtr, false),
	}, nil)
	proxyReqType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ProxyRequest", nil),
		proxyReqStruct, nil)
	scope.Insert(proxyReqType.Obj())
	proxyReqRecv := types.NewVar(token.NoPos, nil, "r", types.NewPointer(proxyReqType))

	// ProxyRequest.SetURL(target *url.URL)
	urlPtr := types.NewPointer(types.NewStruct(nil, nil))
	proxyReqType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetURL",
		types.NewSignatureType(proxyReqRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "target", urlPtr)),
			nil, false)))
	// ProxyRequest.SetXForwarded()
	proxyReqType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetXForwarded",
		types.NewSignatureType(proxyReqRecv, nil, nil, nil, nil, false)))

	// ReverseProxy struct - Director, Rewrite, FlushInterval, ErrorLog, BufferPool, Transport
	reverseProxyStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Director", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "req", httpReqPtr)), nil, false), false),
		types.NewField(token.NoPos, pkg, "Rewrite", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", types.NewPointer(proxyReqType))), nil, false), false),
		types.NewField(token.NoPos, pkg, "Transport", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "FlushInterval", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "ErrorLog", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "BufferPool", bufferPoolType, false),
		types.NewField(token.NoPos, pkg, "ModifyResponse", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "resp", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false), false),
		types.NewField(token.NoPos, pkg, "ErrorHandler", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "rw", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "req", httpReqPtr),
				types.NewVar(token.NoPos, nil, "err", errType)), nil, false), false),
	}, nil)
	reverseProxyType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ReverseProxy", nil),
		reverseProxyStruct, nil)
	scope.Insert(reverseProxyType.Obj())

	// ReverseProxy.ServeHTTP(rw, req)
	reverseProxyType.AddMethod(types.NewFunc(token.NoPos, pkg, "ServeHTTP",
		types.NewSignatureType(
			types.NewVar(token.NoPos, pkg, "p", types.NewPointer(reverseProxyType)), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "rw", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "req", types.Typ[types.Int])),
			nil, false)))

	// NewSingleHostReverseProxy(target *url.URL) *ReverseProxy
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewSingleHostReverseProxy",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "target", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.NewPointer(reverseProxyType))),
			false)))

	// DumpRequest(req *http.Request, body bool) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DumpRequest",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "req", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "body", types.Typ[types.Bool])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// DumpRequestOut(req *http.Request, body bool) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DumpRequestOut",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "req", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "body", types.Typ[types.Bool])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// DumpResponse(resp *http.Response, body bool) ([]byte, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DumpResponse",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "resp", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "body", types.Typ[types.Bool])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", byteSlice),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// io.Reader stand-in for NewChunkedReader
	httputilReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	httputilReaderIface.Complete()

	// io.Writer stand-in for NewChunkedWriter
	httputilWriterIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	httputilWriterIface.Complete()

	// io.WriteCloser stand-in for NewChunkedWriter return
	httputilWriteCloserIface := types.NewInterfaceType([]*types.Func{
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
	httputilWriteCloserIface.Complete()

	// NewChunkedReader(r io.Reader) io.Reader
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewChunkedReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", httputilReaderIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", httputilReaderIface)),
			false)))

	// NewChunkedWriter(w io.Writer) io.WriteCloser
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewChunkedWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "w", httputilWriterIface)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", httputilWriteCloserIface)),
			false)))

	// Deprecated error variables
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrPersistEOF", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrClosed", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrPipeline", errType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrLineTooLong", errType))

	pkg.MarkComplete()
	return pkg
}

// buildNetMailPackage creates the type-checked net/mail package stub.
func buildNetMailPackage() *types.Package {
	pkg := types.NewPackage("net/mail", "mail")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	byteSliceMail := types.NewSlice(types.Typ[types.Byte])

	// io.Reader interface { Read(p []byte) (n int, err error) }
	ioReaderIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSliceMail)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioReaderIface.Complete()

	// type Header map[string][]string
	headerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Header", nil),
		types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String])), nil)
	scope.Insert(headerType.Obj())

	// Header.Get(key string) string
	headerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "h", headerType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	// Header.Date() (time.Time, error) - simplified as (int64, error)
	headerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Date",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "h", headerType), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// type Address struct
	addrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Address", types.Typ[types.String], false),
	}, nil)
	addrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Address", nil),
		addrStruct, nil)
	scope.Insert(addrType.Obj())
	addrPtr := types.NewPointer(addrType)

	// Address.String() string
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "a", addrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type Message struct
	msgStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Header", headerType, false),
		types.NewField(token.NoPos, pkg, "Body", ioReaderIface, false),
	}, nil)
	msgType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Message", nil),
		msgStruct, nil)
	scope.Insert(msgType.Obj())

	// func ReadMessage(r io.Reader) (*Message, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ReadMessage",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "r", ioReaderIface)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewPointer(msgType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseAddress(address string) (*Address, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseAddress",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", addrPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseAddressList(list string) ([]*Address, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseAddressList",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "list", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(addrPtr)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Header.AddressList(key string) ([]*Address, error)
	headerType.AddMethod(types.NewFunc(token.NoPos, pkg, "AddressList",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "h", headerType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(addrPtr)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// type AddressParser struct { WordDecoder *mime.WordDecoder }
	addrParserStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "WordDecoder", types.NewPointer(types.NewStruct(nil, nil)), false),
	}, nil)
	addrParserType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "AddressParser", nil), addrParserStruct, nil)
	scope.Insert(addrParserType.Obj())
	apPtr := types.NewPointer(addrParserType)
	addrParserType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", apPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", addrPtr),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	addrParserType.AddMethod(types.NewFunc(token.NoPos, pkg, "ParseList",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", apPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "list", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(addrPtr)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func ParseDate(date string) (time.Time, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseDate",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "date", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// var ErrHeaderNotPresent error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrHeaderNotPresent", errType))

	pkg.MarkComplete()
	return pkg
}

func buildNetNetipPackage() *types.Package {
	pkg := types.NewPackage("net/netip", "netip")
	scope := pkg.Scope()

	// type Addr struct { ... }
	addrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "hi", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "lo", types.Typ[types.Uint64], false),
		types.NewField(token.NoPos, pkg, "z", types.Typ[types.Int], false),
	}, nil)
	addrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Addr", nil),
		addrStruct, nil)
	scope.Insert(addrType.Obj())

	// type AddrPort struct { ... }
	addrPortStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ip", addrType, false),
		types.NewField(token.NoPos, pkg, "port", types.Typ[types.Uint16], false),
	}, nil)
	addrPortType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "AddrPort", nil),
		addrPortStruct, nil)
	scope.Insert(addrPortType.Obj())

	// type Prefix struct { ... }
	prefixStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ip", addrType, false),
		types.NewField(token.NoPos, pkg, "bits", types.Typ[types.Int], false),
	}, nil)
	prefixType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Prefix", nil),
		prefixStruct, nil)
	scope.Insert(prefixType.Obj())

	errType := types.Universe.Lookup("error").Type()

	// Addr constructors
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddrFrom4",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", types.NewArray(types.Typ[types.Byte], 4))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddrFrom16",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", types.NewArray(types.Typ[types.Byte], 16))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddrFromSlice",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "slice", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", addrType),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MustParseAddr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseAddr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", addrType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IPv4Unspecified",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IPv6Unspecified",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IPv6LinkLocalAllNodes",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IPv6Loopback",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))

	// Addr methods
	addrMethods := []struct{ name string; ret *types.Tuple }{
		{"IsValid", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"Is4", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"Is6", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"Is4In6", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsLoopback", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsMulticast", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsPrivate", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsGlobalUnicast", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsLinkLocalUnicast", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsLinkLocalMulticast", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsInterfaceLocalMulticast", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"IsUnspecified", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool]))},
		{"BitLen", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]))},
		{"Zone", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]))},
		{"String", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]))},
		{"StringExpanded", types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]))},
	}
	for _, m := range addrMethods {
		addrType.AddMethod(types.NewFunc(token.NoPos, pkg, m.name,
			types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
				nil, m.ret, false)))
	}
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "As4",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewArray(types.Typ[types.Byte], 4))),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "As16",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewArray(types.Typ[types.Byte], 16))),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "AsSlice",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte]))),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unmap",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "WithZone",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "zone", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalBinary",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Prev",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Prefix",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", prefixType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ip2", addrType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])),
			false)))
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Less",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ip2", addrType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// AddrPort constructors
	scope.Insert(types.NewFunc(token.NoPos, pkg, "AddrPortFrom",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ip", addrType),
				types.NewVar(token.NoPos, pkg, "port", types.Typ[types.Uint16])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrPortType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MustParseAddrPort",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrPortType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseAddrPort",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", addrPortType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// AddrPort methods
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "Addr",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrPortType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)), false)))
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "Port",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrPortType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Uint16])), false)))
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrPortType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", addrPortType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))

	// Prefix constructors
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PrefixFrom",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ip", addrType),
				types.NewVar(token.NoPos, pkg, "bits", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", prefixType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "MustParsePrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", prefixType)),
			false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParsePrefix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", prefixType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Prefix methods
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "Addr",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "Bits",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int])), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsValid",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "Contains",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ip", addrType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "Overlaps",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "o", prefixType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "Masked",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", prefixType)), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])), false)))
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsSingleIP",
		types.NewSignatureType(types.NewVar(token.NoPos, pkg, "", prefixType), nil, nil,
			nil, types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])), false)))

	byteSlice := types.NewSlice(types.Typ[types.Byte])
	addrRecv := types.NewVar(token.NoPos, nil, "ip", addrType)
	addrPtrRecv := types.NewVar(token.NoPos, nil, "ip", types.NewPointer(addrType))
	addrPortRecv := types.NewVar(token.NoPos, nil, "p", addrPortType)
	addrPortPtrRecv := types.NewVar(token.NoPos, nil, "p", types.NewPointer(addrPortType))
	prefixRecv := types.NewVar(token.NoPos, nil, "p", prefixType)
	prefixPtrRecv := types.NewVar(token.NoPos, nil, "p", types.NewPointer(prefixType))

	// func IPv6LinkLocalAllRouters() Addr
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IPv6LinkLocalAllRouters",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", addrType)), false)))

	// Addr.UnmarshalText(text []byte) error
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(addrPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "text", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Addr.UnmarshalBinary(b []byte) error
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalBinary",
		types.NewSignatureType(addrPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Addr.AppendTo(b []byte) []byte
	addrType.AddMethod(types.NewFunc(token.NoPos, pkg, "AppendTo",
		types.NewSignatureType(addrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)))

	// AddrPort.MarshalText() ([]byte, error)
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(addrPortRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// AddrPort.MarshalBinary() ([]byte, error)
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalBinary",
		types.NewSignatureType(addrPortRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// AddrPort.UnmarshalText(text []byte) error
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(addrPortPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "text", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// AddrPort.UnmarshalBinary(b []byte) error
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalBinary",
		types.NewSignatureType(addrPortPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// AddrPort.AppendTo(b []byte) []byte
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "AppendTo",
		types.NewSignatureType(addrPortRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)))
	// AddrPort.Compare(p2 AddrPort) int
	addrPortType.AddMethod(types.NewFunc(token.NoPos, pkg, "Compare",
		types.NewSignatureType(addrPortRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p2", addrPortType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])), false)))

	// Prefix.MarshalText() ([]byte, error)
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(prefixRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Prefix.MarshalBinary() ([]byte, error)
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalBinary",
		types.NewSignatureType(prefixRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Prefix.UnmarshalText(text []byte) error
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(prefixPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "text", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Prefix.UnmarshalBinary(b []byte) error
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalBinary",
		types.NewSignatureType(prefixPtrRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	// Prefix.AppendTo(b []byte) []byte
	prefixType.AddMethod(types.NewFunc(token.NoPos, pkg, "AppendTo",
		types.NewSignatureType(prefixRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", byteSlice)), false)))

	pkg.MarkComplete()
	return pkg
}

// buildNetPackage creates the type-checked net package stub.
func buildNetPackage() *types.Package {
	pkg := types.NewPackage("net", "net")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type Addr interface { Network() string; String() string }
	addrIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Network",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, pkg, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
	}, nil)
	addrIface.Complete()
	addrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Addr", nil),
		addrIface, nil)
	scope.Insert(addrType.Obj())

	// type Conn interface { Read, Write, Close, LocalAddr, RemoteAddr, SetDeadline, SetReadDeadline, SetWriteDeadline }
	connIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "LocalAddr",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", addrType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "RemoteAddr",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", addrType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "SetDeadline",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "SetReadDeadline",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "SetWriteDeadline",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	connIface.Complete()
	connType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Conn", nil),
		connIface, nil)
	scope.Insert(connType.Obj())

	// type Listener interface { Accept() (Conn, error); Close() error; Addr() Addr }
	listenerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Accept",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", connType),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Addr",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", addrType)),
				false)),
	}, nil)
	listenerIface.Complete()
	listenerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Listener", nil),
		listenerIface, nil)
	scope.Insert(listenerType.Obj())

	// func Dial(network, address string) (Conn, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", connType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Listen(network, address string) (Listener, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Listen",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", listenerType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func JoinHostPort(host, port string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "JoinHostPort",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "host", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "port", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func SplitHostPort(hostport string) (host, port string, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SplitHostPort",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "hostport", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "host", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "port", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// type IP []byte
	ipType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "IP", nil), byteSlice, nil)
	scope.Insert(ipType.Obj())
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "Equal",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "x", ipType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsLoopback",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsPrivate",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsUnspecified",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "To4",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ipType)), false)))
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "To16",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ipType)), false)))
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalText",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// type IPMask []byte
	ipMaskType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "IPMask", nil), byteSlice, nil)
	scope.Insert(ipMaskType.Obj())
	ipMaskType.AddMethod(types.NewFunc(token.NoPos, pkg, "Size",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", ipMaskType), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ones", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "bits", types.Typ[types.Int])), false)))
	ipMaskType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "m", ipMaskType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type IPNet struct { IP IP; Mask IPMask }
	ipNetStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "IP", ipType, false),
		types.NewField(token.NoPos, pkg, "Mask", ipMaskType, false),
	}, nil)
	ipNetType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "IPNet", nil), ipNetStruct, nil)
	scope.Insert(ipNetType.Obj())
	ipNetPtr := types.NewPointer(ipNetType)
	ipNetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Contains",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "n", ipNetPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "ip", ipType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	ipNetType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "n", ipNetPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type TCPAddr struct { IP IP; Port int; Zone string }
	tcpAddrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "IP", ipType, false),
		types.NewField(token.NoPos, pkg, "Port", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Zone", types.Typ[types.String], false),
	}, nil)
	tcpAddrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TCPAddr", nil), tcpAddrStruct, nil)
	scope.Insert(tcpAddrType.Obj())
	tcpAddrPtr := types.NewPointer(tcpAddrType)
	tcpAddrType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "a", tcpAddrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	tcpAddrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Network",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "a", tcpAddrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// type UDPAddr struct { IP IP; Port int; Zone string }
	udpAddrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "IP", ipType, false),
		types.NewField(token.NoPos, pkg, "Port", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Zone", types.Typ[types.String], false),
	}, nil)
	udpAddrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UDPAddr", nil), udpAddrStruct, nil)
	scope.Insert(udpAddrType.Obj())
	udpAddrPtr := types.NewPointer(udpAddrType)
	udpAddrType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "a", udpAddrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	udpAddrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Network",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "a", udpAddrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// context.Context stand-in for Dialer.DialContext and Resolver.LookupHost
	anyNet := types.NewInterfaceType(nil, nil)
	anyNet.Complete()
	ctxIfaceNet := types.NewInterfaceType([]*types.Func{
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
				types.NewTuple(types.NewVar(token.NoPos, nil, "key", anyNet)),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", anyNet)),
				false)),
	}, nil)
	ctxIfaceNet.Complete()

	// type Dialer struct
	dialerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Timeout", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "Deadline", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "LocalAddr", addrType, false),
		types.NewField(token.NoPos, pkg, "DualStack", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "FallbackDelay", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "KeepAlive", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "KeepAliveConfig", types.NewStruct(nil, nil), false),
	}, nil)
	dialerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Dialer", nil), dialerStruct, nil)
	scope.Insert(dialerType.Obj())
	dialerPtr := types.NewPointer(dialerType)
	dialerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Dial",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "d", dialerPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", connType),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	dialerType.AddMethod(types.NewFunc(token.NoPos, pkg, "DialContext",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "d", dialerPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxIfaceNet),
				types.NewVar(token.NoPos, nil, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", connType),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// type Resolver struct
	resolverType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Resolver", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "PreferGo", types.Typ[types.Bool], false),
			types.NewField(token.NoPos, pkg, "StrictErrors", types.Typ[types.Bool], false),
		}, nil), nil)
	scope.Insert(resolverType.Obj())
	resolverPtr := types.NewPointer(resolverType)
	resolverType.AddMethod(types.NewFunc(token.NoPos, pkg, "LookupHost",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", resolverPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxIfaceNet),
				types.NewVar(token.NoPos, nil, "host", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func ParseIP(s string) IP
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseIP",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ipType)), false)))

	// func ParseCIDR(s string) (IP, *IPNet, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseCIDR",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ipType),
				types.NewVar(token.NoPos, pkg, "", ipNetPtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func IPv4(a, b, c, d byte) IP
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IPv4",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "a", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "c", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "d", types.Typ[types.Byte])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ipType)), false)))

	// func CIDRMask(ones, bits int) IPMask
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CIDRMask",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ones", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "bits", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ipMaskType)), false)))

	// func IPv4Mask(a, b, c, d byte) IPMask
	scope.Insert(types.NewFunc(token.NoPos, pkg, "IPv4Mask",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "a", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "b", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "c", types.Typ[types.Byte]),
				types.NewVar(token.NoPos, pkg, "d", types.Typ[types.Byte])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", ipMaskType)), false)))

	// func ResolveTCPAddr(network, address string) (*TCPAddr, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ResolveTCPAddr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tcpAddrPtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func ResolveUDPAddr(network, address string) (*UDPAddr, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ResolveUDPAddr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", udpAddrPtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func DialTimeout(network, address string, timeout time.Duration) (Conn, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DialTimeout",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "timeout", types.Typ[types.Int64])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", connType),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func LookupHost(host string) ([]string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupHost",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "host", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func LookupIP(host string) ([]IP, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupIP",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "host", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(ipType)),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func LookupPort(network, service string) (int, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupPort",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "service", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// type Error interface { error; Timeout() bool; Temporary() bool }
	netErrIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Error",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
				false)),
		types.NewFunc(token.NoPos, pkg, "Timeout",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
				false)),
		types.NewFunc(token.NoPos, pkg, "Temporary",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
				false)),
	}, nil)
	netErrIface.Complete()
	netErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Error", nil), netErrIface, nil)
	scope.Insert(netErrType.Obj())

	// var IPv4zero, IPv4bcast, IPv6zero, IPv6loopback IP
	scope.Insert(types.NewVar(token.NoPos, pkg, "IPv4zero", ipType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "IPv4bcast", ipType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "IPv6zero", ipType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "IPv6loopback", ipType))

	// var ErrClosed error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrClosed", errType))

	// const IPv4len = 4, IPv6len = 16
	scope.Insert(types.NewConst(token.NoPos, pkg, "IPv4len", types.Typ[types.Int], constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "IPv6len", types.Typ[types.Int], constant.MakeInt64(16)))

	// type OpError struct
	opErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Op", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Net", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Source", addrType, false),
		types.NewField(token.NoPos, pkg, "Addr", addrType, false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	opErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "OpError", nil), opErrStruct, nil)
	scope.Insert(opErrType.Obj())
	opErrPtr := types.NewPointer(opErrType)
	opErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", opErrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	opErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", opErrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	opErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", opErrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	opErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Temporary",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", opErrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// type DNSError struct
	dnsErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Err", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Server", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "IsTimeout", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "IsTemporary", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "IsNotFound", types.Typ[types.Bool], false),
	}, nil)
	dnsErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "DNSError", nil), dnsErrStruct, nil)
	scope.Insert(dnsErrType.Obj())
	dnsErrPtr := types.NewPointer(dnsErrType)
	dnsErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", dnsErrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	dnsErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", dnsErrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	dnsErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Temporary",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", dnsErrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// type PacketConn interface { ReadFrom, WriteTo, Close, LocalAddr, SetDeadline, SetReadDeadline, SetWriteDeadline }
	packetConnIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "ReadFrom",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "addr", addrType),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "WriteTo",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "p", byteSlice),
					types.NewVar(token.NoPos, nil, "addr", addrType)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "LocalAddr",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", addrType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "SetDeadline",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "SetReadDeadline",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "SetWriteDeadline",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	packetConnIface.Complete()
	packetConnType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "PacketConn", nil), packetConnIface, nil)
	scope.Insert(packetConnType.Obj())

	// func ListenPacket(network, address string) (PacketConn, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ListenPacket",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", packetConnType),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// IP.Mask(mask IPMask) IP
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "Mask",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "mask", ipMaskType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ipType)), false)))

	// IP.DefaultMask() IPMask
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "DefaultMask",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", ipMaskType)), false)))

	// IP.IsGlobalUnicast() bool
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsGlobalUnicast",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// IP.IsLinkLocalUnicast() bool
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsLinkLocalUnicast",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// IP.IsLinkLocalMulticast() bool
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsLinkLocalMulticast",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// IP.IsMulticast() bool
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsMulticast",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// IP.IsInterfaceLocalMulticast() bool
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsInterfaceLocalMulticast",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", ipType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// type UnixAddr struct { Name, Net string }
	unixAddrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Net", types.Typ[types.String], false),
	}, nil)
	unixAddrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UnixAddr", nil), unixAddrStruct, nil)
	scope.Insert(unixAddrType.Obj())
	unixAddrPtr := types.NewPointer(unixAddrType)
	unixAddrType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "a", unixAddrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	unixAddrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Network",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "a", unixAddrPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// func ResolveUnixAddr(network, address string) (*UnixAddr, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ResolveUnixAddr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", unixAddrPtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// type TCPConn struct {} — concrete TCP connection
	tcpConnType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TCPConn", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(tcpConnType.Obj())
	tcpConnPtr := types.NewPointer(tcpConnType)
	// TCPConn methods: Read, Write, Close, LocalAddr, RemoteAddr, SetDeadline, SetReadDeadline, SetWriteDeadline, SetKeepAlive, SetKeepAlivePeriod, SetNoDelay, CloseRead, CloseWrite, ReadFrom, SetLinger
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "LocalAddr",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", addrType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "RemoteAddr",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", addrType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetDeadline",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetReadDeadline",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetWriteDeadline",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetKeepAlive",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "keepalive", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetKeepAlivePeriod",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "d", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetNoDelay",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "noDelay", types.Typ[types.Bool])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "CloseRead",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "CloseWrite",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	tcpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetLinger",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", tcpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "sec", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// type UDPConn struct {}
	udpConnType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UDPConn", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(udpConnType.Obj())
	udpConnPtr := types.NewPointer(udpConnType)
	udpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", udpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)), false)))
	udpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", udpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)), false)))
	udpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", udpConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	udpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "LocalAddr",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", udpConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", addrType)), false)))
	udpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "RemoteAddr",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", udpConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", addrType)), false)))
	udpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetDeadline",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", udpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	udpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetReadDeadline",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", udpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	udpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetWriteDeadline",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", udpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	udpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadFromUDP",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", udpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "addr", udpAddrPtr),
				types.NewVar(token.NoPos, nil, "err", errType)), false)))
	udpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteToUDP",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", udpConnPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "b", byteSlice),
				types.NewVar(token.NoPos, nil, "addr", udpAddrPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)), false)))
	udpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetReadBuffer",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", udpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "bytes", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	udpConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetWriteBuffer",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", udpConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "bytes", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// type UnixConn struct {}
	unixConnType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UnixConn", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(unixConnType.Obj())
	unixConnPtr := types.NewPointer(unixConnType)
	unixConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", unixConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)), false)))
	unixConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "Write",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", unixConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "b", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "err", errType)), false)))
	unixConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", unixConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	unixConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "LocalAddr",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", unixConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", addrType)), false)))
	unixConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "RemoteAddr",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", unixConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", addrType)), false)))
	unixConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetDeadline",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", unixConnPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	unixConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "CloseRead",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", unixConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	unixConnType.AddMethod(types.NewFunc(token.NoPos, pkg, "CloseWrite",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "c", unixConnPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// type TCPListener struct {}
	tcpListenerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "TCPListener", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(tcpListenerType.Obj())
	tcpListenerPtr := types.NewPointer(tcpListenerType)
	tcpListenerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Accept",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", tcpListenerPtr), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", connType),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	tcpListenerType.AddMethod(types.NewFunc(token.NoPos, pkg, "AcceptTCP",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", tcpListenerPtr), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", tcpConnPtr),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	tcpListenerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", tcpListenerPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	tcpListenerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Addr",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", tcpListenerPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", addrType)), false)))
	tcpListenerType.AddMethod(types.NewFunc(token.NoPos, pkg, "SetDeadline",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", tcpListenerPtr), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "t", types.Typ[types.Int64])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func DialTCP(network string, laddr, raddr *TCPAddr) (*TCPConn, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DialTCP",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "laddr", tcpAddrPtr),
				types.NewVar(token.NoPos, pkg, "raddr", tcpAddrPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tcpConnPtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func ListenTCP(network string, laddr *TCPAddr) (*TCPListener, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ListenTCP",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "laddr", tcpAddrPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", tcpListenerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func DialUDP(network string, laddr, raddr *UDPAddr) (*UDPConn, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DialUDP",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "laddr", udpAddrPtr),
				types.NewVar(token.NoPos, pkg, "raddr", udpAddrPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", udpConnPtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func ListenUDP(network string, laddr *UDPAddr) (*UDPConn, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ListenUDP",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "laddr", udpAddrPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", udpConnPtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func DialUnix(network string, laddr, raddr *UnixAddr) (*UnixConn, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DialUnix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "laddr", unixAddrPtr),
				types.NewVar(token.NoPos, pkg, "raddr", unixAddrPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", unixConnPtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func ListenUnix(network string, laddr *UnixAddr) (*net.UnixListener — simplified as returning Listener)
	// Actually return a UnixListener
	unixListenerType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "UnixListener", nil),
		types.NewStruct(nil, nil), nil)
	scope.Insert(unixListenerType.Obj())
	unixListenerPtr := types.NewPointer(unixListenerType)
	unixListenerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Accept",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", unixListenerPtr), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", connType),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	unixListenerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", unixListenerPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))
	unixListenerType.AddMethod(types.NewFunc(token.NoPos, pkg, "Addr",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "l", unixListenerPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", addrType)), false)))
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ListenUnix",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "laddr", unixAddrPtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", unixListenerPtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// type AddrError struct { Err, Addr string }
	addrErrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "AddrError", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Err", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Addr", types.Typ[types.String], false),
		}, nil), nil)
	scope.Insert(addrErrType.Obj())
	addrErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(addrErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	addrErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(addrErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	addrErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Temporary",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(addrErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))

	// DNS record types
	// type MX struct { Host string; Pref uint16 }
	mxType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "MX", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Host", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Pref", types.Typ[types.Uint16], false),
		}, nil), nil)
	scope.Insert(mxType.Obj())

	// type NS struct { Host string }
	nsType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "NS", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Host", types.Typ[types.String], false),
		}, nil), nil)
	scope.Insert(nsType.Obj())

	// type SRV struct { Target string; Port uint16; Priority uint16; Weight uint16 }
	srvType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "SRV", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Target", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "Port", types.Typ[types.Uint16], false),
			types.NewField(token.NoPos, pkg, "Priority", types.Typ[types.Uint16], false),
			types.NewField(token.NoPos, pkg, "Weight", types.Typ[types.Uint16], false),
		}, nil), nil)
	scope.Insert(srvType.Obj())

	// func LookupAddr(addr string) ([]string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupAddr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func LookupCNAME(host string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupCNAME",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "host", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func LookupMX(name string) ([]*MX, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupMX",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.NewPointer(mxType))),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func LookupNS(name string) ([]*NS, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupNS",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.NewPointer(nsType))),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func LookupSRV(service, proto, name string) (string, []*SRV, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupSRV",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "service", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "proto", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.NewPointer(srvType))),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func LookupTXT(name string) ([]string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "LookupTXT",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// Resolver additional methods
	// LookupAddr
	resolverType.AddMethod(types.NewFunc(token.NoPos, pkg, "LookupAddr",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", resolverPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxIfaceNet),
				types.NewVar(token.NoPos, nil, "addr", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	// LookupIPAddr
	// type IPAddr struct { IP IP; Zone string }
	ipAddrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "IPAddr", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "IP", ipType, false),
			types.NewField(token.NoPos, pkg, "Zone", types.Typ[types.String], false),
		}, nil), nil)
	scope.Insert(ipAddrType.Obj())
	resolverType.AddMethod(types.NewFunc(token.NoPos, pkg, "LookupIPAddr",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", resolverPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxIfaceNet),
				types.NewVar(token.NoPos, nil, "host", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(ipAddrType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// Resolver.LookupCNAME(ctx, host) (string, error)
	resolverType.AddMethod(types.NewFunc(token.NoPos, pkg, "LookupCNAME",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", resolverPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxIfaceNet),
				types.NewVar(token.NoPos, nil, "host", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// Resolver.LookupTXT(ctx, name) ([]string, error)
	resolverType.AddMethod(types.NewFunc(token.NoPos, pkg, "LookupTXT",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "r", resolverPtr), nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxIfaceNet),
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// type Interface struct { Index int; MTU int; Name string; ... }
	ifaceType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Interface", nil),
		types.NewStruct([]*types.Var{
			types.NewField(token.NoPos, pkg, "Index", types.Typ[types.Int], false),
			types.NewField(token.NoPos, pkg, "MTU", types.Typ[types.Int], false),
			types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
			types.NewField(token.NoPos, pkg, "HardwareAddr", byteSlice, false),
			types.NewField(token.NoPos, pkg, "Flags", types.Typ[types.Uint], false),
		}, nil), nil)
	scope.Insert(ifaceType.Obj())
	ifacePtr := types.NewPointer(ifaceType)
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "Addrs",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ifi", ifacePtr), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(addrType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	ifaceType.AddMethod(types.NewFunc(token.NoPos, pkg, "MulticastAddrs",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ifi", ifacePtr), nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.NewSlice(addrType)),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	// func Interfaces() ([]Interface, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Interfaces",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(ifaceType)),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func InterfaceByName(name string) (*Interface, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "InterfaceByName",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ifacePtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// func InterfaceByIndex(index int) (*Interface, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "InterfaceByIndex",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "index", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ifacePtr),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// type HardwareAddr []byte
	hwAddrType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "HardwareAddr", nil), byteSlice, nil)
	scope.Insert(hwAddrType.Obj())
	hwAddrType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "a", hwAddrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// func ParseMAC(s string) (HardwareAddr, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseMAC",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", hwAddrType),
				types.NewVar(token.NoPos, pkg, "", errType)), false)))

	// Flags constants
	flagsType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "Flags", nil), types.Typ[types.Uint], nil)
	scope.Insert(flagsType.Obj())
	scope.Insert(types.NewConst(token.NoPos, pkg, "FlagUp", flagsType, constant.MakeInt64(1)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FlagBroadcast", flagsType, constant.MakeInt64(2)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FlagLoopback", flagsType, constant.MakeInt64(4)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FlagPointToPoint", flagsType, constant.MakeInt64(8)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FlagMulticast", flagsType, constant.MakeInt64(16)))
	scope.Insert(types.NewConst(token.NoPos, pkg, "FlagRunning", flagsType, constant.MakeInt64(32)))
	flagsType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "f", flagsType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// Dialer additional fields: KeepAlive, LocalAddr, DualStack, FallbackDelay, Resolver, Control
	// Note: these are added to the existing Dialer struct above — we can't retroactively add fields,
	// but the type checker only needs what user code references. The Timeout field is already there.

	// IP.UnmarshalText(text []byte) error
	ipType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalText",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "ip", types.NewPointer(ipType)), nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "text", byteSlice)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)), false)))

	// IPNet.Network() string
	ipNetType.AddMethod(types.NewFunc(token.NoPos, pkg, "Network",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "n", ipNetPtr), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))

	// Additional IPv4/IPv6 variables
	scope.Insert(types.NewVar(token.NoPos, pkg, "IPv4allsys", ipType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "IPv4allrouter", ipType))
	scope.Insert(types.NewVar(token.NoPos, pkg, "IPv6unspecified", ipType))

	// func ResolveIPAddr(network, address string) (*IPAddr, error)
	ipAddrPtr := types.NewPointer(ipAddrType)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ResolveIPAddr",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", ipAddrPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func Pipe() (Conn, Conn)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Pipe",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", connType),
				types.NewVar(token.NoPos, pkg, "", connType)),
			false)))

	// func InterfaceAddrs() ([]Addr, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "InterfaceAddrs",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(addrType)),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// var ErrWriteToConnected error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrWriteToConnected", errType))

	// type ParseError struct { Type string; Text string }
	parseErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Type", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Text", types.Typ[types.String], false),
	}, nil)
	parseErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ParseError", nil),
		parseErrStruct, nil)
	parseErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(parseErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	parseErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(parseErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	parseErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Temporary",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", types.NewPointer(parseErrType)), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	scope.Insert(parseErrType.Obj())

	// type InvalidAddrError string
	invalidAddrErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "InvalidAddrError", nil),
		types.Typ[types.String], nil)
	invalidAddrErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", invalidAddrErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	invalidAddrErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", invalidAddrErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	invalidAddrErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Temporary",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", invalidAddrErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	scope.Insert(invalidAddrErrType.Obj())

	// type UnknownNetworkError string
	unknownNetErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "UnknownNetworkError", nil),
		types.Typ[types.String], nil)
	unknownNetErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownNetErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)))
	unknownNetErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownNetErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	unknownNetErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Temporary",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", unknownNetErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])), false)))
	scope.Insert(unknownNetErrType.Obj())

	// type Buffers [][]byte
	buffersType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Buffers", nil),
		types.NewSlice(byteSlice), nil)
	buffersRecv := types.NewVar(token.NoPos, nil, "b", types.NewPointer(buffersType))
	// io.Writer stand-in for Buffers.WriteTo
	ioWriterNet := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	ioWriterNet.Complete()
	buffersType.AddMethod(types.NewFunc(token.NoPos, pkg, "WriteTo",
		types.NewSignatureType(buffersRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", ioWriterNet)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int64]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	buffersType.AddMethod(types.NewFunc(token.NoPos, pkg, "Read",
		types.NewSignatureType(buffersRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "p", byteSlice)),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	scope.Insert(buffersType.Obj())

	// os.File stand-in for FileConn/FileListener/FilePacketConn
	osFilePtr := types.NewPointer(types.NewStruct(nil, nil))

	// func FileConn(f *os.File) (c Conn, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FileConn",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f", osFilePtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", connType),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func FileListener(f *os.File) (ln Listener, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FileListener",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f", osFilePtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "ln", listenerType),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// func FilePacketConn(f *os.File) (c PacketConn, err error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "FilePacketConn",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "f", osFilePtr)),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "c", packetConnType),
				types.NewVar(token.NoPos, pkg, "err", errType)),
			false)))

	// type ListenConfig struct { Control func; KeepAlive time.Duration; KeepAliveConfig KeepAliveConfig }
	lcStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Control", types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "address", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "c", types.NewInterfaceType(nil, nil))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false), false),
		types.NewField(token.NoPos, pkg, "KeepAlive", types.Typ[types.Int64], false),
		types.NewField(token.NoPos, pkg, "KeepAliveConfig", types.NewStruct(nil, nil), false),
	}, nil)
	lcType := types.NewNamed(types.NewTypeName(token.NoPos, pkg, "ListenConfig", nil), lcStruct, nil)
	scope.Insert(lcType.Obj())
	lcPtr := types.NewPointer(lcType)
	lcRecv := types.NewVar(token.NoPos, nil, "lc", lcPtr)
	lcType.AddMethod(types.NewFunc(token.NoPos, pkg, "Listen",
		types.NewSignatureType(lcRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxIfaceNet),
				types.NewVar(token.NoPos, nil, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", listenerType),
				types.NewVar(token.NoPos, nil, "", errType)), false)))
	lcType.AddMethod(types.NewFunc(token.NoPos, pkg, "ListenPacket",
		types.NewSignatureType(lcRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "ctx", ctxIfaceNet),
				types.NewVar(token.NoPos, nil, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", packetConnType),
				types.NewVar(token.NoPos, nil, "", errType)), false)))

	pkg.MarkComplete()
	return pkg
}

func buildNetRPCJSONRPCPackage() *types.Package {
	pkg := types.NewPackage("net/rpc/jsonrpc", "jsonrpc")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()

	// func Dial(network, address string) (*rpc.Client, error) — simplified
	clientStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	clientType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Client", nil),
		clientStruct, nil)
	clientPtr := types.NewPointer(clientType)

	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", clientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	pkg.MarkComplete()
	return pkg
}

func buildNetRPCPackage() *types.Package {
	pkg := types.NewPackage("net/rpc", "rpc")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()

	// type Client struct { ... }
	clientStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	clientType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Client", nil),
		clientStruct, nil)
	scope.Insert(clientType.Obj())
	clientPtr := types.NewPointer(clientType)

	// type Server struct { ... }
	serverStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	serverType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Server", nil),
		serverStruct, nil)
	scope.Insert(serverType.Obj())

	// var DefaultServer *Server
	scope.Insert(types.NewVar(token.NoPos, pkg, "DefaultServer", types.NewPointer(serverType)))
	// var ErrShutdown error
	scope.Insert(types.NewVar(token.NoPos, pkg, "ErrShutdown", errType))

	anyType := types.NewInterfaceType(nil, nil)

	// func Dial(network, address string) (*Client, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", clientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DialHTTP(network, address string) (*Client, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DialHTTP",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", clientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func NewServer() *Server
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewServer",
		types.NewSignatureType(nil, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.NewPointer(serverType))),
			false)))

	// func Register(rcvr any) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Register",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "rcvr", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Client.Call(serviceMethod string, args any, reply any) error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Call",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "client", clientPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "serviceMethod", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType),
				types.NewVar(token.NoPos, nil, "reply", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// Client.Close() error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "client", clientPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// type Call struct
	callStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "ServiceMethod", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Args", anyType, false),
		types.NewField(token.NoPos, pkg, "Reply", anyType, false),
		types.NewField(token.NoPos, pkg, "Error", errType, false),
	}, nil)
	callType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Call", nil),
		callStruct, nil)
	scope.Insert(callType.Obj())
	callPtr := types.NewPointer(callType)

	// Client.Go(serviceMethod string, args any, reply any, done chan *Call) *Call
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Go",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "client", clientPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "serviceMethod", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", anyType),
				types.NewVar(token.NoPos, nil, "reply", anyType),
				types.NewVar(token.NoPos, nil, "done", types.NewChan(types.SendRecv, callPtr))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", callPtr)),
			false)))

	// func RegisterName(name string, rcvr any) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "RegisterName",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "rcvr", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func DialHTTPPath(network, address, path string) (*Client, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "DialHTTPPath",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "network", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "address", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "path", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", clientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	serverPtr := types.NewPointer(serverType)

	// Server methods
	// func (s *Server) Register(rcvr any) error
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Register",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "server", serverPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "rcvr", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (s *Server) RegisterName(name string, rcvr any) error
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "RegisterName",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "server", serverPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "name", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "rcvr", anyType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (s *Server) HandleHTTP(rpcPath, debugPath string)
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "HandleHTTP",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "server", serverPtr),
			nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "rpcPath", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "debugPath", types.Typ[types.String])),
			nil, false)))

	// func HandleHTTP() — package-level convenience
	scope.Insert(types.NewFunc(token.NoPos, pkg, "HandleHTTP",
		types.NewSignatureType(nil, nil, nil, nil, nil, false)))

	// net.Addr stand-in
	netAddrIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Network",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
		types.NewFunc(token.NoPos, nil, "String",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])), false)),
	}, nil)
	netAddrIface.Complete()

	// net.Listener interface
	rpcByteSlice := types.NewSlice(types.Typ[types.Byte])
	netConnIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", rpcByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", rpcByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	netConnIface.Complete()

	listenerIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Accept",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "", netConnIface),
					types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Addr",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", netAddrIface)),
				false)),
	}, nil)
	listenerIface.Complete()

	// io.ReadWriteCloser interface
	rwcIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", rpcByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", rpcByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	rwcIface.Complete()

	// func Accept(lis net.Listener)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Accept",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "lis", listenerIface)),
			nil, false)))

	// func ServeConn(conn io.ReadWriteCloser)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ServeConn",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "conn", rwcIface)),
			nil, false)))

	// func (s *Server) Accept(lis net.Listener)
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "Accept",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "server", serverPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "lis", listenerIface)),
			nil, false)))

	// func (s *Server) ServeConn(conn io.ReadWriteCloser)
	serverType.AddMethod(types.NewFunc(token.NoPos, pkg, "ServeConn",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "server", serverPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "conn", rwcIface)),
			nil, false)))

	// type ServerError string
	serverErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ServerError", nil),
		types.Typ[types.String], nil)
	serverErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", serverErrType),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(serverErrType.Obj())

	// const DefaultRPCPath, DefaultDebugPath
	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultRPCPath", types.Typ[types.String],
		constant.MakeString("/_goRPC_")))
	scope.Insert(types.NewConst(token.NoPos, pkg, "DefaultDebugPath", types.Typ[types.String],
		constant.MakeString("/debug/rpc")))

	pkg.MarkComplete()
	return pkg
}

func buildNetSMTPPackage() *types.Package {
	pkg := types.NewPackage("net/smtp", "smtp")
	scope := pkg.Scope()

	errType := types.Universe.Lookup("error").Type()

	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type ServerInfo struct (forward declare for Auth interface)
	serverInfoStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Name", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "TLS", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "Auth", types.NewSlice(types.Typ[types.String]), false),
	}, nil)
	serverInfoType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ServerInfo", nil),
		serverInfoStruct, nil)
	scope.Insert(serverInfoType.Obj())

	// type Auth interface { Start(server *ServerInfo) (proto string, toServer []byte, err error); Next(fromServer []byte, more bool) (toServer []byte, err error) }
	authIface := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, pkg, "Start",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "server", types.NewPointer(serverInfoType))),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "proto", types.Typ[types.String]),
					types.NewVar(token.NoPos, nil, "toServer", byteSlice),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, pkg, "Next",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "fromServer", byteSlice),
					types.NewVar(token.NoPos, nil, "more", types.Typ[types.Bool])),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "toServer", byteSlice),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
	}, nil)
	authIface.Complete()
	authType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Auth", nil),
		authIface, nil)
	scope.Insert(authType.Obj())

	// type Client struct { ... }
	clientStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	clientType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Client", nil),
		clientStruct, nil)
	scope.Insert(clientType.Obj())
	clientPtr := types.NewPointer(clientType)

	// func SendMail(addr string, a Auth, from string, to []string, msg []byte) error
	scope.Insert(types.NewFunc(token.NoPos, pkg, "SendMail",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "addr", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "a", authType),
				types.NewVar(token.NoPos, pkg, "from", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "to", types.NewSlice(types.Typ[types.String])),
				types.NewVar(token.NoPos, pkg, "msg", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func PlainAuth(identity, username, password, host string) Auth
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PlainAuth",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "identity", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "username", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "password", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "host", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", authType)),
			false)))

	// func CRAMMD5Auth(username, secret string) Auth
	scope.Insert(types.NewFunc(token.NoPos, pkg, "CRAMMD5Auth",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "username", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "secret", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", authType)),
			false)))

	// func Dial(addr string) (*Client, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Dial",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "addr", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", clientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Client methods
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Mail",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "from", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Rcpt",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "to", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Quit",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (c *Client) Hello(localName string) error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Hello",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "localName", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (c *Client) Auth(a Auth) error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Auth",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "a", authType)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// *tls.Config (opaque)
	tlsConfigStruct := types.NewStruct(nil, nil)
	tlsConfigPtr := types.NewPointer(tlsConfigStruct)

	// io.WriteCloser interface
	ioWriteCloser := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "p", types.NewSlice(types.Typ[types.Byte]))),
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

	// net.Conn interface (Read/Write/Close)
	smtpByteSlice := types.NewSlice(types.Typ[types.Byte])
	netConn := types.NewInterfaceType([]*types.Func{
		types.NewFunc(token.NoPos, nil, "Read",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", smtpByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Write",
			types.NewSignatureType(nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "b", smtpByteSlice)),
				types.NewTuple(
					types.NewVar(token.NoPos, nil, "n", types.Typ[types.Int]),
					types.NewVar(token.NoPos, nil, "err", errType)),
				false)),
		types.NewFunc(token.NoPos, nil, "Close",
			types.NewSignatureType(nil, nil, nil, nil,
				types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
				false)),
	}, nil)
	netConn.Complete()

	// func (c *Client) StartTLS(config *tls.Config) error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "StartTLS",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "config", tlsConfigPtr)),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (c *Client) Data() (io.WriteCloser, error)
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Data",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", ioWriteCloser),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (c *Client) Extension(ext string) (bool, string)
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Extension",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "ext", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool]),
				types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// func (c *Client) Reset() error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Reset",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (c *Client) Noop() error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Noop",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func (c *Client) Verify(addr string) error
	clientType.AddMethod(types.NewFunc(token.NoPos, pkg, "Verify",
		types.NewSignatureType(
			types.NewVar(token.NoPos, nil, "c", clientPtr),
			nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "addr", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))

	// func NewClient(conn net.Conn, host string) (*Client, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewClient",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "conn", netConn),
				types.NewVar(token.NoPos, pkg, "host", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", clientPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// ServerInfo type is defined earlier (before Auth interface)

	pkg.MarkComplete()
	return pkg
}

// buildNetTextprotoPackage creates the type-checked net/textproto package stub.
func buildNetTextprotoPackage() *types.Package {
	pkg := types.NewPackage("net/textproto", "textproto")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()
	stringSlice := types.NewSlice(types.Typ[types.String])
	byteSlice := types.NewSlice(types.Typ[types.Byte])

	// type MIMEHeader map[string][]string
	mimeHeaderType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "MIMEHeader", nil),
		types.NewMap(types.Typ[types.String], stringSlice), nil)
	scope.Insert(mimeHeaderType.Obj())

	mimeRecv := types.NewVar(token.NoPos, nil, "h", mimeHeaderType)
	mimeHeaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(mimeRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			nil, false)))
	mimeHeaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(mimeRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "value", types.Typ[types.String])),
			nil, false)))
	mimeHeaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(mimeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	mimeHeaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Values",
		types.NewSignatureType(mimeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", stringSlice)),
			false)))
	mimeHeaderType.AddMethod(types.NewFunc(token.NoPos, pkg, "Del",
		types.NewSignatureType(mimeRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "key", types.Typ[types.String])),
			nil, false)))

	// type Error struct { Code int; Msg string }
	tpErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Code", types.Typ[types.Int], false),
		types.NewField(token.NoPos, pkg, "Msg", types.Typ[types.String], false),
	}, nil)
	tpErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Error", nil),
		tpErrStruct, nil)
	tpErrPtr := types.NewPointer(tpErrType)
	tpErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", tpErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(tpErrType.Obj())

	// type ProtocolError string
	protoErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "ProtocolError", nil),
		types.Typ[types.String], nil)
	protoErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "p", protoErrType), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	scope.Insert(protoErrType.Obj())

	// type Conn struct
	connStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "conn", types.Typ[types.Int], false),
	}, nil)
	connType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Conn", nil),
		connStruct, nil)
	scope.Insert(connType.Obj())
	connPtr := types.NewPointer(connType)
	connRecv := types.NewVar(token.NoPos, nil, "c", connPtr)
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "Close",
		types.NewSignatureType(connRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	connType.AddMethod(types.NewFunc(token.NoPos, pkg, "Cmd",
		types.NewSignatureType(connRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", types.NewSlice(types.NewInterfaceType(nil, nil)))),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "id", types.Typ[types.Uint]),
				types.NewVar(token.NoPos, nil, "", errType)),
			true)))

	// type Reader struct
	readerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "R", types.Typ[types.Int], false),
	}, nil)
	readerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Reader", nil),
		readerStruct, nil)
	scope.Insert(readerType.Obj())
	readerPtr := types.NewPointer(readerType)
	readerRecv := types.NewVar(token.NoPos, nil, "r", readerPtr)

	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewReader",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "r", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", readerPtr)),
			false)))

	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadLine",
		types.NewSignatureType(readerRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadLineBytes",
		types.NewSignatureType(readerRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadContinuedLine",
		types.NewSignatureType(readerRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadContinuedLineBytes",
		types.NewSignatureType(readerRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadCodeLine",
		types.NewSignatureType(readerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "expectCode", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "code", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "message", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadResponse",
		types.NewSignatureType(readerRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "expectCode", types.Typ[types.Int])),
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "code", types.Typ[types.Int]),
				types.NewVar(token.NoPos, nil, "message", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "err", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadDotLines",
		types.NewSignatureType(readerRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", stringSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadDotBytes",
		types.NewSignatureType(readerRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", byteSlice),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "ReadMIMEHeader",
		types.NewSignatureType(readerRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "", mimeHeaderType),
				types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	readerType.AddMethod(types.NewFunc(token.NoPos, pkg, "DotReader",
		types.NewSignatureType(readerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// type Writer struct
	writerStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "W", types.Typ[types.Int], false),
	}, nil)
	writerType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Writer", nil),
		writerStruct, nil)
	scope.Insert(writerType.Obj())
	writerPtr := types.NewPointer(writerType)
	writerRecv := types.NewVar(token.NoPos, nil, "w", writerPtr)

	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewWriter",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "w", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", writerPtr)),
			false)))

	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "PrintfLine",
		types.NewSignatureType(writerRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, nil, "format", types.Typ[types.String]),
				types.NewVar(token.NoPos, nil, "args", types.NewSlice(types.NewInterfaceType(nil, nil)))),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			true)))
	writerType.AddMethod(types.NewFunc(token.NoPos, pkg, "DotWriter",
		types.NewSignatureType(writerRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Int])),
			false)))

	// func NewConn(conn io.ReadWriteCloser) *Conn
	scope.Insert(types.NewFunc(token.NoPos, pkg, "NewConn",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "conn", types.Typ[types.Int])),
			types.NewTuple(types.NewVar(token.NoPos, nil, "", connPtr)),
			false)))

	// type Pipeline struct
	pipelineStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "data", types.Typ[types.Int], false),
	}, nil)
	pipelineType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Pipeline", nil),
		pipelineStruct, nil)
	scope.Insert(pipelineType.Obj())
	pipelinePtr := types.NewPointer(pipelineType)
	pipelineRecv := types.NewVar(token.NoPos, nil, "p", pipelinePtr)
	pipelineType.AddMethod(types.NewFunc(token.NoPos, pkg, "Next",
		types.NewSignatureType(pipelineRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Uint])),
			false)))
	pipelineType.AddMethod(types.NewFunc(token.NoPos, pkg, "StartRequest",
		types.NewSignatureType(pipelineRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "id", types.Typ[types.Uint])),
			nil, false)))
	pipelineType.AddMethod(types.NewFunc(token.NoPos, pkg, "EndRequest",
		types.NewSignatureType(pipelineRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "id", types.Typ[types.Uint])),
			nil, false)))
	pipelineType.AddMethod(types.NewFunc(token.NoPos, pkg, "StartResponse",
		types.NewSignatureType(pipelineRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "id", types.Typ[types.Uint])),
			nil, false)))
	pipelineType.AddMethod(types.NewFunc(token.NoPos, pkg, "EndResponse",
		types.NewSignatureType(pipelineRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "id", types.Typ[types.Uint])),
			nil, false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "CanonicalMIMEHeaderKey",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	scope.Insert(types.NewFunc(token.NoPos, pkg, "TrimString",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	pkg.MarkComplete()
	return pkg
}

// buildNetURLPackage creates the type-checked net/url package stub.
func buildNetURLPackage() *types.Package {
	pkg := types.NewPackage("net/url", "url")
	scope := pkg.Scope()
	errType := types.Universe.Lookup("error").Type()

	// type Userinfo (forward declare for URL struct)
	userinfoStruct := types.NewStruct(nil, nil)
	userinfoType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Userinfo", nil),
		userinfoStruct, nil)
	scope.Insert(userinfoType.Obj())
	userinfoPtr := types.NewPointer(userinfoType)

	// type URL struct
	urlStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Scheme", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Opaque", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "User", userinfoPtr, false),
		types.NewField(token.NoPos, pkg, "Host", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Path", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "RawPath", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "OmitHost", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "ForceQuery", types.Typ[types.Bool], false),
		types.NewField(token.NoPos, pkg, "RawQuery", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Fragment", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "RawFragment", types.Typ[types.String], false),
	}, nil)
	urlType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "URL", nil),
		urlStruct, nil)
	scope.Insert(urlType.Obj())
	urlPtr := types.NewPointer(urlType)

	// func Parse(rawURL string) (*URL, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "rawURL", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", urlPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func QueryEscape(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "QueryEscape",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func QueryUnescape(s string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "QueryUnescape",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func PathEscape(s string) string
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PathEscape",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func PathUnescape(s string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "PathUnescape",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "s", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// type Values map[string][]string
	valuesType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Values", nil),
		types.NewMap(types.Typ[types.String], types.NewSlice(types.Typ[types.String])), nil)
	scope.Insert(valuesType.Obj())

	// func ParseQuery(query string) (Values, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseQuery",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "query", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", valuesType),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func ParseRequestURI(rawURL string) (*URL, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "ParseRequestURI",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "rawURL", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", urlPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func User(username string) *Userinfo
	scope.Insert(types.NewFunc(token.NoPos, pkg, "User",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "username", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", userinfoPtr)),
			false)))

	// func UserPassword(username, password string) *Userinfo
	scope.Insert(types.NewFunc(token.NoPos, pkg, "UserPassword",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "username", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "password", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", userinfoPtr)),
			false)))

	// URL methods
	urlRecv := types.NewVar(token.NoPos, nil, "u", urlPtr)

	// func (*URL) String() string
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(urlRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (*URL) Query() Values
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "Query",
		types.NewSignatureType(urlRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", valuesType)),
			false)))

	// func (*URL) Hostname() string
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "Hostname",
		types.NewSignatureType(urlRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (*URL) Port() string
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "Port",
		types.NewSignatureType(urlRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (*URL) RequestURI() string
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "RequestURI",
		types.NewSignatureType(urlRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (*URL) EscapedPath() string
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "EscapedPath",
		types.NewSignatureType(urlRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (*URL) EscapedFragment() string
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "EscapedFragment",
		types.NewSignatureType(urlRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (*URL) Redacted() string
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "Redacted",
		types.NewSignatureType(urlRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (*URL) IsAbs() bool
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "IsAbs",
		types.NewSignatureType(urlRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func (*URL) ResolveReference(ref *URL) *URL
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "ResolveReference",
		types.NewSignatureType(urlRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ref", urlPtr)),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", urlPtr)),
			false)))

	// func (*URL) MarshalBinary() ([]byte, error)
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "MarshalBinary",
		types.NewSignatureType(urlRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.NewSlice(types.Typ[types.Byte])),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func (*URL) UnmarshalBinary(text []byte) error
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "UnmarshalBinary",
		types.NewSignatureType(urlRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "text", types.NewSlice(types.Typ[types.Byte]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// Values methods
	valuesRecv := types.NewVar(token.NoPos, nil, "v", valuesType)

	// func (Values) Get(key string) string
	valuesType.AddMethod(types.NewFunc(token.NoPos, pkg, "Get",
		types.NewSignatureType(valuesRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (Values) Set(key, value string)
	valuesType.AddMethod(types.NewFunc(token.NoPos, pkg, "Set",
		types.NewSignatureType(valuesRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String])),
			nil, false)))

	// func (Values) Add(key, value string)
	valuesType.AddMethod(types.NewFunc(token.NoPos, pkg, "Add",
		types.NewSignatureType(valuesRecv, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "value", types.Typ[types.String])),
			nil, false)))

	// func (Values) Del(key string)
	valuesType.AddMethod(types.NewFunc(token.NoPos, pkg, "Del",
		types.NewSignatureType(valuesRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String])),
			nil, false)))

	// func (Values) Has(key string) bool
	valuesType.AddMethod(types.NewFunc(token.NoPos, pkg, "Has",
		types.NewSignatureType(valuesRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "key", types.Typ[types.String])),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func (Values) Encode() string
	valuesType.AddMethod(types.NewFunc(token.NoPos, pkg, "Encode",
		types.NewSignatureType(valuesRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// Userinfo methods
	uiRecv := types.NewVar(token.NoPos, nil, "u", userinfoPtr)

	// func (*Userinfo) Username() string
	userinfoType.AddMethod(types.NewFunc(token.NoPos, pkg, "Username",
		types.NewSignatureType(uiRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// func (*Userinfo) Password() (string, bool)
	userinfoType.AddMethod(types.NewFunc(token.NoPos, pkg, "Password",
		types.NewSignatureType(uiRecv, nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.Bool])),
			false)))

	// func (*Userinfo) String() string
	userinfoType.AddMethod(types.NewFunc(token.NoPos, pkg, "String",
		types.NewSignatureType(uiRecv, nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", types.Typ[types.String])),
			false)))

	// type Error struct { Op, URL string; Err error }
	urlErrStruct := types.NewStruct([]*types.Var{
		types.NewField(token.NoPos, pkg, "Op", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "URL", types.Typ[types.String], false),
		types.NewField(token.NoPos, pkg, "Err", errType, false),
	}, nil)
	urlErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "Error", nil),
		urlErrStruct, nil)
	urlErrPtr := types.NewPointer(urlErrType)
	urlErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", urlErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))
	urlErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Unwrap",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", urlErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", errType)),
			false)))
	urlErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Timeout",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", urlErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	urlErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Temporary",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", urlErrPtr), nil, nil,
			nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.Bool])),
			false)))
	scope.Insert(urlErrType.Obj())

	// func (*URL) JoinPath(elem ...string) *URL
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "JoinPath",
		types.NewSignatureType(urlRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "elem",
				types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(types.NewVar(token.NoPos, pkg, "", urlPtr)),
			true)))

	// func (*URL) Parse(ref string) (*URL, error)
	urlType.AddMethod(types.NewFunc(token.NoPos, pkg, "Parse",
		types.NewSignatureType(urlRecv, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, pkg, "ref", types.Typ[types.String])),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", urlPtr),
				types.NewVar(token.NoPos, pkg, "", errType)),
			false)))

	// func JoinPath(base string, elem ...string) (string, error)
	scope.Insert(types.NewFunc(token.NoPos, pkg, "JoinPath",
		types.NewSignatureType(nil, nil, nil,
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "base", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "elem", types.NewSlice(types.Typ[types.String]))),
			types.NewTuple(
				types.NewVar(token.NoPos, pkg, "", types.Typ[types.String]),
				types.NewVar(token.NoPos, pkg, "", errType)),
			true)))

	// EscapeError (returned by invalid escape sequences)
	escapeErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "EscapeError", nil),
		types.Typ[types.String], nil)
	scope.Insert(escapeErrType.Obj())
	escapeErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", escapeErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	// InvalidHostError
	invalidHostErrType := types.NewNamed(
		types.NewTypeName(token.NoPos, pkg, "InvalidHostError", nil),
		types.Typ[types.String], nil)
	scope.Insert(invalidHostErrType.Obj())
	invalidHostErrType.AddMethod(types.NewFunc(token.NoPos, pkg, "Error",
		types.NewSignatureType(types.NewVar(token.NoPos, nil, "e", invalidHostErrType), nil, nil, nil,
			types.NewTuple(types.NewVar(token.NoPos, nil, "", types.Typ[types.String])),
			false)))

	pkg.MarkComplete()
	return pkg
}
