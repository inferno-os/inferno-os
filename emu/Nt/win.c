#define Unknown win_Unknown
#include	<windows.h>
#undef Unknown
#include	"dat.h"
#include	"fns.h"
#include	"error.h"

#include	"keyboard.h"
#include	"cursor.h"

/*
 * image channel descriptors - copied from draw.h as it clashes with windows.h on many things
 */
enum {
	CRed = 0,
	CGreen,
	CBlue,
	CGrey,
	CAlpha,
	CMap,
	CIgnore,
	NChan,
};

#define __DC(type, nbits)	((((type)&15)<<4)|((nbits)&15))
#define CHAN1(a,b)	__DC(a,b)
#define CHAN2(a,b,c,d)	(CHAN1((a),(b))<<8|__DC((c),(d)))
#define CHAN3(a,b,c,d,e,f)	(CHAN2((a),(b),(c),(d))<<8|__DC((e),(f)))
#define CHAN4(a,b,c,d,e,f,g,h)	(CHAN3((a),(b),(c),(d),(e),(f))<<8|__DC((g),(h)))

#define NBITS(c) ((c)&15)
#define TYPE(c) (((c)>>4)&15)

enum {
	GREY1	= CHAN1(CGrey, 1),
	GREY2	= CHAN1(CGrey, 2),
	GREY4	= CHAN1(CGrey, 4),
	GREY8	= CHAN1(CGrey, 8),
	CMAP8	= CHAN1(CMap, 8),
	RGB15	= CHAN4(CIgnore, 1, CRed, 5, CGreen, 5, CBlue, 5),
	RGB16	= CHAN3(CRed, 5, CGreen, 6, CBlue, 5),
	RGB24	= CHAN3(CRed, 8, CGreen, 8, CBlue, 8),
	RGBA32	= CHAN4(CRed, 8, CGreen, 8, CBlue, 8, CAlpha, 8),
	ARGB32	= CHAN4(CAlpha, 8, CRed, 8, CGreen, 8, CBlue, 8),	/* stupid VGAs */
	XRGB32  = CHAN4(CIgnore, 8, CRed, 8, CGreen, 8, CBlue, 8),
};

extern ulong displaychan;

extern void drawend(void);

/*
 * defs for image types to overcome name conflicts
 */
typedef struct IPoint		IPoint;
typedef struct IRectangle	IRectangle;

struct IPoint
{
	LONG	x;
	LONG	y;
};

struct IRectangle
{
	IPoint	min;
	IPoint	max;
};

extern	char*	runestoutf(char*, Rune*, int);
extern	int	bytesperline(IRectangle, int);
extern	int	main(int argc, char **argv);
static	void	dprint(char*, ...);
static	DWORD WINAPI	winproc(LPVOID);

static	HINSTANCE	inst;
static	HINSTANCE	previnst;
static	int		cmdshow;
static	HWND		window;
static	HDC		screen;
static	HPALETTE	palette;
static	int		maxxsize;
static	int		maxysize;
static	int		attached;
static	int		isunicode = 1;
static	HCURSOR		hcursor;

static	char	*argv0 = "inferno";
static	ulong	*data;

extern	DWORD	PlatformId;
char*	gkscanid = "emu_win32vk";

int WINAPI
WinMain(HINSTANCE winst, HINSTANCE wprevinst, LPSTR cmdline, int wcmdshow)
{
	inst = winst;
	previnst = wprevinst;
	cmdshow = wcmdshow;

	/* cmdline passed into WinMain does not contain name of executable.
	 * The globals __argc and __argv to include this info - like UNIX
	 */
	main(__argc, __argv);
	return 0;
}

void
dprint(char *fmt, ...)
{
	va_list arg;
	char buf[128];

	va_start(arg, fmt);
	vseprint(buf, buf+sizeof(buf), fmt, (LPSTR)arg);
	va_end(arg);
	OutputDebugString("inferno: ");
	OutputDebugString(buf);
}

int
col(int v, int n)
{
	int i, c;

	c = 0;
	for(i = 0; i < 8; i += n)
		c |= v << (16-(n+i));
	return c >> 8;
}

static void
graphicscmap(PALETTEENTRY *pal)
{
	int r, g, b, cr, cg, cb, v, p;
	int num, den;
	int i, j;
	for(r=0,i=0;r!=4;r++) for(v=0;v!=4;v++,i+=16){
		for(g=0,j=v-r;g!=4;g++) for(b=0;b!=4;b++,j++){
			den=r;
			if(g>den) den=g;
			if(b>den) den=b;
			if(den==0)	/* divide check -- pick grey shades */
				cr=cg=cb=v*17;
			else{
				num=17*(4*den+v);
				cr=r*num/den;
				cg=g*num/den;
				cb=b*num/den;
			}
			p = i+(j&15);
			pal[p].peRed = cr*0x01010101;
			pal[p].peGreen = cg*0x01010101;
			pal[p].peBlue = cb*0x01010101;
			pal[p].peFlags = 0;
		}
	}
}

static void
graphicsgmap(PALETTEENTRY *pal, int d)
{
	int i, j, s, m, p;

	s = 8-d;
	m = 1;
	while(--d >= 0)
		m *= 2;
	m = 255/(m-1);
	for(i=0; i < 256; i++){
		j = (i>>s)*m;
		p = 255-i;
		pal[p].peRed = pal[p].peGreen = pal[p].peBlue = (255-j)*0x01010101;
		pal[p].peFlags = 0;
	}
}

static ulong
autochan(void)
{
	HDC dc;
	int bpp;

	dc = GetDC(NULL);
	if (dc == NULL)
		return CMAP8;

	bpp = GetDeviceCaps(dc, BITSPIXEL);
	if (bpp < 15)
		return CMAP8;
	if (bpp < 24)
		return RGB15;
	return RGB24;
}

uchar*
attachscreen(IRectangle *r, ulong *chan, int *d, int *width, int *softscreen)
{
	int i, k;
	ulong c;
	DWORD h;
	RECT bs;
	RGBQUAD *rgb;
	HBITMAP bits;
	BITMAPINFO *bmi;
	LOGPALETTE *logpal;
	PALETTEENTRY *pal;
	int bsh, bsw, sx, sy;

	if(attached)
		goto Return;

	/* Compute bodersizes */
	memset(&bs, 0, sizeof(bs));
	AdjustWindowRect(&bs, WS_OVERLAPPEDWINDOW, 0);
	bsw = bs.right - bs.left;
	bsh = bs.bottom - bs.top;
	sx = GetSystemMetrics(SM_CXFULLSCREEN) - bsw;
	Xsize -= Xsize % 4;	/* Round down */
	if(Xsize > sx)
		Xsize = sx;
	sy = GetSystemMetrics(SM_CYFULLSCREEN) - bsh + 20;
	if(Ysize > sy)
		Ysize = sy;

	logpal = malloc(sizeof(LOGPALETTE) + 256*sizeof(PALETTEENTRY));
	if(logpal == nil)
		return nil;
	logpal->palVersion = 0x300;
	logpal->palNumEntries = 256;
	pal = logpal->palPalEntry;

	c = displaychan;
	if(c == 0)
		c = autochan();
	k = 8;
	if(TYPE(c) == CGrey){
		graphicsgmap(pal, NBITS(c));
		c = GREY8;
	}else{
		if(c == RGB15)
			k = 16;
		else if(c == RGB24)
			k = 24;
		else if(c == XRGB32)
			k = 32;
		else
			c = CMAP8;
		graphicscmap(pal);
	}

	palette = CreatePalette(logpal);

	if(k == 8)
		bmi = malloc(sizeof(BITMAPINFOHEADER) + 256*sizeof(RGBQUAD));
	else
		bmi = malloc(sizeof(BITMAPINFOHEADER));
	if(bmi == nil)
		return nil;
	bmi->bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
	bmi->bmiHeader.biWidth = Xsize;
	bmi->bmiHeader.biHeight = -Ysize;	/* - => origin upper left */
	bmi->bmiHeader.biPlanes = 1;	/* always 1 */
	bmi->bmiHeader.biBitCount = k;
	bmi->bmiHeader.biCompression = BI_RGB;
	bmi->bmiHeader.biSizeImage = 0;	/* Xsize*Ysize*(k/8) */
	bmi->bmiHeader.biXPelsPerMeter = 0;
	bmi->bmiHeader.biYPelsPerMeter = 0;
	bmi->bmiHeader.biClrUsed = 0;
	bmi->bmiHeader.biClrImportant = 0;	/* number of important colors: 0 means all */

	if(k == 8){
		rgb = bmi->bmiColors;
		for(i = 0; i < 256; i++){
			rgb[i].rgbRed = pal[i].peRed;
			rgb[i].rgbGreen = pal[i].peGreen;
			rgb[i].rgbBlue = pal[i].peBlue;
		}
	}

	screen = CreateCompatibleDC(NULL);
	if(screen == nil){
		fprint(2, "screen dc nil\n");
		return nil;
	}

	if(SelectPalette(screen, palette, 1) == nil){
		fprint(2, "select pallete failed\n");
	}
	i = RealizePalette(screen);
	GdiFlush();
	bits = CreateDIBSection(screen, bmi, DIB_RGB_COLORS, &data, nil, 0);
	if(bits == nil){
		fprint(2, "CreateDIBSection failed\n");
		return nil;
	}

	SelectObject(screen, bits);
	GdiFlush();
	CreateThread(0, 16384, winproc, nil, 0, &h);
	attached = 1;

    Return:
	r->min.x = 0;
	r->min.y = 0;
	r->max.x = Xsize;
	r->max.y = Ysize;
	displaychan = c;
	*chan = c;
	*d = k;
	*width = (Xsize/4)*(k/8);
	*softscreen = 1;
	return (uchar*)data;
}

void
flushmemscreen(IRectangle r)
{
	RECT wr;

	if(r.max.x<=r.min.x || r.max.y<=r.min.y)
		return;
	wr.left = r.min.x;
	wr.top = r.min.y;
	wr.right = r.max.x;
	wr.bottom = r.max.y;
	InvalidateRect(window, &wr, 0);
}

static void
scancode(WPARAM wparam, LPARAM lparam, int keyup)
{
	uchar buf[2];

	if(!(lparam & (1<<30))) {		/* don't auto-repeat chars */
		buf[0] = wparam;
		buf[1] = wparam >> 8;
		if (keyup)
			buf[1] |= 0x80;
		qproduce(gkscanq, buf, sizeof buf);
	}
}

LRESULT CALLBACK
WindowProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
	PAINTSTRUCT paint;
	HDC hdc;
	LPMINMAXINFO mmi;
	LONG x, y, w, h, b;
	HCURSOR dcurs;

	switch(msg) {
	case WM_SETCURSOR:
		/* User set */
		if(hcursor != NULL) {
			SetCursor(hcursor);
			break;
		}
		/* Pick the default */
		dcurs = LoadCursor(NULL, IDC_ARROW);
		SetCursor(dcurs);
		break;
	case WM_LBUTTONDBLCLK:
		b = (1<<8) | 1;
		goto process;
	case WM_MBUTTONDBLCLK:
		b = (1<<8) | 2;
		goto process;
	case WM_RBUTTONDBLCLK:
		b = (1<<8) | 4;
		goto process;
	case WM_MOUSEMOVE:
	case WM_LBUTTONUP:
	case WM_MBUTTONUP:
	case WM_RBUTTONUP:
	case WM_LBUTTONDOWN:
	case WM_MBUTTONDOWN:
	case WM_RBUTTONDOWN:
		b = 0;
	process:
		x = LOWORD(lparam);
		y = HIWORD(lparam);
		if(wparam & MK_LBUTTON)
			b |= 1;
		if(wparam & MK_MBUTTON)
			b |= 2;
		if(wparam & MK_RBUTTON)
			if(wparam & MK_CONTROL)
				b |= 2;  //simulate middle button
			else
				b |= 4;  //right button
		mousetrack(b, x, y, 0);
		break;
	case WM_SYSKEYDOWN:
		if(gkscanq)
			scancode(wparam, lparam, 0);
		break;
	case WM_SYSKEYUP:
		if(gkscanq)
			scancode(wparam, lparam, 1);
		else if(wparam == VK_MENU)
			gkbdputc(gkbdq, Latin);
		break;
	case WM_KEYDOWN:
		if(gkscanq) {
			scancode(wparam, lparam, 0);
			break;
		}
		switch(wparam) {
		default:
			return 0;
		case VK_HOME:
			wparam = Home;
			break;
		case VK_END:
			wparam = End;
			break;
		case VK_UP:
			wparam = Up;
			break;
		case VK_DOWN:
			wparam = Down;
			break;
		case VK_LEFT:
			wparam = Left;
			break;
		case VK_RIGHT:
			wparam = Right;
			break;
		case VK_PRIOR:	/* VK_PAGE_UP */
			wparam = Pgup;
			break;
		case VK_NEXT:		/* VK_PAGE_DOWN */
			wparam = Pgdown;
			break;
		case VK_PRINT:
			wparam = Print;
			break;
		case VK_SCROLL:
			wparam = Scroll;
			break;
		case VK_PAUSE:
			wparam = Pause;
			break;
		case VK_INSERT:
			wparam = Ins;
			break;
		case VK_DELETE:
			wparam = Del;
			break;
/*
		case VK_TAB:
			if(GetKeyState(VK_SHIFT)<0)
				wparam = BackTab;
			else
				wparam = '\t';
			break;
*/
		}
		gkbdputc(gkbdq, wparam);
		break;
	case WM_KEYUP:
		if(gkscanq)
			scancode(wparam, lparam, 1);
		break;
	case WM_CHAR:
		if(gkscanq)
			break;
		switch(wparam) {
		case '\n':
		  	wparam = '\r';
		  	break;
		case '\r':
		  	wparam = '\n';
		  	break;
		case '\t':
			if(GetKeyState(VK_SHIFT)<0)
				wparam = BackTab;
			else
				wparam = '\t';
			break;
		}
		if(lparam & KF_ALTDOWN) 
		    	wparam = APP | (wparam & 0xFF);
		gkbdputc(gkbdq, wparam);
		break;
	case WM_CLOSE:
		// no longer used?
		//m.b = 128;
		//m.modify = 1;
		//mousetrack(128, 0, 0, 1);
		DestroyWindow(hwnd);
		break;
	case WM_DESTROY:
		PostQuitMessage(0);
		cleanexit(0);
		break;
	case WM_PALETTECHANGED:
		if((HWND)wparam == hwnd)
			break;
	/* fall through */
	case WM_QUERYNEWPALETTE:
		hdc = GetDC(hwnd);
		SelectPalette(hdc, palette, 0);
		if(RealizePalette(hdc) != 0)
			InvalidateRect(hwnd, nil, 0);
		ReleaseDC(hwnd, hdc);
		break;
	case WM_PAINT:
		hdc = BeginPaint(hwnd, &paint);
		SelectPalette(hdc, palette, 0);
		RealizePalette(hdc);
		x = paint.rcPaint.left;
		y = paint.rcPaint.top;
		w = paint.rcPaint.right - x;
		h = paint.rcPaint.bottom - y;
		BitBlt(hdc, x, y, w, h, screen, x, y, SRCCOPY);
		EndPaint(hwnd, &paint);
		break;
	case WM_GETMINMAXINFO:
		mmi = (LPMINMAXINFO)lparam;
		mmi->ptMaxSize.x = maxxsize;
		mmi->ptMaxSize.y = maxysize;
		mmi->ptMaxTrackSize.x = maxxsize;
		mmi->ptMaxTrackSize.y = maxysize;
		break;
	case WM_SYSCHAR:
	case WM_COMMAND:
	case WM_CREATE:
	case WM_SETFOCUS:
	case WM_DEVMODECHANGE:
	case WM_WININICHANGE:
	case WM_INITMENU:
	default:
		if(isunicode)
			return DefWindowProcW(hwnd, msg, wparam, lparam);
		return DefWindowProcA(hwnd, msg, wparam, lparam);
	}
	return 0;
}

static DWORD WINAPI
winproc(LPVOID x)
{
	MSG msg;
	RECT size;
	WNDCLASSW wc;
	WNDCLASSA wca;
	DWORD ws;

	if(!previnst){
		wc.style = CS_DBLCLKS;
		wc.lpfnWndProc = WindowProc;
		wc.cbClsExtra = 0;
		wc.cbWndExtra = 0;
		wc.hInstance = inst;
		wc.hIcon = LoadIcon(inst, MAKEINTRESOURCE(100));
		wc.hCursor = NULL;
		wc.hbrBackground = GetStockObject(WHITE_BRUSH);

		wc.lpszMenuName = 0;
		wc.lpszClassName = L"inferno";

		if(RegisterClassW(&wc) == 0){
			wca.style = wc.style;
			wca.lpfnWndProc = wc.lpfnWndProc;
			wca.cbClsExtra = wc.cbClsExtra;
			wca.cbWndExtra = wc.cbWndExtra;
			wca.hInstance = wc.hInstance;
			wca.hIcon = wc.hIcon;
			wca.hCursor = wc.hCursor;
			wca.hbrBackground = wc.hbrBackground;

			wca.lpszMenuName = 0;
			wca.lpszClassName = "inferno";
			isunicode = 0;

			RegisterClassA(&wca);
		}
	}

	size.left = 0;
	size.top = 0;
	size.right = Xsize;
	size.bottom = Ysize;

	ws = WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX;

	if(AdjustWindowRect(&size, ws, 0)) {
		maxxsize = size.right - size.left;
		maxysize = size.bottom - size.top;
	}
	else {
		maxxsize = Xsize + 40;
		maxysize = Ysize + 40;
	}

	if(isunicode) {
		window = CreateWindowExW(
			0,			/* extended style */
			L"inferno",		/* class */
			L"Inferno",		/* caption */
			ws,	/* style */
			CW_USEDEFAULT,		/* init. x pos */
			CW_USEDEFAULT,		/* init. y pos */
			maxxsize,		/* init. x size */
			maxysize,		/* init. y size */
			NULL,			/* parent window (actually owner window for overlapped) */
			NULL,			/* menu handle */
			inst,			/* program handle */
			NULL			/* create parms */
			);
	}
	else {
		window = CreateWindowExA(
			0,			/* extended style */
			"inferno",		/* class */
			"Inferno",		/* caption */
			ws,	/* style */
			CW_USEDEFAULT,		/* init. x pos */
			CW_USEDEFAULT,		/* init. y pos */
			maxxsize,		/* init. x size */
			maxysize,		/* init. y size */
			NULL,			/* parent window (actually owner window for overlapped) */
			NULL,			/* menu handle */
			inst,			/* program handle */
			NULL			/* create parms */
			);
	}

	if(window == nil){
		fprint(2, "can't make window\n");
		ExitThread(0);
	}

	SetForegroundWindow(window);
	ShowWindow(window, cmdshow);
	UpdateWindow(window);
	// CloseWindow(window);

	if(isunicode) {
		while(GetMessageW(&msg, NULL, 0, 0)) {
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
		}
	}
	else {
		while(GetMessageA(&msg, NULL, 0, 0)) {
			TranslateMessage(&msg);
			DispatchMessageA(&msg);
		}
	}
	attached = 0;
	/* drawend(); */
	ExitThread(msg.wParam);
	return 0;
}

void
setpointer(int x, int y)
{
	POINT pt; 
 
	pt.x = x; pt.y = y;
	ClientToScreen(window, (LPPOINT)&pt);
	SetCursorPos(pt.x, pt.y);
}

void
drawcursor(Drawcursor* c)
{
	HCURSOR nh, oh;
	IRectangle ir;
	int i, h, j, bpl, ch, cw;
	uchar *bs, *bc, *and, *xor, *cand, *cxor;

	/* Set the default system cursor */
	if(c->data == nil) {
		oh = hcursor;
		hcursor = NULL;
		if(oh != NULL) {
			SendMessage(window, WM_SETCURSOR, (int)window, 0);
			DestroyCursor(oh);
		}
		return;
	}

	ir.min.x = c->minx;
	ir.min.y = c->miny;
	ir.max.x = c->maxx;
	ir.max.y = c->maxy;
	/* passing IRectangle to Rectangle is safe */
	bpl = bytesperline(ir, 1);

	h = (c->maxy-c->miny)/2;

	ch = GetSystemMetrics(SM_CYCURSOR);
	cw = (GetSystemMetrics(SM_CXCURSOR)+7)/8;

	i = ch*cw;
	and = malloc(2*i);
	if(and == nil)
		return;
	xor = and + i;
	memset(and, 0xff, i);
	memset(xor, 0, i);

	cand = and;
	cxor = xor;
	bc = c->data;
	bs = c->data + h*bpl;	

	for(i = 0; i < ch && i < h; i++) {
		for(j = 0; j < cw && j < bpl; j++) {
			cand[j] = ~(bs[j] | bc[j]);
			cxor[j] = ~bs[j] & bc[j];
		}
		cand += cw;
		cxor += cw;
		bs += bpl;
		bc += bpl;
	}
	nh = CreateCursor(inst, -c->hotx, -c->hoty, 8*cw, ch, and, xor);
	if(nh != NULL) {
		oh = hcursor;
		hcursor = nh;
		SendMessage(window, WM_SETCURSOR, (int)window, 0);
		if(oh != NULL)
			DestroyCursor(oh);
	}
	else {
		print("CreateCursor error %d\n", GetLastError());
		print("CXCURSOR=%d\n", GetSystemMetrics(SM_CXCURSOR));
		print("CYCURSOR=%d\n", GetSystemMetrics(SM_CYCURSOR));
	}
	free(and);
}

/*
 * thanks to drawterm for these
 */

static char*
clipreadunicode(HANDLE h)
{
	Rune *p;
	int n;
	char *q;
	
	p = GlobalLock(h);
	n = runenlen(p, runestrlen(p)+1);
	q = malloc(n);
	if(q != nil)
		runestoutf(q, p, n);
	GlobalUnlock(h);

	if(q == nil)
		error(Enovmem);
	return q;
}

static char *
clipreadutf(HANDLE h)
{
	uchar *p;

	p = GlobalLock(h);
	p = strdup(p);
	GlobalUnlock(h);

	if(p == nil)
		error(Enovmem);
	return p;
}

char*
clipread(void)
{
	HANDLE h;
	char *p;

	if(!OpenClipboard(window))
		return strdup("");

	if((h = GetClipboardData(CF_UNICODETEXT)))
		p = clipreadunicode(h);
	else if((h = GetClipboardData(CF_TEXT)))
		p = clipreadutf(h);
	else
		p = strdup("");
	
	CloseClipboard();
	return p;
}

int
clipwrite(char *buf)
{
	HANDLE h;
	char *p, *e;
	Rune *rp;
	int n;

	n = 0;
	if(buf != nil)
		n = strlen(buf);
	if(!OpenClipboard(window))
		return -1;

	if(!EmptyClipboard()){
		CloseClipboard();
		return -1;
	}

	h = GlobalAlloc(GMEM_MOVEABLE|GMEM_DDESHARE, (n+1)*sizeof(Rune));
	if(h == NULL)
		error(Enovmem);
	rp = GlobalLock(h);
	p = buf;
	e = p+n;
	while(p<e)
		p += chartorune(rp++, p);
	*rp = 0;
	GlobalUnlock(h);

	SetClipboardData(CF_UNICODETEXT, h);

	h = GlobalAlloc(GMEM_MOVEABLE|GMEM_DDESHARE, n+1);
	if(h == NULL)
		error(Enovmem);
	p = GlobalLock(h);
	memmove(p, buf, n);
	p[n] = 0;
	GlobalUnlock(h);
	
	SetClipboardData(CF_TEXT, h);

	CloseClipboard();
	return n;
}
