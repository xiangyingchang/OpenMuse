import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const extension = path.join(root, "Sources/OpenMuseCore/Resources/openmuse-pi-read.mjs");
const piCandidates = (process.env.PATH ?? "").split(path.delimiter).map((entry) => path.join(entry, "pi"));
const piExecutable = process.env.PI_BIN ?? piCandidates.find((candidate) => spawnSync(candidate, ["--version"], { stdio: "ignore" }).status === 0);

test("Pi RPC calls the scoped OpenMuse read tool and returns only its result", { skip: !piExecutable }, async (t) => {
	const base = await mkdtemp(path.join(os.tmpdir(), "openmuse-pi-runtime-"));
	const piHome = path.join(base, "pi-home");
	const readRoot = path.join(base, "snapshot");
	await mkdir(readRoot, { recursive: true });
	await writeFile(path.join(readRoot, "trip.md"), "七天旅行的本地只读资料。", "utf8");
	t.after(() => rm(base, { recursive: true, force: true }));

	let requestCount = 0;
	let secondRequest;
	const server = createServer(async (request, response) => {
		const chunks = [];
		for await (const chunk of request) chunks.push(chunk);
		const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
		requestCount += 1;
		if (requestCount === 1) {
			assert.deepEqual(body.tools.map((tool) => tool.function.name), ["openmuse_list_files", "openmuse_read_file"]);
			response.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache" });
			response.write(`data: ${JSON.stringify({ id: "fixture-1", object: "chat.completion.chunk", created: 1, model: "fixture", choices: [{ index: 0, delta: { role: "assistant", tool_calls: [{ index: 0, id: "call-read-1", type: "function", function: { name: "openmuse_read_file", arguments: JSON.stringify({ path: "trip.md" }) } }] }, finish_reason: null }] })}\n\n`);
			response.write(`data: ${JSON.stringify({ id: "fixture-1", object: "chat.completion.chunk", created: 1, model: "fixture", choices: [{ index: 0, delta: {}, finish_reason: "tool_calls" }] })}\n\n`);
			response.end("data: [DONE]\n\n");
			return;
		}
		secondRequest = body;
		const toolMessage = body.messages.find((message) => message.role === "tool");
		response.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache" });
		response.write(`data: ${JSON.stringify({ id: "fixture-2", object: "chat.completion.chunk", created: 2, model: "fixture", choices: [{ index: 0, delta: { role: "assistant", content: "我读到了本地旅行资料。" }, finish_reason: null }] })}\n\n`);
		response.write(`data: ${JSON.stringify({ id: "fixture-2", object: "chat.completion.chunk", created: 2, model: "fixture", choices: [{ index: 0, delta: {}, finish_reason: "stop" }] })}\n\n`);
		response.end("data: [DONE]\n\n");
	});
	await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
	t.after(() => new Promise((resolve) => server.close(resolve)));
	const address = server.address();
	assert.ok(address && typeof address === "object");
	await mkdir(piHome, { recursive: true });
	await writeFile(path.join(piHome, "models.json"), JSON.stringify({ providers: { openmuse: {
		name: "OpenMuse", baseUrl: `http://127.0.0.1:${address.port}/v1`, api: "openai-completions", apiKey: "$OPENMUSE_API_KEY",
		models: [{ id: "fixture", name: "fixture", api: "openai-completions", contextWindow: 8192, maxTokens: 1024, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }],
	} } }));

	const child = spawn(piExecutable, [
		"--mode", "rpc", "--no-session", "--no-extensions", "--no-mcp", "--no-skills", "--no-context-files",
		"--no-builtin-tools", "--extension", extension, "--tools", "openmuse_list_files,openmuse_read_file",
		"--provider", "openmuse", "--model", "fixture", "--thinking", "off",
	], { env: { ...process.env, PI_CODING_AGENT_DIR: piHome, OPENMUSE_API_KEY: "fixture-key", OPENMUSE_READ_ROOT: readRoot }, stdio: ["pipe", "pipe", "pipe"] });
	let stdout = "";
	let stderr = "";
	child.stdout.setEncoding("utf8").on("data", (chunk) => {
		stdout += chunk;
		if (stdout.includes('"type":"agent_settled"')) child.stdin.end();
	});
	child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
	child.stdin.write(`${JSON.stringify({ id: "read-test", type: "prompt", message: "请读一下本地旅行资料。" })}\n`);
	let timeout;
	const exitCode = await Promise.race([
		new Promise((resolve) => child.once("close", (code) => resolve(code))),
		new Promise((_, reject) => { timeout = setTimeout(() => { child.kill("SIGTERM"); reject(new Error("Pi RPC timed out")); }, 20_000); }),
	]);
	clearTimeout(timeout);
	assert.equal(exitCode, 0, stderr);
	const records = stdout.split("\n").filter(Boolean).map((line) => JSON.parse(line));
	assert.ok(records.some((record) => record.type === "tool_execution_start" && record.toolName === "openmuse_read_file"), `missing tool start\n${stdout}\n${stderr}`);
	assert.ok(records.some((record) => record.type === "tool_execution_end" && record.toolName === "openmuse_read_file" && record.isError === false), `missing tool success\n${stdout}\n${stderr}`);
	assert.ok(records.some((record) => record.type === "message_end" && JSON.stringify(record.message).includes("我读到了本地旅行资料。")));
	assert.equal(requestCount, 2);
	assert.ok(secondRequest);
	const toolMessage = secondRequest.messages.find((message) => message.role === "tool");
	assert.ok(toolMessage, JSON.stringify(secondRequest.messages));
	assert.match(toolMessage.content, /七天旅行的本地只读资料/);
});
