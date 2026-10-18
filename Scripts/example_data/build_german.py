#!/usr/bin/env python3
"""Builds ExampleData-Deutsch.gmz from the reviewed English package.

Folders (category 2) stay as they are. Every other item becomes a German duplicate with a new id;
links, parent references and folder child lists are remapped to the new ids.

usage: german.py SRC.gmz DST.gmz [--list]   (--list prints the untranslated strings)
"""
import json, re, struct, sys, urllib.parse, uuid

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from translations import TR, TAGS, LINKS

SRC, DST = sys.argv[1], sys.argv[2]
LIST_ONLY = '--list' in sys.argv
LINK = re.compile(r'\[([^\]]*)\]\((RPG://[^)]*)\)')
UUID = re.compile(r'[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
TKEYS = {'_name_', '_description_', 'name', 'content', 'value', 'description'}


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


def crdt(node):
    return node['_crdtValue']['_storage']


def get(item, *keys):
    for k in keys:
        if k in item:
            return crdt(item[k])['value'] if isinstance(item[k], dict) and '_crdtValue' in item[k] else item[k]
    return None


head, mods = load(SRC)

# ---------- folders: dedupe, collect id map ----------
idmap = {}
for m in mods:
    seen = set()
    kept = []
    for it in m['items']:
        j = it['json']
        if get(j, '_category_', 'category') == 2:
            if j['_id' if '_id' in j else 'id'] in seen:
                continue
            seen.add(j['_id' if '_id' in j else 'id'])
        else:
            idmap[j['_id' if '_id' in j else 'id']] = str(uuid.uuid4()).upper()
        kept.append(it)
    m['items'] = kept

# ---------- translation ----------
missing = []


def skeleton(text):
    links = LINK.findall(text)
    sk = LINK.sub(lambda m: '{}', text)
    return sk, links


def tr_text(text, key):
    if not text or not re.search(r'[A-Za-z]', text):
        return text
    sk, links = skeleton(text)
    new_links = [(LINKS.get(t, t), target) for t, target in links]
    if not re.search(r'[A-Za-z]', sk.replace('{}', '')):
        out = sk
    elif sk in TR:
        out = TR[sk]
    else:
        missing.append((key, sk))
        out = sk
    it = iter(new_links)
    return re.sub(r'\{\}', lambda _: '[%s](%s)' % next(it), out) if links else out


def walk(node, key=None, is_entry_value_text=True):
    if isinstance(node, dict):
        if '_crdtValue' in node:
            s = crdt(node)
            v = s['value']
            if key == '_tags_' or key == 'tags':
                s['value'] = [TAGS.get(t, t) for t in v]
            elif key in TKEYS and isinstance(v, str):
                s['value'] = tr_text(v, key)
            return
        for k, v in node.items():
            walk(v, k)
    elif isinstance(node, list):
        for v in node:
            walk(v, key)


files_renamed = 0
for m in mods:
    for it in m['items']:
        j = it['json']
        if get(j, '_category_', 'category') == 2:
            continue
        walk(j)
        fu = j.get('_fileUrl_')
        if fu and (fu.get('_value') or {}).get('_url'):
            val = fu['_value']
            name = get(j, '_name_')
            folder, _, last = urllib.parse.unquote(val['_url']).rpartition('/')
            ext = last.rpartition('.')[2]
            val['_url'] = f"{folder}/{urllib.parse.quote(name)}.{ext}"

if LIST_ONLY:
    seen = set()
    for key, sk in missing:
        if sk not in seen:
            seen.add(sk)
            print(json.dumps(sk, ensure_ascii=False))
    print(len(seen), 'untranslated', file=sys.stderr)
    sys.exit(0)

if missing:
    print('UNTRANSLATED:', len(missing), file=sys.stderr)
    for key, sk in missing[:20]:
        print(' ', key, repr(sk[:80]), file=sys.stderr)
    sys.exit(1)

# ---------- id remap on the serialized JSON ----------
for m in mods:
    for it in m['items']:
        text = json.dumps(it['json'], ensure_ascii=False)
        text = UUID.sub(lambda mt: idmap.get(mt.group(0), mt.group(0)), text)
        it['json'] = json.loads(text)

save(DST, head, mods)
print('written', DST, sum(len(m['items']) for m in mods), 'items,', len(idmap), 'duplicated')
