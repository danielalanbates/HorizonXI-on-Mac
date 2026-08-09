#!/usr/bin/env python3
"""Lift FFXI's COM registration out of a working wine prefix into a .reg file.

FFXI is three COM in-proc servers — FFXi.FFXiEntry (FFXi.dll),
FFXiMain.GameMain (FFXiMain.dll) and POLCore.POLCoreCom (polcore.dll). A prefix
missing any of them fails with "Failed to initialize instance of FFxi!" or a bare
`err:ole:com_get_class_object ... not registered`.

You cannot just run regsvr32: FFXi.dll's DllRegisterServer opens a GUI dialog, and
on macOS synthetic input (CGEvent) does not reach wine-hosted windows, so it hangs
forever with no way to click it. Copying the registry sections is the way.

    ./export-ffxi-com.py <src-prefix>/system.reg ffxi-com.reg
    wine regedit /S 'C:\\ffxi-com.reg'      # in the destination prefix
"""
import re, sys

PATTERN = re.compile(
    r'FFXi|POLCore|PlayOnline|989D79|1027DC46|3501F5DD|07974581|E5966FB3|3B0B8E16',
    re.I)


def main(src, out):
    txt = open(src, encoding='utf-8', errors='replace').read()
    lines = ['Windows Registry Editor Version 5.00', '']
    kept = 0
    for block in re.split(r'\n(?=\[)', txt):
        if not block.startswith('['):
            continue
        header = block.split(']')[0]
        if not PATTERN.search(header):
            continue
        key = re.match(r'\[(.*?)\]', block).group(1).replace('\\\\', '\\')
        # wine's system.reg stores HKLM-relative paths and #time= comments
        body = [l for l in block.split('\n')[1:] if l and not l.startswith('#')]
        lines.append('[HKEY_LOCAL_MACHINE\\' + key + ']')
        lines.extend(body)
        lines.append('')
        kept += 1
    open(out, 'w', encoding='utf-8').write('\n'.join(lines))
    print(f'{kept} sections -> {out}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
