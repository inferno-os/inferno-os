#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

static Queue*	consiq;
static Queue*	consoq;

void
bothputs(char *s, int n)
{
	uartputs(s, n);
//	cgascreenputs(s, n);
}

static void (*consputs)(char*, int) =  0;

void
consinit(void)
{
	char *p;
	int baud, port;
	static int cgadone;

	if((p = getconf("console")) == 0 || strcmp(p, "lcd") == 0 || strcmp(p, "screen") == 0){
		consiq = qopen(4*1024, 0, 0, 0);
		consoq = qopen(8*1024, 0, 0, 0);
		consputs = uartputs;
		if(!cgadone) {
			cgadone = 1;
			//screeninit();
			//kbdinit();
		port = 1;
		baud = 9600;
		uartspecial(port, baud, &consiq, &consoq, kbdchar);
		}
		return;
	}
	if(0 || strstr(p, "lcd") == 0)
		consputs = bothputs;
	else
		consputs = uartputs;

	port = strtoul(p, 0, 0);
	baud = 0;
	if(p = getconf("baud"))
		baud = strtoul(p, 0, 0);
	if(baud == 0)
		baud = 9600;
	uartspecial(port, baud, &consiq, &consoq, kbdchar);
}

void
kbdchar(Queue *q, int c)
{
	c &= 0x7F;
	if(c == 0x10)
		panic("^p");
	if(q == 0) {
		if(consiq != 0)
			qbputc(consiq, c);
	} else
		qbputc(q, c);
}

static int
getline(char *buf, int size, int dotimeout)
{
	int c, i=0;
	ulong start;
	char echo;

	for (;;) {
		start = m->ticks;
		do{
			if(dotimeout && ((m->ticks - start) > 5*HZ))
				return -2;
			c = qbgetc(consiq);
		}while(c == -1);
		if(c == '\r')
			c = '\n'; 		/* turn carriage return into newline */
		if(c == '\177')
			c = '\010';		/* turn delete into backspace */
		if(c == '\025')
			echo = '\n';		/* echo ^U as a newline */
		else
			echo = c;
		(*consputs)(&echo, 1);

		if(c == '\010'){
			if(i > 0)
				i--; /* bs deletes last character */
			continue;
		}
		/* a newline ends a line */
		if (c == '\n')
			break;
		/* ^U wipes out the line */
		if (c =='\025')
			return -1;
		if(i == size)
			return size;
		buf[i++] = c;
	}
	buf[i] = 0;
	return i;
}

int
getstr(char *prompt, char *buf, int size, char *def)
{
	int len, isdefault;

	buf[0] = 0;
	isdefault = (def && *def);
	for (;;) {
		if(isdefault)
			print("%s[default==%s]: ", prompt, def);
		else
			print("%s: ", prompt);
		len = getline(buf, size, isdefault);
		switch(len){
		case -1:
			/* ^U typed */
			continue;
		case -2:
			/* timeout, use default */
			(*consputs)("\n", 1);
			len = 0;
			break;
		default:
			break;
		}
		if(len >= size){
			print("line too long\n");
			continue;
		}
		break;
	}
	if(len == 0 && isdefault)
		strcpy(buf, def);
	return 0;
}

int
sprint(char *s, char *fmt, ...)
{
	return donprint(s, s+PRINTSIZE, fmt, (&fmt+1)) - s;
}

int
print(char *fmt, ...)
{
	char buf[PRINTSIZE];
	int n;

	if(consputs == 0)
		return 0;
	n = donprint(buf, buf+sizeof(buf), fmt, (&fmt+1)) - buf;
	(*consputs)(buf, n);
	return n;
}

void
panic(char *fmt, ...)
{
	char buf[PRINTSIZE];
	int n;

	if(consputs){
		(*consputs)("panic: ", 7);
		n = donprint(buf, buf+sizeof(buf), fmt, (&fmt+1)) - buf;
		(*consputs)(buf, n);
		(*consputs)("\n", 1);
	}
	spllo();
	for(;;)
		idle();
}
