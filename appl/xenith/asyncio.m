Asyncio: module {
	PATH: con "/dis/xenith/asyncio.dis";

	init: fn(mods: ref Dat->Mods);

	# Async operation messages sent to casync channel
	AsyncMsg: adt {
		pick {
			Chunk =>
				opid: int;      # Operation ID
				data: string;   # Chunk of data read
				offset: int;    # Position in file
			Progress =>
				opid: int;
				current: int;   # Bytes processed so far
				total: int;     # Total bytes (0 if unknown)
			Complete =>
				opid: int;
				nbytes: int;    # Total bytes read
				nrunes: int;    # Total runes (characters)
				err: string;    # nil on success
			Error =>
				opid: int;
				err: string;
			ImageData =>
				opid: int;
				winid: int;     # Window ID for the image
				path: string;   # Image path (for display in tag)
				data: array of byte;  # Raw image bytes
				err: string;    # nil on success
		ImageDecoded =>
				winid: int;     # Window ID for the image
				path: string;   # Image path (for display in tag)
				image: ref Draw->Image;  # Decoded image (nil on error)
				err: string;    # nil on success
		ImageProgress =>
				winid: int;     # Window ID for the image
				path: string;   # Image path
				image: ref Draw->Image;  # Image being decoded (partial content)
				rowsdone: int;  # Rows decoded so far
				rowstotal: int; # Total rows
		# Content rendering messages (renderer-based pipeline)
		ContentData =>
				opid: int;
				winid: int;     # Window ID
				path: string;   # File path
				data: array of byte;  # Raw file bytes
				err: string;    # nil on success
		ContentDecoded =>
				winid: int;     # Window ID
				path: string;   # File path (for display in tag)
				image: ref Draw->Image;  # Rendered image (nil on error)
				text: string;   # Extracted text content (nil if none)
				err: string;    # nil on success
		ContentProgress =>
				winid: int;     # Window ID
				path: string;   # File path
				image: ref Draw->Image;  # Partial render
				done: int;      # Units completed
				total: int;     # Total units
		TextData =>
				opid: int;      # Operation ID
				winid: int;     # Window ID for the text
				path: string;   # File path
				q0: int;        # Insert position (start of file content)
				data: string;   # Chunk of text data
				offset: int;    # Rune offset within file (cumulative)
				err: string;    # nil on success
		TextComplete =>
				opid: int;      # Operation ID
				winid: int;     # Window ID for the text
				path: string;   # File path
				nbytes: int;    # Total bytes read
				nrunes: int;    # Total runes read
				err: string;    # nil on success
		DirEntry =>
				opid: int;      # Operation ID
				winid: int;     # Window ID
				name: string;   # Entry name (with trailing / for dirs)
				isdir: int;     # 1 if directory
		DirComplete =>
				opid: int;      # Operation ID
				winid: int;     # Window ID
				path: string;   # Directory path
				nentries: int;  # Total entries read
				err: string;    # nil on success
		SaveProgress =>
				opid: int;      # Operation ID
				winid: int;     # Window ID
				written: int;   # Bytes written so far
				total: int;     # Total bytes to write
		SaveComplete =>
				opid: int;      # Operation ID
				winid: int;     # Window ID
				path: string;   # File path
				nbytes: int;    # Total bytes written
				mtime: int;     # New mtime after save
				err: string;    # nil on success
		}
	};

	# Async operation handle for cancellation
	AsyncOp: adt {
		opid: int;
		ctl: chan of int;   # Send 1 to cancel
		path: string;
		active: int;
		winid: int;         # Window ID (for image ops)
	};

	# Start async file read - returns operation handle
	asyncload: fn(path: string, q0: int): ref AsyncOp;

	# Start async image load - returns operation handle
	asyncloadimage: fn(path: string, winid: int): ref AsyncOp;

	# Start async content load (for renderer pipeline) - returns operation handle
	asyncloadcontent: fn(path: string, winid: int): ref AsyncOp;

	# Start async text file load - returns operation handle
	asyncloadtext: fn(path: string, q0: int, winid: int): ref AsyncOp;

	# Start async directory listing - returns operation handle
	asyncloaddir: fn(path: string, winid: int): ref AsyncOp;

	# Start async file save - returns operation handle
	# Reads from buffer positions q0..q1 and writes to path
	asyncsavefile: fn(path: string, winid: int, buf: ref Bufferm->Buffer, q0, q1: int): ref AsyncOp;

	# Cancel an async operation
	asynccancel: fn(op: ref AsyncOp);

	# Check if operation is still active
	asyncactive: fn(op: ref AsyncOp): int;

	# Note: Results are sent to dat->casync channel
};
