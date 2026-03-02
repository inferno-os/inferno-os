#
# Tlayout - Text layout engine for Xenith formatters
#
# Takes a document tree (list of DocNode) and produces typeset plain text
# using Unicode characters for headings, rules, code blocks, etc.
# Shared between markdown and HTML text formatters.
#
# No Draw dependency -- output is a string.
#

Tlayout: module {
	PATH: con "/dis/xenith/render/tlayout.dis";

	# Document node types (same values as rlayout.m for consistency)
	Ntext,		# Inline text run
	Nbold,		# Bold text (pass through -- single font)
	Nitalic,	# Italic text (pass through)
	Ncode,		# Inline code (keep backtick delimiters)
	Nlink,		# Hyperlink (show text only)
	Npara,		# Paragraph block
	Nheading,	# Heading block (level in aux)
	Ncodeblock,	# Code block (indent + bar prefix)
	Nbullet,	# Bullet list item
	Nnumber,	# Numbered list item (number in aux)
	Nhrule,		# Horizontal rule
	Nblockquote,	# Block quote
	Nnewline,	# Explicit line break
	Ntable,		# Table container
	Ntablerow	# Table row
		: con iota;

	# Document node: tree of content
	DocNode: adt {
		kind: int;
		text: string;
		children: list of ref DocNode;
		aux: int;
	};

	init: fn();

	# Convert document tree to typeset text.
	totext: fn(doc: list of ref DocNode, width: int): string;
};
