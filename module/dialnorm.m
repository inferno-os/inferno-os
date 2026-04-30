Dialnorm: module
{
	PATH: con "/dis/lib/dialnorm.dis";

	# normalize coerces a user-typed dial address into Inferno's
	# tcp!host!port form.
	#
	#   - Strings containing '!' are returned unchanged (already
	#     in Inferno dial syntax — could be tcp!h!p, udp!h!p, etc.)
	#   - host:port and ip:port (with a numeric port) become
	#     tcp!host!port.
	#   - Anything else (no port, non-numeric port, empty host)
	#     is returned unchanged so the caller can let the dial
	#     syscall surface its native error.
	normalize: fn(s: string): string;
};
