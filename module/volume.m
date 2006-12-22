Volumectl: module
{
	PATH:	con "/dis/lib/volume.dis";

	# Volumectl should be spawned as a separate process from
	# any process that desires volume control.  The parameters
	# are a ref Context that provides volumectl with access to
	# the display, a chan of int through which volumectl receives
	# Ir->Enter, Ir->VolUP, or Ir->VolDN commands (others are
	# ignored), and a string that names the specific volume to
	# be controlled (typically "audio out").
	# Volumectl exits upon receiving Ir->Enter.
	# It displays a volume control slider when receiving either
	# Ir->VolUP or Ir->VolDN.  The slider automatically disappears
	# after a period of inactivity.

	volumectl:	fn(ctxt: ref Draw->Context, ch: chan of int, device: string);
};
