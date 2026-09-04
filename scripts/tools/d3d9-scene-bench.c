/* Reproduce FFXI's scene-load DXVK traffic without an account or server.
 *
 * The game's loading stall samples land in DxvkBuffer::allocBuffer's clearing memset,
 * reached from UpdateFixedFunctionVS (a transform change between draws renames DXVK's
 * fixed-function constant buffer) and from CreateIndexBuffer/CreateVertexBuffer
 * initialisation. This program drives both paths at a scene-load rate: many draws per
 * frame, each with a fresh world transform, plus a batch of new buffers per frame.
 *
 * Build on macOS with:
 *   i686-w64-mingw32-gcc -O2 -Wall -Wextra -o d3d9-scene-bench.exe \
 *     scripts/tools/d3d9-scene-bench.c -ld3d9 -lgdi32
 *
 * Usage:
 *   d3d9-scene-bench.exe [FRAMES] [DRAWS_PER_FRAME] [BUFFERS_PER_FRAME] [BUFFER_BYTES]
 *
 * Prints one line per frame with the frame time so a stall is visible, then a summary.
 */
#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct vertex { float x, y, z; DWORD color; };
#define FVF (D3DFVF_XYZ | D3DFVF_DIFFUSE)

static double now_seconds(void) {
  LARGE_INTEGER f, c;
  QueryPerformanceFrequency(&f);
  QueryPerformanceCounter(&c);
  return (double)c.QuadPart / (double)f.QuadPart;
}

static LRESULT CALLBACK window_proc(HWND w, UINT m, WPARAM wp, LPARAM lp) {
  return DefWindowProcA(w, m, wp, lp);
}

static int fail(const char *op, HRESULT r) {
  fprintf(stderr, "%s failed: 0x%08lx\n", op, (unsigned long)r);
  return 1;
}

static void identity(D3DMATRIX *m) {
  memset(m, 0, sizeof(*m));
  m->_11 = m->_22 = m->_33 = m->_44 = 1.0f;
}

int main(int argc, char **argv) {
  unsigned long frames = 40, draws = 3000, buffers = 64, bytes = 65536;
  if (argc > 1) frames = strtoul(argv[1], NULL, 10);
  if (argc > 2) draws = strtoul(argv[2], NULL, 10);
  if (argc > 3) buffers = strtoul(argv[3], NULL, 10);
  if (argc > 4) bytes = strtoul(argv[4], NULL, 10);

  /* Optional fifth argument: comma-separated steps run in order before the device exists.
   *   load-nonx        load nonx.dll, a DLL without IMAGE_DLLCHARACTERISTICS_NX_COMPAT, the way
   *                    FFXiMain.dll is built; Wine answers by enabling execute on all memory
   *   nx-on            NtSetInformationProcess(ProcessExecuteFlags, MEM_EXECUTE_OPTION_DISABLE)
   *   nx-on-permanent  the same plus MEM_EXECUTE_OPTION_PERMANENT, so later loads cannot undo it
   *   query            print the current flags
   * Flag values: 1 = DISABLE (NX enforced), 2 = ENABLE (execute everywhere), 8 = PERMANENT. */
  typedef LONG (WINAPI *set_info_fn)(HANDLE, int, void *, ULONG);
  typedef LONG (WINAPI *query_fn)(HANDLE, int, void *, ULONG, ULONG *);
  HMODULE ntdll = GetModuleHandleA("ntdll.dll");
  set_info_fn set_info = (set_info_fn)(void *)GetProcAddress(ntdll, "NtSetInformationProcess");
  query_fn query = (query_fn)(void *)GetProcAddress(ntdll, "NtQueryInformationProcess");
  char steps[256] = "";
  if (argc > 5) strncpy(steps, argv[5], sizeof(steps) - 1);
  for (char *step = strtok(steps, ","); step; step = strtok(NULL, ",")) {
    ULONG flags = 0, len = 0;
    if (!strcmp(step, "load-nonx")) {
      if (!LoadLibraryA("nonx.dll")) { fprintf(stderr, "LoadLibraryA(nonx.dll) failed\n"); return 1; }
      printf("loaded nonx.dll\n");
    } else if (!strcmp(step, "nx-on") || !strcmp(step, "nx-on-permanent")) {
      flags = 1 | (strcmp(step, "nx-on") ? 8 : 0);
      LONG st = set_info ? set_info(GetCurrentProcess(), 0x22, &flags, sizeof(flags)) : -1;
      printf("%s: NtSetInformationProcess(ProcessExecuteFlags, 0x%lx) -> 0x%08lx\n", step,
             (unsigned long)flags, (unsigned long)st);
    }
    if (query && query(GetCurrentProcess(), 0x22, &flags, sizeof(flags), &len) == 0)
      printf("after %s: ProcessExecuteFlags=0x%lx\n", step, (unsigned long)flags);
  }

  HINSTANCE inst = GetModuleHandleA(NULL);
  WNDCLASSA wc = {0};
  wc.lpfnWndProc = window_proc; wc.hInstance = inst; wc.lpszClassName = "HXI-Scene-Bench";
  RegisterClassA(&wc);
  HWND window = CreateWindowExA(0, wc.lpszClassName, "D3D9 scene benchmark",
                                WS_OVERLAPPEDWINDOW, 0, 0, 640, 480, NULL, NULL, inst, NULL);
  if (!window) { fprintf(stderr, "CreateWindowExA failed\n"); return 1; }

  IDirect3D9 *d3d = Direct3DCreate9(D3D_SDK_VERSION);
  if (!d3d) { fprintf(stderr, "Direct3DCreate9 failed\n"); return 1; }
  D3DPRESENT_PARAMETERS pp = {0};
  pp.Windowed = TRUE; pp.SwapEffect = D3DSWAPEFFECT_DISCARD; pp.hDeviceWindow = window;
  pp.BackBufferWidth = 640; pp.BackBufferHeight = 480; pp.BackBufferFormat = D3DFMT_UNKNOWN;
  pp.PresentationInterval = D3DPRESENT_INTERVAL_IMMEDIATE;
  IDirect3DDevice9 *dev = NULL;
  HRESULT r = IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, window,
      D3DCREATE_SOFTWARE_VERTEXPROCESSING | D3DCREATE_FPU_PRESERVE, &pp, &dev);
  if (FAILED(r)) return fail("CreateDevice", r);

  /* One static triangle list, drawn repeatedly under different transforms. */
  const unsigned tri_count = 64;
  IDirect3DVertexBuffer9 *vb = NULL;
  r = IDirect3DDevice9_CreateVertexBuffer(dev, tri_count * 3 * sizeof(struct vertex),
      D3DUSAGE_WRITEONLY, FVF, D3DPOOL_DEFAULT, &vb, NULL);
  if (FAILED(r)) return fail("CreateVertexBuffer", r);
  struct vertex *v = NULL;
  IDirect3DVertexBuffer9_Lock(vb, 0, 0, (void **)&v, 0);
  for (unsigned i = 0; i < tri_count * 3; i++) {
    v[i].x = (float)(i % 3) * 0.01f; v[i].y = (float)((i / 3) % 8) * 0.01f; v[i].z = 0.5f;
    v[i].color = 0xff00ff00 | (i & 0xff);
  }
  IDirect3DVertexBuffer9_Unlock(vb);
  IDirect3DDevice9_SetStreamSource(dev, 0, vb, 0, sizeof(struct vertex));
  IDirect3DDevice9_SetFVF(dev, FVF);
  IDirect3DDevice9_SetRenderState(dev, D3DRS_LIGHTING, FALSE);
  IDirect3DDevice9_SetRenderState(dev, D3DRS_ZENABLE, FALSE);
  D3DMATRIX m; identity(&m);
  IDirect3DDevice9_SetTransform(dev, D3DTS_VIEW, &m);
  IDirect3DDevice9_SetTransform(dev, D3DTS_PROJECTION, &m);

  double total = 0.0, worst = 0.0; unsigned long worst_frame = 0, slow_frames = 0;
  for (unsigned long f = 0; f < frames; f++) {
    double start = now_seconds();
    IDirect3DDevice9_BeginScene(dev);
    for (unsigned long d = 0; d < draws; d++) {
      /* A distinct world matrix per draw makes DXVK rename its fixed-function
       * constant buffer, which is the top stack in the game's loading stall. */
      identity(&m);
      float a = (float)(d + f * draws) * 0.001f;
      m._11 = cosf(a); m._12 = sinf(a); m._21 = -sinf(a); m._22 = cosf(a);
      m._41 = (float)(d % 100) * 0.001f;
      IDirect3DDevice9_SetTransform(dev, D3DTS_WORLD, &m);
      IDirect3DDevice9_DrawPrimitive(dev, D3DPT_TRIANGLELIST, 0, tri_count);
    }
    /* A scene's worth of fresh geometry: create, initialise, draw once, release. */
    for (unsigned long b = 0; b < buffers; b++) {
      IDirect3DIndexBuffer9 *ib = NULL;
      r = IDirect3DDevice9_CreateIndexBuffer(dev, bytes, D3DUSAGE_WRITEONLY, D3DFMT_INDEX16,
                                             D3DPOOL_DEFAULT, &ib, NULL);
      if (FAILED(r)) return fail("CreateIndexBuffer", r);
      WORD *idx = NULL;
      IDirect3DIndexBuffer9_Lock(ib, 0, 0, (void **)&idx, 0);
      for (unsigned long i = 0; i < bytes / 2; i++) idx[i] = (WORD)(i % (tri_count * 3));
      IDirect3DIndexBuffer9_Unlock(ib);
      IDirect3DDevice9_SetIndices(dev, ib);
      IDirect3DDevice9_DrawIndexedPrimitive(dev, D3DPT_TRIANGLELIST, 0, 0, tri_count * 3, 0,
                                            (UINT)((bytes / 2) / 3));
      IDirect3DDevice9_SetIndices(dev, NULL);
      IDirect3DIndexBuffer9_Release(ib);
    }
    IDirect3DDevice9_EndScene(dev);
    IDirect3DDevice9_Present(dev, NULL, NULL, NULL, NULL);
    double elapsed = now_seconds() - start;
    total += elapsed;
    if (elapsed > worst) { worst = elapsed; worst_frame = f; }
    if (elapsed >= 0.25) slow_frames++;
    printf("frame=%lu seconds=%.4f\n", f, elapsed);
    fflush(stdout);
  }
  printf("frames=%lu draws=%lu buffers=%lu bytes=%lu total_s=%.3f avg_ms=%.1f worst_ms=%.1f "
         "worst_frame=%lu slow_frames=%lu\n", frames, draws, buffers, bytes, total,
         total / frames * 1000.0, worst * 1000.0, worst_frame, slow_frames);
  fflush(stdout);
  IDirect3DVertexBuffer9_Release(vb);
  IDirect3DDevice9_Release(dev);
  IDirect3D9_Release(d3d);
  return 0;
}
