const assert = require("node:assert/strict");
const test = require("node:test");

globalThis.Hooks = {
  once() {},
  on() {}
};

const {
  classifyAsset,
  collectAssetReferences,
  normalizedAssetPath,
  permitsDocumentRecord,
  scrubPrivateMetadata
} = require("../scripts/masterrpg-bridge.js");

test("privacy scrub removes Foundry metadata but preserves game-system fields", () => {
  // Given
  const privateValue = "private-user-id";
  const systemValue = "game-rule-value";
  const source = {
    authorID: privateValue,
    owners: [privateValue],
    playerOwners: [privateValue],
    users: [privateValue],
    whisper: [privateValue],
    messages: [{ content: "private chat" }],
    nested: { userId: privateValue },
    payload: {
      user: "valid nested field",
      messages: ["valid nested message field"]
    },
    explicitUser: { documentName: "User", _id: privateValue },
    explicitChat: { documentType: "ChatMessage", content: "private chat" },
    system: {
      user: systemValue,
      users: [systemValue],
      messages: [systemValue],
      nested: {
        authorID: systemValue,
        whisper: systemValue
      }
    },
    flags: {
      "example-module": {
        user: systemValue,
        messages: [systemValue],
        authorID: systemValue
      }
    }
  };

  // When
  const result = scrubPrivateMetadata(
    source,
    { includeChat: false, includeUsers: false },
    "document"
  );

  // Then
  assert.deepEqual(result, {
    nested: {},
    payload: {
      user: "valid nested field",
      messages: ["valid nested message field"]
    },
    system: {
      user: systemValue,
      users: [systemValue],
      messages: [systemValue],
      nested: {
        authorID: systemValue,
        whisper: systemValue
      }
    },
    flags: {
      "example-module": {
        user: systemValue,
        messages: [systemValue],
        authorID: systemValue
      }
    }
  });
});

test("document record privacy is based on the declared Foundry document type", () => {
  const options = { includeChat: false, includeUsers: false };

  assert.equal(permitsDocumentRecord({ documentType: "Actor" }, options), true);
  assert.equal(permitsDocumentRecord({ documentType: "ChatMessage" }, options), false);
  assert.equal(permitsDocumentRecord({ documentType: "USER" }, options), false);
});

test("package asset classification is case-insensitive", () => {
  const excludesPackageAssets = { includePackageAssets: false };
  const includesPackageAssets = { includePackageAssets: true };

  assert.equal(classifyAsset("Systems/DS4/Icons/Sword.WEBP", excludesPackageAssets), "core");
  assert.equal(classifyAsset("MODULES/MyModule/Map.PNG", excludesPackageAssets), "core");
  assert.equal(classifyAsset("ICONS/svg/sword.svg", excludesPackageAssets), "core");
  assert.equal(classifyAsset("Systems/DS4/Icons/Sword.WEBP", includesPackageAssets), "local");
});

test("asset discovery accepts supported media and quoted or unquoted HTML attributes", () => {
  const paths = new Set();

  collectAssetReferences(
    '<img src="art/token.webp"><audio src=\'audio/theme.opus\'><audio src=audio/room.webm>',
    paths
  );

  assert.deepEqual(
    [...paths].sort(),
    ["art/token.webp", "audio/room.webm", "audio/theme.opus"]
  );
  assert.equal(normalizedAssetPath("art/animated.apng?cache=1"), "art/animated.apng");
  assert.equal(normalizedAssetPath("audio/scene.mp4#track"), "audio/scene.mp4");
});
