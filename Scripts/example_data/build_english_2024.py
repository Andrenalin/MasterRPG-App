#!/usr/bin/env python3
"""Rebuilds ExampleData.gmz: decode the 2024 package, modernize text, add new feature content."""
import copy, json, struct, sys, time, uuid

SRC, DST = sys.argv[1], sys.argv[2]
NOW = time.time() - 978307200  # Apple reference date, like the app's CRDT clocks


def uid():
    return str(uuid.uuid4()).upper()


# ---------- container ----------
def load(path):
    d = open(path, 'rb').read()
    p = 0

    def u():
        nonlocal p
        v = struct.unpack_from('<I', d, p)[0]
        p += 4
        return v

    head = (u(), u(), u())
    mods = []
    while p < len(d):
        c, t, v = u(), u(), u()
        items, n, f = [], 0, None
        while n < c:
            s, tok = u(), u()
            data = d[p:p + s]
            p += s
            if tok == 10001:
                f = data
                continue
            n += 1
            items.append({'file': f, 'json': json.loads(data)})
            f = None
        mods.append({'token': t, 'version': v, 'items': items})
    return head, mods


def save(path, head, mods):
    out = bytearray()
    total = sum(len(m['items']) for m in mods)
    out += struct.pack('<III', total, 8096, head[2])
    for m in mods:
        out += struct.pack('<III', len(m['items']), m['token'], m['version'])
        for it in m['items']:
            if it['file'] is not None:
                out += struct.pack('<II', len(it['file']), 10001) + it['file']
            data = json.dumps(it['json'], ensure_ascii=False, separators=(',', ':')).encode()
            out += struct.pack('<II', len(data), 10000) + data
    open(path, 'wb').write(out)


# ---------- CRDT helpers ----------
def C(value):
    a = uid()
    return {'_crdtValue': {'selfId': a, '_storage': {'value': value, 'clockId': {'actorId': a, 'clock': NOW}}}}


def setc(node, value):
    """Set the value of an existing CRDT wrapper with a fresh clock (newer than the old data)."""
    s = node['_crdtValue']['_storage']
    s['value'] = value
    s['clockId']['clock'] = NOW


def touch_entries(node):
    node['update'] = C(uid())


# ---------- link helpers ----------
def link(text, module, *ids):
    return f"[{text}](RPG://{module}/0/{'/'.join(ids)})"


head, mods = load(SRC)
M = {m['token']: m for m in mods}
TAG = 'EXAMPLE'


def items(token):
    return [i['json'] for i in M[token]['items']]


def by_name(token, name):
    for it in items(token):
        if it['_name_']['_crdtValue']['_storage']['value'] == name:
            return it
    raise KeyError(name)


def retag(it):
    setc(it['_tags_'], [TAG if t == 'BEISPIEL' else t for t in it['_tags_']['_crdtValue']['_storage']['value']])


for tok in M:
    for it in items(tok):
        if '_tags_' in it:
            retag(it)

# ---------- known ids ----------
PHOTO_GM, PHOTO_MAP, PHOTO_CHAR, PHOTO_ADV = ['4590E6C0-8976-4FDB-A559-75A32E550691', 'F3CA87E3-940B-402F-B059-F09EC602AC52',
                                             '12975503-CC29-4837-8018-EFF774E97595', '1D0034CE-0BEE-4AA1-9E8E-7704F0DF1E00']
AUDIO = '8AC1B410-F2E8-4EE9-A640-F8E9244AA20C'
PDF = '4478CA2D-20D9-49F7-9F44-1C1DD1B93C03'
SPACE = 'DD1FBF0F-332D-4E92-97D2-5A4D1D86222D'
WEATHER = '1DCDD905-867D-4AA3-82DB-F0B09A137C35'
D20, D2D20, D5D20 = '36F37F17-728D-4315-B2BB-B9401039D07E', '1381950F-C01E-4A1D-891C-39BB6A41C988', '77BB0CC0-9BD8-4D48-B52A-920DB43FB81B'
T_TABLES, T_WEAPONS, T_LOOT = '25321D0A-CBAC-4A6C-944C-C8916049FC45', '606D5981-990C-48EC-9027-0672FAF1502D', '6995F106-941E-43AE-95FC-696297875512'
E_AXE, E_DAGGER, E_SWORD = 'ACFF7CE0-04C1-439C-984A-8E78276126F5', '9B9D577B-DBD7-4495-879D-8DC9D03DA531', '12B309DE-D0D1-4693-BC3C-A3B6CD5B2CBE'
MAP = '50DFDB6F-E8B1-41A4-A409-911D888119E8'
CHAR_GM, CHAR_ATTR, CHAR_EXPLAIN = '07358E66-CA4F-45AE-9E12-F57167A6FB89', 'B6B05571-E7E7-4BAE-B3F1-E503580DCB58', 'C8E6D074-7FC1-4170-A310-93C87D767982'
ATTR_STR, ATTR_DEX, ATTR_INT = '16587A5F-327B-4579-B528-D84E9E8DA363', 'ACAB03A0-A174-4A52-B818-9E6E8344AEC0', '4FC4ABB3-97FE-417D-A89A-4D845126D030'

L_D20 = link('D20', 'DICE', D20)
L_5D20 = link('5d20', 'DICE', D5D20)
L_AUDIO = link('00 Music', 'AUDIOS', AUDIO)
L_MAP = link('00 Map', 'MAPS', MAP)
L_PDF = link('00 Pdf', 'PDFS', PDF)
L_SPACE = link('00 Model 3D', 'SPACES', SPACE)
L_WEATHER = link('00 Weather', 'WEATHERS', WEATHER)
L_LOOT = link('02 Loot', 'TABLES', T_LOOT)
L_WEAPONS = link('01 Weapons', 'TABLES', T_WEAPONS)
L_SWORD = link('Sword', 'TABLES', T_WEAPONS, E_SWORD)
L_AXE = link('Axe', 'TABLES', T_WEAPONS, E_AXE)


def text_entry(name, content):
    return {'name': C(name), 'id': uid(), 'content': C(content), 'displayState': 0}


def set_entry(e, name=None, content=None):
    if name is not None:
        setc(e['name'], name)
    if content is not None:
        setc(e['content'], content)


def entries_of(it):
    return it['_entries_']['_value']


# ======================= CHARACTERS =======================
def ventry(name, value, type_=0, calculated=False, dice=None, value_id=None):
    return {'id': uid(), 'name': C(name), 'value': C(value), 'type': C(type_), 'calculated': C(calculated),
            'diceId': C(dice), 'valueId': C(value_id), 'isGenerator': C(False), 'displayState': 0}


def new_value_item(name, desc, category, photo, entries):
    base = copy.deepcopy(items(9)[0])
    base['_id'] = uid()
    setc(base['_name_'], name)
    setc(base['_description_'], desc)
    setc(base['_category_'], category)
    setc(base['_photoId_'], photo)
    base['_photos_']['_value'] = [photo] if photo else []
    touch_entries(base['_photos_'])
    base['_entries_']['_value'] = entries
    touch_entries(base['_entries_'])
    return base


chars = items(9)
gm = next(c for c in chars if c['_id'] == CHAR_GM)
attr = next(c for c in chars if c['_id'] == CHAR_ATTR)
explain = next(c for c in chars if c['_id'] == CHAR_EXPLAIN)

setc(gm['_description_'], 'The game master needs nothing more than a name. The photo only appears in lists, and a dice value sets the starting dice for the game.')
ge = entries_of(gm)
setc(ge[0]['name'], 'Starting dice')
setc(ge[0]['value'], '1')
setc(ge[1]['name'], 'Only dice?')
setc(ge[1]['value'], 'Yes. The game master does not need attributes. A linked dice entry is used as the first dice in the game, which saves a tap at the table.')
ge[0]['diceId'] = C(D2D20)
# the first entry is a number entry: make it a plain dice shortcut
setc(ge[0]['value'], '0')

setc(attr['_description_'], 'A group collects values that belong together. It is shared by characters through a group entry. Hide it (top right) so it does not clutter the character list.')
ae = entries_of(attr)
setc(ae[0]['name'], 'Strength')
setc(ae[1]['name'], 'Dexterity')
setc(ae[2]['name'], 'Intelligence')

# --- 00 Character: the explainer, modernized and extended ---
setc(explain['_description_'], 'This character explains every kind of value. A character needs a name only for online play. The photo is the pin on the map and the portrait in the game; without a photo the app picks a random color. Everything else is optional.')
xe = entries_of(explain)
setc(xe[0]['name'], 'Name of the value')
setc(xe[0]['value'], 'A value can hold text, an integer, a decimal number or a selection. Add a dice to the dice field. For a number value the dice uses it as the comparison value. Dice from the rules are copied before they are rolled, so the original is never changed. Dice from the character category stay as they are.')
setc(xe[1]['name'], 'Names can contain links, for example ' + L_AXE)
setc(xe[2]['name'], 'Group')
setc(xe[2]['value'], 'Groups arrange values. In the list (right side on iPad and Mac, previous screen on iPhone) groups can be opened and closed and are shown indented. A group belongs to one character value; using an assigned group again makes a copy.')
setc(xe[4]['name'], 'The name can include dice ' + link('2d20', 'DICE', D2D20) + ' and tables ' + L_LOOT)
setc(xe[4]['value'], 'The value can contain dice, tables, other characters and PDF bookmarks. Tap a link to read, roll or share it with the players.')
setc(xe[5]['name'], 'Calculated value')
setc(xe[5]['value'], 'Switch calculation on for a number or decimal value. Then +, -, * and / and links to other values of the same character work. A value that cannot be calculated shows an error.')
setc(xe[6]['name'], 'Battle value')
setc(xe[6]['value'], link('Strength', 'VALUES', CHAR_ATTR, ATTR_STR) + '+' + link('Dexterity', 'VALUES', CHAR_ATTR, ATTR_DEX) + '+' + link('Intelligence', 'VALUES', CHAR_ATTR, ATTR_INT) + '*2')
setc(xe[7]['name'], 'PDF links')
setc(xe[7]['value'], 'A link to a PDF bookmark shows the bookmark text right here: ' + L_PDF)
xe[0]['diceId'] = C(D2D20)

# --- Elara, the hero ---
elara_id = uid()
e_con, e_dex, e_hp, e_ini = uid(), uid(), uid(), uid()


def ve(eid, *a, **k):
    d = ventry(*a, **k)
    d['id'] = eid
    return d


elara = new_value_item(
    '03 Elara Dawnwhisper',
    'A ready-to-play hero. Her HP and Ini values are what the Battle Round reads, so she can fight right away on the map.',
    6001, PHOTO_CHAR,
    [
        ve(e_con, 'Constitution', '12', 1),
        ve(e_dex, 'Dexterity', '16', 1),
        ve(e_hp, 'HP', link('Constitution', 'VALUES', elara_id, e_con) + '*2+10', 1, True),
        ve(e_ini, 'Ini', link('Dexterity', 'VALUES', elara_id, e_dex), 1, True, dice=D20),
        ventry('Weapon', 'A longbow. Pick the damage from the weapon table: ' + L_SWORD + ' for the melee fallback.', 0),
        ventry('Attack', 'Roll ' + L_D20 + ' and compare it with her Dexterity.', 0),
        ventry('About the HP entry', 'The Battle Round finds the entry named "HP" automatically. The base is 100%; damage and healing are tracked as a modifier. The value can be a number or a calculation with links, like here.', 0),
        ventry('About the Ini entry', 'The initiative uses the entry named "Ini" and its dice. Rename them in the Battle Round settings if your system uses other names.', 0),
    ])
elara['_id'] = elara_id
# patch the group entry link ids into the final id (items created before the id was fixed)
chars.append(elara)

# --- Goblin archer, a monster ---
gob_id = uid()
g_con, g_dex, g_hp, g_ini = uid(), uid(), uid(), uid()
goblin = new_value_item(
    '04 Goblin Archer',
    'A simple monster for the Battle Round. Copy it as often as you like; each copy keeps its own HP during the game.',
    6003, None,
    [
        ve(g_con, 'Constitution', '8', 1),
        ve(g_dex, 'Dexterity', '14', 1),
        ve(g_hp, 'HP', link('Constitution', 'VALUES', gob_id, g_con) + '+4', 1, True),
        ve(g_ini, 'Ini', link('Dexterity', 'VALUES', gob_id, g_dex), 1, True, dice=D20),
        ventry('Treasure', 'Roll for loot: ' + L_LOOT, 0),
    ])
goblin['_id'] = gob_id
chars.append(goblin)
M[9]['items'].append({'file': None, 'json': elara})
M[9]['items'].append({'file': None, 'json': goblin})
M[9]['items'] = [i for i in M[9]['items']]
# the list `chars` was only a view; `elara`/`goblin` were appended to the module explicitly
# ======================= TABLES =======================
t0, t1, t2 = items(3)
setc(t0['_description_'], 'Tables hold any RPG data: weapon lists, loot tables, rules, random encounters. Categories sort the tables, tags help you find them.\nThere are three types. A list is the simplest, for example a weapons list. A dice table has a dice result as the name and the outcome as content, for example loot. The "everything" table tells a generator to use every entry.')
te = entries_of(t0)
set_entry(te[0], 'Entries', 'Each table has as many entries as you need. Keep the name short, because it is the link text. The content can be long and can contain links to dice, other tables and table entries. Links show their content right in the text, and you can also share them with the players or roll them.')
set_entry(te[1], 'Links in content', 'The content can be anything: text, a number, a long description. Links make it fast. Dice: ' + L_5D20 + ', tables: ' + L_LOOT + ', entries from tables: ' + L_AXE + '.\nA dice link can be rolled and shared. A table link shows a summary and an entry link shows the content.')
set_entry(te[2], 'Weapons', 'A link to the weapon list: ' + L_WEAPONS)
set_entry(te[3], 'Loot', 'Roll for a weapon here: ' + L_LOOT)
te.append(text_entry('Monster loot', 'The ' + link('04 Goblin Archer', 'VALUES', gob_id) + ' carries a weapon from ' + L_LOOT + '. Use the dice link in the table to roll it during the game.'))
touch_entries(t0['_entries_'])
setc(t1['_description_'], 'A simple list, like a table from a rulebook. Every row can be linked from characters, maps and the adventure.')
for e, txt in zip(entries_of(t1), [
    'Chop wood or fight with it. A cheap, reliable weapon.',
    'Fast and light, ideal for the thief, but it does not do much damage.',
    'The classic weapon of a knight, and it hits harder.',
    'A huge, heavy axe, typically carried by dwarves.',
    'As heavy as the battleaxe, and it crushes armor.',
    'The mace is the weapon of choice for a priest.']):
    setc(e['content'], txt)
touch_entries(t1['_entries_'])
setc(t2['_description_'], 'A dice table uses a dice (here a D20). The names are dice results and can be ranges such as 1-3. The app does not validate the entries; a generator ignores a result it cannot find. That lets you add rows without values, or roll on a plain list.\nThe content can contain several links, often more dice. Tap a link to roll or open it.')
touch_entries(t2['_entries_'])

# ======================= DICE =======================
dice = items(6)
d_by = {d['_id']: d for d in dice}
setc(d_by['9FFF5240-8533-40B0-892A-6B9D8D332DB0']['_description_'],
     'Dice are the heart of every game. This editor manages the dice and special rules for how a result is calculated.\n\n'
     'Categories: rule dice belong to a rule system, table dice are for the tables module (usually summed), and character dice are special dice used inside a character.\n\n'
     'Settings\nSum dice: add up all dice, exploding dice included.\nModifier: always added to (or subtracted from) the roll.\nCheck against: compare the result with a value (less than, less or equal, greater or equal, greater), or switch it off.\n\n'
     'Critical hit and fumble settings\nChoose whether a single die value or the total triggers it, enter the number and add it. A critical hit is a lucky success, a fumble a total failure. Optionally only the first die counts.\n\n'
     'Reroll settings\nA die can be rolled again (an exploding die). Either only the new roll counts, or all rolls are added, with an optional replacement value for the first roll.\n\n'
     'Special settings\nSort dice by value before calculating (DungeonSlayers), or add another die at a threshold, for example another D20 on every 20.\n\n'
     'A character value can link a dice and use its own number as the comparison value. The Battle Round rolls the dice linked to the Ini entry for the initiative.')
setc(d_by['92386123-626A-4975-8B15-7C8A05F2F858']['_description_'], 'Call of Cthulhu: a percentage roll that must be less than or equal to the skill value. 01 and 05 are critical successes, 96 to 100 is a fumble.')
setc(d_by['92386123-626A-4975-8B15-7C8A05F2F858']['_name_'], 'Call of Cthulhu')
for i, d in d_by.items():
    if d['_description_']['_crdtValue']['_storage']['value'] == 'Treasure Dice':
        setc(d['_description_'], 'Sum dice for the loot tables. Used as the dice of a dice table.')

# ======================= PHOTOS / AUDIO / PDF / SPACE / WEATHER =======================
photos = {p['_id']: p for p in items(1)}
setc(photos[PHOTO_GM]['_description_'], 'A portrait for the game master. The photo is only shown in lists and on the pin of the game master.')
setc(photos[PHOTO_MAP]['_description_'], 'This photo is the base of the map. Any photo or floor plan works: the Map module cuts it into rooms that you reveal in the game.')
setc(photos[PHOTO_CHAR]['_description_'], 'The portrait of a character. In the game it is the pin on the map and the avatar next to the HP bar in the Battle Round. An AI-generated image.')
setc(photos[PHOTO_ADV]['_description_'], 'The cover of the adventure. Show it to the players in the game with the photo link. An AI-generated image.')
setc(items(10)[0]['_description_'], 'The music module manages your music. Playlists make it easy to use music in the game, and a link in an adventure, character or map starts the track with one tap. Files stay in iCloud; players receive them over SharePlay or the local network.')
pdf = items(11)[0]
setc(pdf['_description_'], 'Manage your PDFs here: adventures, characters, rules and supplements. Each PDF can have bookmarks. A bookmark link shows the bookmark text inside the content where it is used, and a PDF link opens the document. PDFs can be linked from adventures, maps, characters and tables.')
pe = entries_of(pdf)
set_entry(pe[0], 'Bookmark', 'The bookmark text can come from the PDF or be typed. It is what a link to this bookmark shows.')
set_entry(pe[1], 'Page bookmark', 'Bookmarks give quick access to a page. This one is on page 2.')
touch_entries(pdf['_entries_'])
setc(items(12)[0]['_description_'], 'The Space module manages 3D objects in USDZ format. Free and paid models are available on the web, and an iPhone or iPad with LiDAR can scan its own objects with the scanner button. In the game a 3D object can be shown to the players and rotated.')
setc(items(7)[0]['_description_'], 'Simulate weather to give a scene more atmosphere: rain, clouds, storms and lightning. Play with the values until the weather suits you. Add a background photo in the photo section; not every photo works, so experiment a little.\nStars appear at night; set the time to noon to remove them. With lightning enabled a tap creates a bolt, otherwise they fall at the configured frequency. In the game the weather is shown to the players.')

# ======================= MAP =======================
mp = items(2)[0]
setc(mp['_description_'], 'A map is a photo with layers (rooms) that hide content from the players. Use it as a dungeon map with pins or as a world map. Every room can link characters, maps, dice, tables, audio, PDFs, photos and 3D objects. The Battle Round and the 3D game table work from the same map.')
me = entries_of(mp)
set_entry(me[0], 'Entrance', 'The entrance of the temple. ' + link('03 Elara Dawnwhisper', 'VALUES', elara_id) + ' waits for the party here. Her pin belongs to a player.')
set_entry(me[1], 'Main Hall', 'The main building. Two goblin archers guard it: ' + link('04 Goblin Archer', 'VALUES', gob_id) + '. Start the Battle Round from the game menu to roll their initiative and track their HP. Add links by drag and drop or selection, for example the photo ' + link('00 Character', 'PHOTOS', PHOTO_CHAR) + ' or the music ' + L_AUDIO + '.')
set_entry(me[2], 'Further rooms', 'You do not have to mark every place. A description should belong to a place on the map, usually a room, but any shape works. Add tables, dice, music, photos, 3D objects, PDFs or characters (as monsters or NPCs) to the room. Rooms start hidden; reveal them in the game with the fog of war.')
set_entry(me[3], 'Pins', 'When a character link is added, the app offers a pin. The pin uses the character photo; if several photos are linked it picks one. Pins that link a character with an HP value show a colored health ring (green, orange, red) and a red highlight when it is that character\'s turn. A fighter can be marked as dead.')
touch_entries(mp['_entries_'])

# pins: Elara (player) + two goblins
pins = mp['_mapPins_']['_value']
elara_pin = pins[0]
elara_pin.update({'name': 'Elara', 'photoId': PHOTO_CHAR, 'characterId': elara_id, 'isShown': True, 'isPlayer': True, 'size': 2})
goblin_pins = []
for i, loc in enumerate(([300.0, 360.0], [330.0, 450.0])):
    gp = copy.deepcopy(elara_pin)
    gp.update({'id': uid(), 'name': f'Goblin {i + 1}', 'photoId': None, 'characterId': gob_id, 'location': loc, 'isShown': False,
               'isPlayer': False, 'color': {'red': 0.2, 'green': 0.7, 'blue': 0.25, 'opacity': 1}, 'size': 1})
    gp.pop('photoId')
    goblin_pins.append(gp)
pins.extend(goblin_pins)
touch_entries(mp['_mapPins_'])

# ======================= ADVENTURE =======================
adv = items(4)[0]
setc(adv['_description_'], 'The adventure is the story. Its entries divide it into chapters, and links connect every other module: PDFs, music, photos, characters, tables, dice, maps, 3D objects and weather. In the game you run the adventure by opening its links.')
ae = entries_of(adv)
set_entry(ae[0], 'Welcome', 'This tutorial adventure shows every module. Entries hold any text. Dice, music and every other module are one tap away: roll ' + L_5D20 + ', start the music ' + L_AUDIO + ', or open the PDF ' + L_PDF + '.')
set_entry(ae[1], 'The temple', 'Explore the map ' + L_MAP + ' or show a photo to the players: ' + link('02 Adventure', 'PHOTOS', PHOTO_ADV) + '.')
set_entry(ae[2], 'Structure', 'How you structure the story is up to you. Like tables and characters, an adventure can contain further adventures. Folders group your adventures.')
set_entry(ae[3], 'Characters', 'Add heroes, NPCs and monsters: ' + link('03 Elara Dawnwhisper', 'VALUES', elara_id) + ', ' + link('04 Goblin Archer', 'VALUES', gob_id) + ' or the explainer ' + link('00 Character', 'VALUES', CHAR_EXPLAIN) + '.')
set_entry(ae[4], 'Other content', 'Use tables ' + L_LOOT + ', weather ' + L_WEATHER + ' and 3D objects ' + L_SPACE + '.')
set_entry(ae[5], 'Let us go', 'Compile everything in one place with links and run the game by opening them.')
ae.extend([
    text_entry('Battle Round', 'Open the map ' + L_MAP + ', reveal the Main Hall and start the Battle Round. Every pin with a character joins the fight. The round rolls initiative from the "Ini" entry, tracks HP from the "HP" entry and highlights the active pin. Drag the order to change it, mark a fighter as dead, and end the fight with End.'),
    text_entry('Game mode', 'Start a game from the adventure to play with your group. Players join with SharePlay or over the local network and see only what you show them: photos, maps with fog of war, music, 3D objects and tables. The "pause sharing" toggle keeps your edits private until you refresh the shared map.'),
    text_entry('3D game table', 'On Apple Vision Pro the game opens a volumetric table: the map, fog and pins stand on the table, with a dice pool for each seat. On iPad, iPhone and Mac the same table is a camera view of the map without dice or seats.'),
    text_entry('Search and links', 'Search finds items, entries and text across all modules. Type @ in the search field for the tags. Links in any content can be shared with the players, rolled or opened in their own window.'),
    text_entry('Tips', 'Use the tags to find items, hide groups you only need as a template, and export an adventure with everything it links to as a single package for your players.'),
])
touch_entries(adv['_entries_'])

# ---------- write ----------
save(DST, head, mods)
print('written', DST, sum(len(m['items']) for m in mods), 'items')
