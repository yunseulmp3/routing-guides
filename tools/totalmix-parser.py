# -*- coding: utf-8 -*-
"""TotalMix 프리셋(.tmss/.tmws) → 윤슬 라우팅 요약"""
import re, io, sys

def parse(path):
    s = io.open(path, encoding='utf-8', errors='replace').read()
    def sec(n):
        m = re.search(r'<%s>(.*?)</%s>' % (n, n), s, re.S)
        return m.group(1) if m else ''
    def names(n):
        d = {}
        for i, v in re.findall(r'<val e="Name (\d+)" v="([^"]*)"', sec(n)):
            v = v.strip().rstrip(',')
            if v: d[int(i)] = v
        return d
    def flags(n, key):
        d = {}
        for i, v in re.findall(r'<val e="%s (\d+)" v="([^"]*)"' % key, sec(n)):
            d[int(i)] = float(v.rstrip(','))
        return d
    mixer = {}
    for a, b, v in re.findall(r'<val e="Slider (\d+) (\d+)" v="([^"]*)"', sec('Mixer')):
        mixer[(int(a), int(b))] = float(v.rstrip(','))
    return {
        'in': names('Inputs'), 'pb': names('Playbacks'), 'out': names('Outputs'),
        'inmute': flags('Inputs', 'Chan Mute'), 'mixer': mixer,
        'loop': flags('Outputs', 'Loopback'),
        'rate': (re.search(r'SampleRate" v="([\d.]+)', s).group(1) if 'SampleRate' in s else '?')
    }

def db(v):
    return '−∞' if v is None or v <= -64.9 else ('%+.1f dB' % v if v else '0.0 dB')

def report(path):
    d = parse(path)
    OUT_OFFSET, PB_BASE, MASTER = 2, 12, 24
    print('=' * 60)
    print(' 파일:', path)
    print('=' * 60)
    print('\n[하드웨어 입력]')
    for i, n in sorted(d['in'].items()):
        print('   %-14s %s' % (n, '뮤트됨' if d['inmute'].get(i) == 1.0 else '열려 있음'))
    print('\n[출력별 서브믹스]')
    for oi, on in sorted(d['out'].items()):
        mi = oi + OUT_OFFSET
        sends = []
        for pi, pn in sorted(d['pb'].items()):
            v = d['mixer'].get((mi, PB_BASE + pi))
            if v is not None and v > -64.9:
                sends.append('%s %s' % (pn, db(v)))
        master = d['mixer'].get((mi, MASTER))
        lb = '[루프백 ON]' if d['loop'].get(oi) == 1.0 else '           '
        print('   ● %-14s %s 마스터 %-9s ← %s' % (on, lb, db(master), ', '.join(sends) if sends else '(없음)'))
    print()

for p in sys.argv[1:]:
    report(p)
