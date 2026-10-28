#!/usr/bin/env python3
# this file has been modified with the assistance of AI Tool [claude 4.6]
"""Standalone go test -json tally. Takes JSON log paths as argv (NOT stdin).
"""
import sys, json, os, collections

def load(path):
    evs = []
    with open(path, 'r', errors='replace') as fh:
        for line in fh:
            line = line.strip()
            if not line or not line.startswith('{'):
                continue
            try:
                evs.append(json.loads(line))
            except Exception:
                continue
    return evs

def analyse(path, detail=False, only=None):
    name = os.path.basename(path)
    evs = load(path)
    p = f = s = 0
    failed = []
    out = collections.defaultdict(list)
    pkgfail = set()
    for e in evs:
        a = e.get('Action'); t = e.get('Test'); pkg = e.get('Package', '')
        if a == 'output' and t:
            out[(pkg, t)].append(e.get('Output', ''))
        if a == 'output' and not t:
            out[(pkg, None)].append(e.get('Output', ''))
        if t:
            if a == 'pass': p += 1
            elif a == 'skip': s += 1
            elif a == 'fail':
                f += 1; failed.append((pkg, t))
        else:
            if a == 'fail':
                pkgfail.add(pkg)
    print(f"[{name}] PASS={p} FAIL={f} SKIP={s} TOTAL={p+f+s}")
    print(f"[{name}] packages with non-test (build/setup) failure: {len(pkgfail)}")
    for q in sorted(pkgfail):
        txt = ''.join(out.get((q, None), []))
        marker = ''
        for key in ('build failed', 'setup failed', 'build constraints exclude'):
            if key in txt:
                marker = key; break
        print(f"    ! {q}  [{marker or 'test failures only'}]")
    if failed:
        print(f"[{name}] failing tests ({len(failed)}):")
        for pkg, t in failed:
            print(f"    - {pkg} :: {t}")
    if detail:
        print(f"\n===== ASSERTION TEXT [{name}] =====")
        for pkg, t in failed:
            if only and only not in t and only not in pkg:
                continue
            print(f"\n----- {pkg} :: {t} -----")
            body = ''.join(out.get((pkg, t), []))
            print(body.rstrip() or '(no captured output)')
    return p, f, s

def main():
    args = [a for a in sys.argv[1:]]
    detail = '--detail' in args
    args = [a for a in args if a != '--detail']
    only = None
    if '--only' in args:
        i = args.index('--only'); only = args[i+1]; del args[i:i+2]
    tp = tf = ts = 0
    for path in args:
        p, f, s = analyse(path, detail=detail, only=only)
        tp += p; tf += f; ts += s
        print()
    print(f"[TOTAL] PASS={tp} FAIL={tf} SKIP={ts} TOTAL={tp+tf+ts}")

if __name__ == '__main__':
    main()
