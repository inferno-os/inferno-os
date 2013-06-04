typedef unsigned short Rune16;

	wchar_t	*widen(char *s);
	char		*narrowen(wchar_t *ws);
	int		widebytes(wchar_t *ws);
	int		runeslen(Rune16*);
	Rune16*	runesdup(Rune*);
	Rune16*	utftorunes(Rune*, char*, int);
	char*	runestoutf(char*, Rune16*, int);
	int		runescmp(Rune16*, Rune*);
