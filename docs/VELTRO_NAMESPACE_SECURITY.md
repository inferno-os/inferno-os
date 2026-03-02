# Veltro Namespace Security Model (v2) -- SUPERSEDED

> **This document describes the v2 security model (NEWNS + sandbox), which has been replaced by v3 (FORKNS + bind-replace).**
>
> **Current documentation: [`appl/veltro/SECURITY.md`](../appl/veltro/SECURITY.md)**
>
> **Design review: [`docs/NAMESPACE_SECURITY_REVIEW.md`](NAMESPACE_SECURITY_REVIEW.md) (Section 11)**

This document is retained as a historical reference for understanding the design evolution.

---

## Why v2 Was Replaced

The NEWNS + sandbox approach had fundamental problems:

1. **Bootstrap problem**: After `pctl(NEWNS)`, the namespace is empty -- no paths exist, so you can't bind anything without first solving how to create mount points in an empty namespace.

2. **File copying**: NEWNS loses all bind mounts, so granted paths had to be physically copied into the sandbox directory. This was slow, fragile, and required cleanup.

3. **Cleanup complexity**: Sandbox directories under `/tmp/.veltro/sandbox/{id}/` needed explicit cleanup via `rmrf()`, with race conditions around stale detection.

4. **Code size**: ~863 lines of sandbox construction, validation, cleanup, and edge-case handling.

v3 replaces all of this with `restrictdir()` (~455 lines): fork the existing namespace, then bind-replace each directory with a shadow containing only allowed items. No file copying, no cleanup, no bootstrap problem.

---

## v2 Architecture (Historical)

### Security Model

```
Parent (before spawn):
  1. validatesandboxid(id)     - Reject traversal attacks (../, /, special chars)
  2. preparesandbox(caps)      - Create sandbox with restrictive permissions
  3. Pre-load tool modules     - Load .dis files while paths exist

Child (after spawn):
  1. pctl(NEWPGRP, nil)        - Fresh process group (empty srv registry)
  2. pctl(FORKNS, nil)         - Fork namespace for mutation
  3. pctl(NEWENV, nil)         - Empty environment (no inherited secrets)
  4. verifysafefds()           - Check FDs 0-2 are safe
  5. pctl(NEWFD, keepfds)      - Prune all other FDs
  6. pctl(NODEVS, nil)         - Block #U/#p/#c device naming
  7. chdir(sandboxdir)         - Enter prepared sandbox
  8. pctl(NEWNS, nil)          - Sandbox becomes /
  9. safeexec(task)            - Execute using pre-loaded modules
```

### Sandbox Structure

```
/tmp/.veltro/sandbox/{id}/
+-- dis/
|   +-- lib/              bound from /dis/lib (runtime)
|   +-- veltro/tools/     bound from /dis/veltro/tools
|   +-- sh.dis            only if trusted=1
+-- dev/
|   +-- cons              bound from /dev/cons
|   +-- null              bound from /dev/null
+-- tool/                 mount point for tools9p
+-- tmp/                  writable scratch space
+-- n/llm/                LLM access (if configured)
+-- [granted paths]       copied from parent namespace
```

### Learnings Carried Forward to v3

1. **Module pre-loading is essential**: Tool modules must be loaded before namespace restriction. v3 continues this pattern.
2. **Tool init() before restriction**: Tools may load dependencies in init(). Both v2 and v3 call init() while /dis is unrestricted.
3. **NODEVS + NEWENV + NEWPGRP together**: Full security requires all three. v3 applies these in the child spawn sequence.
4. **NODEVS doesn't block everything**: `#e` (environment), `#s` (srv), `#|` (pipes) are still permitted. Mitigated by NEWENV and NEWPGRP.

---

*For the current security model, see [`appl/veltro/SECURITY.md`](../appl/veltro/SECURITY.md).*
