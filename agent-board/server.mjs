import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const HOME = process.env.USERPROFILE || process.env.HOME;
const CONFIG_DIR = path.join(HOME, ".config", "opencode");
const SERVICE_JSON = path.join(CONFIG_DIR, "service.json");
const INDEX_HTML = path.join(__dirname, "index.html");
const ASSETS_DIR = path.join(__dirname, "assets");
const PORT = Number(process.env.AGENT_BOARD_PORT || 43124);
const STUCK_MS = Number(process.env.AGENT_BOARD_STUCK_MS || 15 * 60 * 1000);
const TASK_CACHE_MS = 10000;
const TASK_MESSAGE_LIMIT = 40;
const TASK_FETCH_TIMEOUT_MS = 6000;
const TASK_MAX_SESSIONS = 12;
const TASK_MAX_ITEMS = 40;

const CONTENT_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".gif": "image/gif",
  ".ico": "image/x-icon",
};

function findCli() {
  const root = path.join(process.env.APPDATA || "", "ai.opencode.desktop", "cli");
  if (!fs.existsSync(root)) return null;
  const dirs = fs
    .readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort()
    .reverse();
  for (const dir of dirs) {
    const exe = path.join(root, dir, "opencode-cli.exe");
    if (fs.existsSync(exe)) return exe;
  }
  return null;
}

function resolveServerUrl() {
  const cli = findCli();
  if (cli) {
    try {
      const out = execFileSync(cli, ["service", "status"], {
        encoding: "utf8",
        timeout: 5000,
        windowsHide: true,
      }).trim();
      const match = out.match(/https?:\/\/[^\s]+/);
      if (match) return match[0];
    } catch {
      // Fall back to the default local endpoint.
    }
  }
  return "http://127.0.0.1:45278";
}

let cached = { url: null, auth: null, at: 0 };

function authHeader() {
  if (cached.auth && Date.now() - cached.at < 30_000) return cached.auth;
  const service = JSON.parse(fs.readFileSync(SERVICE_JSON, "utf8"));
  cached.auth = "Basic " + Buffer.from(`opencode:${service.password}`).toString("base64");
  cached.at = Date.now();
  return cached.auth;
}

async function upstream(pathname, timeoutMs = 15000) {
  const url = cached.url || (cached.url = resolveServerUrl());
  let response;
  try {
    response = await fetch(url + pathname, {
      headers: { Authorization: authHeader() },
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    cached.url = null;
    cached.auth = null;
    throw error;
  }
  const text = await response.text();
  if (!response.ok) {
    const error = new Error(`Upstream ${response.status}: ${text.slice(0, 500)}`);
    error.status = response.status;
    throw error;
  }
  return JSON.parse(text);
}

async function upstreamPost(pathname, timeoutMs = 15000) {
  const url = cached.url || (cached.url = resolveServerUrl());
  let response;
  try {
    response = await fetch(url + pathname, {
      method: "POST",
      headers: { Authorization: authHeader() },
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (error) {
    cached.url = null;
    cached.auth = null;
    throw error;
  }
  const text = await response.text();
  if (!response.ok) {
    const error = new Error(`Upstream ${response.status}: ${text.slice(0, 500)}`);
    error.status = response.status;
    throw error;
  }
  return text ? JSON.parse(text) : {};
}

function readJson(req, limit = 64 * 1024) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (chunk) => {
      data += chunk;
      if (data.length > limit) {
        reject(new Error("request body too large"));
        req.destroy();
      }
    });
    req.on("end", () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch {
        reject(new Error("invalid JSON body"));
      }
    });
    req.on("error", reject);
  });
}

function isWorktree(dir) {
  const normalized = dir.replaceAll("\\", "/").toLowerCase();
  return normalized.includes("/worktree/") || normalized.includes("/.slim/worktrees/");
}

function attachProjectDirs(sessions) {
  const byId = new Map(sessions.map((session) => [session.id, session]));
  for (const session of sessions) {
    let current = session;
    const seen = new Set();
    while (current?.parentID && byId.has(current.parentID) && !seen.has(current.id)) {
      seen.add(current.id);
      current = byId.get(current.parentID);
    }
    session.projectDir =
      current?.location?.directory || session.location?.directory || null;
  }
  return sessions;
}

function taskFromPart(session, message, part) {
  if (part.type !== "tool") return null;
  if (part.name !== "subagent" && part.name !== "task") return null;
  const state = part.state || {};
  const input = state.input || {};
  const agent = input.agent || input.subagent_type || input.subagentType || null;
  if (!agent) return null;
  const startedAt =
    state.time?.created || state.time?.ran || message.time?.created || null;
  const completedAt = state.time?.completed || message.time?.completed || null;
  const status = state.status || "unknown";
  const running = status === "running";
  const stuck = Boolean(
    running && startedAt && Date.now() - startedAt > STUCK_MS,
  );
  const description = String(input.description || input.prompt || "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 180);
  return {
    id: part.id || `${session.id}:${startedAt || 0}:${agent}`,
    sessionID: session.id,
    sessionTitle: session.title || session.id,
    sessionAgent: session.agent || null,
    project: session.projectDir || session.location?.directory || null,
    tool: part.name,
    agent,
    description,
    status,
    background: input.background === true,
    startedAt,
    completedAt,
    elapsedMs: startedAt
      ? Math.max(0, (completedAt || Date.now()) - startedAt)
      : null,
    stuck,
    error: state.error?.message || null,
  };
}

function tasksFromMessages(session, messages) {
  const tasks = [];
  for (const message of messages) {
    for (const part of message.content || message.parts || []) {
      const task = taskFromPart(session, message, part);
      if (task) tasks.push(task);
    }
  }
  return tasks;
}

const taskCache = new Map();

async function fetchSessionTasks(session) {
  const updated = session.time?.updated || 0;
  const cached = taskCache.get(session.id);
  if (
    cached &&
    cached.updated === updated &&
    Date.now() - cached.at < TASK_CACHE_MS
  ) {
    return cached.tasks;
  }
  try {
    const response = await upstream(
      `/api/session/${encodeURIComponent(session.id)}/message?limit=${TASK_MESSAGE_LIMIT}`,
      TASK_FETCH_TIMEOUT_MS,
    );
    const messages = Array.isArray(response) ? response : response.data || [];
    const tasks = tasksFromMessages(session, messages);
    taskCache.set(session.id, { at: Date.now(), updated, tasks });
    return tasks;
  } catch {
    taskCache.set(session.id, { at: Date.now(), updated, tasks: [] });
    return [];
  }
}

async function collectTasks(sessions, activeMap) {
  const activeIds = new Set(Object.keys(activeMap || {}));
  const now = Date.now();
  const candidates = sessions
    .filter((session) => {
      if (activeIds.has(session.id)) return true;
      if (session.outcome === "succeeded" || session.outcome === "failed") {
        return false;
      }
      return (
        session.time?.updated &&
        now - session.time.updated < 24 * 60 * 60 * 1000
      );
    })
    .sort((a, b) => (b.time?.updated || 0) - (a.time?.updated || 0))
    .slice(0, TASK_MAX_SESSIONS);
  const results = await Promise.allSettled(candidates.map(fetchSessionTasks));
  const tasks = results.flatMap((result) =>
    result.status === "fulfilled" ? result.value : [],
  );
  const seen = new Set();
  const rank = (task) =>
    task.stuck ? 0 : task.status === "running" ? 1 : task.status === "error" ? 2 : 3;
  return tasks
    .filter((task) => {
      if (task.status !== "running" && task.status !== "error") return false;
      if (seen.has(task.id)) return false;
      seen.add(task.id);
      return true;
    })
    .sort((a, b) => rank(a) - rank(b) || (b.startedAt || 0) - (a.startedAt || 0))
    .slice(0, TASK_MAX_ITEMS);
}

function addBoardPath(paths, seen, dir) {
  const kind = isWorktree(dir) ? "worktree" : "project";
  const plans = path.join(dir, ".opencode", "plans");
  const add = (file, boardId, legacy) => {
    if (!fs.existsSync(file)) return;
    const key = path.resolve(file).toLowerCase();
    if (seen.has(key)) return;
    seen.add(key);
    paths.push({ file, dir, kind, boardId, legacy });
  };
  add(path.join(plans, "current.md"), "current", true);
  const boardsDir = path.join(plans, "boards");
  if (fs.existsSync(boardsDir)) {
    let entries = [];
    try {
      entries = fs.readdirSync(boardsDir, { withFileTypes: true });
    } catch {
      entries = [];
    }
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.toLowerCase().endsWith(".md")) continue;
      add(path.join(boardsDir, entry.name), entry.name.slice(0, -3), false);
    }
  }
}

function walkWorktrees(paths, seen, root, depth = 0, budget = { dirs: 0 }) {
  if (depth > 4 || budget.dirs > 300 || !fs.existsSync(root)) return;
  budget.dirs += 1;
  addBoardPath(paths, seen, root);
  let entries;
  try {
    entries = fs.readdirSync(root, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    if (
      [
        "node_modules",
        ".git",
        "dist",
        "build",
        ".next",
        "target",
        "vendor",
        "coverage",
        ".cache",
      ].includes(entry.name)
    ) {
      continue;
    }
    walkWorktrees(paths, seen, path.join(root, entry.name), depth + 1, budget);
  }
}

let boardPathCache = { at: 0, paths: [] };

function discoverBoardPaths(sessions) {
  if (Date.now() - boardPathCache.at < 10_000) return boardPathCache.paths;
  const paths = [];
  const seen = new Set();
  const dirs = new Set();
  for (const session of sessions) {
    const dir = session.projectDir || session.location?.directory;
    if (dir) dirs.add(dir);
  }
  if (process.cwd()) dirs.add(process.cwd());
  for (const dir of dirs) addBoardPath(paths, seen, dir);

  const roots = [
    path.join(HOME, ".local", "share", "opencode", "worktree"),
    path.join(HOME, ".slim", "worktrees"),
    path.join(process.cwd(), ".slim", "worktrees"),
  ];
  for (const root of roots) walkWorktrees(paths, seen, root);

  paths.sort((a, b) => {
    if (a.kind !== b.kind) return a.kind === "project" ? -1 : 1;
    return a.dir.localeCompare(b.dir);
  });
  boardPathCache = { at: Date.now(), paths };
  return paths;
}

function readBoards(sessions, activeMap) {
  const paths = discoverBoardPaths(sessions);
  const activeIds = new Set(Object.keys(activeMap || {}));
  const activeDirs = new Set(
    sessions
      .filter((session) => activeIds.has(session.id))
      .map((session) => session.projectDir || session.location?.directory)
      .filter(Boolean),
  );
  const boards = [];
  for (const item of paths) {
    try {
      const stat = fs.statSync(item.file);
      boards.push({
        path: item.file,
        dir: item.dir,
        project: path.basename(item.dir),
        kind: item.kind,
        boardId: item.boardId,
        legacy: item.legacy,
        label:
          path.basename(item.dir) +
          (item.legacy ? " · current" : " · " + item.boardId) +
          (item.kind === "worktree" ? " · worktree" : ""),
        mtime: stat.mtimeMs,
        text: fs.readFileSync(item.file, "utf8"),
      });
    } catch {
      // The board may disappear between discovery and read.
    }
  }
  boards.sort((a, b) => {
    const activeA = activeDirs.has(a.dir) ? 1 : 0;
    const activeB = activeDirs.has(b.dir) ? 1 : 0;
    if (activeA !== activeB) return activeB - activeA;
    if (a.kind !== b.kind) return a.kind === "project" ? -1 : 1;
    return b.mtime - a.mtime;
  });
  return boards;
}

function projectName(dir) {
  return path.basename(dir || "") || dir || "?";
}

function listProjects(sessions, boards) {
  const map = new Map();
  const ensure = (dir) => {
    if (!dir) return null;
    if (!map.has(dir)) {
      map.set(dir, {
        dir,
        name: projectName(dir),
        kind: isWorktree(dir) ? "worktree" : "project",
        sessionCount: 0,
        activeCount: 0,
        boardCount: 0,
        updated: 0,
      });
    }
    return map.get(dir);
  };
  for (const session of sessions) {
    const item = ensure(session.projectDir || session.location?.directory);
    if (!item) continue;
    item.sessionCount += 1;
    item.updated = Math.max(item.updated, session.time?.updated || 0);
  }
  for (const board of boards) {
    const item = ensure(board.dir);
    if (!item) continue;
    item.boardCount += 1;
    item.updated = Math.max(item.updated, board.mtime || 0);
  }
  return [...map.values()].sort((a, b) => b.updated - a.updated);
}

function serveStatic(res, pathname) {
  const relative = decodeURIComponent(pathname.slice("/assets/".length));
  const file = path.resolve(ASSETS_DIR, relative);
  const root = path.resolve(ASSETS_DIR) + path.sep;
  if (!file.toLowerCase().startsWith(root.toLowerCase()) || !fs.existsSync(file)) {
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    res.end("not found");
    return;
  }
  const ext = path.extname(file).toLowerCase();
  res.writeHead(200, {
    "content-type": CONTENT_TYPES[ext] || "application/octet-stream",
    "cache-control": "public, max-age=3600",
  });
  res.end(fs.readFileSync(file));
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", "http://127.0.0.1");
    if (url.pathname === "/" || url.pathname === "/index.html") {
      res.writeHead(200, {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(fs.readFileSync(INDEX_HTML));
      return;
    }
    if (url.pathname.startsWith("/assets/")) {
      serveStatic(res, url.pathname);
      return;
    }
    if (url.pathname === "/api/interrupt") {
      if (req.method !== "POST") {
        res.writeHead(405, { "content-type": "text/plain; charset=utf-8" });
        res.end("method not allowed");
        return;
      }
      const origin = req.headers.origin;
      const allowedOrigins = new Set([
        `http://127.0.0.1:${PORT}`,
        `http://localhost:${PORT}`,
      ]);
      if (origin && !allowedOrigins.has(origin)) {
        res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
        res.end("forbidden origin");
        return;
      }
      let body;
      try {
        body = await readJson(req);
      } catch (error) {
        res.writeHead(400, { "content-type": "text/plain; charset=utf-8" });
        res.end(error.message);
        return;
      }
      const sessionID = String(body.sessionID || "");
      if (!/^ses_[A-Za-z0-9]+$/.test(sessionID)) {
        res.writeHead(400, { "content-type": "text/plain; charset=utf-8" });
        res.end("invalid session id");
        return;
      }
      const active = await upstream("/api/session/active").catch(() => ({}));
      const activeMap = Array.isArray(active) ? {} : active.data || active || {};
      if (!activeMap[sessionID]) {
        res.writeHead(409, { "content-type": "text/plain; charset=utf-8" });
        res.end("session is not active");
        return;
      }
      const sessionResponse = await upstream(
        `/api/session/${encodeURIComponent(sessionID)}`,
      );
      const session = Array.isArray(sessionResponse)
        ? sessionResponse[0]
        : sessionResponse.data || sessionResponse;
      const messagesResponse = await upstream(
        `/api/session/${encodeURIComponent(sessionID)}/message?limit=${TASK_MESSAGE_LIMIT}`,
        TASK_FETCH_TIMEOUT_MS,
      );
      const messages = Array.isArray(messagesResponse)
        ? messagesResponse
        : messagesResponse.data || [];
      const runningTasks = tasksFromMessages(session, messages).filter(
        (task) => task.status === "running",
      );
      if (!runningTasks.length) {
        res.writeHead(409, { "content-type": "text/plain; charset=utf-8" });
        res.end("no running subagent task");
        return;
      }
      let interrupted = false;
      if (process.env.AGENT_BOARD_INTERRUPT_DRY_RUN !== "1") {
        const result = await upstreamPost(
          `/api/session/${encodeURIComponent(sessionID)}/interrupt`,
        );
        interrupted = result.interrupted === true;
      }
      res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
      res.end(
        JSON.stringify({
          ok: true,
          dryRun: process.env.AGENT_BOARD_INTERRUPT_DRY_RUN === "1",
          interrupted,
          sessionID,
          stoppedTasks: runningTasks.length,
        }),
      );
      return;
    }
    if (url.pathname === "/api/state") {
      const [sessions, active, agents] = await Promise.all([
        upstream("/api/session?limit=100"),
        upstream("/api/session/active").catch(() => ({})),
        upstream("/api/agent").catch(() => []),
      ]);
      const sessionList = attachProjectDirs(
        Array.isArray(sessions) ? sessions : sessions.data || [],
      );
      const activeMap = Array.isArray(active) ? {} : active.data || active || {};
      const rawAgents = Array.isArray(agents) ? agents : agents.data || [];
      const agentList = rawAgents.map((agent) => ({
        id: agent.id,
        name: agent.name,
        description: agent.description,
        mode: agent.mode,
        model: agent.model,
      }));
      const allBoards = readBoards(sessionList, activeMap);
      const projects = listProjects(sessionList, allBoards);
      const activeIds = new Set(Object.keys(activeMap));
      let allTasks = [];
      try {
        allTasks = await collectTasks(sessionList, activeMap);
      } catch {
        allTasks = [];
      }
      for (const project of projects) {
        project.activeCount = sessionList.filter(
          (session) =>
            (session.projectDir || session.location?.directory) === project.dir &&
            activeIds.has(session.id),
        ).length;
        project.taskCount = allTasks.filter(
          (task) => task.project === project.dir && task.status === "running",
        ).length;
        project.stuckCount = allTasks.filter(
          (task) => task.project === project.dir && task.stuck,
        ).length;
      }
      const requested = url.searchParams.get("project");
      const latestActive = [...sessionList]
        .filter((session) => activeIds.has(session.id))
        .sort((a, b) => (b.time?.updated || 0) - (a.time?.updated || 0))[0];
      const defaultProject =
        latestActive?.projectDir ||
        latestActive?.location?.directory ||
        allBoards.find((board) => board.kind === "project")?.dir ||
        sessionList[0]?.projectDir ||
        sessionList[0]?.location?.directory ||
        null;
      const selectedProject =
        requested && projects.some((project) => project.dir === requested)
          ? requested
          : defaultProject;
      const selectedSessions = selectedProject
        ? sessionList.filter(
            (session) =>
              (session.projectDir || session.location?.directory) ===
              selectedProject,
          )
        : [];
      const selectedIds = new Set(selectedSessions.map((session) => session.id));
      const selectedActive = Object.fromEntries(
        Object.entries(activeMap).filter(([id]) => selectedIds.has(id)),
      );
      const selectedBoards = selectedProject
        ? allBoards.filter((board) => board.dir === selectedProject)
        : [];
      const selectedTasks = selectedProject
        ? allTasks.filter((task) => task.project === selectedProject)
        : [];
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(
        JSON.stringify({
          sessions: selectedSessions,
          active: selectedActive,
          agents: agentList,
          boards: selectedBoards,
          board: selectedBoards[0] || null,
          project: selectedProject,
          projects,
          tasks: selectedTasks,
          stuckCount: selectedTasks.filter((task) => task.stuck).length,
          generatedAt: Date.now(),
        }),
      );
      return;
    }
    if (url.pathname === "/health") {
      res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
      res.end("ok");
      return;
    }
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    res.end("not found");
  } catch (error) {
    res.writeHead(error.status || 502, {
      "content-type": "text/plain; charset=utf-8",
    });
    res.end(String(error.message || error));
  }
});

server.on("error", (error) => {
  if (error.code === "EADDRINUSE") process.exit(0);
  console.error(error);
  process.exit(1);
});

server.listen(PORT, "127.0.0.1", () => {
  console.log("Ajan Panosu: http://127.0.0.1:" + PORT);
});
