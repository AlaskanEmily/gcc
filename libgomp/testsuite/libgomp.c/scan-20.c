/* { dg-require-effective-target size32plus } */
/* { dg-additional-options "-O2 -fopenmp -fdump-tree-vect-details" } */
/* { dg-additional-options "-mavx" { target avx_runtime } } */
/* { dg-final { scan-tree-dump-times "vectorized \[2-6] loops" 2 "vect" { target sse2_runtime } } } */

extern void abort (void);
int r, a[1024], b[1024], x, y, z;

__attribute__((noipa)) void
foo (int *a, int *b)
{
  #pragma omp for simd reduction (inscan, +:r) lastprivate (conditional: z) firstprivate (x) private (y) simdlen(1)
  for (int i = 0; i < 1024; i++)
    {
      { b[i] = r; if ((i & 1) == 0 && i < 937) z = r; }
      #pragma omp scan exclusive(r)
      { y = a[i]; r += y + x + 12; }
    }
}

__attribute__((noipa)) int
bar (void)
{
  int s = 0;
  #pragma omp parallel
  #pragma omp for simd reduction (inscan, +:s) firstprivate (x) private (y) lastprivate (z) if (0)
  for (int i = 0; i < 1024; i++)
    {
      { y = s; b[i] = y + x + 12; }
      #pragma omp scan exclusive(s)
      { y = 2 * a[i]; s += y; z = y; }
    }
  return s;
}

__attribute__((noipa)) void
baz (int *a, int *b)
{
  #pragma omp parallel for simd reduction (inscan, +:r) firstprivate (x) lastprivate (x)
  for (int i = 0; i < 1024; i++)
    {
      b[i] = r;
      #pragma omp scan exclusive(r)
      { r += a[i]; if (i == 1023) x = 29; }
    }
}

__attribute__((noipa)) int
qux (void)
{
  int s = 0;
  #pragma omp parallel for simd reduction (inscan, +:s) lastprivate (conditional: x, y)
  for (int i = 0; i < 1024; i++)
    {
      { b[i] = s; if ((a[i] & 1) == 0 && i < 829) y = a[i]; }
      #pragma omp scan exclusive(s)
      { s += 2 * a[i]; if ((a[i] & 1) == 1 && i < 825) x = a[i]; }
    }
  return s;
}

int
main ()
{
  int s = 0;
  x = -12;
  for (int i = 0; i < 1024; ++i)
    {
      a[i] = i;
      b[i] = -1;
      asm ("" : "+g" (i));
    }
  #pragma omp parallel
  foo (a, b);
  if (r != 1024 * 1023 / 2 || x != -12 || z != b[936])
    abort ();
  for (int i = 0; i < 1024; ++i)
    {
      if (b[i] != s)
	abort ();
      else
	b[i] = 25;
      s += i;
    }
  if (bar () != 1024 * 1023 || x != -12 || z != 2 * 1023)
    abort ();
  s = 0;
  for (int i = 0; i < 1024; ++i)
    {
      if (b[i] != s)
	abort ();
      else
	b[i] = -1;
      s += 2 * i;
    }
  r = 0;
  baz (a, b);
  if (r != 1024 * 1023 / 2 || x != 29)
    abort ();
  s = 0;
  for (int i = 0; i < 1024; ++i)
    {
      if (b[i] != s)
	abort ();
      else
	b[i] = -25;
      s += i;
    }
  if (qux () != 1024 * 1023 || x != 823 || y != 828)
    abort ();
  s = 0;
  for (int i = 0; i < 1024; ++i)
    {
      if (b[i] != s)
	abort ();
      s += 2 * i;
    }
  return 0;
}
