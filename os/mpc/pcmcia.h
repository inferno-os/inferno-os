/*
 * PCMCIA support code.
 */
int	inb(int);
int	inb(int);
ulong	inl(int);
ushort	ins(int);
void	insb(int, void*, int);
void	insl(int, void*, int);
void	inss(int, void*, int);
void	outb(int, int);
void	outl(int, ulong);
void	outs(int, ushort);
void	outsb(int, void*, int);
void	outsl(int, void*, int);
void	outss(int, void*, int);
void	pcmintrenable(int, void(*)(Ureg*,void*), void*);
int	pcmspecial(char*, ISAConf*);
void	pcmspecialclose(int);
