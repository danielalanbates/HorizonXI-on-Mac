/* A fairer x87 measurement than the first one.
   The earlier loop forced every value through memory as 80-bit (fstpt/fldt), which is the
   single most expensive thing Rosetta has to do. Real 3D code keeps values in the x87 stack
   and works in float/double: 4x4 matrix by vector, over and over, which is what character
   animation and transform actually cost. */
#include <stdio.h>
#include <time.h>

static double now_s(void) {
  struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec / 1e9;
}

static float m[16] = { 1.01f,0.02f,0.03f,0.f, 0.04f,1.05f,0.06f,0.f,
                       0.07f,0.08f,1.09f,0.f, 1.f,2.f,3.f,1.f };

static float transform_many(int n) {
  float x = 1.f, y = 2.f, z = 3.f, acc = 0.f;
  for (int i = 0; i < n; i++) {
    float nx = m[0]*x + m[4]*y + m[8]*z  + m[12];
    float ny = m[1]*x + m[5]*y + m[9]*z  + m[13];
    float nz = m[2]*x + m[6]*y + m[10]*z + m[14];
    float len = nx*nx + ny*ny + nz*nz;
    x = nx / (1.f + len * 1e-9f);
    y = ny / (1.f + len * 1e-9f);
    z = nz / (1.f + len * 1e-9f);
    acc += x + y + z;
  }
  return acc;
}

int main(void) {
  double t = now_s();
  float r = transform_many(20000000);
  printf("20M vertex transforms  %7.3f s   (%.0f Mverts/s)  [%f]\n",
         now_s() - t, 20.0 / (now_s() - t), r);
  return 0;
}
