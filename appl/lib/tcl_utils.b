implement Tcl_Utils;
include "sys.m";
include "draw.m";
include "tk.m";
include "tcl.m";
include "tcllib.m";
include "utils.m";

break_it(s : string) : array of string {
	argv:= array[200] of string;
	buf : string;
	argc := 0;
	nc := 0;
   outer:
	for (i := 0; i < len s ; ) {
		case int s[i] {
		' ' or '\t' or '\n' =>
			if (nc > 0) {	# end of a word?
				argv[argc++] = buf;
				buf = nil;
				nc = 0;
			}
			i++;
		'{' =>
			if (s[i+1]=='}'){
				argv[argc++] = nil;
				buf = nil;
				nc = 0;	
				i+=2;
			}else{
				nbra := 1;
				for (i++; i < len s; i++) {
					if (s[i] == '{')
						nbra++;
					else if (s[i] == '}') {
						nbra--;
					if (nbra == 0) {
							i++;
							continue outer;
						}
					}
					buf[nc++] = s[i];
				}
			}	
		* =>
			buf[nc++] = s[i++];
		}
	}
	if (nc > 0)	# fix up last word if present
		argv[argc++] = buf;
	ret := array[argc] of string;
	ret[0:] = argv[0:argc];
	return ret;
}

arr_resize(argv : array of string) : array of string {
	ret := array[len argv + 25] of string;
	ret[0:]=argv;
	return ret;
}

