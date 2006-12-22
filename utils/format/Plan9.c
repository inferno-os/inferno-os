#include <lib9.h>

int
initfflag()
{
	return 0;
}

Tm *
getlocaltime()
{
	return localtime(time(0));
}

int
openfloppy(char *dev)
{
	return create(dev, ORDWR, 0666);
}
