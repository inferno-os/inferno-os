#
# cowfs.m - Copy-on-Write Filesystem for Veltro Agent Safety
#
# Provides a transparent overlay so agent writes never touch real files
# until the user explicitly promotes them. Reads fall through to the
# base when the overlay has no modification.
#
# Each granted path gets its own cowfs instance. The agent sees a merged
# view; the real files are never modified until promotion.
#

Cowfs: module {
	PATH: con "/dis/veltro/cowfs.dis";

	# Start a cowfs instance serving basepath with writes to overlaydir.
	# Returns mount FD for caller to sys->mount(), or nil + error.
	start: fn(basepath, overlaydir: string): (ref Sys->FD, string);

	# List modified files. Returns list of "M relpath" / "A relpath" / "D relpath".
	diff: fn(overlaydir: string): list of string;

	# Count modified files in overlay.
	modcount: fn(overlaydir: string): int;

	# Copy overlay files to base, apply whiteout deletes, clear overlay.
	promote: fn(basepath, overlaydir: string): (int, string);

	# Promote a single file. Returns nil on success, error on failure.
	promotefile: fn(basepath, overlaydir, relpath: string): string;

	# Discard all overlay changes.
	revert: fn(overlaydir: string): string;

	# Revert a single file.
	revertfile: fn(overlaydir, relpath: string): string;
};
