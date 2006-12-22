Ctype: module
{
	PATH: con "/dis/charon/ctype.dis";

	# Classify first NCTYPE chars of Unicode into one of
	#
	#   W: whitespace
	#   D: decimal digit
	#   L: lowercase letter
	#   U: uppercase letter
	#   N: '.' or '-' (parts of certain kinds of names)
	#   S: '_' (parts of other kinds of names)
	#   P: printable other than all of above
	#   C: control other than whitespace
	#
	# These are separate bits, so can test for, e.g., ctype[c]&(U|L),
	# but only one is set for any particular character,
	# so can use faster ctype[c]==W too.

	W, D, L, U, N, S, P, C: con byte (1<<iota);
	NCTYPE: con 256;

	ctype: array of byte;
};
