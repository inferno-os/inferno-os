#
# Rlayout - Rich text layout engine for Xenith renderers
#
# Takes a document tree (list of DocNode) and renders it to a Draw->Image.
# Shared between markdown and HTML renderers. Uses Draw font measurement
# for line breaking and text() for rendering.
#

Rlayout: module {
	PATH: con "/dis/xenith/render/rlayout.dis";

	# Document node types
	Ntext,          # Inline text run
	Nbold,          # Bold text
	Nitalic,        # Italic text (rendered with underline, since we have limited fonts)
	Ncode,          # Inline code (monospace)
	Nlink,          # Hyperlink (rendered as underlined text)
	Npara,          # Paragraph block
	Nheading,       # Heading block (level in aux)
	Ncodeblock,     # Code block (monospace, background)
	Nbullet,        # Bullet list item
	Nnumber,        # Numbered list item (number in aux)
	Nhrule,         # Horizontal rule
	Nblockquote,    # Block quote
	Nnewline        # Explicit line break
		: con iota;

	# Document node: tree of content
	DocNode: adt {
		kind: int;            # Node type (Ntext, Nbold, etc.)
		text: string;         # Text content (for Ntext, Ncode, etc.)
		children: list of ref DocNode;  # Child nodes (for blocks)
		aux: int;             # Auxiliary data (heading level, list number)
	};

	# Layout configuration
	Style: adt {
		width: int;           # Available width in pixels
		margin: int;          # Left/right margin
		font: ref Draw->Font; # Base proportional font
		codefont: ref Draw->Font; # Monospace font
		fgcolor: ref Draw->Image; # Text color
		bgcolor: ref Draw->Image; # Background color
		linkcolor: ref Draw->Image; # Link color
		codebgcolor: ref Draw->Image; # Code block background
		h1scale: int;         # H1 size multiplier x100 (150 = 1.5x, via repeated text)
	};

	init: fn(d: ref Draw->Display);

	# Render a document to an image.
	# Returns (image, total height used).
	render: fn(doc: list of ref DocNode, style: ref Style): (ref Draw->Image, int);

	# Extract plain text from a document tree (for AI/body buffer).
	totext: fn(doc: list of ref DocNode): string;
};
