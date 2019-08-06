/* Any copyright is dedicated to the Public Domain.
 * https://creativecommons.org/publicdomain/zero/1.0/ */

#undef TARGET_OS216
#define TARGET_OS216 1
/*
#undef NO_IMPLICIT_EXTERN_C
#define NO_IMPLICIT_EXTERN_C
*/
#undef TARGET_OS_CPP_BUILTINS
#define TARGET_OS_CPP_BUILTINS() { \
        builtin_define("__os216__"); \
        builtin_define("__sys216__"); \
        builtin_assert("system=os216"); \
        \
    }

/* This is a consequence of supporting COFF/PE */
#undef MAX_OFILE_ALIGNMENT
#define MAX_OFILE_ALIGNMENT 8192

/* All longs are 64-bit on OS216, regardless of architecture */
#undef LONG_TYPE_SIZE
#define LONG_TYPE_SIZE 64

/* size_t would have been set to long if we didn't intervene */
#undef SIZE_TYPE
#define SIZE_TYPE (TARGET_64BIT ? "long unsigned int" : "unsigned int")

/* size_t would have been set to long if we didn't intervene */
#undef PTRDIFF_TYPE
#define PTRDIFF_TYPE (TARGET_64BIT ? "long int" : "int")

/* Default to unsigned chars */
#undef DEFAULT_SIGNED_CHAR
#define DEFAULT_SIGNED_CHAR 0

/* This is in the long tradition of calling C++ from ASM */
#undef TARGET_CXX_CDTOR_RETURN_THIS
#define TARGET_CXX_CDTOR_RETURN_THIS() true

/* libc216 supplies the math library */
#undef MATH_LIBRARY
#define MATH_LIBRARY ""

