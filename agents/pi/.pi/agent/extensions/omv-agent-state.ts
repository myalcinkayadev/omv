// omv: tells the bar when a pi session works or is done, through the same
// claude-waiting.sh hook Claude Code uses, naming the agent pi. pi asks for no approvals,
// so its sessions are working or done, never asking. Only sessions in pi's terminal UI
// are reported: other modes have no terminal to go back to.

import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";

const HOOK = process.env.OMV_AGENT_HOOK || `${os.homedir()}/.claude/claude-waiting.sh`;

// The hook names its state file after the session, so only letters, digits and dashes.
const plainId = (id) => String(id).replace(/[^A-Za-z0-9-]/g, "-");

let queue = Promise.resolve();

function report(event, ctx) {
  const file = ctx?.sessionManager?.getSessionFile?.();
  const session = typeof file === "string" ? path.basename(file, ".jsonl") : String(process.pid);
  queue = queue.then(() => new Promise((resolve) => {
    const child = spawn(HOOK, ["wait", "pi"], { stdio: ["pipe", "ignore", "ignore"] });
    child.on("error", resolve);
    child.on("close", resolve);
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify({ hook_event_name: event, session_id: plainId(session), cwd: ctx?.cwd ?? process.cwd() }));
  }));
  return queue;
}

export default function omvAgentState(pi) {
  let inTerminal = false;
  pi.on("session_start", (_event, ctx) => {
    inTerminal = ctx?.mode === "tui";
  });
  pi.on("agent_start", (_event, ctx) => (inTerminal ? report("UserPromptSubmit", ctx) : undefined));
  pi.on("agent_settled", (_event, ctx) => (inTerminal && ctx?.isIdle?.() === true ? report("Stop", ctx) : undefined));
}
