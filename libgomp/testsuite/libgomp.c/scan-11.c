/* { dg-require-effective-target size32plus } */
/* { dg-additional-options "-O2 -fopenmp -fdump-tree-vect-details" } */
/* { dg-additional-options "-mavx" { target avx_runtime } } */
/* { dg-final { scan-tree-dump-times "vectorized \[2-6] loops" 2 "vect" { target sse2_runtime } } } */

extern void abort (void);
int r, a[1024], b[1024];

__attribute__((noipa)) void
foo (int *a, int *b)
{
  #pragma omp for simd reduction (inscan, +:r)
  for (int i = 0; i < 1024; i++)
    {
      r += a[i];
      #pragma omp scan inclusive(r)
      b[i] = r;
    }
}

__attribute__((noipa)) int
bar (void)
{
  int s = 0;
  #pragma omp parallel
  #pragma omp for simd reduction (inscan, +:s) if (0)
  for (int i = 0; i < 1024; i++)
    {
      s += 2 * a[i];
      #pragma omp scan inclusive(s)
      b[i] = s;
    }
  return s;
}

__attribute__((noipa)) void
baz (int *a, int *b)
{
  #pragma omp parallel for simd reduction (inscan, +:r) simdlen(1)
  for (int i = 0; i < 1024; i++)
    {
      r += a[i];
      #pragma omp scan inclusive(r)
      b[i] = r;
    }
}

__attribute__((noipa)) int
qux (void)
{
  int s = 0;
  #pragma omp parallel for simd reduction (inscan, +:s)
  for (int i = 0; i < 1024; i++)
    {
      s += 2 * a[i];
      #pragma omp scan inclusive(s)
      b[i] = s;
    }
  return s;
}

int
main ()
{
  int s = 0;
  for (int i = 0; i < 1024; ++i)
    {
      a[i] = i;
      b[i] = -1;
      asm ("" : "+g" (i));
    }
  #pragma omp parallel
  foo (a, b);
  if (r != 1024 * 1023 / 2)
    abort ();
  for (int i = 0; i < 1024; ++i)
    {
      s += i;
      if (b[i] != s)
	abort ();
      else
	b[i] = 25;
    }
  if (bar () != 1024 * 1023)
    abort ();
  s = 0;
  for (int i = 0; i < 1024; ++i)
    {
      s += 2 * i;
      if (b[i] != s)
	abort ();
      else
	b[i] = -1;
    }
  r = 0;
  baz (a, b);
  if (r != 1024 * 1023 / 2)
    abort ();
  s = 0;
  for (int i = 0; i < 1024; ++i)
    {
      s += i;
      if (b[i] != s)
	abort ();
      else
	b[i] = -25;
    }
  if (qux () != 1024 * 1023)
    abort ();
  s = 0;
  for (int i = 0; i < 1024; ++i)
    {
      s += 2 * i;
      if (b[i] != s)
	abort ();
    }
  return 0;
}
