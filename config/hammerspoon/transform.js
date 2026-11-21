// The palette's clipboard actions: omvTransform(query, clip, now) gives the rows to show at
// the top of the palette, each { kind, label, hint, value, tone, verb }. With nothing typed,
// the clipboard's text is recognised by its shape, JWT, JSON, an epoch time, URL escapes or
// base64, in that order, so one text gets at most one row; ordinary text gets none. A typed
// action word applies to what follows it, else to the clipboard. value is what Enter copies,
// null for an error row. Everything runs in the page: nothing leaves the Mac.
// card.lua inlines this file into the palette's page; node runs it for the tests.

const OMV_VERBS = [
  { verb: "json", kind: "JSON", about: "pretty JSON" },
  { verb: "jwt", kind: "JWT", about: "decode a JWT" },
  { verb: "b64", kind: "B64", about: "encode base64" },
  { verb: "unb64", kind: "B64", about: "decode base64" },
  { verb: "url", kind: "URL", about: "encode URL escapes" },
  { verb: "unurl", kind: "URL", about: "decode URL escapes" },
  { verb: "epoch", kind: "TIME", about: "epoch time to a date" },
];

function omvSpan(ms) {
  const minutes = Math.round(Math.abs(ms) / 60000);
  if (minutes < 60) return minutes + " min";
  const hours = Math.round(minutes / 60);
  if (hours < 48) return hours + " h";
  return Math.round(hours / 24) + " days";
}

// Bytes to text, or null when they aren't valid UTF-8 or hold control characters.
function omvReadable(bytes) {
  let text;
  try { text = new TextDecoder("utf-8", { fatal: true }).decode(bytes); } catch (error) { return null; }
  return /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(text) ? null : text;
}

function omvFromBase64(text) {
  const normal = text.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normal + "===".slice((normal.length + 3) % 4);
  let binary;
  try { binary = atob(padded); } catch (error) { return null; }
  return omvReadable(Uint8Array.from(binary, (character) => character.charCodeAt(0)));
}

function omvToBase64(text) {
  let binary = "";
  new TextEncoder().encode(text).forEach((byte) => { binary += String.fromCharCode(byte); });
  return btoa(binary);
}

function omvParseJson(text) {
  try { return JSON.parse(text); } catch (error) { return undefined; }
}

function omvJson(text) {
  const trimmed = text.trim();
  if (!/^[[{]/.test(trimmed)) return null;
  const parsed = omvParseJson(trimmed);
  if (parsed === undefined || typeof parsed !== "object" || parsed === null) return null;
  const value = JSON.stringify(parsed, null, 2);
  return { kind: "JSON", label: "Pretty JSON", hint: value.split("\n").length + " lines", value, tone: null };
}

function omvJwt(text, now) {
  const parts = text.trim().split(".");
  if (parts.length !== 3 || !parts.every((part) => /^[A-Za-z0-9_-]+$/.test(part))) return null;
  const header = omvParseJson(omvFromBase64(parts[0]) || "");
  const payload = omvParseJson(omvFromBase64(parts[1]) || "");
  if (!header || typeof header !== "object" || typeof header.alg !== "string") return null;
  if (!payload || typeof payload !== "object") return null;
  let hint = "no expiry", tone = null;
  if (typeof payload.exp === "number") {
    const left = payload.exp * 1000 - now;
    hint = left > 0 ? "valid · " + omvSpan(left) + " left" : "expired " + omvSpan(left) + " ago";
    tone = left > 0 ? "ok" : "bad";
  }
  const subject = payload.sub !== undefined ? " · sub " + String(payload.sub) : "";
  return { kind: "JWT", label: "JWT · " + header.alg + subject, hint, value: JSON.stringify(payload, null, 2), tone };
}

function omvEpoch(text) {
  const trimmed = text.trim();
  const match = /^\d{10}$|^\d{13}$/.exec(trimmed);
  if (!match) return null;
  const milliseconds = trimmed.length === 13;
  const label = new Date(Number(trimmed) * (milliseconds ? 1 : 1000)).toString().slice(0, 24);
  return { kind: "TIME", label, hint: "epoch " + (milliseconds ? "milliseconds" : "seconds") + " · local", value: label, tone: null };
}

function omvUnurl(text) {
  if (!/%[0-9A-Fa-f]{2}/.test(text)) return null;
  let value;
  try { value = decodeURIComponent(text.trim()); } catch (error) { return null; }
  return { kind: "URL", label: value.split("\n")[0], hint: "URL-decoded", value, tone: null };
}

function omvUnb64(text) {
  const trimmed = text.trim();
  if (trimmed.length < 8 || trimmed.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(trimmed)) return null;
  const value = omvFromBase64(trimmed);
  if (value === null || !value.trim()) return null;
  return { kind: "B64", label: value.split("\n")[0], hint: "base64-decoded", value, tone: null };
}

function omvDetect(text, now) {
  if (typeof text !== "string" || !text.trim()) return null;
  return omvJwt(text, now) || omvJson(text) || omvEpoch(text) || omvUnurl(text) || omvUnb64(text);
}

const OMV_ERRORS = {
  json: "Not valid JSON", jwt: "Not a JWT", unb64: "Not base64 text", unurl: "Not URL-encoded", epoch: "Not an epoch time",
};

function omvApply(verb, input, now) {
  if (verb === "b64") return { kind: "B64", label: omvToBase64(input), value: omvToBase64(input) };
  if (verb === "url") return { kind: "URL", label: encodeURIComponent(input), value: encodeURIComponent(input) };
  const found = { json: omvJson, jwt: (text) => omvJwt(text, now), unb64: omvUnb64, unurl: omvUnurl, epoch: omvEpoch }[verb](input);
  return found;
}

function omvTransform(query, clip, now) {
  const typed = String(query || "");
  if (!typed.trim()) {
    const found = omvDetect(clip, now);
    return found ? [found] : [];
  }
  const match = /^\s*(\S+)(?:\s+([\s\S]*))?$/.exec(typed);
  const word = match[1].toLowerCase();
  const known = OMV_VERBS.find((entry) => entry.verb === word);
  if (!known) {
    if (word.length < 2 || match[2] !== undefined) return [];
    return OMV_VERBS.filter((entry) => entry.verb.startsWith(word))
      .map((entry) => ({ kind: entry.kind, label: entry.verb, hint: entry.about, value: null, tone: null, verb: entry.verb }));
  }
  const fromTyped = match[2] !== undefined && match[2].trim() !== "";
  const input = fromTyped ? match[2] : clip;
  const kind = known.kind;
  if (typeof input !== "string" || !input.trim()) {
    return [{ kind, label: "The clipboard is empty", hint: "copy something, or type it after " + known.verb, value: null, tone: "bad" }];
  }
  const result = omvApply(known.verb, input, now);
  const source = fromTyped ? "what you typed" : "the clipboard";
  if (!result) return [{ kind, label: OMV_ERRORS[known.verb], hint: "from " + source, value: null, tone: "bad" }];
  const hint = known.verb === "b64" || known.verb === "url" ? known.about.replace(/^encode /, "") + " of " + source : result.hint;
  return [{ kind, label: result.label, hint, value: result.value, tone: result.tone || null }];
}

if (typeof module !== "undefined") module.exports = omvTransform;
