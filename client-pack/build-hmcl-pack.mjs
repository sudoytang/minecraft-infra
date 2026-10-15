import fs from "node:fs/promises";
import path from "node:path";

const gameVersion = "26.2";
const api = "https://api.modrinth.com/v2";
const work = "/home/ytang/client-pack-work";

const requested = [
  ["fabric-api", "mods"],
  ["sodium", "mods"],
  ["iris", "mods"],
  ["appleskin", "mods"],
  ["nfn13YXA", "mods"],
  ["xaeros-minimap", "mods"],
  ["xaeros-world-map", "mods"],
  ["modmenu", "mods"],
  ["continuity", "mods"],
  ["entity-model-features", "mods"],
  ["entitytexturefeatures", "mods"],
  ["fresh-animations", "resourcepacks"],
  ["complementary-reimagined", "shaderpacks"],
];

async function getJson(url) {
  const response = await fetch(url, {
    headers: { "User-Agent": "ytang-hmcl-pack/1.0" },
  });
  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText}: ${url}`);
  }
  return response.json();
}

function chooseVersion(versions, kind) {
  const compatible = versions.filter((version) =>
    version.game_versions.includes(gameVersion)
  );
  const loaderMatch = compatible.filter((version) => {
    if (kind === "mods") return version.loaders.includes("fabric");
    return true;
  });
  const candidates = loaderMatch.length ? loaderMatch : compatible;
  const stable = candidates.filter((version) =>
    version.version_type === "release"
  );
  return (stable.length ? stable : candidates)[0];
}

async function resolveProject(slug, kind) {
  const project = await getJson(`${api}/project/${slug}`);
  const versions = await getJson(`${api}/project/${project.id}/version`);
  const version = chooseVersion(versions, kind);
  if (!version) {
    throw new Error(`No ${gameVersion} version for ${slug}`);
  }
  const file = version.files.find((entry) => entry.primary) ?? version.files[0];
  return { project, version, file, kind };
}

async function resolveVersion(versionId, kind) {
  const version = await getJson(`${api}/version/${versionId}`);
  const project = await getJson(`${api}/project/${version.project_id}`);
  const file = version.files.find((entry) => entry.primary) ?? version.files[0];
  return { project, version, file, kind };
}

async function main() {
  await fs.rm(work, { recursive: true, force: true });
  await fs.mkdir(path.join(work, "overrides"), { recursive: true });

  const resolved = new Map();
  const queue = requested.map(([slug, kind]) => ({ slug, kind }));
  while (queue.length) {
    const entry = queue.shift();
    let item;
    if (entry.versionId) {
      item = await resolveVersion(entry.versionId, entry.kind);
    } else {
      item = await resolveProject(entry.slug, entry.kind);
    }
    if (resolved.has(item.project.id)) continue;
    resolved.set(item.project.id, item);
    console.log(`${item.project.slug}: ${item.version.version_number}`);
    const required = item.version.dependencies.filter((dependency) =>
      dependency.dependency_type === "required"
    );
    for (const dependency of required) {
      if (dependency.project_id && resolved.has(dependency.project_id)) continue;
      queue.push({
        slug: dependency.project_id,
        versionId: dependency.version_id,
        kind: "mods",
      });
    }
  }

  const loaderData = await getJson(
    `https://meta.fabricmc.net/v2/versions/loader/${gameVersion}`
  );
  const stableLoader = loaderData.find((entry) => entry.loader.stable);
  const loader = stableLoader ?? loaderData[0];
  if (!loader) throw new Error("No Fabric loader found");

  const files = [...resolved.values()].map(({ file, kind }) => ({
    path: `${kind}/${file.filename}`,
    hashes: {
      sha1: file.hashes.sha1,
      sha512: file.hashes.sha512,
    },
    env: {
      client: "required",
      server: "unsupported",
    },
    downloads: [file.url],
    fileSize: file.size,
  }));

  const index = {
    formatVersion: 1,
    game: "minecraft",
    versionId: "1.0.0-mc26.2",
    name: "Ytang Cozy Vanilla Client",
    summary: "Client-only visual, performance and beginner-friendly pack",
    files,
    dependencies: {
      minecraft: gameVersion,
      "fabric-loader": loader.loader.version,
    },
  };

  await fs.writeFile(
    path.join(work, "modrinth.index.json"),
    `${JSON.stringify(index, null, 2)}\n`
  );
  await fs.writeFile(
    path.join(work, "overrides", "selected-versions.txt"),
    [...resolved.values()].map(({ project, version }) =>
      `${project.slug}=${version.version_number}`
    ).join("\n") + `\nfabric-loader=${loader.loader.version}\n`
  );
}

await main();
