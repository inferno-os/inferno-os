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

#define B14400	14400
#define B28800	28800
#define B57600	57600
#define B76800	76800
#define B115200	115200
#define B230400	230400

extern int vflag;

#define MAXDEV 8
static char *sysdev[MAXDEV];

#include <sys/ioctl.h>
#include <sys/ttycom.h>

static void _buildsysdev(void);
#define	buildsysdev()	_buildsysdev()	/* for devfs-posix.c */

static void
_buildsysdev(void)
{
    kern_return_t           kernResult;
    mach_port_t             masterPort;
    CFMutableDictionaryRef  classesToMatch;
    io_iterator_t           serialPortIterator;
    io_object_t             serialDevice;
    CFMutableArrayRef       array;
    CFIndex                 idx;

    kernResult = IOMasterPort(MACH_PORT_NULL, &masterPort);
    if (KERN_SUCCESS != kernResult)
    {
        printf("IOMasterPort returned %d\n", kernResult);
    } else {
        classesToMatch = IOServiceMatching(kIOSerialBSDServiceValue);
        if (classesToMatch == NULL)
        {
            printf("IOServiceMatching returned a NULL dictionary.\n");
        } else {
            CFDictionarySetValue(classesToMatch,
                                 CFSTR(kIOSerialBSDTypeKey),
                                 CFSTR(kIOSerialBSDAllTypes));
        }
        
        kernResult = IOServiceGetMatchingServices(masterPort, classesToMatch, &serialPortIterator);
        if (KERN_SUCCESS != kernResult)
        {
            printf("IOServiceGetMatchingServices returned %d\n", kernResult);
        } else {
            array = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
            
            while ((serialDevice = IOIteratorNext(serialPortIterator))) {
                CFTypeRef	bsdPathAsCFString;
                bsdPathAsCFString = IORegistryEntryCreateCFProperty(serialDevice,
                                                                    CFSTR(kIOCalloutDeviceKey),
                                                                    kCFAllocatorDefault,
                                                                    0);
                if (bsdPathAsCFString) {
                    CFArrayAppendValue(array, bsdPathAsCFString);
                }
                
                (void) IOObjectRelease(serialDevice);
            }
            
            idx = CFArrayGetCount(array);
            if (idx > 0) {
                Boolean result;
                char 	bsdPath[MAXPATHLEN];
                char 	*tmpsysdev[idx+1];
                CFIndex i;
                
                for (i=0; i<idx; i++) {
                    result = CFStringGetCString(CFArrayGetValueAtIndex(array, i),
                                                bsdPath,
                                                sizeof(bsdPath),
                                                kCFStringEncodingASCII);
                    if (result) {
                        int len = strlen(bsdPath);
                        tmpsysdev[i] = (char *)malloc((len+1)*sizeof(char));
                        strcpy(tmpsysdev[i], bsdPath);
                    }
                }
                tmpsysdev[idx] = NULL;
                for (i=0; i < idx; i++) {
                    sysdev[i] = tmpsysdev[i];
                    if (vflag)
                        printf("BSD path: '%s'\n", sysdev[i]);
                }
            }
            
            CFRelease(array);
        }
    }
	
    if (serialPortIterator)
        IOObjectRelease(serialPortIterator);
    if (masterPort)
        mach_port_deallocate(mach_task_self(), masterPort);

    return;
}

#undef nil

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
