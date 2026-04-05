# 9P Data Format Conventions

A guide for developers writing 9P file servers in InferNode.


## The Rule

Data served through 9P filesystems is plain text. Fields are
space-separated. Records are one per line. Complex structures
are decomposed into the directory hierarchy.


## Why Not JSON

JSON is the default instinct for structured data. It is wrong
here. The reasons are architectural, not aesthetic.

**Simplicity.** A line of space-separated fields is the simplest
possible representation of a record. It requires no grammar, no
escaping rules, no nesting, no closing delimiters. The cognitive
load of reading `37.7749 -122.4194 San_Francisco 2025-02-15T14:32:00Z`
is zero. The cognitive load of reading the equivalent JSON is not
zero — your eye has to parse braces, colons, quotes, and commas
to find the four values. Simplicity is not a preference in Plan 9.
It is a design principle. Every layer of unnecessary syntax is a
layer of unnecessary complexity in every tool that touches the data.

**Clarity.** Text lines are human-readable at every point in the
system. `cat /n/sensors/temperature` shows a number. `cat /n/alerts`
shows one alert per line. There is nothing to decode, no structure
to navigate, no keys to look up. The data is right there. This
matters for debugging, for auditing, for understanding what a
system is doing at 3 AM when something is wrong. JSON forces you
to visually parse structure before you can see values.

**Tool composition.** The entire Plan 9 and Inferno tool ecosystem
assumes text lines. Pipes, `grep`, `awk`, `sed`, `sort`, `wc`,
`tail`, `head` — they all operate on lines and fields. When a 9P
server emits one record per line, the full power of this ecosystem
is immediately available.

```
cat /n/sensors/readings | grep temperature | wc -l
cat /n/fleet/vehicles | awk '{print $1, $4}' | sort
```

JSON breaks this. A JSON array is not a sequence of lines — it is
a single structure with internal delimiters. Pipelines cannot
operate on it without a dedicated parser as an intermediary. The
tool ecosystem becomes useless, and every consumer must import
a JSON library instead of calling `tokenize`.

**Parseability.** `sys->tokenize(line, " \t")` splits a text line
into fields in one call. No module to load, no buffer to create,
no error tree to walk. A display module that reads sensor data
every two seconds does one `read` and one `tokenize`. With JSON,
it loads a parser module, allocates an I/O buffer, calls `readjson`,
checks for parse errors, navigates a tagged value tree with `get`
calls, and pick-matches each value to extract its type. This is
not a matter of convenience — it is a matter of how many things
can go wrong between reading bytes and having values.

**Consistency.** Every kernel interface in Plan 9 and Inferno uses
text: `/proc/*/status` (space-separated fields), `/dev/sysstat`
(one line per processor, space-separated numbers), `/dev/time`
(space-separated values), `/net/tcp/*/status` (text lines). If
your 9P server emits JSON, it is the odd one out. Every consumer
needs special-case code. Every tool that works on other parts of
the namespace stops working on yours.

**Agents.** AI agents read and write files. They understand text
natively — it is their primary medium. An agent reasoning about
the line `AAPL long 0.85 sentiment` can parse it instantly. An
agent reasoning about `{"asset":"AAPL","direction":"long",
"confidence":0.85,"signal_type":"sentiment"}` must first parse
the JSON structure, then extract the same four values. LLMs are
measurably worse at extracting values from JSON than from plain
text — the syntactic overhead (braces, quotes, colons, commas)
consumes context and introduces extraction errors that do not
occur with space-separated fields. In a system where agents are
first-class consumers of the namespace, the data format must be
optimised for how agents actually process text.

JSON is appropriate at system boundaries — when talking to
external HTTP APIs, REST services, or web browsers. Inside the
9P namespace, text is the universal interface.


## Conventions

These conventions are derived from the Plan 9 kernel interfaces
documented in proc(3), cons(3), and the Plan 9 papers from
Bell Labs.

### Single values: one file per datum

When a piece of data is a single value (a number, a status string,
a name), it gets its own file. The file contains the value as text,
optionally followed by a newline.

Sensor network:
```
/n/sensors/temperature     →  22.5
/n/sensors/humidity        →  0.65
/n/sensors/status          →  normal
```

Fleet tracking:
```
/n/fleet/vehicles/truck-7/lat   →  37.7749
/n/fleet/vehicles/truck-7/lon   →  -122.4194
/n/fleet/vehicles/truck-7/speed →  65.2
```

Trading system:
```
/n/portfolio/cash           →  125000.00
/n/portfolio/total_value    →  1250000.50
/n/portfolio/defense/status →  normal
```

This is the most Plan 9 pattern. The directory hierarchy is the
structure. The file content is the value. No parsing required
beyond reading the bytes.

### Records: one per line, fields space-separated

When a file contains multiple records (a list of readings, a log
of events), each record is one line. Fields within a record are
separated by spaces.

Geospatial observations:
```
/n/observations:
sta-001 37.7749 -122.4194 22.5 0.65 clear 2025-02-15T14:32:00Z
sta-002 34.0522 -118.2437 28.1 0.42 clear 2025-02-15T14:32:00Z
sta-003 40.7128 -74.0060 -2.3 0.78 snow 2025-02-15T14:32:00Z
```

Network events:
```
/n/firewall/log:
a]1e8400 10.0.1.15 10.0.2.30 443 allow 2025-02-15T14:32:00Z
b72e8401 192.168.1.5 10.0.1.15 22 deny 2025-02-15T14:33:12Z
c83e8402 10.0.1.20 8.8.8.8 53 allow 2025-02-15T14:33:15Z
```

Trading signals:
```
/n/signals:
550e8400 AAPL long 0.85 sentiment 2025-02-15T14:32:00Z
660e8401 TSLA short 0.72 technical 2025-02-15T14:33:00Z
```

The reader uses `sys->tokenize(line, " \t")` to split each line.
Field order is fixed and documented. There is no header line — the
format is part of the interface specification, not embedded in
the data.

### Field ordering

Fields are ordered from most important to least important, left
to right. The first field is typically the key or identifier. This
makes `grep` and `awk '{print $1}'` useful without knowing the
full format.

### Numeric formatting

Numbers are formatted as decimal text. Floats use a fixed number
of decimal places appropriate to their precision. There is no
requirement for fixed-width padding in application-level 9P
servers (the kernel convention of 11-digit blank-padded numbers
is for kernel interfaces where fixed-width simplifies parsing at
interrupt time).

```
22.5          temperature (1 decimal place)
37.774900     latitude (6 decimal places)
0.85          confidence (2 decimal places)
125000.00     currency (2 decimal places)
100           integer count
```

### Key-value data: use the directory

Do not put key-value pairs in a single file. Use the directory
structure. Each key becomes a file (or subdirectory) whose
content is the value.

Wrong:
```
/n/sensors/station-1  →  {"temperature": 22.5, "humidity": 0.65, "status": "normal"}
```

Right:
```
/n/sensors/station-1/temperature  →  22.5
/n/sensors/station-1/humidity     →  0.65
/n/sensors/station-1/status       →  normal
```

If the values are logically grouped, use a subdirectory. The
hierarchy is the schema.

### Lists of names: one per line

Simple lists (identifiers, labels, available resources) are one
item per line.

```
/n/fleet/drivers:
Alice Chen
Bob Martinez
Carol Okafor
```

### Timestamps

Use RFC 3339 format (`2025-02-15T14:32:00Z`). It is text,
it sorts lexicographically, and it is unambiguous. It contains
no spaces, so it works as a single field in a space-separated
record.

### Control files

Files that accept commands (not just data) follow the Plan 9
`ctl` convention. Commands are text strings written to the file.

```
echo alarm > /n/sensors/station-1/status
echo 30 > /n/sensors/station-1/poll_interval
echo rebalance > /n/portfolio/ctl
```

### Writable data files

When a file is writable, the write format matches the read format.
If reading a status file returns `normal`, then writing `alarm` to
it changes the status. No wrapper syntax.

### What to do when fields contain spaces

If a field may contain spaces (e.g., a place name like
"San Francisco"), there are two options:

1. **Quote the field.** Use Plan 9 quoting conventions (single
   quotes with doubled internal quotes). `sys->tokenize` handles
   quoted fields automatically.

2. **Put it in its own file.** If the value is complex enough to
   need quoting, it probably deserves its own file in the hierarchy.

Prefer option 2. Quoting adds parsing complexity.


## Summary

| Pattern | Format |
|---------|--------|
| Single value | Own file, value as text |
| Multiple records | One per line, space-separated fields |
| Key-value data | Directory hierarchy |
| Simple list | One item per line |
| Numbers | Decimal text, appropriate precision |
| Timestamps | RFC 3339 |
| Commands | Text written to ctl files |
| Fields with spaces | Own file, or Plan 9 quoting |
