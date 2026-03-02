Render: module {
	PATH: con "/dis/xenith/render.dis";

	# Registry entry: maps content types to renderer module paths
	RendererEntry: adt {
		name: string;           # Display name ("PNG image", "PDF document")
		modpath: string;        # Dis module path (e.g., "/dis/xenith/render/imgrender.dis")
		extensions: string;     # Space-separated extensions (".png .ppm .pgm")
		priority: int;          # Higher = preferred when multiple match
	};

	init: fn(d: ref Draw->Display);

	# Register a renderer by module path.  The renderer is loaded
	# and queried for its info().  Returns nil on success, error string on failure.
	register: fn(modpath: string): string;

	# Find the best renderer for the given data and path hint.
	# Checks extension first, then probes registered renderers.
	# Returns (loaded Renderer module, nil) or (nil, error).
	find: fn(data: array of byte, path: string): (Renderer, string);

	# Find renderer by extension only (without data probing).
	# Useful for pre-checking before async load completes.
	findbyext: fn(path: string): (Renderer, string);

	# List all registered renderers.
	getall: fn(): list of ref RendererEntry;

	# Check if a file path matches any registered renderer extension.
	# Replaces look.b's isimage() with a general content check.
	iscontent: fn(path: string): int;
};
