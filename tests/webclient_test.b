implement WebclientTest;

include "sys.m";
	sys: Sys;

include "draw.m";

include "testing.m";
	testing: Testing;
	T: import testing;

include "webclient.m";
	webclient: Webclient;
	Response, Header: import webclient;

WebclientTest: module
{
	init: fn(nil: ref Draw->Context, args: list of string);
};

SRCFILE: con "/tests/webclient_test.b";

passed := 0;
failed := 0;
skipped := 0;

run(name: string, testfn: ref fn(t: ref T))
{
	t := testing->newTsrc(name, SRCFILE);
	{
		testfn(t);
	} exception {
	"fail:fatal" =>
		;
	"fail:skip" =>
		;
	* =>
		t.failed = 1;
	}

	if(testing->done(t))
		passed++;
	else if(t.skipped)
		skipped++;
	else
		failed++;
}

testHttpsGet(t: ref T)
{
	(resp, err) := webclient->get("https://example.com");
	if(err != nil) {
		t.skip("network: " + err);
		return;
	}
	t.assert(resp != nil, "response not nil");
	t.asserteq(resp.statuscode, 200, "status code");
	t.assert(resp.body != nil && len resp.body > 0, "body not empty");
	t.log("body length: " + string len resp.body);
}

testRedirect(t: ref T)
{
	# HTTP to HTTPS redirect
	(resp, err) := webclient->get("http://example.com");
	if(err != nil) {
		t.skip("network: " + err);
		return;
	}
	t.assert(resp != nil, "response not nil");
	# example.com may or may not redirect; just check we got a response
	t.assert(resp.statuscode == 200 || resp.statuscode == 301 || resp.statuscode == 302,
		"reasonable status: " + string resp.statuscode);
}

testTlsDial(t: ref T)
{
	(fd, err) := webclient->tlsdial("tcp!example.com!443", "example.com");
	if(err != nil) {
		t.skip("network: " + err);
		return;
	}
	t.assert(fd != nil, "fd not nil");

	# Send a minimal HTTP request
	req := array of byte "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n";
	n := sys->write(fd, req, len req);
	t.assert(n == len req, "write request");

	buf := array [1024] of byte;
	n = sys->read(fd, buf, len buf);
	t.assert(n > 0, "read response");
	respstr := string buf[:n];
	t.log("response start: " + respstr[:80]);
	t.assert(len respstr > 12, "response has content");
}

testPost(t: ref T)
{
	body := array of byte "test=hello";
	(resp, err) := webclient->post("https://httpbin.org/post",
		"application/x-www-form-urlencoded", body);
	if(err != nil) {
		t.skip("network: " + err);
		return;
	}
	t.assert(resp != nil, "response not nil");
	t.asserteq(resp.statuscode, 200, "status code");
	t.assert(resp.body != nil && len resp.body > 0, "body not empty");
}

testHeaderLookup(t: ref T)
{
	hdrs := Header("Content-Type", "text/html") ::
		Header("X-Custom", "hello") :: nil;
	resp := ref Response(200, "HTTP/1.1 200 OK", hdrs, nil);
	t.assertseq(resp.hdrval("Content-Type"), "text/html", "Content-Type");
	t.assertseq(resp.hdrval("content-type"), "text/html", "case insensitive");
	t.assertseq(resp.hdrval("X-Custom"), "hello", "custom header");
	t.assertnil(resp.hdrval("Missing"), "missing header is nil");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	testing = load Testing Testing->PATH;

	if(testing == nil) {
		sys->fprint(sys->fildes(2), "cannot load testing module: %r\n");
		raise "fail:cannot load testing";
	}

	testing->init();

	for(a := args; a != nil; a = tl a) {
		if(hd a == "-v")
			testing->verbose(1);
	}

	webclient = load Webclient Webclient->PATH;
	if(webclient == nil) {
		sys->fprint(sys->fildes(2), "cannot load webclient: %r\n");
		raise "fail:cannot load webclient";
	}
	err := webclient->init();
	if(err != nil) {
		sys->fprint(sys->fildes(2), "webclient init: %s\n", err);
		raise "fail:webclient init";
	}

	# Non-network tests first
	run("HeaderLookup", testHeaderLookup);

	# Network tests (may skip if no connectivity)
	run("HttpsGet", testHttpsGet);
	run("Redirect", testRedirect);
	run("TlsDial", testTlsDial);
	run("Post", testPost);

	if(testing->summary(passed, failed, skipped) > 0)
		raise "fail:tests failed";
}
