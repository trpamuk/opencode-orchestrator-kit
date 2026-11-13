import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "opencode-panel-test-"));
const configDir = path.join(temp, ".config", "opencode");
fs.mkdirSync(configDir, { recursive: true });
const omoConfig = path.join(configDir, "oh-my-opencode-slim.json");
fs.writeFileSync(
  omoConfig,
  JSON.stringify(
    {
      preset: "session",
      presets: {
        session: {
          orchestrator: { model: "test/model" },
        },
      },
      apiKey: "sk-test-secret-12345678",
      nested: { password: "super-secret-password", safe: "ok" },
      headers: { Authorization: "Bearer bearer-token-value" },
    },
    null,
    2,
  ),
);

const port = 43200 + Math.floor(Math.random() * 300);
const base = `http://127.0.0.1:${port}`;
const server = spawn(process.execPath, [path.join(root, "agent-board", "server.mjs")], {
  env: {
    ...process.env,
    USERPROFILE: temp,
    HOME: temp,
    AGENT_BOARD_PORT: String(port),
    AGENT_BOARD_OMO_CONFIG: omoConfig,
    AGENT_BOARD_FAKE_NO_MODEL: "1",
  },
  stdio: ["ignore", "pipe", "pipe"],
  windowsHide: true,
});
let stderr = "";
server.stderr.on("data", (chunk) => {
  stderr += chunk.toString();
});

async function waitForHealth() {
  for (let i = 0; i < 50; i += 1) {
    try {
      const response = await fetch(`${base}/health`);
      if (response.ok && (await response.text()) === "ok") return;
    } catch {
      // Server is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`panel did not start\n${stderr}`);
}

try {
  await waitForHealth();

  const html = await (await fetch(`${base}/`)).text();
  const token = /name="panel-token" content="([a-f0-9]{48})"/.exec(html)?.[1];
  assert.ok(token, "panel token missing");

  const writeEndpoints = [
    "/api/interrupt",
    "/api/profile",
    "/api/preset",
    "/api/project-profile/reset",
    "/api/archive-board",
    "/api/model-test",
    "/api/retry",
  ];
  for (const endpoint of writeEndpoints) {
    const response = await fetch(`${base}${endpoint}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    });
    assert.equal(response.status, 403, `${endpoint} should reject a missing token`);
  }

  const wrongToken = await fetch(`${base}/api/preset`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-panel-token": "0".repeat(48),
    },
    body: JSON.stringify({ preset: "session" }),
  });
  assert.equal(wrongToken.status, 403, "wrong token should be rejected");

  const badOrigin = await fetch(`${base}/api/preset`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-panel-token": token,
      origin: "http://evil.example",
    },
    body: JSON.stringify({ preset: "session" }),
  });
  assert.equal(badOrigin.status, 403, "foreign origin should be rejected");

  const badPreset = await fetch(`${base}/api/preset`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-panel-token": token,
    },
    body: JSON.stringify({ preset: "bogus" }),
  });
  assert.equal(badPreset.status, 400, "unknown preset should be rejected");

  const traversal = await fetch(`${base}/assets/%2e%2e%2fserver.mjs`);
  assert.equal(traversal.status, 404, "asset traversal should be blocked");

  const diagnosticNoToken = await fetch(`${base}/api/diagnostic`);
  assert.equal(diagnosticNoToken.status, 403, "diagnostic should reject a missing token");
  const diagnostic = await (
    await fetch(`${base}/api/diagnostic`, {
      headers: { "x-panel-token": token },
    })
  ).json();
  const diagnosticText = JSON.stringify(diagnostic);
  assert.equal(diagnostic.omoConfig.apiKey, "***", "apiKey should be masked");
  assert.equal(diagnostic.omoConfig.nested.password, "***", "password should be masked");
  assert.equal(diagnostic.omoConfig.nested.safe, "ok", "safe values should be preserved");
  assert.ok(!diagnosticText.includes("sk-test-secret-12345678"), "raw API key leaked");
  assert.ok(!diagnosticText.includes("super-secret-password"), "raw password leaked");
  assert.ok(!diagnosticText.includes("bearer-token-value"), "raw bearer token leaked");

  console.log("Panel API tests passed.");
} finally {
  server.kill();
  fs.rmSync(temp, { recursive: true, force: true });
}
