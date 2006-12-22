#include "rc.h"
#include "y.tab.h"

Tree *Treenodes;

/*
 * create and clear a new Tree node, and add it
 * to the node list.
 */
Tree *
newtree(void)
{
	Tree *t=new(Tree);
	t->iskw=0;
	t->str=0;
	t->child[0]=t->child[1]=t->child[2]=0;
	t->next=Treenodes;
	Treenodes=t;
	return t;
}

void
freenodes(void)
{
	Tree *t, *u;
	for(t=Treenodes;t;t=u){
		u=t->next;
		if(t->str)
			free(t->str);
		free(t);
	}
	Treenodes=0;
}

Tree *
tree1(int type, Tree *c0)
{
	return tree3(type, c0, 0, 0);
}

Tree *
tree2(int type, Tree *c0, Tree *c1)
{
	return tree3(type, c0, c1, 0);
}

Tree *
tree3(int type, Tree *c0, Tree *c1, Tree *c2)
{
	Tree *t;
	if(type==';'){
		if(c0==0) return c1;
		if(c1==0) return c0;
	}
	t=newtree();
	t->type=type;
	t->child[0]=c0;
	t->child[1]=c1;
	t->child[2]=c2;
	return t;
}

Tree *
mung1(Tree *t, Tree *c0)
{
	t->child[0]=c0;
	return t;
}

Tree *
mung2(Tree *t, Tree *c0, Tree *c1)
{
	t->child[0]=c0;
	t->child[1]=c1;
	return t;
}

Tree *
mung3(Tree *t, Tree *c0, Tree *c1, Tree *c2)
{
	t->child[0]=c0;
	t->child[1]=c1;
	t->child[2]=c2;
	return t;
}

Tree *
epimung(Tree *comp, Tree *epi)
{
	Tree *p;
	if(epi==0) return comp;
	for(p=epi;p->child[1];p=p->child[1]);
	p->child[1]=comp;
	return epi;
}

/*
 * Add a SIMPLE node at the root of t and percolate all the redirections
 * up to the root.
 */
Tree *
simplemung(Tree *t)
{
	Tree *u;
	Io *s;
	t=tree1(SIMPLE, t);
	s=openstr();
	pfmt(s, "%t", t);
	t->str=strdup(s->strp);
	closeio(s);
	for(u=t->child[0];u->type==ARGLIST;u=u->child[0]){
		if(u->child[1]->type==DUP
		|| u->child[1]->type==REDIR){
			u->child[1]->child[1]=t;
			t=u->child[1];
			u->child[1]=0;
		}
	}
	return t;
}

Tree *
token(char *str, int type)
{
	Tree *t=newtree();
	t->type=type;
	t->str=strdup(str);
	return t;
}

void
freetree(Tree *p)
{
	if(p==0) return;	
	freetree(p->child[0]);
	freetree(p->child[1]);
	freetree(p->child[2]);
	if(p->str) free(p->str);
	free((char *)p);
}
