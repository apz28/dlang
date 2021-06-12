/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2019 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 * A clone from https://github.com/dotnet/corefx
 * tree/master/src/System.Runtime.Numerics/src/System/Numerics
 */

module pham.utl.big_integer_helper;

nothrow @safe:

package(pham.utl):

enum kcbitUint = cast(uint)(uint.sizeof * 8);
enum kcbitUlong = cast(uint)(ulong.sizeof * 8);
enum knMaskHighBit = int.min;
enum kuMaskHighBit = cast(uint)int.min;
//enum decimalScaleFactorMask = cast(int)0x00FF0000;
//enum decimalSignMask = cast(int)0x80000000;

struct BigIntegerHelper
{
    static union DoubleUlong
    {
        ulong uu; // Declare integral first to have zero initialized
        double dbl;
    }

@nogc nothrow pure @safe:

    pragma (inline, true)
    static void getDoubleParts(double dbl, out int sign, out int exp, out ulong man, out bool fFinite)
    {
        DoubleUlong du;
        du.dbl = dbl;

        sign = 1 - (cast(int)(du.uu >> 62) & 2);
        man = du.uu & 0x000FFFFFFFFFFFFF;
        exp = cast(int)(du.uu >> 52) & 0x7FF;
        if (exp == 0)
        {
            // Denormalized number.
            fFinite = true;
            if (man != 0)
                exp = -1074;
        }
        else if (exp == 0x7FF)
        {
            // NaN or Infinite.
            fFinite = false;
            exp = int.max;
        }
        else
        {
            fFinite = true;
            man |= 0x0010000000000000;
            exp -= 1075;
        }
    }

    pragma (inline, true)
    static double getDoubleFromParts(int sign, int exp, ulong man)
    {
        DoubleUlong du;

        if (man == 0)
            du.uu = 0;
        else
        {
            // Normalize so that 0x0010 0000 0000 0000 is the highest bit set.
            const int cbitShift = cbitHighZero(man) - 11;
            if (cbitShift < 0)
                man >>= -cbitShift;
            else
                man <<= cbitShift;
            exp -= cbitShift;
            assert((man & 0xFFF0000000000000) == 0x0010000000000000);

            // Move the point to just behind the leading 1: 0x001.0 0000 0000 0000
            // (52 bits) and skew the exponent (by 0x3FF == 1023).
            exp += 1075;

            if (exp >= 0x7FF)
            {
                // Infinity.
                du.uu = 0x7FF0000000000000;
            }
            else if (exp <= 0)
            {
                // Denormalized.
                exp--;
                if (exp < -52)
                {
                    // Underflow to zero.
                    du.uu = 0;
                }
                else
                {
                    du.uu = man >> -exp;
                    assert(du.uu != 0);
                }
            }
            else
            {
                // Mask off the implicit high bit.
                du.uu = (man & 0x000FFFFFFFFFFFFF) | (cast(ulong)exp << 52);
            }
        }

        if (sign < 0)
            du.uu |= 0x8000000000000000;

        return du.dbl;
    }

    pragma (inline, true)
    static ulong makeUlong(uint uHi, uint uLo)
    {
        return (cast(ulong)uHi << kcbitUint) | uLo;
    }

    pragma (inline, true)
    static uint abs(int a)
    {
        const mask = cast(uint)(a >> 31);
        return (cast(uint)a ^ mask) - mask;
    }

    static if (size_t.sizeof > 4)
    pragma (inline, true)
    static uint combineHash(uint u1, uint u2)
    {
        return ((u1 << 7) | (u1 >> 25)) ^ u2;
    }

    pragma (inline, true)
    static int combineHash(int n1, int n2)
    {
        return cast(int)combineHash(cast(uint)n1, cast(uint)n2);
    }

    pragma (inline, true)
    static size_t combineHash(size_t u1, size_t u2)
    {
        return ((u1 << 7) | (u1 >> 25)) ^ u2;
    }

    pragma (inline, true)
    static int compare(long left, long right)
    {
        return left < right ? -1 : (left > right ? 1 : 0);
    }

    pragma (inline, true)
    static int compare(ulong left, ulong right)
    {
        return left < right ? -1 : (left > right ? 1 : 0);
    }

    static int cbitHighZero(uint u)
    {
        if (u == 0)
            return 32;

        int cbit = 0;
        if ((u & 0xFFFF0000) == 0)
        {
            cbit += 16;
            u <<= 16;
        }
        if ((u & 0xFF000000) == 0)
        {
            cbit += 8;
            u <<= 8;
        }
        if ((u & 0xF0000000) == 0)
        {
            cbit += 4;
            u <<= 4;
        }
        if ((u & 0xC0000000) == 0)
        {
            cbit += 2;
            u <<= 2;
        }
        if ((u & 0x80000000) == 0)
            cbit += 1;
        return cbit;
    }

    pragma (inline, true)
    static int cbitHighZero(ulong uu)
    {
        if ((uu & 0xFFFFFFFF00000000) == 0)
            return 32 + cbitHighZero(cast(uint)uu);
        else
            return cbitHighZero(cast(uint)(uu >> 32));
    }
}
