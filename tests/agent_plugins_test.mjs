// Behavior of the OpenCode plugin and the pi extension that report their sessions to
// claude-waiting.sh. Run through agent_plugins_test.sh with node. The hook is a stub
// that logs its arguments and the JSON it was given, one line per call.

import fs from "node:fs";

const log = process.env.OMV_TEST_LOG;
let failed = 0;
const check = (name, passed) => {
  console.log((passed ? "ok   - " : "FAIL - ") + name);
  if (!passed) failed += 1;
};
const calls = () => (fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim().split("\n").filter(Boolean) : []);
const reset = () => fs.writeFileSync(log, "");
const last = () => {
  const line = calls().at(-1) || "";
  const [args, json] = line.split("\t");
  return { args, data: json ? JSON.parse(json) : {} };
};

const { OmvAgentState } = await import(process.env.OMV_OPENCODE_PLUGIN);
const opencode = await OmvAgentState({ directory: "/Users/me/work/omv" });
const send = (type, properties) => opencode.event({ event: { type, properties } });

reset();
await send("session.status", { sessionID: "ses_abc1", status: { type: "busy" } });
check("should report a session that starts working", last().data.hook_event_name === "UserPromptSubmit");
check("should name the agent opencode", last().args === "wait opencode");
check("should pass the session's folder", last().data.cwd === "/Users/me/work/omv");
check("should turn the session id into a plain id", last().data.session_id === "ses-abc1");
await send("permission.asked", { sessionID: "ses_abc1" });
check("should report a permission request as PermissionRequest", last().data.hook_event_name === "PermissionRequest");
await send("permission.replied", { sessionID: "ses_abc1" });
check("should report a reply as working again", last().data.hook_event_name === "PostToolUse");
await send("session.idle", { sessionID: "ses_abc1" });
check("should report an idle session as Stop", last().data.hook_event_name === "Stop");
await send("session.deleted", { sessionID: "ses_abc1" });
check("should report a deleted session as SessionEnd", last().data.hook_event_name === "SessionEnd");
reset();
await send("session.created", { info: { id: "ses_child", parentID: "ses_abc1" } });
await send("permission.asked", { sessionID: "ses_child" });
check("should ignore OpenCode's child sessions", calls().length === 0);
await send("message.updated", { sessionID: "ses_abc1" });
check("should ignore events that change no state", calls().length === 0);

const { default: omvAgentState } = await import(process.env.OMV_PI_EXTENSION);
const handlers = {};
omvAgentState({ on: (name, handler) => { handlers[name] = handler; } });
const ctx = { mode: "tui", cwd: "/Users/me/work/api", isIdle: () => true,
  sessionManager: { getSessionFile: () => "/Users/me/.pi/sessions/2026_11_11-abc.jsonl" } };
reset();
await handlers.session_start?.({}, ctx);
await handlers.agent_start?.({}, ctx);
check("should report pi's agent_start as working", last().data.hook_event_name === "UserPromptSubmit");
check("should name the agent pi", last().args === "wait pi");
check("should name a pi session by its file", last().data.session_id === "2026-11-11-abc");
await handlers.agent_settled?.({}, ctx);
check("should report pi settling as Stop", last().data.hook_event_name === "Stop");
reset();
await handlers.session_start?.({}, { ...ctx, mode: "rpc" });
await handlers.agent_start?.({}, { ...ctx, mode: "rpc" });
check("should report nothing for pi outside its terminal UI", calls().length === 0);

process.exit(failed === 0 ? 0 : 1);
