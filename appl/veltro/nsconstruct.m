#
# nsconstruct.m - Namespace construction for Veltro agents (v3)
#
# Security Model (v3): FORKNS + bind-replace
#   Fork parent namespace, then restrict directories via bind-replace (MREPL).
#   restrictdir() replaces a directory's contents with only allowed items.
#   This is an allowlist operation — anything not explicitly placed is invisible.
#
# Capability attenuation is natural: children fork an already-restricted
# namespace and can only narrow further.
#
# Replaces v2's NEWNS + sandbox directory construction with zero file copying,
# no sandbox directory management, and no NEWNS bootstrap problem.
#

NsConstruct: module {
	PATH: con "/dis/veltro/nsconstruct.dis";

	# LLM configuration for a child agent
	LLMConfig: adt {
		model:       string;   # Model name (e.g., "haiku", "sonnet", "opus")
		temperature: real;     # 0.0 - 2.0
		system:      string;   # System prompt (parent-controlled)
		thinking:    int;      # Thinking tokens: 0=off, -1=max, >0=budget
	};

	# MCP provider configuration (for mc9p integration)
	MCProvider: adt {
		name:     string;          # Provider name ("http", "fs", "search")
		domains:  list of string;  # Domains to grant within provider
		netgrant: int;             # 1 = provider has /net access
	};

	# Capabilities to grant to an agent
	Capabilities: adt {
		tools:       list of string;       # Tool names to include ("read", "list")
		paths:       list of string;       # File paths to expose
		shellcmds:   list of string;       # Shell commands for exec — if non-nil, sh.dis + these are allowed
		llmconfig:   ref LLMConfig;        # Child's LLM settings
		fds:         list of int;          # Explicit FD keep-list
		mcproviders: list of ref MCProvider;  # mc9p providers to spawn
		memory:      int;                  # 1 = enable agent memory
		xenith:      int;                  # 1 = grant /chan (Xenith 9P) access
	};

	# Initialize the module
	init: fn();

	# Restrict a directory to only the allowed entries.
	# Creates shadow dir, binds allowed items into it, replaces target with MREPL.
	# writable=1 adds Sys->MCREATE to the final bind (needed for /tmp).
	# writable=0 for all read-only directories (/dis, /lib, /dev, /n, /).
	# Items not in allowed list become invisible after the bind-replace.
	# Returns nil on success, error string on failure.
	restrictdir: fn(target: string, allowed: list of string, writable: int): string;

	# Apply full namespace restriction policy using restrictdir() calls
	# Restricts /dis, /dev, /n, /lib, /tmp based on capabilities
	# Returns nil on success, error string on failure
	restrictns: fn(caps: ref Capabilities): string;

	# Verify namespace matches expected security policy
	# Reads /prog/$pid/ns and checks for dangerous paths
	# expected: list of paths that should be accessible
	# Returns nil on success, violation description on failure
	verifyns: fn(expected: list of string): string;

	# Emit audit log of namespace restriction operations
	# Writes to /tmp/veltro/.ns/audit/{id}.ns
	emitauditlog: fn(id: string, ops: list of string);
};
