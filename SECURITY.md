# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| master  | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability in InferNode, please report it
responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities.
2. Email security details to the maintainers via GitHub private vulnerability
   reporting: https://github.com/NERVsystems/infernode/security/advisories/new
3. Include a description of the vulnerability, steps to reproduce, and any
   relevant proof-of-concept code.

You should receive an acknowledgement within 72 hours. We will work with you
to understand the issue and coordinate a fix before any public disclosure.

## Scope

The following components are in scope for security reports:

- **Dis VM interpreter and JIT compiler** (`libinterp/`)
- **Emulator kernel** (`emu/port/`, `emu/MacOSX/`, `emu/Linux/`)
- **Cryptography** (`libsec/`, `libmp/`, `libkeyring/`)
- **9P protocol implementation** (`emu/port/devmnt.c`, `emu/port/exportfs.c`)
- **Namespace and capability system** (`emu/port/pgrp.c`, `emu/port/devcap.c`)

## Security Measures

- Static analysis via CodeQL, cppcheck, and flawfinder runs on every push
- All GitHub Actions are pinned to specific commit SHAs
- Workflow tokens follow the principle of least privilege
