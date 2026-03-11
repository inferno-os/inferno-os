# START HERE - ARM64 64-bit Inferno Port

✅ **The port is COMPLETE and WORKING**

## For Users - Quick Start

```bash
./emu/MacOSX/o.emu -r.
```

You'll see the `;` prompt. The system works!

→ See [QUICKSTART.md](../QUICKSTART.md) for details

## For Porters - Critical Information

**Porting to another 64-bit architecture?**

→ Read [LESSONS-LEARNED.md](LESSONS-LEARNED.md) **FIRST**

**Key fix:** Pool quanta must be 127 (not 31) for 64-bit. This single change made everything work.

## Documentation Navigator

→ See [DOCUMENTATION-INDEX.md](DOCUMENTATION-INDEX.md) for complete navigation

Or [COMPLETE-PORT-SUMMARY.md](COMPLETE-PORT-SUMMARY.md) for the full story.

## What Was Accomplished

- ✅ Full 64-bit Dis VM on ARM64
- ✅ Interactive shell with clean output
- ✅ 280+ compiled Limbo programs
- ✅ Complete documentation (15 files)
- ✅ 51 commits tracking every step

## The Breakthrough

The critical fix was changing pool quanta from 31 to 127 in `emu/port/alloc.c`. This was discovered by investigating the working inferno64 repository.

---

**51 commits. 15 docs. 6-8 hours. One working system.**

**Start with [COMPLETE-PORT-SUMMARY.md](COMPLETE-PORT-SUMMARY.md) for the complete story.**
