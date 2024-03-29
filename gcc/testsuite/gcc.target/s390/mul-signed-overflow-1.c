/* { dg-do run } */
/* z14 only because we need msrkc, msc, msgrkc, msgc  */
/* { dg-options "-O3 -march=z14 -mzarch --save-temps" } */

#include <stddef.h>
#include <limits.h>

int __attribute__((noinline,noclone))
smul (int a, int b, int *res)
{
   return __builtin_smul_overflow(a, b, res);
}

int __attribute__((noinline,noclone))
smull (long a, long b, long *res)
{
   return __builtin_smull_overflow(a, b, res);
}

int __attribute__((noinline,noclone))
smulll (long long a, long long b, long long *res)
{
   return __builtin_smulll_overflow(a, b, res);
}


int
main ()
{
  int ret = 0;
  int result;
  long lresult;
  long long llresult;

  ret += !!smul (INT_MAX, 2, &result);
  ret += !!smull (LONG_MAX, 2, &lresult);
  ret += !!smulll (LLONG_MAX, 2, &llresult);

  if (ret != 3)
    __builtin_abort ();

  return 0;
}

/* Check that no compare or bitop instructions are emitted.  */
/* { dg-final { scan-assembler-not "\tcr" } } */
/* { dg-final { scan-assembler-not "\txr" } } */
/* { dg-final { scan-assembler-not "\tnr" } } */
/* { dg-final { scan-assembler-not "\tcgr" } } */
/* { dg-final { scan-assembler-not "\txgr" } } */
/* { dg-final { scan-assembler-not "\tngr" } } */
/* On 31 bit the long long variants use risbgn to merge the 32 bit
   regs into a 64 bit reg.  */
/* { dg-final { scan-assembler-not "\trisbg" { target { lp64 } } } } */
/* Just one for the ret != 3 comparison.  */
/* { dg-final { scan-assembler-times "ci" 1 } } */
