// Behavior of the palette's clipboard actions, transform.js. Run through transform_test.sh with node.

import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const transform = require(process.env.OMV_TRANSFORM);
let failed = 0;
const check = (name, passed) => {
  console.log((passed ? "ok   - " : "FAIL - ") + name);
  if (!passed) failed += 1;
};

const NOW = Date.UTC(2026, 10, 21, 12, 0, 0);
const base64url = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
const jwt = (header, payload) => base64url(header) + "." + base64url(payload) + ".c2lnbmF0dXJl";
const one = (query, clip) => transform(query, clip, NOW)[0];

// Detection, with nothing typed.
const pretty = one("", '{"id":42,"user":{"name":"Ada"}}');
check("should offer pretty JSON for an object", pretty && pretty.kind === "JSON" && pretty.label === "Pretty JSON");
check("should copy the JSON indented", pretty && pretty.value === JSON.stringify({ id: 42, user: { name: "Ada" } }, null, 2));
check("should count the pretty JSON's lines", pretty && pretty.hint === "6 lines");
check("should offer pretty JSON for an array", one("", "[1, 2, 3]").kind === "JSON");
check("should offer nothing for JSON that doesn't parse", transform("", '{"id": 42,', NOW).length === 0);
check("should not offer pretty JSON for a bare number", transform("", "42", NOW).length === 0);
check("should not offer pretty JSON for a bare string", transform("", '"hello"', NOW).length === 0);

const valid = one("", jwt({ alg: "HS256", typ: "JWT" }, { sub: "1042", exp: NOW / 1000 + 2 * 3600 }));
check("should decode a JWT's algorithm and subject", valid && valid.kind === "JWT" && valid.label === "JWT · HS256 · sub 1042");
check("should copy a JWT's payload as pretty JSON", valid && JSON.parse(valid.value).sub === "1042");
check("should say how long a JWT is still valid", valid && valid.hint === "valid · 2 h left" && valid.tone === "ok");
const expired = one("", jwt({ alg: "RS256" }, { exp: NOW / 1000 - 3 * 3600 }));
check("should say how long ago a JWT expired", expired && expired.hint === "expired 3 h ago" && expired.tone === "bad");
check("should give minutes for a JWT expiring soon",
  one("", jwt({ alg: "HS256" }, { exp: NOW / 1000 + 25 * 60 })).hint === "valid · 25 min left");
check("should treat a JWT without exp as having no expiry", one("", jwt({ alg: "HS256" }, { sub: "x" })).hint === "no expiry");
check("should not treat three dotted parts as a JWT when the header isn't JSON",
  transform("", "abc.def.ghi", NOW).every((row) => row.kind !== "JWT"));

const seconds = one("", "1732190400");
check("should read a 10-digit number as epoch seconds", seconds && seconds.kind === "TIME" && seconds.hint === "epoch seconds · local");
check("should show the epoch as a local date", seconds && seconds.label === new Date(1732190400 * 1000).toString().slice(0, 24));
check("should read a 13-digit number as epoch milliseconds", one("", "1732190400000").hint === "epoch milliseconds · local");
check("should not read other lengths as an epoch", transform("", "123456789", NOW).length === 0);

const decoded = one("", "redirect%3D%2Fsettings%3Ftab%3Dbilling");
check("should decode URL-encoded text", decoded && decoded.kind === "URL" && decoded.value === "redirect=/settings?tab=billing");
check("should offer nothing for text without %xx", transform("", "redirect=/settings", NOW).length === 0);

const b64 = one("", Buffer.from("deploy: v1.14.2 to staging").toString("base64"));
check("should decode strict base64 to readable text", b64 && b64.kind === "B64" && b64.value === "deploy: v1.14.2 to staging");
check("should not treat a plain word as base64", transform("", "password", NOW).length === 0);
check("should refuse base64 that decodes to binary", transform("", Buffer.from([0, 1, 2, 255, 254, 3, 4, 5, 6]).toString("base64"), NOW).length === 0);
check("should refuse base64 under 8 characters", transform("", "aGk=", NOW).length === 0);
check("should offer one row, a JWT before base64", transform("", jwt({ alg: "HS256" }, { sub: "x" }), NOW).length === 1);
check("should offer one row, JSON before an epoch", transform("", "[1732190400]", NOW).length === 1 && one("", "[1732190400]").kind === "JSON");
check("should offer nothing without a clipboard", transform("", null, NOW).length === 0);

// Action words.
check("should encode with b64", one("b64 hello omv", null).value === "aGVsbG8gb212");
check("should decode with unb64", one("unb64", "aGVsbG8gb212").value === "hello omv");
check("should encode with url", one("url a b&c", null).value === "a%20b%26c");
check("should decode with unurl", one("unurl", "q%3Domv%20palette").value === "q=omv palette");
check("should apply an action word to what's typed after it", one("epoch 1732190400", "something else").kind === "TIME");
check("should apply an action word to the clipboard when nothing follows it", one("json", "[1,2]").value === "[\n  1,\n  2\n]");
check("should say where an action word's input came from", one("b64 hi", null).hint === "base64 of what you typed");
const notJwt = one("jwt", "just some text");
check("should give an error row when the input doesn't fit", notJwt && notJwt.label === "Not a JWT" && notJwt.tone === "bad" && notJwt.value === null);
check("should give an error row for an empty clipboard", one("json", "").label === "The clipboard is empty");
check("should read an action word whatever its case", one("B64 hi", null).value === "aGk=");
check("should show no row for an unknown word, so the palette filters as usual", transform("zed", "[1]", NOW).length === 0);
const listed = transform("un", "x", NOW);
check("should list the matching action words while one is half typed", listed.length === 2 && listed[0].verb === "unb64" && listed[1].verb === "unurl");
check("should not list action words for a single letter", transform("u", "x", NOW).length === 0);

process.exit(failed === 0 ? 0 : 1);
