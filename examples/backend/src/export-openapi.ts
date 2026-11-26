import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { todosOpenApiSpec } from "./openapi.ts";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(scriptDir, "../openapi");

await mkdir(outDir, { recursive: true });
await writeFile(resolve(outDir, "todos.json"), JSON.stringify(todosOpenApiSpec, null, 2) + "\n", "utf8");

console.log(`Exported OpenAPI specs to ${outDir}`);
