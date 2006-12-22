typedef struct{char *name; long sig; void (*fn)(void*); int size; int np; uchar map[16];} Runtab;
Runtab Tkmodtab[]={
	"cmd",0x1ee9697,Tk_cmd,40,2,{0x0,0xc0,},
	"color",0xc6935858,Tk_color,40,2,{0x0,0x80,},
	"getimage",0x80bea378,Tk_getimage,40,2,{0x0,0xc0,},
	"keyboard",0x8671bae6,Tk_keyboard,40,2,{0x0,0x80,},
	"namechan",0x35182638,Tk_namechan,48,2,{0x0,0xe0,},
	"pointer",0x21188625,Tk_pointer,56,2,{0x0,0x80,},
	"putimage",0x2dc55622,Tk_putimage,48,2,{0x0,0xf0,},
	"quote",0xb2cd7190,Tk_quote,40,2,{0x0,0x80,},
	"rect",0x683e6bae,Tk_rect,48,2,{0x0,0xc0,},
	"toplevel",0x96ab1cc9,Tk_toplevel,40,2,{0x0,0xc0,},
	0
};
#define Tkmodlen	10
