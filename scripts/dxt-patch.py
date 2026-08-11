#!/usr/bin/env python3
"""Teach wined3d's Vulkan backend about DXT1-5.

wined3d keeps a static table mapping wined3d format ids to VkFormats. It lists the D3D10-era
names (WINED3DFMT_BC1_UNORM ...) but not the D3D8/9 FourCC aliases (WINED3DFMT_DXT1 ...), which
are *different enum values*. A D3D8 game like FFXI creates its textures as DXT1/3/5, wined3d looks
those ids up, misses, logs "Unsupported format WINED3DFMT_DXT1" and drops the texture — which is
why every model and terrain surface renders untextured on renderer=vulkan.

The source fix is five extra rows. We do not have a wine build here, so instead we rewrite five
rows *in place* in the shipped PE: the BC4/BC5/BC6H/BC7 entries, which a 2002 D3D8 game can never
ask for. Same table, same size, no relocation, fully reversible from the .orig backup.

    dxtpatch.py <wined3d.dll> [--revert] [--check]
"""
import struct, sys, shutil, os

# Vulkan
BC1_RGBA_UNORM, BC2_UNORM, BC3_UNORM = 133, 135, 137
# wined3d, FourCC — these are absolute and do not shift with the enum
DXT = {n: int.from_bytes(f"DXT{n}".encode(), "little") for n in range(1, 6)}

# (donor wined3d id in THIS binary, donor VkFormat) -> (DXT id, VkFormat)
# Donor ids are read from the binary rather than assumed: Gcenx's tree has one extra enum
# member ahead of these, so every id sits one above upstream wine's.
DONOR_VK = [139, 140, 143, 144, 145]           # BC4_UNORM, BC4_SNORM, BC6H_UF, BC6H_SF, BC7_UNORM
NEW = [(DXT[1], BC1_RGBA_UNORM),
       (DXT[2], BC2_UNORM),                    # premultiplied alpha; Vulkan has no such format
       (DXT[3], BC2_UNORM),
       (DXT[4], BC3_UNORM),                    # premultiplied alpha
       (DXT[5], BC3_UNORM)]


def find_table(d):
    """Anchor on the VkFormat column: 133..146 at a 12-byte stride."""
    u = lambda o: struct.unpack_from("<I", d, o)[0]
    for off in range(0, len(d) - 12 * 14 - 8, 4):
        if u(off) != 133:
            continue
        if all(u(off + 12 * k) == 133 + k for k in range(14)):
            return off - 4          # start of the BC1_UNORM row
    return None


def main():
    path = sys.argv[1]
    revert = "--revert" in sys.argv
    check = "--check" in sys.argv
    backup = path + ".orig"

    if revert:
        if not os.path.exists(backup):
            sys.exit("no .orig backup to revert to")
        shutil.copyfile(backup, path)
        print("reverted from", backup)
        return

    d = bytearray(open(path, "rb").read())
    base = find_table(d)
    if base is None:
        sys.exit("could not locate the Vulkan format table")
    print(f"table at 0x{base:x}")

    # map VkFormat -> row offset, for the donor rows
    rows = {}
    for k in range(14):
        o = base + 12 * k
        fid, vk, fixup = struct.unpack_from("<III", d, o)
        rows[vk] = (o, fid, fixup)

    if check:
        for vk in DONOR_VK:
            o, fid, fx = rows[vk]
            print(f"  donor vk={vk} at 0x{o:x} id={fid} fixup=0x{fx:x}")
        return

    if not os.path.exists(backup):
        shutil.copyfile(path, backup)
        print("backed up to", backup)

    for vk_donor, (new_id, new_vk) in zip(DONOR_VK, NEW):
        o, old_id, fixup = rows[vk_donor]
        if fixup:
            sys.exit(f"donor row at 0x{o:x} has a fixup pointer; pick another donor")
        struct.pack_into("<II", d, o, new_id, new_vk)
        name = "DXT" + chr(ord('0') + NEW.index((new_id, new_vk)) + 1) if False else \
               f"DXT{[k for k, v in DXT.items() if v == new_id][0]}"
        print(f"  0x{o:x}: id {old_id} -> {name} ({new_id}), vk {vk_donor} -> {new_vk}")

    open(path, "wb").write(d)
    print("patched", path)


if __name__ == "__main__":
    main()
