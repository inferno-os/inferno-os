typedef struct{char *name; long sig; void (*fn)(void*); int size; int np; uchar map[16];} Runtab;
Runtab Freetypemodtab[]={
	"Face.haschar",0x6a7da190,Face_haschar,40,2,{0x0,0x80,},
	"Face.loadglyph",0xdd275b67,Face_loadglyph,40,2,{0x0,0x80,},
	"newface",0x18a90be,Freetype_newface,40,2,{0x0,0x80,},
	"newmemface",0xc56f82dd,Freetype_newmemface,40,2,{0x0,0x80,},
	"Face.setcharsize",0xb282ce87,Face_setcharsize,48,2,{0x0,0x80,},
	"Face.settransform",0xcf26b85e,Face_settransform,48,2,{0x0,0xe0,},
	0
};
#define Freetypemodlen	6
