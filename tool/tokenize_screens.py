#!/usr/bin/env python3
"""One-shot tokenizer: swap hardcoded theme literals for ThemeSlot accessors.

Not part of the app. Kept so the mapping stays auditable and re-runnable if a
fourth screen needs the same treatment.

    python3 tool/tokenize_screens.py lib/ui/screens/garage_screen.dart ...
"""
import re
import sys

# Applied in order: `Colors.white.withOpacity` has to go before bare
# `Colors.white` or it would match the prefix and leave `(.4)` dangling.
SUBS = [
    (r'Colors\.white\.withOpacity\(([\d.]+)\)', r'_slot.dim(\1)'),
    (r'Colors\.white\b', '_slot.text'),
    (r'Colors\.black\b', '_slot.onAccent'),
    (r'Colors\.redAccent\b', '_slot.danger'),
    (r'Colors\.orangeAccent\b', '_slot.warning'),
    (r'Colors\.amber\b', '_slot.warning'),
    (r'Color\(0xFF080B11\)', '_slot.background'),
    (r'Color\(0xFF0C1017\)', '_slot.surface'),
    (r'Color\(0xFF0F172A\)', '_slot.elevated'),
    (r'Color\(0xFF131B2E\)', '_slot.elevated'),
    (r'Color\(0xFF00E5FF\)', '_slot.accent'),
    (r'Color\(0xFF00FF66\)', '_slot.positive'),
    (r'Color\(0xFFFFB300\)', '_slot.warning'),
]

# Material's pre-baked white opacities. 10/12/24 are hairlines and dividers,
# not dimmed text, so they map to border() rather than dim().
BORDER_PCT = {'10', '12', '24'}

CONST_HEAD = re.compile(r'\bconst\s+[A-Za-z_][\w.]*\s*\(')
CONST_BRACKET = re.compile(r'\bconst\s*[\[{]')
# After the substitution, a former `const Color(0xFF...)` reads
# `const _slot.elevated` -- there is no `(` left for CONST_HEAD to anchor on,
# so the accessor form needs its own pattern. The type argument covers
# `const AlwaysStoppedAnimation<Color>(...)`.
CONST_SLOT = re.compile(r'\bconst\s+_slot\.')

def _white_variant(m):
    pct = m.group(1)
    # Material's named opacities are whole percents: white10 is 0.1, not 10.
    op = str(int(pct) / 100.0)
    op = op.rstrip('0').rstrip('.')
    return f'_slot.border({op})' if pct in BORDER_PCT else f'_slot.dim({op})'


def match_bracket(src, open_idx):
    """Index of the bracket closing the one at open_idx, skipping strings.

    Handles (), [] and {} alike because a `const` list needs losing its
    `const` just as much as a `const Text` does.
    """
    depth = 0
    i = open_idx
    while i < len(src):
        ch = src[i]
        if ch in '"\'':
            quote = ch
            i += 1
            while i < len(src) and src[i] != quote:
                i += 2 if src[i] == '\\' else 1
        elif ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def swap(src):
    src = re.sub(r'Colors\.white(\d+)\b', _white_variant, src)
    for pat, rep in SUBS:
        src = re.sub(pat, rep, src)
    return src


def strip_const_near_slot(src):
    """Drop `const` from const-expressions that now read `_slot`.

    `_slot` is a getter, not a compile-time constant, so `const Text(... color:
    _slot.text)` will not compile -- and neither will a `const [...]` holding
    that Text, nor any list nested inside it. So the pass repeats until stable:
    losing a const child invalidates its const parent, which is found on the
    next round.
    """
    while True:
        drop = []
        for pattern in (CONST_HEAD, CONST_BRACKET, CONST_SLOT):
            for m in pattern.finditer(src):
                if pattern is CONST_SLOT:
                    drop.append(m.start())
                    continue
                close = match_bracket(src, m.end() - 1)
                if close is None:
                    continue
                if '_slot' in src[m.end():close]:
                    drop.append(m.start())
        if not drop:
            return src
        for start in sorted(set(drop), reverse=True):
            src = src[:start] + src[start + len('const '):]


if __name__ == '__main__':
    for path in sys.argv[1:]:
        original = open(path).read()
        out = strip_const_near_slot(swap(original))
        if out != original:
            open(path, 'w').write(out)
            print(f'rewrote {path}')
        else:
            print(f'unchanged {path}')
