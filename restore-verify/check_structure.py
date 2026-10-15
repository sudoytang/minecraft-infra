#!/usr/bin/env python3
"""Structure check for an extracted Paper server dir. Usage: check_structure.py SERVER_DIR SEED"""
import gzip, struct, sys, os, glob, json, random, zlib

def nbt(buf):
    pos = 0
    def rd(n):
        nonlocal pos; b = buf[pos:pos+n]; pos += n; return b
    def s(): (l,) = struct.unpack('>H', rd(2)); return rd(l).decode('utf-8', 'replace')
    def p(t):
        if t == 1: return struct.unpack('>b', rd(1))[0]
        if t == 2: return struct.unpack('>h', rd(2))[0]
        if t == 3: return struct.unpack('>i', rd(4))[0]
        if t == 4: return struct.unpack('>q', rd(8))[0]
        if t == 5: return struct.unpack('>f', rd(4))[0]
        if t == 6: return struct.unpack('>d', rd(8))[0]
        if t == 7: (n,) = struct.unpack('>i', rd(4)); rd(n); return b''
        if t == 8: return s()
        if t == 9:
            et = rd(1)[0]; (n,) = struct.unpack('>i', rd(4)); return [p(et) for _ in range(n)]
        if t == 10:
            d = {}
            while True:
                tt = rd(1)[0]
                if tt == 0: return d
                k = s(); d[k] = p(tt)
        if t == 11: (n,) = struct.unpack('>i', rd(4)); return list(struct.unpack('>%di' % n, rd(4*n)))
        if t == 12: (n,) = struct.unpack('>i', rd(4)); rd(8*n); return []
        raise ValueError('bad tag %d' % t)
    t = rd(1)[0]; s(); return p(t)

def find_key(o, key, path=''):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == key and isinstance(v, int): yield path + '/' + k, v
            yield from find_key(v, key, path + '/' + k)
    elif isinstance(o, list):
        for i, v in enumerate(o): yield from find_key(v, key, path)

def main():
    root, seed = sys.argv[1], int(sys.argv[2])
    res = {'ok': True, 'notes': []}
    def fail(m): res['ok'] = False; res['notes'].append('FAIL: ' + m)
    w = os.path.join(root, 'world')
    ld = os.path.join(w, 'level.dat')
    if not os.path.isfile(ld):
        fail('level.dat missing'); print(json.dumps(res)); return 1
    try:
        data = nbt(gzip.open(ld).read())
        res['level_name'] = data.get('Data', {}).get('LevelName')
        res['data_version'] = data.get('Data', {}).get('DataVersion')
    except Exception as e:
        fail('level.dat parse: %r' % e); data = {}
    # seed may live in level.dat or (newer versions) world/data/*.dat
    seeds = list(find_key(data, 'seed'))
    for f in glob.glob(os.path.join(w, '**', 'data', '**', '*.dat'), recursive=True):
        try:
            raw = open(f, 'rb').read()
            if raw[:2] == b'\x1f\x8b': raw = gzip.decompress(raw)
            seeds += [(os.path.relpath(f, w) + p, v) for p, v in find_key(nbt(raw), 'seed')]
        except Exception:
            pass
    res['seed_found'] = seeds[:3]
    if not any(v == seed for _, v in seeds): fail('seed %d not found (found %s)' % (seed, seeds[:3]))
    dims = {'overworld': ['dimensions/minecraft/overworld/region', 'region'],
            'the_nether': ['dimensions/minecraft/the_nether/region', 'DIM-1/region'],
            'the_end': ['dimensions/minecraft/the_end/region', 'DIM1/region']}
    res['regions'] = {}
    for d, cands in dims.items():
        files = []
        for c in cands: files += glob.glob(os.path.join(w, c, '*.mca'))
        res['regions'][d] = len(files)
        if not files: fail('no .mca for ' + d); continue
        bad = 0; checked = 0
        for f in random.sample(files, min(8, len(files))):
            b = open(f, 'rb').read()
            if len(b) == 0: continue  # empty region files are legal
            if len(b) < 8192: bad += 1; continue
            for i in range(1024):
                off = int.from_bytes(b[i*4:i*4+3], 'big'); cnt = b[i*4+3]
                if off == 0: continue
                if off < 2 or (off + cnt) * 4096 > len(b): bad += 1; break
                if checked < 40 * 1:
                    st = off * 4096; (ln,) = struct.unpack('>I', b[st:st+4]); comp = b[st+4]
                    try:
                        if comp == 2: zlib.decompress(b[st+5:st+4+ln])
                        elif comp == 1: gzip.decompress(b[st+5:st+4+ln])
                        checked += 1
                    except Exception: bad += 1; break
        res.setdefault('chunks_decompressed', {})[d] = checked
        if bad: fail('%s: %d bad region headers/chunks' % (d, bad))
    print(json.dumps(res)); return 0 if res['ok'] else 1

sys.exit(main())
