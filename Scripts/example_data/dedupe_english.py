"""Writes the reviewed English package with duplicate folder copies removed (usage: dedupe.py SRC DST)."""
import sys, json
sys.argv = [sys.argv[0], sys.argv[1], sys.argv[2]]
src = open(__file__.rsplit('/', 1)[0] + '/build_german.py').read().split('# ---------- folders: dedupe')[0]
exec(src)
for m in mods:
    seen, kept = set(), []
    for it in m['items']:
        j = it['json']
        if get(j, '_category_', 'category') == 2:
            i = j.get('_id', j.get('id'))
            if i in seen:
                continue
            seen.add(i)
        kept.append(it)
    m['items'] = kept
save(DST, head, mods)
print('written', DST, sum(len(m['items']) for m in mods), 'items')
