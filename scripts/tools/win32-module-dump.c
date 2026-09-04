/* Dump a loaded 32-bit Windows module from another process.
 *
 * FFXiMain.dll is packed on disk, so its runtime code cannot be disassembled
 * from the installed file. This helper finds a process and module by name,
 * reads the unpacked image with ReadProcessMemory, and writes it to a file.
 *
 * Build with:
 *   i686-w64-mingw32-gcc -O2 -Wall -Wextra -o win32-module-dump.exe \
 *     scripts/tools/win32-module-dump.c
 *
 * Usage:
 *   win32-module-dump.exe horizon-loader.exe FFXiMain.dll Z:\\private\\tmp\\FFXiMain.mem
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static DWORD find_process(const char *name) {
  PROCESSENTRY32 entry = {0};
  entry.dwSize = sizeof(entry);
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE)
    return 0;

  DWORD pid = 0;
  if (Process32First(snapshot, &entry)) {
    do {
      if (_stricmp(entry.szExeFile, name) == 0) {
        pid = entry.th32ProcessID;
        break;
      }
    } while (Process32Next(snapshot, &entry));
  }
  CloseHandle(snapshot);
  return pid;
}

static int find_module(DWORD pid, const char *name, MODULEENTRY32 *module) {
  module->dwSize = sizeof(*module);
  HANDLE snapshot = CreateToolhelp32Snapshot(
      TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
  if (snapshot == INVALID_HANDLE_VALUE)
    return 0;

  int found = 0;
  if (Module32First(snapshot, module)) {
    do {
      if (_stricmp(module->szModule, name) == 0) {
        found = 1;
        break;
      }
    } while (Module32Next(snapshot, module));
  }
  CloseHandle(snapshot);
  return found;
}

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: %s PROCESS.exe MODULE.dll OUTPUT\n", argv[0]);
    return 64;
  }

  DWORD pid = find_process(argv[1]);
  if (!pid) {
    fprintf(stderr, "process not found: %s\n", argv[1]);
    return 1;
  }

  MODULEENTRY32 module = {0};
  if (!find_module(pid, argv[2], &module)) {
    fprintf(stderr, "module not found in pid %lu: %s\n",
            (unsigned long)pid, argv[2]);
    return 1;
  }

  HANDLE process = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
                               FALSE, pid);
  if (!process) {
    fprintf(stderr, "OpenProcess(%lu) failed: %lu\n",
            (unsigned long)pid, (unsigned long)GetLastError());
    return 1;
  }

  BYTE *image = (BYTE *)calloc(1, module.modBaseSize);
  if (!image) {
    fprintf(stderr, "could not allocate %lu bytes\n",
            (unsigned long)module.modBaseSize);
    CloseHandle(process);
    return 1;
  }

  SIZE_T total = 0;
  const SIZE_T chunk_size = 4096;
  for (SIZE_T offset = 0; offset < module.modBaseSize; offset += chunk_size) {
    SIZE_T wanted = module.modBaseSize - offset;
    if (wanted > chunk_size)
      wanted = chunk_size;
    SIZE_T got = 0;
    if (ReadProcessMemory(process, module.modBaseAddr + offset,
                          image + offset, wanted, &got))
      total += got;
  }
  CloseHandle(process);

  FILE *output = fopen(argv[3], "wb");
  if (!output) {
    fprintf(stderr, "could not open output: %s\n", argv[3]);
    free(image);
    return 1;
  }
  size_t written = fwrite(image, 1, module.modBaseSize, output);
  fclose(output);
  free(image);

  if (written != module.modBaseSize) {
    fprintf(stderr, "short write: %lu of %lu bytes\n",
            (unsigned long)written, (unsigned long)module.modBaseSize);
    return 1;
  }

  printf("pid=%lu base=0x%08lx size=%lu readable=%lu output=%s\n",
         (unsigned long)pid, (unsigned long)(uintptr_t)module.modBaseAddr,
         (unsigned long)module.modBaseSize, (unsigned long)total, argv[3]);
  return total ? 0 : 1;
}
