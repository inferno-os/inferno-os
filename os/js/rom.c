#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"

typedef struct Rom Rom;

struct Rom
{
	uint	magic;
	uint	version;
	uint	plugin_version;
	uint	monitor_id;

	void	**physmemlist;
	void	**virtmemlist;
	void	**availphysmemlist;
	void	*config_info;

	char	**bootcmd;

	uint	(*open)();
	uint	(*close)();

	uint	(*read_blocks)();
	uint	(*write_blocks)();

	uint	(*transmit_pkt)();
	uint	(*poll_pkt)();

	uint	(*read_bytes)();
	uint	(*write_bytes)();
	uint	(*seek)();

	uchar	*input;
	uchar	*output;

	uchar	(*getchar)();
	uchar	(*putchar)();
	uchar	(*noblock_getchar)();
	uchar	(*noblock_putchar)();

	uchar	(*fb_writestr)(char*);

	void	(*boot)(char*);

	void	(*printf)(char*,...);

	void	(*some_kbd_thing)();
	int	*ms_count;
	void	(*exit)();
	void	(**vector)();
	void	(**interpret)(char*,...);
	void	*bootparam;	
	uint	(*mac_addr)();
	char	**v2_bootpath;
	char	** v2_bootargs;
	int	*v2_stdin;
	int	*v2_stdout;
	void*	(*v2_phandle)();
	char*	(*v2_allocphys)();
	char*	(*v2_freephys)();
	char*	(*v2_map_dev)();
	char*	(*v2_unmap_dev)();
	ulong	(*v2_open)();
	uint	(*v2_close)();
	uint	(*v2_read)();
	uint	(*v2_write)();
	uint	(*v2_seek)();
	void	(*v2_chain)();
	void	(*v2_release)();
	char	*(*v3_alloc)();
	int	*reserved[14];
	void	(*setctxsegmap)();
	int	(*v3_startcpu)();
	int	(*v3_stopcpu)();
	int	(*v3_idlecpu)();
	int	(*v3_resumecpu)();
};

Rom	*rom;		/* open boot rom vector -- assigned by l.s */

void
prom_printf(char *format, ...)
{
	char buf[512];
	int l;
	va_list ap;

	va_start(ap, format);
	l = vseprint(buf,buf+sizeof(buf),format,ap) - buf;
	va_end(ap);

	call_openboot(rom->v2_write,*rom->v2_stdout,buf,l);
}

void
prom_halt(void)
{
	call_openboot(rom->exit,0xfeedface);
}
