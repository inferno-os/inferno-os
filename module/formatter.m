#
# Formatter - Pure text-to-text content formatting interface
#
# A Formatter module takes raw text and produces visually formatted
# text using Unicode characters for display in a Xenith text frame.
# No Draw dependency -- output is plain text with Unicode box-drawing,
# bullets, etc.
#
# The formatted text lives in the native text frame, giving free
# scrolling, selection, and proper redraw.
#

Formatter: module {
	FormatterInfo: adt {
		name: string;		# "Markdown", "HTML"
		extensions: string;	# ".md .markdown"
	};

	init: fn();
	info: fn(): ref FormatterInfo;
	canformat: fn(data: string, hint: string): int;	# confidence 0-100
	format: fn(text: string, width: int): string;		# raw -> typeset
};
