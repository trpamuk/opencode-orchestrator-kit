import fs from "node:fs";
import path from "node:path";

const [command, target, source] = process.argv.slice(2);

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
  } catch {
    return null;
  }
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n", "utf8");
}

if (!command || !target) {
  console.error("usage: install-config.mjs opencode|omo|model <target> <source>");
  process.exit(1);
}

if (command === "opencode") {
  if (!source) {
    console.error("missing template");
    process.exit(1);
  }
  const template = readJson(source);
  if (!template) {
    console.error("template is not valid JSON: " + source);
    process.exit(1);
  }
  const exists = fs.existsSync(target);
  const existing = readJson(target);
  if (exists && !existing) {
    const fallback = target + ".kit.json";
    writeJson(fallback, template);
    console.warn("existing opencode.json is invalid; wrote " + fallback);
    process.exit(0);
  }
  if (!existing) {
    writeJson(target, template);
    process.exit(0);
  }
  const plugins = [
    ...new Set([...(existing.plugins || []), ...(template.plugins || [])]),
  ];
  const merged = { ...existing, plugins };
  if (template.default_agent) merged.default_agent = template.default_agent;
  writeJson(target, merged);
  process.exit(0);
}

if (command === "omo") {
  if (!source) {
    console.error("missing template");
    process.exit(1);
  }
  const template = readJson(source);
  if (!template) {
    console.error("template is not valid JSON: " + source);
    process.exit(1);
  }
  const existing = readJson(target);
  if (fs.existsSync(target) && !existing) {
    fs.copyFileSync(target, target + ".bak");
  }
  if (
    existing &&
    ["session", "opencode-go"].includes(existing.preset) &&
    template.presets?.[existing.preset]
  ) {
    template.preset = existing.preset;
  }
  writeJson(target, template);
  process.exit(0);
}

if (command === "model") {
  const existing = readJson(target);
  if (!existing) {
    console.error("opencode.json is missing or invalid: " + target);
    process.exit(1);
  }
  if (source === "--clear") {
    delete existing.model;
  } else if (source) {
    existing.model = source;
  } else {
    console.error("missing model");
    process.exit(1);
  }
  writeJson(target, existing);
  process.exit(0);
}

console.error("unknown command: " + command);
process.exit(1);
