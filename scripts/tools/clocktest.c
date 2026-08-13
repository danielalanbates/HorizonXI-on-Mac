/* Clock consistency under this wine.
   FFXI paces itself from the Windows timers. If they disagree with each other, its frame
   limiter computes the wrong delay -- which would cap the frame rate regardless of how fast
   the renderer is, and would explain why no renderer-side change moves the number. */
#include <windows.h>
#include <mmsystem.h>
#include <stdio.h>

int main(void) {
  LARGE_INTEGER f, q0, q1;
  QueryPerformanceFrequency(&f);
  printf("QPC frequency: %lld Hz\n", (long long) f.QuadPart);

  DWORD t0 = timeGetTime(), g0 = GetTickCount();
  QueryPerformanceCounter(&q0);
  Sleep(2000);
  DWORD t1 = timeGetTime(), g1 = GetTickCount();
  QueryPerformanceCounter(&q1);

  double qpcMs = (double)(q1.QuadPart - q0.QuadPart) * 1000.0 / (double) f.QuadPart;
  printf("over one 2000 ms sleep:  QPC %.2f ms | timeGetTime %lu ms | GetTickCount %lu ms\n",
         qpcMs, (unsigned long)(t1 - t0), (unsigned long)(g1 - g0));

  /* Resolution: how often does each clock actually change? */
  DWORD tPrev = timeGetTime(); int tSteps = 0; DWORD tMin = 0xFFFFFFFF;
  LARGE_INTEGER qStart; QueryPerformanceCounter(&qStart);
  for (;;) {
    LARGE_INTEGER now; QueryPerformanceCounter(&now);
    if ((double)(now.QuadPart - qStart.QuadPart) * 1000.0 / (double) f.QuadPart > 500.0) break;
    DWORD t = timeGetTime();
    if (t != tPrev) { if (t - tPrev < tMin) tMin = t - tPrev; tPrev = t; tSteps++; }
  }
  printf("timeGetTime: %d ticks in 500 ms, smallest step %lu ms\n", tSteps, (unsigned long) tMin);
  return 0;
}
