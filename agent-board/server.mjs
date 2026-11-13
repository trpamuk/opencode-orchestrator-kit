import http from "node:http";
import crypto from "node:crypto";
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
const OMO_CONFIG =
  process.env.AGENT_BOARD_OMO_CONFIG ||
  path.join(CONFIG_DIR, "oh-my-opencode-slim.json");
const MODEL_CACHE_MS = 10000;
const PROFILE_AGENTS = [
  "orchestrator",
  "oracle",
  "explorer",
  "designer",
  "fixer",
  "observer",
];
const PANEL_TOKEN = crypto.randomBytes(24).toString("hex");
const VERSION_FILE = path.join(__dirname, "VERSION");
const PANEL_VERSION = fs.existsSync(VERSION_FILE)
  ? fs.readFileSync(VERSION_FILE, "utf8").trim()
  : "dev";
const GITHUB_REPO = "trpamuk/opencode-orchestrator-kit";
const UPDATE_CACHE_MS = 60 * 60 * 1000;
const GUARD_LOG = path.join(__dirname, "guard.log");
let updateCache = { at: 0, data: null };

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

async function upstreamJson(method, pathname, body, timeoutMs = 15000) {
  const url = cached.url || (cached.url = resolveServerUrl());
  let response;
  try {
    response = await fetch(url + pathname, {
      method,
      headers: {
        Authorization: authHeader(),
        ...(body !== undefined ? { "content-type": "application/json" } : {}),
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
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

async function upstreamPost(pathname, timeoutMs = 15000) {
  return upstreamJson("POST", pathname, undefined, timeoutMs);
}

async function upstreamDelete(pathname, timeoutMs = 15000) {
  return upstreamJson("DELETE", pathname, undefined, timeoutMs);
}

function compareVersions(a, b) {
  const left = String(a || "")
    .split(".")
    .map((part) => parseInt(part, 10) || 0);
  const right = String(b || "")
    .split(".")
    .map((part) => parseInt(part, 10) || 0);
  for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
    const delta = (left[index] || 0) - (right[index] || 0);
    if (delta !== 0) return delta;
  }
  return 0;
}

async function checkUpdate() {
  if (Date.now() - updateCache.at < UPDATE_CACHE_MS) return updateCache.data;
  try {
    const response = await fetch(
      `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`,
      {
        headers: {
          "user-agent": "ajan-panosu",
          accept: "application/vnd.github+json",
        },
        signal: AbortSignal.timeout(8000),
      },
    );
    if (!response.ok) throw new Error(`GitHub ${response.status}`);
    const release = await response.json();
    const latest = String(release.tag_name || "").replace(/^v/, "");
    const data = {
      current: PANEL_VERSION,
      latest,
      updateAvailable: compareVersions(latest, PANEL_VERSION) > 0,
      url: release.html_url || null,
      publishedAt: release.published_at || null,
      name: release.name || null,
    };
    updateCache = { at: Date.now(), data };
    return data;
  } catch (error) {
    const data = {
      current: PANEL_VERSION,
      latest: null,
      updateAvailable: false,
      error: String(error.message || error),
    };
    updateCache = { at: Date.now(), data };
    return data;
  }
}

function isPanelTokenValid(req) {
  return req.headers["x-panel-token"] === PANEL_TOKEN;
}

function parseStuckMs(url) {
  const value = Number(url.searchParams.get("stuckMs"));
  if (!Number.isFinite(value) || value < 60000) return STUCK_MS;
  return Math.min(value, 24 * 60 * 60 * 1000);
}

function isAllowedOrigin(req) {
  const origin = req.headers.origin;
  if (!origin) return true;
  return new Set([
    `http://127.0.0.1:${PORT}`,
    `http://localhost:${PORT}`,
  ]).has(origin);
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

function taskFromPart(session, message, part, stuckMs = STUCK_MS) {
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
    running && startedAt && Date.now() - startedAt > stuckMs,
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

function tasksFromMessages(session, messages, stuckMs = STUCK_MS) {
  const tasks = [];
  for (const message of messages) {
    for (const part of message.content || message.parts || []) {
      const task = taskFromPart(session, message, part, stuckMs);
      if (task) tasks.push(task);
    }
  }
  return tasks;
}

const taskCache = new Map();

async function fetchSessionTasks(session, stuckMs = STUCK_MS) {
  const updated = session.time?.updated || 0;
  const cached = taskCache.get(session.id);
  if (
    cached &&
    cached.updated === updated &&
    cached.stuckMs === stuckMs &&
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
    const tasks = tasksFromMessages(session, messages, stuckMs);
    taskCache.set(session.id, { at: Date.now(), updated, stuckMs, tasks });
    return tasks;
  } catch {
    taskCache.set(session.id, { at: Date.now(), updated, stuckMs, tasks: [] });
    return [];
  }
}

async function collectTasks(sessions, activeMap, stuckMs = STUCK_MS) {
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
  const results = await Promise.allSettled(
    candidates.map((session) => fetchSessionTasks(session, stuckMs)),
  );
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

function redact(text, max = 240) {
  let value = String(text ?? "");
  value = value
    .replace(/\b(sk-[A-Za-z0-9_-]{8,})\b/g, "sk-***")
    .replace(/\b(ghp_[A-Za-z0-9]{8,})\b/g, "ghp_***")
    .replace(/\b(github_pat_[A-Za-z0-9_]{8,})\b/g, "github_pat_***")
    .replace(/(Bearer\s+)[A-Za-z0-9._-]+/gi, "$1***")
    .replace(
      /((?:api[_-]?key|token|secret|password|passwd)\s*[:=]\s*["']?)[^"'\s,;]+/gi,
      "$1***",
    )
    .replace(/([?&](?:key|token|secret|password)=)[^&\s]+/gi, "$1***");
  if (value.length > max) value = value.slice(0, max) + "…";
  return value;
}

function sanitizeModel(model) {
  const providerID = model.providerID || "";
  const modelID = model.modelID || model.id || "";
  const input = model.capabilities?.input || [];
  return {
    id: providerID + "/" + modelID,
    providerID,
    modelID,
    name: model.name || modelID,
    tools: model.capabilities?.tools === true,
    vision: input.includes("image") || input.includes("pdf"),
    input,
    variants: (model.variants || []).map((variant) => variant.id).filter(Boolean),
    context: model.limit?.context || null,
    cost: model.cost?.[0]
      ? {
          input: model.cost[0].input,
          output: model.cost[0].output,
        }
      : null,
  };
}

let modelCache = { at: 0, models: [], defaultModel: null };

async function fetchModelCatalog() {
  if (Date.now() - modelCache.at < MODEL_CACHE_MS) return modelCache;
  const [modelsResponse, defaultResponse] = await Promise.all([
    upstream("/api/model", 10000),
    upstream("/api/model/default", 8000).catch(() => null),
  ]);
  const raw = Array.isArray(modelsResponse)
    ? modelsResponse
    : modelsResponse.data || [];
  const models = raw
    .filter((model) => model && model.enabled !== false)
    .map(sanitizeModel)
    .filter((model) => model.providerID && model.modelID);
  const defaultRaw = defaultResponse
    ? defaultResponse.data || defaultResponse
    : null;
  const defaultModel =
    defaultRaw?.providerID && defaultRaw?.modelID
      ? sanitizeModel(defaultRaw)
      : null;
  modelCache = { at: Date.now(), models, defaultModel };
  return modelCache;
}

let defaultModelCache = { at: 0, value: null };

async function getDefaultModel() {
  if (process.env.AGENT_BOARD_FAKE_NO_MODEL === "1") return null;
  if (Date.now() - defaultModelCache.at < MODEL_CACHE_MS) {
    return defaultModelCache.value;
  }
  try {
    const response = await upstream("/api/model/default", 8000);
    const raw = response.data || response;
    const value =
      raw?.providerID && raw?.modelID
        ? `${raw.providerID}/${raw.modelID}`
        : null;
    defaultModelCache = { at: Date.now(), value };
    return value;
  } catch {
    defaultModelCache = { at: Date.now(), value: null };
    return null;
  }
}

function readOmoConfig() {
  const text = fs.readFileSync(OMO_CONFIG, "utf8").replace(/^\uFEFF/, "");
  return JSON.parse(text);
}

function writeOmoConfig(config) {
  const stamp = new Date()
    .toISOString()
    .replace(/[:.]/g, "-");
  const backupRoot = path.join(
    path.dirname(OMO_CONFIG),
    "backups",
    `${stamp}-profile`,
  );
  fs.mkdirSync(backupRoot, { recursive: true });
  if (fs.existsSync(OMO_CONFIG)) {
    fs.copyFileSync(
      OMO_CONFIG,
      path.join(backupRoot, "oh-my-opencode-slim.json"),
    );
  }
  const temp = `${OMO_CONFIG}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(temp, JSON.stringify(config, null, 2) + "\n", "utf8");
  fs.copyFileSync(temp, OMO_CONFIG);
  fs.rmSync(temp, { force: true });
}

function activePreset(config) {
  const name = config.preset;
  const preset = config.presets?.[name];
  if (!preset || typeof preset !== "object" || Array.isArray(preset)) {
    const error = new Error(`active preset not found: ${name || "?"}`);
    error.status = 409;
    throw error;
  }
  return { name, preset };
}

function normalizeModelEntry(entry) {
  if (typeof entry === "string") return { id: entry, variant: null };
  if (entry && typeof entry === "object" && entry.id) {
    return { id: entry.id, variant: entry.variant || null };
  }
  return null;
}

function profileForEntry(entry) {
  if (
    !entry ||
    typeof entry !== "object" ||
    entry.inheritModelFrom === "session"
  ) {
    return { mode: "session", model: null, variant: null, fallback: null };
  }
  const models = (
    Array.isArray(entry.model) ? entry.model : [entry.model]
  )
    .map(normalizeModelEntry)
    .filter(Boolean);
  if (!models.length) {
    return { mode: "session", model: null, variant: null, fallback: null };
  }
  return {
    mode: "model",
    model: models[0].id,
    variant: models[0].variant || entry.variant || null,
    fallback: models[1] || null,
  };
}

function profilesFromConfig(config) {
  const { name, preset } = activePreset(config);
  const profiles = {};
  for (const agent of PROFILE_AGENTS) {
    profiles[agent] = profileForEntry(preset[agent]);
  }
  return { preset: name, profiles };
}

function getProfiles() {
  return profilesFromConfig(readOmoConfig());
}

async function setProfile(
  agent,
  mode,
  modelID,
  variant,
  fallbackID,
  fallbackVariant,
) {
  if (!PROFILE_AGENTS.includes(agent)) {
    const error = new Error(`unknown agent: ${agent}`);
    error.status = 400;
    throw error;
  }
  if (mode !== "session" && mode !== "model") {
    const error = new Error("mode must be session or model");
    error.status = 400;
    throw error;
  }
  const config = readOmoConfig();
  const { preset } = activePreset(config);
  const entry =
    preset[agent] && typeof preset[agent] === "object"
      ? { ...preset[agent] }
      : {};
  if (mode === "session") {
    delete entry.model;
    delete entry.variant;
    entry.inheritModelFrom = "session";
  } else {
    const catalog = await fetchModelCatalog();
    const model = catalog.models.find((item) => item.id === modelID);
    if (!model) {
      const error = new Error(`unknown model: ${modelID}`);
      error.status = 400;
      throw error;
    }
    delete entry.inheritModelFrom;
    const chosen = { id: model.id };
    if (variant && model.variants.includes(variant)) {
      chosen.variant = variant;
    }
    entry.model = [chosen];
    if (fallbackID && fallbackID !== modelID) {
      const fallback = catalog.models.find((item) => item.id === fallbackID);
      if (!fallback) {
        const error = new Error(`unknown fallback model: ${fallbackID}`);
        error.status = 400;
        throw error;
      }
      const chosenFallback = { id: fallback.id };
      if (fallbackVariant && fallback.variants.includes(fallbackVariant)) {
        chosenFallback.variant = fallbackVariant;
      }
      entry.model.push(chosenFallback);
    }
    delete entry.variant;
  }
  preset[agent] = entry;
  if (process.env.AGENT_BOARD_PROFILE_DRY_RUN !== "1") {
    writeOmoConfig(config);
  }
  return {
    dryRun: process.env.AGENT_BOARD_PROFILE_DRY_RUN === "1",
    ...profilesFromConfig(config),
  };
}

async function getSetup() {
  const defaultModel = await getDefaultModel();
  let preset = null;
  try {
    preset = readOmoConfig().preset || null;
  } catch {
    preset = null;
  }
  return { hasModel: Boolean(defaultModel), defaultModel, preset };
}

function setPreset(name) {
  if (name !== "session" && name !== "opencode-go") {
    const error = new Error("unknown preset");
    error.status = 400;
    throw error;
  }
  const config = readOmoConfig();
  if (!config.presets?.[name]) {
    const error = new Error(`preset not found: ${name}`);
    error.status = 400;
    throw error;
  }
  config.preset = name;
  if (process.env.AGENT_BOARD_PROFILE_DRY_RUN !== "1") {
    writeOmoConfig(config);
  }
  return {
    dryRun: process.env.AGENT_BOARD_PROFILE_DRY_RUN === "1",
    ...profilesFromConfig(config),
  };
}

function projectConfigPath(project) {
  const dir = path.resolve(String(project || ""));
  if (!project || !fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) {
    const error = new Error("project directory not found");
    error.status = 400;
    throw error;
  }
  return path.join(dir, ".opencode", "oh-my-opencode-slim.json");
}

function projectPresetName(project) {
  return (
    "project-" +
    crypto
      .createHash("sha1")
      .update(path.resolve(project).toLowerCase())
      .digest("hex")
      .slice(0, 8)
  );
}

function readProjectConfig(project) {
  const file = projectConfigPath(project);
  if (!fs.existsSync(file)) return { file, config: null };
  try {
    return {
      file,
      config: JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, "")),
    };
  } catch {
    const error = new Error("project OMO config is invalid");
    error.status = 409;
    throw error;
  }
}

function profilesFromPreset(presetName, preset) {
  const profiles = {};
  for (const agent of PROFILE_AGENTS) {
    profiles[agent] = profileForEntry(preset[agent]);
  }
  return { preset: presetName, profiles };
}

function getProfilesForProject(project) {
  if (!project) return { ...getProfiles(), projectProfile: false, project: null };
  const { config } = readProjectConfig(project);
  if (!config || !config.preset || !config.presets?.[config.preset]) {
    return {
      ...getProfiles(),
      projectProfile: false,
      project: path.resolve(project),
    };
  }
  return {
    ...profilesFromPreset(config.preset, config.presets[config.preset]),
    projectProfile: true,
    project: path.resolve(project),
  };
}

async function setProjectProfile(
  project,
  agent,
  mode,
  modelID,
  variant,
  fallbackID,
  fallbackVariant,
) {
  if (!PROFILE_AGENTS.includes(agent)) {
    const error = new Error(`unknown agent: ${agent}`);
    error.status = 400;
    throw error;
  }
  if (mode !== "session" && mode !== "model") {
    const error = new Error("mode must be session or model");
    error.status = 400;
    throw error;
  }
  const globalConfig = readOmoConfig();
  const { preset: globalPreset } = activePreset(globalConfig);
  const cloned = JSON.parse(JSON.stringify(globalPreset));
  const entry =
    cloned[agent] && typeof cloned[agent] === "object"
      ? { ...cloned[agent] }
      : {};
  if (mode === "session") {
    delete entry.model;
    delete entry.variant;
    entry.inheritModelFrom = "session";
  } else {
    const catalog = await fetchModelCatalog();
    const model = catalog.models.find((item) => item.id === modelID);
    if (!model) {
      const error = new Error(`unknown model: ${modelID}`);
      error.status = 400;
      throw error;
    }
    delete entry.inheritModelFrom;
    const chosen = { id: model.id };
    if (variant && model.variants.includes(variant)) {
      chosen.variant = variant;
    }
    entry.model = [chosen];
    if (fallbackID && fallbackID !== modelID) {
      const fallback = catalog.models.find((item) => item.id === fallbackID);
      if (!fallback) {
        const error = new Error(`unknown fallback model: ${fallbackID}`);
        error.status = 400;
        throw error;
      }
      const chosenFallback = { id: fallback.id };
      if (fallbackVariant && fallback.variants.includes(fallbackVariant)) {
        chosenFallback.variant = fallbackVariant;
      }
      entry.model.push(chosenFallback);
    }
    delete entry.variant;
  }
  cloned[agent] = entry;
  const name = projectPresetName(project);
  const config = {
    $schema:
      "https://unpkg.com/oh-my-opencode-slim@3.0.7/oh-my-opencode-slim.schema.json",
    preset: name,
    presets: { [name]: cloned },
  };
  const { file } = readProjectConfig(project);
  if (process.env.AGENT_BOARD_PROFILE_DRY_RUN !== "1") {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    if (fs.existsSync(file)) {
      const backupRoot = path.join(
        path.dirname(file),
        "backups",
        `${new Date().toISOString().replace(/[:.]/g, "-")}-profile`,
      );
      fs.mkdirSync(backupRoot, { recursive: true });
      fs.copyFileSync(
        file,
        path.join(backupRoot, "oh-my-opencode-slim.json"),
      );
    }
    fs.writeFileSync(file, JSON.stringify(config, null, 2) + "\n", "utf8");
  }
  return {
    dryRun: process.env.AGENT_BOARD_PROFILE_DRY_RUN === "1",
    ...profilesFromPreset(name, cloned),
    projectProfile: true,
    project: path.resolve(project),
  };
}

function resetProjectProfile(project) {
  const { file } = readProjectConfig(project);
  if (fs.existsSync(file) && process.env.AGENT_BOARD_PROFILE_DRY_RUN !== "1") {
    const backupRoot = path.join(
      path.dirname(file),
      "backups",
      `${new Date().toISOString().replace(/[:.]/g, "-")}-profile-reset`,
    );
    fs.mkdirSync(backupRoot, { recursive: true });
    fs.copyFileSync(file, path.join(backupRoot, "oh-my-opencode-slim.json"));
    fs.rmSync(file, { force: true });
  }
  return {
    ok: true,
    dryRun: process.env.AGENT_BOARD_PROFILE_DRY_RUN === "1",
    ...getProfiles(),
    projectProfile: false,
    project: path.resolve(project),
  };
}

function toolDescription(name, input) {
  if (name === "subagent" || name === "task") {
    return [input.agent, input.description].filter(Boolean).join(" — ") || name;
  }
  if (name === "shell") return input.command || name;
  if (name === "read" || name === "write" || name === "edit") {
    return input.filePath || input.path || name;
  }
  if (name === "grep" || name === "glob") return input.pattern || name;
  if (name === "webfetch") return input.url || name;
  return (
    input.description ||
    input.command ||
    input.path ||
    input.filePath ||
    input.pattern ||
    input.url ||
    name
  );
}

async function getSessionChildren(sessionID) {
  try {
    const response = await upstream(
      `/api/session?parentID=${encodeURIComponent(sessionID)}&limit=50`,
      8000,
    );
    const list = Array.isArray(response) ? response : response.data || [];
    return list.map((session) => ({
      id: session.id,
      parentID: session.parentID,
      agent: session.agent,
      title: session.title,
      outcome: session.outcome,
      time: session.time,
      location: session.location,
    }));
  } catch {
    return [];
  }
}

async function getSessionDetail(sessionID) {
  const sessionResponse = await upstream(
    `/api/session/${encodeURIComponent(sessionID)}`,
  );
  const session = Array.isArray(sessionResponse)
    ? sessionResponse[0]
    : sessionResponse.data || sessionResponse;
  if (!session || !session.id) {
    const error = new Error("session not found");
    error.status = 404;
    throw error;
  }
  const messagesResponse = await upstream(
    `/api/session/${encodeURIComponent(sessionID)}/message?limit=25`,
    8000,
  );
  const messages = Array.isArray(messagesResponse)
    ? messagesResponse
    : messagesResponse.data || [];
  const tools = [];
  const errors = [];
  for (const message of messages) {
    for (const part of message.content || message.parts || []) {
      if (part.type !== "tool") continue;
      const state = part.state || {};
      const input = state.input || {};
      const startedAt =
        state.time?.created || state.time?.ran || message.time?.created || null;
      const completedAt =
        state.time?.completed || message.time?.completed || null;
      const error = state.error?.message || null;
      tools.push({
        id: part.id || `${startedAt || 0}:${part.name}`,
        name: part.name || "tool",
        status: state.status || "unknown",
        description: redact(toolDescription(part.name, input)),
        startedAt,
        completedAt,
        durationMs: startedAt
          ? Math.max(0, (completedAt || Date.now()) - startedAt)
          : null,
        error: error ? redact(error) : null,
        agent: input.agent || null,
      });
      if (error) {
        errors.push({
          tool: part.name || "tool",
          message: redact(error),
          at: completedAt || startedAt,
        });
      }
    }
  }
  tools.sort((a, b) => (b.startedAt || 0) - (a.startedAt || 0));
  return {
    session: {
      id: session.id,
      title: session.title || session.id,
      agent: session.agent || null,
      model: session.model
        ? `${session.model.providerID || ""}/${session.model.id || ""}`
        : null,
      outcome: session.outcome || null,
      parentID: session.parentID || null,
      directory: session.location?.directory || null,
      created: session.time?.created || null,
      updated: session.time?.updated || null,
      tokens: session.tokens || null,
      cost: session.cost || 0,
      error: session.error?.message ? redact(session.error.message) : null,
    },
    tools: tools.slice(0, 30),
    errors: errors.slice(0, 10),
    children: await getSessionChildren(sessionID),
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function extractAssistantText(messages) {
  for (const message of messages) {
    if (message.type !== "assistant") continue;
    const parts = message.content || message.parts || [];
    const text = parts
      .filter((part) => part.type === "text" && part.text)
      .map((part) => part.text)
      .join(" ")
      .trim();
    if (text) return text.slice(0, 240);
  }
  return null;
}

async function testModel(modelID, variant, project) {
  const catalog = await fetchModelCatalog();
  const model = catalog.models.find((item) => item.id === modelID);
  if (!model) {
    const error = new Error(`unknown model: ${modelID}`);
    error.status = 400;
    throw error;
  }
  const directory =
    project && fs.existsSync(project) ? project : process.cwd();
  const started = Date.now();
  let sessionID = null;
  try {
    const created = await upstreamJson(
      "POST",
      "/api/session",
      {
        title: "Ajan Panosu model test",
        agent: "build",
        model: {
          id: model.modelID,
          providerID: model.providerID,
          ...(variant && model.variants.includes(variant) ? { variant } : {}),
        },
        location: { directory },
      },
      15000,
    );
    const session = created.data || created;
    sessionID = session.id;
    if (!sessionID) throw new Error("session id alinamadi");
    await upstreamJson(
      "POST",
      `/api/session/${encodeURIComponent(sessionID)}/prompt`,
      { text: "Yalnızca OK yaz.", resume: true },
      10000,
    );
    let reply = null;
    for (let attempt = 0; attempt < 90; attempt += 1) {
      await sleep(500);
      const response = await upstream(
        `/api/session/${encodeURIComponent(sessionID)}/message?limit=10`,
        8000,
      );
      const messages = Array.isArray(response) ? response : response.data || [];
      reply = extractAssistantText(messages);
      if (reply) break;
    }
    return {
      ok: Boolean(reply),
      model: model.id,
      variant: variant || null,
      reply,
      durationMs: Date.now() - started,
      tools: model.tools,
      vision: model.vision,
    };
  } finally {
    if (sessionID) {
      await upstreamDelete(
        `/api/session/${encodeURIComponent(sessionID)}`,
        8000,
      ).catch(() => {});
    }
  }
}

function buildAnalytics(sessions, tasks, activeIds) {
  const map = new Map();
  const ensure = (agent) => {
    if (!map.has(agent)) {
      map.set(agent, {
        agent,
        sessions: 0,
        succeeded: 0,
        failed: 0,
        interrupted: 0,
        running: 0,
        tokens: 0,
        cost: 0,
        durationMs: 0,
        stuckTasks: 0,
      });
    }
    return map.get(agent);
  };
  for (const session of sessions) {
    const item = ensure(session.agent || "?");
    item.sessions += 1;
    if (session.outcome === "succeeded") item.succeeded += 1;
    else if (session.outcome === "failed") item.failed += 1;
    else if (session.outcome === "interrupted") item.interrupted += 1;
    else if (activeIds.has(session.id)) item.running += 1;
    const tokens = session.tokens || {};
    item.tokens +=
      (tokens.input || 0) + (tokens.output || 0) + (tokens.reasoning || 0);
    item.cost += Number(session.cost) || 0;
    if (session.time?.created && session.time?.updated) {
      item.durationMs += Math.max(0, session.time.updated - session.time.created);
    }
  }
  for (const task of tasks) {
    if (!task.stuck) continue;
    ensure(task.sessionAgent || "?").stuckTasks += 1;
  }
  return [...map.values()]
    .map((item) => ({
      ...item,
      avgDurationMs: item.sessions
        ? Math.round(item.durationMs / item.sessions)
        : 0,
    }))
    .sort((a, b) => b.sessions - a.sessions);
}

function readGuardLog(limit = 200) {
  if (!fs.existsSync(GUARD_LOG)) return { path: GUARD_LOG, lines: [] };
  const lines = fs
    .readFileSync(GUARD_LOG, "utf8")
    .replace(/^\uFEFF/, "")
    .split(/\r?\n/)
    .filter(Boolean)
    .slice(-limit)
    .map((line) => redact(line, 500));
  return { path: GUARD_LOG, lines };
}

function archiveBoard(boardPath) {
  const resolved = path.resolve(String(boardPath || ""));
  const marker = `${path.sep}.opencode${path.sep}plans${path.sep}boards${path.sep}`;
  const index = resolved.toLowerCase().lastIndexOf(marker.toLowerCase());
  if (index <= 0) {
    const error = new Error("board path is not under .opencode/plans/boards");
    error.status = 400;
    throw error;
  }
  if (!resolved.toLowerCase().endsWith(".md")) {
    const error = new Error("board must be a markdown file");
    error.status = 400;
    throw error;
  }
  if (!fs.existsSync(resolved)) {
    const error = new Error("board not found");
    error.status = 404;
    throw error;
  }
  const projectDir = resolved.slice(0, index);
  const month = new Date().toISOString().slice(0, 7);
  const archiveDir = path.join(
    projectDir,
    ".opencode",
    "plans",
    "archive",
    month,
    "boards",
  );
  fs.mkdirSync(archiveDir, { recursive: true });
  const target = path.join(archiveDir, path.basename(resolved));
  if (fs.existsSync(target)) {
    const error = new Error("archive target already exists");
    error.status = 409;
    throw error;
  }
  fs.renameSync(resolved, target);
  const readme = path.join(path.dirname(archiveDir), "README.md");
  const line = `- ${path.basename(resolved, ".md")}: panelden arsivlendi (${new Date().toISOString().slice(0, 10)})`;
  if (fs.existsSync(readme)) {
    fs.appendFileSync(readme, `\n${line}\n`, "utf8");
  } else {
    fs.writeFileSync(readme, `# Arsiv\n\n${line}\n`, "utf8");
  }
  return { ok: true, archived: target, project: projectDir };
}

async function getDiagnostic() {
  const setup = await getSetup();
  let profiles = null;
  try {
    profiles = getProfiles();
  } catch {
    profiles = null;
  }
  let omoConfig = null;
  try {
    omoConfig = readOmoConfig();
  } catch {
    omoConfig = null;
  }
  let opencodeConfig = null;
  try {
    const raw = fs
      .readFileSync(path.join(CONFIG_DIR, "opencode.json"), "utf8")
      .replace(/^\uFEFF/, "");
    const config = JSON.parse(raw);
    opencodeConfig = {
      model: config.model || null,
      default_agent: config.default_agent || null,
      plugins: config.plugins || [],
    };
  } catch {
    opencodeConfig = null;
  }
  const logDir = path.join(HOME, ".local", "share", "opencode", "log");
  const logTails = {};
  try {
    const names = ["opencode.log"];
    const omoLogs = fs
      .readdirSync(logDir)
      .filter((name) => name.startsWith("oh-my-opencode-slim."))
      .sort();
    if (omoLogs.length) names.push(omoLogs[omoLogs.length - 1]);
    for (const name of names) {
      const file = path.join(logDir, name);
      if (!fs.existsSync(file)) continue;
      logTails[name] = fs
        .readFileSync(file, "utf8")
        .split(/\r?\n/)
        .slice(-100)
        .map((line) => redact(line, 500));
    }
  } catch {
    // Logs are optional in the diagnostic bundle.
  }
  return {
    generatedAt: new Date().toISOString(),
    version: PANEL_VERSION,
    platform: process.platform,
    node: process.version,
    cwd: process.cwd(),
    configDir: CONFIG_DIR,
    setup,
    profiles,
    omoConfig,
    opencodeConfig,
    guardLog: readGuardLog(100).lines,
    logTails,
  };
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
      const html = fs
        .readFileSync(INDEX_HTML, "utf8")
        .replaceAll("__PANEL_TOKEN__", PANEL_TOKEN);
      res.writeHead(200, {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(html);
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
      if (!isAllowedOrigin(req)) {
        res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
        res.end("forbidden origin");
        return;
      }
      if (!isPanelTokenValid(req)) {
        res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
        res.end("forbidden token");
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
    if (url.pathname === "/api/setup") {
      const setup = await getSetup();
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(JSON.stringify({ ...setup, version: PANEL_VERSION }));
      return;
    }
    if (url.pathname === "/api/models") {
      const catalog = await fetchModelCatalog();
      const project = url.searchParams.get("project") || null;
      const profiles = getProfilesForProject(project);
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(
        JSON.stringify({
          models: catalog.models,
          defaultModel: catalog.defaultModel,
          ...profiles,
        }),
      );
      return;
    }
    if (url.pathname === "/api/profile") {
      if (req.method !== "POST") {
        res.writeHead(405, { "content-type": "text/plain; charset=utf-8" });
        res.end("method not allowed");
        return;
      }
      if (!isAllowedOrigin(req)) {
        res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
        res.end("forbidden origin");
        return;
      }
      if (!isPanelTokenValid(req)) {
        res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
        res.end("forbidden token");
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
      const profileArgs = [
        String(body.agent || ""),
        String(body.mode || ""),
        String(body.model || ""),
        body.variant ? String(body.variant) : null,
        body.fallback ? String(body.fallback) : null,
        body.fallbackVariant ? String(body.fallbackVariant) : null,
      ];
      const result =
        body.scope === "project" && body.project
          ? await setProjectProfile(
              String(body.project),
              ...profileArgs,
            )
          : await setProfile(...profileArgs);
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(JSON.stringify(result));
      return;
    }
    if (url.pathname === "/api/session-detail") {
      const sessionID = url.searchParams.get("session") || "";
      if (!/^ses_[A-Za-z0-9]+$/.test(sessionID)) {
        res.writeHead(400, { "content-type": "text/plain; charset=utf-8" });
        res.end("invalid session id");
        return;
      }
      const detail = await getSessionDetail(sessionID);
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(JSON.stringify(detail));
      return;
    }
    if (url.pathname === "/api/update") {
      const update = await checkUpdate();
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(JSON.stringify(update));
      return;
    }
    if (url.pathname === "/api/guard-log") {
      const data = readGuardLog(200);
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(JSON.stringify(data));
      return;
    }
    if (url.pathname === "/api/diagnostic") {
      const data = await getDiagnostic();
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
        "content-disposition": 'attachment; filename="ajan-panosu-diagnostic.json"',
      });
      res.end(JSON.stringify(data, null, 2));
      return;
    }
    if (url.pathname === "/api/preset") {
      if (req.method !== "POST") {
        res.writeHead(405, { "content-type": "text/plain; charset=utf-8" });
        res.end("method not allowed");
        return;
      }
      if (!isAllowedOrigin(req) || !isPanelTokenValid(req)) {
        res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
        res.end("forbidden");
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
      const result = setPreset(String(body.preset || ""));
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(JSON.stringify(result));
      return;
    }
    if (url.pathname === "/api/model-test") {
      if (req.method !== "POST") {
        res.writeHead(405, { "content-type": "text/plain; charset=utf-8" });
        res.end("method not allowed");
        return;
      }
      if (!isAllowedOrigin(req) || !isPanelTokenValid(req)) {
        res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
        res.end("forbidden");
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
      let result;
      try {
        result = await testModel(
          String(body.model || ""),
          body.variant ? String(body.variant) : null,
          body.project ? String(body.project) : null,
        );
      } catch (error) {
        result = {
          ok: false,
          model: String(body.model || ""),
          error: String(error.message || error),
        };
      }
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(JSON.stringify(result));
      return;
    }
    if (url.pathname === "/api/archive-board") {
      if (req.method !== "POST") {
        res.writeHead(405, { "content-type": "text/plain; charset=utf-8" });
        res.end("method not allowed");
        return;
      }
      if (!isAllowedOrigin(req) || !isPanelTokenValid(req)) {
        res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
        res.end("forbidden");
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
      const result = archiveBoard(String(body.path || ""));
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(JSON.stringify(result));
      return;
    }
    if (url.pathname === "/api/project-profile/reset") {
      if (req.method !== "POST") {
        res.writeHead(405, { "content-type": "text/plain; charset=utf-8" });
        res.end("method not allowed");
        return;
      }
      if (!isAllowedOrigin(req) || !isPanelTokenValid(req)) {
        res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
        res.end("forbidden");
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
      const result = resetProjectProfile(String(body.project || ""));
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(JSON.stringify(result));
      return;
    }
    if (url.pathname === "/api/retry") {
      if (req.method !== "POST") {
        res.writeHead(405, { "content-type": "text/plain; charset=utf-8" });
        res.end("method not allowed");
        return;
      }
      if (!isAllowedOrigin(req) || !isPanelTokenValid(req)) {
        res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
        res.end("forbidden");
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
      const description = redact(String(body.description || ""), 200);
      const text = description
        ? `Önceki takılan alt görevi tekrar dene: ${description}. Önce git status kontrol et; yarım değişiklikleri koru.`
        : "Önceki takılan alt görevi tekrar dene. Önce git status kontrol et; yarım değişiklikleri koru.";
      const result = await upstreamJson(
        "POST",
        `/api/session/${encodeURIComponent(sessionID)}/prompt`,
        { text, resume: true },
        15000,
      );
      res.writeHead(200, {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(JSON.stringify({ ok: true, result }));
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
      const setup = await getSetup().catch(() => ({
        hasModel: false,
        defaultModel: null,
        preset: null,
      }));
      const allBoards = readBoards(sessionList, activeMap);
      const projects = listProjects(sessionList, allBoards);
      const activeIds = new Set(Object.keys(activeMap));
      const stuckMs = parseStuckMs(url);
      let allTasks = [];
      try {
        allTasks = await collectTasks(sessionList, activeMap, stuckMs);
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
      const analytics = buildAnalytics(
        selectedSessions,
        selectedTasks,
        activeIds,
      );
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
          stuckMs,
          analytics,
          setup,
          version: PANEL_VERSION,
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
