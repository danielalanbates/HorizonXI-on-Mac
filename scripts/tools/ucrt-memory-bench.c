/* Compare Wine's 32-bit UCRT memory routines with simple copies under Rosetta.
 *
 * Build on macOS with:
 *   i686-w64-mingw32-gcc -O2 -msse2 -Wall -Wextra -o ucrt-memory-bench.exe \
 *     scripts/tools/ucrt-memory-bench.c
 *
 * Usage:
 *   ucrt-memory-bench.exe METHOD SIZE ITERATIONS [hot|ring|pages]
 */
#include <windows.h>
#include <emmintrin.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void *(__cdecl *copy_fn)(void *, const void *, size_t);
typedef void *(__cdecl *set_fn)(void *, int, size_t);

static double now_seconds(void) {
  LARGE_INTEGER frequency;
  LARGE_INTEGER counter;
  QueryPerformanceFrequency(&frequency);
  QueryPerformanceCounter(&counter);
  return (double)counter.QuadPart / (double)frequency.QuadPart;
}

__attribute__((noinline))
static void *scalar_copy(void *destination, const void *source, size_t size) {
  volatile uint8_t *dst = (volatile uint8_t *)destination;
  const volatile uint8_t *src = (const volatile uint8_t *)source;
  while (size--)
    *dst++ = *src++;
  return destination;
}

__attribute__((noinline))
static void *dword_copy(void *destination, const void *source, size_t size) {
  volatile uint32_t *dst32 = (volatile uint32_t *)destination;
  const volatile uint32_t *src32 = (const volatile uint32_t *)source;
  while (size >= sizeof(uint32_t)) {
    *dst32++ = *src32++;
    size -= sizeof(uint32_t);
  }
  volatile uint8_t *dst8 = (volatile uint8_t *)dst32;
  const volatile uint8_t *src8 = (const volatile uint8_t *)src32;
  while (size--)
    *dst8++ = *src8++;
  return destination;
}

__attribute__((noinline))
static void *rep_copy(void *destination, const void *source, size_t size) {
  void *result = destination;
  __asm__ __volatile__("cld; rep movsb"
                       : "+D"(destination), "+S"(source), "+c"(size)
                       :
                       : "memory");
  return result;
}

__attribute__((noinline))
static void *sse_copy(void *destination, const void *source, size_t size) {
  uint8_t *dst = (uint8_t *)destination;
  const uint8_t *src = (const uint8_t *)source;
  size_t offset = 0;
  while (offset + 16 <= size) {
    __m128i value = _mm_loadu_si128((const __m128i *)(src + offset));
    _mm_storeu_si128((__m128i *)(dst + offset), value);
    offset += 16;
  }
  while (offset < size) {
    dst[offset] = src[offset];
    offset++;
  }
  return destination;
}

__attribute__((noinline))
static void *scalar_set(void *destination, int value, size_t size) {
  volatile uint8_t *dst = (volatile uint8_t *)destination;
  while (size--)
    *dst++ = (uint8_t)value;
  return destination;
}

static size_t parse_size(const char *text) {
  char *end = NULL;
  unsigned long value = strtoul(text, &end, 10);
  if (end == text || *end != '\0' || value == 0)
    return 0;
  return (size_t)value;
}

int main(int argc, char **argv) {
  if (argc < 4 || argc > 5) {
    fprintf(stderr, "usage: %s METHOD SIZE ITERATIONS [hot|ring|pages]\n", argv[0]);
    return 2;
  }

  const char *method = argv[1];
  const size_t size = parse_size(argv[2]);
  const size_t iterations = parse_size(argv[3]);
  const char *pattern = argc == 5 ? argv[4] : "hot";
  if (!size || !iterations) {
    fprintf(stderr, "SIZE and ITERATIONS must be positive integers\n");
    return 2;
  }

  size_t stride = 0;
  if (!strcmp(pattern, "hot"))
    stride = 0;
  else if (!strcmp(pattern, "ring"))
    stride = (size + 255u) & ~(size_t)255u;
  else if (!strcmp(pattern, "pages"))
    stride = 4096;
  else {
    fprintf(stderr, "unknown access pattern: %s\n", pattern);
    return 2;
  }

  const size_t slots = stride ? iterations : 1;
  if (stride && slots > 1 && (slots - 1) > (SIZE_MAX - size) / stride) {
    fprintf(stderr, "allocation size overflow\n");
    return 2;
  }
  const size_t allocation_size = stride
    ? (slots - 1) * stride + size
    : (size < 65536 ? 65536 : size);
  if (allocation_size > 512u * 1024u * 1024u) {
    fprintf(stderr, "benchmark allocation exceeds 512 MiB\n");
    return 2;
  }

  uint8_t *source = VirtualAlloc(NULL, allocation_size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
  uint8_t *destination = VirtualAlloc(NULL, allocation_size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
  if (!source || !destination) {
    fprintf(stderr, "VirtualAlloc failed for %lu bytes\n", (unsigned long)allocation_size);
    return 1;
  }
  for (size_t offset = 0; offset < allocation_size; offset += 4096)
    source[offset] = (uint8_t)(offset >> 12);

  HMODULE ucrt = LoadLibraryA("ucrtbase.dll");
  if (!ucrt) {
    fprintf(stderr, "LoadLibraryA(ucrtbase.dll) failed: %lu\n", GetLastError());
    return 1;
  }
  copy_fn copy = NULL;
  set_fn set = NULL;
  if (!strcmp(method, "ucrt-memmove"))
    copy = (copy_fn)GetProcAddress(ucrt, "memmove");
  else if (!strcmp(method, "ucrt-memcpy"))
    copy = (copy_fn)GetProcAddress(ucrt, "memcpy");
  else if (!strcmp(method, "scalar-copy"))
    copy = scalar_copy;
  else if (!strcmp(method, "dword-copy"))
    copy = dword_copy;
  else if (!strcmp(method, "rep-copy"))
    copy = rep_copy;
  else if (!strcmp(method, "sse-copy"))
    copy = sse_copy;
  else if (!strcmp(method, "ucrt-memset"))
    set = (set_fn)GetProcAddress(ucrt, "memset");
  else if (!strcmp(method, "scalar-set"))
    set = scalar_set;
  else {
    fprintf(stderr, "unknown method: %s\n", method);
    return 2;
  }
  if (!copy && !set) {
    fprintf(stderr, "GetProcAddress failed for %s: %lu\n", method, GetLastError());
    return 1;
  }

  /* Hot mode measures an already translated and resident call. Ring and pages modes leave the
   * destination untouched so their first pass includes page commitment, like a fresh upload
   * allocation. The source is resident in all modes. */
  if (!stride) {
    if (copy)
      copy(destination, source, size);
    else
      set(destination, 0x5a, size);
  }

  const double start = now_seconds();
  for (size_t i = 0; i < iterations; i++) {
    const size_t offset = stride ? i * stride : 0;
    if (copy)
      copy(destination + offset, source + offset, size);
    else
      set(destination + offset, 0x5a, size);
  }
  const double elapsed = now_seconds() - start;
  const double mib = (double)size * (double)iterations / (1024.0 * 1024.0);
  volatile uint8_t checksum = destination[0] ^ destination[allocation_size - 1];
  printf("method=%s pattern=%s size=%lu iterations=%lu mib=%.3f seconds=%.6f mib_per_s=%.3f checksum=%u\n",
         method, pattern, (unsigned long)size, (unsigned long)iterations, mib, elapsed,
         elapsed > 0.0 ? mib / elapsed : 0.0, (unsigned int)checksum);
  fflush(stdout);
  VirtualFree(destination, 0, MEM_RELEASE);
  VirtualFree(source, 0, MEM_RELEASE);
  FreeLibrary(ucrt);
  return 0;
}
