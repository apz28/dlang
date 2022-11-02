module pham.external.dec.math;

import std.traits : isFloatingPoint, isIntegral, isSigned, Unqual, Unsigned;

import pham.external.dec.compare : coefficientApproxEqu, coefficientCmp;
import pham.external.dec.decimal : CommonDecimal, CommonStorage, DataType,
    Decimal, Decimal32, Decimal64, Decimal128,
    ExceptionFlags, FastClass, RoundingMode,
    decimalToDecimal, decimalToSigned,
    copysign, fabs, fastDecode, isDecimal, isLess, isGreater, realFloatPrecision,
    signbit, unsignalize;
import pham.external.dec.integral : cappedAdd, cappedSub, clz, ctz, cvt, divrem,
    isAnyUnsignedBit, makeUnsignedBit, maxmul10, pow10, prec, uint128, unsign,
    xadd, xmul, xsqr, xsub;

 @safe nothrow:
package(pham.external.dec):

 /* ****************************************************************************************************************** */
/* COEFFICIENT ARITHMETIC                                                                                            */
/* ****************************************************************************************************************** */
//divPow10          - inexact
//mulPow10          - overflow
//coefficientAdjust - inexact, overflow, underflow
//coefficientExpand - none
//coefficientShrink - inexact
//coefficientAdd    - inexact, overflow
//coefficientMul    - inexact, overflow, underflow
//coefficientDiv    - inexact, overflow, underflow, div0
//coefficientMod    - inexact, overflow, underflow, invalid
//coefficientFMA    - inexact, overflow, underflow
//coefficientCmp    - none
//coefficientEqu    - none
//coefficientSqr    - inexact, overflow, underflow

ExceptionFlags decimalAdd(D1, D2)(ref D1 x, auto const ref D2 y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    alias T = DataType!D;
    alias T1 = DataType!D1;

    T cx, cy; int ex, ey; bool sx, sy;

    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN)
    {
        x = sx  ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        x = sy && (fx == FastClass.quietNaN ? sx : true) ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
        return ExceptionFlags.none;

    if (fy == FastClass.quietNaN)
    {
        x = sy ? -D1.nan : D1.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.infinite && sx != sy)
        {
            x = D1.nan;
            return ExceptionFlags.invalidOperation;
        }
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        x = sy ? -D1.infinity : D1.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        if (fy == FastClass.zero)
        {
            x = (mode == RoundingMode.towardNegative && sx != sy)  || (sx && sy) ? -D1.zero : D1.zero;
            return ExceptionFlags.none;
        }
        return decimalToDecimal(y, x, precision, mode);
    }

    if (fy == FastClass.zero)
        return ExceptionFlags.none;

    auto flags = coefficientAdd(cx, ex, sx, cy, ey, sy, mode);
    flags = x.adjustedPack(cx, ex, sx, precision, mode, flags);
    if (x.isZero)
        x = (mode == RoundingMode.towardNegative && sx != sy)  || (sx && sy) ? -D1.zero : D1.zero;
    return flags;
}

ExceptionFlags decimalAdd(D, T)(ref D x, auto const ref T y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    alias X = DataType!D;
    U cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!y)
                return ExceptionFlags.none;
            bool sy;
            U cy = unsign!U(y, sy);
            auto flags = coefficientAdd(cx, ex, sx, cy, 0, sy, RoundingMode.implicit);
            flags |= coefficientAdjust(cx, ex, cvt!U(X.max), sx, RoundingMode.implicit);
            return x.adjustedPack(cvt!X(cx), ex, sx, precision, mode, flags);
        case FastClass.zero:
            return x.packIntegral(y, precision, mode);
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalAdd(D, F)(ref D x, auto const ref F y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isFloatingPoint!F)
{
    alias T = CommonStorage!(D, F);
    alias X = DataType!D;

    T cx, cy; int ex, ey; bool sx, sy;
    ExceptionFlags flags;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy, mode, flags);

    if (fx == FastClass.signalingNaN)
    {
        x = sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
        return ExceptionFlags.none;

    if (fy == FastClass.quietNaN)
    {
        x = sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.infinite && sx != sy)
        {
            x = sx ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        }
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        x = sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
        return x.adjustedPack(cy, ey, sy, realFloatPrecision!F(precision), mode, flags);

    if (fy == FastClass.zero)
        return x.adjustedPack(cx, ex, sx, precision, mode, flags);

    flags |= coefficientAdjust(cy, ey, realFloatPrecision!F(0), sy, mode);
    flags |= coefficientAdd(cx, ex, sx, cy, ey, sy, mode);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

ExceptionFlags decimalAdd(T, D)(auto const ref T x, auto const ref D y, out D z, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isIntegral!T)
{
    z = y;
    return decimalAdd(z, x, precision, mode);
}

ExceptionFlags decimalAdd(F, D)(auto const ref F x, auto const ref D y, out D z, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isFloatingPoint!F)
{
    z = y;
    return decimalAdd(z, x, precision, mode);
}

//inexact, overflow, underflow
ExceptionFlags coefficientAdd(T)(ref T cx, ref int ex, ref bool sx, const(T) cy, const(int) ey, const(bool) sy, const(RoundingMode) mode) @safe pure nothrow @nogc
{
    if (!cy)
        return ExceptionFlags.none;

    if (!cx)
    {
        cx = cy;
        ex = ey;
        sx = sy;
        return ExceptionFlags.none;
    }

    Unqual!T cyy = cy;
    int eyy = ey;

    //if cx or cy underflowed, don't propagate
    auto flags = exponentAlign(cx, ex, sx, cyy, eyy, sy, mode) & ~ExceptionFlags.underflow;

    if (!cyy)
    {
        //cx is very big
        switch (mode)
        {
            case RoundingMode.towardPositive:
                if (!sx && !sy)
                    ++cx;
                else if (sx && !sy)
                    --cx;
                break;
            case RoundingMode.towardNegative:
                if (sx && sy)
                    ++cx;
                else if (!sx && sy)
                    --cx;
                break;
            case RoundingMode.towardZero:
                if (sx != sy)
                    --cx;
                break;
            default:
                break;
        }

        //if (sx == sy)
        //{
        //    //cx + 0.0.....001 => cx0000.0....001
        //    if (sx && mode == RoundingMode.towardNegative)
        //        ++cx;
        //    else if (!sx && mode == RoundingMode.towardPositive)
        //        ++cx;
        //}
        //else
        //{
        //    //cx - 0.0.....001 => (cx-1)9999.9...999
        //    if (sx && mode == RoundingMode.towardZero)
        //        --cx;
        //    else if (!sx && mode == RoundingMode.towardNegative)
        //        --cx;
        //}
    }

    if (!cx)
    {
        //cy is very big, cx is tiny
        switch (mode)
        {
            case RoundingMode.towardPositive:
                if (!sx && !sy)
                    ++cyy;
                else if (!sx && sy)
                    --cyy;
                break;
            case RoundingMode.towardNegative:
                if (sx && sy)
                    ++cyy;
                else if (sx && !sy)
                    --cyy;
                break;
            case RoundingMode.towardZero:
                if (sx != sy)
                    --cyy;
                break;
            default:
                break;
        }

        //if (sx == sy)
        //{
        //    //0.0.....001 + cyy => cyy0000.0....001
        //    if (sy && mode == RoundingMode.towardNegative)
        //        ++cyy;
        //    else if (!sy && mode == RoundingMode.towardPositive)
        //        ++cyy;
        //}
        //else
        //{
        //    //0.0.....001 - cyy => -(cyy + 0.0.....001)
        //    if (sy && mode == RoundingMode.towardZero)
        //        --cyy;
        //    else if (!sy && mode == RoundingMode.towardNegative)
        //        --cyy;
        //}
    }

    if (sx == sy)
    {
        Unqual!T savecx = cx;
        const carry = xadd(cx, cyy);
        if (carry)
        {
            if (!cappedAdd(ex, 1))
                return flags | ExceptionFlags.overflow;
            flags |= divpow10(savecx, 1, sx, mode);
            flags |= divpow10(cyy, 1, sy, mode);
            cx = savecx + cyy;
        }
        return flags;
    }
    else
    {
        if (cx == cyy)
        {
            cx = T(0U);
            ex = 0;
            sx = false;
            return flags;
        }

        if (cx > cyy)
            cx -= cyy;
        else
        {
            cx = cyy - cx;
            sx = sy;
        }
        return flags;
    }
}

ExceptionFlags decimalAdjust(D)(ref D x, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            return x.adjustedPack(cx, ex, sx, precision, mode, ExceptionFlags.none);
        case FastClass.zero:
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalAcos(D)(ref D x, const(int) precision, const(RoundingMode) mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (isLess(x, -D.one) || isGreater(x, D.one))
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
    {
        x = D.PI_2;
        return decimalAdjust(x, precision, mode);
    }

    if (x == -D.one)
    {
        x = D.PI;
        return decimalAdjust(x, precision, mode);
    }

    if (x == D.one)
    {
        x = D.zero;
        return ExceptionFlags.none;
    }

    if (x == -D.SQRT3_2)
    {
        x = D._5PI_6;
        return ExceptionFlags.none;
    }

    if (x == -D.SQRT2_2)
    {
        x = D._3PI_4;
        return ExceptionFlags.none;
    }

    if (x == -D.half)
    {
        x  = D._2PI_3;
        return ExceptionFlags.none;
    }

    if (x == D.half)
    {
        x  = D.PI_2;
        return ExceptionFlags.none;
    }

    if (x == D.SQRT2_2)
    {
        x = D.PI_4;
        return ExceptionFlags.none;
    }

    if (x == D.SQRT3_2)
    {
        x = D.PI_6;
        return ExceptionFlags.none;
    }

    Unqual!D x2 = x;
    auto flags = decimalSqr(x2, 0, mode);
    x2 = -x2;
    flags |= decimalAdd(x2, 1U, 0, mode);
    flags |= decimalSqrt(x2, 0, mode);
    flags |= decimalAdd(x, 1U, 0, mode);
    flags |= decimalDiv(x2, x, 0, mode);
    x = x2;
    flags |= decimalAtan(x, 0, mode);
    flags |= decimalMul(x, 2U, precision, mode);
    return flags;
}

ExceptionFlags decimalAcosh(D)(ref D x, const(int) precision, const(RoundingMode) mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (isLess(x, D.one))
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x == D.one)
    {
        x = D.zero;
        return ExceptionFlags.none;
    }

    if (x.isInfinity)
        return ExceptionFlags.none;

    /*
        ln(x+sqrt(x*x - 1))
        for very big x: (ln(x + x) = ln(2) + ln(x), otherwise will overflow
    */

    //sqrt(D.max)/2
    static if (is(D: Decimal32))
    {
        enum acoshmax = Decimal32("1.581138e51");
    }
    else static if (is(D: Decimal64))
    {
        enum acoshmax = Decimal64("1.581138830084189e192");
    }
    else
    {
        enum acoshmax = Decimal128("1.581138830084189665999446772216359e3072");
    }

    ExceptionFlags flags;
    if (isGreater(x, acoshmax))
    {
        flags = decimalLog(x, 0, mode) | ExceptionFlags.inexact;
        flags |= decimalAdd(x, D.LN2, precision, mode);
        return flags;
    }
    else
    {
        Unqual!D x1 = x;
        flags = decimalSqr(x1, 0, mode);
        flags |= decimalSub(x1, 1U, 0, mode);
        flags |= decimalSqrt(x1, 0, mode);
        flags |= decimalAdd(x, x1, 0, mode);
        flags |= decimalLog(x, precision, mode);
        return flags;
    }
}

ExceptionFlags decimalAsin(D)(ref D x, const(int) precision, const(RoundingMode) mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (isLess(x, -D.one) || isGreater(x, D.one))
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
        return ExceptionFlags.none;

    if (x == -D.one)
    {
        x = -D.PI_2;
        return decimalAdjust(x, precision, mode);
    }

    if (x == D.one)
    {
        x = D.PI_2;
        return ExceptionFlags.none;
    }

    if (x == -D.SQRT3_2)
    {
        x = -D.PI_3;
        return ExceptionFlags.none;
    }

    if (x == -D.SQRT2_2)
    {
        x = -D.PI_4;
        return ExceptionFlags.none;
    }

    if (x == -D.half)
    {
        x  = -D.PI_6;
        return ExceptionFlags.none;
    }

    if (x == D.half)
    {
        x  = D.PI_6;
        return ExceptionFlags.none;
    }

    if (x == D.SQRT2_2)
    {
        x = D.PI_4;
        return ExceptionFlags.none;
    }

    if (x == D.SQRT3_2)
    {
        x = D.PI_6;
        return ExceptionFlags.none;
    }

    //asin(x) = 2 * atan(x / ( 1 + sqrt(1 - x* x))
    Unqual!D x2 = x;
    auto flags = decimalSqr(x2, 0, mode);
    x2 = -x2;
    flags |= decimalAdd(x2, 1U, 0, mode);
    flags |= decimalSqrt(x2, 0, mode);
    flags |= decimalAdd(x2, 1U, 0, mode);
    flags |= decimalDiv(x, x2, 0, mode);
    flags |= decimalAtan(x, 0, mode);
    flags |= decimalMul(x, 2U, precision, mode);
    return flags;
}

ExceptionFlags decimalAsinh(D)(ref D x, const(int) precision, const(RoundingMode) mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN || x.isZero || x.isInfinity)
        return ExceptionFlags.none;

    //+- ln(|x| + sqrt(x*x + 1))
    //+-[ln(2) + ln(|x|)] for very big x,

    //sqrt(D.max)/2
    static if (is(D: Decimal32))
    {
        enum asinhmax = Decimal32("1.581138e51");
    }
    else static if (is(D: Decimal64))
    {
        enum asinhmax = Decimal64("1.581138830084189e192");
    }
    else
    {
        enum asinhmax = Decimal128("1.581138830084189665999446772216359e3072");
    }

    bool sx = cast(bool)signbit(x);
    x = fabs(x);

    ExceptionFlags flags;
    if (isGreater(x, asinhmax))
    {
        flags = decimalLog(x, 0, mode) | ExceptionFlags.inexact;
        flags |= decimalAdd(x, D.LN2, 0, mode);
    }
    else
    {
        Unqual!D x1 = x;
        flags = decimalSqr(x1, 0, mode);
        flags |= decimalAdd(x1, 1U, 0, mode);
        flags |= decimalSqrt(x1, 0, mode);
        flags |= decimalAdd(x, x1, 0, mode);
        flags |= decimalLog(x, 0, mode);
    }

    if (sx)
        x = -x;
    flags |= decimalAdjust(x, precision, mode);
    return flags;
}

ExceptionFlags decimalAtan(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    switch (fastDecode(x, cx, ex, sx))
    {
        case FastClass.signalingNaN:
            return ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
        case FastClass.zero:
            return ExceptionFlags.none;
        case FastClass.infinite:
            x = signbit(x) ? -D.PI_2 : D.PI_2;
            return decimalAdjust(x, precision, mode);
        default:
            DataType!D reductions;
            coefficientCapAtan(cx, ex, sx, reductions);
            auto flags = coefficientAtan(cx, ex, sx);
            if (reductions)
            {
                flags |= coefficientMul(cx, ex, sx, reductions, 0, false, RoundingMode.implicit);
                flags |= coefficientMul(cx, ex, sx, DataType!D(2U), 0, false, RoundingMode.implicit);
            }
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
    }
}

ExceptionFlags coefficientAtan(T)(ref T cx, ref int ex, bool sx) @safe pure nothrow @nogc
{
    //taylor series:
    //atan(x) = x - x^3/3 + x^5/5 - x^7/7 ...

    Unqual!T cx2 = cx; int ex2 = ex;
    coefficientSqr(cx2, ex2, RoundingMode.implicit);

    Unqual!T cy; int ey; bool sy;
    Unqual!T cxx = cx; int exx = ex; bool sxx = sx;
    Unqual!T n = 3U;

    do
    {
        cy = cx;
        ey = ex;
        sy = sx;

        coefficientMul(cxx, exx, sxx, cx2, ex2, true, RoundingMode.implicit);

        Unqual!T cf = cxx;
        int ef = exx;
        bool sf = sxx;

        coefficientDiv(cf, ef, sf, n, 0, false, RoundingMode.implicit);
        coefficientAdd(cx, ex, sx, cf, ef, sf, RoundingMode.implicit);
        n += 2U;
    }
    while (!coefficientApproxEqu(cx, ex, sx, cy, ey, sy));
    return ExceptionFlags.inexact;
}

ExceptionFlags coefficientCapAtan(T)(ref T cx, ref int ex, ref bool sx, out T reductions) @safe pure nothrow @nogc
{
    //half angle formula: atan(x/2) = 2 * atan(x/(1 + sqrt(1 +x^^2))))
    //reduce x = x / (sqrt(x * x + 1) + 1);

    reductions = 0U;
    while (coefficientCmp(cx, ex, T(1U), 0) >= 0)
    {
        Unqual!T cy = cx; int ey = ex; bool sy = false;
        coefficientSqr(cy, ey, RoundingMode.implicit);
        coefficientAdd(cy, ey, sy, T(1U), 0, false, RoundingMode.implicit);
        coefficientSqrt(cy, ey);
        coefficientAdd(cy, ey, sy, T(1U), 0, false, RoundingMode.implicit);
        coefficientDiv(cx, ex, sx, cy, ey, false, RoundingMode.implicit);
        ++reductions;
    }

    return ExceptionFlags.inexact;
}

ExceptionFlags decimalAtanh(D)(ref D x, const(int) precision, const(RoundingMode) mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN || x.isZero)
        return ExceptionFlags.none;

    alias T = DataType!D;
    T cx = void;
    int ex = void;
    bool sx = x.unpack(cx, ex);

    const cmp = coefficientCmp(cx, ex, false, T(1U), 0, false);

    if (cmp > 0)
    {
        x = signbit(x) ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (cmp == 0)
    {
        x = signbit(x) ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    const flags = coefficientAtanh(cx, ex, sx);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

ExceptionFlags coefficientAtanh(T)(ref T cx, ref int ex, ref bool sx) @safe pure nothrow @nogc
{
    //1/2*ln[(1 + x)/(1 - x)]

    assert(coefficientCmp(cx, ex, sx, T(1U), 0, true) > 0);
    assert(coefficientCmp(cx, ex, sx, T(1U), 0, false) < 0);

    //1/2*ln[(1 + x)/(1 - x)]

    Unqual!T cm1 = cx;
    int em1 = ex;
    bool sm1 = !sx;
    coefficientAdd(cm1, em1, sm1, T(1U), 0, false, RoundingMode.implicit);
    coefficientAdd(cx, ex, sx, T(1U), 0, false, RoundingMode.implicit);
    coefficientDiv(cx, ex, sx, cm1, em1, sm1, RoundingMode.implicit);
    coefficientLog(cx, ex, sx);
    coefficientMul(cx, ex, sx, T(5U), -1, false, RoundingMode.implicit);
    return ExceptionFlags.inexact;
}

ExceptionFlags decimalAtanPi(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN || x.isZero)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? -D.half : D.half;
        return ExceptionFlags.none;
    }

    const bool sx = cast(bool)signbit(x);
    x = fabs(x);

    //if (decimalEqu(x, D.SQRT3))
    //{
    //    x = sx ? -D.onethird : D.onethird;
    //    return ExceptionFlags.none;
    //}
    //
    //if (decimalEqu(x, D.one))
    //{
    //    x = sx ? -D.quarter : D.quarter;
    //    return ExceptionFlags.none;
    //}
    //
    //if (decimalEqu(x, D.M_SQRT3))
    //{
    //    x = sx ? -D._1_6 : D._1_6;
    //    return ExceptionFlags.none;
    //}

    auto flags = decimalAtan(x, 0, mode);
    flags |= decimalDiv(x, D.PI, precision, mode);
    return flags;
}

ExceptionFlags decimalAtan2(D1, D2, D3)(auto const ref D1 y, auto const ref D2 x, out D3 z, const(int) precision, const(RoundingMode) mode)
{
    alias D = CommonDecimal!(D1, D2);

    if (x.isSignalNaN || y.isSignalNaN)
    {
        z = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN || y.isNaN)
    {
        z = D.nan;
        return ExceptionFlags.none;
    }

    if (y.isZero)
    {
        if (signbit(x))
            z = signbit(y) ? -D.PI : D.PI;
        else
            z = signbit(y) ? -D.zero : D.zero;
        return ExceptionFlags.inexact;
    }

    if (x.isZero)
    {
        z = signbit(y) ? -D.PI_2 : D.PI_2;
        return ExceptionFlags.inexact;
    }

    if (y.isInfinity)
    {
        if (x.isInfinity)
        {
            if (signbit(x))
                z = signbit(y) ? -D._3PI_4 : D._3PI_4;
            else
                z = signbit(y) ? -D.PI_4 : D.PI_4;
        }
        else
            z = signbit(y) ? -D.PI_2 : D.PI_2;
        return ExceptionFlags.inexact;
    }

    if (x.isInfinity)
    {
        if (signbit(x))
            z = signbit(y) ? -D.PI : D.PI;
        else
            z = signbit(y) ? -D.zero : D.zero;
        return ExceptionFlags.inexact;
    }

    z = y;
    D xx = x;
    auto flags = decimalDiv(z, xx, 0, mode);
    z = fabs(z);
    flags |= decimalAtan(z, 0, mode);

    if (signbit(x))
    {
        z = -z;
        flags |= decimalAdd(z, D.PI, precision, mode);
        return flags & ExceptionFlags.inexact;
    }
    else
    {
        flags |= decimalAdjust(z, precision, mode);
        return flags & (ExceptionFlags.inexact | ExceptionFlags.underflow);
    }
}

ExceptionFlags decimalAtan2Pi(D1, D2, D3)(auto const ref D1 y, auto const ref D2 x, out D3 z,
    const(int) precision, const(RoundingMode) mode)
if (isDecimal!(D1, D2, D3))
{
    alias D = CommonDecimal!(D1, D2);

    if (x.isSignalNaN || y.isSignalNaN)
    {
        z = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN || y.isNaN)
    {
        z = D.nan;
        return ExceptionFlags.none;
    }

    if (y.isZero)
    {
        if (signbit(x))
            z = signbit(y) ? -D.one : D.one;
        else
            z = signbit(y) ? -D.zero : D.zero;
        return ExceptionFlags.inexact;
    }

    if (x.isZero)
    {
        z = signbit(y) ? -D.half : D.half;
        return ExceptionFlags.inexact;
    }

    if (y.isInfinity)
    {
        if (x.isInfinity)
        {
            if (signbit(x))
                z = signbit(y) ? -D.threequarters : D.threequarters;
            else
                z = signbit(y) ? -D.quarter : D.quarter;
        }
        else
            z = signbit(y) ? -D.half : D.half;
        return ExceptionFlags.inexact;
    }

    if (x.isInfinity)
    {
        if (signbit(x))
            z = signbit(y) ? -D.one : D.one;
        else
            z = signbit(y) ? -D.zero : D.zero;
        return ExceptionFlags.inexact;
    }

    auto flags = decimalAtan2(y, x, z, 0, mode);
    flags |= decimalDiv(z, D.PI, precision, mode);
    return flags;
}

ExceptionFlags decimalCbrt(D)(ref D x, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            const flags = coefficientCbrt(cx, ex);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags coefficientCbrt(T)(ref T cx, ref int ex) @safe pure nothrow @nogc
{
    // Newton-Raphson: x = (2x + N/x2)/3

    if (!cx)
    {
        cx = 0U;
        ex = 0;
        return ExceptionFlags.none;
    }

    alias U = makeUnsignedBit!(T.sizeof * 16);

    U cxx = cx;
    ExceptionFlags flags;

    //we need full precision
    coefficientExpand(cxx, ex);

    const r = ex % 3;
    if (r)
    {
        //exponent is not divisible by 3, make it
        flags = divpow10(cxx, 3 - r, false, RoundingMode.implicit);
        ex += 3 - r;
    }

    ex /= 3;
    import pham.external.dec.integral : cbrtIntegral = cbrt;
    const bool inexact = cbrtIntegral(cxx);
    flags |= coefficientAdjust(cxx, ex, cvt!U(T.max), false, RoundingMode.implicit);
    cx = cast(T)cxx;
    return inexact ? flags | ExceptionFlags.inexact : flags;
}

ExceptionFlags decimalCompound(D)(ref D x, const(int) n, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (isLess(x, -D.one))
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (n == 0)
    {
        x = D.one;
        return ExceptionFlags.none;
    }

    if (x == -1 && n < 0)
    {
        x = D.infinity;
        return ExceptionFlags.divisionByZero;
    }

    if (x == -1)
    {
        x = D.zero;
        return ExceptionFlags.none;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        if (signbit(x))
            x = n & 1 ? -D.infinity : D.infinity;
        else
            x = D.infinity;
        return ExceptionFlags.none;
    }

    Unqual!D y = x;
    auto flags = decimalAdd(x, 1U, 0, mode);
    if ((flags & ExceptionFlags.overflow) && n < 0)
    {
        x = y;
        flags &= ~ExceptionFlags.overflow;
    }

    if (flags & ExceptionFlags.overflow)
        return flags;

    flags |= decimalPow(x, n, precision, mode);
    return flags;
}

ExceptionFlags decimalCos(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.signalingNaN:
            return ExceptionFlags.invalidOperation;
        case FastClass.infinite:
            x = sx ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.zero:
            x = D.one;
            return ExceptionFlags.none;
        default:
            int quadrant;
            auto flags = coefficientCapAngle(cx, ex, sx, quadrant);
            switch (quadrant)
            {
                case 1:
                    flags |= coefficientCosQ(cx, ex, sx);
                    break;
                case 2:
                    flags |= coefficientSinQ(cx, ex, sx);
                    sx = !sx;
                    break;
                case 3:
                    flags |= coefficientCosQ(cx, ex, sx);
                    sx = !sx;
                    break;
                case 4:
                    flags |= coefficientSinQ(cx, ex, sx);
                    break;
                default:
                    assert(0);
            }
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
    }
}

ExceptionFlags decimalCosh(D)(ref D x, const(int) precision, const(RoundingMode) mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = D.infinity;
        return ExceptionFlags.none;
    }

    if (x.isZero)
    {
        x = D.one;
        return ExceptionFlags.none;
    }

    Unqual!D x1 = x;
    Unqual!D x2 = -x;
    auto flags = decimalExp(x1, 0, mode);
    flags |= decimalExp(x2, 0, mode);
    flags |= decimalAdd(x1, x2, 0, mode);
    x = x1;
    flags |= decimalMul(x, D.half, precision, mode);
    return flags;
}

version (none) // Missing decimalReduceAngle
ExceptionFlags decimalCosPi(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (x.isSignalNaN || x.isInfinity)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    decimalReduceAngle(x);

    auto flags = decimalMul(x, D.PI, 0, mode);
    flags |= decimalCos(x, precision, mode);
    return flags;
}

ExceptionFlags coefficientCosQ(T)(ref T cx, ref int ex, ref bool sx) @safe pure nothrow @nogc
{
    //taylor series: cos(x) = 1 - x^2/2! + x^4/4! - x^6/6! ...

    Unqual!T cx2 = cx; int ex2 = ex; bool sx2 = true;
    coefficientSqr(cx2, ex2, RoundingMode.implicit);

    cx = 1U;
    ex = 0;
    sx = false;
    Unqual!T cy; int ey; bool sy;
    Unqual!T cf = cx; int ef = ex; bool sf = sx;
    Unqual!T n = 1U;

    do
    {
        cy = cx;
        ey = ex;
        sy = sx;

        coefficientMul(cf, ef, sf, cx2, ex2, sx2, RoundingMode.implicit);
        coefficientDiv(cf, ef, sf, n++, 0, false, RoundingMode.implicit);
        coefficientDiv(cf, ef, sf, n++, 0, false, RoundingMode.implicit);
        coefficientAdd(cx, ex, sx, cf, ef, sf, RoundingMode.implicit);
        //writefln("%10d %10d %10d %10d", cx, ex, cy, ey);
    }
    while (!coefficientApproxEqu(cx, ex, sx, cy, ey, sy));
    return ExceptionFlags.inexact;
}

ExceptionFlags decimalDec(D)(ref D x, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            const flags = coefficientAdd(cx, ex, sx, DataType!D(1U), 0, true, RoundingMode.implicit);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
            x = -D.one;
            return ExceptionFlags.none;
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalDiv(D1, D2)(ref D1 x, auto const ref D2 y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    alias T = DataType!D;
    alias T1 = DataType!D1;

    T cx, cy; int ex, ey; bool sx, sy;

    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN || fy == FastClass.signalingNaN)
    {
        x = sx ^ sy ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN)
    {
        x = sx ^ sy ? -D1.nan : D1.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.infinite)
        {
            x = sx ^ sy ? -D1.nan : D1.nan;
            return ExceptionFlags.invalidOperation;
        }
        x = sx ^ sy ? -D1.infinity : D1.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        if (fy == FastClass.zero)
        {
            x = sx ^ sy ? -D1.nan : D1.nan;
            return ExceptionFlags.invalidOperation;
        }

        x = sx ^ sy ? -D1.zero : D1.zero;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        x = sx ^ sy ? -D1.zero : D1.zero;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        x = sx ^ sy ? -D1.infinity : D1.infinity;
        return ExceptionFlags.divisionByZero;
    }

    auto flags = coefficientDiv(cx, ex, sx, cy, ey, sy, RoundingMode.implicit);
    flags |= coefficientAdjust(cx, ex, cvt!T(T1.max), sx, RoundingMode.implicit);
    return x.adjustedPack(cvt!T1(cx), ex, sx, precision, mode, flags);
}

ExceptionFlags decimalDiv(D, T)(ref D x, auto const ref T y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    U cx; int ex; bool sx; bool sy;
    U cy = unsign!U(y, sy);
    final switch (fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!y)
            {
                x = sx ^ sy ? -D.infinity : D.infinity;
                return ExceptionFlags.divisionByZero;
            }
            const flags = coefficientDiv(cx, ex, sx, cy, 0, sy, mode);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
            x = sx ^ sy ? -D.zero : D.zero;
            return ExceptionFlags.none;
        case FastClass.infinite:
            if (!y)
            {
                x = sx ^ sy ? -D.nan : D.nan;
                return ExceptionFlags.invalidOperation | ExceptionFlags.divisionByZero;
            }
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalDiv(T, D)(auto const ref T x, auto const ref D y, out D z, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    U cy; int ey; bool sy; int ex = 0; bool sx;
    U cx = unsign!U(x, sx);
    final switch (fastDecode(y, cy, ey, sy))
    {
        case FastClass.finite:
            auto flags = coefficientDiv(cx, ex, sx, cy, 0, sy, RoundingMode.implicit);
            flags |= coefficientAdjust(cx, ex, cvt!U(DataType!D.max), sx, RoundingMode.implicit);
            return z.adjustedPack(cvt!(DataType!D)(cx), ex, sx, precision, mode, flags);
        case FastClass.zero:
            z = sx ^ sy ? -D.infinity : D.infinity;
            return ExceptionFlags.divisionByZero;
        case FastClass.infinite:
            z = y;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            z = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            z = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalDiv(D, F)(ref D x, auto const ref F y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isFloatingPoint!F)
{
    alias T = CommonStorage!(D, F);

    T cx, cy; int ex, ey; bool sx, sy;

    ExceptionFlags flags;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy, mode, flags);

    if (fx == FastClass.signalingNaN)
    {
        x = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN)
    {
        x = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.zero)
        {
            x = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation | ExceptionFlags.divisionByZero;
        }

        if (fy == FastClass.infinite)
        {
            x = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        }
        x = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        x = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        x = sx ^ sy ? -D.zero : D.zero;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        x = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.divisionByZero;
    }

    flags |= coefficientAdjust(cy, ey, realFloatPrecision!F(0), sy, mode);
    flags |= coefficientDiv(cx, ex, sx, cy, ey, sy, mode);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

ExceptionFlags decimalDiv(F, D)(auto const ref F x, auto const ref D y, out D z, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isFloatingPoint!F)
{
    alias T = CommonStorage!(D, F);

    T cx, cy; int ex, ey; bool sx, sy;
    ExceptionFlags flags;
    const fx = fastDecode(x, cx, ex, sx, mode, flags);
    const fy = fastDecode(y, cy, ey, sy);

    if (fy == FastClass.signalingNaN)
    {
        z = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN)
    {
        z = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.zero)
        {
            z = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation | ExceptionFlags.divisionByZero;
        }

        if (fy == FastClass.infinite)
        {
            z = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        }
        z = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        z = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        z = sx ^ sy ? -D.zero : D.zero;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        z = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.divisionByZero;
    }
    flags |= coefficientAdjust(cx, ex, realFloatPrecision!F(0), sx, mode);
    flags |= coefficientDiv(cx, ex, sx, cy, ey, sy, mode);
    return z.adjustedPack(cx, ex, sx, precision, mode, flags);
}

//div0, overflow, underflow
ExceptionFlags coefficientDiv(T)(ref T cx, ref int ex, ref bool sx, const(T) cy, const(int) ey, const(bool) sy, const(RoundingMode) mode) @safe pure nothrow @nogc
{
    if (!cy)
    {
        sx ^= sy;
        return ExceptionFlags.divisionByZero;
    }

    if (!cx)
    {
        ex = 0;
        sx ^= sy;
        return ExceptionFlags.none;
    }

    if (cy == 1U)
    {
        if (cappedSub(ex, ey) != ey)
            return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
        sx ^= sy;
        return ExceptionFlags.none;
    }

    Unqual!T savecx = cx;
    sx ^= sy;
    auto r = divrem(cx, cy);
    if (!r)
    {
        if (cappedSub(ex, ey) != ey)
           return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
        return ExceptionFlags.none;
    }

    alias U = makeUnsignedBit!(T.sizeof * 16);
    U cxx = savecx;
    const px = prec(savecx);
    const pm = prec(U.max) - 1;
    mulpow10(cxx, pm - px);
    const scale = pm - px - cappedSub(ex, pm - px);
    auto s = divrem(cxx, cy);
    ExceptionFlags flags;
    if (s)
    {
        const half = cy >>> 1;
        final switch (mode)
        {
            case RoundingMode.tiesToEven:
                if (s > half)
                    ++cxx;
                else if ((s == half) && ((cxx & 1U) == 0U))
                    ++cxx;
                break;
            case RoundingMode.tiesToAway:
                if (s >= half)
                    ++cxx;
                break;
            case RoundingMode.towardNegative:
                if (sx)
                    ++cxx;
                break;
            case RoundingMode.towardPositive:
                if (!sx)
                    ++cxx;
                break;
            case RoundingMode.towardZero:
                break;
        }
        flags = ExceptionFlags.inexact;
    }

    flags |= coefficientAdjust(cxx, ex, U(T.max), sx, mode);

    if (flags & ExceptionFlags.underflow)
    {
        cx = 0U;
        ex = 0U;
        return flags;
    }

    if (flags & ExceptionFlags.overflow)
        return flags;

    cx = cast(T)cxx;
    if (cappedSub(ex, ey) != ey)
        flags |= ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
    if (cappedSub(ex, scale) != scale)
        flags |= ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;

    return flags;
}

ExceptionFlags decimalDot(D)(const(D)[] x, const(D)[] y, out D result, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    const len = x.length > y.length ? y.length : x.length;

    bool hasPositiveInfinity, hasNegativeInfinity;

    alias T = makeUnsignedBit!(D.sizeof * 16);
    DataType!D cx, cy;
    T cxx, cyy, cr;
    int ex, ey, er;
    bool sx, sy, sr;

    size_t i = 0;
    while (i < len)
    {
        if (x[i].isSignalNaN || y[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN || y[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (y[i].isZero)
            {
                result = D.nan;
                return ExceptionFlags.invalidOperation;
            }

            if (y[i].isInfinity)
            {
                if (signbit(x[i]) ^ signbit(y[i]))
                    hasNegativeInfinity = true;
                else
                    hasPositiveInfinity = true;
            }
            else
            {
                if (signbit(x[i]))
                    hasNegativeInfinity = true;
                else
                    hasPositiveInfinity = true;
            }
            ++i;
            break;
        }

        if (y[i].isInfinity)
        {
            if (x[i].isZero)
            {
                result = D.nan;
                return ExceptionFlags.invalidOperation;
            }

            if (signbit(y[i]))
                hasNegativeInfinity = true;
            else
                hasPositiveInfinity = true;

            ++i;
            break;
        }

        if (x[i].isZero || y[i].isZero)
        {
            ++i;
            continue;
        }

        sx = x[i].unpack(cx, ex);
        sy = y[i].unpack(cy, ey);
        cxx = cx; cyy = cy;
        flags |= coefficientMul(cx, ex, sx, cy, ey, sy, mode);
        flags |= coefficientAdd(cr, er, sr, cx, ex, sx, mode);
        ++i;
        if (flags & ExceptionFlags.overflow)
            break;
    }

    while (i < len)
    {
        if (x[i].isSignalNaN || y[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN || y[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (y[i].isZero)
            {
                result = D.nan;
                return ExceptionFlags.invalidOperation;
            }

            if (y[i].isInfinity)
            {
                if (signbit(x[i]) ^ signbit(y[i]))
                    hasNegativeInfinity = true;
                else
                    hasPositiveInfinity = true;
            }
            else
            {
                if (signbit(x[i]))
                    hasNegativeInfinity = true;
                else
                    hasPositiveInfinity = true;
            }
        }

        if (y[i].isInfinity)
        {
            if (x[i].isZero)
            {
                result = D.nan;
                return ExceptionFlags.invalidOperation;
            }

            if (signbit(y[i]))
                hasNegativeInfinity = true;
            else
                hasPositiveInfinity = true;
        }

        ++i;
    }

    if (hasPositiveInfinity)
    {
        if (hasNegativeInfinity)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }
        result = D.infinity;
        return ExceptionFlags.none;
    }

    if (hasNegativeInfinity)
    {
        result = -D.infinity;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalExp(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
    {
        x = D.one;
        return ExceptionFlags.none;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? D.zero : D.infinity;
        return ExceptionFlags.none;
    }

    long n;
    const flags = decimalToSigned(x, n, mode);
    if (flags == ExceptionFlags.none)
    {
        x = D.E;
        return decimalPow(x, n, precision, mode);
    }

    static if (is(D : Decimal32))
    {
        enum lnmax = Decimal32("+223.3507");
        enum lnmin = Decimal32("-232.5610");
    }
    else static if (is(D: Decimal64))
    {
        enum lnmax = Decimal64("+886.4952608027075");
        enum lnmin = Decimal64("-916.4288670116301");
    }
    else static if (is(D: Decimal128))
    {
        enum lnmax = Decimal128("+14149.38539644841072829055748903541");
        enum lnmin = Decimal128("-14220.76553433122614449511522413063");
    }
    else
        static assert(0);

    if (isLess(x, lnmin))
    {
        x = D.zero;
        return ExceptionFlags.underflow | ExceptionFlags.inexact;
    }

    if (isGreater(x, lnmax))
    {
        x = D.infinity;
        return ExceptionFlags.overflow | ExceptionFlags.inexact;
    }

    DataType!D cx = void;
    int ex = void;
    bool sx = x.unpack(cx, ex);
    const flags2 = coefficientExp(cx, ex, sx);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags2);
}

ExceptionFlags coefficientExp(T)(ref T cx, ref int ex, ref bool sx) @safe pure nothrow @nogc
{
    //e^x = 1 + x + x2/2! + x3/3! + x4/4! ...
    //to avoid overflow and underflow:
    //x^n/n! = (x^(n-1)/(n-1)! * x/n

    //save x for repeated multiplication
    const Unqual!T cxx = cx;
    const exx = ex;
    const sxx = sx;

    //shadow value
    Unqual!T cy;
    int ey = 0;
    bool sy = false;

    Unqual!T cf = cx;
    int ef = ex;
    bool sf = sx;

    if (coefficientAdd(cx, ex, sx, T(1U), 0, false, RoundingMode.implicit) & ExceptionFlags.overflow)
        return ExceptionFlags.overflow;

    Unqual!T n = 1U;

    do
    {
        cy = cx;
        ey = ex;
        sy = sx;

        Unqual!T cp = cxx;
        int ep = exx;
        bool sp = sxx;

        coefficientDiv(cp, ep, sp, ++n, 0, false, RoundingMode.implicit);
        coefficientMul(cf, ef, sf, cp, ep, sp, RoundingMode.implicit);
        coefficientAdd(cx, ex, sx, cf, ef, sf, RoundingMode.implicit);
    }
    while (!coefficientApproxEqu(cx, ex, sx, cy, ey, sy));

    return ExceptionFlags.inexact;
}

ExceptionFlags decimalExp10(D)(out D x, int n, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (n == 0)
    {
        x = D.one;
        return ExceptionFlags.none;
    }
    alias T = DataType!D;
    return x.adjustedPack(T(1U), n, false, precision, mode, ExceptionFlags.none);
}

ExceptionFlags decimalExp10(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
    {
        x = D.one;
        return ExceptionFlags.none;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? D.zero : D.infinity;
        return ExceptionFlags.none;
    }

    int n;
    auto flags = decimalToSigned(x, n, RoundingMode.implicit);
    if (flags == ExceptionFlags.none)
        return decimalExp10(x, n, precision, mode);

    flags = decimalMul(x, D.LN10, 0, mode);
    flags |= decimalExp(x, precision, mode);
    return flags;
}

ExceptionFlags decimalExp10m1(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
        return ExceptionFlags.none;

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? -D.one : D.infinity;
        return ExceptionFlags.none;
    }

    auto flags = decimalExp10(x, 0, mode);
    flags |= decimalAdd(x, -1, precision, mode);
    return flags;
}

ExceptionFlags decimalExpm1(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
        return ExceptionFlags.none;

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? -D.one : D.infinity;
        return ExceptionFlags.none;
    }

    auto flags = decimalExp(x, 0, mode);
    flags |= decimalAdd(x, -1, precision, mode);
    return flags;
}

ExceptionFlags decimalExp2(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
    {
        x = D.one;
        return ExceptionFlags.none;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? D.zero : D.infinity;
        return ExceptionFlags.none;
    }

    int n;
    auto flags = decimalToSigned(x, n, RoundingMode.implicit);
    if (flags == ExceptionFlags.none)
    {
        x = D.two;
        return decimalPow(x, n, precision, mode);
    }

    flags = decimalMul(x, D.LN2, 0, mode);
    flags |= decimalExp(x, precision, mode);
    return flags;
}

ExceptionFlags decimalExp2m1(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isZero)
        return ExceptionFlags.none;

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? -D.one : D.infinity;
        return ExceptionFlags.none;
    }

    auto flags = decimalExp2(x, 0, mode);
    flags |= decimalAdd(x, -1, precision, mode);
    return flags;
}

ExceptionFlags decimalFMA(D1, D2, D3, D)(auto const ref D1 x, auto const ref D2 y, auto const ref D3 z,
    out D result, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!(D1, D2, D3) && is(D : CommonDecimal!(D1, D2, D3)))
{
    alias U = DataType!D;

    U cx, cy, cz; int ex, ey, ez; bool sx, sy, sz;

    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);
    const fz = fastDecode(z, cz, ez, sz);

    if (fx == FastClass.signalingNaN || fy == FastClass.signalingNaN || fz == FastClass.signalingNaN)
    {
        result = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN || fz == FastClass.quietNaN)
    {
        result = D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.zero)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (fz == FastClass.infinite)
        {
            if ((sx ^ sy) != sz)
            {
                result = D.nan;
                return ExceptionFlags.invalidOperation;
            }
        }
        result = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        if (fx == FastClass.zero)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (fz == FastClass.infinite)
        {
            if ((sx ^ sy) != sz)
            {
                result = D.nan;
                return ExceptionFlags.invalidOperation;
            }
        }
        result = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fz == FastClass.infinite)
    {
        const flags = coefficientMul(cx, ex, sx, cy, ey, sy, mode);
        if (flags & ExceptionFlags.overflow)
        {
            if (sy != sx)
                return result.invalidPack(sz, U(0U));
            else
                return result.infinityPack(sz);
        }
        return result.infinityPack(sz);
    }

    if (fx == FastClass.zero || fy == FastClass.zero)
        return result.adjustedPack(cz, ez, sz, precision, mode, ExceptionFlags.none);

    if (fz == FastClass.zero)
    {
        const flags = coefficientMul(cx, ex, sx, cy, ey, sy, RoundingMode.implicit);
        return result.adjustedPack(cx, ex, sx, precision, mode, flags);
    }

    const flags = coefficientFMA(cx, ex, sx, cy, ey, sy, cz, ez, sz, mode);
    return result.adjustedPack(cx, ex, sx, precision, mode, flags);
}

//inexact, overflow, underflow
ExceptionFlags coefficientFMA(T)(ref T cx, ref int ex, ref bool sx, const(T) cy, const(int) ey, const(bool) sy, const(T) cz, const(int) ez, const(bool) sz, const(RoundingMode) mode) @safe pure nothrow @nogc
{
    if (!cx || !cy)
    {
        cx = cz;
        ex = ez;
        sx = sz;
        return ExceptionFlags.none;
    }

    if (!cz)
        return coefficientMul(cx, ex, sx, cy, ey, sy, mode);

    if (cappedAdd(ex, ey) != ey)
        return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
    auto m = xmul(cx, cy);
    sx ^= sy;

    typeof(m) czz = cz;
    auto flags = coefficientAdd(m, ex, sx, czz, ez, sz, mode);
    const pm = prec(m);
    const pmax = prec(T.max) - 1;
    if (pm > pmax)
    {
        flags |= divpow10(m, pm - pmax, sx, mode);
        if (cappedAdd(ex, pm - pmax) != pm - pmax)
            return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
    }
    cx = cast(Unqual!T)m;
    return flags;
}

ExceptionFlags decimalHypot(D1, D2, D)(auto const ref D1 x, auto const ref D2 y, out D z,
    const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!(D1, D2) && is(D: CommonDecimal!(D1, D2)))
{
    alias U = DataType!D;

    U cx, cy; int ex, ey; bool sx, sy;

    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN || fy == FastClass.signalingNaN)
    {
        z = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.infinite || fy == FastClass.infinite)
    {
        z = D.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN)
    {
        z = D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
        return z.adjustedPack(cy, cy ? ey : 0, false, precision, mode, ExceptionFlags.none);

    if (fy == FastClass.zero)
        return z.adjustedPack(cx, cx ? ex : 0, false, precision, mode, ExceptionFlags.none);

    auto flags = coefficientHypot(cx, ex, cy, ey);
    return z.adjustedPack(cx, ex, false, precision, mode, flags);
}

ExceptionFlags coefficientHypot(T)(ref T cx, ref int ex, auto const ref T cy, const(int) ey) @safe pure nothrow @nogc
{
    Unqual!T cyy = cy;
    int eyy = ey;
    bool sx;
    auto flags = coefficientSqr(cx, ex, RoundingMode.implicit);
    flags |= coefficientSqr(cyy, eyy, RoundingMode.implicit);
    flags |= coefficientAdd(cx, ex, sx, cyy, eyy, false, RoundingMode.implicit);
    flags |= coefficientSqrt(cx, ex);
    return flags;
}

ExceptionFlags decimalInc(D)(ref D x, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            const flags = coefficientAdd(cx, ex, sx, DataType!D(1U), 0, false, RoundingMode.implicit);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
            x = D.one;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
        case FastClass.infinite:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalLog(D)(auto const ref D x, out int y) @safe pure nothrow @nogc
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            y = prec(cx) + ex - 1;
            return ExceptionFlags.none;
        case FastClass.zero:
            y = int.min;
            return ExceptionFlags.invalidOperation;
        case FastClass.infinite:
            y = int.max;
            return ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
        case FastClass.signalingNaN:
            y = int.min;
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalLog(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (signbit(x))
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isInfinity)
    {
        x = D.infinity;
        return ExceptionFlags.none;
    }

    if (x.isZero)
    {
        x = -D.infinity;
        return ExceptionFlags.divisionByZero;
    }

    DataType!D cx = void;
    int ex = void;
    bool sx = x.unpack(cx, ex);
    const flags = coefficientLog(cx, ex, sx);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

ExceptionFlags coefficientLog(T)(ref T cx, ref int ex, ref bool sx) @safe pure nothrow @nogc
in
{
    assert(!sx); //only positive
    assert(cx);
}
do
{
    //ln(coefficient * 10^exponent) = ln(coefficient) + exponent * ln(10);

    static if (is(T:uint))
    {
        static immutable uint ce = 2718281828U;
        static immutable int ee = -9;
        static immutable uint cl = 2302585093U;
        static immutable int el = -9;
    }
    else static if (is(T:ulong))
    {
        static immutable ulong ce = 2718281828459045235UL;
        static immutable int ee = -18;
        static immutable ulong cl = 2302585092994045684UL;
        static immutable int el = -18;
    }
    else static if (is(T:uint128))
    {
        static immutable uint128 ce = uint128("271828182845904523536028747135266249776");
        static immutable int ee = -38;
        static immutable uint128 cl = uint128("230258509299404568401799145468436420760");
        static immutable int el = -38;
    }
    else
        static assert(0);

    //ln(x) = ln(n*e) = ln(n) + ln(e);
    //we divide x by e to find out how many times (n) we must add ln(e) = 1
    //ln(x + 1) taylor series works in the interval (-1 .. 1]
    //so our taylor series is valid for x in (0 .. 2]

    //save exponent for later
    int exponent = ex;
    ex = 0;

    enum one = T(1U);
    enum two = T(2U);

    Unqual!T n = 0U;
    bool ss = false;

    const aaa = cx;

    while (coefficientCmp(cx, ex, false, two, 0, false) >= 0)
    {
        coefficientDiv(cx, ex, sx, ce, ee, false, RoundingMode.implicit);
        ++n;
    }

    coefficientDiv(cx, ex, sx, ce, ee, false, RoundingMode.implicit);
    ++n;

    //ln(x) = (x - 1) - [(x - 1)^2]/2 + [(x - 1)^3]/3 - ....

    //initialize our result to x - 1;
    coefficientAdd(cx, ex, sx, one, 0, true, RoundingMode.implicit);

    //store cx in cxm1, this will be used for repeated multiplication
    //we negate the sign to alternate between +/-
    Unqual!T cxm1 = cx;
    int exm1 = ex;
    bool sxm1 = !sx;

    //shadow
    Unqual!T cy;
    int ey;
    bool sy;

    Unqual!T cd = cxm1;
    int ed = exm1;
    bool sd = !sxm1;

    Unqual!T i = 2U;

    do
    {
        cy = cx;
        ey = ex;
        sy = sx;

        coefficientMul(cd, ed, sd, cxm1, exm1, sxm1, RoundingMode.implicit);

        Unqual!T cf = cd;
        int ef = ed;
        bool sf = sd;

        coefficientDiv(cf, ef, sf, i++, 0, false, RoundingMode.implicit);
        coefficientAdd(cx, ex, sx, cf, ef, sf, RoundingMode.implicit);

        //writefln("%10d %10d %10d %10d %10d %10d", cx, ex, cy, ey, cx - cy, i);
    }
    while (!coefficientApproxEqu(cx, ex, sx, cy, ey, sy));

    coefficientAdd(cx, ex, sx, n, 0, false, RoundingMode.implicit);

    if (exponent != 0)
    {
        sy = exponent < 0;
        cy = sy ? cast(uint)(-exponent) : cast(uint)(exponent);
        ey = 0;
        coefficientMul(cy, ey, sy, cl, el, false, RoundingMode.implicit);
        coefficientAdd(cx, ex, sx, cy, ey, sy, RoundingMode.implicit);
    }

    //iterations
    //Decimal32 min:         15, max:         48 avg:      30.03
    //Decimal64 min:         30, max:        234 avg:     149.25
    return ExceptionFlags.inexact;
}

ExceptionFlags decimalLog2(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    auto flags = decimalLog(x, 0, mode);
    flags |= decimalDiv(x, D.LN2, precision, mode);
    return flags;
}

ExceptionFlags decimalLog10(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (signbit(x))
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isInfinity)
    {
        x = D.infinity;
        return ExceptionFlags.none;
    }

    if (x.isZero)
    {
        x = -D.infinity;
        return ExceptionFlags.divisionByZero;
    }

    DataType!D c = void;
    int e = void;
    x.unpack(c, e);
    coefficientShrink(c, e);

    Unqual!D y = e;
    auto flags = decimalMul(y, D.LN10, 0, RoundingMode.implicit);
    x = c;
    flags |= decimalLog(x, 0, mode);
    flags |= decimalAdd(x, y, precision, mode);
    return flags;
}

ExceptionFlags decimalLogp1(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    auto flags = decimalAdd(x, 1U, 0, mode);
    flags |= decimalLog(x);
    return flags;
}

ExceptionFlags decimalLog2p1(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    auto flags = decimalAdd(x, 1U, 0, mode);
    flags |= decimalLog2(x, precision, mode);
    return flags;
}

ExceptionFlags decimalLog10p1(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    auto flags = decimalAdd(x, 1U, 0, mode);
    flags |= decimalLog10(x, precision, mode);
    return flags;
}

ExceptionFlags decimalMax(D1, D2, D)(auto const ref D1 x, auto const ref D2 y, out D z)
if (isDecimal!(D1, D2, D) && is(D: CommonDecimal!(D1, D2)))
{
try {
    DataType!D cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN)
    {
        z = copysign(D.nan, x);
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        if (fx == FastClass.quietNaN)
            z = copysign(D.nan, x);
        else
            z = copysign(D.nan, y);
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
    {
        if (fy == FastClass.quietNaN)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.quietNaN)
    {
        z = x;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (sx)
            z = y;
        else
            z = x;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        if (sy)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        if (sy)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        if (sx)
            z = y;
        else
            z = x;
        return ExceptionFlags.none;
    }

    const c = coefficientCmp(cx, ex, sx, cy, ey, sy);
    if (c >= 0)
        z = x;
    else
        z = y;
    return ExceptionFlags.none;
} catch (Exception) return ExceptionFlags.invalidOperation;
}

ExceptionFlags decimalMaxAbs(D1, D2, D)(auto const ref D1 x, auto const ref D2 y, out D z)
if (isDecimal!(D1, D2, D) && is(D: CommonDecimal!(D1, D2)))
{
try {
    DataType!D cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN)
    {
        z = copysign(D.nan, x);
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        if (fx == FastClass.quietNaN)
            z = copysign(D.nan, x);
        else
            z = copysign(D.nan, y);
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
    {
        if (fy == FastClass.quietNaN)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.quietNaN)
    {
        z = x;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (!sx || fy != FastClass.infinite)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        z = y;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        z = x;
        return ExceptionFlags.none;
    }

    const c = coefficientCmp(cx, ex, cy, ey);
    if (c > 0)
        z = x;
    else if (c == 0 && !sx)
        z = x;
    else
        z = y;
    return ExceptionFlags.none;
} catch (Exception) return ExceptionFlags.invalidOperation;
}

ExceptionFlags decimalMin(D1, D2, D)(auto const ref D1 x, auto const ref D2 y, out D z)
if (isDecimal!(D1, D2, D) && is(D: CommonDecimal!(D1, D2)))
{
try {
    DataType!D cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN)
    {
        z = copysign(D.nan, x);
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        if (fx == FastClass.quietNaN)
            z = copysign(D.nan, x);
        else
            z = copysign(D.nan, y);
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
    {
        if (fy == FastClass.quietNaN)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.quietNaN)
    {
        z = x;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (sx)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        if (sy)
            z = y;
        else
            z = x;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        if (sy)
            z = y;
        else
            z = x;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        if (sx)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    const c = coefficientCmp(cx, ex, sx, cy, ey, sy);
    if (c <= 0)
        z = x;
    else
        z = y;
    return ExceptionFlags.none;
} catch (Exception) return ExceptionFlags.invalidOperation;
}

ExceptionFlags decimalMinAbs(D1, D2, D)(auto const ref D1 x, auto const ref D2 y, out D z)
if (isDecimal!(D1, D2, D) && is(D: CommonDecimal!(D1, D2)))
{
try {
    DataType!D cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN)
    {
        z = copysign(D.nan, x);
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        if (fx == FastClass.quietNaN)
            z = copysign(D.nan, x);
        else
            z = copysign(D.nan, y);
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
    {
        if (fy == FastClass.quietNaN)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.quietNaN)
    {
        z = x;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.infinite && sx)
            z = x;
        else
            z = y;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        z = x;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero)
    {
        z = x;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.zero)
    {
        z = y;
        return ExceptionFlags.none;
    }

    const c = coefficientCmp(cx, ex, cy, ey);
    if (c < 0)
        z = x;
    else if (c == 0 && sx)
        z = x;
    else
        z = y;
    return ExceptionFlags.none;
} catch (Exception) return ExceptionFlags.invalidOperation;
}

ExceptionFlags decimalMod(D1, D2)(ref D1 x, auto const ref D2 y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    alias T = DataType!D;
    alias T1 = DataType!D1;

    T cx, cy; int ex, ey; bool sx, sy;

    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);
    const sxx = sx;

    if (fx == FastClass.signalingNaN)
    {
        unsignalize(x);
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        x = sy ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
        return ExceptionFlags.none;

    if (fy == FastClass.quietNaN)
    {
        x = sy ? -D1.nan : D1.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        x = sx ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.zero)
    {
        x = sx ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.zero)
        return ExceptionFlags.none;

    if (fy == FastClass.infinite)
        return ExceptionFlags.none;

    ////coefficientShrink(cx, ex);
    //coefficientShrink(cy, ey);
    //
    //if (cy == 1U && ey == 0)
    //{
    //    //if (cx == 1U && ex == 0)
    //        x = sx ? -D1.zero : D1.zero;
    //    return ExceptionFlags.none;
    //}

    auto flags = coefficientMod(cx, ex, sx, cy, ey, sy, mode);
    flags = x.adjustedPack(cx, ex, sx, precision, mode, flags);
    if (x.isZero)
        x = sxx ? -D1.zero : D1.zero;
    return flags;
}

ExceptionFlags decimalMod(D, T)(ref D x, auto const ref T y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    alias X = DataType!D;

    U cx; int ex; bool sx;
    bool sy;
    U cy = unsign!U(y, sy);

    if (!y)
    {
        x = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    final switch (fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            const flags = coefficientMod(cx, ex, sx, cy, 0, sy, mode);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
            return ExceptionFlags.none;
        case FastClass.infinite:
            x = sx ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalMod(T, D)(auto const ref T x, auto const ref D y, out D z, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    alias X = DataType!D;
    U cy; int ey; bool sy;
    int ex = 0;
    bool sx;
    U cx = unsign!U(x, sx);
    final switch (fastDecode(y, cy, ey, sy))
    {
        case FastClass.finite:
            if (x == 0)
            {
                z = D.zero;
                return ExceptionFlags.none;
            }
            auto flags = coefficientMod(cx, ex, sx, cy, 0, sy, mode);
            flags |= coefficientAdjust(cx, ex, cvt!U(X.max), sx, RoundingMode.implicit);
            return z.adjustedPack(cvt!X(cx), ex, sx, precision, mode, flags);
        case FastClass.zero:
            z = sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        case FastClass.infinite:
            return z.packIntegral(x, precision, mode);
        case FastClass.quietNaN:
            z = sy ? -D.nan : D.nan;
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            z = sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalMod(D, F)(ref D x, auto const ref F y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isFloatingPoint!F)
{
    alias T = CommonStorage!(D, F);

    T cx, cy; int ex, ey; bool sx, sy;
    ExceptionFlags flags;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy, mode, flags);

    if (fx == FastClass.signalingNaN)
    {
        unsignalize(x);
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
        return ExceptionFlags.none;

    if (fy == FastClass.quietNaN)
    {
        x = sy ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite || fy == FastClass.zero)
    {
        x = sx ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.zero)
        return ExceptionFlags.none;

    if (fy == FastClass.infinite)
        return ExceptionFlags.none;

    flags |= coefficientAdjust(cy, ey, realFloatPrecision!F(0), sy, mode);
    flags |= coefficientMod(cx, ex, sx, cy, ey, sy, mode);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

ExceptionFlags decimalMod(F, D)(auto const ref F x, auto const ref D y, out D z, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isFloatingPoint!F)
{
    alias T = CommonStorage!(D, F);
    alias X = DataType!D;

    T cx, cy; int ex, ey; bool sx, sy;
    ExceptionFlags flags;
    const fx = fastDecode(x, cx, ex, sx, mode, flags);
    const fy = fastDecode(y, cy, ey, sy);

    if (fy == FastClass.signalingNaN)
    {
        z = sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
    {
        z = sx ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.quietNaN)
    {
        z = sy ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite || fy == FastClass.zero)
    {
        z = sx ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.infinite)
        return ExceptionFlags.none;

    flags |= coefficientAdjust(cx, ex, realFloatPrecision!F(0), sx, mode);
    flags |= coefficientMod(cx, ex, sx, cy, ey, sy, mode);
    return z.adjustedPack(cx, ex, sx, precision, mode, flags);
}

//inexact, overflow, underflow
ExceptionFlags coefficientMod(T)(ref T cx, ref int ex, ref bool sx, const(T) cy, const(int) ey, const(bool) sy, const(RoundingMode) mode) @safe pure nothrow @nogc
{
    if (!cy)
        return ExceptionFlags.invalidOperation;
    Unqual!T rcx = cx;
    int rex = ex;
    bool rsx = sx;
    coefficientDiv(rcx, rex, rsx, cy, ey, sy, mode);   //16
    coefficientRound(rcx, rex, rsx, mode);             //00
    coefficientMul(rcx, rex, rsx, cy, ey, sy, mode);   //16
    return coefficientAdd(cx, ex, sx, rcx, rex, !rsx, mode);  //0
}

ExceptionFlags coefficientMod2PI(T)(ref T cx, ref int ex)
{
    ExceptionFlags flags;
    if (coefficientCmp(cx, ex, Constants!T.c2π, Constants!T.e2π) > 0)
    {
        bool sx = false;
        Unqual!T cy = cx;
        cx = get_mod2pi!T(ex);
        flags |= coefficientMul(cx, ex, sx, cy, 0, false, RoundingMode.implicit);
        flags |= coefficientFrac(cx, ex);
        flags |= coefficientMul(cx, ex, sx, Constants!T.c2π, Constants!T.e2π, false, RoundingMode.implicit);
    }
    return flags;
}

ExceptionFlags decimalMul(D1, D2)(ref D1 x, auto const ref D2 y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    alias T = DataType!D;
    alias T1 = DataType!D1;

    T cx, cy; int ex, ey; bool sx, sy;

    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN || fy == FastClass.signalingNaN)
    {
        x = sx ^ sy ? -D1.nan : D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN)
    {
        x = sx ^ sy ? -D1.nan : D1.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.zero)
        {
            x = sx ^ sy ? -D1.nan : D1.nan;
            return ExceptionFlags.invalidOperation;
        }
        x = sx ^ sy ? -D1.infinity : D1.infinity;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        if (fx == FastClass.zero)
        {
            x = sx ^ sy ? -D1.nan : D1.nan;
            return ExceptionFlags.invalidOperation;
        }
        x = sx ^ sy ? -D1.infinity : D1.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero || fy == FastClass.zero)
    {
        x = sx ^ sy ? -D1.zero : D1.zero;
        return ExceptionFlags.none;
    }

    const flags = coefficientMul(cx, ex, sx, cy, ey, sy, mode);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

ExceptionFlags decimalMul(D, T)(ref D x, auto const ref T y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    alias X = DataType!D;
    U cx; int ex; bool sx;
    bool sy;
    U cy = unsign!U(y, sy);
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!y)
            {
                x = sx ^ sy ? -D.zero : D.zero;
                return ExceptionFlags.none;
            }
            auto flags = coefficientMul(cx, ex, sx, cy, 0, sy, RoundingMode.implicit);
            flags |= coefficientAdjust(cx, ex, cvt!U(X.max), sx, RoundingMode.implicit);
            return x.adjustedPack(cvt!X(cx), ex, sx, precision, mode, flags);
        case FastClass.zero:
            x = sx ^ sy ? -D.zero : D.zero;
            return ExceptionFlags.none;
        case FastClass.infinite:
            if (!y)
            {
                x = sx ^ sy ? -D.nan : D.nan;
                return ExceptionFlags.invalidOperation;
            }
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalMul(D, F)(ref D x, auto const ref F y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isFloatingPoint!F)
{
    alias T = CommonStorage!(D, F);

    T cx, cy; int ex, ey; bool sx, sy;
    ExceptionFlags flags;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy, mode, flags);

    if (fx == FastClass.signalingNaN)
    {
        x = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN || fy == FastClass.quietNaN)
    {
        x = sx ^ sy ? -D.nan : D.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.zero)
        {
            x = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        }
        x = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fy == FastClass.infinite)
    {
        if (fx == FastClass.zero)
        {
            x = sx ^ sy ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        }
        x = sx ^ sy ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.zero || fy == FastClass.zero)
    {
        x = sx ^ sy ? -D.zero : D.zero;
        return ExceptionFlags.none;
    }
    flags |= coefficientAdjust(cy, ey, realFloatPrecision!F(0), sy, mode);
    flags |= coefficientMul(cx, ex, sx, cy, ey, sy, mode);
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

ExceptionFlags decimalMul(T, D)(auto const ref T x, auto const ref D y, out D z, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isIntegral!T)
{
   z = y;
   return decimalMul(z, x, precision, mode);
}

ExceptionFlags decimalMul(F, D)(auto const ref F x, auto const ref D y, out D z, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isFloatingPoint!F)
{
    z = y;
    return decimalMul(z, x, precision, mode);
}

//inexact, overflow, underflow
ExceptionFlags coefficientMul(T)(ref T cx, ref int ex, ref bool sx, const(T) cy, const(int) ey, const(bool) sy, const(RoundingMode) mode) @safe pure nothrow @nogc
{
    if (!cy || !cy)
    {
        cx = T(0U);
        sx ^= sy;
        return ExceptionFlags.none;
    }

    auto r = xmul(cx, cy);

    if (cappedAdd(ex, ey) != ey)
        return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;

    sx ^= sy;

    if (r > T.max)
    {
        const px = prec(r);
        const pm = prec(T.max) - 1;
        const flags = divpow10(r, px - pm, sx, mode);
        if (cappedAdd(ex, px - pm) != px - pm)
            return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
        cx = cvt!T(r);
        return flags;
    }
    else
    {
        cx = cvt!T(r);
        return ExceptionFlags.none;
    }
}

ExceptionFlags decimalMulPow2(D)(ref D x, const(int) n, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!n)
                return ExceptionFlags.none;
            DataType!D cy = 1U;
            int ey = n;
            ExceptionFlags flags;
            final switch(mode)
            {
                case RoundingMode.tiesToAway:
                    flags = exp2to10!(RoundingMode.tiesToAway)(cy, ey, false);
                    break;
                case RoundingMode.tiesToEven:
                    flags = exp2to10!(RoundingMode.tiesToEven)(cy, ey, false);
                    break;
                case RoundingMode.towardZero:
                    flags = exp2to10!(RoundingMode.towardZero)(cy, ey, false);
                    break;
                case RoundingMode.towardNegative:
                    flags = exp2to10!(RoundingMode.towardNegative)(cy, ey, false);
                    break;
                case RoundingMode.towardPositive:
                    flags = exp2to10!(RoundingMode.towardPositive)(cy, ey, false);
                    break;
            }
            flags |= coefficientMul(cx, ex, sx, cy, ey, false, mode);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalNextDown(D)(ref D x) @safe pure nothrow @nogc
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            coefficientExpand(cx, ex);
            if (!sx)
                --cx;
            else
                ++cx;
            return x.adjustedPack(cx, ex, sx, 0, RoundingMode.towardNegative, ExceptionFlags.none);
        case FastClass.zero:
            x.pack(DataType!D(1U), D.EXP_MIN, true);
            return ExceptionFlags.none;
        case FastClass.infinite:
            if (!sx)
                x = D.max;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalNextUp(D)(ref D x) @safe pure nothrow @nogc
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            coefficientExpand(cx, ex);
            if (sx)
                --cx;
            else
                ++cx;
            return x.adjustedPack(cx, ex, sx, 0, RoundingMode.towardPositive, ExceptionFlags.none);
        case FastClass.zero:
            x.pack(DataType!D(1U), D.EXP_MIN, false);
            return ExceptionFlags.none;
        case FastClass.infinite:
            if (sx)
                x = -D.max;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalPoly(D1, D2, D)(auto const ref D1 x, const(D2)[] a, out D result)
if (isDecimal!(D1, D2) && is(D: CommonDecimal!(D1, D2)))
{
    if (!a.length)
    {
        result = 0;
        return ExceptionFlags.none;
    }
    ptrdiff_t i = a.length - 1;
    D result = a[i];
    ExceptionFlags flags;
    while (--i >= 0)
    {
        flags |= decimalMul(result, x);
        flags |= decimalAdd(result, a[i]);
    }
    return flags;
}

ExceptionFlags decimalPow(D, T)(ref D x, const(T) n, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D & isIntegral!T)
{
    DataType!D cx; int ex; bool sx;

    final switch (fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!n)
            {
                x = D.one;
                return ExceptionFlags.none;
            }

            DataType!D cv; int ev; bool sv;
            ExceptionFlags flags;
            static if (isSigned!T)
            {
                auto m = unsign!(Unsigned!T)(n);
                if (n < 0)
                {
                    cv = 1U;
                    ev = 0;
                    sv = false;
                    flags = coefficientDiv(cv, ev, sv, cx, ex, sx, RoundingMode.implicit);
                }
                else
                {
                    cv = cx;
                    ev = ex;
                    sv = sx;
                }
            }
            else
            {
                Unqual!T m = n;
                cv = cx;
                ev = ex;
                sv = sx;
            }

            cx = 1U;
            ex = 0;
            sx = false;

            ExceptionFlags sqrFlags;
            while (m)
            {
                if (m & 1)
                {
                    flags |= sqrFlags | coefficientMul(cx, ex, sx, cv, ev, sv, RoundingMode.implicit);
                    sqrFlags = ExceptionFlags.none;
                    if (flags & (ExceptionFlags.overflow | ExceptionFlags.underflow))
                        break;
                }
                m >>>= 1;
                sqrFlags |= coefficientSqr(cv, ev, RoundingMode.implicit);
                sv = false;
            }

            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
            if (!n)
                x = D.one;
            else
            {
                if (n & 1) //odd
                    return n < 0 ? ExceptionFlags.divisionByZero : ExceptionFlags.none;
                else //even
                {
                    if (n < 0)
                        return ExceptionFlags.divisionByZero;
                    else
                    {
                        x = D.zero;
                        return ExceptionFlags.none;
                    }
                }
            }
            return ExceptionFlags.none;
        case FastClass.infinite:
            if (!n)
                x = D.one;
            else
                x = !sx || (n & 1) ? D.infinity : -D.infinity;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            if (!n)
                x = D.one;
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalPow(D1, D2)(ref D1 x, auto const ref D2 y, const(int) precision, const(RoundingMode) mode)
if (isDecimal!(D1, D2))
{
    long ip;
    auto flags = decimalToSigned(y, ip, mode);
    if (flags == ExceptionFlags.none)
        return decimalPow(x, ip, precision, mode);

    flags = decimalLog(x, 0, mode);
    flags |= decimalMul(x, y, 0, mode);
    flags |= decimalExp(x, precision, mode);
    return flags;
}

ExceptionFlags decimalPow(D, F)(ref D x, auto const ref F y, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D && isFloatingPoint!F)
{
    Unqual!D z;
    auto flags = z.packFloatingPoint(y, precision, mode, 0);
    flags |= decimalPow(x, z, precision, mode);
    return flags;
}

ExceptionFlags decimalPow(T, D)(auto const ref T x, auto const ref D y, out D result, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D && isIntegral!T)
{
    auto r = Decimal128(x, mode);
    auto flags = decimalPow(r, y, precision, mode);
    flags |= decimalToDecimal(r, result, precision, mode);
    return flags;
}

ExceptionFlags decimalPow(F, D)(auto const ref F x, auto const ref D y, out D result, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D && isFloatingPoint!F)
{
    auto r = Decimal128(x, mode, 0);
    auto flags = decimalPow(r, y, precision, mode);
    flags |= decimalToDecimal(r, result, precision, mode);
    return flags;
}

ExceptionFlags decimalProd(D)(const(D)[] x, out D result, out int scale, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    alias T = makeUnsignedBit!(D.sizeof * 16);
    DataType!D cx;
    T cxx, cr;
    ExceptionFlags flags;
    int ex, er;
    bool sx, sr;

    result = 0;
    scale = 0;
    bool hasInfinity;
    bool hasZero;
    bool infinitySign;
    bool zeroSign;
    size_t i = 0;
    while (i < x.length)
    {
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            hasInfinity = true;
            infinitySign = cast(bool)(signbit(x[i]));
            ++i;
            break;
        }

        if (x[i].isZero)
        {
            hasZero = true;
            zeroSign = cast(bool)(signbit(x[i]));
            ++i;
            break;
        }

        sx = x.unpack(cx, ex);
        cxx = cx;
        flags |= coefficientMul(cr, er, sr, cxx, ex, sx, mode);
        er -= cappedAdd(scale, er);
        ++i;

        if (flags & ExceptionFlags.overflow)
            break;
    }

    while (i < x.length)
    {
        //infinity or overflow detected
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            hasInfinity = true;
            infinitySign ^= cast(bool)(signbit(x[i]));
        }
        else if (x[i].isZero)
        {
            hasZero = true;
            zeroSign ^= cast(bool)(signbit(x[i]));
        }
        else
        {
            zeroSign ^= cast(bool)(signbit(x[i]));
        }

        ++i;
    }

    if (hasInfinity & hasZero)
    {
        result = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (hasInfinity)
    {
        result = infinitySign ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (hasZero)
    {
        result = zeroSign ? -D.zero : D.zero;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalProdDiff(D)(const(D)[] x, const(D)[] y, out D result, out int scale, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    const len = x.length > y.length ? y.length : x.length;

    bool hasInfinity;
    bool hasZero;
    bool infinitySign;
    bool invalidSum;

    alias T = makeUnsignedBit!(D.sizeof * 16);
    DataType!D cx, cy;
    T cxx, cyy, cr;
    int ex, ey, er;
    bool sx, sy, sr;

    size_t i = 0;
    while (i < len)
    {
        if (x[i].isSignalNaN || y[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN || y[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (y[i].isInfinity && signbit(x) != signbit(y))
            {
                invalidSum = true;
                ++i;
                break;
            }

            hasInfinity = true;
            infinitySign = cast(bool)signbit(x[i]);
            ++i;
            break;
        }

        if (y[i].isInfinity)
        {
            hasInfinity = true;
            infinitySign = cast(bool)signbit(x[i]);
            ++i;
            break;
        }

        if (x[i] == y[i])
        {
            hasZero = true;
            ++i;
            break;
        }
        sx = x[i].unpack(cx, ex);
        sy = y[i].unpack(cy, ey);
        cxx = cx; cyy = cy;
        flags |= coefficientSub(cx, ex, sx, cy, ey, sy, mode);
        flags |= coefficientMul(cr, er, sr, cx, ex, sx, mode);
        er -= cappedAdd(scale, er);
        ++i;
        if (flags & (ExceptionFlags.overflow | ExceptionFlags.underflow))
            break;
    }

    while (i < len)
    {
        //inf, zero or overflow, underflow, invalidSum;
        if (x[i].isSignalNaN || y[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN || y[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (y[i].isInfinity && signbit(x) != signbit(y))
                invalidSum = true;
            else
            {
                hasInfinity = true;
                infinitySign ^= cast(bool)signbit(x[i]);
            }
        }
        else if (y[i].isInfinity)
        {
            hasInfinity = true;
            infinitySign ^= cast(bool)signbit(y[i]);
        }
        else if (x[i] == y[i])
            hasZero = true;
        ++i;
    }

    if (invalidSum)
    {
        result = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (hasInfinity & hasZero)
    {
        result = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (hasInfinity)
    {
        result = infinitySign ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (hasZero)
    {
        result = D.zero;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalProdSum(D)(const(D)[] x, const(D)[] y, out D result, out int scale, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    const len = x.length > y.length ? y.length : x.length;

    bool hasInfinity;
    bool hasZero;
    bool infinitySign;
    bool invalidSum;

    alias T = makeUnsignedBit!(D.sizeof * 16);
    DataType!D cx, cy;
    T cxx, cyy, cr;
    int ex, ey, er;
    bool sx, sy, sr;

    size_t i = 0;
    while (i < len)
    {
        if (x[i].isSignalNaN || y[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN || y[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (y[i].isInfinity && signbit(x) != signbit(y))
            {
                invalidSum = true;
                ++i;
                break;
            }

            hasInfinity = true;
            infinitySign = cast(bool)signbit(x[i]);
            ++i;
            break;
        }

        if (y[i].isInfinity)
        {
            hasInfinity = true;
            infinitySign = cast(bool)signbit(x[i]);
            ++i;
            break;
        }

        if (x[i] == -y[i])
        {
            hasZero = true;
            ++i;
            break;
        }
        sx = x[i].unpack(cx, ex);
        sy = y[i].unpack(cy, ey);
        cxx = cx; cyy = cy;
        flags |= coefficientAdd(cx, ex, sx, cy, ey, sy, mode);
        flags |= coefficientMul(cr, er, sr, cx, ex, sx, mode);
        er -= cappedAdd(scale, er);
        ++i;
        if (flags & (ExceptionFlags.overflow | ExceptionFlags.underflow))
            break;
    }

    while (i < len)
    {
        //inf, zero or overflow, underflow, invalidSum;
        if (x[i].isSignalNaN || y[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN || y[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (y[i].isInfinity && signbit(x) != signbit(y))
                invalidSum = true;
            else
            {
                hasInfinity = true;
                infinitySign ^= cast(bool)signbit(x[i]);
            }
        }
        else if (y[i].isInfinity)
        {
            hasInfinity = true;
            infinitySign ^= cast(bool)signbit(y[i]);
        }
        else if (x[i] == -y[i])
            hasZero = true;
        ++i;
    }

    if (invalidSum)
    {
        result = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (hasInfinity & hasZero)
    {
        result = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (hasInfinity)
    {
        result = infinitySign ? -D.infinity : D.infinity;
        return ExceptionFlags.none;
    }

    if (hasZero)
    {
        result = D.zero;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalQuantize(D1, D2)(ref D1 x, auto const ref D2 y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!(D1, D2))
{
    alias U = CommonStorage!(D1, D2);
    U cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    if (fx == FastClass.signalingNaN)
    {
        unsignalize(x);
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.signalingNaN)
    {
        x = D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fx == FastClass.quietNaN)
        return ExceptionFlags.none;

    if (fy == FastClass.quietNaN)
    {
        x = D1.nan;
        return ExceptionFlags.none;
    }

    if (fx == FastClass.infinite)
    {
        if (fy == FastClass.infinite)
            return ExceptionFlags.none;
        x = D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (fy == FastClass.infinite)
    {
        x = D1.nan;
        return ExceptionFlags.invalidOperation;
    }

    auto flags = coefficientAdjust(cx, ex, ey, ey, cvt!U(D1.COEF_MAX), sx, mode);
    if (flags & ExceptionFlags.overflow)
        flags = ExceptionFlags.invalidOperation;
    return x.adjustedPack(cx, ex, sx, precision, mode, flags);
}

ExceptionFlags decimalRoot(D, T)(ref D x, const(T) n, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D && isIntegral!T)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (!n)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (n == -1)
    {
        return ExceptionFlags.overflow | ExceptionFlags.underflow;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = !signbit(x) || (n & 1) ? D.infinity : -D.infinity;
    }

    if (x.isZero)
    {
        if (n & 1) //odd
        {
            if (n < 0)
            {
                x = signbit(x) ? -D.infinity : D.infinity;
                return ExceptionFlags.divisionByZero;
            }
            else
                return ExceptionFlags.none;
        }
        else //even
        {
            if (n < 0)
            {
                x = D.infinity;
                return ExceptionFlags.divisionByZero;
            }
            else
            {
                x = D.zero;
                return ExceptionFlags.none;
            }
        }
    }

    if (n == 1)
        return ExceptionFlags.none;
    Unqual!D y = 1U;
    auto flags = decimalDiv(y, n, 0, mode);
    flags |= decimalPow(x, y, precision, mode);
    return flags;
}

ExceptionFlags decimalRound(D)(ref D x, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            const flags = coefficientAdjust(cx, ex, 0, D.EXP_MAX, D.COEF_MAX, sx, mode);
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

//inexact
ExceptionFlags coefficientRound(T)(ref T cx, ref int ex, const(bool) sx, const(RoundingMode) mode) @safe pure nothrow @nogc
{
    if (ex < 0)
    {
        const flags = divpow10(cx, -ex, sx, mode);
        ex = 0;
        return flags;
    }
    return ExceptionFlags.none;
}

ExceptionFlags decimalScale(D)(ref D x, const(int) n, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!n)
                return ExceptionFlags.none;
            const remainder = cappedAdd(ex, n) - n;
            ExceptionFlags flags;
            if (remainder)
            {
                if (remainder < 0)
                    coefficientShrink(cx, ex);
                else
                    coefficientExpand(cx, ex);
                if (cappedAdd(ex, remainder) != remainder)
                    flags = ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
            }
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
        case FastClass.zero:
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalSin(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
        case FastClass.infinite:
            x = sx ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
        case FastClass.zero:
            return ExceptionFlags.none;
        default:
            int quadrant;
            auto flags = coefficientCapAngle(cx, ex, sx, quadrant);
            switch (quadrant)
            {
                case 1:
                    flags |= coefficientSinQ(cx, ex, sx);
                    break;
                case 2:
                    flags |= coefficientCosQ(cx, ex, sx);
                    break;
                case 3:
                    flags |= coefficientSinQ(cx, ex, sx);
                    sx = !sx;
                    break;
                case 4:
                    flags |= coefficientCosQ(cx, ex, sx);
                    sx = !sx;
                    break;
                default:
                    assert(0);
            }
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
    }
}

ExceptionFlags decimalSinh(D)(ref D x, const(int) precision, const(RoundingMode) mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = D.infinity;
        return ExceptionFlags.none;
    }

    if (x.isZero)
        return ExceptionFlags.none;

    Unqual!D x1 = x;
    Unqual!D x2 = -x;

    auto flags = decimalExp(x1, 0, mode);
    flags |= decimalExp(x2, 0, mode);
    flags |= decimalSub(x1, x2, 0, mode);
    x = x1;
    flags |= decimalMul(x, 2U, precision, mode);
    return flags;
}

version (none) // Missing decimalReduceAngle
ExceptionFlags decimalSinPi(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    if (x.isSignalNaN || x.isInfinity)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    decimalReduceAngle(x);

    auto flags = decimalMul(x, D.PI, 0, mode);
    flags |= decimalSin(x, precision, mode);
    return flags;
}

ExceptionFlags coefficientSinQ(T)(ref T cx, ref int ex, ref bool sx) @safe pure nothrow @nogc
{
    //taylor series: sin(x) = x - x^3/3! + x^5/5! - x^7/7! ...

    Unqual!T cx2 = cx; int ex2 = ex; bool sx2 = true;
    coefficientSqr(cx2, ex2, RoundingMode.implicit);

    Unqual!T cy; int ey; bool sy;
    Unqual!T cf = cx; int ef = ex; bool sf = sx;
    Unqual!T n = 2U;

    do
    {
        cy = cx;
        ey = ex;
        sy = sx;

        coefficientMul!T(cf, ef, sf, cx2, ex2, sx2, RoundingMode.implicit);
        coefficientDiv!T(cf, ef, sf, n++, 0, false, RoundingMode.implicit);
        coefficientDiv!T(cf, ef, sf, n++, 0, false, RoundingMode.implicit);
        coefficientAdd!T(cx, ex, sx, cf, ef, sf, RoundingMode.implicit);
        //writefln("%10d %10d %10d %10d", cx, ex, cy, ey);
       // writefln("%016x%016x %10d %016x%016x %10d", cx.hi, cx.lo, ex, cy.hi, cy.lo, ey);
    }
    while (!coefficientApproxEqu!T(cx, ex, sx, cy, ey, sy));
    return ExceptionFlags.inexact;
}

unittest
{
    ulong cx = 11000000000000000855UL;
    int ex = -19;
    bool sx;

    coefficientSinQ!ulong(cx, ex, sx);

    //writefln("%35.34f", sin(Decimal128("1.1000000000000000855000000000000000")));
    //writefln("%35.34f", Decimal128(1.1));
}

ExceptionFlags coefficientSinCosQ(T)(const T cx, const(int) ex, const(bool) sx,
    out T csin, out int esin, out bool ssin,
    out T ccos, out int ecos, out bool scos) @safe pure nothrow @nogc
{
    csin = cx; esin = ex; ssin = sx;
    ccos = 1U; ecos = 0; scos = false;
    Unqual!T cs, cc; int es, ec; bool ss, sc;
    Unqual!T cf = cx; int ef = ex; bool sf = sx;
    Unqual!T n = 2U;
    do
    {
        cs = csin; es = esin; ss = ssin;
        cc = ccos; ec = ecos; sc = scos;
        coefficientMul(cf, ef, sf, cx, ex, !sx, RoundingMode.implicit);
        coefficientDiv(cf, ef, sf, n++, 0, false, RoundingMode.implicit);
        coefficientAdd(ccos, ecos, scos, cf, ef, sf, RoundingMode.implicit);
        coefficientMul(cf, ef, sf, cx, ex, sx, RoundingMode.implicit);
        coefficientDiv(cf, ef, sf, n++, 0, false, RoundingMode.implicit);
        coefficientAdd(csin, esin, ssin, cf, ef, sf, RoundingMode.implicit);
        //writefln("%10d %10d %10d %10d %10d %10d %10d %10d", csin, esin, cs, es, ccos, ecos, cc, ec);
    }
    while(!coefficientApproxEqu(csin, esin, ssin, cs, es, ss) &&
          !coefficientApproxEqu(ccos, ecos, scos, cc, ec, sc));

    return ExceptionFlags.inexact;
}

ExceptionFlags decimalRSqrt(D)(ref D x, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (sx)
            {
                x = -D.nan;
                return ExceptionFlags.invalidOperation;
            }
            const flags = coefficientRSqrt(cx, ex);
            return x.adjustedPack(cx, ex, false, precision, mode, flags);
        case FastClass.zero:
            x = D.infinity;
            return ExceptionFlags.divisionByZero;
        case FastClass.infinite:
            if (sx)
            {
                x = -D.nan;
                return ExceptionFlags.invalidOperation;
            }
            x = D.zero;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

//inexact, underflow
ExceptionFlags coefficientRSqrt(T)(ref T cx, ref int ex) @safe pure nothrow @nogc
{
    bool sx = false;
    if (!cx)
        return ExceptionFlags.divisionByZero;
    Unqual!T cy = cx; int ey = ex;
    const flags = coefficientSqrt(cy, ey);
    if (flags & ExceptionFlags.underflow)
        return ExceptionFlags.overflow;
    cx = 1U;
    ex = 0;
    return flags | coefficientDiv(cx, ex, sx, cy, ey, false, RoundingMode.implicit);
}

ExceptionFlags decimalSqr(D)(ref D x, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            const flags = coefficientSqr(cx, ex, RoundingMode.implicit);
            return x.adjustedPack(cx, ex, false, precision, mode, flags);
        case FastClass.zero:
            x = D.zero;
            return ExceptionFlags.none;
        case FastClass.infinite:
            x = D.infinity;
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalSqrt(D)(ref D x, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (sx)
            {
                x = -D.nan;
                return ExceptionFlags.invalidOperation;
            }
            const flags = coefficientSqrt(cx, ex);
            return x.adjustedPack(cx, ex, false, precision, mode, flags);
        case FastClass.zero:
            return ExceptionFlags.none;
        case FastClass.infinite:
            if (sx)
            {
                x = -D.nan;
                return ExceptionFlags.invalidOperation;
            }
            return ExceptionFlags.none;
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
 }

//inexact, overflow, underflow
ExceptionFlags coefficientSqr(T)(ref T cx, ref int ex, const(RoundingMode) mode) @safe pure nothrow @nogc
{
    if (!cx)
    {
        cx = T(0U);
        ex = 0;
        return ExceptionFlags.none;
    }

    auto r = xsqr(cx);

    const int ey = ex;
    if (cappedAdd(ex, ey) != ey)
        return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;

    if (r > T.max)
    {
        const px = prec(r);
        const pm = prec(T.max) - 1;
        const flags = divpow10(r, px - pm, false, mode);
        if (cappedAdd(ex, px - pm) != px - pm)
            return ex < 0 ? ExceptionFlags.underflow : ExceptionFlags.overflow;
        cx = cvt!T(r);
        return flags;
    }
    else
    {
        cx = cvt!T(r);
        return ExceptionFlags.none;
    }
}

//inexact, underflow
ExceptionFlags coefficientSqrt(T)(ref T cx, ref int ex) @safe pure nothrow @nogc
{
    // Newton-Raphson: x = (x + n/x) / 2;
    if (!cx)
    {
        cx = 0U;
        ex = 0;
        return ExceptionFlags.none;
    }

    alias U = makeUnsignedBit!(T.sizeof * 16);

    U cxx = cx;
    ExceptionFlags flags;

    //we need full precision
    coefficientExpand(cxx, ex);

    if (ex & 1)
    {
        //exponent is odd, make it even
        flags = divpow10(cxx, 1, false, RoundingMode.implicit);
        ++ex;
    }

    ex /= 2;
    import pham.external.dec.integral : sqrtIntegral = sqrt;
    const bool inexact = sqrtIntegral(cxx);
    flags |= coefficientAdjust(cxx, ex, cvt!U(T.max), false, RoundingMode.implicit);
    cx = cast(T)cxx;
    return inexact ? flags | ExceptionFlags.inexact : flags;
}

ExceptionFlags decimalSum(D)(const(D)[] x, out D result, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    alias T = makeUnsignedBit!(D.sizeof * 16);

    DataType!D cx;
    T cxx, cr;
    int ex, er;
    bool sx, sr;
    ExceptionFlags flags;

    result = 0;
    bool hasPositiveInfinity, hasNegativeInfinity;
    size_t i = 0;
    while (i < x.length)
    {
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (signbit(x[i]))
                hasNegativeInfinity = true;
            else
                hasPositiveInfinity = true;
            ++i;
            break;
        }

        if (x[i].isZero)
        {
            ++i;
            continue;
        }

        sx = x.unpack(cx, ex);
        cxx = cx;
        flags |= coefficientAdd(cr, er, sr, cxx, ex, sx, mode);
        ++i;

        if (flags & ExceptionFlags.overflow)
            break;
    }

    while (i < x.length)
    {
        //infinity or overflow detected
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            if (signbit(x[i]))
                hasNegativeInfinity = true;
            else
                hasPositiveInfinity = true;
        }
        ++i;
    }

    if (hasPositiveInfinity)
    {
        if (hasNegativeInfinity)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }
        result = D.infinity;
        return ExceptionFlags.none;
    }

    if (hasNegativeInfinity)
    {
        result = -D.infinity;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalSumAbs(D)(const(D)[] x, out D result, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    alias T = makeUnsignedBit!(D.sizeof * 16);
    DataType!D cx;
    T cxx, cr;
    ExceptionFlags flags;
    int ex, er;
    bool sr;

    result = 0;
    bool hasInfinity;
    size_t i = 0;
    while (i < x.length)
    {
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            hasInfinity = true;
            ++i;
            break;
        }

        if (x[i].isZero)
        {
            ++i;
            continue;
        }

        x.unpack(cx, ex);
        cxx = cx;
        flags |= coefficientAdd(cr, er, sr, cxx, ex, false, mode);
        ++i;

        if (flags & ExceptionFlags.overflow)
            break;
    }

    while (i < x.length)
    {
        //infinity or overflow detected
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
            hasInfinity = true;
        ++i;
    }

    if (hasInfinity)
    {
        result = D.infinity;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalSumSquare(D)(const(D)[] x, out D result, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    alias T = makeUnsignedBit!(D.sizeof * 16);
    DataType!D cx;
    T cxx, cr;
    ExceptionFlags flags;
    int ex, er;
    bool sr;
    result = 0;
    bool hasInfinity;
    size_t i = 0;
    while (i < x.length)
    {
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
        {
            hasInfinity = true;
            ++i;
            break;
        }

        if (x[i].isZero)
        {
            ++i;
            continue;
        }

        x.unpack(cx, ex);
        cxx = cx;
        flags |= coefficientSqr(cxx, ex);
        flags |= coefficientAdd(cr, er, sr, cxx, ex, false, mode);
        ++i;

        if (flags & ExceptionFlags.overflow)
            break;
    }

    while (i < x.length)
    {
        //infinity or overflow detected
        if (x[i].isSignalNaN)
        {
            result = D.nan;
            return ExceptionFlags.invalidOperation;
        }

        if (x[i].isNaN)
        {
            result = D.nan;
            return ExceptionFlags.none;
        }

        if (x[i].isInfinity)
            hasInfinity = true;
        ++i;
    }

    if (hasInfinity)
    {
        result = D.infinity;
        return ExceptionFlags.none;
    }

    flags |= coefficientAdjust(cr, er, cvt!T(DataType!D.max), sr, mode);
    return result.adjustedPack(cvt!(DataType!D)(cr), er, sr, precision, mode, flags);
}

ExceptionFlags decimalSub(D1, D2)(ref D1 x, auto const ref D2 y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!(D1, D2))
{
   return decimalAdd(x, -y, precision, mode);
}

ExceptionFlags decimalSub(D, T)(ref D x, auto const ref T y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    alias X = DataType!D;
    U cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            if (!y)
                return x.adjustedPack(cvt!X(cx), ex, sx, precision, mode, ExceptionFlags.none);
            bool sy;
            U cy = unsign!U(y, sy);
            auto flags = coefficientAdd(cx, ex, sx, cy, 0, !sy, RoundingMode.implicit);
            flags |= coefficientAdjust(cx, ex, cvt!U(X.max), sx, RoundingMode.implicit);
            return x.adjustedPack(cvt!X(cx), ex, sx, precision, mode, flags);
        case FastClass.zero:
            const flags = x.packIntegral(y, precision, mode);
            x = -x;
            return flags;
        case FastClass.infinite:
        case FastClass.quietNaN:
            return ExceptionFlags.none;
        case FastClass.signalingNaN:
            unsignalize(x);
            return ExceptionFlags.invalidOperation;
    }
}

ExceptionFlags decimalSub(D, F)(ref D x, auto const ref F y, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isFloatingPoint!F)
{
    return decimalAdd(x, -y, precision, mode);
}

ExceptionFlags decimalSub(T, D)(auto const ref T x, auto const ref D y, out D z, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isIntegral!T)
{
    z = -y;
    return decimalAdd(z, x, precision, mode);
}

ExceptionFlags decimalSub(F, D)(auto const ref F x, auto const ref D y, out D z, const(int) precision, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isDecimal!D && isFloatingPoint!F)
{
    z = -y;
    return decimalAdd(z, x, precision, mode);
}

ExceptionFlags decimalTan(D)(ref D x, const(int) precision, const(RoundingMode) mode)
if (isDecimal!D)
{
    DataType!D cx; int ex; bool sx;
    switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.signalingNaN:
            return ExceptionFlags.invalidOperation;
        case FastClass.infinite:
            x = sx ? -D.nan : D.nan;
            return ExceptionFlags.invalidOperation;
        case FastClass.quietNaN:
        case FastClass.zero:
            return ExceptionFlags.none;
        default:
            int quadrant;
            auto flags = coefficientCapAngle(cx, ex, sx, quadrant);
            DataType!D csin, ccos; int esin, ecos; bool ssin, scos;
            flags |= coefficientSinCosQ(cx, ex, sx, csin, esin, ssin, ccos, ecos, scos);
            switch (quadrant)
            {
                case 1:
                    //sin/cos, -sin/-cos
                case 3:
                    cx = csin; ex = esin; sx = ssin;
                    flags |= coefficientDiv(cx, ex, sx, ccos, ecos, scos, RoundingMode.implicit);
                    break;
                case 2:
                    //cos/-sin
                    cx = ccos; ex = ecos; sx = scos;
                    flags |= coefficientDiv(cx, ex, sx, csin, esin, !ssin, RoundingMode.implicit);
                    break;
                case 4://-cos/sin
                    cx = ccos; ex = ecos; sx = !scos;
                    flags |= coefficientDiv(cx, ex, sx, csin, esin, ssin, RoundingMode.implicit);
                    break;
                default:
                    assert(0);
            }
            return x.adjustedPack(cx, ex, sx, precision, mode, flags);
    }
}

ExceptionFlags decimalTanh(D)(ref D x, const(int) precision, const(RoundingMode) mode)
{
    if (x.isSignalNaN)
    {
        x = D.nan;
        return ExceptionFlags.invalidOperation;
    }

    if (x.isNaN)
        return ExceptionFlags.none;

    if (x.isInfinity)
    {
        x = signbit(x) ? -D.one : D.one;
        return ExceptionFlags.none;
    }

    if (x.isZero)
        return ExceptionFlags.none;

    Unqual!D x1 = x;
    Unqual!D x2 = -x;
    auto flags = decimalSinh(x1, 0, mode);
    flags |= decimalCosh(x2, 0, mode);
    x = x1;
    flags |= decimalDiv(x, x2, precision, mode);
    return flags;
}

ExceptionFlags exp2to10(RoundingMode mode = RoundingMode.implicit, U)(ref U coefficient, ref int exponent, const(bool) isNegative)
{
    enum maxMultiplicable = U.max / 5U;
    enum hibit = U(1U) << (U.sizeof * 8 - 1);
    ExceptionFlags flags;
    auto e5 = -exponent;

    if (e5 > 0)
    {
        const tz = ctz(coefficient);
        if (tz)
        {
            const shift = e5 > tz ? tz : e5;
            e5 -= shift;
            exponent += shift;
            coefficient >>= shift;
        }

        while (e5 > 0)
        {
            --e5;
            if (coefficient < maxMultiplicable)
                coefficient *= 5U;
            else
            {
                ++exponent;
                bool mustRound = cast(bool)(coefficient & 1U);
                coefficient >>= 1;
                if (mustRound)
                {
                    flags = ExceptionFlags.inexact;
                    static if (mode == RoundingMode.tiesToAway)
                    {
                        ++coefficient;
                    }
                    else static if (mode == RoundingMode.tiesToEven)
                    {
                        if ((coefficient & 1U))
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.towardNegative)
                    {
                        if (isNegative)
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.towardPositive)
                    {
                        if (!isNegative)
                            ++coefficient;
                    }
                }
            }
        }
    }

    if (e5 < 0)
    {
        const lz = clz(coefficient);
        if (lz)
        {
            const shift = -e5 > lz ? lz : -e5;
            exponent -= shift;
            e5 += shift;
            coefficient <<= shift;
        }

        while (e5 < 0)
        {
            ++e5;
            if (coefficient & hibit)
            {
                auto r = divrem(coefficient, 5U);
                if (r)
                {
                    flags = ExceptionFlags.inexact;
                    static if (mode == RoundingMode.towardNegative)
                    {
                        if (isNegative)
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.towardPositive)
                    {
                        if (!isNegative)
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.tiesToAway || mode == RoundingMode.tiesToEven)
                    {
                        if (r >= 3U)
                            ++coefficient;
                    }
                }
            }
            else
            {
                coefficient <<= 1;
                --exponent;
            }
        }
    }

    return flags;
}

ExceptionFlags exp10to2(RoundingMode mode = RoundingMode.implicit, U)(ref U coefficient, ref int exponent, const(bool) isNegative)
{
    enum maxMultiplicable = U.max / 5U;
    enum hibit = U(1U) << (U.sizeof * 8 - 1);
    ExceptionFlags flags;
    auto e5 = exponent;

    if (e5 > 0)
    {
        while (e5 > 0)
        {
            if (coefficient < maxMultiplicable)
            {
                --e5;
                coefficient *= 5U;
            }
            else
            {
                ++exponent;
                const bool mustRound = cast(bool)(coefficient & 1U);
                coefficient >>= 1;
                if (mustRound)
                {
                    flags = ExceptionFlags.inexact;
                    static if (mode == RoundingMode.tiesToAway)
                    {
                        ++coefficient;
                    }
                    else static if (mode == RoundingMode.tiesToEven)
                    {
                        if ((coefficient & 1U))
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.towardNegative)
                    {
                        if (isNegative)
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.towardPositive)
                    {
                        if (!isNegative)
                            ++coefficient;
                    }
                }
            }
        }
    }

    if (e5 < 0)
    {
        while (e5 < 0)
        {
            if (coefficient & hibit)
            {
                ++e5;
                auto r = divrem(coefficient, 5U);
                if (r)
                {
                    flags = ExceptionFlags.inexact;
                    static if (mode == RoundingMode.towardNegative)
                    {
                        if (isNegative)
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.towardPositive)
                    {
                        if (!isNegative)
                            ++coefficient;
                    }
                    else static if (mode == RoundingMode.tiesToAway || mode == RoundingMode.tiesToEven)
                    {
                        if (r >= 3U)
                            ++coefficient;
                    }
                }
            }
            else
            {
                coefficient <<= 1;
                --exponent;
            }
        }
    }

    return flags;
}

unittest
{
    uint cx = 3402823;
    int ex = 32;

    exp10to2!(RoundingMode.towardZero)(cx, ex, false);
}

//divides coefficient by 10^power
//inexact
ExceptionFlags divpow10(T)(ref T coefficient, const(int) power, const(bool) isNegative, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isAnyUnsignedBit!T)
in
{
    assert(power >= 0);
}
do
{
    if (coefficient == 0U)
        return ExceptionFlags.none;

    if (power == 0)
        return ExceptionFlags.none;

    Unqual!T remainder;

    if (power >= pow10!T.length)
    {
        remainder = coefficient;
        coefficient = 0U;
    }
    else
        remainder = divrem(coefficient, pow10!T[power]);

    if (remainder == 0U)
        return ExceptionFlags.none;

    const half = power >= pow10!T.length ? T.max : pow10!T[power] >>> 1;
    final switch (mode)
    {
        case RoundingMode.tiesToEven:
            if (remainder > half)
                ++coefficient;
            else if ((remainder == half) && ((coefficient & 1U) != 0U))
                ++coefficient;
            break;
        case RoundingMode.tiesToAway:
            if (remainder >= half)
                ++coefficient;
            break;
        case RoundingMode.towardNegative:
            if (isNegative)
                ++coefficient;
            break;
        case RoundingMode.towardPositive:
            if (!isNegative)
                ++coefficient;
            break;
        case RoundingMode.towardZero:
            break;
    }

    return ExceptionFlags.inexact;
}

unittest
{
    struct S {uint c; int p; bool n; RoundingMode r; uint outc; bool inexact; }

    S[] test =
    [
        S (0, 0, false, RoundingMode.tiesToAway, 0, false),
        S (0, 0, false, RoundingMode.tiesToEven, 0, false),
        S (0, 0, false, RoundingMode.towardNegative, 0, false),
        S (0, 0, false, RoundingMode.towardPositive, 0, false),
        S (0, 0, false, RoundingMode.towardZero, 0, false),

        S (10, 1, false, RoundingMode.tiesToAway, 1, false),
        S (10, 1, false, RoundingMode.tiesToEven, 1, false),
        S (10, 1, false, RoundingMode.towardNegative, 1, false),
        S (10, 1, false, RoundingMode.towardPositive, 1, false),
        S (10, 1, false, RoundingMode.towardZero, 1, false),

        S (13, 1, false, RoundingMode.tiesToAway, 1, true),
        S (13, 1, false, RoundingMode.tiesToEven, 1, true),
        S (13, 1, false, RoundingMode.towardNegative, 1, true),
        S (13, 1, false, RoundingMode.towardPositive, 2, true),
        S (13, 1, false, RoundingMode.towardZero, 1, true),

        S (13, 1, true, RoundingMode.tiesToAway, 1, true),
        S (13, 1, true, RoundingMode.tiesToEven, 1, true),
        S (13, 1, true, RoundingMode.towardNegative, 2, true),
        S (13, 1, true, RoundingMode.towardPositive, 1, true),
        S (13, 1, true, RoundingMode.towardZero, 1, true),

        S (15, 1, false, RoundingMode.tiesToAway, 2, true),
        S (15, 1, false, RoundingMode.tiesToEven, 2, true),
        S (15, 1, false, RoundingMode.towardNegative, 1, true),
        S (15, 1, false, RoundingMode.towardPositive, 2, true),
        S (15, 1, false, RoundingMode.towardZero, 1, true),

        S (15, 1, true, RoundingMode.tiesToAway, 2, true),
        S (15, 1, true, RoundingMode.tiesToEven, 2, true),
        S (15, 1, true, RoundingMode.towardNegative, 2, true),
        S (15, 1, true, RoundingMode.towardPositive, 1, true),
        S (15, 1, true, RoundingMode.towardZero, 1, true),

        S (18, 1, false, RoundingMode.tiesToAway, 2, true),
        S (18, 1, false, RoundingMode.tiesToEven, 2, true),
        S (18, 1, false, RoundingMode.towardNegative, 1, true),
        S (18, 1, false, RoundingMode.towardPositive, 2, true),
        S (18, 1, false, RoundingMode.towardZero, 1, true),

        S (18, 1, true, RoundingMode.tiesToAway, 2, true),
        S (18, 1, true, RoundingMode.tiesToEven, 2, true),
        S (18, 1, true, RoundingMode.towardNegative, 2, true),
        S (18, 1, true, RoundingMode.towardPositive, 1, true),
        S (18, 1, true, RoundingMode.towardZero, 1, true),

        S (25, 1, false, RoundingMode.tiesToAway, 3, true),
        S (25, 1, false, RoundingMode.tiesToEven, 2, true),
        S (25, 1, false, RoundingMode.towardNegative, 2, true),
        S (25, 1, false, RoundingMode.towardPositive, 3, true),
        S (25, 1, false, RoundingMode.towardZero, 2, true),

        S (25, 1, true, RoundingMode.tiesToAway, 3, true),
        S (25, 1, true, RoundingMode.tiesToEven, 2, true),
        S (25, 1, true, RoundingMode.towardNegative, 3, true),
        S (25, 1, true, RoundingMode.towardPositive, 2, true),
        S (25, 1, true, RoundingMode.towardZero, 2, true),
    ];

    foreach (ref s; test)
    {
        auto flags = divpow10(s.c, s.p, s.n, s.r);
        assert(s.c == s.outc);
        assert(flags == ExceptionFlags.inexact ? s.inexact : !s.inexact);
    }
}

//multiplies coefficient by 10^^power, returns possible overflow
ExceptionFlags mulpow10(T)(ref T coefficient, const(int) power) @safe pure nothrow @nogc
if (isAnyUnsignedBit!T)
in
{
    assert(power >= 0);
}
do
{
    if (coefficient == 0U || power == 0)
        return ExceptionFlags.none;
    if (power >= pow10!T.length || coefficient > maxmul10!T[power])
        return ExceptionFlags.overflow;
    coefficient *= pow10!T[power];
    return ExceptionFlags.none;
}

//inexact
ExceptionFlags exponentAlign(T)(ref T cx, ref int ex, const(bool) sx, ref T cy, ref int ey, const(bool) sy, const(RoundingMode) mode) @safe pure nothrow @nogc
out
{
    assert(ex == ey);
}
do
{
    if (ex == ey)
        return ExceptionFlags.none;

    if (!cx)
    {
        ex = ey;
        return ExceptionFlags.none;
    }

    if (!cy)
    {
        ey = ex;
        return ExceptionFlags.none;
    }

    ExceptionFlags flags;
    int dif = ex - ey;
    if (dif > 0) //ex > ey
    {
        coefficientExpand(cx, ex, dif);
        if (dif)
            flags = coefficientShrink(cy, ey, sy, dif, mode);
        assert(!dif);
    }
    else //ex < ey
    {
        dif = -dif;
        coefficientExpand(cy, ey, dif);
        if (dif)
            flags = coefficientShrink(cx, ex, sx, dif, mode);
        assert(!dif);
    }
    return flags;
}

//adjusts coefficient to fit minExponent <= exponent <= maxExponent and coefficient <= maxCoefficient
//inexact, overflow, underflow
ExceptionFlags coefficientAdjust(T)(ref T coefficient, ref int exponent, const(int) minExponent, const(int) maxExponent,
    const(T) maxCoefficient, const(bool) isNegative, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isAnyUnsignedBit!T)
in
{
    assert(minExponent <= maxExponent);
    assert(maxCoefficient >= 1U);
}
do
{
    if (coefficient == 0U)
    {
        if (exponent < minExponent)
            exponent = minExponent;
        if (exponent > maxExponent)
            exponent = maxExponent;
        return ExceptionFlags.none;
    }

    ExceptionFlags flags;

    if (exponent < minExponent)
    {
        //increase exponent, divide coefficient
        const dif = minExponent - exponent;
        flags = divpow10(coefficient, dif, isNegative, mode);
        if (coefficient == 0U)
            flags |= ExceptionFlags.underflow | ExceptionFlags.inexact;
        exponent += dif;
    }
    else if (exponent > maxExponent)
    {
        //decrease exponent, multiply coefficient
        const dif = exponent - maxExponent;
        flags = mulpow10(coefficient, dif);
        if (flags & ExceptionFlags.overflow)
            return flags | ExceptionFlags.inexact;
        else
            exponent -= dif;
    }

    if (coefficient > maxCoefficient)
    {
        //increase exponent, divide coefficient
        auto dif = prec(coefficient) - prec(maxCoefficient);
        if (!dif)
            dif = 1;
        flags |= divpow10(coefficient, dif, isNegative, mode);
        if (coefficient > maxCoefficient)
        {
            //same precision but greater
            flags |= divpow10(coefficient, 1, isNegative, mode);
            ++dif;
        }
        if (cappedAdd(exponent, dif) != dif)
        {
            if (coefficient != 0U)
                return flags | ExceptionFlags.overflow | ExceptionFlags.inexact;
        }
    }

    //coefficient became 0, dont' bother with exponents;
    if (coefficient == 0U)
    {
        exponent = 0;
        if (exponent < minExponent)
            exponent = minExponent;
        if (exponent > maxExponent)
            exponent = maxExponent;
        return flags;
    }

    if (exponent < minExponent)
        return flags | ExceptionFlags.underflow | ExceptionFlags.inexact;

    if (exponent > maxExponent)
        return flags | ExceptionFlags.overflow | ExceptionFlags.inexact;

    return flags;
}

//adjusts coefficient to fit minExponent <= exponent <= maxExponent
//inexact, overflow, underflow
ExceptionFlags coefficientAdjust(T)(ref T coefficient, ref int exponent, const(int) minExponent, const(int) maxExponent,
    const(bool) isNegative, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isAnyUnsignedBit!T)
in
{
    assert(minExponent <= maxExponent);
}
do
{
    return coefficientAdjust(coefficient, exponent, minExponent, maxExponent, T.max, isNegative, mode);
}

//adjusts coefficient to fit coefficient in maxCoefficient
//inexact, overflow, underflow
ExceptionFlags coefficientAdjust(T)(ref T coefficient, ref int exponent, const(T) maxCoefficient,
    const(bool) isNegative, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isAnyUnsignedBit!T)
in
{
    assert(maxCoefficient >= 1U);
}
do
{
    return coefficientAdjust(coefficient, exponent, int.min, int.max, maxCoefficient, isNegative, mode);
}

//adjusts coefficient to fit minExponent <= exponent <= maxExponent and to fit precision
//inexact, overflow, underflow
ExceptionFlags coefficientAdjust(T)(ref T coefficient, ref int exponent, const(int) minExponent, const(int) maxExponent,
    const(int) precision, const(bool) isNegative, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isAnyUnsignedBit!T)
in
{
    assert(precision >= 1);
    assert(minExponent <= maxExponent);
}
do
{
    const maxCoefficient = precision >= pow10!T.length ? T.max : pow10!T[precision] - 1U;
    auto flags = coefficientAdjust(coefficient, exponent, minExponent, maxExponent, maxCoefficient, isNegative, mode);
    if (flags & (ExceptionFlags.overflow | ExceptionFlags.underflow))
        return flags;

    const p = prec(coefficient);
    if (p > precision)
    {
        flags |= divpow10(coefficient, 1, isNegative, mode);
        if (coefficient == 0U)
        {
            exponent = 0;
            if (exponent < minExponent)
                exponent = minExponent;
            if (exponent > maxExponent)
                exponent = maxExponent;
            return flags;
        }
        else
        {
            if (cappedAdd(exponent, 1) != 1)
                return flags | ExceptionFlags.overflow;
            if (exponent > maxExponent)
                return flags | ExceptionFlags.overflow;
        }
    }
    return flags;
}

//adjusts coefficient to fit precision
//inexact, overflow, underflow
ExceptionFlags coefficientAdjust(T)(ref T coefficient, ref int exponent,
    const(int) precision, const(bool) isNegative, const(RoundingMode) mode) @safe pure nothrow @nogc
if (isAnyUnsignedBit!T)
in
{
    assert(precision >= 1);
}
do
{
    return coefficientAdjust(coefficient, exponent, int.min, int.max, precision, isNegative, mode);
}

//caps angle to -2π ... +2π
ExceptionFlags coefficientCapAngle(T)(ref T cx, ref int ex, ref bool sx) @safe pure nothrow @nogc
{
    if (coefficientCmp(cx, ex, Constants!T.c2π, Constants!T.e2π) > 0)
    {
        alias U = makeUnsignedBit!(T.sizeof * 16);
        U cxx = cx;
        auto flags = coefficientMod2PI(cxx, ex);
        flags |= coefficientAdjust(cxx, ex, cvt!U(T.max), sx, RoundingMode.implicit);
        cx = cvt!T(cxx);
    }
    return ExceptionFlags.none;
}

//caps angle to -π/2  .. +π/2
ExceptionFlags coefficientCapAngle(T)(ref T cx, ref int ex, ref bool sx, out int quadrant) @safe pure nothrow @nogc
{
    quadrant = 1;
    if (coefficientCmp(cx, ex, Constants!T.cπ_2, Constants!T.eπ_2) > 0)
    {
        ExceptionFlags flags;
        if (coefficientCmp(cx, ex, Constants!T.c2π, Constants!T.e2π) > 0)
        {
            alias U = makeUnsignedBit!(T.sizeof * 16);
            U cxx = cx;
            flags = coefficientMod2PI(cxx, ex);
            flags |= coefficientAdjust(cxx, ex, cvt!U(T.max), sx, RoundingMode.implicit);
            cx = cvt!T(cxx);
            if (coefficientCmp(cx, ex, Constants!T.cπ_2, Constants!T.eπ_2) <= 0)
                return flags;
        }
        Unqual!T cy = cx;
        int ey = ex;
        bool sy = sx;
        flags |= coefficientMul(cy, ey, sy, Constants!T.c2_π, Constants!T.e2_π, false, RoundingMode.towardZero);
        flags |= coefficientRound(cy, ey, sy, RoundingMode.towardZero);
        quadrant = cast(uint)(cy % 4U) + 1;
        flags |= coefficientMul(cy, ey, sy, Constants!T.cπ_2, Constants!T.eπ_2, false, RoundingMode.implicit);
        flags |= coefficientAdd(cx, ex, sx, cy, ey, !sy, RoundingMode.implicit);
        return flags;
    }
    return ExceptionFlags.none;
}

//expands cx with 10^^target if possible
void coefficientExpand(T)(ref T cx, ref int ex, ref int target) @safe pure nothrow @nogc
in
{
    assert(cx);
    assert(target > 0);
}
do
{
    const int px = prec(cx);
    int maxPow10 = cast(int)pow10!T.length - px;
    const maxCoefficient = maxmul10!T[$ - px];
    if (cx > maxCoefficient)
        --maxPow10;
    auto pow = target > maxPow10 ? maxPow10 : target;
    pow = cappedSub(ex, pow);
    if (pow)
    {
        cx *= pow10!T[pow];
        target -= pow;
    }
}

//expands cx to maximum available digits
void coefficientExpand(T)(ref T cx, ref int ex) @safe pure nothrow @nogc
{
    if (cx)
    {
        const int px = prec(cx);
        int pow = cast(int)pow10!T.length - px;
        const maxCoefficient = maxmul10!T[$ - px];
        if (cx > maxCoefficient)
            --pow;
        pow = cappedSub(ex, pow);
        if (pow)
        {
            cx *= pow10!T[pow];
        }
    }
}

unittest
{
    struct S {uint x1; int ex1; int target1; uint x2; int ex2; int target2; }
    S[] tests =
    [
        S(1, 0, 4, 10000, -4, 0),
        S(429496729, 0, 1, 4294967290, -1, 0),
        S(429496739, 0, 1, 429496739, 0, 1),
        S(429496729, 0, 2, 4294967290, -1, 1),
        S(42949672, 0, 1, 429496720, -1, 0),
        S(42949672, 0, 2, 4294967200, -2, 0),
        S(42949672, 0, 3, 4294967200, -2, 1),
    ];

    foreach ( s; tests)
    {
        coefficientExpand(s.x1, s.ex1, s.target1);
        assert(s.x1 == s.x2);
        assert(s.ex1 == s.ex2);
        assert(s.target1 == s.target2);
    }
}

ExceptionFlags coefficientFrac(T)(ref T cx, ref int ex)
{
    if (ex >= 0)
    {
        cx = 0U;
        ex = 0;
        return ExceptionFlags.none;
    }
    const p = prec(cx);
    if (ex < -p)
       return ExceptionFlags.none;
    cx %= pow10!T[-ex];
    return ExceptionFlags.none;
}

//shrinks coefficient by cutting out terminating zeros and increasing exponent
void coefficientShrink(T)(ref T coefficient, ref int exponent) @safe pure nothrow @nogc
{
    if (coefficient > 9U && (coefficient & 1U) == 0U && exponent < int.max)
    {
        Unqual!T c = coefficient;
        Unqual!T r = divrem(c, 10U);
        int e = exponent + 1;
        while (r == 0U)
        {
            coefficient = c;
            exponent = e;
            if ((c & 1U) || e == int.max)
                break;
            r = divrem(c, 10U);
            ++e;
        }
    }
}

//shrinks cx with 10^^target
//inexact
ExceptionFlags coefficientShrink(T)(ref T cx, ref int ex, const(bool) sx, ref int target, const(RoundingMode) mode) @safe pure nothrow @nogc
in
{
    assert(cx);
    assert(target > 0);
}
do
{
    const pow = cappedAdd(ex, target);
    if (pow)
    {
        const flags = divpow10(cx, pow, sx, mode);
        target -= pow;
        return flags;
    }
    else
        return ExceptionFlags.none;
}
