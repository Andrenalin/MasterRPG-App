#!/usr/bin/env python3
"""Replaces the file of the "00 Pdf" item in an example package. usage: embed_pdf.py PACKAGE.gmz GUIDE.pdf OUT.gmz"""
import sys, json, struct, hashlib, base64

src, pdf, dst = sys.argv[1:4]
d = open(src, 'rb').read()
p = 0


def u():
    global p
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

blob = open(pdf, 'rb').read()
digest = base64.b64encode(hashlib.sha256(blob).digest()).decode()
done = 0
for m in mods:
    if m['token'] != 11:  # PDF module
        continue
    for it in m['items']:
        j = it['json']
        if '_fileUrl_' in j and (j['_fileUrl_'].get('_value') or {}).get('_url', '').endswith('.pdf'):
            it['file'] = blob
            j['_fileUrl_']['_value']['contentHash'] = digest
            done += 1
assert done == 1, done

out = bytearray(struct.pack('<III', sum(len(m['items']) for m in mods), 8096, head[2]))
for m in mods:
    out += struct.pack('<III', len(m['items']), m['token'], m['version'])
    for it in m['items']:
        if it['file'] is not None:
            out += struct.pack('<II', len(it['file']), 10001) + it['file']
        data = json.dumps(it['json'], ensure_ascii=False, separators=(',', ':')).encode()
        out += struct.pack('<II', len(data), 10000) + data
open(dst, 'wb').write(out)
print('written', dst, len(out))
