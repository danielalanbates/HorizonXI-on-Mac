/* icon-into-exe.exe <target.exe> <icon.ico>
 *
 * Adds an .ico as the executable's icon, using Windows' own resource-update API so no PE surgery
 * happens here. Built for i686 and run under wine; see scripts/theme-loader.sh.
 *
 * Why this exists: wine's macOS driver takes the Dock tile from the *first RT_GROUP_ICON of the
 * running .exe*, once, at first window creation (dlls/winemac.drv/window.c: pthread_once ->
 * set_app_icon -> dllmain.c: macdrv_app_icon -> EnumResourceNamesW(NULL, RT_GROUP_ICON, ...)).
 * HorizonXI's horizon-loader.exe carries no icon resource at all -- only version and manifest --
 * so wine logs "found no RT_GROUP_ICON resource" and the game sits in the Dock under wine's
 * generic tile. Give the exe an icon and the tile follows. Nothing else moves it: WM_SETICON is
 * read for window icons only, and the app icon is latched before any addon can run.
 *
 * Operates on a copy. Never point this at a server's own binary in place.
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

#pragma pack(push, 1)
typedef struct { WORD reserved, type, count; } ICONDIR;
typedef struct {
    BYTE width, height, colors, reserved;
    WORD planes, bpp;
    DWORD bytes, offset;
} ICONDIRENTRY;
typedef struct {
    BYTE width, height, colors, reserved;
    WORD planes, bpp;
    DWORD bytes;
    WORD id;
} GRPICONDIRENTRY;
#pragma pack(pop)

int main(int argc, char **argv)
{
    if (argc != 3) { fprintf(stderr, "usage: icon-into-exe <target.exe> <icon.ico>\n"); return 2; }

    FILE *f = fopen(argv[2], "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", argv[2]); return 1; }
    fseek(f, 0, SEEK_END); long size = ftell(f); fseek(f, 0, SEEK_SET);
    BYTE *ico = malloc(size);
    if (fread(ico, 1, size, f) != (size_t)size) { fprintf(stderr, "short read\n"); return 1; }
    fclose(f);

    ICONDIR *dir = (ICONDIR *)ico;
    if (dir->reserved || dir->type != 1 || !dir->count) { fprintf(stderr, "not an .ico\n"); return 1; }
    ICONDIRENTRY *entries = (ICONDIRENTRY *)(ico + sizeof(ICONDIR));

    HANDLE upd = BeginUpdateResourceA(argv[1], FALSE);
    if (!upd) { fprintf(stderr, "BeginUpdateResource failed: %lu\n", GetLastError()); return 1; }

    /* The group directory the loader will point at, one entry per image, ids 1..count. */
    DWORD grp_size = sizeof(ICONDIR) + dir->count * sizeof(GRPICONDIRENTRY);
    BYTE *grp = calloc(1, grp_size);
    memcpy(grp, dir, sizeof(ICONDIR));
    GRPICONDIRENTRY *g = (GRPICONDIRENTRY *)(grp + sizeof(ICONDIR));

    for (int i = 0; i < dir->count; i++)
    {
        if (!UpdateResourceA(upd, (LPCSTR)RT_ICON, MAKEINTRESOURCEA(i + 1),
                             MAKELANGID(LANG_NEUTRAL, SUBLANG_NEUTRAL),
                             ico + entries[i].offset, entries[i].bytes))
        {
            fprintf(stderr, "UpdateResource(icon %d) failed: %lu\n", i + 1, GetLastError());
            return 1;
        }
        g[i].width = entries[i].width;   g[i].height = entries[i].height;
        g[i].colors = entries[i].colors; g[i].reserved = 0;
        g[i].planes = entries[i].planes; g[i].bpp = entries[i].bpp;
        g[i].bytes = entries[i].bytes;   g[i].id = i + 1;
    }

    if (!UpdateResourceA(upd, (LPCSTR)RT_GROUP_ICON, MAKEINTRESOURCEA(1),
                         MAKELANGID(LANG_NEUTRAL, SUBLANG_NEUTRAL), grp, grp_size))
    {
        fprintf(stderr, "UpdateResource(group) failed: %lu\n", GetLastError());
        return 1;
    }
    if (!EndUpdateResourceA(upd, FALSE))
    {
        fprintf(stderr, "EndUpdateResource failed: %lu\n", GetLastError());
        return 1;
    }
    printf("added %d icon image(s) to %s\n", dir->count, argv[1]);
    return 0;
}
