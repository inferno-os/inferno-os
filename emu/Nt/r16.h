typedef unsigned short Rune16;

	wchar_t	*widen(char *s);
	char		*narrowen(wchar_t *ws);
	int		widebytes(wchar_t *ws);
	int		runes16len(Rune16*);
	Rune16*	runes16dup(Rune16*);
	Rune16*	utftorunes16(Rune16*, char*, int);
	char*	runes16toutf(char*, Rune16*, int);
	int		runes16cmp(Rune16*, Rune16*);
