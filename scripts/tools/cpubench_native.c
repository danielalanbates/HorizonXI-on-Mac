/* Translation-cost benchmark.
   FFXI's frame thread was measured burning a full core in its own code, and no change anywhere
   in the graphics stack moved the frame rate. That points at the cost of running its 32-bit
   x86 through translation. This measures that cost directly: the same three workloads compiled
   for 32-bit Windows (run under wine) and for native arm64, so the ratio is the penalty.
   x87 is separated out because a 2002 game engine does its geometry in x87, and 80-bit
   emulation is far more expensive than SSE. */
#include <stdio.h>
#include <stdint.h>
#include <time.h>
#include <stdlib.h>

static double now_s(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec / 1e9;
}

static uint64_t bench_int(void) {
  uint64_t acc = 1;
  for (int i = 0; i < 60000000; i++)
    acc = acc * 6364136223846793005ULL + 1442695040888963407ULL + i;
  return acc;
}

static double bench_x87(void) {
  /* long double forces the x87 stack on 32-bit x86 -- the expensive path to emulate. */
  volatile long double a = 1.0000001L, s = 0.0L;
  for (int i = 0; i < 20000000; i++)
    s += a * a + s * 0.0000001L;
  return (double) s;
}

static double bench_double(void) {
  volatile double a = 1.0000001, s = 0.0;
  for (int i = 0; i < 20000000; i++)
    s += a * a + s * 0.0000001;
  return s;
}

int main(void) {
  double t;
  FILE *out = NULL;
  if (out == NULL) out = stdout;
  t = now_s(); volatile uint64_t r1 = bench_int();    fprintf(out, "int64    %7.3f s\n", now_s() - t);
  t = now_s(); volatile double   r2 = bench_x87();    fprintf(out, "x87/long %7.3f s\n", now_s() - t);
  t = now_s(); volatile double   r3 = bench_double(); fprintf(out, "double   %7.3f s\n", now_s() - t);
  (void) r1; (void) r2; (void) r3;
  fclose(out);
  return 0;
}
