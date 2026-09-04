/* Exercise DXVK's 112-byte DrawPrimitiveUP upload path without launching FFXI.
 *
 * Build with:
 *   i686-w64-mingw32-gcc -O2 -Wall -Wextra -o d3d9-up-bench.exe \
 *     scripts/tools/d3d9-up-bench.c -ld3d9 -lgdi32
 */
#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct Vertex {
  float x, y, z, rhw;
  DWORD color;
  float u, v;
} Vertex;

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
  unsigned long iterations = 200000;
  if (argc == 2)
    iterations = strtoul(argv[1], NULL, 10);
  if (!iterations) {
    fprintf(stderr, "iteration count must be positive\n");
    return 2;
  }

  HINSTANCE instance = GetModuleHandleA(NULL);
  WNDCLASSA window_class = {0};
  window_class.lpfnWndProc = window_proc;
  window_class.hInstance = instance;
  window_class.lpszClassName = "HorizonXI-D3D9-UP-Bench";
  if (!RegisterClassA(&window_class) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    fprintf(stderr, "RegisterClassA failed: %lu\n", GetLastError());
    return 1;
  }
  HWND window = CreateWindowExA(0, window_class.lpszClassName, "D3D9 UP benchmark",
                                WS_OVERLAPPEDWINDOW, 0, 0, 64, 64, NULL, NULL, instance, NULL);
  if (!window) {
    fprintf(stderr, "CreateWindowExA failed: %lu\n", GetLastError());
    return 1;
  }

  const double init_start = now_seconds();
  IDirect3D9 *d3d = Direct3DCreate9(D3D_SDK_VERSION);
  if (!d3d) {
    fprintf(stderr, "Direct3DCreate9 failed\n");
    DestroyWindow(window);
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
  if (FAILED(result)) {
    IDirect3D9_Release(d3d);
    DestroyWindow(window);
    return fail("IDirect3D9::CreateDevice", result);
  }
  const double init_seconds = now_seconds() - init_start;

  result = IDirect3DDevice9_SetFVF(device, D3DFVF_XYZRHW | D3DFVF_DIFFUSE | D3DFVF_TEX1);
  if (FAILED(result))
    return fail("IDirect3DDevice9::SetFVF", result);

  Vertex vertices[4] = {
      {0.0f,  0.0f, 0.0f, 1.0f, 0xffffffffu, 0.0f, 0.0f},
      {32.0f, 0.0f, 0.0f, 1.0f, 0xffffffffu, 1.0f, 0.0f},
      {0.0f, 32.0f, 0.0f, 1.0f, 0xffffffffu, 0.0f, 1.0f},
      {32.0f,32.0f, 0.0f, 1.0f, 0xffffffffu, 1.0f, 1.0f},
  };
  if (sizeof(vertices) != 112) {
    fprintf(stderr, "unexpected vertex payload size: %lu\n", (unsigned long)sizeof(vertices));
    return 1;
  }

  result = IDirect3DDevice9_BeginScene(device);
  if (FAILED(result))
    return fail("IDirect3DDevice9::BeginScene", result);

  double first_start = now_seconds();
  result = IDirect3DDevice9_DrawPrimitiveUP(
      device, D3DPT_TRIANGLESTRIP, 2, vertices, sizeof(Vertex));
  const double first_microseconds = (now_seconds() - first_start) * 1000000.0;
  if (FAILED(result))
    return fail("first IDirect3DDevice9::DrawPrimitiveUP", result);

  const double run_start = now_seconds();
  for (unsigned long i = 0; i < iterations; i++) {
    vertices[0].color ^= (DWORD)i;
    result = IDirect3DDevice9_DrawPrimitiveUP(
        device, D3DPT_TRIANGLESTRIP, 2, vertices, sizeof(Vertex));
    if (FAILED(result))
      return fail("IDirect3DDevice9::DrawPrimitiveUP", result);
    if ((i & 4095u) == 4095u) {
      IDirect3DDevice9_EndScene(device);
      IDirect3DDevice9_Present(device, NULL, NULL, NULL, NULL);
      IDirect3DDevice9_BeginScene(device);
    }
  }
  const double run_seconds = now_seconds() - run_start;

  IDirect3DDevice9_EndScene(device);
  IDirect3DDevice9_Present(device, NULL, NULL, NULL, NULL);
  printf("init_seconds=%.6f first_call_us=%.3f iterations=%lu seconds=%.6f calls_per_s=%.1f payload_bytes=%lu\n",
         init_seconds, first_microseconds, iterations, run_seconds,
         run_seconds > 0.0 ? (double)iterations / run_seconds : 0.0,
         (unsigned long)sizeof(vertices));
  fflush(stdout);

  IDirect3DDevice9_Release(device);
  IDirect3D9_Release(d3d);
  DestroyWindow(window);
  return 0;
}
