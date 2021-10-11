/*
 * Darwin serial port definitions, uses IOKit to build sysdev
 * Loosely based on FreeBSD/deveia.c
 * Copyright © 1998, 1999 Lucent Technologies Inc.  All rights reserved.
 * Revisions Copyright © 1999, 2000 Vita Nuova Limited.  All rights reserved.
 * Revisions Copyright © 2003 Corpus Callosum Corporation.  All rights reserved.
*/

#include <termios.h>
#include <sys/param.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

#include <mach/mach.h>

#include <CoreFoundation/CFNumber.h>

#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/serial/IOSerialKeys.h>
#include <IOKit/IOBSD.h>

#include <sys/ioctl.h>
#include <sys/ttycom.h>

#undef nil

#define B14400	14400
#define B28800	28800
#define B57600	57600
#define B76800	76800
#define B115200	115200
#define B230400	230400

extern int vflag;

#define MAXDEV 16
static char *sysdev[MAXDEV];

static void _buildsysdev(void);
#define	buildsysdev()	_buildsysdev()	/* for devfs-posix.c */

#include "deveia-posix.c"
#include "deveia-bsd.c"

static struct tcdef_t bps[] = {
    {0,             B0},
    {50,            B50},
    {75,            B75},
    {110,           B110},
    {134,           B134},
    {150,           B150},
    {200,           B200},
    {300,           B300},
    {600,           B600},
    {1200,	B1200},
    {1800,	B1800},
    {2400,	B2400},
    {4800,	B4800},
    {9600,	B9600},
    {19200,	B19200},
    {38400,	B38400},
    {57600,	B57600},
    {76800,	B76800},
    {115200,	B115200},
    {230400,	B230400},
    {0,		-1}
};

static void
_buildsysdev(void)
{
	mach_port_t port;
	CFMutableDictionaryRef classesToMatch;
	io_iterator_t serialPortIterator;
	io_object_t serialDevice;
	CFMutableArrayRef paths;
	CFTypeRef path;
	char	eiapath[MAXPATHLEN];
	CFIndex i, o, npath;

	if(IOMasterPort(MACH_PORT_NULL, &port) != KERN_SUCCESS)
		return;
	classesToMatch = IOServiceMatching(kIOSerialBSDServiceValue);
	if(classesToMatch == NULL){
		printf("IOServiceMatching returned a NULL dictionary.\n");
		goto Failed;
	}
	CFDictionarySetValue(classesToMatch,
		CFSTR(kIOSerialBSDTypeKey),
		CFSTR(kIOSerialBSDAllTypes));

	if(IOServiceGetMatchingServices(port, classesToMatch, &serialPortIterator) != KERN_SUCCESS)
		goto Failed;

	paths = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
	while((serialDevice = IOIteratorNext(serialPortIterator)) != 0){
		path = IORegistryEntryCreateCFProperty(serialDevice, CFSTR(kIOCalloutDeviceKey), kCFAllocatorDefault, 0);
		if(path != NULL)
			CFArrayAppendValue(paths, path);
		IOObjectRelease(serialDevice);
	}

	npath = CFArrayGetCount(paths);
	o = 0;
	for(i = 0; i < npath && i < nelem(sysdev); i++){
		if(CFStringGetCString(CFArrayGetValueAtIndex(paths, i), eiapath, sizeof(eiapath), kCFStringEncodingUTF8)){
			sysdev[o] = strdup(eiapath);
			if(vflag > 1)
				print("deveia path: eia%d -> '%s'\n", o, sysdev[o]);
			o++;
		}
	}

	CFRelease(paths);
	IOObjectRelease(serialPortIterator);

Failed:
	mach_port_deallocate(mach_task_self(), port);
}

