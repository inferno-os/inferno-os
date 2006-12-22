ESHostobj: module
{
	#
	# extensible interface for adding host objects
	#
	# any implementation must obey the rules of the interpreter.
	# it is an error to return bogus values, and may cause
	# the interpreter to crash.
	#
	# get/put must return/set the value of property in o
	#
	# canput and hasproperty return es->true or es->false
	#
	# defaultval must return a primitive (non-object) value.
	#	this means it can't return a String object, etc.
	#
	# call gets the caller's execution context in ex.
	# the new this value is passed as an argument,
	# but no new scopechain is allocated
	# it returns a reference, which is typically just a value
	#
	# construct should make up a new object
	#
	get:		fn(ex: ref Ecmascript->Exec, o: ref Ecmascript->Obj, property: string): ref Ecmascript->Val;
	put:		fn(ex: ref Ecmascript->Exec, o: ref Ecmascript->Obj, property: string, val: ref Ecmascript->Val);
	canput:		fn(ex: ref Ecmascript->Exec, o: ref Ecmascript->Obj, property: string): ref Ecmascript->Val;
	hasproperty:	fn(ex: ref Ecmascript->Exec, o: ref Ecmascript->Obj, property: string): ref Ecmascript->Val;
	delete:		fn(ex: ref Ecmascript->Exec, o: ref Ecmascript->Obj, property: string);
	defaultval:	fn(ex: ref Ecmascript->Exec, o: ref Ecmascript->Obj, tyhint: int): ref Ecmascript->Val;
	call:		fn(ex: ref Ecmascript->Exec, func, this: ref Ecmascript->Obj, args: array of ref Ecmascript->Val, eval: int): ref Ecmascript->Ref;
	construct:	fn(ex: ref Ecmascript->Exec, func: ref Ecmascript->Obj, args: array of ref Ecmascript->Val): ref Ecmascript->Obj;
};

#
# calls to init and mkexec do the following
#	math->FPcontrol(0, Math->INVAL|Math->ZDIV|Math->OVFL|Math->UNFL|Math->INEX);
#
Ecmascript: module
{
	PATH:	con "/dis/lib/ecmascript.dis";

	#
	# an execution context
	#
	Exec: adt
	{
		#
		# well known glop
		#
		objproto:	cyclic ref Obj;
		funcproto:	cyclic ref Obj;
		strproto:	cyclic ref Obj;	
		numproto:	cyclic ref Obj;
		boolproto:	cyclic ref Obj;
		arrayproto:	cyclic ref Obj;
		dateproto:	cyclic ref Obj;
		regexpproto:	cyclic ref Obj;
		errproto:		cyclic ref Obj;
		evlerrproto:		cyclic ref Obj;
		ranerrproto:		cyclic ref Obj;
		referrproto:		cyclic ref Obj;
		synerrproto:		cyclic ref Obj;
		typerrproto:		cyclic ref Obj;
		urierrproto:		cyclic ref Obj;
		interrproto:		cyclic ref Obj;
		
		global:		cyclic ref Obj;
		this:		cyclic ref Obj;
		scopechain:	cyclic list of ref Obj;

		error:		string;
		errval:		cyclic ref Val;

		#
		# private, keep out
		#
		stack:		cyclic array of ref Ref;
		sp:	int;
	};

	#
	# must be called at the dawn of time
	# returns error string
	init:	fn(): string;

	#
	# initialize a new global execution context
	# if go is supplied, it's the global object
	# if not, one is made up automatically
	#
	mkexec:		fn(go: ref Obj): ref Exec;

	#
	# throw a runtime error
	# msg ends up in ex.error, and an
	# "ecmascript runtime error" is raised
	#
	RUNTIME:	con "ecmascript runtime error";
	runtime:	fn(ex: ref Exec, o: ref Obj, msg: string);

	# runtime errors
	EvalError, RangeError, ReferenceError, SyntaxError, TypeError, URIError, InternalError: ref Obj;

	#
	# debug flags: array of 256 indexed by char
	#
	# e	print ops as they are executed
	# f	abort on an internal error
	# p	print parsed code
	# r	abort on any runtime error
	# v	print value of expression statements
	#
	debug: array of int;

	#
	# parse and runt the source string
	#
	eval:	fn(ex: ref Exec, src: string): Completion;

	Re: type ref Arena;

	# the fundamental data structure
	Obj: adt
	{
		props:		cyclic array of ref Prop;
		prototype:	cyclic ref Obj;		# some builtin properties
		val:		cyclic ref Val;
		call:		cyclic ref Call;
		construct:	cyclic ref Call;
		class:		string;
		host:		ESHostobj;		# method suite for host objects
		re:		Re;				# compiled regexp for RegExp objects
	};

	Call: adt
	{
		params:		array of string;
		code:		cyclic ref Code;
		ex:		cyclic ref Exec;
	};

	# attributes
	ReadOnly, DontEnum, DontDelete: con 1 << iota;
	Prop: adt
	{
		attr:		int;
		name:		string;
		val:		cyclic ref RefVal;
	};

	# an extra level of indirection, because sometimes properties are aliased
	RefVal: adt
	{
		val:		cyclic ref Val;
	};

	# types of js values
	TUndef, TNull, TBool, TNum, TStr, TObj, TRegExp, NoHint: con iota;
	Val: adt
	{
		ty:		int;
		num:		real;
		str:		string;
		obj:		cyclic ref Obj;
		rev:		ref REval;
	};

	# regular expression
	REval: adt
	{
		p: string;
		f: string;
		i: int;
	};

	# intermediate result of expression evaluation
	Ref: adt
	{
		isref:		int;
		val:		ref Val;
		base:		ref Obj;
		name:		string;				# name of property within base
	};

	# completion values of statements
	CNormal, CBreak, CContinue, CReturn, CThrow: con iota;
	Completion: adt
	{
		kind:		int;
		val:		ref Val;
		lab:		string;
	};

	Code: adt
	{
		ops:		array of byte;			# all instructions
		npc:		int;				# end of active portion of ops
		vars:		cyclic array of ref Prop;	# variables defined in the code
		ids:		array of string;		# ids used in the code
		strs:		array of string;		# string literal
		nums:		array of real;			# numerical literals
		fexps:	cyclic array of ref Obj;	# function expressions
	};

	#
	# stuff for adding host objects
	#
	# ecmascript is also a host object;
	get:		fn(ex: ref Ecmascript->Exec, o: ref Ecmascript->Obj, property: string): ref Ecmascript->Val;
	put:		fn(ex: ref Ecmascript->Exec, o: ref Ecmascript->Obj, property: string, val: ref Ecmascript->Val);
	canput:		fn(ex: ref Ecmascript->Exec, o: ref Ecmascript->Obj, property: string): ref Ecmascript->Val;
	hasproperty:	fn(ex: ref Ecmascript->Exec, o: ref Ecmascript->Obj, property: string): ref Ecmascript->Val;
	delete:		fn(ex: ref Ecmascript->Exec, o: ref Ecmascript->Obj, property: string);
	defaultval:	fn(ex: ref Ecmascript->Exec, o: ref Ecmascript->Obj, tyhint: int): ref Ecmascript->Val;
	call:		fn(ex: ref Ecmascript->Exec, func, this: ref Ecmascript->Obj, args: array of ref Ecmascript->Val, eval: int): ref Ecmascript->Ref;
	construct:	fn(ex: ref Ecmascript->Exec, func: ref Ecmascript->Obj, args: array of ref Ecmascript->Val): ref Ecmascript->Obj;

	#
	# return the named variable from the scope chain sc
	#
	bivar:		fn(ex: ref Exec, sc: list of ref Obj, s: string): ref Val;

	#
	# return the nth argument value, or undefined if too far
	#
	biarg:		fn(args: array of ref Val, n: int): ref Val;

	#
	# make up a new object
	# most often called as mkobj(ex.objproto, "Object")
	#
	mkobj:		fn(proto: ref Obj, class: string): ref Obj;

	#
	# object installation helpers
	#
	Builtin: adt
	{
		name:	string;
		val:	string;
		params:	array of string;
		length:	int;
	};
	biinst:		fn(o: ref Obj, bi: Builtin, proto: ref Obj, h: ESHostobj): ref Obj;
	biminst:	fn(o: ref Obj, bis: array of Builtin, proto: ref Obj, h: ESHostobj);

	#
	# instantiate a new variable inside an object
	#
	varinstant:	fn(in: ref Obj, attr: int, name: string, val: ref RefVal);

	#
	# various constructors
	#
	objval:		fn(o: ref Obj): ref Val;
	strval:		fn(s: string): ref Val;
	numval:		fn(r: real): ref Val;
	valref:		fn(v: ref Val): ref Ref;

	#
	# conversion routines defined in section 9
	#
	toPrimitive:	fn(ex: ref Exec, v: ref Val, ty: int): ref Val;
	toBoolean:	fn(ex: ref Exec, v: ref Val): ref Val;
	toNumber:	fn(ex: ref Exec, v: ref Val): real;
	toInteger:	fn(ex: ref Exec, v: ref Val): real;
	toInt32:	fn(ex: ref Exec, v: ref Val): int;
	toUint32:	fn(ex: ref Exec, v: ref Val): big;
	toUint16:	fn(ex: ref Exec, v: ref Val): int;
	toString:	fn(ex: ref Exec, v: ref Val): string;
	toObject:	fn(ex: ref Exec, v: ref Val): ref Obj;

	#
	# simple coercion routines to force
	# Boolean, String, and Number values to objects and vice versa
	#
	coerceToObj:	fn(ex: ref Exec, v: ref Val): ref Val;
	coerceToVal:	fn(v: ref Val): ref Val;

	#
	# object/value kind checkers
	#
	isstrobj:	fn(o: ref Obj): int;
	isnumobj:	fn(o: ref Obj): int;
	isboolobj:	fn(o: ref Obj): int;
	isdateobj:	fn(o: ref Obj): int;
	isregexpobj: fn(o: ref Obj): int;
	isarray:	fn(o: ref Obj): int;
	isstr:		fn(v: ref Val): int;
	isnum:		fn(v: ref Val): int;
	isbool:		fn(v: ref Val): int;
	isobj:		fn(v: ref Val): int;

	#
	# well-known ecmascript primitive values
	#
	undefined:	ref Val;
	true:		ref Val;
	false:		ref Val;
	null:		ref Val;

	# regexp data structures

	refRex: type int;	# used instead of ref Rex to avoid circularity

	Set: adt {				# character class
		neg: int;			# 0 or 1
		ascii: array of int;		# ascii members, bit array
		unicode: list of (int,int);	# non-ascii char ranges
		subset: cyclic list of ref Set;
	};

	Nstate: adt{
		m: int;
		n: int;
	};

	Rex: adt {		# node in parse of regex, or state of fsm
		kind: int;	# kind of node: char or ALT, CAT, etc
		left: refRex;	# left descendant
		right: refRex;	# right descendant, or next state
		set: ref Set;	# character class
		pno: int;
		greedy: int;
		ns: ref Nstate;
	};

	Arena: adt {		# free store from which nodes are allocated
		rex: array of Rex;		
		ptr: refRex;	# next available space
		start: refRex;	# root of parse, or start of fsm
		pno: int;
	};
};
