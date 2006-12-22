#include "u.h"
#include "lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"

struct Queue {
	Block*	first;
	Block*	last;
	void	(*kick)(void*);
	void*	arg;
	long	len;
};

Block *
iallocb(int n)
{
	Block *b;

	b = (Block*)malloc(sizeof(Block)+n);
	b->data = (uchar*)b + sizeof(Block);
	b->rp = b->wp = b->data;
	b->lim = b->data + n;
	b->next = 0;
	b->magic = 0xcafebee0;
	return b;
}

void
freeb(Block *b)
{
	if(b){
		if(b->magic != 0xcafebee0)
			panic("freeb");
		b->magic = 0;
		b->next = (Block*)0xdeadbabe;
		free(b);
	}
}

Queue *
qopen(int limit, int msg, void (*kick)(void*), void *arg)
{
	Queue *q;

	USED(limit, msg);
	q = (Queue*)malloc(sizeof(Queue));
	q->first = q->last = 0;
	q->kick = kick;
	q->arg = arg;
	q->len = 0;
	return q;
}

Block *
qget(Queue *q)
{
	int s;
	Block *b;

	s = splhi();
	if((b = q->first) != 0){
		q->first = b->next;
		b->next = 0;
		q->len -= BLEN(b);
		if(q->len < 0)
			panic("qget");
	}
	splx(s);
	return b;
}

void
qbwrite(Queue *q, Block *b)
{
	int s;

	s = splhi();
	b->next = 0;
	if(q->first == 0)
		q->first = b;
	else
		q->last->next = b;
	q->last = b;
	q->len += BLEN(b);
	splx(s);
	if(q->kick)
		q->kick(q->arg);
}

long
qlen(Queue *q)
{
	return q->len;
}

int
qbgetc(Queue *q)
{
	Block *b;
	int s, c;

	c = -1;
	s = splhi();
	while(c < 0 && (b = q->first) != nil){
		if(b->rp < b->wp){
			c = *b->rp++;
			q->len--;
		}
		if(b->rp >= b->wp){
			q->first = b->next;
			b->next = nil;
		}
	}
	splx(s);
	return c;
}

void
qbputc(Queue *q, int c)
{
	Block *b;

	b = iallocb(1);
	*b->wp++ = c;
	qbwrite(q, b);
}
