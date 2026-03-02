# ARM64 JIT Debug Checkpoint - 2026-01-23 (Session 8 Final)

## Session 8 Final Summary - Root Cause Identified

### Status: "Args Hang" is Actually an Early Emuinit JIT Crash

**Root Cause Identified**: The "args hang" is NOT a hang at all. It's the Emuinit shutdown crash happening BEFORE Echo module has a chance to run. The execution order differs between stdin and args:

| Scenario | Execution Order | Result |
|----------|-----------------|--------|
| stdin | Echo runs → prints "hello" → Emuinit crashes | "hello" visible |
| args | Emuinit runs → crashes immediately | No output |

**Why the difference?**
- stdin: Echo's read() call blocks, allowing scheduler to run Echo first
- args: No blocking call, Emuinit runs first and crashes during JIT execution

### Detailed Trace Evidence

**cflag=0 (interpreter only) with args** - Shows correct execution order:
```
XEC: module=Emuinit compiled=0 PC=... (runs 7+ times for setup)
XEC: module=Echo compiled=0 PC=...
hello
XEC: module=Echo compiled=0 PC=...
```

**cflag=1+ (JIT) with args** - Shows early crash:
```
[JIT] Compiling module 'Emuinit' (size=196, ...)
...compilation output...
XEC_JIT: module=Emuinit PC=ffff... FP=... MP=... M=...
[Emuinit] Broken: "sys: segmentation violation addr=0x..."
```
Echo module never appears in the trace - it never gets a chance to run.

**cflag=4 (JIT with max debug) with stdin** - Shows full execution:
```
hello  ← Echo prints before Emuinit crash
[JIT] Compiling module 'Emuinit' ...
XEC_JIT: module=Emuinit ...
JIT_EXEC[183]: executing
JIT_EXEC[184]: executing
JIT_EXEC[185]: executing
JIT_EXEC[186]: executing
[Emuinit] Broken: "sys: illegal instruction pc=0x..."
```

### Crash Analysis

The crash always happens in Emuinit JIT code, but manifests differently:
- args/cflag=1: "sys: segmentation violation addr=0xffff...b14"
- stdin/cflag=1: "sys: illegal instruction pc=0xffff...cb0"
- stdin/cflag=4: "sys: illegal instruction pc=0xffff...b14"

Both are JIT code bugs in Emuinit module. The crash addresses are NOT in the JIT code area - they're in the module data area (between MP and FP), suggesting:
1. Bad pointer dereference
2. Incorrect offset calculation
3. Executing data as code

### Investigation Attempts This Session

1. **Memory barriers (DMB_SY)** - Added at multiple points - No effect
2. **nop_sync() calls** - Added BLR call for synchronization - No effect
3. **XEC tracing** - Confirmed execution order difference between stdin/args
4. **cflag comparison** - Higher cflag levels don't fix the bug, just show more debug output

### Conclusion

The "args hang" bug and the "shutdown crash" are the **same underlying issue**: JIT bugs in Emuinit module. The difference is timing:
- stdin delays execution enough for Echo to print first
- args causes immediate crash before Echo runs

**Next Steps to Fix**:
1. Debug the Emuinit JIT code that crashes
2. The crash happens during instructions 183-186 (per cflag=4 trace)
3. Look at what opcodes these are and why they cause crashes
4. The first instruction (ISLICEA) may also be involved

---

## Session 8 Earlier Summary - Args Hang at ALL JIT cflag Levels

### Status: Command-Line Arguments Hang at ALL cflag Levels (1-4)

**UPDATE**: Further investigation revealed the args issue is NOT cflag-level dependent. Args hang at ALL JIT cflag levels (1, 2, 3, 4). Only cflag=0 (interpreter-only) works.

| Input Method | cflag=0 | cflag=1 | cflag=2 | cflag=3 | cflag=4 |
|-------------|---------|---------|---------|---------|---------|
| stdin (pipe) | Works   | Works   | Works   | Works   | Works   |
| Arguments   | Works   | HANGS   | HANGS   | HANGS   | HANGS   |

**Evidence**:
```bash
# stdin works at all cflag levels
$ echo "hello" | timeout 5 ./o.emu -r../.. -c1 dis/echo.dis
hello
[Emuinit] Broken: "sys: segmentation violation..."

# Arguments hang at ALL JIT cflag levels (1-4)
$ timeout 5 ./o.emu -r../.. -c2 dis/echo.dis "hello"
# Times out with no "hello" output

# Arguments ONLY work with interpreter-only mode (cflag=0)
$ timeout 2 ./o.emu -r../.. -c0 dis/echo.dis "hello"
hello
```

### Key Observations

1. **stdin works because**: The blocking read() call provides synchronization/yield points
2. **args hang because**: No blocking calls, so execution path differs from stdin
3. **cflag=0 works because**: Interpreter handles all instructions correctly
4. **cflag>0 hangs because**: JIT code path for args has an issue

The issue is NOT about memory barriers or debug BLR calls. It's a fundamental problem with how the JIT handles the args execution path.

### Analysis Attempts

1. Added DMB (Data Memory Barrier) instructions at multiple points - **No effect**
2. Added nop_sync() BLR calls for synchronization - **No effect**
3. The issue is specific to JIT-compiled code processing command-line arguments

### Updated Finding: Not a Hang, But an Early Crash

**Key Insight**: The "args hang" is NOT a hang. It's an early crash in Emuinit JIT code that happens BEFORE Echo can run and print.

**Execution Order Difference**:
- With stdin: Echo runs first (during read() blocking), prints "hello", THEN Emuinit crashes
- With args: Emuinit runs first (no blocking), crashes, Echo never runs

**Evidence from cflag=0 (interpreter)**:
```
XEC: module=Emuinit compiled=0 PC=... (runs multiple times)
XEC: module=Echo compiled=0 PC=...
hello
XEC: module=Echo compiled=0 PC=...
```

In interpreter mode, Emuinit runs first for setup, then Echo runs and prints "hello". With JIT, Emuinit crashes during its first execution.

**Crash Differences**:
- With args: "sys: segmentation violation addr=0x..."
- With stdin: "sys: illegal instruction pc=0x..."

Both are JIT bugs in Emuinit, but different symptoms. The underlying issue is that Emuinit's JIT code has bugs that only manifest in certain execution paths.

### Current Hypothesis

The Emuinit JIT crash is the root cause. Fixing the Emuinit crash would likely fix the "args hang" issue since:
1. Echo would get a chance to run before the crash
2. The crash happens during initialization with args
3. With stdin, the blocking read() delays the crash long enough for Echo to print

---

## Session 7 Summary (Previous) - MAIN EXECUTION WORKING!

### Status: JIT Main Execution Fixed, Shutdown Crash Remains

**Test Result**:
```
$ echo "hello" | timeout 10 ./o.emu -r../.. -c1 dis/echo.dis
hello
[Emuinit] Broken: "sys: illegal instruction pc=0xffff91effcb0"
```

The main program executes correctly ("hello" prints), but crashes during Emuinit shutdown. This is a **separate issue** from the original JIT bug.

### Key Finding This Session: Need ALL 4 VM Registers Saved

The previous fix only saved RFP/RMP (X9/X10). This session discovered that **ALL 4 VM registers** (X9-X12) must be saved around BLR calls:

- **RFP** (X9) - Dis Frame Pointer
- **RMP** (X10) - Module Pointer
- **RREG** (X11) - Pointer to REG struct
- **RM** (X12) - Cached R.M

All are caller-saved in ARM64 ABI and can be clobbered by any BLR call.

### Updated Fixes (32-byte stack frame for 4 registers)

**Fix 1 - schedcheck() (~lines 1467-1481)**:
```c
/* Save ALL VM registers before call (they're caller-saved X9-X12) */
emit(STP_PRE(RFP, RMP, SP, -32));
emit(STP(RREG, RM, SP, 16));
/* Call reschedule macro */
con((uvlong)(base + macro[MacRELQ]), RA0, 0);
emit(BLR(RA0));
/* Restore ALL VM registers after call */
emit(LDP(RREG, RM, SP, 16));
emit(LDP_POST(RFP, RMP, SP, 32));
```

**Fix 2 - movp: label (~lines 2024-2050)**:
```c
/* Save ALL VM registers before macro call (X9-X12 are caller-saved) */
emit(STP_PRE(RFP, RMP, SP, -32));
emit(STP(RREG, RM, SP, 16));
con((uvlong)(base + macro[MacCOLR]), RA0, 0);
emit(BLR(RA0));
emit(LDP(RREG, RM, SP, 16));
emit(LDP_POST(RFP, RMP, SP, 32));
/* ... same pattern for MacFRP call ... */
```

**Fix 3 - comd() type destroyer (~lines 2824-2831)**:
```c
mem(Ldw, j, RFP, RA0);
/* Save ALL VM registers around macro call (X9-X12 are caller-saved) */
emit(STP_PRE(RFP, RMP, SP, -32));
emit(STP(RREG, RM, SP, 16));
con((uvlong)(base + macro[MacFRP]), RA1, 0);
emit(BLR(RA1));
emit(LDP(RREG, RM, SP, 16));
emit(LDP_POST(RFP, RMP, SP, 32));
```

### Shutdown Crash Analysis

The crash during shutdown:
- Occurs in Emuinit module (system initialization), not echo module
- `sys: illegal instruction pc=0xffff91effcb0` - executing at non-code address
- **Also affects interpreter mode** (cflag=0) - it hangs instead of crashing
- This suggests a thread synchronization or cleanup issue, NOT a JIT bug

### Verification

Grep confirms all 14 locations now use 32-byte stack frame:
```
$ grep -n "STP_PRE(RFP, RMP, SP, -32)" comp-arm64.c
1146, 1166, 1221, 1468, 2031, 2045, 2495, 2581, 2599, 2674, 2728, 2747, 2776, 2826
```

---

## Session 6 Summary (Previous) - Initial RFP Fix

### Root Cause: BLR Calls Clobbering Caller-Saved RFP Register

**Problem Identified**: In ARM64 ABI, registers X9-X15 are caller-saved. Any BLR (branch-link-register) call can clobber these registers. The JIT was using X9 as RFP (Dis Frame Pointer) but NOT saving/restoring it around BLR calls to macro routines.

**Affected Locations**:
1. `schedcheck()` - BLR to MacRELQ (reschedule)
2. `movp` case (IMOVP, ITAIL, IHEADP) - BLR to MacCOLR and MacFRP
3. `comd()` type destroyer - BLR to MacFRP in loop

### Initial Fix (Later Updated)

Initial fix saved only RFP/RMP (16-byte frame). Session 7 updated to save all 4 VM registers (32-byte frame).

### Additional Notes

- cflag=0 (interpreter only) works but is slow to exit (~10+ seconds)
- This is NOT a JIT bug - likely thread synchronization in emulator shutdown
- cflag=1 exits immediately due to print() calls providing synchronization points

---

## Session 5 Summary (Previous)

### Key Finding: RFP Register Corruption

**Critical Discovery**: The RFP (frame pointer) register gets corrupted between instructions, while R.FP memory remains correct.

Trace evidence:
```
RFP_RELOAD[7]: R.FP=ffffbd8d0240 loaded_RFP=ffffbd8d0240 match=yes
RFP_STORE[107]: R.FP=ffffbd8d0240 storing_RFP=ffffbd8d02c8
```

Key observations:
- After instruction 7 (IFRAME): RFP = 0x240 (correct)
- At instruction 107 start: RFP = 0x2c8 (WRONG), but R.FP memory = 0x240 (still correct)
- The difference (0x88 = 136 bytes) is exactly a frame size
- Something between instructions 7 and 107 modifies the RFP REGISTER directly without updating R.FP

### Debug Tracing Added

Added comprehensive RFP tracing to `comp-arm64.c`:

1. **trace_rfp_store()** - Traces RFP value at start of punt():
```c
static void
trace_rfp_store(long idx, void *rfp_reg)
{
    print("RFP_STORE[%ld]: R.FP=%p storing_RFP=%p\n",
        idx, R.FP, rfp_reg);
}
```

2. **trace_rfp_reload()** - Traces RFP value after punt() reload:
```c
static void
trace_rfp_reload(long idx, void *rfp_reg)
{
    print("RFP_RELOAD[%ld]: R.FP=%p loaded_RFP=%p match=%s\n",
        idx, R.FP, rfp_reg, R.FP == (uchar*)rfp_reg ? "yes" : "NO!");
}
```

3. **Inline IFRAME tracing** - Before and after macfram() macro call

### Analysis of Code Flow

After mcall returns (instruction 6):
1. `RFP_RELOAD[6]` shows RFP=0x240 loaded correctly from R.FP
2. NEWPC branches to R.PC (instruction 7)
3. Instruction 7 (inline IFRAME) executes, preserves RFP=0x240
4. Instructions 8-106 execute (direct JIT, no punt())
5. Instruction 107 starts with RFP=0x2c8 (corrupted!)

### Current Hypothesis

Something in the direct JIT code (instructions 8-106) modifies the X9 (RFP) register. Possibilities:
1. A C function call that doesn't properly save/restore X9
2. An inline macro that clobbers X9
3. Some ARM64 instruction using X9 as a destination

### Files Modified This Session

**libinterp/comp-arm64.c**:
- Added `trace_rfp_store()` function (~line 617)
- Added `trace_rfp_reload()` function (~line 609)
- Added RFP tracing at punt() start (before line 1099)
- Added RFP tracing after punt() reload (after line 1241)
- Added RFP tracing around inline IFRAME macfram() call (lines 2204-2228)

---

## Session 4 Summary (Previous)

### Verified Branch Calculations
All branch offsets verified correct through compile-time and runtime debug:
- `cbra[159]`: target_idx=177, dst(patch)=3333, code_offset=3069, branch_off=1056 bytes
- `INST[177]`: code_offset=3333 (correctly targeted)

### Critical Finding: Crash Timing
The crash occurs IMMEDIATELY after instruction 159's branch to 177:
```
CBRA_CMP: mid=115 src=39 cond=1 target=177 result=branch
[Emuinit] Broken: "dereference of nil"
```

---

## Session 3 Summary

### MAJOR FIX #1: Branch Offset Calculation Bug (CRITICAL - FIXED)

**File**: `libinterp/comp-arm64.c` - multiple locations

**Problem**: Branch offset calculations were treating word offsets as byte offsets.

**Fix**: Use pointer arithmetic before casting:
```c
vlong off = (vlong)(base + dst) - (vlong)code;
```

**Locations Fixed**:
1. `cbra()` - word comparison branch
2. `cbrab()` - byte comparison branch
3. `cbral()` - long comparison branch
4. `IJMP` case - unconditional jump

**Result**: After fix, `echo.dis` prints "hello" correctly!

### MAJOR FIX #2: SRCOP AIMM Indirect Addressing (FIXED)

**File**: `libinterp/comp-arm64.c` - punt() function

**Problem**: For immediate source operands (`SRC(AIMM)`), the JIT was storing the immediate value directly into R.s. But interpreter functions use `W(s)` which dereferences R.s as a pointer.

**Fix**: Store immediate to R.st (source temp), then store &R.st to R.s.

### TCHECK Skip Distance (FIXED)

Fixed skip calculation for TCHECK+NEWPC combination.

---

## Build Commands

```bash
# Build libinterp
cd /mnt/orin-ssd/pdfinn/github.com/NERVsystems/infernode/libinterp
ROOT=/mnt/orin-ssd/pdfinn/github.com/NERVsystems/infernode OBJTYPE=arm64 \
  /mnt/orin-ssd/pdfinn/github.com/NERVsystems/infernode/Linux/arm64/bin/mk install

# Build emulator
cd /mnt/orin-ssd/pdfinn/github.com/NERVsystems/infernode/emu/Linux && rm -f o.emu
ROOT=/mnt/orin-ssd/pdfinn/github.com/NERVsystems/infernode OBJTYPE=arm64 \
  /mnt/orin-ssd/pdfinn/github.com/NERVsystems/infernode/Linux/arm64/bin/mk o.emu

# Test with debug level 2
echo "hello" | ./o.emu -r../.. -c2 dis/echo.dis
```

## Key Files

- `libinterp/comp-arm64.c` - JIT compiler (main file)
- `libinterp/xec.c` - Interpreter functions
- `include/isa.h` - Opcode definitions
- `include/interp.h` - Data structures

## Register Assignments

```c
#define RFP     X9      /* Dis Frame Pointer */
#define RMP     X10     /* Module Pointer (R.MP) */
#define RREG    X11     /* Pointer to REG struct (&R) */
#define RM      X12     /* Cached R.M */
#define RA0     X0      /* General purpose 0, return value */
#define RA1     X1      /* General purpose 1 */
#define RA2     X2      /* General purpose 2 */
#define RA3     X3      /* General purpose 3 */
#define RTA     X4      /* Temporary address */
#define RCON    X5      /* Constant builder */
#define RLINK   X30     /* Link register */
```

## Status: MAIN JIT EXECUTION WORKING

The ARM64 JIT main execution is **WORKING** - programs run correctly and produce expected output.

A separate crash occurs during emulator shutdown in Emuinit module. This also affects interpreter-only mode (hangs instead of crashes), confirming it's NOT a JIT bug.

### Summary of All Fixes (Sessions 3-7)

1. **Branch Offset Calculation** (Session 3) - Fixed byte vs word offset confusion
2. **SRCOP AIMM Indirect Addressing** (Session 3) - Fixed immediate operand handling
3. **TCHECK Skip Distance** (Session 3) - Fixed skip calculation
4. **RFP/RMP Clobbering in BLR Calls** (Session 6) - Added STP/LDP for X9/X10
5. **ALL VM Registers (X9-X12) Clobbering** (Session 7) - Expanded to 32-byte frame saving all 4 VM registers

### Remaining Work

1. Clean up debug tracing code (trace_rfp_store, trace_rfp_reload, etc.)
2. Commit the working fixes to git
3. Investigate emulator shutdown crash/hang (affects both JIT and interpreter modes - separate issue)
