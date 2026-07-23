const MODULE_ID = "masterrpg-bridge";
const FORMAT = "masterrpg-foundry-bridge";
const FORMAT_VERSION = 1;
const MAX_ASSET_BYTES = 64 * 1024 * 1024;
const MAX_TOTAL_ASSET_BYTES = 128 * 1024 * 1024;
const SOURCE_INSTANCES_SETTING = "sourceInstances";

const WORLD_COLLECTIONS = [
  ["actors", "Actor", () => game.actors],
  ["items", "Item", () => game.items],
  ["scenes", "Scene", () => game.scenes],
  ["journal", "JournalEntry", () => game.journal],
  ["tables", "RollTable", () => game.tables],
  ["playlists", "Playlist", () => game.playlists],
  ["cards", "Cards", () => game.cards],
  ["combats", "Combat", () => game.combats],
  ["messages", "ChatMessage", () => game.messages],
  ["macros", "Macro", () => game.macros],
  ["folders", "Folder", () => game.folders],
  ["users", "User", () => game.users]
];

Hooks.once("init", () => {
  game.settings.register(MODULE_ID, SOURCE_INSTANCES_SETTING, {
    scope: "world",
    config: false,
    type: Object,
    default: {}
  });
});

Hooks.once("ready", () => {
  const module = game.modules.get(MODULE_ID);
  if (!module) return;

  module.api = Object.freeze({
    exportWorld: options => exportWorld(options),
    exportAdventure: (adventure, options) => exportDocuments([adventure], {
      ...options,
      sourceKind: "adventure",
      sourceID: adventure?.uuid ?? adventure?.id,
      sourceTitle: adventure?.name
    }),
    exportDocuments: (documents, options) => exportDocuments(documents, options)
  });
});

Hooks.on("renderSettings", (_application, renderedHTML) => {
  if (!game.user?.isGM) return;
  const root = renderedHTML instanceof HTMLElement ? renderedHTML : renderedHTML?.[0];
  if (!root || root.querySelector("[data-action='masterrpg-export']")) return;

  const button = document.createElement("button");
  button.type = "button";
  button.dataset.action = "masterrpg-export";
  button.classList.add("masterrpg-export-button");
  button.innerHTML = '<i class="fa-solid fa-file-export" aria-hidden="true"></i> Export for MasterRPG';
  button.addEventListener("click", showExportDialog);

  const target = root.querySelector("#settings-game")
    ?? root.querySelector("[data-tab='game']")
    ?? root;
  target.append(button);
});

async function showExportDialog() {
  const DialogV2 = foundry.applications.api.DialogV2;
  const formData = await DialogV2.input({
    window: { title: "Export for MasterRPG" },
    content: `
      <div class="masterrpg-bridge-options">
        <p>Every imported item is reviewed in MasterRPG before it is committed. Macro code is stored only as text and is never executed.</p>
        <label><input type="checkbox" name="assets" checked> Include accessible local assets</label>
        <label><input type="checkbox" name="packageAssets"> Include system/module assets when accessible</label>
        <label><input type="checkbox" name="combats" checked> Include combats</label>
        <label><input type="checkbox" name="macros" checked> Include macros as non-executable text</label>
        <label><input type="checkbox" name="chat"> Include chat history (may contain private messages)</label>
        <label><input type="checkbox" name="users"> Include users and ownership metadata</label>
      </div>`,
    ok: { label: "Export" },
    rejectClose: false,
    modal: true
  });
  if (!formData) return;

  try {
    ui.notifications.info("Preparing MasterRPG export…");
    await exportWorld({
      includeAssets: dialogOptionIsSelected(formData, "assets"),
      includePackageAssets: dialogOptionIsSelected(formData, "packageAssets"),
      includeCombats: dialogOptionIsSelected(formData, "combats"),
      includeMacros: dialogOptionIsSelected(formData, "macros"),
      includeChat: dialogOptionIsSelected(formData, "chat"),
      includeUsers: dialogOptionIsSelected(formData, "users")
    });
    ui.notifications.info("MasterRPG export is ready.");
  } catch (error) {
    console.error(`${MODULE_ID} | Export failed`, error);
    ui.notifications.error(`MasterRPG export failed: ${error.message}`);
  }
}

function dialogOptionIsSelected(result, name) {
  if (!result) return false;

  let value;
  if (typeof result === "object" && Object.hasOwn(result, name)) {
    value = result[name];
  } else if (typeof result.object === "object" && Object.hasOwn(result.object, name)) {
    value = result.object[name];
  } else if (typeof result.get === "function") {
    value = result.get(name);
  }

  if (Array.isArray(value)) return value.some(dialogOptionValueIsSelected);
  return dialogOptionValueIsSelected(value);
}

function dialogOptionValueIsSelected(value) {
  if (value && typeof value === "object") {
    if (Object.hasOwn(value, "checked")) return value.checked === true;
    if (Object.hasOwn(value, "value")) return dialogOptionValueIsSelected(value.value);
  }
  if (typeof value === "string") {
    return ["1", "on", "true", "yes"].includes(value.toLowerCase());
  }
  return value === true || value === 1;
}

async function exportWorld(options = {}) {
  assertGameMaster();
  const settings = {
    includeAssets: options.includeAssets ?? true,
    includePackageAssets: options.includePackageAssets ?? false,
    includeCombats: options.includeCombats ?? true,
    includeMacros: options.includeMacros ?? true,
    includeChat: options.includeChat ?? false,
    includeUsers: options.includeUsers ?? false
  };

  const records = [];
  for (const [collection, documentType, resolveCollection] of WORLD_COLLECTIONS) {
    if (collection === "combats" && !settings.includeCombats) continue;
    if (collection === "messages" && !settings.includeChat) continue;
    if (collection === "macros" && !settings.includeMacros) continue;
    if (collection === "users" && !settings.includeUsers) continue;

    for (const document of resolveCollection() ?? []) {
      records.push(documentRecord(document, collection, documentType));
    }
  }

  return createExport(records, {
    ...settings,
    sourceKind: "world",
    sourceID: game.world?.id,
    sourceTitle: game.world?.title
  });
}

async function exportDocuments(documents, options = {}) {
  assertGameMaster();
  const selectedDocuments = Array.from(documents ?? []);
  const records = selectedDocuments.map(document => documentRecord(
    document,
    options.collection ?? inferCollection(document),
    document?.documentName ?? document?.constructor?.documentName ?? "Unknown"
  ));
  const selectedSourceKey = selectedDocuments
    .map(document => document?.uuid ?? document?.id)
    .filter(Boolean)
    .sort()
    .join("|");
  const selectedSourceID = options.sourceID
    ?? (selectedSourceKey
      ? `selection:${await sha256(new TextEncoder().encode(selectedSourceKey))}`
      : game.world?.id);
  return createExport(records, {
    includeAssets: options.includeAssets ?? true,
    includePackageAssets: options.includePackageAssets ?? false,
    includeChat: options.includeChat ?? false,
    includeUsers: options.includeUsers ?? false,
    sourceKind: options.sourceKind ?? "selection",
    sourceID: selectedSourceID,
    sourceTitle: options.sourceTitle ?? game.world?.title
  });
}

async function createExport(documentRecords, options) {
  const privacyOptions = {
    includeChat: options.includeChat ?? false,
    includeUsers: options.includeUsers ?? false
  };
  const safeDocumentRecords = documentRecords
    .filter(record => permitsDocumentRecord(record, privacyOptions))
    .flatMap(record => {
      const data = scrubPrivateMetadata(record.data, privacyOptions, "document");
      return data === undefined ? [] : [{ ...record, data }];
    });
  const assetReferences = new Set();
  for (const record of safeDocumentRecords) collectAssetReferences(record.data, assetReferences);

  let assetRecords;
  if (options.includeAssets) {
    assetRecords = [];
    let includedBytes = 0;
    for (const path of Array.from(assetReferences).sort()) {
      const result = await exportAsset(path, options, MAX_TOTAL_ASSET_BYTES - includedBytes);
      assetRecords.push(result.record);
      includedBytes += result.byteCount;
    }
  } else {
    assetRecords = Array.from(assetReferences).sort().map(path => ({
        record: "assetReference",
        path,
        status: classifyAsset(path, options),
        reason: "Asset inclusion was disabled."
      }));
  }

  const includedAssetCount = assetRecords.filter(record => record.record === "asset").length;
  const instanceID = await sourceInstanceID(options.sourceKind, options.sourceID);
  const manifest = {
    record: "manifest",
    format: FORMAT,
    version: FORMAT_VERSION,
    exportedAt: new Date().toISOString(),
    foundryVersion: game.version,
    source: {
      kind: options.sourceKind,
      id: options.sourceID ?? "unknown",
      instanceID,
      title: options.sourceTitle ?? "Foundry export",
      systemID: game.system?.id ?? null,
      systemVersion: game.system?.version ?? null
    },
    documentCount: safeDocumentRecords.length,
    assetCount: includedAssetCount,
    notices: [
      "Review the licenses of the world, system, modules, and assets before redistributing this file.",
      "Macro commands are data only; MasterRPG never executes them."
    ]
  };
  const end = {
    record: "end",
    documentCount: safeDocumentRecords.length,
    assetCount: includedAssetCount
  };
  const lines = [manifest, ...safeDocumentRecords, ...assetRecords, end]
    .map(record => JSON.stringify(record));
  const blob = new Blob([`${lines.join("\n")}\n`], { type: "application/x-ndjson" });
  const filename = `${safeFilename(options.sourceTitle ?? "foundry-export")}.mrpgfoundry`;
  download(blob, filename);
  return { filename, documentCount: safeDocumentRecords.length, assetCount: includedAssetCount };
}

async function sourceInstanceID(sourceKind, sourceID) {
  const key = `${sourceKind ?? "selection"}:${sourceID ?? "unknown"}`;
  const current = { ...(game.settings.get(MODULE_ID, SOURCE_INSTANCES_SETTING) ?? {}) };
  if (typeof current[key] === "string" && /^[0-9a-f-]{36}$/iu.test(current[key])) {
    return current[key];
  }
  const value = crypto.randomUUID();
  current[key] = value;
  await game.settings.set(MODULE_ID, SOURCE_INSTANCES_SETTING, current);
  return value;
}

function documentRecord(document, collection, documentType) {
  if (!document?.toObject) throw new Error("Only Foundry Documents can be exported.");
  return {
    record: "document",
    collection,
    documentType,
    uuid: document.uuid ?? `${documentType}.${document.id}`,
    parentUUID: document.parent?.uuid ?? null,
    data: document.toObject(true)
  };
}

function inferCollection(document) {
  const name = document?.documentName ?? document?.constructor?.documentName;
  return WORLD_COLLECTIONS.find(([, type]) => type === name)?.[0] ?? "custom";
}

function collectAssetReferences(value, paths) {
  if (Array.isArray(value)) {
    for (const child of value) collectAssetReferences(child, paths);
    return;
  }
  if (value && typeof value === "object") {
    for (const child of Object.values(value)) collectAssetReferences(child, paths);
    return;
  }
  if (typeof value !== "string") return;

  const direct = normalizedAssetPath(value);
  if (direct) paths.add(direct);
  for (const match of value.matchAll(/(?:src|href)\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s"'=<>`]+))/giu)) {
    const embedded = normalizedAssetPath(match[1] ?? match[2] ?? match[3]);
    if (embedded) paths.add(embedded);
  }
}

function normalizedAssetPath(value) {
  const trimmed = value.trim();
  if (!trimmed || trimmed.startsWith("data:") || trimmed.startsWith("@UUID[")) return null;
  const withoutFragment = trimmed.split(/[?#]/u, 1)[0];
  if (!/\.(?:apng|avif|bmp|gif|heic|heif|jpe?g|png|svg|tiff?|webp|webm|aac|aiff?|caf|flac|m4a|mp3|mp4|oga|ogg|opus|wav|pdf|gltf|glb|usdz)$/iu.test(withoutFragment)) return null;
  if (/^https?:\/\//iu.test(withoutFragment)) return withoutFragment;
  const normalized = withoutFragment.replace(/^\/+/, "").replaceAll("\\", "/");
  if (normalized.split("/").some(component => component === "..")) return null;
  return normalized;
}

async function exportAsset(path, options, remainingBytes) {
  const classification = classifyAsset(path, options);
  if (classification !== "local") {
    return { byteCount: 0, record: {
      record: "assetReference",
      path,
      status: classification,
      reason: classification === "remote"
        ? "Remote assets are not downloaded by the bridge."
        : "Package assets require the explicit package-assets option."
    } };
  }
  if (remainingBytes <= 0) {
    return {
      byteCount: 0,
      record: {
        record: "assetReference",
        path,
        status: "external",
        reason: `The export reached its ${MAX_TOTAL_ASSET_BYTES} byte aggregate asset limit.`
      }
    };
  }

  try {
    const route = foundry.utils.getRoute?.(path) ?? path;
    const response = await fetch(route, { credentials: "same-origin" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const declaredLength = Number(response.headers.get("content-length"));
    const maximumBytes = Math.min(MAX_ASSET_BYTES, Math.max(0, remainingBytes));
    if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
      await response.body?.cancel();
      return { byteCount: 0, record: {
        record: "assetReference",
        path,
        status: "external",
        reason: remainingBytes <= 0
          ? `The export reached its ${MAX_TOTAL_ASSET_BYTES} byte aggregate asset limit.`
          : `Asset exceeds the ${MAX_ASSET_BYTES} byte bridge limit.`
      } };
    }
    const data = await readResponseBytes(response, maximumBytes);
    return { byteCount: data.byteLength, record: {
      record: "asset",
      path,
      mediaType: response.headers.get("content-type")?.split(";", 1)[0] ?? "application/octet-stream",
      sha256: await sha256(data),
      encoding: "base64",
      data: await base64(data)
    } };
  } catch (error) {
    const limited = error instanceof RangeError;
    return {
      byteCount: 0,
      record: {
        record: "assetReference",
        path,
        status: limited ? "external" : "missing",
        reason: error.message
      }
    };
  }
}

async function readResponseBytes(response, maximumBytes) {
  if (!response.body?.getReader) {
    const data = await response.arrayBuffer();
    if (data.byteLength > maximumBytes) throw new RangeError("Asset exceeds the remaining bridge export limit.");
    return data;
  }
  const reader = response.body.getReader();
  const chunks = [];
  let byteCount = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      byteCount += value.byteLength;
      if (byteCount > maximumBytes) {
        await reader.cancel("Asset exceeds the remaining bridge export limit.");
        throw new RangeError("Asset exceeds the remaining bridge export limit.");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const result = new Uint8Array(byteCount);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result.buffer;
}

const IDENTITY_KEYS = new Set([
  "author", "authorid", "createdby", "modifiedby", "owner", "owners", "ownership",
  "permission", "permissions", "playerowner", "playerowners", "userid", "whisper"
]);
const CHAT_CONTAINER_KEYS = new Set(["chat", "chatmessage", "chatmessages", "messages"]);
const USER_CONTAINER_KEYS = new Set(["user", "users"]);

function normalizedPrivacyKey(key) {
  return String(key).toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
}

function permitsDocumentRecord(record, options) {
  const type = normalizedPrivacyKey(record?.documentType ?? "");
  if (!options.includeChat && ["chatmessage", "chatmessages"].includes(type)) return false;
  return options.includeUsers || !["user", "users"].includes(type);
}

function scrubPrivateMetadata(value, options, context) {
  if (Array.isArray(value)) {
    return value
      .map(child => scrubPrivateMetadata(child, options, context))
      .filter(child => child !== undefined);
  }
  if (!value || typeof value !== "object") return value;
  if (context !== "semantic" && isPrivateDocumentObject(value, options)) return undefined;

  const result = {};
  for (const [key, child] of Object.entries(value)) {
    const normalized = normalizedPrivacyKey(key);
    if (context === "document" && !options.includeChat && CHAT_CONTAINER_KEYS.has(normalized)) {
      continue;
    }
    if (context === "document" && !options.includeUsers && USER_CONTAINER_KEYS.has(normalized)) {
      continue;
    }
    if (["document", "payload"].includes(context)
      && !options.includeUsers
      && IDENTITY_KEYS.has(normalized)) {
      continue;
    }
    let childContext = "payload";
    if (context === "semantic" || ["flags", "system"].includes(normalized)) {
      childContext = "semantic";
    }
    const sanitizedChild = scrubPrivateMetadata(child, options, childContext);
    if (sanitizedChild !== undefined) result[key] = sanitizedChild;
  }
  return result;
}

function isPrivateDocumentObject(value, options) {
  const declaredTypes = [
    value.documentName,
    value.documentType,
    value._stats?.documentName
  ].filter(type => typeof type === "string").map(normalizedPrivacyKey);
  if (!options.includeChat && declaredTypes.some(type => ["chatmessage", "chatmessages"].includes(type))) {
    return true;
  }
  if (!options.includeUsers && declaredTypes.some(type => ["user", "users"].includes(type))) {
    return true;
  }

  const identifiers = [value._key, value.uuid, value.sourceUUID]
    .filter(identifier => typeof identifier === "string");
  return identifiers.some(identifier => isPrivateReference(identifier, options));
}

function isPrivateReference(value, options) {
  const normalized = value.toLowerCase();
  if (!options.includeChat && (
    normalized.startsWith("chatmessage.")
    || normalized.includes("/chatmessage/")
    || normalized.includes("!chatmessages!")
  )) return true;
  return !options.includeUsers && (
    normalized.startsWith("user.")
    || normalized.includes("/user/")
    || normalized.includes("!users!")
  );
}

function classifyAsset(path, options) {
  if (/^https?:\/\//iu.test(path)) return "remote";
  if (/^(?:icons|systems|modules)\//iu.test(path) && !options.includePackageAssets) return "core";
  return "local";
}

async function sha256(data) {
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}

function base64(data) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.addEventListener("load", () => resolve(String(reader.result).split(",", 2)[1]));
    reader.addEventListener("error", () => reject(reader.error));
    reader.readAsDataURL(new Blob([data]));
  });
}

function download(blob, filename) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.hidden = true;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}

function safeFilename(value) {
  const filename = String(value).normalize("NFKD").replace(/[^\p{L}\p{N}._-]+/gu, "-");
  return filename.replace(/^-+|-+$/gu, "") || "foundry-export";
}

function assertGameMaster() {
  if (!game.user?.isGM) throw new Error("Only a Game Master can export world data.");
}

// Node's built-in test runner exercises the bridge's privacy and asset contract without changing
// the Foundry browser API. `module` is absent when this script is loaded by Foundry.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    classifyAsset,
    collectAssetReferences,
    normalizedAssetPath,
    permitsDocumentRecord,
    scrubPrivateMetadata
  };
}
