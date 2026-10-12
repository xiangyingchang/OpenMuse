import { constants, promises as fs } from "node:fs";
import path from "node:path";

const ALLOWED_EXTENSIONS = new Set([".csv", ".json", ".jsonl", ".md", ".txt", ".yaml", ".yml"]);
const MAX_FILE_BYTES = 128 * 1024;
const MAX_LIST_ENTRIES = 200;
const MAX_DEPTH = 4;

function result(text, isError = false) {
	return { content: [{ type: "text", text }], details: {}, ...(isError ? { isError: true } : {}) };
}

function relativePath(value, allowEmpty = false) {
	if (typeof value !== "string" || value.length > 500 || value.includes("\\") || value.includes("\0") || path.isAbsolute(value)) {
		throw new Error("请提供授权文件夹内的相对路径。");
	}
	const normalized = path.normalize(value.trim());
	if (normalized === "." && allowEmpty) return "";
	if (!normalized || normalized === "." || normalized === ".." || normalized.startsWith(`..${path.sep}`)) {
		throw new Error("路径必须位于已授权文件夹内。");
	}
	if (normalized.split(path.sep).some((part) => part.startsWith("."))) {
		throw new Error("隐藏文件和隐藏目录不会开放给模型。");
	}
	return normalized;
}

function isWithin(root, target) {
	const relative = path.relative(root, target);
	return relative === "" || (!path.isAbsolute(relative) && relative !== ".." && !relative.startsWith(`..${path.sep}`));
}

async function resolveSafePath(root, input, allowRoot = false) {
	const relative = relativePath(input, allowRoot);
	const candidate = path.resolve(root, relative || ".");
	const canonical = await fs.realpath(candidate);
	if (!isWithin(root, canonical) || canonical !== candidate) {
		throw new Error("符号链接或越界路径不会开放给模型。");
	}
	return { relative, canonical };
}

async function collectFiles(root, directory, depth, output, signal) {
	if (signal?.aborted) throw new Error("读取已取消。");
	if (depth > MAX_DEPTH || output.length >= MAX_LIST_ENTRIES) return;
	const entries = await fs.readdir(directory, { withFileTypes: true });
	entries.sort((left, right) => left.name.localeCompare(right.name));
	for (const entry of entries) {
		if (signal?.aborted) throw new Error("读取已取消。");
		if (entry.name.startsWith(".")) continue;
		const absolutePath = path.join(directory, entry.name);
		const metadata = await fs.lstat(absolutePath);
		if (metadata.isSymbolicLink()) continue;
		if (metadata.isDirectory()) {
			if (depth < MAX_DEPTH) await collectFiles(root, absolutePath, depth + 1, output, signal);
			continue;
		}
		if (!metadata.isFile() || !ALLOWED_EXTENSIONS.has(path.extname(entry.name).toLowerCase())) continue;
		const relative = path.relative(root, absolutePath);
		output.push({ path: relative, bytes: metadata.size });
		if (output.length >= MAX_LIST_ENTRIES) return;
	}
}

export function createOpenMuseReadTools(rootPath) {
	if (typeof rootPath !== "string" || !path.isAbsolute(rootPath)) {
		throw new Error("Mac 尚未提供经过授权的只读文件夹。");
	}
	const rootPromise = fs.realpath(rootPath);

	return [
		{
			name: "openmuse_list_files",
			label: "列出已授权资料",
			description: "只列出用户在 Mac 选择的只读文件夹中的文本资料。返回相对路径，不访问文件夹之外的内容。",
			promptSnippet: "Use this to list text files in the user's selected read-only folder.",
			parameters: {
				type: "object",
				properties: { path: { type: "string", description: "授权目录内的相对文件夹路径；留空列出整个授权范围。" } },
				additionalProperties: false,
			},
			annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
			async execute(_id, params, signal) {
				try {
					const root = await rootPromise;
					const { canonical: directory } = await resolveSafePath(root, params?.path ?? "", true);
					const stat = await fs.stat(directory);
					if (!stat.isDirectory()) return result("指定路径不是文件夹。", true);
					const files = [];
					await collectFiles(root, directory, 0, files, signal);
					return result(JSON.stringify({ files, truncated: files.length >= MAX_LIST_ENTRIES }));
				} catch (error) {
					return result(error instanceof Error ? error.message : "无法读取授权文件夹。", true);
				}
			},
		},
		{
			name: "openmuse_read_file",
			label: "读取已授权资料",
			description: "读取用户在 Mac 选择的只读文件夹中的一个 Markdown、文本、JSON、JSONL、CSV 或 YAML 文件。每个文件最多 128 KiB。",
			promptSnippet: "Use this to read a text file from the user's selected read-only folder.",
			parameters: {
				type: "object",
				properties: { path: { type: "string", description: "刚才从 openmuse_list_files 得到的相对文件路径。" } },
				required: ["path"],
				additionalProperties: false,
			},
			annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
			async execute(_id, params, signal) {
				try {
					if (signal?.aborted) throw new Error("读取已取消。");
					const root = await rootPromise;
					const { relative, canonical } = await resolveSafePath(root, params?.path ?? "");
					if (!ALLOWED_EXTENSIONS.has(path.extname(canonical).toLowerCase())) throw new Error("只允许读取常见文本文件格式。");
					const handle = await fs.open(canonical, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
					try {
						const stat = await handle.stat();
						if (!stat.isFile()) throw new Error("指定路径不是普通文件。");
						if (stat.size > MAX_FILE_BYTES) throw new Error("文件超过 128 KiB，暂不读取。");
						const content = await handle.readFile({ encoding: "utf8", signal });
						return result(JSON.stringify({ path: relative, content }));
					} finally {
						await handle.close();
					}
				} catch (error) {
					return result(error instanceof Error ? error.message : "无法读取该文件。", true);
				}
			},
		},
	];
}

export default function openMuseReadExtension(pi) {
	const root = process.env.OPENMUSE_READ_ROOT;
	if (!root) return;
	for (const tool of createOpenMuseReadTools(root)) pi.registerTool(tool);
}
