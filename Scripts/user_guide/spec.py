import json

# Marker coordinates are in the screenshot's point space (1180 x 820).
P = []


def page(title, kicker, intro, image, marks, tip=None):
    P.append({"title": title, "kicker": kicker, "intro": intro, "image": image,
              "marks": [{"x": x, "y": y, "text": t} for (x, y, t) in marks], "tip": tip})


P.append({"cover": True, "title": "MasterRPG", "subtitle": "A guided tour for game masters",
          "text": "Every screen in this guide comes from the tutorial adventure that ships with the app. Open it next to the guide and tap along.",
          "image": "22_game_map"})

page("Find your way around", "Start here",
     "MasterRPG keeps everything for a game in one library. Each module has the same layout: the sidebar chooses the module, the list shows its items, the detail shows the selected item.",
     "01_adventure_list",
     [(240, 299, "The sidebar groups the modules. Library: Adventure, Character, Map, Weather. References: Rules, Pdf, Table. Material: Audio, Dice, Photo, Space."),
      (500, 200, "Folders keep a long list tidy. Open one with the arrow; the same folders exist in every module."),
      (492, 266, "Tap an item to open it. The picture and the first lines of the description help you find it again."),
      (506, 108, "Search by text, or type @ to search by tag."),
      (424, 54, "Plus adds a new item, the three dots open list options such as folders and collections.")])

page("Create and edit an item", "Start here",
     "Every item has a name, a description and tags. Tap the pencil at the top right of an item to edit these.",
     "02_edit_item_keyboard",
     [(833, 228, "The name is what you see in lists and what a link to this item shows."),
      (860, 340, "The description explains the item to you and, for a photo or a character, to your players."),
      (590, 376, "These buttons insert a link to another module: adventure, map, character, PDF, table or weather. Links are what connect the whole game.")],
     "Tip: tags such as EXAMPLE make a group of items easy to find later. Search for @EXAMPLE.")

page("Adventures: the story", "Library",
     "An adventure is the story. Its entries are chapters or scenes, and links in the entries bring in every other module.",
     "04_adventure_entries",
     [(600, 144, "Tags help you find the adventure. Use them for system, setting or session."),
      (860, 294, "Each entry has a short heading and free text. Use one entry per scene."),
      (990, 378, "A blue chip is a link. Tap a dice link to roll, a music link to play, a map or photo link to open it."),
      (1093, 54, "The pencil edits the adventure. The button at the bottom right asks the on-device assistant for ideas, if your device supports it.")],
     "Adventures can contain other adventures and be grouped in folders, so a campaign can hold many scenarios.")

page("Characters", "Library",
     "Characters hold players, NPCs and monsters. Folders sort them, and collections gather related ones, such as all monsters.",
     "06_character_list",
     [(370, 237, "00 Character explains every kind of value. Open it to learn the editor."),
      (370, 322, "A ready-to-play hero. Her portrait becomes her pin on the map."),
      (370, 405, "A monster for the Battle Round. Copy it for every goblin you need; each copy keeps its own HP during play."),
      (320, 509, "Collections list characters that belong together, for example Monster or NPC. A collection can contain the same item more than once.")])

page("Values, dice and links", "Library",
     "A character is a list of values. A value can be text, a number, a decimal or a selection, and it can carry a dice and links.",
     "05_character_values",
     [(335, 214, "A dice chip on the character sets the starting dice for the game."),
      (730, 320, "The photo is the portrait and the pin on the map. Without a photo the app picks a random color."),
      (422, 481, "A value has a name and a value. The value here is free text."),
      (343, 601, "A dice on a value. For a number value the dice uses it as the comparison value."),
      (676, 656, "Names can contain links, such as this table entry.")])

page("HP, initiative and the Battle Round", "Library",
     "The Battle Round reads two values from every character by name: HP and Ini. Both can be a plain number or a calculation.",
     "07_character_hp_ini",
     [(623, 236, "The entry named HP is the health. The base is 100 percent; damage and healing are tracked as a modifier during the game."),
      (660, 271, "A calculated value uses links to other values of the same character. Here Constitution times 2 plus 10 gives 34."),
      (620, 317, "The entry named Ini is the initiative."),
      (600, 391, "The dice chip is rolled for the initiative in a battle."),
      (1030, 481, "Other values can hold text with links, such as the weapon table.")],
     "If your system uses other names for HP and initiative, change them in the Battle Round settings.")

page("Maps", "Library",
     "A map is a photo with rooms on it. Rooms hide content from the players until you reveal them, and each room can link characters, dice, tables, music, PDFs and photos.",
     "09_map_menu",
     [(790, 314, "The map photo. Below it, Config sets the cover color, cover tile and border."),
      (1146, 54, "The detail menu opens the tools below."),
      (962, 114, "Map Editor: draw rooms and place pins."),
      (962, 152, "Edit Tile: edit the cover tile of the map."),
      (962, 190, "Extract Information from the map image."),
      (962, 59, "Inspector: browse and drag links from other modules.")])

page("The map editor", "Library",
     "In the editor you draw the rooms and place pins. The green areas are rooms, and the pins are characters on the map.",
     "10_map_editor",
     [(560, 250, "A room is a shape on the map. It has a name, a description, and any links you add. The entrance and the main hall here each have their own room."),
      (930, 427, "A pin with a portrait is a character. Elara's pin belongs to a player."),
      (514, 390, "A plain colored pin is a monster. These two goblin pins are hidden from the players."),
      (260, 778, "Switch between the display modes to see the map the way the players see it."),
      (320, 778, "Place characters on the map. The app offers a pin whenever you link a character."),
      (32, 778, "Accept the changes.")])

page("Tables", "References",
     "Tables hold any data you roll or look up: weapons, loot, encounters, rules.",
     "11_table_list",
     [(365, 152, "Folders organize tables."),
      (350, 328, "A simple list, such as a weapon list from a rulebook."),
      (485, 445, "A dice table. The die on the right is the dice you roll on it."),
      (370, 502, "A collection organizes extra lists of categorized items.")])

page("Roll on a table", "References",
     "A dice table maps results of its dice to entries. The entries can hold links, even to other tables and dice.",
     "12_table_loot",
     [(586, 112, "Tags group tables, here the category Loot."),
      (595, 501, "The dice of the table. Change it in the editor."),
      (624, 648, "The entry name is the dice result. Ranges such as 1-3 work too."),
      (587, 683, "The content can link to another table entry. Tap the Axe link to read it, or share it with the players.")])

page("Dice", "Material",
     "The Dice module manages every die you use: sets of colored dice, rules for how a result is calculated, and sum dice for tables.",
     "14_dice_editor",
     [(325, 237, "The dice of this item. Tap the x to remove a die."),
      (400, 400, "Choose dice in different colors and shapes, from a D3 to a D20 and percentile dice."),
      (730, 793, "Options: sum the dice, add a modifier, compare against a value, critical and fumble rules, rerolls."),
      (315, 144, "Tags group the dice by rule system.")])

page("Dice bags", "Material",
     "A dice bag collects several dice. Use one for a set that always travels together, such as the treasure dice.",
     "13_dice_bag",
     [(313, 112, "The bag name. A bag is a collection, so the same die can be in more than one bag."),
      (1145, 180, "Each row shows the die and its description. Tap a row to open the die."),
      (1093, 54, "Plus adds another die to the bag.")])

page("Weather", "Library",
     "Weather gives a scene atmosphere. You set it up here and show it to the players during the game.",
     "15_weather",
     [(860, 398, "A background photo behind the weather. Not every photo works, so try a few."),
      (865, 511, "The time of day. Stars appear at night; noon removes them."),
      (1127, 547, "Cloud thickness."),
      (1127, 611, "The type of precipitation (here Rain). Intensity and angle follow below.")])

page("Photos, audio, PDFs and 3D", "Material",
     "These modules manage the files of your game and keep them in iCloud. Folders in these modules are real folders in iCloud, so the files stay organized there too.",
     "16_photo_folder",
     [(364, 152, "A folder. Open it to see its photos. The same folders exist for Audio, Pdf and Space."),
      (397, 54, "Plus adds a new item to the list."),
      (507, 54, "Show or hide the list for more room.")])

page("Start the game: Portal Gate", "Play",
     "The Portal Gate is the Game tab. Choose your role first; the app remembers your last adventure and character for the next session.",
     "17_portal_gate",
     [(437, 320, "Player: choose a character and join a shared game."),
      (729, 320, "Game Master: choose an adventure and host the session."),
      (1021, 320, "Join: find a nearby game as an observer or proxy."),
      (729, 516, "Drop an item here or tap to choose it."),
      (410, 650, "Game statistics show an example dashboard of your sessions.")])

page("Host a game", "Play",
     "As game master pick the adventure, then start. Players join over SharePlay or your local network.",
     "19_gm_start_game",
     [(729, 440, "The adventure the game will run. Remove it with the minus to pick another."),
      (1093, 546, "The join code. Players enter it to join your game."),
      (729, 626, "Start Game."),
      (1068, 470, "Import a saved game to continue a session."),
      (1068, 504, "Play RPG online with a remote group.")])

page("During the game", "Play",
     "The game screen has a stage for the map, photo or weather and a side panel with your adventure. Players only see what you show.",
     "20_game_running",
     [(25, 23, "Quit the game. You can save it first to continue later."),
      (73, 22, "Hide or show the dice bag."),
      (76, 75, "Roll dice in front of the table."),
      (493, 23, "The join code, tap to see it again."),
      (856, 23, "Show or hide the side panel."),
      (886, 300, "Your adventure. Links in it work as in the editor.")])

page("Show it to the players", "Play",
     "Tap a link in the adventure and it expands with actions. You decide what the players see.",
     "21_game_link_actions",
     [(1116, 696, "The map link."),
      (944, 722, "Share sends the content to the players."),
      (1018, 722, "Show opens it for you on the stage."),
      (1090, 770, "The content of the link, previewed in green.")])

page("The game map", "Play",
     "The map is the heart of a session. Rooms stay hidden until you reveal them, and the toolbar controls what the players see.",
     "22_game_map",
     [(427, 423, "A room that is still hidden from the players."),
      (776, 427, "Elara's pin is visible to the players."),
      (360, 390, "A goblin pin, still hidden."),
      (141, 778, "Display mode (here: Master)."),
      (196, 778, "Share map: players only get updates when this is enabled."),
      (250, 778, "Choose map pins: add characters to the map."),
      (297, 778, "Pointing mode."),
      (25, 778, "Show the 3D table. On Apple Vision Pro it is a volumetric table, on other devices a camera view of the map.")])

page("Add characters to the map", "Play",
     "Add pins during a session without leaving the game.",
     "23_game_choose_pins",
     [(338, 330, "Pick one or more characters."),
      (792, 112, "Confirm. The pins are placed on the map, with the portraits of the characters."),
      (845, 506, "Open a folder or collection to choose a character inside.")])

page("Export, import and tips", "Settings",
     "Your adventures can be exported as one package and imported on another device. A package includes everything an adventure links to.",
     "10_settings",
     [(330, 227, "Export the data to share with another device or as a backup."),
      (330, 279, "Import a package: review what changes before it is applied."),
      (330, 389, "Validate Folders: checks the folder structure."),
      (330, 499, "Show Tips Again restores the in-app guidance."),
      (330, 743, "Reset Data removes everything. Use with care.")])

json.dump(P, open('spec.json', 'w'), indent=1, ensure_ascii=False)
print(len(P), 'pages')
