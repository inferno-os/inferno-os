; AMD64 assembly routines for Windows (MASM syntax)
;
; Windows x64 ABI:
;   Arguments: rcx, rdx, r8, r9  (then stack)
;   Return: rax (and rdx for 128-bit)
;   Caller-saved: rax, rcx, rdx, r8-r11
;   Callee-saved: rbx, rbp, rsi, rdi, r12-r15
;   Stack: 16-byte aligned before call
;   Shadow space: 32 bytes reserved by caller above return address
;
; Assembled with: ml64.exe /c asm-amd64-win.asm

EXTRN ExitProcess:PROC
EXTRN ExitThread:PROC

.code

;
; int _tas(int *p)
;
; Test-and-set: atomically exchange *p with 1, return old value.
; rcx = pointer to int
;
_tas PROC
	mov eax, 1
	xchg eax, DWORD PTR [rcx]
	ret
_tas ENDP

;
; unsigned long long umult(unsigned long long m1, unsigned long long m2, unsigned long long *hi)
;
; 64-bit multiply returning 128-bit result.
; rcx = m1, rdx = m2, r8 = pointer to store high 64 bits
; Returns: low 64 bits in rax
;
umult PROC
	mov rax, rcx		; m1
	mul rdx			; rdx:rax = rax * rdx
	mov QWORD PTR [r8], rdx	; store high bits
	ret			; low bits already in rax
umult ENDP

;
; void FPsave(void *p)
;
; Save floating-point state.
; On x86_64 Windows, FP context is handled per-thread by the OS.
; No-op stub for compatibility.
; rcx = pointer to save area (unused)
;
FPsave PROC
	ret
FPsave ENDP

;
; void FPrestore(void *p)
;
; Restore floating-point state.
; rcx = pointer to save area (unused)
;
FPrestore PROC
	ret
FPrestore ENDP

;
; uintptr getcallerpc(void *dummy)
;
; Return the return address of the caller.
; MSVC x64 with /O2 does not use frame pointers, so rbp is unreliable.
; Return our own return address (one level less than ideal, but safe).
; Used only for allocation debugging tags.
;
getcallerpc PROC
	mov rax, QWORD PTR [rsp]
	ret
getcallerpc ENDP

;
; void executeonnewstack(void *tos, void (*tramp)(void *arg), void *arg)
;
; Switch to a new stack and call the trampoline function.
; rcx = new stack top
; rdx = trampoline function
; r8  = argument to pass
;
; On Windows x64, the first argument to the tramp goes in rcx.
;
executeonnewstack PROC
	mov rsp, rcx		; switch to new stack
	mov rcx, r8		; arg becomes first argument to tramp (Windows ABI)
	xor rbp, rbp		; clear frame pointer to stop backtrace
	sub rsp, 32		; allocate shadow space for callee
	call rdx		; call tramp(arg)
	; if we return, exit the process
	xor ecx, ecx		; exit code 0
	call ExitProcess	; Windows API exit
executeonnewstack ENDP

;
; void unlockandexit(int *key)
;
; Unlock the key and exit the thread.
; rcx = pointer to lock
;
unlockandexit PROC
	mov DWORD PTR [rcx], 0	; unlock
	xor ecx, ecx		; exit code 0
	call ExitThread		; Windows API thread exit
unlockandexit ENDP

END
