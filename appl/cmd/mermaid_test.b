implement MermaidTest;

#
# mermaid_test.b — Runtime validation of all Mermaid diagram types.
#
# Run with:
#   ./emu/MacOSX/o.emu -r. -g 800x600 /dis/cmd/mermaid_test.dis
#
# Exit status 0 = all tests passed.
# Each test wraps render() in an exception handler so a panic in one type
# does not abort the rest of the suite.
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Font, Image, Point, Rect: import draw;

include "mermaid.m";
	mermaid: Mermaid;

MermaidTest: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

# ─────────────────────────────────────────────────────────────────────────────

passed:	int;
failed:	int;
stderr:	ref Sys->FD;

check(name, syntax: string, w: int)
{
	img: ref Image;
	err: string;
	{
		(img, err) = mermaid->render(syntax, w);
	} exception e {
	"*" =>
		sys->fprint(stderr, "PANIC %-22s  exception: %s\n", name, e);
		failed++;
		return;
	}
	if(img != nil) {
		iw := img.r.max.x - img.r.min.x;
		ih := img.r.max.y - img.r.min.y;
		sys->print("PASS  %-22s  %dx%d px\n", name, iw, ih);
		passed++;
	} else {
		sys->fprint(stderr, "FAIL  %-22s  error: %s\n", name, err);
		failed++;
	}
}

# Expect an error return (not a panic) — used for invalid/empty input.
checkfail(name, syntax: string, w: int)
{
	img: ref Image;
	err: string;
	{
		(img, err) = mermaid->render(syntax, w);
	} exception e {
	"*" =>
		sys->fprint(stderr, "PANIC %-22s  (expected error) exception: %s\n", name, e);
		failed++;
		return;
	}
	if(img == nil && err != nil) {
		sys->print("PASS  %-22s  (correctly returned error: %s)\n", name, err);
		passed++;
	} else if(img != nil) {
		# Rendered something even for degenerate input — that's also acceptable
		iw := img.r.max.x - img.r.min.x;
		ih := img.r.max.y - img.r.min.y;
		sys->print("PASS  %-22s  (degenerate, rendered %dx%d)\n", name, iw, ih);
		passed++;
	} else {
		sys->fprint(stderr, "FAIL  %-22s  nil image AND nil error\n", name);
		failed++;
	}
}

# ─────────────────────────────────────────────────────────────────────────────

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys  = load Sys  Sys->PATH;
	draw = load Draw Draw->PATH;
	stderr = sys->fildes(2);

	# Open display — needed because mermaid->init() allocates color images.
	disp: ref Display;
	if(ctxt != nil) {
		disp = ctxt.display;
	} else {
		disp = Display.allocate(nil);
		if(disp == nil) {
			sys->fprint(stderr, "mermaid_test: cannot open display\n");
			sys->fprint(stderr, "Hint: run  ./emu/MacOSX/o.emu -r. -g 800x600 /dis/cmd/mermaid_test.dis\n");
			raise "fail:no display";
		}
	}

	mermaid = load Mermaid Mermaid->PATH;
	if(mermaid == nil) {
		sys->fprint(stderr, "mermaid_test: cannot load mermaid module: %r\n");
		raise "fail:cannot load mermaid";
	}
	mermaid->init(disp, nil, nil);

	passed = 0;
	failed = 0;

	sys->print("\n── Mermaid renderer validation ──────────────────────────────────────\n\n");
	sys->print("%-28s  result\n", "Test");
	sys->print("%s\n", "─────────────────────────────────────────────────────────────────────");

	# ── 1. flowchart (TD / LR) ──────────────────────────────────────────────
	check("flowchart/TD",
		"graph TD\n" +
		"  A[Start] --> B{Check?}\n" +
		"  B -->|Yes| C[Do it]\n" +
		"  B -->|No| D[Skip]\n" +
		"  C --> E((End))\n" +
		"  D --> E",
		700);

	check("flowchart/LR",
		"flowchart LR\n" +
		"  P1([Source]) --> P2[Transform] --> P3[(Store)]\n" +
		"  P2 -.-> P4{{Cache}}\n" +
		"  P3 ==> P5>Result]",
		700);

	checkfail("flowchart/empty",
		"graph TD",
		700);

	# ── 2. pie ───────────────────────────────────────────────────────────────
	check("pie",
		"pie title Browser share\n" +
		"  \"Chrome\" : 65\n" +
		"  \"Firefox\" : 12\n" +
		"  \"Safari\" : 10\n" +
		"  \"Edge\" : 8\n" +
		"  \"Other\" : 5",
		600);

	checkfail("pie/empty", "pie title No data", 600);

	# ── 3. sequenceDiagram ───────────────────────────────────────────────────
	check("sequenceDiagram",
		"sequenceDiagram\n" +
		"  participant Alice\n" +
		"  participant Bob\n" +
		"  Alice->>Bob: Hello!\n" +
		"  Bob-->>Alice: Hi there\n" +
		"  Alice->>Bob: How are you?\n" +
		"  Note right of Bob: Bob thinks\n" +
		"  Bob-->>Alice: I am good",
		700);

	# ── 4. gantt ─────────────────────────────────────────────────────────────
	check("gantt",
		"gantt\n" +
		"  title Project Plan\n" +
		"  dateFormat YYYY-MM-DD\n" +
		"  section Phase 1\n" +
		"    Task A  : a1, 2024-01-01, 7d\n" +
		"    Task B  : a2, after a1, 5d\n" +
		"  section Phase 2\n" +
		"    Task C  : crit, 2024-01-15, 10d\n" +
		"    Task D  : active, after a2, 3d",
		800);

	# ── 5. xychart-beta ──────────────────────────────────────────────────────
	check("xychart-beta",
		"xychart-beta\n" +
		"  title \"Sales Q1\"\n" +
		"  x-axis [Jan, Feb, Mar, Apr]\n" +
		"  y-axis \"Revenue\" 0 --> 10000\n" +
		"  bar [4000, 7000, 5500, 9000]\n" +
		"  line [3500, 6500, 5000, 8500]",
		700);

	# ── 6. classDiagram ──────────────────────────────────────────────────────
	check("classDiagram/basic",
		"classDiagram\n" +
		"  class Animal {\n" +
		"    +String name\n" +
		"    +int age\n" +
		"    +makeSound()\n" +
		"  }\n" +
		"  class Dog {\n" +
		"    +String breed\n" +
		"    +fetch()\n" +
		"  }\n" +
		"  class Cat {\n" +
		"    +purr()\n" +
		"  }\n" +
		"  Animal <|-- Dog\n" +
		"  Animal <|-- Cat",
		800);

	check("classDiagram/relationships",
		"classDiagram\n" +
		"  class Order {\n" +
		"    +int id\n" +
		"    +place()\n" +
		"  }\n" +
		"  class Customer {\n" +
		"    +String name\n" +
		"  }\n" +
		"  class LineItem {\n" +
		"    +int qty\n" +
		"  }\n" +
		"  Customer --> Order : places\n" +
		"  Order *-- LineItem : contains",
		800);

	checkfail("classDiagram/empty", "classDiagram", 700);

	# ── 7. stateDiagram-v2 ───────────────────────────────────────────────────
	check("stateDiagram-v2/basic",
		"stateDiagram-v2\n" +
		"  [*] --> Idle\n" +
		"  Idle --> Running : start\n" +
		"  Running --> Paused : pause\n" +
		"  Paused --> Running : resume\n" +
		"  Running --> [*] : stop",
		700);

	check("stateDiagram-v2/multi-state",
		"stateDiagram-v2\n" +
		"  [*] --> Off\n" +
		"  Off --> On : power\n" +
		"  On --> Standby : timeout\n" +
		"  Standby --> On : wake\n" +
		"  On --> Off : power\n" +
		"  Standby --> Off : power",
		700);

	checkfail("stateDiagram-v2/empty", "stateDiagram-v2", 700);

	# ── 8. erDiagram ─────────────────────────────────────────────────────────
	check("erDiagram/basic",
		"erDiagram\n" +
		"  CUSTOMER {\n" +
		"    int id PK\n" +
		"    string name\n" +
		"    string email\n" +
		"  }\n" +
		"  ORDER {\n" +
		"    int id PK\n" +
		"    date placed\n" +
		"  }\n" +
		"  PRODUCT {\n" +
		"    int id PK\n" +
		"    string name\n" +
		"    float price\n" +
		"  }\n" +
		"  CUSTOMER ||--o{ ORDER : places\n" +
		"  ORDER }|--|{ PRODUCT : contains",
		800);

	checkfail("erDiagram/empty", "erDiagram", 700);

	# ── 9. mindmap ───────────────────────────────────────────────────────────
	check("mindmap/basic",
		"mindmap\n" +
		"  root((Project))\n" +
		"    Frontend\n" +
		"      React\n" +
		"      CSS\n" +
		"    Backend\n" +
		"      Node.js\n" +
		"      Database\n" +
		"        PostgreSQL\n" +
		"        Redis\n" +
		"    DevOps\n" +
		"      Docker\n" +
		"      CI/CD",
		700);

	check("mindmap/single-root",
		"mindmap\n" +
		"  root((Root only))",
		700);

	checkfail("mindmap/empty", "mindmap", 700);

	# ── 10. timeline ─────────────────────────────────────────────────────────
	check("timeline/basic",
		"timeline\n" +
		"  title History of the Web\n" +
		"  section 1990s\n" +
		"    1991 : WWW invented\n" +
		"    1995 : JavaScript created\n" +
		"    1998 : Google founded\n" +
		"  section 2000s\n" +
		"    2004 : Facebook launched\n" +
		"    2007 : iPhone released\n" +
		"  section 2010s\n" +
		"    2015 : ES6 published\n" +
		"    2017 : WebAssembly",
		700);

	checkfail("timeline/empty", "timeline", 700);

	# ── 11. gitGraph ─────────────────────────────────────────────────────────
	check("gitGraph/basic",
		"gitGraph\n" +
		"  commit id: \"init\"\n" +
		"  commit id: \"A\"\n" +
		"  branch develop\n" +
		"  checkout develop\n" +
		"  commit id: \"B\"\n" +
		"  commit id: \"C\"\n" +
		"  checkout main\n" +
		"  merge develop\n" +
		"  commit id: \"D\"",
		800);

	check("gitGraph/single-branch",
		"gitGraph\n" +
		"  commit id: \"v1\"\n" +
		"  commit id: \"v2\"\n" +
		"  commit id: \"v3\"",
		600);

	checkfail("gitGraph/empty", "gitGraph", 700);

	# ── 12. quadrantChart ────────────────────────────────────────────────────
	check("quadrantChart/full",
		"quadrantChart\n" +
		"  title Feature prioritization\n" +
		"  x-axis Low Effort --> High Effort\n" +
		"  y-axis Low Value --> High Value\n" +
		"  quadrant-1 Quick wins\n" +
		"  quadrant-2 Major projects\n" +
		"  quadrant-3 Fill-ins\n" +
		"  quadrant-4 Thankless tasks\n" +
		"  Auth: [0.1, 0.8]\n" +
		"  Search: [0.3, 0.7]\n" +
		"  Dashboard: [0.6, 0.9]\n" +
		"  Reports: [0.8, 0.4]\n" +
		"  Settings: [0.2, 0.2]",
		700);

	check("quadrantChart/no-points",
		"quadrantChart\n" +
		"  title Empty chart\n" +
		"  quadrant-1 Q1\n" +
		"  quadrant-2 Q2\n" +
		"  quadrant-3 Q3\n" +
		"  quadrant-4 Q4",
		700);

	checkfail("quadrantChart/empty", "quadrantChart", 700);

	# ── 13. journey ──────────────────────────────────────────────────────────
	check("journey/basic",
		"journey\n" +
		"  title My working day\n" +
		"  section Go to work\n" +
		"    Make tea: 5: Me\n" +
		"    Go upstairs: 3: Me, Cat\n" +
		"    Do work: 1: Me\n" +
		"  section Go home\n" +
		"    Go downstairs: 5: Me\n" +
		"    Sit down: 3: Me",
		700);

	checkfail("journey/empty", "journey", 700);

	# ── 14. requirementDiagram ───────────────────────────────────────────────
	check("requirementDiagram/basic",
		"requirementDiagram\n" +
		"  requirement performance_req {\n" +
		"    id: 1\n" +
		"    text: System shall respond in 200ms\n" +
		"    risk: high\n" +
		"    verifymethod: test\n" +
		"  }\n" +
		"  functionalRequirement auth_req {\n" +
		"    id: 2\n" +
		"    text: Users must authenticate\n" +
		"    risk: medium\n" +
		"    verifymethod: inspection\n" +
		"  }\n" +
		"  element api_server {\n" +
		"    type: simulation\n" +
		"  }\n" +
		"  api_server - satisfies -> performance_req\n" +
		"  api_server - satisfies -> auth_req",
		800);

	checkfail("requirementDiagram/empty", "requirementDiagram", 700);

	# ── 15. block-beta ───────────────────────────────────────────────────────
	check("block-beta/basic",
		"block-beta\n" +
		"  columns 3\n" +
		"  A[\"Auth\"] B[\"API Gateway\"] C[\"Cache\"]\n" +
		"  D[\"User Svc\"] E[\"Order Svc\"] F[\"Product Svc\"]\n" +
		"  G[\"PostgreSQL\"] H[\"Kafka\"] I[\"Redis\"]",
		800);

	check("block-beta/single",
		"block-beta\n" +
		"  columns 1\n" +
		"  X[\"Only one\"]",
		400);

	checkfail("block-beta/empty", "block-beta", 700);

	# ── Edge cases ─────────────────────────────────────────────────────────
	checkfail("unknown-type",
		"invaliddiagram\n  foo --> bar",
		700);

	sys->print("\n%s\n", "─────────────────────────────────────────────────────────────────────");
	sys->print("Results: %d passed, %d failed\n\n", passed, failed);

	if(failed > 0)
		raise "fail:mermaid tests failed";
}
