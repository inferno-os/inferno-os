/*
 * CBMC Stubs for Inferno Kernel Verification
 *
 * Provides minimal implementations of kernel primitives needed
 * to verify pgrp.c and chan.c functions with CBMC.
 *
 * These stubs model the essential semantics while abstracting
 * away implementation details irrelevant to namespace isolation.
 */

#ifndef CBMC_STUBS_H
#define CBMC_STUBS_H

#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* ====== Basic Types (matching Inferno's type system) ====== */

typedef unsigned char uchar;
typedef unsigned short ushort;
typedef unsigned int uint;
typedef unsigned long ulong;
typedef long long vlong;
typedef unsigned long long uvlong;

#define nil  ((void*)0)
#define KNAMELEN 28

/* ====== Lock Primitives ====== */

typedef struct Lock {
    int key;
} Lock;

typedef struct RWLock {
    Lock l;
    int readers;
    int writer;
} RWlock;

typedef struct QLock {
    Lock l;
} QLock;

/* Lock operations - track state for verification */
static inline void lock(Lock *l) { l->key = 1; }
static inline void unlock(Lock *l) { l->key = 0; }

static inline void rlock(RWlock *l) {
    __CPROVER_assert(l->writer == 0, "rlock: no writer held");
    l->readers++;
}
static inline void runlock(RWlock *l) {
    __CPROVER_assert(l->readers > 0, "runlock: readers > 0");
    l->readers--;
}
static inline void wlock(RWlock *l) {
    __CPROVER_assert(l->writer == 0, "wlock: no writer held");
    __CPROVER_assert(l->readers == 0, "wlock: no readers held");
    l->writer = 1;
}
static inline void wunlock(RWlock *l) {
    __CPROVER_assert(l->writer == 1, "wunlock: writer held");
    l->writer = 0;
}

/* ====== Reference Counting ====== */

typedef struct Ref {
    Lock lk;
    long ref;
} Ref;

static inline long incref(Ref *r) {
    long old;
    lock(&r->lk);
    old = r->ref;
    __CPROVER_assert(old >= 0, "incref: non-negative before increment");
    r->ref = old + 1;
    unlock(&r->lk);
    return r->ref;
}

static inline long decref(Ref *r) {
    long old;
    lock(&r->lk);
    old = r->ref;
    __CPROVER_assert(old > 0, "decref: positive before decrement");
    r->ref = old - 1;
    unlock(&r->lk);
    return old - 1;
}

/* ====== Forward Declarations ====== */

typedef struct Chan Chan;
typedef struct Cname Cname;
typedef struct Dev Dev;
typedef struct Mhead Mhead;
typedef struct Mount Mount;
typedef struct Mntcache Mntcache;
typedef struct Mnt Mnt;
typedef struct Pgrp Pgrp;
typedef struct Fgrp Fgrp;
typedef struct Walkqid Walkqid;
typedef struct Block Block;

/* ====== Qid ====== */

typedef struct Qid {
    uvlong path;
    ulong vers;
    uchar type;
} Qid;

/* ====== Chan ====== */

struct Cname {
    Ref r;
    int alen;
    int len;
    char *s;
};

struct Chan {
    Lock l;
    Ref r;
    Chan *next;
    Chan *link;
    vlong offset;
    ushort type;
    ulong dev;
    ushort mode;
    ushort flag;
    Qid qid;
    int fid;
    ulong iounit;
    Mhead *umh;
    Chan *umc;
    QLock umqlock;
    int uri;
    int dri;
    ulong mountid;
    Mntcache *mcp;
    Mnt *mux;
    void *aux;
    Chan *mchan;
    Qid mqid;
    Cname *name;
};

/* ====== Mhead and Mount ====== */

struct Mount {
    ulong mountid;
    Mount *next;
    Mount *order;
    Mount *copy;
    Mhead *head;
    Chan *to;
    int mflag;
    char *spec;
};

struct Mhead {
    Ref r;
    RWlock lock;
    Chan *from;
    Mount *mount;
    Mhead *hash;
};

/* ====== Pgrp ====== */

enum {
#ifndef MNTLOG
    MNTLOG = 5,
#endif
    MNTHASH = 1<<MNTLOG,
    DELTAFD = 20,
    MAXNFD = 4000
};

#define MOUNTH(p,qid) ((p)->mnthash[(qid).path&((1<<MNTLOG)-1)])

struct Pgrp {
    Ref r;
    ulong pgrpid;
    RWlock ns;
    QLock nsh;
    Mhead *mnthash[MNTHASH];
    int progmode;
    Chan *dot;
    Chan *slash;
    int nodevs;
    int pin;
};

struct Fgrp {
    Lock l;
    Ref r;
    Chan **fd;
    int nfd;
    int maxfd;
    int minfd;
};

/* ====== Error Handling ====== */

/* Model waserror/poperror/nexterror as CBMC nondeterministic choice.
 * waserror() returns 0 on first call (setjmp), or 1 on error (longjmp).
 * We model this as a nondeterministic boolean for error injection. */

static int _cbmc_waserror_count = 0;
static int _cbmc_error_at = -1;  /* Which waserror call should fail */

static inline int waserror(void) {
    int n = _cbmc_waserror_count++;
    if (_cbmc_error_at >= 0 && n == _cbmc_error_at)
        return 1;  /* Simulate error */
    return 0;  /* Normal path */
}

static inline void poperror(void) { /* no-op in stub */ }
static inline void nexterror(void) { /* model as assertion failure path */ }
static inline void error(char *msg) { /* model as raising error */ }

/* ====== Memory Allocation ====== */

/* For CBMC, malloc can return NULL nondeterministically */
/* We use the real malloc but CBMC's --malloc-may-fail flag */

/* ====== Channel Operations (stubs) ====== */

static inline void cclose(Chan *c) {
    if (c == nil) return;
    if (decref(&c->r) == 0) {
        /* Channel freed - in real code this calls close device method */
    }
}

static inline Chan* cclone(Chan *c) {
    Chan *nc = (Chan*)malloc(sizeof(Chan));
    if (nc == nil) error("clone failed");
    memcpy(nc, c, sizeof(Chan));
    nc->r.ref = 1;
    if (c->name) incref(&c->name->r);
    return nc;
}

/* ====== Mhead Operations ====== */

static inline void putmhead(Mhead *m) {
    if (m != nil && decref(&m->r) == 0) {
        /* Free mhead */
        free(m);
    }
}

/* ====== String Operations ====== */

static inline void kstrdup(char **pp, char *s) {
    if (s == nil) return;
    int n = strlen(s) + 1;
    char *ns = (char*)malloc(n);
    if (ns == nil) error("kstrdup");
    memmove(ns, s, n);
    if (*pp) free(*pp);
    *pp = ns;
}

/* ====== Global State for Stubs ====== */

/* Global mount ID counter (from pgrp.c) */
static Ref _stub_pgrpid;
static Ref _stub_mountid;

/* ====== Helper for CBMC ====== */

/* Create a symbolic but valid Pgrp for testing */
static inline Pgrp* cbmc_alloc_pgrp(void) {
    Pgrp *p = (Pgrp*)malloc(sizeof(Pgrp));
    if (p == nil) return nil;
    memset(p, 0, sizeof(Pgrp));
    p->r.ref = 1;
    p->ns.readers = 0;
    p->ns.writer = 0;
    return p;
}

/* Create a symbolic but valid Chan for testing */
static inline Chan* cbmc_alloc_chan(void) {
    Chan *c = (Chan*)malloc(sizeof(Chan));
    if (c == nil) return nil;
    memset(c, 0, sizeof(Chan));
    c->r.ref = 1;
    return c;
}

/* Create a symbolic but valid Mhead for testing */
static inline Mhead* cbmc_alloc_mhead(Chan *from) {
    Mhead *mh = (Mhead*)malloc(sizeof(Mhead));
    if (mh == nil) return nil;
    memset(mh, 0, sizeof(Mhead));
    mh->r.ref = 1;
    mh->from = from;
    mh->lock.readers = 0;
    mh->lock.writer = 0;
    return mh;
}

/* Create a symbolic but valid Mount for testing */
static inline Mount* cbmc_alloc_mount(Mhead *head, Chan *to) {
    Mount *m = (Mount*)malloc(sizeof(Mount));
    if (m == nil) return nil;
    memset(m, 0, sizeof(Mount));
    m->head = head;
    m->to = to;
    if (to) incref(&to->r);
    return m;
}

#endif /* CBMC_STUBS_H */
