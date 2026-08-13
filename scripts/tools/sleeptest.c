/* Sleep granularity + socket-wait probe for this wine build.
   Answers "Still untested #2" in docs/INWORLD-STALL.md without needing the game. */
#include <windows.h>
#include <stdio.h>
#include <mmsystem.h>

static double ms_since(LARGE_INTEGER a, LARGE_INTEGER b, LARGE_INTEGER f) {
  return (double)(b.QuadPart - a.QuadPart) * 1000.0 / (double)f.QuadPart;
}

static void run(const char *label, int req, int iters) {
  LARGE_INTEGER f, a, b; QueryPerformanceFrequency(&f);
  double tot = 0, mx = 0;
  for (int i = 0; i < iters; i++) {
    QueryPerformanceCounter(&a);
    Sleep(req);
    QueryPerformanceCounter(&b);
    double d = ms_since(a, b, f);
    tot += d; if (d > mx) mx = d;
  }
  printf("%-28s Sleep(%d) x%d: mean %.3f ms  max %.3f ms\n", label, req, iters, tot/iters, mx);
  fflush(stdout);
}

int main(void) {
  run("default timer", 1, 200);
  run("default timer", 0, 200);
  timeBeginPeriod(1);
  run("timeBeginPeriod(1)", 1, 200);
  run("timeBeginPeriod(1)", 0, 200);
  timeEndPeriod(1);

  /* WaitForSingleObject on a never-signalled event: the other coarse-wait path */
  HANDLE ev = CreateEventA(NULL, TRUE, FALSE, NULL);
  LARGE_INTEGER f, a, b; QueryPerformanceFrequency(&f);
  double tot = 0, mx = 0;
  for (int i = 0; i < 200; i++) {
    QueryPerformanceCounter(&a);
    WaitForSingleObject(ev, 1);
    QueryPerformanceCounter(&b);
    double d = ms_since(a, b, f);
    tot += d; if (d > mx) mx = d;
  }
  printf("%-28s Wait(1ms) x200: mean %.3f ms  max %.3f ms\n", "event wait", tot/200, mx);
  return 0;
}
