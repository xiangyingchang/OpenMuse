import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { createOpenMuseReadTools } from "../../Sources/OpenMuseCore/Resources/openmuse-pi-read.mjs";

async function fixture(t) {
	const base = await mkdtemp(path.join(os.tmpdir(), "openmuse-pi-read-"));
	const root = path.join(base, "approved");
	const outside = path.join(base, "outside.md");
	await mkdir(path.join(root, "notes"), { recursive: true });
	await writeFile(path.join(root, "notes", "trip.md"), "旅行计划只读测试。", "utf8");
	await writeFile(path.join(root, ".private.md"), "隐藏内容", "utf8");
	await writeFile(path.join(root, "credentials.env"), "token=secret", "utf8");
	await writeFile(outside, "文件夹外的私密内容", "utf8");
	await symlink(outside, path.join(root, "escape.md"));
	t.after(() => rm(base, { recursive: true, force: true }));
	return { root, outside };
}

function findTool(root, name) {
	const tool = createOpenMuseReadTools(root).find((candidate) => candidate.name === name);
	assert.ok(tool, `missing tool ${name}`);
	return tool;
}

test("lists only visible, supported text files and omits symlinks", async (t) => {
	const { root } = await fixture(t);
	const tool = findTool(root, "openmuse_list_files");
	const response = await tool.execute("list", { path: "" });
	const { files } = JSON.parse(response.content[0].text);
	assert.deepEqual(files.map((file) => file.path), ["notes/trip.md"]);
	assert.equal(response.isError, undefined);
});

test("reads a selected relative file but rejects traversal, absolute paths, symlinks, and unsupported files", async (t) => {
	const { root, outside } = await fixture(t);
	const tool = findTool(root, "openmuse_read_file");
	const ok = await tool.execute("read", { path: "notes/trip.md" });
	assert.equal(JSON.parse(ok.content[0].text).content, "旅行计划只读测试。");
	for (const value of ["../outside.md", outside, "escape.md", "credentials.env", ".private.md"]) {
		const denied = await tool.execute("read", { path: value });
		assert.equal(denied.isError, true, `expected ${value} to be rejected`);
	}
});

test("enforces the per-file read limit and cancellation", async (t) => {
	const { root } = await fixture(t);
	await writeFile(path.join(root, "large.txt"), "x".repeat(129 * 1024), "utf8");
	const tool = findTool(root, "openmuse_read_file");
	const tooLarge = await tool.execute("large", { path: "large.txt" });
	assert.match(tooLarge.content[0].text, /128 KiB/);
	const controller = new AbortController();
	controller.abort();
	const cancelled = await tool.execute("cancel", { path: "notes/trip.md" }, controller.signal);
	assert.equal(cancelled.isError, true);
	assert.match(cancelled.content[0].text, /取消/);
});

test("refuses to register tools without an absolute authorized snapshot root", () => {
	assert.throws(() => createOpenMuseReadTools(undefined), /只读文件夹/);
	assert.throws(() => createOpenMuseReadTools("relative"), /只读文件夹/);
});
