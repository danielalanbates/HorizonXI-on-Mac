/* Does the x87 precision-control field change Rosetta's cost?
   Rosetta must reproduce x87 semantics exactly, and 80-bit extended precision is the expensive
   case. If setting precision control to 24- or 53-bit lets it use a cheaper path, that is a
   knob we can set on FFXI's threads -- d3d9 is documented to set exactly this, so it is also
   behaviour the game already expects. */
#include <stdio.h>
#include <stdint.h>
#include <time.h>

static double now_s(void) {
  struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void set_pc(uint16_t pcBits) {
  uint16_t cw;
  __asm__ __volatile__("fnstcw %0" : "=m" (cw));
  cw = (uint16_t) ((cw & ~0x0300u) | pcBits);   /* PC field is bits 8-9 */
  __asm__ __volatile__("fldcw %0" : : "m" (cw));
}

static double bench_x87(void) {
  volatile long double a = 1.0000001L, s = 0.0L;
  for (int i = 0; i < 20000000; i++)
    s += a * a + s * 0.0000001L;
  return (double) s;
}

int main(void) {
  struct { const char *name; uint16_t bits; } modes[] = {
    { "extended 64-bit (default)", 0x0300 },
    { "double   53-bit",           0x0200 },
    { "single   24-bit",           0x0000 },
  };
  for (int i = 0; i < 3; i++) {
    set_pc(modes[i].bits);
    double t = now_s();
    volatile double r = bench_x87();
    printf("%-26s %7.3f s\n", modes[i].name, now_s() - t);
    (void) r;
  }
  return 0;
}
