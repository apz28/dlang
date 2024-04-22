module pham.external.dec.dec_numeric;

/* ****************************************************************************************************************** */
/* FLOAT UTILITY FUNCTIONS                                                                                            */
/* ****************************************************************************************************************** */

import pham.external.dec.dec_integral: clz, divrem, uint128;

package(pham.external.dec):

static immutable MAX_FLOAT_COEFFICIENT_34   = uint128(cast(const(ubyte)[])[167, 197, 171, 159, 85, 155, 61, 7, 200, 75, 93, 204, 99, 241]); // uint128("3402823466385288598117041834845169");
enum MAX_FLOAT_EXPONENT_34      = 5;
static immutable MIN_FLOAT_COEFFICIENT_34   = uint128(cast(const(ubyte)[])[69, 22, 223, 138, 22, 254, 99, 213, 183, 26, 180, 153, 54, 60]); // uint128("1401298464324817070923729583289916");
enum MIN_FLOAT_EXPONENT_34      = -78;

static immutable MAX_DOUBLE_COEFFICIENT_34  = uint128(cast(const(ubyte)[])[88, 162, 19, 204, 122, 79, 250, 224, 60, 72, 37, 21, 111, 179]); // uint128("1797693134862315708145274237317043");
enum MAX_DOUBLE_EXPONENT_34     = 275;
static immutable MIN_DOUBLE_COEFFICIENT_34  = uint128(cast(const(ubyte)[])[243, 151, 218, 3, 175, 6, 170, 131, 63, 210, 87, 21, 246, 229]); // uint128("4940656458412465441765687928682213");
enum MIN_DOUBLE_EXPONENT_34     = -357;

static immutable MAX_REAL_COEFFICIENT_34    = uint128(cast(const(ubyte)[])[58, 168, 133, 203, 26, 108, 236, 243, 134, 52, 204, 240, 142, 58]); // uint128("1189731495357231765021263853030970");
enum MAX_REAL_EXPONENT_34       = 4899;
static immutable MIN_REAL_COEFFICIENT_34    = uint128(cast(const(ubyte)[])[179, 184, 226, 237, 169, 26, 35, 45, 217, 80, 16, 41, 120, 219]);   // uint128("3645199531882474602528405933619419");
enum MIN_REAL_EXPONENT_34       = -4984;

version(ShowEnumDecBytes)
unittest
{
    static assert(MAX_FLOAT_COEFFICIENT_34 == uint128("3402823466385288598117041834845169"));
    static assert(MIN_FLOAT_COEFFICIENT_34 == uint128("1401298464324817070923729583289916"));

    static assert(MAX_DOUBLE_COEFFICIENT_34 == uint128("1797693134862315708145274237317043"));
    static assert(MIN_DOUBLE_COEFFICIENT_34 == uint128("4940656458412465441765687928682213"));

    static assert(MAX_REAL_COEFFICIENT_34 == uint128("1189731495357231765021263853030970"));
    static assert(MIN_REAL_COEFFICIENT_34 == uint128("3645199531882474602528405933619419"));
}

version(ShowEnumDecBytes) version(none)
unittest
{
    import std.stdio;
    scope (failure) assert(0, "Assume nothrow failed");

    ubyte[16] b128;

    writeln("MAX_FLOAT_COEFFICIENT_34: ", MAX_FLOAT_COEFFICIENT_34.toBigEndianBytes(b128[]));
    writeln("MIN_FLOAT_COEFFICIENT_34: ", MIN_FLOAT_COEFFICIENT_34.toBigEndianBytes(b128[]));

    writeln("MAX_DOUBLE_COEFFICIENT_34: ", MAX_DOUBLE_COEFFICIENT_34.toBigEndianBytes(b128[]));
    writeln("MIN_DOUBLE_COEFFICIENT_34: ", MIN_DOUBLE_COEFFICIENT_34.toBigEndianBytes(b128[]));

    writeln("MAX_REAL_COEFFICIENT_34: ", MAX_REAL_COEFFICIENT_34.toBigEndianBytes(b128[]));
    writeln("MIN_REAL_COEFFICIENT_34: ", MIN_REAL_COEFFICIENT_34.toBigEndianBytes(b128[]));
}

union FU
{
    uint u;
    float f;
}

@safe pure nothrow @nogc
float fpack(const bool sign, int exp, uint mantissa)
{
    if (mantissa == 0)
        return sign ? -0.0f : +0.0f;

    const shift = clz(mantissa) - 8;
    if (shift < 0)
    {
        if (exp > int.max + shift)
            return sign ? -float.infinity : +float.infinity;
        else
            mantissa >>= -shift;
    }
    else
    {
        if (exp < int.min + shift)
            return sign ? -0.0f : +0.0f;
        mantissa <<= shift;
    }
    exp -= shift;

    if (exp > int.max - 150)
        return sign ? -float.infinity : +float.infinity;
    exp += 150;

    if (exp >= 0xFF)
        return sign ? -float.infinity : +float.infinity;

    if (exp <= 0)
    {
        --exp;
        if (exp < -23)
            return sign ? -0.0f : +0.0f;
        mantissa >>= -exp;
        exp = 0;
    }

    FU fu = void;
    fu.u = (mantissa & 0x7F_FFFF) | (exp << 23);
    if (sign)
        fu.u |= 0x8000_0000U;
    return fu.f;
}

@safe pure nothrow @nogc
bool funpack(const(float) f, out int exp, out uint mantissa, out bool inf, out bool nan)
{
    FU fu = void;
    fu.f = f;

    exp = (fu.u >> 23) & 0xFF;
    mantissa = fu.u & 0x7F_FFFFU;
    if (exp == 0)
    {
        inf = nan = false;
        if (mantissa)
            exp -= 149;
    }
    else if (exp == 0xFF)
    {
        inf = mantissa == 0;
        nan = !inf;
    }
    else
    {
        inf = nan = false;
        mantissa |= 0x0080_0000;
        exp -= 150;
    }

    return (fu.u & 0x8000_0000U) != 0;
}

union DU
{
    ulong u;
    double d;
}

@safe pure nothrow @nogc
double dpack(const(bool) sign, int exp, ulong mantissa)
{
    if (mantissa == 0)
        return sign ? -0.0 : +0.0;

    auto shift = clz(mantissa) - 11;
    if (shift < 0)
    {
        if (exp > int.max + shift)
            return sign ? -double.infinity : +double.infinity;
        else
            mantissa >>= -shift;
    }
    else
    {
        if (exp < int.min + shift)
            return sign ? -0.0 : +0.0;
        mantissa <<= shift;
    }
    exp -= shift;

    if (exp > int.max - 1075)
        return sign ? -double.infinity : +double.infinity;
    exp += 1075;

    if (exp >= 0x7FF)
        return sign ? -double.infinity : +double.infinity;

    if (exp <= 0)
    {
        --exp;
        if (exp < -52)
            return sign ? -0.0 : +0.0;
        mantissa >>= -exp;
        exp = 0;
    }

    DU du = void;
    du.u = (mantissa & 0x000F_FFFF_FFFF_FFFFUL) | (cast(ulong)exp << 52);
    if (sign)
        du.u |= 0x8000_0000_0000_0000UL;
    return du.d;
}

@safe pure nothrow @nogc
bool dunpack(const(double) d, out int exp, out ulong mantissa, out bool inf, out bool nan)
{
    DU du = void;
    du.d = d;

    exp = (du.u >> 52) & 0x07FF;
    mantissa = du.u & 0x0F_FFFF_FFFF_FFFF;

    if (exp == 0)
    {
        inf = nan = false;
        if (mantissa)
            exp -= 1074;
    }
    else if (exp == 0x7FF)
    {
        inf = mantissa == 0;
        nan = !inf;
    }
    else
    {
        inf = nan = false;
        mantissa |= 0x10_0000_0000_0000;
        exp -= 1075;
    }

    return (du.u & 0x8000_0000_0000_0000UL) != 0;
}

union RU
{
    struct
    {   align(1):
        version(LittleEndian)
        {
            ulong m;
            ushort e;
        }
        else
        {
            ushort e;
            ulong m;
        }
    }
    real r;
}
static assert(RU.sizeof == 10);

@safe pure nothrow @nogc
real rpack(const(bool) sign, int exp, ulong mantissa)
{
    if (mantissa == 0)
        return sign ? -0.0L : +0.0L;

    const shift = clz(mantissa);
    if (exp < int.min + shift)
        return sign ? -0.0L : +0.0L;
    mantissa <<= shift;
    exp -= shift;

    if (exp > int.max - 16447) //16383 + 64
        return sign ? -real.infinity : +real.infinity;
    exp += 16447;

    if (exp >= 0x7FFF)
        return sign ? -real.infinity : +real.infinity;

    if (exp <= 0)
    {
        --exp;
        if (exp < -64)
            return sign ? -0.0L : +0.0L;
        mantissa >>= -exp;
        exp = 0;
    }

    RU ru = void;
    ru.m = mantissa;
    ru.e = cast(ushort)exp;
    if (sign)
        ru.e |= 0x8000U;
    return ru.r;
}

@safe pure nothrow @nogc
bool runpack(const(real) r, out int exp, out ulong mantissa, out bool inf, out bool nan)
{
    RU ru = void;
    ru.r = r;

    exp = ru.e & 0x7FFF;
    mantissa = ru.m;

    if (exp == 0)
    {
        inf = nan = false;
        if (mantissa)
            exp -= 16445;
    }
    else if (exp == 0x7FFF)
    {
        inf = (mantissa & 0x7FFF_FFFF_FFFF_FFFF) == 0;
        nan = !inf;
    }
    else
    {
        inf = nan = false;
        exp -= 16446;
    }

    return (ru.e & 0x8000) != 0;
}

version(none)
void floatExtract(float f, out uint coefficient, out int exponent)
{
    // x * 2^n = y * 10^m -> 2^n = n * log2(10)
}

@nogc @safe pure nothrow
bool exp2to10(ref uint coefficient, ref int exponent)
{
    enum maxMultiplicable = uint.max / 5U;

    bool inexact;

    auto e5 = -exponent;

    while (e5 > 0)
    {
        if (!(coefficient & 1U))
        {
            ++exponent;
            --e5;
            coefficient >>>= 1;
        }
        else
        {
            --e5;
            if (coefficient <= maxMultiplicable)
                coefficient *= 5U;
            else
            {
                inexact = true;
                ++exponent;
                coefficient >>>= 1;
            }
        }
    }

    while (e5 < 0)
    {
        if ((coefficient & 0x8000_0000U) != 0x8000_0000U)
        {
            --exponent;
            ++e5;
            coefficient <<= 1;
        }
        else
        {
            ++e5;
            if (coefficient % 5U != 0)
                inexact = true;
            coefficient /= 5U;
        }
    }

    return inexact;
}

@nogc @safe pure nothrow
bool exp2to10(ref ulong coefficient, ref int exponent)
{
    enum maxMultiplicable = ulong.max / 5UL;

    bool inexact;

    auto e5 = -exponent;

    while (e5 > 0)
    {
        if (!(coefficient & 1UL))
        {
            ++exponent;
            --e5;
            coefficient >>>= 1;
        }
        else
        {
            --e5;
            if (coefficient <= maxMultiplicable)
                coefficient *= 5UL;
            else
            {
                inexact = true;
                ++exponent;
                coefficient >>>= 1;
            }
        }
    }

    while (e5 < 0)
    {
        if ((coefficient & 0x8000_0000_0000_0000UL) != 0x8000_0000_0000_0000UL)
        {
            --exponent;
            ++e5;
            coefficient <<= 1;
        }
        else
        {
            ++e5;
            if (coefficient % 5UL != 0)
                inexact = true;
            coefficient /= 5UL;
        }
    }

    return inexact;
}

@nogc @safe pure nothrow
bool exp2to10(ref uint128 coefficient, ref int exponent)
{
    enum maxMultiplicable = uint128.max / 5UL;

    bool inexact;

    auto e5 = -exponent;

    while (e5 > 0)
    {
        if (!(coefficient & 1UL))
        {
            ++exponent;
            --e5;
            coefficient >>>= 1;
        }
        else
        {
            --e5;
            if (coefficient <= maxMultiplicable)
                coefficient *= 5U;
            else
            {
                inexact = true;
                ++exponent;
                coefficient >>>= 1;
            }
        }
    }

    while (e5 < 0)
    {
        if ((coefficient.hi & 0x8000_0000_0000_0000UL) != 0x8000_0000_0000_0000UL)
        {
            --exponent;
            ++e5;
            coefficient <<= 1;
        }
        else
        {
            ++e5;
            if (divrem(coefficient, 5U))
                inexact = true;
        }
    }

    return inexact;
}
