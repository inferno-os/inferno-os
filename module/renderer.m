#
# Renderer - Dynamic content rendering interface for Xenith
#
# A Renderer module takes raw file bytes and produces a Draw->Image
# for display in a Xenith window body.  The underlying text content
# (if any) is handled separately by the caller -- the renderer is
# purely a visual concern.
#
# Renderers are dynamically loaded Limbo modules that can live anywhere:
#   /dis/xenith/render/   - built-in renderers
#   /dis/render/          - user-installed renderers
#   network paths         - fetched on demand
#
# Each renderer implements this interface and is registered with the
# Xenith render registry (see Render module).
#

Renderer: module {
	# RenderProgress mirrors ImgProgress but is renderer-agnostic.
	# For image renderers, rowsdone/rowstotal track decode progress.
	# For document renderers, they can track pages or percentage.
	# The image field carries the current (possibly partial) render.
	RenderProgress: adt {
		image: ref Draw->Image;  # Current rendered output (partial or complete)
		done: int;               # Units completed (rows, pages, etc.)
		total: int;              # Total units (0 if unknown)
	};

	# RenderInfo describes what the renderer produces.
	# Used by the registry to understand renderer capabilities.
	RenderInfo: adt {
		name: string;         # Human-readable name ("PNG image", "PDF document")
		extensions: string;   # Space-separated extensions (".png .ppm .pgm")
		hastextcontent: int;  # 1 if renderer can extract text for the body buffer
	};

	# Command describes an action the renderer supports.
	# Renderers declare their available commands; Xenith presents
	# them through Plan 9-style mouse chording / context menu.
	#
	# The tag field controls where/how the command appears:
	#   "b2" - button 2 (middle click) menu
	#   "b3" - button 3 (right click) context menu
	#   "tag" - appears in window tag as executable text
	#
	# Commands are dispatched back to the renderer via the
	# command() function.
	Command: adt {
		name: string;     # Command name ("Zoom", "Grab", "Play", "Stop")
		tag: string;      # Where it appears: "b2", "b3", "tag"
		key: string;      # Keyboard shortcut hint (informational, e.g., "+", "-")
		arg: string;      # Default argument (nil if none)
	};

	# Initialize the renderer with the display for image allocation.
	init: fn(d: ref Draw->Display);

	# Return renderer metadata.
	info: fn(): ref RenderInfo;

	# Probe raw data to check if this renderer can handle it.
	# Returns confidence 0-100 (0 = cannot handle, 100 = certain).
	# The hint is typically the file path/extension.
	canrender: fn(data: array of byte, hint: string): int;

	# Render content to a Draw->Image, with progressive updates.
	# width/height are the available display area (for renderers that
	# need to know target size, e.g. document/HTML renderers).
	# Pass 0,0 if the renderer should use native dimensions.
	# The progress channel receives partial results during rendering.
	# Send nil to progress when complete.
	# Returns (final image, extracted text, error string).
	# Extracted text is nil if the content has no text representation.
	render: fn(data: array of byte, hint: string,
	           width, height: int,
	           progress: chan of ref RenderProgress): (ref Draw->Image, string, string);

	# Return the list of commands this renderer supports.
	# Called once after init() and cached by the registry.
	# The list is context-dependent: a video renderer might return
	# Play/Pause/Stop, an image renderer Zoom/Grab/Rotate.
	commands: fn(): list of ref Command;

	# Execute a renderer command.  The arg string carries any
	# argument (e.g., zoom level, page number).  Returns
	# (new image, error) — the new image replaces the current
	# display, or nil if the display doesn't change.
	# The data parameter is the original file content so the
	# renderer can re-render at different parameters.
	command: fn(cmd: string, arg: string,
	            data: array of byte, hint: string,
	            width, height: int): (ref Draw->Image, string);
};
