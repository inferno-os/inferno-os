/*
 * SDL3 GUI Backend for Infernode
 *
 * This module provides cross-platform GUI via SDL3.
 * It is completely self-contained and can be removed
 * without impacting Infernode core.
 *
 * Platforms: macOS (Metal), Linux (Vulkan/OpenGL), Windows (D3D12)
 *
 * Function signatures match stubs-headless.c for drop-in replacement.
 *
 * RENDERING ARCHITECTURE (Performance Critical)
 * =============================================
 *
 * Infernode's draw system calls flushmemscreen() frequently during rendering
 * (100-1000+ times per frame for text-heavy operations like directory
 * listings or text selection). The naive implementation would call
 * SDL_UpdateTexture() and SDL_RenderPresent() on each flush, but on macOS
 * this requires dispatch_sync() to the main thread for each call, creating
 * massive synchronization overhead (multi-second delays for simple operations).
 *
 * Solution: Batched Dirty Rectangle Accumulation
 *
 *   1. flushmemscreen() does NO synchronization - it only accumulates
 *      dirty rectangles into a bounding box (O(1), ~10 nanoseconds)
 *
 *   2. sdl3_mainloop() runs on the main thread at ~60Hz and performs:
 *      - Single SDL_UpdateTexture() with the accumulated dirty region
 *      - Single SDL_RenderPresent() per frame
 *
 * This reduces cross-thread synchronization from 1000s of dispatch_sync()
 * calls per frame to zero, while maintaining correct rendering.
 *
 * The tradeoff is ~16ms maximum latency from draw to display, which is
 * imperceptible and far better than the previous multi-second delays.
 */

#include "dat.h"
#include "fns.h"
#include "error.h"
#include "keyboard.h"
#include <draw.h>
#include <memdraw.h>
#include <cursor.h>

#include <SDL3/SDL.h>

#ifdef __APPLE__
#include <dispatch/dispatch.h>
#include <pthread.h>
#endif

/* External keyboard queue (from devcons.c) */
extern Queue *gkbdq;

/* SDL3 state - private to this module */
static SDL_Window *sdl_window = NULL;
static SDL_Renderer *sdl_renderer = NULL;
static SDL_Texture *sdl_texture = NULL;
static int sdl_width = 0;
static int sdl_height = 0;
static int sdl_running = 0;
static int sdl_initialized = 0;  /* Flag: SDL already initialized on main thread */

/* Mouse state */
static int mouse_x = 0;
static int mouse_y = 0;
static int mouse_buttons = 0;

/*
 * Event-based button state tracking.
 *
 * SDL_GetMouseState() returns the instantaneous button state at the time
 * of the call, NOT the state at the time a queued event was generated.
 * When a fast click produces both BUTTON_DOWN and BUTTON_UP events before
 * the event loop runs, SDL_GetMouseState() during BUTTON_DOWN processing
 * already shows the button released — the click is silently lost.
 *
 * This variable tracks button state from events: BUTTON_DOWN sets bits,
 * BUTTON_UP clears them, mirroring how the X11 backend (win-x11a.c)
 * derives state from the event structure.
 */
static Uint32 sdl_button_state = 0;

/* HiDPI state - for coordinate conversion */
static float display_scale = 1.0f;

/* Shutdown request flag - can be set from any thread */
static volatile int sdl_quit_requested = 0;

/*
 * Dirty rectangle accumulator for batched updates.
 *
 * CRITICAL PERFORMANCE FIX:
 * Previously, flushmemscreen() called dispatch_sync() for every tiny
 * texture update (100s of times per frame for text rendering), causing
 * massive synchronization overhead. Now flushmemscreen() just accumulates
 * dirty rectangles with NO synchronization, and the main loop does a
 * single dispatch_sync() per frame to upload all changes at once.
 */
static volatile int dirty_pending = 0;
static int dirty_min_x = 0, dirty_min_y = 0;
static int dirty_max_x = 0, dirty_max_y = 0;

/* Screen data pointer (set by attachscreen) */
static uchar *screen_data = NULL;

/*
 * Destination rectangle for rendering texture to window.
 * Used to maintain aspect ratio and center content when
 * window size differs from texture size (e.g., full-screen).
 */
static SDL_FRect dest_rect = {0, 0, 0, 0};
static int window_width = 0;
static int window_height = 0;

/*
 * Calculate destination rectangle for centered, aspect-ratio-preserving render.
 * This prevents stretching/distortion when window and texture sizes differ.
 */
static void
calc_dest_rect(void)
{
	float scale_x, scale_y, scale;
	float dest_w, dest_h;

	if (window_width <= 0 || window_height <= 0 ||
	    sdl_width <= 0 || sdl_height <= 0) {
		dest_rect.x = 0;
		dest_rect.y = 0;
		dest_rect.w = (float)sdl_width;
		dest_rect.h = (float)sdl_height;
		return;
	}

	/* Calculate scale to fit texture in window while maintaining aspect ratio */
	scale_x = (float)window_width / (float)sdl_width;
	scale_y = (float)window_height / (float)sdl_height;
	scale = (scale_x < scale_y) ? scale_x : scale_y;

	/* Calculate destination size */
	dest_w = (float)sdl_width * scale;
	dest_h = (float)sdl_height * scale;

	/* Center in window */
	dest_rect.x = ((float)window_width - dest_w) / 2.0f;
	dest_rect.y = ((float)window_height - dest_h) / 2.0f;
	dest_rect.w = dest_w;
	dest_rect.h = dest_h;
}

/*
 * Transform window mouse coordinates to texture coordinates.
 * Accounts for letterboxing offset and scaling.
 */
static void
window_to_texture_coords(float win_x, float win_y, int *tex_x, int *tex_y)
{
	float rel_x, rel_y;
	int x, y;

	if (dest_rect.w <= 0 || dest_rect.h <= 0) {
		/* Fallback - direct mapping */
		*tex_x = (int)win_x;
		*tex_y = (int)win_y;
		return;
	}

	/* Subtract letterbox offset to get position relative to rendered texture */
	rel_x = win_x - dest_rect.x;
	rel_y = win_y - dest_rect.y;

	/* Scale from rendered size to texture size */
	x = (int)(rel_x * (float)sdl_width / dest_rect.w);
	y = (int)(rel_y * (float)sdl_height / dest_rect.h);

	/* Clamp to texture bounds */
	if (x < 0) x = 0;
	if (y < 0) y = 0;
	if (x >= sdl_width) x = sdl_width - 1;
	if (y >= sdl_height) y = sdl_height - 1;

	*tex_x = x;
	*tex_y = y;
}

/*
 * Map raw SDL button state to Inferno button mask with modifier key emulation.
 * On macOS laptops without a three-button mouse:
 *   - Option + Left Click  = Button 2 (middle click)
 *   - Command + Left Click = Button 3 (right click)
 * This follows Plan 9 / Acme conventions.
 *
 * Takes the raw SDL button bitmask (from event-based tracking) rather than
 * polling SDL_GetMouseState(), which can miss fast clicks due to a race
 * between event queuing and state polling.
 */
static int
map_buttons(Uint32 state)
{
	int buttons = 0;
	SDL_Keymod mods = SDL_GetModState();

	/* Check for physical buttons */
	int left = (state & SDL_BUTTON_LMASK) ? 1 : 0;
	int middle = (state & SDL_BUTTON_MMASK) ? 1 : 0;
	int right = (state & SDL_BUTTON_RMASK) ? 1 : 0;

	/* Emulate button 2 (middle) with Option/Alt + Left Click */
	if (left && (mods & SDL_KMOD_ALT)) {
		buttons |= 2;  /* Button 2 */
	}
	/* Emulate button 3 (right) with Command/GUI + Left Click */
	else if (left && (mods & SDL_KMOD_GUI)) {
		buttons |= 4;  /* Button 3 */
	}
	/* Normal left click (no emulation) */
	else if (left) {
		buttons |= 1;  /* Button 1 */
	}

	/* Physical middle and right buttons always work */
	if (middle)
		buttons |= 2;
	if (right)
		buttons |= 4;

	return buttons;
}

/*
 * Update tracked button state from an SDL mouse button event.
 * Returns the SDL button mask bit for the event's button.
 */
static Uint32
button_event_mask(Uint8 button)
{
	switch (button) {
	case SDL_BUTTON_LEFT:   return SDL_BUTTON_LMASK;
	case SDL_BUTTON_MIDDLE: return SDL_BUTTON_MMASK;
	case SDL_BUTTON_RIGHT:  return SDL_BUTTON_RMASK;
	default:                return 0;
	}
}

/* Forward declarations */
static void sdl_atexit_handler(void);
void sdl_shutdown(void);

/*
 * Pre-initialize SDL3 on main thread
 * Called from main() before threading starts
 */
int
sdl3_preinit(void)
{
	const char *driver;

	/*
	 * Initialize SDL3 on the main thread.
	 * On macOS, this must happen before any Cocoa window operations.
	 * We use the native driver (Cocoa on macOS) for real GUI.
	 */
	if (!SDL_Init(SDL_INIT_VIDEO)) {
		fprint(2, "sdl3_preinit: SDL_Init failed: %s\n", SDL_GetError());
		return 0;
	}

	/* Set app metadata for macOS menu bar and About dialog */
	SDL_SetAppMetadata("InferNode", "1.0", "systems.nerv.infernode");
	SDL_SetAppMetadataProperty(SDL_PROP_APP_METADATA_CREATOR_STRING, "NERV Systems");
	SDL_SetAppMetadataProperty(SDL_PROP_APP_METADATA_COPYRIGHT_STRING, "Copyright 2026 NERV Systems. MIT License.");
	SDL_SetAppMetadataProperty(SDL_PROP_APP_METADATA_URL_STRING, "https://github.com/NERVsystems/infernode");
	SDL_SetAppMetadataProperty(SDL_PROP_APP_METADATA_TYPE_STRING, "Operating System");

	driver = SDL_GetCurrentVideoDriver();
	USED(driver);

	/* Register cleanup handler to ensure window closes on exit */
	atexit(sdl_atexit_handler);

	sdl_initialized = 1;
	return 1;
}

/*
 * atexit handler - ensures SDL cleanup happens on program exit
 */
static void
sdl_atexit_handler(void)
{
	sdl_shutdown();
}

/*
 * Initialize SDL3 and create window
 * Returns pointer to screen buffer
 */
uchar*
attachscreen(Rectangle *r, ulong *chan, int *d, int *width, int *softscreen)
{
	/* SDL3 should already be initialized from main thread */
	if (!sdl_initialized)
		return nil;

	/* Get screen dimensions from globals */
	sdl_width = Xsize;
	sdl_height = Ysize;

	/* Create window - dispatch to main thread on macOS */
#ifdef __APPLE__
	/* Dispatch to main thread (Cocoa requirement) */
	__block SDL_Window *created_window = NULL;

	dispatch_sync(dispatch_get_main_queue(), ^{
		created_window = SDL_CreateWindow(
			"InferNode",
			sdl_width, sdl_height,
			SDL_WINDOW_RESIZABLE
		);
	});

	sdl_window = created_window;
	if (!sdl_window)
		return nil;

	/* Get physical pixel dimensions for native resolution rendering */
	{
		int win_x, win_y, win_w, win_h, pix_w, pix_h;
		float scale;
		SDL_GetWindowPosition(sdl_window, &win_x, &win_y);
		SDL_GetWindowSize(sdl_window, &win_w, &win_h);
		SDL_GetWindowSizeInPixels(sdl_window, &pix_w, &pix_h);
		scale = SDL_GetWindowDisplayScale(sdl_window);

		USED(win_x);
		USED(win_y);

		/*
		 * Use physical pixel dimensions for crisp rendering.
		 * This fixes fuzzy/blurry graphics on HiDPI displays.
		 * Mouse coordinates will be scaled in event handlers.
		 */
		display_scale = scale;
		sdl_width = pix_w;
		sdl_height = pix_h;

		/* Initialize window tracking for centered rendering */
		window_width = win_w;
		window_height = win_h;
		calc_dest_rect();
	}
#else
	/* Linux/Windows: Direct call */
	sdl_window = SDL_CreateWindow(
		"InferNode",
		sdl_width, sdl_height,
		SDL_WINDOW_RESIZABLE
	);

	if (!sdl_window) {
		fprint(2, "draw-sdl3: SDL_CreateWindow failed: %s\n", SDL_GetError());
		return nil;
	}

	/* Get physical pixel dimensions for native resolution rendering */
	{
		int win_w, win_h, pix_w, pix_h;
		float scale;
		SDL_GetWindowSize(sdl_window, &win_w, &win_h);
		SDL_GetWindowSizeInPixels(sdl_window, &pix_w, &pix_h);
		scale = SDL_GetWindowDisplayScale(sdl_window);

		display_scale = scale;
		sdl_width = pix_w;
		sdl_height = pix_h;

		/* Initialize window tracking for centered rendering */
		window_width = win_w;
		window_height = win_h;
		calc_dest_rect();
	}
#endif

	/* Create renderer and texture - also needs main thread on macOS */
#ifdef __APPLE__
	__block SDL_Renderer *created_renderer = NULL;
	__block SDL_Texture *created_texture = NULL;

	dispatch_sync(dispatch_get_main_queue(), ^{
		created_renderer = SDL_CreateRenderer(sdl_window, NULL);
		if (!created_renderer)
			return;

		/*
		 * Disable vsync to ensure consistent rendering.
		 * VSync can cause subtle timing-related visual artifacts.
		 */
		SDL_SetRenderVSync(created_renderer, 0);

		/*
		 * Disable logical presentation scaling.
		 * This ensures 1:1 pixel mapping from texture to display
		 * and prevents any automatic scaling/interpolation that
		 * could cause fuzziness when the window is "idle".
		 */
		SDL_SetRenderLogicalPresentation(created_renderer, sdl_width, sdl_height,
			SDL_LOGICAL_PRESENTATION_DISABLED);

		/*
		 * Texture is created at native physical resolution (set above).
		 * This gives crisp rendering on HiDPI displays.
		 */

		/* Create texture - XRGB8888 matches Infernode's XRGB32 */
		created_texture = SDL_CreateTexture(
			created_renderer,
			SDL_PIXELFORMAT_XRGB8888,
			SDL_TEXTUREACCESS_STREAMING,
			sdl_width, sdl_height
		);

		/*
		 * Use nearest-neighbor scaling to prevent blurry text.
		 * Without this, SDL3 defaults to linear filtering which
		 * causes subtle fuzziness even at native resolution.
		 */
		if (created_texture)
			SDL_SetTextureScaleMode(created_texture, SDL_SCALEMODE_NEAREST);

		SDL_ShowWindow(sdl_window);

		/* Enable text input to receive SDL_EVENT_TEXT_INPUT events */
		SDL_StartTextInput(sdl_window);
	});

	sdl_renderer = created_renderer;
	sdl_texture = created_texture;

	if (!sdl_renderer || !sdl_texture) {
		if (sdl_renderer) SDL_DestroyRenderer(sdl_renderer);
		SDL_DestroyWindow(sdl_window);
		return nil;
	}
#else
	/* Create GPU renderer */
	sdl_renderer = SDL_CreateRenderer(sdl_window, NULL);
	if (!sdl_renderer) {
		fprint(2, "SDL_CreateRenderer failed: %s\n", SDL_GetError());
		SDL_DestroyWindow(sdl_window);
		SDL_Quit();
		return nil;
	}

	/*
	 * Disable vsync to ensure consistent rendering.
	 */
	SDL_SetRenderVSync(sdl_renderer, 0);

	/*
	 * Disable logical presentation scaling.
	 * This ensures 1:1 pixel mapping from texture to display
	 * and prevents any automatic scaling/interpolation that
	 * could cause fuzziness when the window is "idle".
	 */
	SDL_SetRenderLogicalPresentation(sdl_renderer, sdl_width, sdl_height,
		SDL_LOGICAL_PRESENTATION_DISABLED);

	/*
	 * Texture is created at native physical resolution (set above).
	 * This gives crisp rendering on HiDPI displays.
	 */

	/* Create streaming texture for pixel buffer */
	sdl_texture = SDL_CreateTexture(
		sdl_renderer,
		SDL_PIXELFORMAT_XRGB8888,  /* Match Infernode XRGB32 */
		SDL_TEXTUREACCESS_STREAMING,
		sdl_width, sdl_height
	);

	if (!sdl_texture) {
		fprint(2, "SDL_CreateTexture failed: %s\n", SDL_GetError());
		SDL_DestroyRenderer(sdl_renderer);
		SDL_DestroyWindow(sdl_window);
		SDL_Quit();
		return nil;
	}

	/*
	 * Use nearest-neighbor scaling to prevent blurry text.
	 * Without this, SDL3 defaults to linear filtering which
	 * causes subtle fuzziness even at native resolution.
	 */
	SDL_SetTextureScaleMode(sdl_texture, SDL_SCALEMODE_NEAREST);

	SDL_ShowWindow(sdl_window);

	/* Enable text input to receive SDL_EVENT_TEXT_INPUT events */
	SDL_StartTextInput(sdl_window);
#endif

	sdl_running = 1;

	/* Allocate screen buffer */
	screen_data = malloc(sdl_width * sdl_height * 4);
	if (!screen_data) {
		SDL_DestroyTexture(sdl_texture);
		SDL_DestroyRenderer(sdl_renderer);
		SDL_DestroyWindow(sdl_window);
		return nil;
	}

	/* Initialize buffer to white (Infernode default) */
	memset(screen_data, 0xFF, sdl_width * sdl_height * 4);

	/* Return screen parameters to Infernode */
	*r = Rect(0, 0, sdl_width, sdl_height);
	*chan = XRGB32;
	*d = 32;
	/*
	 * width is in 'ulong' words per row, not bytes.
	 * On 64-bit systems sizeof(ulong)=8, so we use wordsperline()
	 * which correctly calculates based on word size.
	 */
	*width = wordsperline(*r, *d);
	*softscreen = 1;

	return screen_data;
}

/*
 * Flush dirty rectangle to screen
 *
 * CRITICAL PERFORMANCE FIX:
 * This function NO LONGER calls dispatch_sync or SDL_UpdateTexture.
 * It only accumulates dirty rectangles into a bounding box.
 * The actual texture upload happens in sdl3_mainloop() once per frame.
 *
 * Previously, this function was called 100s of times per frame during
 * text rendering, each call doing a blocking dispatch_sync to the main
 * thread. This caused massive latency (seconds for directory listings).
 *
 * Now: flushmemscreen() is O(1) with no synchronization.
 * The main loop batches all updates into a single GPU upload per frame.
 */
void
flushmemscreen(Rectangle r)
{
	if (!sdl_running || !screen_data)
		return;

	/*
	 * Clamp dirty rectangle to screen bounds.
	 */
	if (r.min.x < 0) r.min.x = 0;
	if (r.min.y < 0) r.min.y = 0;
	if (r.max.x > sdl_width) r.max.x = sdl_width;
	if (r.max.y > sdl_height) r.max.y = sdl_height;

	/* Skip if rectangle is empty or invalid */
	if (r.min.x >= r.max.x || r.min.y >= r.max.y)
		return;

	/*
	 * Accumulate into bounding box of all dirty regions.
	 * No locking needed - single writer (Infernode), single reader (main loop).
	 */
	if (!dirty_pending) {
		dirty_min_x = r.min.x;
		dirty_min_y = r.min.y;
		dirty_max_x = r.max.x;
		dirty_max_y = r.max.y;
		dirty_pending = 1;
	} else {
		/* Expand bounding box */
		if (r.min.x < dirty_min_x) dirty_min_x = r.min.x;
		if (r.min.y < dirty_min_y) dirty_min_y = r.min.y;
		if (r.max.x > dirty_max_x) dirty_max_x = r.max.x;
		if (r.max.y > dirty_max_y) dirty_max_y = r.max.y;
	}
}

/*
 * Process SDL events and generate Infernode input events
 * Called periodically from main event loop
 */
void
sdl_pollevents(void)
{
	SDL_Event event;

	if (!sdl_running)
		return;

	while (SDL_PollEvent(&event)) {
		switch (event.type) {
		case SDL_EVENT_QUIT:
			cleanexit(0);
			break;

		case SDL_EVENT_MOUSE_MOTION:
			{
				/*
				 * Transform window coordinates to texture coordinates.
				 * This handles letterboxing offset and scaling.
				 */
				window_to_texture_coords(event.motion.x, event.motion.y,
					&mouse_x, &mouse_y);

				mouse_buttons = map_buttons(sdl_button_state);
				mousetrack(mouse_buttons, mouse_x, mouse_y, 0);
			}
			break;

		case SDL_EVENT_MOUSE_BUTTON_DOWN:
		case SDL_EVENT_MOUSE_BUTTON_UP:
			{
				/*
				 * Track button state from events to avoid race with
				 * SDL_GetMouseState().  A fast click queues both DOWN
				 * and UP before we poll; polling would show the button
				 * already released during DOWN processing, losing it.
				 */
				Uint32 mask = button_event_mask(event.button.button);
				if (event.type == SDL_EVENT_MOUSE_BUTTON_DOWN)
					sdl_button_state |= mask;
				else
					sdl_button_state &= ~mask;

				window_to_texture_coords(event.button.x, event.button.y,
					&mouse_x, &mouse_y);

				mouse_buttons = map_buttons(sdl_button_state);
				mousetrack(mouse_buttons, mouse_x, mouse_y, 0);
			}
			break;

		case SDL_EVENT_MOUSE_WHEEL:
			/* Scroll wheel as buttons 4 & 5 */
			if (event.wheel.y > 0)
				mouse_buttons = 8;   /* scroll up */
			else if (event.wheel.y < 0)
				mouse_buttons = 16;  /* scroll down */
			mousetrack(mouse_buttons, mouse_x, mouse_y, 0);
			mouse_buttons = 0;  /* Release scroll button */
			break;

		case SDL_EVENT_TEXT_INPUT:
			/*
			 * Text input event - receives actual characters with modifiers applied.
			 * This handles shift, caps lock, keyboard layout, and Option+key
			 * combinations (e.g., Option+t → †) properly.
			 * event.text.text is a UTF-8 string.
			 *
			 * macOS Option+key composition is handled here - the OS composes
			 * the character and sends it via TEXT_INPUT.
			 *
			 * Plan 9 composition is separate: Alt release sends Latin to
			 * enter compose mode, then regular keypresses compose.
			 *
			 * Skip control characters (< 0x20) - those are handled in KEY_DOWN
			 * via Ctrl+letter detection.
			 */
			{
				const unsigned char *text = (const unsigned char *)event.text.text;

				/* Skip control characters - handled by Ctrl+letter in KEY_DOWN */
				if (text[0] < 0x20 && text[0] != '\t')
					break;
				while (*text) {
					int codepoint;
					int bytes;

					/* Decode UTF-8 to Unicode codepoint */
					if ((*text & 0x80) == 0) {
						/* 1-byte ASCII: 0xxxxxxx */
						codepoint = *text;
						bytes = 1;
					} else if ((*text & 0xE0) == 0xC0) {
						/* 2-byte: 110xxxxx 10xxxxxx */
						if ((text[1] & 0xC0) != 0x80)
							goto skip;
						codepoint = ((*text & 0x1F) << 6) |
						            (text[1] & 0x3F);
						bytes = 2;
					} else if ((*text & 0xF0) == 0xE0) {
						/* 3-byte: 1110xxxx 10xxxxxx 10xxxxxx */
						if ((text[1] & 0xC0) != 0x80 ||
						    (text[2] & 0xC0) != 0x80)
							goto skip;
						codepoint = ((*text & 0x0F) << 12) |
						            ((text[1] & 0x3F) << 6) |
						            (text[2] & 0x3F);
						bytes = 3;
					} else if ((*text & 0xF8) == 0xF0) {
						/* 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx */
						if ((text[1] & 0xC0) != 0x80 ||
						    (text[2] & 0xC0) != 0x80 ||
						    (text[3] & 0xC0) != 0x80)
							goto skip;
						codepoint = ((*text & 0x07) << 18) |
						            ((text[1] & 0x3F) << 12) |
						            ((text[2] & 0x3F) << 6) |
						            (text[3] & 0x3F);
						bytes = 4;
					} else {
					skip:
						/* Invalid UTF-8, skip byte */
						text++;
						continue;
					}

					gkbdputc(gkbdq, codepoint);
					text += bytes;
				}
			}
			break;

		case SDL_EVENT_KEY_DOWN:
			{
				int key = 0;
				/*
				 * Use event.key.mod (modifier state at event time)
				 * instead of SDL_GetModState() (current state).
				 */
				SDL_Keymod mods = event.key.mod;
				/*
				 * Use the virtual keycode (event.key.key), not scancode.
				 * Scancodes are physical positions and vary by keyboard.
				 * Keycodes are logical keys: SDLK_a='a'=97, SDLK_h='h'=104, etc.
				 */
				SDL_Keycode kc = event.key.key;

				/*
				 * Handle Ctrl+letter -> control character (^A=1, ^H=8, etc.)
				 * These don't generate TEXT_INPUT events, so handle here.
				 * Use lowercase keycode range ('a' to 'z').
				 */
				if ((mods & SDL_KMOD_CTRL) && kc >= 'a' && kc <= 'z') {
					key = kc - 'a' + 1;  /* 'a'->1, 'h'->8, etc. */
				}

				/*
				 * Handle special/non-printable keys only.
				 * Printable characters come via SDL_EVENT_TEXT_INPUT.
				 * macOS Option+key composition also uses TEXT_INPUT.
				 */
				if (key == 0)
				switch (event.key.scancode) {
				case SDL_SCANCODE_ESCAPE:   key = 27; break;
				case SDL_SCANCODE_RETURN:   key = '\n'; break;
				case SDL_SCANCODE_KP_ENTER: key = '\n'; break;
				case SDL_SCANCODE_TAB:      key = '\t'; break;
				case SDL_SCANCODE_BACKSPACE: key = '\b'; break;
				case SDL_SCANCODE_DELETE:   key = 0x7F; break;
				case SDL_SCANCODE_UP:       key = Up; break;
				case SDL_SCANCODE_DOWN:     key = Down; break;
				case SDL_SCANCODE_LEFT:     key = Left; break;
				case SDL_SCANCODE_RIGHT:    key = Right; break;
				case SDL_SCANCODE_HOME:     key = Home; break;
				case SDL_SCANCODE_END:      key = End; break;
				case SDL_SCANCODE_PAGEUP:   key = Pgup; break;
				case SDL_SCANCODE_PAGEDOWN: key = Pgdown; break;
				case SDL_SCANCODE_INSERT:   key = Ins; break;
				case SDL_SCANCODE_F1:       key = KF|1; break;
				case SDL_SCANCODE_F2:       key = KF|2; break;
				case SDL_SCANCODE_F3:       key = KF|3; break;
				case SDL_SCANCODE_F4:       key = KF|4; break;
				case SDL_SCANCODE_F5:       key = KF|5; break;
				case SDL_SCANCODE_F6:       key = KF|6; break;
				case SDL_SCANCODE_F7:       key = KF|7; break;
				case SDL_SCANCODE_F8:       key = KF|8; break;
				case SDL_SCANCODE_F9:       key = KF|9; break;
				case SDL_SCANCODE_F10:      key = KF|10; break;
				case SDL_SCANCODE_F11:      key = KF|11; break;
				case SDL_SCANCODE_F12:      key = KF|12; break;
				default:
					break;  /* Printable chars handled by TEXT_INPUT */
				}

				if (key != 0)
					gkbdputc(gkbdq, key);
			}
			break;

		case SDL_EVENT_KEY_UP:
			/*
			 * Plan 9 latin1 composition: Alt/Option release sends Latin
			 * to enter compose mode. User then types two characters
			 * (without Alt held) to produce a composed glyph.
			 *
			 * This is separate from macOS composition where you HOLD
			 * Option and press a key (handled via TEXT_INPUT).
			 */
			if (event.key.scancode == SDL_SCANCODE_LALT ||
			    event.key.scancode == SDL_SCANCODE_RALT) {
				gkbdputc(gkbdq, Latin);
			}
			break;

		case SDL_EVENT_WINDOW_RESIZED:
		case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
			{
				int log_w, log_h;

				/*
				 * Window size changed (e.g., entering/exiting full-screen).
				 *
				 * We do NOT resize the texture or screen buffer here.
				 * Infernode's display size is fixed at initialization.
				 * Instead, we recalculate the destination rectangle
				 * to render the texture centered with letterboxing.
				 */
				SDL_GetWindowSize(sdl_window, &log_w, &log_h);

				fprint(2, "SDL3 resize: window=%dx%d texture=%dx%d\n",
					log_w, log_h, sdl_width, sdl_height);

				/* Update window dimensions and recalculate centered dest rect */
				window_width = log_w;
				window_height = log_h;
				calc_dest_rect();

				fprint(2, "SDL3: dest_rect=(%.1f,%.1f,%.1f,%.1f)\n",
					dest_rect.x, dest_rect.y, dest_rect.w, dest_rect.h);
			}
			break;
		}
	}
}

/*
 * Set mouse pointer position
 * Coordinates from Infernode are in texture space; we convert to window space.
 */
void
setpointer(int x, int y)
{
	float win_x, win_y;

	if (!sdl_running)
		return;

	/*
	 * Convert from texture coordinates to window coordinates.
	 * This is the inverse of window_to_texture_coords.
	 */
	if (dest_rect.w > 0 && dest_rect.h > 0 && sdl_width > 0 && sdl_height > 0) {
		/* Scale from texture size to rendered size, then add offset */
		win_x = (float)x * dest_rect.w / (float)sdl_width + dest_rect.x;
		win_y = (float)y * dest_rect.h / (float)sdl_height + dest_rect.y;
	} else {
		/* Fallback - use display_scale */
		win_x = (float)x / display_scale;
		win_y = (float)y / display_scale;
	}

	SDL_WarpMouseInWindow(sdl_window, win_x, win_y);
	mouse_x = x;
	mouse_y = y;
}

/*
 * Draw cursor (Infernode's software cursor)
 */
void
drawcursor(Drawcursor *c)
{
	/* SDL3 handles the cursor - we can implement custom cursor here if needed */
	USED(c);

	/* For now, use default cursor */
	/* TODO: Convert Infernode cursor to SDL cursor and set it */
}

/*
 * Read clipboard/snarf buffer
 */
char*
clipread(void)
{
	if (!sdl_running)
		return nil;

	if (!SDL_HasClipboardText())
		return nil;

	char *text = SDL_GetClipboardText();
	if (!text)
		return nil;

	/* Copy to Infernode-managed memory */
	char *result = strdup(text);
	SDL_free(text);

	return result;
}

/*
 * Write to clipboard/snarf buffer
 */
int
clipwrite(char *buf)
{
	if (!sdl_running)
		return 0;

	if (SDL_SetClipboardText(buf) < 0)
		return 0;

	return strlen(buf);
}

/*
 * Shutdown SDL3
 * On macOS, window operations must happen on the main thread.
 */
void
sdl_shutdown(void)
{
	sdl_running = 0;

	if (screen_data) {
		free(screen_data);
		screen_data = NULL;
	}

#ifdef __APPLE__
	/*
	 * SDL/Cocoa cleanup must happen on the main thread.
	 *
	 * If we're already on the main thread (e.g., called from sdl3_mainloop
	 * via cleanexit), execute cleanup directly. Otherwise use dispatch_sync.
	 * Using dispatch_sync when already on the main queue causes a deadlock.
	 */
	if (sdl_window) {
		if (pthread_main_np()) {
			/* Already on main thread - cleanup directly */
			SDL_HideWindow(sdl_window);

			if (sdl_texture) {
				SDL_DestroyTexture(sdl_texture);
				sdl_texture = NULL;
			}

			if (sdl_renderer) {
				SDL_DestroyRenderer(sdl_renderer);
				sdl_renderer = NULL;
			}

			SDL_DestroyWindow(sdl_window);
			sdl_window = NULL;

			SDL_Quit();
		} else {
			/* Not on main thread - dispatch to it */
			dispatch_sync(dispatch_get_main_queue(), ^{
				if (sdl_window)
					SDL_HideWindow(sdl_window);

				if (sdl_texture) {
					SDL_DestroyTexture(sdl_texture);
					sdl_texture = NULL;
				}

				if (sdl_renderer) {
					SDL_DestroyRenderer(sdl_renderer);
					sdl_renderer = NULL;
				}

				if (sdl_window) {
					SDL_DestroyWindow(sdl_window);
					sdl_window = NULL;
				}

				SDL_Quit();
			});
		}
	}
#else
	if (sdl_texture) {
		SDL_DestroyTexture(sdl_texture);
		sdl_texture = NULL;
	}

	if (sdl_renderer) {
		SDL_DestroyRenderer(sdl_renderer);
		sdl_renderer = NULL;
	}

	if (sdl_window) {
		SDL_DestroyWindow(sdl_window);
		sdl_window = NULL;
	}

	SDL_Quit();
#endif
}

/*
 * Main thread event loop for SDL3/Cocoa
 * This function runs on the TRUE main thread and never returns
 * Worker threads communicate via dispatch_sync()
 */
void
sdl3_mainloop(void)
{
	SDL_Event event;
	static Uint64 last_refresh = 0;
	Uint64 now;

	/* Event loop - processes SDL events and sends to Infernode */
	for(;;) {
		/*
		 * BATCHED TEXTURE UPDATE AND PRESENTATION
		 *
		 * This is the ONLY place where SDL texture/render operations happen.
		 * flushmemscreen() just accumulates dirty rectangles with no sync.
		 * We batch all updates into a single GPU upload per frame (~60Hz).
		 *
		 * This eliminates the massive dispatch_sync overhead that was
		 * causing multi-second delays for directory listings.
		 */
		now = SDL_GetTicks();
		if (sdl_running && sdl_renderer && sdl_texture && screen_data) {
			/*
			 * Update and present if:
			 * 1. Dirty regions accumulated (dirty_pending), OR
			 * 2. 250ms elapsed (keep display fresh, prevent macOS idle optimizations)
			 */
			if (dirty_pending || (now - last_refresh > 250)) {
				if (dirty_pending) {
					/*
					 * Upload the accumulated dirty region to GPU texture.
					 * This is the ONLY SDL_UpdateTexture call per frame.
					 */
					SDL_Rect dirty;
					uchar *src;
					int pitch;

					dirty.x = dirty_min_x;
					dirty.y = dirty_min_y;
					dirty.w = dirty_max_x - dirty_min_x;
					dirty.h = dirty_max_y - dirty_min_y;

					pitch = sdl_width * 4;
					src = screen_data + (dirty_min_y * pitch) + (dirty_min_x * 4);

					SDL_UpdateTexture(sdl_texture, &dirty, src, pitch);
					dirty_pending = 0;
				}

				SDL_SetRenderDrawColor(sdl_renderer, 0, 0, 0, 255);
				SDL_RenderClear(sdl_renderer);
				SDL_RenderTexture(sdl_renderer, sdl_texture, NULL, &dest_rect);
				SDL_RenderPresent(sdl_renderer);
				last_refresh = now;
			}
		}

		/* Poll for events (non-blocking) */
		while (SDL_PollEvent(&event)) {
			switch (event.type) {
			case SDL_EVENT_QUIT:
				cleanexit(0);
				break;

			case SDL_EVENT_MOUSE_MOTION:
				window_to_texture_coords(event.motion.x, event.motion.y, &mouse_x, &mouse_y);
				mousetrack(map_buttons(sdl_button_state), mouse_x, mouse_y, 0);
				break;

			case SDL_EVENT_MOUSE_BUTTON_DOWN:
			case SDL_EVENT_MOUSE_BUTTON_UP:
				{
					Uint32 mask = button_event_mask(event.button.button);
					if (event.type == SDL_EVENT_MOUSE_BUTTON_DOWN)
						sdl_button_state |= mask;
					else
						sdl_button_state &= ~mask;

					window_to_texture_coords(event.button.x, event.button.y, &mouse_x, &mouse_y);
					mousetrack(map_buttons(sdl_button_state), mouse_x, mouse_y, 0);
				}
				break;

			case SDL_EVENT_MOUSE_WHEEL:
				/* Scroll wheel as buttons 4 & 5 - use tracked mouse position */
				if (event.wheel.y > 0)
					mousetrack(8, mouse_x, mouse_y, 0);   /* scroll up = button 4 */
				else if (event.wheel.y < 0)
					mousetrack(16, mouse_x, mouse_y, 0);  /* scroll down = button 5 */
				break;

			case SDL_EVENT_TEXT_INPUT:
				/*
				 * Text input event - receives actual characters with modifiers applied.
				 * This handles shift, caps lock, keyboard layout, and Option+key
				 * combinations (e.g., Option+t → †) properly.
				 * event.text.text is a UTF-8 string.
				 *
				 * macOS Option+key composition is handled here - the OS composes
				 * the character and sends it via TEXT_INPUT.
				 *
				 * Plan 9 composition is separate: Alt release sends Latin to
				 * enter compose mode, then regular keypresses compose.
				 *
				 * Skip control characters (< 0x20) - those are handled in KEY_DOWN
				 * via Ctrl+letter detection.
				 */
				{
					const unsigned char *text = (const unsigned char *)event.text.text;

					/* Skip control characters - handled by Ctrl+letter in KEY_DOWN */
					if (text[0] < 0x20 && text[0] != '\t')
						break;
					while (*text) {
						int codepoint;
						int bytes;

						/* Decode UTF-8 to Unicode codepoint */
						if ((*text & 0x80) == 0) {
							/* 1-byte ASCII: 0xxxxxxx */
							codepoint = *text;
							bytes = 1;
						} else if ((*text & 0xE0) == 0xC0) {
							/* 2-byte: 110xxxxx 10xxxxxx */
							if ((text[1] & 0xC0) != 0x80)
								goto skip_mainloop;
							codepoint = ((*text & 0x1F) << 6) |
							            (text[1] & 0x3F);
							bytes = 2;
						} else if ((*text & 0xF0) == 0xE0) {
							/* 3-byte: 1110xxxx 10xxxxxx 10xxxxxx */
							if ((text[1] & 0xC0) != 0x80 ||
							    (text[2] & 0xC0) != 0x80)
								goto skip_mainloop;
							codepoint = ((*text & 0x0F) << 12) |
							            ((text[1] & 0x3F) << 6) |
							            (text[2] & 0x3F);
							bytes = 3;
						} else if ((*text & 0xF8) == 0xF0) {
							/* 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx */
							if ((text[1] & 0xC0) != 0x80 ||
							    (text[2] & 0xC0) != 0x80 ||
							    (text[3] & 0xC0) != 0x80)
								goto skip_mainloop;
							codepoint = ((*text & 0x07) << 18) |
							            ((text[1] & 0x3F) << 12) |
							            ((text[2] & 0x3F) << 6) |
							            (text[3] & 0x3F);
							bytes = 4;
						} else {
						skip_mainloop:
							/* Invalid UTF-8, skip byte */
							text++;
							continue;
						}

						gkbdputc(gkbdq, codepoint);
						text += bytes;
					}
				}
				break;

			case SDL_EVENT_KEY_DOWN:
				{
					int key = 0;
					/*
					 * Use event.key.mod (modifier state at event time)
					 * instead of SDL_GetModState() (current state).
					 */
					SDL_Keymod mods = event.key.mod;
					/*
					 * Use the virtual keycode (event.key.key), not scancode.
					 * Scancodes are physical positions and vary by keyboard.
					 * Keycodes are logical keys: SDLK_a='a'=97, SDLK_h='h'=104, etc.
					 */
					SDL_Keycode kc = event.key.key;

					/*
					 * Handle Ctrl+letter -> control character (^A=1, ^H=8, etc.)
					 * These don't generate TEXT_INPUT events, so handle here.
					 * Use lowercase keycode range ('a' to 'z').
					 */
					if ((mods & SDL_KMOD_CTRL) && kc >= 'a' && kc <= 'z') {
						key = kc - 'a' + 1;  /* 'a'->1, 'h'->8, etc. */
					}

					/*
					 * Handle special/non-printable keys only.
					 * Printable characters come via SDL_EVENT_TEXT_INPUT.
					 * macOS Option+key composition also uses TEXT_INPUT.
					 */
					if (key == 0)
					switch (event.key.scancode) {
					case SDL_SCANCODE_ESCAPE:   key = 27; break;
					case SDL_SCANCODE_RETURN:   key = '\n'; break;
					case SDL_SCANCODE_KP_ENTER: key = '\n'; break;
					case SDL_SCANCODE_TAB:      key = '\t'; break;
					case SDL_SCANCODE_BACKSPACE: key = '\b'; break;
					case SDL_SCANCODE_DELETE:   key = 0x7F; break;
					case SDL_SCANCODE_UP:       key = Up; break;
					case SDL_SCANCODE_DOWN:     key = Down; break;
					case SDL_SCANCODE_LEFT:     key = Left; break;
					case SDL_SCANCODE_RIGHT:    key = Right; break;
					case SDL_SCANCODE_HOME:     key = Home; break;
					case SDL_SCANCODE_END:      key = End; break;
					case SDL_SCANCODE_PAGEUP:   key = Pgup; break;
					case SDL_SCANCODE_PAGEDOWN: key = Pgdown; break;
					case SDL_SCANCODE_INSERT:   key = Ins; break;
					case SDL_SCANCODE_F1:       key = KF|1; break;
					case SDL_SCANCODE_F2:       key = KF|2; break;
					case SDL_SCANCODE_F3:       key = KF|3; break;
					case SDL_SCANCODE_F4:       key = KF|4; break;
					case SDL_SCANCODE_F5:       key = KF|5; break;
					case SDL_SCANCODE_F6:       key = KF|6; break;
					case SDL_SCANCODE_F7:       key = KF|7; break;
					case SDL_SCANCODE_F8:       key = KF|8; break;
					case SDL_SCANCODE_F9:       key = KF|9; break;
					case SDL_SCANCODE_F10:      key = KF|10; break;
					case SDL_SCANCODE_F11:      key = KF|11; break;
					case SDL_SCANCODE_F12:      key = KF|12; break;
					default:
						break;  /* Printable chars handled by TEXT_INPUT */
					}

					if (key != 0)
						gkbdputc(gkbdq, key);
				}
				break;

			case SDL_EVENT_KEY_UP:
				/*
				 * Plan 9 latin1 composition: Alt/Option release sends Latin
				 * to enter compose mode. User then types two characters
				 * (without Alt held) to produce a composed glyph.
				 *
				 * This is separate from macOS composition where you HOLD
				 * Option and press a key (handled via TEXT_INPUT).
				 */
				if (event.key.scancode == SDL_SCANCODE_LALT ||
				    event.key.scancode == SDL_SCANCODE_RALT) {
					gkbdputc(gkbdq, Latin);
				}
				break;
			}
		}

		/* Brief sleep to avoid busy-wait */
		SDL_Delay(16);  /* ~60Hz */
	}

	/* Never reached */
}
