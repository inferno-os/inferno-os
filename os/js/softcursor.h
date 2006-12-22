/*
 * this should be #define'd to nothing if you have a hardware cursor
 */

void	cursormaybeoff(Rectangle*, Memimage*, Rectangle, Memimage*, Point*);

/*
 * also, you should #define cussoron() and cursoroff() to nothing
 * if you have a hardware cursor.. This isn't as bad as it sounds, because
 * this file is only included in port/devdraw.c, and it doesn't need to
 * touch the cursor if it's a hardware cursor
 *	-Tad
 */
