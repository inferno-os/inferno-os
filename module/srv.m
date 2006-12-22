Srv: module
{
	PATH:	con	"$Srv";	# some hosted, never native

	#
	# IP network database lookups
	#
	#	iph2a:	host name to ip addrs
	#	ipa2h:	ip addr to host aliases
	#	ipn2p:	service name to port
	#
	iph2a:	fn(host: string): list of string;
	ipa2h:	fn(addr: string): list of string;
	ipn2p:	fn(net, service: string): string;

	init:	fn();
};
