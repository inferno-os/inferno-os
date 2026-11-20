#
# CPace (draft-irtf-cfrg-cpace) over X25519 with SHA-512: a balanced
# password-authenticated key exchange. Two parties that share a secret
# string agree on a key; anyone else, watching or taking part, can test
# one guess at the secret for each run and learns nothing else about it.
#
Cpace: module
{
	PATH:	con "/dis/lib/cpace.dis";

	Sharelen:	con 32;
	ISKlen:		con 64;

	init:	fn(): string;

	# the generator for a secret prs, a channel identifier ci and a session identifier sid
	generator:	fn(prs, ci, sid: array of byte): array of byte;
	# the public share g**y for a private y of 32 random bytes
	share:	fn(g, y: array of byte): array of byte;
	# the key, for the initiator (sent ya first, with associated data ada) or the
	# responder: y is one's own private value and peer the other's share.
	# nil if peer is not an acceptable share.
	isk:	fn(sid, y, peer: array of byte, ya, ada, yb, adb: array of byte): array of byte;

	# the draft's lv_cat: each part preceded by its length
	lvcat:	fn(parts: list of array of byte): array of byte;
};
