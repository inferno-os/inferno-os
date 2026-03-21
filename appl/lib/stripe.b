implement Stripe;

#
# Stripe API client.
#
# Uses Stripe's REST API with Basic auth (secret key as username).
# All requests go to https://api.stripe.com/v1/
#
# API key is provided at init time (retrieved from factotum by caller).
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "bufio.m";
	bufio: Bufio;

include "json.m";
	json: JSON;
	JValue: import json;

include "encoding.m";
	base64: Encoding;

include "webclient.m";
	webclient: Webclient;
	Header, Response: import webclient;

include "stripe.m";

APIBASE: con "https://api.stripe.com/v1";

secretkey: string;

init(apikey: string): string
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return "cannot load Sys";
	kr = load Keyring Keyring->PATH;
	if(kr == nil)
		return "cannot load Keyring";
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		return "cannot load Bufio";
	json = load JSON JSON->PATH;
	if(json == nil)
		return "cannot load JSON";
	json->init(bufio);
	base64 = load Encoding Encoding->BASE64PATH;
	if(base64 == nil)
		return "cannot load base64";
	webclient = load Webclient Webclient->PATH;
	if(webclient == nil)
		return "cannot load Webclient";
	err := webclient->init();
	if(err != nil)
		return "webclient: " + err;

	if(apikey == nil || apikey == "")
		return "empty API key";
	secretkey = apikey;
	return nil;
}

#
# Create a PaymentIntent.
# POST /v1/payment_intents
# Body: amount=NNN&currency=usd&description=...
#
createpayment(amount: int, currency: string, description: string): (string, string)
{
	if(secretkey == "")
		return (nil, "stripe not initialized");

	body := "amount=" + string amount +
		"&currency=" + currency +
		"&description=" + urlencode(description) +
		"&automatic_payment_methods[enabled]=true";

	(resp, err) := apipost("/payment_intents", body);
	if(err != nil)
		return (nil, err);

	jv := parsejson(string resp.body);
	if(jv == nil)
		return (nil, "invalid JSON response");

	# Check for error
	errobj := jv.get("error");
	if(errobj != nil && errobj.isobject())
		return (nil, "stripe: " + getstr(errobj, "message"));

	id := getstr(jv, "id");
	if(id == "")
		return (nil, "no payment intent id in response");

	return (id, nil);
}

#
# Get account balance.
# GET /v1/balance
#
balance(): (string, string)
{
	if(secretkey == "")
		return (nil, "stripe not initialized");

	(resp, err) := apiget("/balance");
	if(err != nil)
		return (nil, err);

	jv := parsejson(string resp.body);
	if(jv == nil)
		return (nil, "invalid JSON response");

	# Parse available balance
	avail := jv.get("available");
	if(avail == nil || !avail.isarray())
		return ("0", nil);

	result := "";
	pick a := avail {
	Array =>
		for(i := 0; i < len a.a; i++) {
			b := a.a[i];
			if(b != nil && b.isobject()) {
				amt := getstr(b, "amount");
				cur := getstr(b, "currency");
				if(result != "")
					result += ", ";
				result += amt + " " + cur;
			}
		}
	}

	if(result == "")
		result = "0";
	return (result, nil);
}

#
# List recent charges.
# GET /v1/charges?limit=N
#
recent(count: int): (string, string)
{
	if(secretkey == "")
		return (nil, "stripe not initialized");

	(resp, err) := apiget("/charges?limit=" + string count);
	if(err != nil)
		return (nil, err);

	jv := parsejson(string resp.body);
	if(jv == nil)
		return (nil, "invalid JSON response");

	data := jv.get("data");
	if(data == nil || !data.isarray())
		return ("no charges", nil);

	result := "";
	pick a := data {
	Array =>
		for(i := 0; i < len a.a; i++) {
			ch := a.a[i];
			if(ch != nil && ch.isobject()) {
				id := getstr(ch, "id");
				amt := getstr(ch, "amount");
				cur := getstr(ch, "currency");
				status := getstr(ch, "status");
				result += id + " " + amt + " " + cur + " " + status + "\n";
			}
		}
	}

	if(result == "")
		result = "no charges\n";
	return (result, nil);
}

#
# HTTP helpers
#

apiget(path: string): (ref Response, string)
{
	url := APIBASE + path;
	hdrs := authheader() :: nil;
	return webclient->request("GET", url, hdrs, nil);
}

apipost(path: string, body: string): (ref Response, string)
{
	url := APIBASE + path;
	hdrs :=
		authheader() ::
		Header("Content-Type", "application/x-www-form-urlencoded") ::
		nil;
	return webclient->request("POST", url, hdrs, array of byte body);
}

# Stripe uses Basic auth with secret key as username, empty password
authheader(): Header
{
	creds := secretkey + ":";
	encoded := base64->enc(array of byte creds);
	return Header("Authorization", "Basic " + encoded);
}

#
# Utility helpers
#

parsejson(s: string): ref JValue
{
	iob := bufio->sopen(s);
	if(iob == nil)
		return nil;
	(jv, nil) := json->readjson(iob);
	return jv;
}

getstr(jv: ref JValue, field: string): string
{
	v := jv.get(field);
	if(v == nil)
		return "";
	if(v.isstring()) {
		pick sv := v {
		String =>
			return sv.s;
		}
	}
	if(v.isint()) {
		pick iv := v {
		Int =>
			return string iv.value;
		}
	}
	return "";
}

# Simple URL encoding for Stripe form bodies
urlencode(s: string): string
{
	result := "";
	for(i := 0; i < len s; i++) {
		c := s[i];
		if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		   (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~')
			result[len result] = c;
		else if(c == ' ')
			result += "+";
		else
			result += sys->sprint("%%%02X", c);
	}
	return result;
}
