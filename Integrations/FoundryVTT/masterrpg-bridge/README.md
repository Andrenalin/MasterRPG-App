# MasterRPG Bridge for Foundry VTT

This optional Foundry module exports a world, an Adventure, or a caller-provided document selection as a `.mrpgfoundry` JSON Lines file. MasterRPG opens that file with the same preflight/review flow as direct Foundry packages.

## Install for local development

1. Copy the `masterrpg-bridge` directory into Foundry's `Data/modules` directory.
2. Enable **MasterRPG Bridge** in the world.
3. Open **Game Settings** and choose **Export for MasterRPG**.

Only a GM can export. Chat history and users are excluded by default because they can contain private information. System/module assets require a separate opt-in so their licenses are not silently bypassed.
When users are disabled, common ownership/author identifiers are recursively removed from the exported document data as well. Remote assets are never downloaded. Local assets are fetched sequentially, limited to 64 MiB each and 128 MiB in aggregate, and oversized files remain explicit external references.

The module keeps a hidden world setting with one stable UUID per exported source (world, Adventure, or explicit document selection). MasterRPG uses it to update the same imported items after a file is renamed or regenerated; it is not a user identifier.

The module API is available at `game.modules.get("masterrpg-bridge").api`:

```js
await game.modules.get("masterrpg-bridge").api.exportWorld();
await game.modules.get("masterrpg-bridge").api.exportAdventure(adventure);
await game.modules.get("masterrpg-bridge").api.exportDocuments([actor, scene]);
```

Macro commands are retained only as JSON text. The bridge does not run them, and the MasterRPG importer never evaluates them.
