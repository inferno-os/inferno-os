typedef struct IPint IPint;

#pragma incomplete IPint

//Keyring_IPint*	newIPint(mpint*);
void*	newIPint(mpint*);
//mpint*	checkIPint(Keyring_IPint*);
mpint*	checkIPint(void*);
void	freeIPint(Heap*, int);
void	ipintsmodinit(void);

extern	Type*	TIPint;
