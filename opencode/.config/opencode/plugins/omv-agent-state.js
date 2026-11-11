// omv: tells the bar when an OpenCode session works, asks for approval or is done, through
// the same claude-waiting.sh hook Claude Code uses, naming the agent opencode. The pill,
// Option+Shift+A and the Agents card then show OpenCode sessions beside Claude's.
// Child sessions, such as a subagent's, are left out: their parent stands for them.

import { spawn } from "node:child_process";
import os from "node:os";

const HOOK = process.env.OMV_AGENT_HOOK || `${os.homedir()}/.claude/claude-waiting.sh`;

const HOOK_EVENTS = new Map([
  ["permission.asked", "PermissionRequest"],
  ["question.asked", "PermissionRequest"],
  ["permission.replied", "PostToolUse"],
  ["question.replied", "PostToolUse"],
  ["question.rejected", "PostToolUse"],
  ["tool.execute.after", "PostToolUse"],
  ["session.idle", "Stop"],
  ["session.deleted", "SessionEnd"],
]);

// The Claude Code hook event an OpenCode event stands for, or null when it changes nothing.
function hookEvent(type, properties) {
  if (type !== "session.status") return HOOK_EVENTS.get(type) ?? null;
  const status = properties?.status?.type ?? properties?.status;
  if (status === "busy" || status === "active") return "UserPromptSubmit";
  if (status === "idle") return "Stop";
  return null;
}

// The hook names its state file after the session, so only letters, digits and dashes.
const plainId = (id) => String(id).replace(/[^A-Za-z0-9-]/g, "-");

// One call at a time, so the states reach the hook in the order they happened.
let queue = Promise.resolve();

function report(event, sessionID, cwd) {
  queue = queue.then(() => new Promise((resolve) => {
    const child = spawn(HOOK, ["wait", "opencode"], { stdio: ["pipe", "ignore", "ignore"] });
    child.on("error", resolve);
    child.on("close", resolve);
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify({ hook_event_name: event, session_id: plainId(sessionID), cwd }));
  }));
  return queue;
}

export const OmvAgentState = async ({ directory }) => {
  const children = new Set();
  return {
    event: async ({ event }) => {
      const properties = event?.properties ?? {};
      const info = properties.info;
      if (info?.id && info.parentID) children.add(info.id);
      const sessionID = properties.sessionID ?? info?.id;
      if (!sessionID || children.has(sessionID)) return;
      const hook = hookEvent(event?.type, properties);
      if (hook) await report(hook, sessionID, directory);
    },
  };
};
