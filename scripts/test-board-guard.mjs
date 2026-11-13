import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "board-guard-test-"));
const home = path.join(temp, "home");
const repo = path.join(temp, "main");
const worktree = path.join(temp, "worktree");

fs.mkdirSync(path.join(home, ".config", "opencode", "agent-board"), { recursive: true });
fs.mkdirSync(path.join(repo, ".opencode", "plans", "boards"), { recursive: true });
fs.writeFileSync(path.join(repo, ".opencode", "plans", "current.md"), "# board\n");
fs.writeFileSync(path.join(repo, ".opencode", "plans", "boards", "task.md"), "# task\n");
fs.writeFileSync(path.join(repo, "README.md"), "# test\n");

execFileSync("git", ["init", "-q", repo]);
execFileSync("git", ["-C", repo, "add", "."]);
execFileSync("git", [
  "-C",
  repo,
  "-c",
  "user.email=test@example.com",
  "-c",
  "user.name=Board Guard Test",
  "commit",
  "-q",
  "-m",
  "init",
]);
execFileSync("git", ["-C", repo, "worktree", "add", "-q", worktree, "-b", "test-worktree"]);
fs.mkdirSync(path.join(worktree, ".opencode", "plans", "boards"), { recursive: true });
fs.writeFileSync(path.join(worktree, ".opencode", "plans", "current.md"), "# worktree board\n");

process.env.USERPROFILE = home;
process.env.HOME = home;
const plugin = (
  await import(pathToFileURL(path.join(root, "plugins", "board-guard.js")).href)
).default;

let handler = null;
const dispose = await plugin.setup({
  location: { directory: worktree },
  session: {},
  tool: {
    hook: async (name, callback) => {
      assert.equal(name, "execute.before");
      handler = callback;
      return { dispose: async () => {} };
    },
  },
});
assert.equal(typeof handler, "function", "tool hook was not registered");

const event = (tool, input, agent = "orchestrator") => ({
  tool,
  sessionID: "ses_test",
  agent,
  input,
});
const mainCurrent = path.join(repo, ".opencode", "plans", "current.md");
const mainBoard = path.join(repo, ".opencode", "plans", "boards", "task.md");
const worktreeCurrent = path.join(worktree, ".opencode", "plans", "current.md");

await handler(event("write", { path: mainCurrent }));
await handler(event("write", { filePath: mainBoard }));
await handler(event("write", { path: path.join(repo, "README.md") }));
await assert.rejects(
  () => handler(event("write", { path: worktreeCurrent })),
  /outside this repository's board area/,
);
await assert.rejects(
  () => handler(event("write", { path: mainBoard }, "fixer")),
  /only the orchestrator/,
);
await assert.rejects(
  () =>
    handler(
      event("write", {
        path: path.join(repo, ".opencode", "plans", "boards", "nested", "x.md"),
      }),
    ),
  /outside this repository's board area/,
);
await handler(
  event("apply_patch", {
    patchText: `*** Begin Patch\n*** Update File: ${mainBoard}\n@@\n-old\n+new\n*** End Patch`,
  }),
);
await assert.rejects(
  () =>
    handler(
      event("apply_patch", {
        patchText: `*** Update File: ${worktreeCurrent}`,
      }),
    ),
  /outside this repository's board area/,
);

const log = fs.readFileSync(
  path.join(home, ".config", "opencode", "agent-board", "guard.log"),
  "utf8",
);
assert.match(log, /SETUP/);
assert.match(log, /ALLOW/);
assert.match(log, /DENY_PATH/);
assert.match(log, /DENY_AGENT/);

await dispose();
fs.rmSync(temp, { recursive: true, force: true });
console.log("Board Guard tests passed.");
