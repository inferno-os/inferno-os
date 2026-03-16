# Veltro Message Layer — Implementation Plan

## Architecture Overview

The message layer gives Veltro a **sensory nervous system**: the ability to receive
external stimuli (email, messages, signals, sensor data) and respond through the
same channel. It follows Inferno's "everything is a file" philosophy.

### Core Abstraction: Message Source (`msgsrc.m`)

A **Message Source** is any bidirectional channel that produces and consumes
messages. Email, WhatsApp, Telegram, trading signals, sensor readings — all
implement the same interface. The agent never knows or cares about the underlying
protocol.

```
MsgSrc: module {
    init:       fn(cfg: string): string;
    name:       fn(): string;
    watch:      fn(incoming: chan of ref Msg): string;   # blocks, pushes new msgs
    stop:       fn();
    send:       fn(m: ref Msg): string;                 # reply through same channel
    status:     fn(): string;
};

Msg: adt {
    id:         string;         # unique message ID
    source:     string;         # "email", "telegram", etc.
    sender:     string;         # who sent it
    recipient:  string;         # who it's to
    subject:    string;         # subject/topic (may be nil)
    body:       string;         # message content
    timestamp:  int;            # epoch seconds
    headers:    list of (string, string);  # key-value metadata
    replyto:    string;         # message ID this replies to (threading)
    channel:    string;         # reply channel info (email addr, chat ID, etc.)
    urgency:    int;            # 0=unknown, set by classifier
};
```

### 9P Presentation: `msg9p.b`

Mounts at `/n/msg/` and exposes all sources uniformly:

```
/n/msg/
├── sources           (r)    list of registered source names
├── ctl               (rw)   "register email /dis/veltro/sources/email.dis"
├── notify            (r)    BLOCKS until notification; returns msg summary
├── email/
│   ├── status        (r)    "connected 142 messages 3 unseen"
│   ├── ctl           (rw)   "connect", "disconnect", "idle"
│   ├── new           (r)    BLOCKS until new message; returns msg ID
│   ├── {id}/
│   │   ├── headers   (r)    From/To/Subject/Date as key: value lines
│   │   ├── body      (r)    message body text
│   │   ├── raw       (r)    raw message (for debugging)
│   │   ├── ctl       (rw)   "reply <body>", "forward <to>", "archive", "flag", "delete"
│   │   └── status    (r)    "new"|"classified"|"drafted"|"sent"|"archived"
│   └── outbox/
│       ├── {id}/
│       │   ├── headers (rw)  compose headers
│       │   ├── body    (rw)  compose body
│       │   └── ctl     (rw)  "send", "discard"
│       └── new       (rw)   create new outgoing message
├── telegram/
│   └── ...           (same structure)
└── ...               (any future source)
```

Key design: reading `/n/msg/notify` **blocks** until any source has a notification.
This is how repl.b integrates — it adds this to its `alt` alongside user input.

### Message Watcher Daemon: `msgwatch.b`

A persistent daemon that:
1. Monitors all registered sources via their `watch()` channels
2. Classifies incoming messages using a lightweight LLM call + policy
3. Takes action based on classification tier
4. Writes notifications to `/n/msg/notify` for the Meta Agent

Classification tiers (from policy):
- **ignore**: junk/spam — no action, mark as read
- **decline**: honest solicitation — draft polite refusal, queue in outbox
- **defer**: non-urgent — draft reply, save, don't interrupt
- **notify**: urgent — draft reply AND interrupt the user

### Policy System

Policy files in `/lib/veltro/policies/`:

```
# /lib/veltro/policies/secretary.txt
You are classifying an incoming message for the user.

Given the message below, classify it into exactly one tier:
- IGNORE: spam, marketing, newsletters the user didn't ask for, automated notifications
- DECLINE: legitimate solicitations, meeting requests the user would decline, cold outreach
- DEFER: legitimate messages that need a reply but aren't time-sensitive
- NOTIFY: urgent messages requiring immediate attention (from known contacts about
  active projects, emergencies, time-sensitive decisions)

Respond with:
TIER: <tier>
REASON: <one sentence>
DRAFT: <suggested reply if tier is DECLINE or DEFER or NOTIFY, omit for IGNORE>
```

### Integration with Meta Agent

When `msgwatch` classifies a message as NOTIFY:
1. Writes to `/n/msg/notify`: `"URGENT email from <sender>: <subject>"`
2. `repl.b` receives this in its main alt loop
3. Presents it to the user in the Xenith window (or terminal)
4. Meta Agent can then use the `mail` tool to read the full message and respond

For DECLINE/DEFER, msgwatch handles it autonomously — drafts are queued in the
source's outbox for user review.

---

## Implementation Steps

### Phase 1: Module Interface + Message ADT
- **Create `module/msgsrc.m`** — Message Source interface and Msg ADT
- This is the contract all sources implement

### Phase 2: Email Source (`appl/veltro/sources/email.b`)
- Implements MsgSrc interface
- Wraps existing `imap.b` (IDLE for push) and `smtp.b` (for sending)
- `watch()` uses imap->idle() to get push notifications, then fetches new messages
- `send()` uses smtp for replies
- Config: server, mailbox, credentials (via factotum)

### Phase 3: Message 9P Server (`appl/veltro/msg9p.b`)
- Styxserver-based 9P file server
- Mounts at `/n/msg/`
- Manages source registration, per-message files, blocking reads on `notify`/`new`
- Follows tools9p.b pattern (Navigator + serveloop)

### Phase 4: Message Watcher (`appl/veltro/msgwatch.b`)
- Daemon that receives messages from all sources
- Uses lightweight LLM session for classification (via /n/llm)
- Reads policy from `/lib/veltro/policies/secretary.txt`
- Routes messages to appropriate action tier
- Writes notifications for NOTIFY tier

### Phase 5: REPL Integration
- Modify `repl.b` to watch `/n/msg/notify` in its alt loop
- When notification arrives, inject it into conversation
- Meta Agent sees it as a system message and can act on it

### Phase 6: Policy + Agent Configuration
- **`lib/veltro/policies/secretary.txt`** — default secretary policy
- **`lib/veltro/agents/secretary.txt`** — secretary agent behavior prompt
- **`lib/veltro/tools/msgsrc.txt`** — tool documentation for message source

### Phase 7: Mail Tool Enhancement
- Add `mail watch` and `mail idle` commands to existing tool
- Add `mail reply <N> <body>` (proper In-Reply-To threading)
- Connect tool to msg9p for unified access

---

## File Manifest

### New Files
| File | Purpose |
|------|---------|
| `module/msgsrc.m` | Message Source interface + Msg ADT |
| `appl/veltro/sources/email.b` | Email MsgSrc (IMAP IDLE + SMTP) |
| `appl/veltro/msg9p.b` | 9P server for `/n/msg/` |
| `appl/veltro/msgwatch.b` | Watcher daemon + classifier |
| `lib/veltro/policies/secretary.txt` | Default secretary classification policy |
| `lib/veltro/agents/secretary.txt` | Secretary agent behavior prompt |
| `lib/veltro/tools/msgsrc.txt` | Message source tool documentation |

### Modified Files
| File | Change |
|------|--------|
| `appl/veltro/repl.b` | Add `/n/msg/notify` to alt loop |
| `appl/veltro/tools/mail.b` | Add watch/reply commands |
| `lib/veltro/meta.txt` | Add message handling delegation guidance |

---

## Design Principles

1. **Protocol-agnostic**: MsgSrc interface doesn't know about IMAP, HTTP, or WebSocket.
   Adding Telegram = implementing one module, registering it with msg9p.

2. **Filesystem-native**: Messages are files. Reading `/n/msg/email/42/body` gets you
   the email body. Writing `"reply Hello"` to `/n/msg/email/42/ctl` sends a reply.
   No special APIs — just read/write.

3. **Namespace = capability**: An agent granted `/n/msg/email` can read email.
   One without it cannot. No ACL needed.

4. **Push, not poll**: Sources use blocking channels (IMAP IDLE, WebSocket, etc.).
   The watcher blocks on channels, not sleep loops.

5. **Policy-driven autonomy**: The LLM classifies messages against a user-defined
   policy. The user controls the policy, not the code. Change the prompt,
   change the behavior.

6. **Bidirectional by design**: Every source that can receive can also send.
   The `send()` function and outbox filesystem are part of the core interface,
   not afterthoughts.
