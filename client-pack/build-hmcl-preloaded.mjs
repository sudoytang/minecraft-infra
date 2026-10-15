import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

const source = "/home/ytang/client-pack-work";
const target = "/home/ytang/client-pack-preloaded";

async function main() {
  const manifest = JSON.parse(
    await fs.readFile(path.join(source, "modrinth.index.json"), "utf8")
  );

  await fs.rm(target, { recursive: true, force: true });
  await fs.mkdir(path.join(target, "overrides"), { recursive: true });
  await fs.cp(
    path.join(source, "overrides"),
    path.join(target, "overrides"),
    { recursive: true }
  );

  const remoteOnly = [];
  for (const file of manifest.files) {
    if (file.path.startsWith("shaderpacks/")) {
      remoteOnly.push(file);
      continue;
    }

    const response = await fetch(file.downloads[0], {
      headers: { "User-Agent": "ytang-hmcl-pack/1.0" },
    });
    if (!response.ok) throw new Error(`${response.status}: ${file.path}`);
    const data = Buffer.from(await response.arrayBuffer());
    const hash = crypto.createHash("sha512").update(data).digest("hex");
    if (hash !== file.hashes.sha512) {
      throw new Error(`SHA-512 mismatch: ${file.path}`);
    }

    const destination = path.join(target, "overrides", file.path);
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.writeFile(destination, data);
    console.log(`Embedded: ${file.path}`);
  }

  manifest.name = "Ytang Cozy Vanilla Client Preloaded";
  manifest.versionId = "1.0.0-mc26.2-preloaded";
  manifest.summary = "Preloaded private client pack; shader downloads separately";
  manifest.files = remoteOnly;
  await fs.writeFile(
    path.join(target, "modrinth.index.json"),
    `${JSON.stringify(manifest, null, 2)}\n`
  );
}

await main();
