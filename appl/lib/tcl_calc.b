implement TclLib;

include "sys.m";
	sys: Sys;

include "draw.m";

include "tk.m";

include "string.m";
	str : String;

include "tcl.m";

include "tcllib.m";

include "math.m";
	math : Math;

include "regex.m";
	regex : Regex;

include "utils.m";
	htab: Int_Hashtab;

IHash: import htab;

leaf : adt {
	which : int;
	s_val : string;
	i_val : int;
	r_val : real;
};

where : int;
text:string;
EOS,MALFORMED,UNKNOWN,REAL,INT,STRING,FUNC,ADD,SUB,MUL,MOD,DIV,LAND,
LOR,BAND,BOR,BEOR,EXCL,TILDE,QUEST,COLON,F_ABS,F_ACOS,F_ASIN,F_ATAN,
F_ATAN2,F_CEIL,F_COS,F_COSH,F_EXP,F_FLOOR,F_FMOD,F_HYPOT,F_LOG,F_LOG10,
F_POW,F_SIN,F_SINH,F_SQRT,F_TAN,F_TANH,L_BRACE,R_BRACE,COMMA,LSHIF,RSHIF,
LT,GT,LEQ,GEQ,EQ,NEQ : con iota; 
i_val : int;
r_val : real;
s_val : string;
numbers : con "-?(([0-9]+)|([0-9]*\\.[0-9]+)([eE][-+]?[0-9]+)?)";
re : Regex->Re;
f_table : ref IHash;
started : int;

# does an eval on a string. The string is assumed to be 
# mathematically correct. No Tcl parsing is done.

commands := array[] of {"calc"};

about() : array of string {
	return commands;
}

init() : string {
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
	math = load Math Math->PATH;
	regex = load Regex Regex->PATH;
	htab = load Int_Hashtab Int_Hashtab->PATH;
	started=1;
	if (regex==nil || math==nil || str==nil || htab==nil)
		return "Cannot initialise calc module.";
	f_table=htab->alloc(101);
	f_table.insert("abs",F_ABS);
	f_table.insert("acos",F_ACOS);
	f_table.insert("asin",F_ASIN);
	f_table.insert("atan",F_ATAN);
	f_table.insert("atan2",F_ATAN2);
	f_table.insert("ceil",F_CEIL);
	f_table.insert("cos",F_COS);
	f_table.insert("cosh",F_COSH);
	f_table.insert("exp",F_EXP);
	f_table.insert("floor",F_FLOOR);
	f_table.insert("fmod",F_FMOD);		
	f_table.insert("hypot",F_HYPOT);
	f_table.insert("log",F_LOG);
	f_table.insert("log10",F_LOG10);
	f_table.insert("pow",F_POW);
	f_table.insert("sin",F_SIN);
	f_table.insert("sinh",F_SINH);
	f_table.insert("sqrt",F_SQRT);
	f_table.insert("tan",F_TAN);
	f_table.insert("tanh",F_TANH);
	(re,nil)=regex->compile(numbers, 0);
	return nil;
}

uarray:= array[] of { EXCL, 0, 0, 0, MOD, BAND, 0, L_BRACE, R_BRACE, MUL,
	ADD, COMMA, SUB, 0, DIV, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, COLON,
	0, LT, EQ, GT, QUEST};

getTok(eat : int) : int {
	val, s : string;
	dec:=0;
	s=text;
	i:=0;
	if (s==nil) 
		return EOS;
	while(i<len s && (s[i]==' '||s[i]=='\t')) i++;
	if (i==len s)
		return EOS;
	case s[i]{
		'+' or '-' or '*' or '?' or '%' or '/' or '(' 
		or ')' or ',' or ':' =>  
			if (eat)
				text=s[i+1:];
			return uarray[s[i]-'!'];
		'~'  =>
			if (eat)
				text=s[i+1:];
			return TILDE;	
		'^'  =>
			if (eat)
				text=s[i+1:];
			return BEOR;
		'&' =>
			if (s[i+1]=='&'){
				if (eat)
					text=s[i+2:];
				return LAND;
			}
			if (eat)
				text=s[i+1:];
			return BAND;
			
		'|' =>			
			if (s[i+1]=='|'){
				if (eat)
					text=s[i+2:];
				return LOR;
			}
			if (eat)
				text=s[i+1:];
			return BOR;

		'!' =>	
			if (s[i+1]=='='){
				if (eat)
					text=s[i+2:];
				return NEQ;
			}
			if (eat)
				text=s[i+1:];
			return EXCL;
		'=' =>
			if (s[i+1]!='=')
				return UNKNOWN;
			if (eat)
				text=s[i+2:];
			return EQ;
		'>' =>
			case s[i+1]{
				'>' =>
					if (eat)
						text=s[i+2:];
					return RSHIF;
				'=' => 
					if (eat)
						text=s[i+2:];
					return GEQ;
				* =>
					if (eat)
						text=s[i+1:];
					return GT;
			}
		'<' =>
			case s[i+1]{
				'<' =>
					if (eat)
						text=s[i+2:];
					return LSHIF;
				'=' => 
					if (eat)
						text=s[i+2:];
					return LEQ;
				* =>
					if (eat)
						text=s[i+1:];
					return LT;
			}
		'0' =>
			return oct_hex(eat);
		'1' to '9' 
		or '.'=>
			
			match:=regex->execute(re,s[i:]);
			if (match != nil)
				(i1, i2) := match[0];
			if (match==nil || i1!=0)
				sys->print("ARRG! non-number where number should be!");
			if (eat)
				text=s[i+i2:];
			val=s[i:i+i2];
			if (str->in('.',val) || str->in('e',val)
				|| str->in('E',val)) {
				r_val=real val;
				return REAL;
			}
			i_val=int val;
			return INT;
		* =>
			return get_func(eat);	
		}
	return UNKNOWN;
}

oct_hex(eat : int) : int {
	s:=text;
	rest : string;
	if (len s == 1){
		i_val=0;
		if (eat)
			text=nil;
		return INT;
	}
	if(s[1]=='x' || s[1]=='X'){
		(i_val,rest)=str->toint(s[2:],16);
		if (eat)
			text = rest;
		return INT;
	}
	if (s[1]=='.'){
		match:=regex->execute(re,s);
		if (match != nil)
			(i1, i2) := match[0];
		if (match==nil || i1!=0)
			sys->print("ARRG!");
		if (eat)
			text=s[i2:];
		val:=s[0:i2];
		r_val=real val;
		return REAL;
	}
	(i_val,rest)=str->toint(s[1:],8);
	if (eat)
		text = rest;
	return INT;
}

get_func(eat : int) : int{
	s:=text;
	i:=0;
	tok:=STRING;
	while(i<len s && ((s[i]>='a' && s[i]<='z') || 
			 (s[i]>='A' && s[i]<='Z') || 
			 (s[i]>='0' && s[i]<='9') || (s[i]=='_'))) i++;
	(found,val):=f_table.find(s[0:i]);
	if (found)
		tok=val;
	else
		s_val = s[0:i];
	if (eat)
		text = s[i:];
	return tok;
}


exec(tcl: ref Tcl_Core->TclData,argv : array of string) : (int,string){
	if (tcl==nil);
	if (!started)
		if ((msg:=init())!=nil)
			return (1,msg);
	retval : leaf;
	expr:="";
	for (i:=0;i<len argv;i++){
		expr+=argv[i];
		expr[len expr]=' ';
	}
	if (expr=="") 
		return (1,"Error!");
	text=expr[0:len expr-1];
	#sys->print("Text is %s\n",text);
	retval = expr_9();
	if (retval.which == UNKNOWN)
		return (1,"Error!");
	if (retval.which == INT)
		return (0,string retval.i_val);
	if (retval.which == STRING)
		return (0,retval.s_val);
	return (0,string retval.r_val);
}

expr_9() : leaf {
	retval : leaf;
	r1:=expr_8();
	tok := getTok(0);
	if(tok==QUEST){ 
		getTok(1);
		r2:=expr_8();
		if (getTok(1)!=COLON)
			r1.which=UNKNOWN;
		r3:=expr_8();
		if (r1.which == INT && r1.i_val==0)
			return r3;
		if (r1.which == INT && r1.i_val!=0)
			return r2;
		if (r1.which == REAL && r1.r_val==0.0)
			return r3;
		if (r1.which == REAL && r1.r_val!=0.0)
			return r2;
		retval.which=UNKNOWN;
		return retval;
	}
	return r1;
}


expr_8() : leaf {
	retval : leaf;
	r1:=expr_7();
	retval=r1;
	tok := getTok(0);
	if (tok == LOR){
		getTok(1);
		r2:=expr_7(); # start again?
		if (r1.which!=INT || r2.which!=INT){
			retval.which = UNKNOWN;
			return retval;
		}
		retval.i_val=r1.i_val || r2.i_val;	
		return retval;
	}
	return retval;
}

expr_7() : leaf {
	retval : leaf;
	r1:=expr_6();
	retval=r1;
	tok := getTok(0);
	if (tok == LAND){
		getTok(1);
		r2:=expr_6();
		if (r1.which!=INT || r2.which!=INT){
			retval.which = UNKNOWN;
			return retval;
		}
		retval.i_val=r1.i_val && r2.i_val;	
		return retval;
	}
	return retval;
}

expr_6() : leaf {
	retval : leaf;
	r1:=expr_5();
	retval=r1;
	tok := getTok(0);
	if (tok == BOR){
		getTok(1);
		r2:=expr_5();
		if (r1.which!=INT || r2.which!=INT){
			retval.which = UNKNOWN;
			return retval;
		}
		retval.i_val=r1.i_val | r2.i_val;	
		return retval;
	}
	return retval;
}

expr_5() : leaf {
	retval : leaf;
	r1:=expr_4();
	retval=r1;
	tok := getTok(0);
	if (tok == BEOR){
		getTok(1);
		r2:=expr_4();
		if (r1.which!=INT || r2.which!=INT){
			retval.which = UNKNOWN;
			return retval;
		}
		retval.i_val=r1.i_val ^ r2.i_val;	
		return retval;
	}
	return retval;
}

expr_4() : leaf {
	retval : leaf;
	r1:=expr_3();
	retval=r1;
	tok := getTok(0);
	if (tok == BAND){
		getTok(1);
		r2:=expr_3();
		if (r1.which!=INT || r2.which!=INT){
			retval.which = UNKNOWN;
			return retval;
		}
		retval.i_val=r1.i_val & r2.i_val;	
		return retval;
	}
	return retval;
}
	
expr_3() : leaf {
	retval : leaf;
	r1:=expr_2();
	retval=r1;
	tok:=getTok(0);
	if (tok==EQ || tok==NEQ){
		retval.which=INT;
		getTok(1);
		r2:=expr_2();
		if (r1.which==UNKNOWN || r2.which==UNKNOWN){
			r1.which=UNKNOWN;
			return r1;
		}
		if (tok==EQ){
			case r1.which {
				STRING =>
					if (r2.which == INT)
					   retval.i_val = 
					    (r1.s_val == string r2.i_val);
					else if (r2.which == REAL)
					   retval.i_val = 
				 	    (r1.s_val == string r2.r_val);
					else retval.i_val = 
						   (r1.s_val == r2.s_val);
				INT =>
					if (r2.which == INT)
					   retval.i_val = 
						   (r1.i_val == r2.i_val);
					else if (r2.which == REAL)
					   retval.i_val = 
					      (real r1.i_val == r2.r_val);
					else retval.i_val = 
					    (string r1.i_val == r2.s_val);
				REAL =>
					if (r2.which == INT)
					   retval.i_val = 
					      (r1.r_val == real r2.i_val);
					else if (r2.which == REAL)
					   retval.i_val = 
						   (r1.r_val == r2.r_val);
					else retval.i_val = 
					    (string r1.r_val == r2.s_val);
			}
		}
		else {
			case r1.which {
				STRING =>
					if (r2.which == INT)
					   retval.i_val = 
					    (r1.s_val != string r2.i_val);
					else if (r2.which == REAL)
					   retval.i_val = 
				 	    (r1.s_val != string r2.r_val);
					else retval.i_val = 
						   (r1.s_val != r2.s_val);
				INT =>
					if (r2.which == INT)
					   retval.i_val = 
						   (r1.i_val != r2.i_val);
					else if (r2.which == REAL)
					   retval.i_val = 
					      (real r1.i_val != r2.r_val);
					else retval.i_val = 
					    (string r1.i_val != r2.s_val);
				REAL =>
					if (r2.which == INT)
					   retval.i_val = 
					      (r1.r_val != real r2.i_val);
					else if (r2.which == REAL)
					   retval.i_val = 
						   (r1.r_val != r2.r_val);
					else retval.i_val = 
					    (string r1.r_val != r2.s_val);
			}
		}			
		return retval;
	}
	return retval;
}


expr_2() : leaf {
	retval : leaf;
	ar1,ar2 : real;
	s1,s2 : string;
	r1:=expr_1();
	retval=r1;
	tok:=getTok(0);
	if (tok==LT || tok==GT || tok ==LEQ || tok==GEQ){
		retval.which=INT;
		getTok(1);
		r2:=expr_1();
		if (r1.which == STRING || r2.which == STRING){
			if (r1.which==STRING)
				s1=r1.s_val;
			else if (r1.which==INT)
				s1=string r1.i_val;
			else s1= string r1.r_val;
			if (r2.which==STRING)
				s2=r2.s_val;
			else if (r2.which==INT)
				s2=string r2.i_val;
			else s2= string r2.r_val;
			case tok{
				LT =>
					retval.i_val = (s1<s2);
				GT =>
					retval.i_val = (s1>s2);
				LEQ =>
					retval.i_val = (s1<=s2);
				GEQ =>
					retval.i_val = (s1>=s2);
			}
			return retval;
		}
		if (r1.which==UNKNOWN || r2.which==UNKNOWN){
			r1.which=UNKNOWN;
			return r1;
		}
		if (r1.which == INT)
			ar1 = real r1.i_val;
		else
			ar1 = r1.r_val;
		if (r2.which == INT)
			ar2 = real r2.i_val;
		else
			ar2 = r2.r_val;
		case tok{
			LT =>
				retval.i_val = (ar1<ar2);
			GT =>
				retval.i_val = (ar1>ar2);
			LEQ =>
				retval.i_val = (ar1<=ar2);
			GEQ =>
				retval.i_val = (ar1>=ar2);
		}
		return retval;
	}
	return retval;
}
expr_1() : leaf {
	retval : leaf;
	r1:=expr0();
	retval=r1;
	tok := getTok(0);
	if (tok == LSHIF || tok==RSHIF){
		getTok(1);
		r2:=expr0();
		if (r1.which!=INT || r2.which!=INT){
			retval.which = UNKNOWN;
			return retval;
		}
		if (tok == LSHIF)
			retval.i_val=r1.i_val << r2.i_val;
		if (tok == RSHIF)
			retval.i_val=r1.i_val >> r2.i_val;
		return retval;
	}
	return retval;
}
	
expr0() : leaf {
	retval : leaf;
	r1:=expr1();
	retval=r1;
	tok := getTok(0);
	while(tok==ADD || tok==SUB){
		getTok(1);
		r2:=expr1();
		if (r1.which==UNKNOWN || r2.which==UNKNOWN){
			r1.which=UNKNOWN;
			return r1;
		}
		if (r2.which==r1.which){
			case tok{
				ADD =>
					if (r1.which==INT)
						r1.i_val+=r2.i_val;
					else if (r1.which==REAL)
						r1.r_val+=r2.r_val;
				SUB =>
					if (r1.which==INT)
						r1.i_val-=r2.i_val;
					else if (r1.which==REAL)
						r1.r_val-=r2.r_val;
			}
			retval = r1;
		}else{
			retval.which = REAL;
			ar1,ar2 : real;
			if (r1.which==INT)
				ar1= real r1.i_val;
			else
				ar1 = r1.r_val;
			if (r2.which==INT)
				ar2= real r2.i_val;
			else
				ar2 = r2.r_val;
			if (tok==ADD)
				retval.r_val = ar1+ar2;
			if (tok==SUB)
				retval.r_val = ar1-ar2;
		}
	tok=getTok(0);
	}
	return retval;
}

expr1() : leaf	{
	retval : leaf;
	r1:=expr2();
	retval=r1;
	tok := getTok(0);
	while(tok==MUL || tok==DIV || tok==MOD){
		getTok(1);
		r2:=expr2();
		if (tok==MOD){
			if (r1.which!=INT && r2.which!=INT){
				r1.which=UNKNOWN;
				return r1;
			}
			r1.i_val %= r2.i_val;
			return r1;
		}
		if (r1.which==UNKNOWN || r2.which==UNKNOWN){
			r1.which=UNKNOWN;
			return r1;
		}
		if (r2.which==r1.which){
			case tok{
				MUL =>
					if (r1.which==INT)
						r1.i_val*=r2.i_val;
					else if (r1.which==REAL)
						r1.r_val*=r2.r_val;
				DIV =>
					if (r1.which==INT)
						r1.i_val/=r2.i_val;
					else if (r1.which==REAL)
						r1.r_val/=r2.r_val;
			}
			retval = r1;
		}else{
			retval.which = REAL;
			ar1,ar2 : real;
			if (r1.which==INT)
				ar1= real r1.i_val;
			else
				ar1 = r1.r_val;
			if (r2.which==INT)
				ar2= real r2.i_val;
			else
				ar2 = r2.r_val;
			if (tok==MUL)
				retval.r_val = ar1*ar2;
			if (tok==DIV)
				retval.r_val = ar1/ar2;
		}
	tok=getTok(0);
	}
	return retval;
}

expr2() : leaf	{
	tok := getTok(0);
	if(tok==ADD || tok==SUB || tok==EXCL || tok==TILDE){
		getTok(1);
		r1:=expr2();
		if (r1.which!=UNKNOWN)
			case tok{
				ADD =>
					;
				SUB =>
					if (r1.which==INT)
						r1.i_val=-r1.i_val;
					else if (r1.which==REAL)
						r1.r_val=-r1.r_val;
				EXCL =>
					if (r1.which != INT)
						r1.which=UNKNOWN;
					else
						r1.i_val = !r1.i_val;
				TILDE =>
					if (r1.which != INT)
						r1.which=UNKNOWN;
					else
						r1.i_val = ~r1.i_val;
			}
		else
			r1.which = UNKNOWN;	
		return r1;
	}
	return expr5();
}

do_func(tok : int) : leaf {
	retval : leaf;
	r1,r2 : real;
	ok : int;
	retval.which=REAL;
	case tok{
		F_ACOS => 
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->acos(r1);
		F_ASIN => 
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->asin(r1);
		F_ATAN => 
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->atan(r1);
		F_ATAN2 => 
			(ok,r1,r2)=pars_rfunc(2);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->atan2(r1,r2);
		F_CEIL => 
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->ceil(r1);
		F_COS =>
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->cos(r1); 
		F_COSH =>
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->cosh(r1);
		F_EXP => 
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->exp(r1);
		F_FLOOR => 
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->floor(r1);
		F_FMOD => 
			(ok,r1,r2)=pars_rfunc(2);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->fmod(r1,r2);
		F_HYPOT =>
			(ok,r1,r2)=pars_rfunc(2);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->hypot(r1,r2);
		F_LOG =>
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->log(r1);
		F_LOG10 =>
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->log10(r1);
		F_POW =>
			(ok,r1,r2)=pars_rfunc(2);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->pow(r1,r2);
		F_SIN =>
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->sin(r1);
		F_SINH =>
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->sinh(r1);
		F_SQRT =>
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->sqrt(r1);
		F_TAN =>
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->tan(r1);
		F_TANH =>
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->tanh(r1);
		F_ABS =>
			(ok,r1,r2)=pars_rfunc(1);
			if (!ok){
				retval.which=UNKNOWN;
				return retval;
			}
			retval.r_val=math->fabs(r1);
		* =>
			sys->print("unexpected op %d\n", tok);
			retval.which=UNKNOWN;
	}
	return retval;
}

pars_rfunc(args : int) : (int,real,real){
	a1,a2 : real;
	ok := 1;
	if (getTok(0)!=L_BRACE)
		ok=0;	
	getTok(1);
	r1:=expr_9();
	if (r1.which == INT)
		a1 = real r1.i_val;
	else if (r1.which == REAL)
		a1 = r1.r_val;
	else ok=0;
	if(args==2){
		if (getTok(0)!=COMMA)
			ok=0;
		getTok(1);
		r2:=expr_9();
		if (r2.which == INT)
			a2 = real r2.i_val;
		else if (r2.which == REAL)
			a2 = r2.r_val;
		else ok=0;
	}
	if (getTok(0)!=R_BRACE)
		ok=0;	
	getTok(1);
	return (ok,a1,a2);
}


expr5() : leaf {
	retval : leaf;
	tok:=getTok(1);
	if (tok>=F_ABS && tok<=F_TANH)
		return do_func(tok);
	case tok{
		STRING =>
			retval.which = STRING;
			retval.s_val = s_val;
		INT =>
			retval.which = INT;
			retval.i_val = i_val;
		REAL =>
			retval.which = REAL;
			retval.r_val = r_val;
		R_BRACE or COMMA =>
			return retval;
		L_BRACE => 
			r1:=expr_9();
			if (getTok(1)!=R_BRACE)
				r1.which=UNKNOWN;
			return r1;
		* =>
			retval.which = UNKNOWN;
	}
	return retval;
}

