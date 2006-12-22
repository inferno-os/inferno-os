typedef struct Sys_Qid Sys_Qid;
typedef struct Sys_Dir Sys_Dir;
typedef struct Sys_FD Sys_FD;
typedef struct Sys_Connection Sys_Connection;
typedef struct Sys_FileIO Sys_FileIO;
typedef struct Draw_Point Draw_Point;
typedef struct Draw_Rect Draw_Rect;
typedef struct Draw_Image Draw_Image;
typedef struct Draw_Font Draw_Font;
typedef struct Draw_Display Draw_Display;
typedef struct Draw_Screen Draw_Screen;
typedef struct Draw_Pointer Draw_Pointer;
typedef struct Draw_Context Draw_Context;
typedef struct Prefab_Style Prefab_Style;
typedef struct Prefab_Environ Prefab_Environ;
typedef struct Prefab_Layout Prefab_Layout;
typedef struct Prefab_Element Prefab_Element;
typedef struct Prefab_Compound Prefab_Compound;
typedef struct Tk_Toplevel Tk_Toplevel;
typedef struct Keyring_SigAlg Keyring_SigAlg;
typedef struct Keyring_PK Keyring_PK;
typedef struct Keyring_SK Keyring_SK;
typedef struct Keyring_Certificate Keyring_Certificate;
typedef struct Keyring_DigestState Keyring_DigestState;
struct Sys_Qid
{
	WORD	path;
	WORD	vers;
};
#define Sys_Qid_size 8
#define Sys_Qid_map {0}
struct Sys_Dir
{
	String*	name;
	String*	uid;
	String*	gid;
	Sys_Qid	qid;
	WORD	mode;
	WORD	atime;
	WORD	mtime;
	WORD	length;
	WORD	dtype;
	WORD	dev;
};
#define Sys_Dir_size 44
#define Sys_Dir_map {0xe0,}
struct Sys_FD
{
	WORD	fd;
};
#define Sys_FD_size 4
#define Sys_FD_map {0}
struct Sys_Connection
{
	Sys_FD*	dfd;
	Sys_FD*	cfd;
	String*	dir;
};
#define Sys_Connection_size 12
#define Sys_Connection_map {0xe0,}
struct Sys_FileIO
{
	Channel*	rd_req;
	Channel*	rd_rep;
	Channel*	wr_req;
	Channel*	wr_rep;
};
typedef struct{ WORD t0; WORD t1; WORD t2; } Sys_FileIO_rd_req;
#define Sys_FileIO_rd_req_size 12
#define Sys_FileIO_rd_req_map {0}
typedef struct{ Array* t0; String* t1; } Sys_FileIO_rd_rep;
#define Sys_FileIO_rd_rep_size 8
#define Sys_FileIO_rd_rep_map {0xc0,}
typedef struct{ WORD t0; Array* t1; WORD t2; } Sys_FileIO_wr_req;
#define Sys_FileIO_wr_req_size 12
#define Sys_FileIO_wr_req_map {0x40,}
typedef struct{ WORD t0; String* t1; } Sys_FileIO_wr_rep;
#define Sys_FileIO_wr_rep_size 8
#define Sys_FileIO_wr_rep_map {0x40,}
#define Sys_FileIO_size 16
#define Sys_FileIO_map {0xf0,}
struct Draw_Point
{
	WORD	x;
	WORD	y;
};
#define Draw_Point_size 8
#define Draw_Point_map {0}
struct Draw_Rect
{
	Draw_Point	min;
	Draw_Point	max;
};
#define Draw_Rect_size 16
#define Draw_Rect_map {0}
struct Draw_Image
{
	Draw_Rect	r;
	Draw_Rect	clipr;
	WORD	ldepth;
	WORD	repl;
};
#define Draw_Image_size 40
#define Draw_Image_map {0}
struct Draw_Font
{
	String*	name;
	WORD	height;
	WORD	ascent;
};
#define Draw_Font_size 12
#define Draw_Font_map {0x80,}
struct Draw_Display
{
	Draw_Image*	image;
	Draw_Image*	ones;
	Draw_Image*	zeros;
};
#define Draw_Display_size 12
#define Draw_Display_map {0xe0,}
struct Draw_Screen
{
	WORD	id;
	Draw_Image*	image;
	Draw_Image*	fill;
};
#define Draw_Screen_size 12
#define Draw_Screen_map {0x60,}
struct Draw_Pointer
{
	WORD	buttons;
	Draw_Point	xy;
};
#define Draw_Pointer_size 12
#define Draw_Pointer_map {0}
struct Draw_Context
{
	Draw_Screen*	screen;
	Draw_Display*	display;
	Channel*	cir;
	Channel*	ckbd;
	Channel*	cptr;
	Channel*	ctoappl;
	Channel*	ctomux;
};
typedef WORD Draw_Context_cir;
#define Draw_Context_cir_size 4
#define Draw_Context_cir_map {0}
typedef WORD Draw_Context_ckbd;
#define Draw_Context_ckbd_size 4
#define Draw_Context_ckbd_map {0}
typedef Draw_Pointer* Draw_Context_cptr;
#define Draw_Context_cptr_size 4
#define Draw_Context_cptr_map {0x80,}
typedef WORD Draw_Context_ctoappl;
#define Draw_Context_ctoappl_size 4
#define Draw_Context_ctoappl_map {0}
typedef WORD Draw_Context_ctomux;
#define Draw_Context_ctomux_size 4
#define Draw_Context_ctomux_map {0}
#define Draw_Context_size 28
#define Draw_Context_map {0xfe,}
struct Prefab_Style
{
	Draw_Font*	titlefont;
	Draw_Font*	textfont;
	Draw_Image*	screencolor;
	Draw_Image*	elemcolor;
	Draw_Image*	edgecolor;
	Draw_Image*	titlecolor;
	Draw_Image*	textcolor;
	Draw_Image*	highlightcolor;
};
#define Prefab_Style_size 32
#define Prefab_Style_map {0xff,}
struct Prefab_Environ
{
	Draw_Screen*	screen;
	Prefab_Style*	style;
};
#define Prefab_Environ_size 8
#define Prefab_Environ_map {0xc0,}
struct Prefab_Layout
{
	Draw_Font*	font;
	Draw_Image*	color;
	String*	text;
	Draw_Image*	icon;
	Draw_Image*	mask;
	String*	tag;
};
#define Prefab_Layout_size 24
#define Prefab_Layout_map {0xfc,}
struct Prefab_Element
{
	WORD	kind;
	Draw_Rect	r;
	Prefab_Environ*	environ;
	String*	tag;
	List*	kids;
	String*	str;
	Draw_Image*	mask;
	Draw_Image*	image;
	Draw_Font*	font;
};
#define Prefab_Element_size 48
#define Prefab_Element_map {0x7,0xf0,}
struct Prefab_Compound
{
	Draw_Image*	image;
	Prefab_Environ*	environ;
	Draw_Rect	r;
	Prefab_Element*	title;
	Prefab_Element*	contents;
};
#define Prefab_Compound_size 32
#define Prefab_Compound_map {0xc3,}
struct Tk_Toplevel
{
	WORD	id;
};
#define Tk_Toplevel_size 4
#define Tk_Toplevel_map {0}
struct Keyring_SigAlg
{
	String*	name;
};
#define Keyring_SigAlg_size 4
#define Keyring_SigAlg_map {0x80,}
struct Keyring_PK
{
	Keyring_SigAlg*	sa;
	String*	owner;
};
#define Keyring_PK_size 8
#define Keyring_PK_map {0xc0,}
struct Keyring_SK
{
	Keyring_SigAlg*	sa;
	String*	owner;
};
#define Keyring_SK_size 8
#define Keyring_SK_map {0xc0,}
struct Keyring_Certificate
{
	Keyring_SigAlg*	sa;
	String*	signer;
	WORD	exp;
};
#define Keyring_Certificate_size 12
#define Keyring_Certificate_map {0xc0,}
struct Keyring_DigestState
{
	WORD	x;
};
#define Keyring_DigestState_size 4
#define Keyring_DigestState_map {0}
void Sys_announce(void*);
typedef struct F_Sys_announce F_Sys_announce;
struct F_Sys_announce
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Connection t1; }*	ret;
	uchar	temps[12];
	String*	addr;
};
void Sys_bind(void*);
typedef struct F_Sys_bind F_Sys_bind;
struct F_Sys_bind
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
	String*	on;
	WORD	flags;
};
void Sys_byte2char(void*);
typedef struct F_Sys_byte2char F_Sys_byte2char;
struct F_Sys_byte2char
{
	WORD	regs[NREG-1];
	struct{ WORD t0; WORD t1; WORD t2; }*	ret;
	uchar	temps[12];
	Array*	buf;
	WORD	n;
};
void Sys_char2byte(void*);
typedef struct F_Sys_char2byte F_Sys_char2byte;
struct F_Sys_char2byte
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	c;
	Array*	buf;
	WORD	n;
};
void Sys_chdir(void*);
typedef struct F_Sys_chdir F_Sys_chdir;
struct F_Sys_chdir
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	path;
};
void Sys_create(void*);
typedef struct F_Sys_create F_Sys_create;
struct F_Sys_create
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[12];
	String*	s;
	WORD	mode;
	WORD	perm;
};
void Sys_dial(void*);
typedef struct F_Sys_dial F_Sys_dial;
struct F_Sys_dial
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Connection t1; }*	ret;
	uchar	temps[12];
	String*	addr;
	String*	local;
};
void Sys_dirread(void*);
typedef struct F_Sys_dirread F_Sys_dirread;
struct F_Sys_dirread
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	dir;
};
void Sys_dup(void*);
typedef struct F_Sys_dup F_Sys_dup;
struct F_Sys_dup
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	old;
	WORD	new;
};
void Sys_export(void*);
typedef struct F_Sys_export F_Sys_export;
struct F_Sys_export
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	c;
	WORD	flag;
};
void Sys_fildes(void*);
typedef struct F_Sys_fildes F_Sys_fildes;
struct F_Sys_fildes
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[12];
	WORD	fd;
};
void Sys_file2chan(void*);
typedef struct F_Sys_file2chan F_Sys_file2chan;
struct F_Sys_file2chan
{
	WORD	regs[NREG-1];
	Sys_FileIO**	ret;
	uchar	temps[12];
	String*	dir;
	String*	file;
	WORD	flags;
};
void Sys_fprint(void*);
typedef struct F_Sys_fprint F_Sys_fprint;
struct F_Sys_fprint
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	String*	s;
	WORD	vargs;
};
void Sys_fstat(void*);
typedef struct F_Sys_fstat F_Sys_fstat;
struct F_Sys_fstat
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Dir t1; }*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
};
void Sys_fwstat(void*);
typedef struct F_Sys_fwstat F_Sys_fwstat;
struct F_Sys_fwstat
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Sys_Dir	d;
};
void Sys_listen(void*);
typedef struct F_Sys_listen F_Sys_listen;
struct F_Sys_listen
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Connection t1; }*	ret;
	uchar	temps[12];
	Sys_Connection	c;
};
void Sys_millisec(void*);
typedef struct F_Sys_millisec F_Sys_millisec;
struct F_Sys_millisec
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
};
void Sys_mount(void*);
typedef struct F_Sys_mount F_Sys_mount;
struct F_Sys_mount
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	String*	on;
	WORD	flags;
	String*	spec;
};
void Sys_open(void*);
typedef struct F_Sys_open F_Sys_open;
struct F_Sys_open
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[12];
	String*	s;
	WORD	mode;
};
void Sys_pctl(void*);
typedef struct F_Sys_pctl F_Sys_pctl;
struct F_Sys_pctl
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	flags;
};
void Sys_print(void*);
typedef struct F_Sys_print F_Sys_print;
struct F_Sys_print
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
	WORD	vargs;
};
void Sys_read(void*);
typedef struct F_Sys_read F_Sys_read;
struct F_Sys_read
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Sys_remove(void*);
typedef struct F_Sys_remove F_Sys_remove;
struct F_Sys_remove
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
};
void Sys_seek(void*);
typedef struct F_Sys_seek F_Sys_seek;
struct F_Sys_seek
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	WORD	off;
	WORD	start;
};
void Sys_sleep(void*);
typedef struct F_Sys_sleep F_Sys_sleep;
struct F_Sys_sleep
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	period;
};
void Sys_sprint(void*);
typedef struct F_Sys_sprint F_Sys_sprint;
struct F_Sys_sprint
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	String*	s;
	WORD	vargs;
};
void Sys_stat(void*);
typedef struct F_Sys_stat F_Sys_stat;
struct F_Sys_stat
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Dir t1; }*	ret;
	uchar	temps[12];
	String*	s;
};
void Sys_stream(void*);
typedef struct F_Sys_stream F_Sys_stream;
struct F_Sys_stream
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	src;
	Sys_FD*	dst;
	WORD	bufsiz;
};
void Sys_tokenize(void*);
typedef struct F_Sys_tokenize F_Sys_tokenize;
struct F_Sys_tokenize
{
	WORD	regs[NREG-1];
	struct{ WORD t0; List* t1; }*	ret;
	uchar	temps[12];
	String*	s;
	String*	delim;
};
void Sys_unmount(void*);
typedef struct F_Sys_unmount F_Sys_unmount;
struct F_Sys_unmount
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s1;
	String*	s2;
};
void Sys_utfbytes(void*);
typedef struct F_Sys_utfbytes F_Sys_utfbytes;
struct F_Sys_utfbytes
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Array*	buf;
	WORD	n;
};
void Sys_write(void*);
typedef struct F_Sys_write F_Sys_write;
struct F_Sys_write
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Sys_wstat(void*);
typedef struct F_Sys_wstat F_Sys_wstat;
struct F_Sys_wstat
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
	Sys_Dir	d;
};
#define Sys_ERRLEN 64
#define Sys_WAITLEN 64
#define Sys_OREAD 0
#define Sys_OWRITE 1
#define Sys_ORDWR 2
#define Sys_CHDIR -2147483648
#define Sys_MREPL 0
#define Sys_MBEFORE 1
#define Sys_MAFTER 2
#define Sys_MCREATE 4
#define Sys_NEWFD 1
#define Sys_FORKFD 2
#define Sys_NEWNS 4
#define Sys_FORKNS 8
#define Sys_NEWPGRP 16
#define Sys_NODEVS 32
#define Sys_EXPWAIT 0
#define Sys_EXPASYNC 1
#define Sys_UTFmax 3
#define Sys_UTFerror 128
void Point_add(void*);
typedef struct F_Point_add F_Point_add;
struct F_Point_add
{
	WORD	regs[NREG-1];
	Draw_Point*	ret;
	uchar	temps[12];
	Draw_Point	p;
	Draw_Point	q;
};
void Point_sub(void*);
typedef struct F_Point_sub F_Point_sub;
struct F_Point_sub
{
	WORD	regs[NREG-1];
	Draw_Point*	ret;
	uchar	temps[12];
	Draw_Point	p;
	Draw_Point	q;
};
void Point_mul(void*);
typedef struct F_Point_mul F_Point_mul;
struct F_Point_mul
{
	WORD	regs[NREG-1];
	Draw_Point*	ret;
	uchar	temps[12];
	Draw_Point	p;
	WORD	i;
};
void Point_div(void*);
typedef struct F_Point_div F_Point_div;
struct F_Point_div
{
	WORD	regs[NREG-1];
	Draw_Point*	ret;
	uchar	temps[12];
	Draw_Point	p;
	WORD	i;
};
void Point_eq(void*);
typedef struct F_Point_eq F_Point_eq;
struct F_Point_eq
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Point	p;
	Draw_Point	q;
};
void Rect_canon(void*);
typedef struct F_Rect_canon F_Rect_canon;
struct F_Rect_canon
{
	WORD	regs[NREG-1];
	Draw_Rect*	ret;
	uchar	temps[12];
	Draw_Rect	r;
};
void Rect_dx(void*);
typedef struct F_Rect_dx F_Rect_dx;
struct F_Rect_dx
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Rect	r;
};
void Rect_dy(void*);
typedef struct F_Rect_dy F_Rect_dy;
struct F_Rect_dy
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Rect	r;
};
void Rect_eq(void*);
typedef struct F_Rect_eq F_Rect_eq;
struct F_Rect_eq
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Rect	s;
};
void Rect_Xrect(void*);
typedef struct F_Rect_Xrect F_Rect_Xrect;
struct F_Rect_Xrect
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Rect	s;
};
void Rect_inrect(void*);
typedef struct F_Rect_inrect F_Rect_inrect;
struct F_Rect_inrect
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Rect	s;
};
void Rect_clip(void*);
typedef struct F_Rect_clip F_Rect_clip;
struct F_Rect_clip
{
	WORD	regs[NREG-1];
	struct{ Draw_Rect t0; WORD t1; }*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Rect	s;
};
void Rect_contains(void*);
typedef struct F_Rect_contains F_Rect_contains;
struct F_Rect_contains
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Point	p;
};
void Rect_addpt(void*);
typedef struct F_Rect_addpt F_Rect_addpt;
struct F_Rect_addpt
{
	WORD	regs[NREG-1];
	Draw_Rect*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Point	p;
};
void Rect_subpt(void*);
typedef struct F_Rect_subpt F_Rect_subpt;
struct F_Rect_subpt
{
	WORD	regs[NREG-1];
	Draw_Rect*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	Draw_Point	p;
};
void Rect_inset(void*);
typedef struct F_Rect_inset F_Rect_inset;
struct F_Rect_inset
{
	WORD	regs[NREG-1];
	Draw_Rect*	ret;
	uchar	temps[12];
	Draw_Rect	r;
	WORD	n;
};
void Image_draw(void*);
typedef struct F_Image_draw F_Image_draw;
struct F_Image_draw
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Rect	r;
	Draw_Image*	src;
	Draw_Image*	mask;
	Draw_Point	p;
};
void Image_line(void*);
typedef struct F_Image_line F_Image_line;
struct F_Image_line
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Point	p0;
	Draw_Point	p1;
	WORD	radius;
	Draw_Image*	src;
};
void Image_text(void*);
typedef struct F_Image_text F_Image_text;
struct F_Image_text
{
	WORD	regs[NREG-1];
	Draw_Point*	ret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Point	p;
	Draw_Image*	src;
	Draw_Font*	font;
	String*	str;
};
void Image_readpixels(void*);
typedef struct F_Image_readpixels F_Image_readpixels;
struct F_Image_readpixels
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Image*	src;
	Draw_Rect	r;
	Array*	data;
};
void Image_writepixels(void*);
typedef struct F_Image_writepixels F_Image_writepixels;
struct F_Image_writepixels
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Image*	dst;
	Draw_Rect	r;
	Array*	data;
};
void Image_top(void*);
typedef struct F_Image_top F_Image_top;
struct F_Image_top
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	win;
};
void Image_bottom(void*);
typedef struct F_Image_bottom F_Image_bottom;
struct F_Image_bottom
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	win;
};
void Image_setrefresh(void*);
typedef struct F_Image_setrefresh F_Image_setrefresh;
struct F_Image_setrefresh
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Image*	win;
	WORD	func;
};
void Font_open(void*);
typedef struct F_Font_open F_Font_open;
struct F_Font_open
{
	WORD	regs[NREG-1];
	Draw_Font**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	String*	name;
};
void Font_build(void*);
typedef struct F_Font_build F_Font_build;
struct F_Font_build
{
	WORD	regs[NREG-1];
	Draw_Font**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	String*	name;
	String*	desc;
};
void Font_width(void*);
typedef struct F_Font_width F_Font_width;
struct F_Font_width
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Draw_Font*	f;
	String*	str;
};
void Display_allocate(void*);
typedef struct F_Display_allocate F_Display_allocate;
struct F_Display_allocate
{
	WORD	regs[NREG-1];
	Draw_Display**	ret;
	uchar	temps[12];
	String*	dev;
};
void Display_startrefresh(void*);
typedef struct F_Display_startrefresh F_Display_startrefresh;
struct F_Display_startrefresh
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Display*	d;
};
void Display_publicscreen(void*);
typedef struct F_Display_publicscreen F_Display_publicscreen;
struct F_Display_publicscreen
{
	WORD	regs[NREG-1];
	Draw_Screen**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	WORD	id;
};
void Display_newimage(void*);
typedef struct F_Display_newimage F_Display_newimage;
struct F_Display_newimage
{
	WORD	regs[NREG-1];
	Draw_Image**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	Draw_Rect	r;
	WORD	ldepth;
	WORD	repl;
	WORD	color;
};
void Display_readimage(void*);
typedef struct F_Display_readimage F_Display_readimage;
struct F_Display_readimage
{
	WORD	regs[NREG-1];
	Draw_Image**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	Sys_FD*	fd;
};
void Display_open(void*);
typedef struct F_Display_open F_Display_open;
struct F_Display_open
{
	WORD	regs[NREG-1];
	Draw_Image**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	String*	name;
};
void Display_color(void*);
typedef struct F_Display_color F_Display_color;
struct F_Display_color
{
	WORD	regs[NREG-1];
	Draw_Image**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	WORD	color;
};
void Display_rgb(void*);
typedef struct F_Display_rgb F_Display_rgb;
struct F_Display_rgb
{
	WORD	regs[NREG-1];
	Draw_Image**	ret;
	uchar	temps[12];
	Draw_Display*	d;
	WORD	r;
	WORD	g;
	WORD	b;
};
void Screen_allocate(void*);
typedef struct F_Screen_allocate F_Screen_allocate;
struct F_Screen_allocate
{
	WORD	regs[NREG-1];
	Draw_Screen**	ret;
	uchar	temps[12];
	Draw_Image*	image;
	Draw_Image*	fill;
	WORD	public;
};
void Screen_newwindow(void*);
typedef struct F_Screen_newwindow F_Screen_newwindow;
struct F_Screen_newwindow
{
	WORD	regs[NREG-1];
	Draw_Image**	ret;
	uchar	temps[12];
	Draw_Screen*	screen;
	Draw_Rect	r;
};
void Screen_top(void*);
typedef struct F_Screen_top F_Screen_top;
struct F_Screen_top
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Draw_Screen*	screen;
	Array*	wins;
};
#define Draw_Black 255
#define Draw_Blue 201
#define Draw_Red 15
#define Draw_Yellow 3
#define Draw_Green 192
#define Draw_White 0
#define Draw_Backup 0
#define Draw_Prefab 1
#define Draw_AMexit 10
#define Draw_AMstartir 11
#define Draw_AMstartkbd 12
#define Draw_AMstartptr 13
#define Draw_AMnewpin 14
#define Draw_MAtop 20
void Element_icon(void*);
typedef struct F_Element_icon F_Element_icon;
struct F_Element_icon
{
	WORD	regs[NREG-1];
	Prefab_Element**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Draw_Rect	r;
	Draw_Image*	icon;
	Draw_Image*	mask;
};
void Element_text(void*);
typedef struct F_Element_text F_Element_text;
struct F_Element_text
{
	WORD	regs[NREG-1];
	Prefab_Element**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	String*	text;
	Draw_Rect	r;
	WORD	kind;
};
void Element_layout(void*);
typedef struct F_Element_layout F_Element_layout;
struct F_Element_layout
{
	WORD	regs[NREG-1];
	Prefab_Element**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	List*	lay;
	Draw_Rect	r;
	WORD	kind;
};
void Element_elist(void*);
typedef struct F_Element_elist F_Element_elist;
struct F_Element_elist
{
	WORD	regs[NREG-1];
	Prefab_Element**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Prefab_Element*	elem;
	WORD	kind;
};
void Element_separator(void*);
typedef struct F_Element_separator F_Element_separator;
struct F_Element_separator
{
	WORD	regs[NREG-1];
	Prefab_Element**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Draw_Rect	r;
	Draw_Image*	icon;
	Draw_Image*	mask;
};
void Element_append(void*);
typedef struct F_Element_append F_Element_append;
struct F_Element_append
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Prefab_Element*	elist;
	Prefab_Element*	elem;
};
void Element_adjust(void*);
typedef struct F_Element_adjust F_Element_adjust;
struct F_Element_adjust
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Element*	elem;
	WORD	equal;
	WORD	dir;
};
void Element_clip(void*);
typedef struct F_Element_clip F_Element_clip;
struct F_Element_clip
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Element*	elem;
	Draw_Rect	r;
};
void Element_scroll(void*);
typedef struct F_Element_scroll F_Element_scroll;
struct F_Element_scroll
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Element*	elem;
	Draw_Point	d;
};
void Element_translate(void*);
typedef struct F_Element_translate F_Element_translate;
struct F_Element_translate
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Element*	elem;
	Draw_Point	d;
};
void Element_show(void*);
typedef struct F_Element_show F_Element_show;
struct F_Element_show
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Prefab_Element*	elist;
	Prefab_Element*	elem;
};
void Compound_iconbox(void*);
typedef struct F_Compound_iconbox F_Compound_iconbox;
struct F_Compound_iconbox
{
	WORD	regs[NREG-1];
	Prefab_Compound**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Draw_Point	p;
	String*	title;
	Draw_Image*	icon;
	Draw_Image*	mask;
};
void Compound_textbox(void*);
typedef struct F_Compound_textbox F_Compound_textbox;
struct F_Compound_textbox
{
	WORD	regs[NREG-1];
	Prefab_Compound**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Draw_Rect	r;
	String*	title;
	String*	text;
};
void Compound_layoutbox(void*);
typedef struct F_Compound_layoutbox F_Compound_layoutbox;
struct F_Compound_layoutbox
{
	WORD	regs[NREG-1];
	Prefab_Compound**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Draw_Rect	r;
	String*	title;
	List*	lay;
};
void Compound_box(void*);
typedef struct F_Compound_box F_Compound_box;
struct F_Compound_box
{
	WORD	regs[NREG-1];
	Prefab_Compound**	ret;
	uchar	temps[12];
	Prefab_Environ*	env;
	Draw_Point	p;
	Prefab_Element*	title;
	Prefab_Element*	elist;
};
void Compound_draw(void*);
typedef struct F_Compound_draw F_Compound_draw;
struct F_Compound_draw
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Compound*	comp;
};
void Compound_scroll(void*);
typedef struct F_Compound_scroll F_Compound_scroll;
struct F_Compound_scroll
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Compound*	comp;
	String*	elem;
	Draw_Point	d;
};
void Compound_show(void*);
typedef struct F_Compound_show F_Compound_show;
struct F_Compound_show
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Prefab_Compound*	comp;
	String*	elem;
};
void Compound_select(void*);
typedef struct F_Compound_select F_Compound_select;
struct F_Compound_select
{
	WORD	regs[NREG-1];
	struct{ WORD t0; WORD t1; Prefab_Element* t2; }*	ret;
	uchar	temps[12];
	Prefab_Compound*	comp;
	String*	elem;
	WORD	i;
	Channel*	c;
};
void Compound_tagselect(void*);
typedef struct F_Compound_tagselect F_Compound_tagselect;
struct F_Compound_tagselect
{
	WORD	regs[NREG-1];
	struct{ WORD t0; WORD t1; Prefab_Element* t2; }*	ret;
	uchar	temps[12];
	Prefab_Compound*	comp;
	String*	elem;
	WORD	i;
	Channel*	c;
};
void Compound_highlight(void*);
typedef struct F_Compound_highlight F_Compound_highlight;
struct F_Compound_highlight
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	Prefab_Compound*	comp;
	String*	elem;
	WORD	on;
};
#define Prefab_EIcon 0
#define Prefab_EText 1
#define Prefab_ETitle 2
#define Prefab_EHorizontal 3
#define Prefab_EVertical 4
#define Prefab_ESeparator 5
#define Prefab_Adjpack 10
#define Prefab_Adjequal 11
#define Prefab_Adjfill 12
#define Prefab_Adjleft 20
#define Prefab_Adjup 20
#define Prefab_Adjcenter 21
#define Prefab_Adjright 22
#define Prefab_Adjdown 22
void Tk_toplevel(void*);
typedef struct F_Tk_toplevel F_Tk_toplevel;
struct F_Tk_toplevel
{
	WORD	regs[NREG-1];
	Tk_Toplevel**	ret;
	uchar	temps[12];
	Draw_Screen*	screen;
	String*	arg;
};
void Tk_namechan(void*);
typedef struct F_Tk_namechan F_Tk_namechan;
struct F_Tk_namechan
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Tk_Toplevel*	t;
	Channel*	c;
	String*	n;
};
void Tk_cmd(void*);
typedef struct F_Tk_cmd F_Tk_cmd;
struct F_Tk_cmd
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Tk_Toplevel*	t;
	String*	arg;
};
void Tk_mouse(void*);
typedef struct F_Tk_mouse F_Tk_mouse;
struct F_Tk_mouse
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	WORD	x;
	WORD	y;
	WORD	button;
};
void Tk_keyboard(void*);
typedef struct F_Tk_keyboard F_Tk_keyboard;
struct F_Tk_keyboard
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	WORD	key;
};
void Real_acos(void*);
typedef struct F_Real_acos F_Real_acos;
struct F_Real_acos
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_acosh(void*);
typedef struct F_Real_acosh F_Real_acosh;
struct F_Real_acosh
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_asin(void*);
typedef struct F_Real_asin F_Real_asin;
struct F_Real_asin
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_asinh(void*);
typedef struct F_Real_asinh F_Real_asinh;
struct F_Real_asinh
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_atan(void*);
typedef struct F_Real_atan F_Real_atan;
struct F_Real_atan
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_atan2(void*);
typedef struct F_Real_atan2 F_Real_atan2;
struct F_Real_atan2
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	y;
	REAL	x;
};
void Real_atanh(void*);
typedef struct F_Real_atanh F_Real_atanh;
struct F_Real_atanh
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_cbrt(void*);
typedef struct F_Real_cbrt F_Real_cbrt;
struct F_Real_cbrt
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_ceil(void*);
typedef struct F_Real_ceil F_Real_ceil;
struct F_Real_ceil
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_copysign(void*);
typedef struct F_Real_copysign F_Real_copysign;
struct F_Real_copysign
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	s;
};
void Real_cos(void*);
typedef struct F_Real_cos F_Real_cos;
struct F_Real_cos
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_cosh(void*);
typedef struct F_Real_cosh F_Real_cosh;
struct F_Real_cosh
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_dot(void*);
typedef struct F_Real_dot F_Real_dot;
struct F_Real_dot
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	Array*	x;
	Array*	y;
};
void Real_erf(void*);
typedef struct F_Real_erf F_Real_erf;
struct F_Real_erf
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_erfc(void*);
typedef struct F_Real_erfc F_Real_erfc;
struct F_Real_erfc
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_exp(void*);
typedef struct F_Real_exp F_Real_exp;
struct F_Real_exp
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_expm1(void*);
typedef struct F_Real_expm1 F_Real_expm1;
struct F_Real_expm1
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_fabs(void*);
typedef struct F_Real_fabs F_Real_fabs;
struct F_Real_fabs
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_fdim(void*);
typedef struct F_Real_fdim F_Real_fdim;
struct F_Real_fdim
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Real_fmin(void*);
typedef struct F_Real_fmin F_Real_fmin;
struct F_Real_fmin
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Real_fmax(void*);
typedef struct F_Real_fmax F_Real_fmax;
struct F_Real_fmax
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Real_finite(void*);
typedef struct F_Real_finite F_Real_finite;
struct F_Real_finite
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_floor(void*);
typedef struct F_Real_floor F_Real_floor;
struct F_Real_floor
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_fmod(void*);
typedef struct F_Real_fmod F_Real_fmod;
struct F_Real_fmod
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Real_gemm(void*);
typedef struct F_Real_gemm F_Real_gemm;
struct F_Real_gemm
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
	WORD	transa;
	WORD	transb;
	WORD	m;
	WORD	n;
	WORD	k;
	WORD	_pad52;
	REAL	alpha;
	Array*	a;
	WORD	ai0;
	WORD	aj0;
	WORD	lda;
	Array*	b;
	WORD	bi0;
	WORD	bj0;
	WORD	ldb;
	REAL	beta;
	Array*	c;
	WORD	ci0;
	WORD	cj0;
	WORD	ldc;
};
void Real_getFPcontrol(void*);
typedef struct F_Real_getFPcontrol F_Real_getFPcontrol;
struct F_Real_getFPcontrol
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
};
void Real_getFPstatus(void*);
typedef struct F_Real_getFPstatus F_Real_getFPstatus;
struct F_Real_getFPstatus
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
};
void Real_FPcontrol(void*);
typedef struct F_Real_FPcontrol F_Real_FPcontrol;
struct F_Real_FPcontrol
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	r;
	WORD	mask;
};
void Real_FPstatus(void*);
typedef struct F_Real_FPstatus F_Real_FPstatus;
struct F_Real_FPstatus
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	r;
	WORD	mask;
};
void Real_hypot(void*);
typedef struct F_Real_hypot F_Real_hypot;
struct F_Real_hypot
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Real_iamax(void*);
typedef struct F_Real_iamax F_Real_iamax;
struct F_Real_iamax
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Array*	x;
};
void Real_ilogb(void*);
typedef struct F_Real_ilogb F_Real_ilogb;
struct F_Real_ilogb
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_isnan(void*);
typedef struct F_Real_isnan F_Real_isnan;
struct F_Real_isnan
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_j0(void*);
typedef struct F_Real_j0 F_Real_j0;
struct F_Real_j0
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_j1(void*);
typedef struct F_Real_j1 F_Real_j1;
struct F_Real_j1
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_jn(void*);
typedef struct F_Real_jn F_Real_jn;
struct F_Real_jn
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	WORD	n;
	WORD	_pad36;
	REAL	x;
};
void Real_lgamma(void*);
typedef struct F_Real_lgamma F_Real_lgamma;
struct F_Real_lgamma
{
	WORD	regs[NREG-1];
	struct{ WORD t0; REAL t1; }*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_log(void*);
typedef struct F_Real_log F_Real_log;
struct F_Real_log
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_log10(void*);
typedef struct F_Real_log10 F_Real_log10;
struct F_Real_log10
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_log1p(void*);
typedef struct F_Real_log1p F_Real_log1p;
struct F_Real_log1p
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_modf(void*);
typedef struct F_Real_modf F_Real_modf;
struct F_Real_modf
{
	WORD	regs[NREG-1];
	struct{ WORD t0; REAL t1; }*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_nextafter(void*);
typedef struct F_Real_nextafter F_Real_nextafter;
struct F_Real_nextafter
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Real_norm1(void*);
typedef struct F_Real_norm1 F_Real_norm1;
struct F_Real_norm1
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	Array*	x;
};
void Real_norm2(void*);
typedef struct F_Real_norm2 F_Real_norm2;
struct F_Real_norm2
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	Array*	x;
};
void Real_pow(void*);
typedef struct F_Real_pow F_Real_pow;
struct F_Real_pow
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	y;
};
void Real_pow10(void*);
typedef struct F_Real_pow10 F_Real_pow10;
struct F_Real_pow10
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	WORD	p;
};
void Real_remainder(void*);
typedef struct F_Real_remainder F_Real_remainder;
struct F_Real_remainder
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	REAL	p;
};
void Real_rint(void*);
typedef struct F_Real_rint F_Real_rint;
struct F_Real_rint
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_scalbn(void*);
typedef struct F_Real_scalbn F_Real_scalbn;
struct F_Real_scalbn
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
	WORD	n;
};
void Real_sin(void*);
typedef struct F_Real_sin F_Real_sin;
struct F_Real_sin
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_sinh(void*);
typedef struct F_Real_sinh F_Real_sinh;
struct F_Real_sinh
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_sqrt(void*);
typedef struct F_Real_sqrt F_Real_sqrt;
struct F_Real_sqrt
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_tan(void*);
typedef struct F_Real_tan F_Real_tan;
struct F_Real_tan
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_tanh(void*);
typedef struct F_Real_tanh F_Real_tanh;
struct F_Real_tanh
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_y0(void*);
typedef struct F_Real_y0 F_Real_y0;
struct F_Real_y0
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_y1(void*);
typedef struct F_Real_y1 F_Real_y1;
struct F_Real_y1
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	REAL	x;
};
void Real_yn(void*);
typedef struct F_Real_yn F_Real_yn;
struct F_Real_yn
{
	WORD	regs[NREG-1];
	REAL*	ret;
	uchar	temps[12];
	WORD	n;
	WORD	_pad36;
	REAL	x;
};
#define Real_Infinity Infinity
#define Real_NaN NaN
#define Real_MachEps 2.220446049250313e-16
#define Real_Pi 3.141592653589793
#define Real_Degree .017453292519943295
#define Real_INVAL 1
#define Real_ZDIV 2
#define Real_OVFL 4
#define Real_UNFL 8
#define Real_INEX 16
#define Real_RND_NR 0
#define Real_RND_NINF 256
#define Real_RND_PINF 512
#define Real_RND_Z 768
#define Real_RND_MASK 768
void Keyring_certtostr(void*);
typedef struct F_Keyring_certtostr F_Keyring_certtostr;
struct F_Keyring_certtostr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Keyring_Certificate*	c;
};
void Keyring_pktostr(void*);
typedef struct F_Keyring_pktostr F_Keyring_pktostr;
struct F_Keyring_pktostr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Keyring_PK*	pk;
};
void Keyring_sktostr(void*);
typedef struct F_Keyring_sktostr F_Keyring_sktostr;
struct F_Keyring_sktostr
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Keyring_SK*	sk;
};
void Keyring_strtocert(void*);
typedef struct F_Keyring_strtocert F_Keyring_strtocert;
struct F_Keyring_strtocert
{
	WORD	regs[NREG-1];
	Keyring_Certificate**	ret;
	uchar	temps[12];
	String*	s;
};
void Keyring_strtopk(void*);
typedef struct F_Keyring_strtopk F_Keyring_strtopk;
struct F_Keyring_strtopk
{
	WORD	regs[NREG-1];
	Keyring_PK**	ret;
	uchar	temps[12];
	String*	s;
};
void Keyring_strtosk(void*);
typedef struct F_Keyring_strtosk F_Keyring_strtosk;
struct F_Keyring_strtosk
{
	WORD	regs[NREG-1];
	Keyring_SK**	ret;
	uchar	temps[12];
	String*	s;
};
void Keyring_sign(void*);
typedef struct F_Keyring_sign F_Keyring_sign;
struct F_Keyring_sign
{
	WORD	regs[NREG-1];
	Keyring_Certificate**	ret;
	uchar	temps[12];
	Keyring_SK*	sk;
	WORD	exp;
	Keyring_DigestState*	state;
	WORD	alg;
};
void Keyring_verify(void*);
typedef struct F_Keyring_verify F_Keyring_verify;
struct F_Keyring_verify
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Keyring_PK*	pk;
	Keyring_Certificate*	cert;
	Keyring_DigestState*	state;
	WORD	alg;
};
void Keyring_genSK(void*);
typedef struct F_Keyring_genSK F_Keyring_genSK;
struct F_Keyring_genSK
{
	WORD	regs[NREG-1];
	Keyring_SK**	ret;
	uchar	temps[12];
	String*	algname;
	String*	owner;
	WORD	length;
};
void Keyring_genSKfromPK(void*);
typedef struct F_Keyring_genSKfromPK F_Keyring_genSKfromPK;
struct F_Keyring_genSKfromPK
{
	WORD	regs[NREG-1];
	Keyring_SK**	ret;
	uchar	temps[12];
	Keyring_PK*	pk;
	String*	owner;
};
void Keyring_sktopk(void*);
typedef struct F_Keyring_sktopk F_Keyring_sktopk;
struct F_Keyring_sktopk
{
	WORD	regs[NREG-1];
	Keyring_PK**	ret;
	uchar	temps[12];
	Keyring_SK*	sk;
};
void Keyring_sha(void*);
typedef struct F_Keyring_sha F_Keyring_sha;
struct F_Keyring_sha
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[12];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
void Keyring_md5(void*);
typedef struct F_Keyring_md5 F_Keyring_md5;
struct F_Keyring_md5
{
	WORD	regs[NREG-1];
	Keyring_DigestState**	ret;
	uchar	temps[12];
	Array*	buf;
	WORD	n;
	Array*	digest;
	Keyring_DigestState*	state;
};
#define Keyring_DEScbc 0
#define Keyring_DESecb 1
#define Keyring_SHA 2
#define Keyring_MD5 3
#define Keyring_SHAdlen 20
#define Keyring_MD5dlen 16
