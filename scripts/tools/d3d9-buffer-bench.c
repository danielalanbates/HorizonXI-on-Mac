/* Measure D3D9 vertex-buffer creation and first-lock cost under DXVK.
 *
 * Build on macOS with:
 *   i686-w64-mingw32-gcc -O2 -Wall -Wextra -o d3d9-buffer-bench.exe \
 *     scripts/tools/d3d9-buffer-bench.c -ld3d9 -lgdi32
 *
 * Usage:
 *   d3d9-buffer-bench.exe [BUFFER_BYTES] [COUNT] [MODE]
 *
 * MODE is one of dynamic-writeonly, dynamic, writeonly, plain,
 * managed-writeonly, managed, or systemmem. The benchmark creates each
 * buffer, locks it, fills it, and unlocks it so it measures first-touch cost
 * as well as DXVK's constructor.
 */
#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static double now_seconds(void) {
  LARGE_INTEGER frequency;
  LARGE_INTEGER counter;
  QueryPerformanceFrequency(&frequency);
  QueryPerformanceCounter(&counter);
  return (double)counter.QuadPart / (double)frequency.QuadPart;
}

static LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  return DefWindowProcA(window, message, wparam, lparam);
}

static int fail(const char *operation, HRESULT result) {
  fprintf(stderr, "%s failed: 0x%08lx\n", operation, (unsigned long)result);
  return 1;
}

int main(int argc, char **argv) {
  unsigned long size = 131072;
  unsigned long count = 640;
  const char *mode = "dynamic-writeonly";
  if (argc > 1)
    size = strtoul(argv[1], NULL, 10);
  if (argc > 2)
    count = strtoul(argv[2], NULL, 10);
  if (argc > 3)
    mode = argv[3];
  if (!size || !count || argc > 4) {
    fprintf(stderr, "usage: %s [BUFFER_BYTES] [COUNT] [MODE]\n", argv[0]);
    return 2;
  }

  DWORD usage = D3DUSAGE_DYNAMIC | D3DUSAGE_WRITEONLY;
  D3DPOOL pool = D3DPOOL_DEFAULT;
  DWORD lock_flags = D3DLOCK_DISCARD;
  if (!strcmp(mode, "dynamic"))
    usage = D3DUSAGE_DYNAMIC;
  else if (!strcmp(mode, "writeonly")) {
    usage = D3DUSAGE_WRITEONLY;
    lock_flags = 0;
  } else if (!strcmp(mode, "plain")) {
    usage = 0;
    lock_flags = 0;
  } else if (!strcmp(mode, "managed-writeonly")) {
    usage = D3DUSAGE_WRITEONLY;
    pool = D3DPOOL_MANAGED;
    lock_flags = 0;
  } else if (!strcmp(mode, "managed")) {
    usage = 0;
    pool = D3DPOOL_MANAGED;
    lock_flags = 0;
  } else if (!strcmp(mode, "systemmem")) {
    usage = 0;
    pool = D3DPOOL_SYSTEMMEM;
    lock_flags = 0;
  } else if (strcmp(mode, "dynamic-writeonly")) {
    fprintf(stderr, "unknown mode: %s\n", mode);
    return 2;
  }

  HINSTANCE instance = GetModuleHandleA(NULL);
  WNDCLASSA window_class = {0};
  window_class.lpfnWndProc = window_proc;
  window_class.hInstance = instance;
  window_class.lpszClassName = "HorizonXI-D3D9-Buffer-Bench";
  if (!RegisterClassA(&window_class) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    fprintf(stderr, "RegisterClassA failed: %lu\n", GetLastError());
    return 1;
  }
  HWND window = CreateWindowExA(0, window_class.lpszClassName, "D3D9 buffer benchmark",
                                WS_OVERLAPPEDWINDOW, 0, 0, 64, 64, NULL, NULL, instance, NULL);
  if (!window) {
    fprintf(stderr, "CreateWindowExA failed: %lu\n", GetLastError());
    return 1;
  }

  IDirect3D9 *d3d = Direct3DCreate9(D3D_SDK_VERSION);
  if (!d3d) {
    fprintf(stderr, "Direct3DCreate9 failed\n");
    return 1;
  }
  D3DPRESENT_PARAMETERS present = {0};
  present.Windowed = TRUE;
  present.SwapEffect = D3DSWAPEFFECT_DISCARD;
  present.hDeviceWindow = window;
  present.BackBufferWidth = 64;
  present.BackBufferHeight = 64;
  present.BackBufferFormat = D3DFMT_UNKNOWN;
  present.PresentationInterval = D3DPRESENT_INTERVAL_IMMEDIATE;

  IDirect3DDevice9 *device = NULL;
  HRESULT result = IDirect3D9_CreateDevice(
      d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, window,
      D3DCREATE_SOFTWARE_VERTEXPROCESSING | D3DCREATE_FPU_PRESERVE,
      &present, &device);
  if (FAILED(result))
    return fail("IDirect3D9::CreateDevice", result);

  IDirect3DVertexBuffer9 **buffers = calloc(count, sizeof(*buffers));
  if (!buffers) {
    fprintf(stderr, "could not allocate buffer pointer array\n");
    return 1;
  }

  double total_start = now_seconds();
  double create_seconds = 0.0;
  double lock_seconds = 0.0;
  double fill_seconds = 0.0;
  double unlock_seconds = 0.0;
  double max_seconds = 0.0;
  unsigned long max_index = 0;
  unsigned long slow = 0;
  for (unsigned long i = 0; i < count; i++) {
    double start = now_seconds();
    result = IDirect3DDevice9_CreateVertexBuffer(
        device, size, usage, 0, pool, &buffers[i], NULL);
    double elapsed = now_seconds() - start;
    create_seconds += elapsed;
    if (FAILED(result))
      return fail("IDirect3DDevice9::CreateVertexBuffer", result);
    if (elapsed > max_seconds) {
      max_seconds = elapsed;
      max_index = i;
    }
    if (elapsed >= 0.1) {
      slow++;
      printf("slow_create index=%lu seconds=%.6f\n", i, elapsed);
      fflush(stdout);
    }

    void *data = NULL;
    start = now_seconds();
    result = IDirect3DVertexBuffer9_Lock(buffers[i], 0, size, &data, lock_flags);
    elapsed = now_seconds() - start;
    lock_seconds += elapsed;
    if (FAILED(result))
      return fail("IDirect3DVertexBuffer9::Lock", result);
    if (elapsed >= 0.1) {
      printf("slow_lock index=%lu seconds=%.6f\n", i, elapsed);
      fflush(stdout);
    }

    start = now_seconds();
    memset(data, (int)(i & 0xff), size);
    elapsed = now_seconds() - start;
    fill_seconds += elapsed;
    if (elapsed >= 0.1) {
      printf("slow_fill index=%lu seconds=%.6f\n", i, elapsed);
      fflush(stdout);
    }

    start = now_seconds();
    result = IDirect3DVertexBuffer9_Unlock(buffers[i]);
    elapsed = now_seconds() - start;
    unlock_seconds += elapsed;
    if (FAILED(result))
      return fail("IDirect3DVertexBuffer9::Unlock", result);
    if (elapsed >= 0.1) {
      printf("slow_unlock index=%lu seconds=%.6f\n", i, elapsed);
      fflush(stdout);
    }
  }
  double total_seconds = now_seconds() - total_start;
  printf("mode=%s usage=0x%08lx pool=%u size=%lu count=%lu mib=%.3f "
         "seconds=%.6f creates_per_s=%.1f create_s=%.6f lock_s=%.6f "
         "fill_s=%.6f unlock_s=%.6f "
         "slow_creates=%lu max_index=%lu max_create_s=%.6f\n",
         mode, (unsigned long)usage, (unsigned int)pool, size, count,
         (double)size * (double)count / (1024.0 * 1024.0),
         total_seconds, total_seconds > 0.0 ? (double)count / total_seconds : 0.0,
         create_seconds, lock_seconds, fill_seconds, unlock_seconds,
         slow, max_index, max_seconds);
  fflush(stdout);

  for (unsigned long i = 0; i < count; i++)
    IDirect3DVertexBuffer9_Release(buffers[i]);
  free(buffers);
  IDirect3DDevice9_Release(device);
  IDirect3D9_Release(d3d);
  DestroyWindow(window);
  return 0;
}
