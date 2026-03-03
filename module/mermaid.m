#
# mermaid.m — Native Mermaid diagram renderer interface
#
# Parses Mermaid syntax and renders to a Draw->Image using Inferno
# drawing primitives only.  No external HTTP calls or third-party services.
#
# Supported diagram types:
#   flowchart / graph  (TD LR BT RL)
#   pie
#   sequenceDiagram
#   gantt
#   xychart-beta
#
Mermaid: module
{
	PATH: con "/dis/lib/mermaid.dis";

	# Initialize with display and fonts.
	# mainfont: proportional font for labels and titles.
	# monofont: monospace font (may be nil, falls back to mainfont).
	# Must be called before render().
	init: fn(disp: ref Draw->Display,
		 mainfont: ref Draw->Font,
		 monofont: ref Draw->Font);

	# Render a Mermaid syntax string to an image.
	# width: desired image width in pixels (0 = default 800).
	# Returns (image, nil) on success, (nil, errmsg) on failure.
	render: fn(syntax: string, width: int): (ref Draw->Image, string);
};
