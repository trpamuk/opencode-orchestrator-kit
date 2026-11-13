import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

const LOG = path.join(
  process.env.USERPROFILE || process.env.HOME,
  ".config",
  "opencode",
  "agent-board",
  "guard.log",
);

function log(...parts) {
  try {
    fs.appendFileSync(LOG, new Date().toISOString() + " " + parts.join(" ") + "\n");
  } catch {
    // Logging must never block a tool call.
  }
}

function canonical(value) {
  const resolved = path.resolve(value);
  try {
    return fs.realpathSync.native(resolved);
  } catch {
    try {
      const parent = path.dirname(resolved);
      return path.join(fs.realpathSync.native(parent), path.basename(resolved));
    } catch {
      return resolved;
    }
  }
}

function normalize(value) {
  return canonical(value).replaceAll("\\", "/").toLowerCase();
}

function isBoardPath(value) {
  const normalized = normalize(value);
  return (
    normalized.endsWith("/.opencode/plans/current.md") ||
    /\/\.opencode\/plans\/boards\/.+\.md$/.test(normalized)
  );
}

function mainRoot(directory) {
  try {
    const common = execFileSync(
      "git",
      ["-C", directory, "rev-parse", "--git-common-dir"],
      { encoding: "utf8", timeout: 4000, windowsHide: true },
    ).trim();
    if (!common) return canonical(directory);
    const resolved = path.resolve(directory, common);
    return canonical(
      path.basename(resolved).toLowerCase() === ".git"
        ? path.dirname(resolved)
        : resolved,
    );
  } catch {
    return canonical(directory);
  }
}

function targetsFor(tool, args, base) {
  const result = [];
  const add = (value) => {
    if (typeof value !== "string" || !value.trim()) return;
    result.push(path.isAbsolute(value) ? value : path.resolve(base, value));
  };
  if (["write", "edit", "multiedit", "patch", "write_file", "edit_file"].includes(tool)) {
    add(args?.path);
    add(args?.filePath);
    add(args?.file_path);
  }
  if (tool === "multiedit" && Array.isArray(args?.edits)) {
    for (const edit of args.edits) {
      add(edit?.path);
      add(edit?.filePath);
    }
  }
  if (tool === "apply_patch" && typeof args?.patchText === "string") {
    for (const match of args.patchText.matchAll(
      /^\*\*\* (?:Update|Add|Delete) File: (.+)$/gm,
    )) {
      add(match[1].trim());
    }
  }
  return result;
}

async function agentFor(client, sessionID, directory) {
  try {
    if (!client?.session?.get) return null;
    const response = await client.session.get({
      path: { id: sessionID },
      query: { directory },
      throwOnError: true,
    });
    return response?.data?.agent || response?.agent || null;
  } catch {
    return null;
  }
}

function allowedBoard(target, root) {
  const plans = path.join(root, ".opencode", "plans");
  const legacy = path.join(plans, "current.md");
  if (normalize(target) === normalize(legacy)) return true;
  const boards = path.join(plans, "boards");
  const relative = path.relative(boards, canonical(target));
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) return false;
  if (relative.includes(path.sep)) return false;
  return relative.toLowerCase().endsWith(".md");
}

const BoardGuardServer = async ({ client, directory, worktree }) => {
  const base = directory || worktree || process.cwd();
  const root = mainRoot(base);
  const plans = path.join(root, ".opencode", "plans");
  const allowedLabel = plans + "\\current.md or " + path.join(plans, "boards") + "\\*.md";
  log("LOAD", base, "root=" + root);

  return {
    "tool.execute.before": async (input, output) => {
      const tool = String(input.tool || "");
      const targets = targetsFor(tool, output.args || {}, base).filter(isBoardPath);
      if (!targets.length) return;

      for (const target of targets) {
        if (!allowedBoard(target, root)) {
          log("DENY_PATH", input.sessionID, tool, target, "allowed=" + allowedLabel);
          throw new Error(
            "Board isolation: " +
              target +
              " is outside this repository's board area. Only " +
              allowedLabel +
              " may be edited. Other projects and worktrees must not create their own current.md.",
          );
        }
      }

      const agent = await agentFor(client, input.sessionID, base);
      if (agent && !["orchestrator", "build"].includes(agent)) {
        log("DENY_AGENT", input.sessionID, agent, tool, targets.join(","));
        throw new Error(
          'Board isolation: only the orchestrator may update project boards. Agent "' +
            agent +
            '" must report board changes to the orchestrator instead of editing a board.',
        );
      }

      log("ALLOW", input.sessionID, agent || "?", tool, targets.join(","));
    },
  };
};

export const BoardGuard = BoardGuardServer;

export default {
  id: "board-guard",
  server: BoardGuardServer,
  setup: async (ctx) => {
    const directory = ctx?.location?.directory || process.cwd();
    const root = mainRoot(directory);
    const plans = path.join(root, ".opencode", "plans");
    const allowedLabel =
      plans + "\\current.md or " + path.join(plans, "boards") + "\\*.md";
    log("SETUP", directory, "root=" + root);
    log("SETUP_KEYS", JSON.stringify(Object.keys(ctx || {})));
    log("SESSION_KEYS", JSON.stringify(Object.keys(ctx?.session || {})));
    log("TOOL_KEYS", JSON.stringify(Object.keys(ctx?.tool || {})));

    if (!ctx?.tool?.hook) {
      log("SETUP_ABORT", "ctx.tool.hook unavailable");
      return async () => {};
    }

    let loggedEvent = false;
    const registration = await ctx.tool.hook("execute.before", async (event) => {
      if (!loggedEvent) {
        loggedEvent = true;
        log("EVENT_KEYS", JSON.stringify(Object.keys(event || {})));
      }
      const tool = String(event?.tool || "");
      const targets = targetsFor(tool, event?.input || {}, directory).filter(isBoardPath);
      if (!targets.length) return;

      for (const target of targets) {
        if (!allowedBoard(target, root)) {
          log("DENY_PATH", event?.sessionID, tool, target, "allowed=" + allowedLabel);
          throw new Error(
            "Board isolation: " +
              target +
              " is outside this repository's board area. Only " +
              allowedLabel +
              " may be edited. Other projects and worktrees must not create their own current.md.",
          );
        }
      }

      const agent = typeof event?.agent === "string" ? event.agent : null;
      if (agent && !["orchestrator", "build"].includes(agent)) {
        log("DENY_AGENT", event?.sessionID, agent, tool, targets.join(","));
        throw new Error(
          'Board isolation: only the orchestrator may update project boards. Agent "' +
            agent +
            '" must report board changes to the orchestrator instead of editing a board.',
        );
      }

      log("ALLOW", event?.sessionID, agent || "?", tool, targets.join(","));
    });

    return async () => {
      try {
        await registration?.dispose?.();
      } catch {
        // Cleanup is best effort.
      }
    };
  },
};
