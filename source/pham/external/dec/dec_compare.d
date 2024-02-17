module pham.external.dec.dec_compare;

import std.math: isInfinity, isNaN, signStd = signbit;
import std.traits: isFloatingPoint, isIntegral, isUnsigned, Unqual;

import pham.external.dec.dec_decimal : CommonDecimal, CommonStorage,
    Decimal, Decimal32, Decimal64, Decimal128,
    fastDecode, isDecimal, signDec = signbit;
import pham.external.dec.dec_integral : pow10, prec, unsign;
import pham.external.dec.dec_math : mulpow10;
import pham.external.dec.dec_sink : dataTypeToString;
import pham.external.dec.dec_type;

//enum nanResult = -2;
//enum signalNaNResult = -3;

nothrow @safe:
package(pham.external.dec):

alias signbit = signDec;
alias signbit = signStd;

float decimalCmp(D1, D2)(auto const ref D1 x, auto const ref D2 y) @safe pure nothrow @nogc
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    DataType!(D.sizeof) cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    final switch(fx)
    {
        case FastClass.finite:
            if (fy == FastClass.finite)
                return coefficientCmp(cx, ex, sx, cy, ey, sy);
            if (fy == FastClass.zero)
                return sx ? -1: 1;
            if (fy == FastClass.infinite)
                return sy ? 1 : -1;
            //return fy == FastClass.signalingNaN ? signalNaNResult : nanResult;
            return float.nan;
        case FastClass.zero:
            if (fy == FastClass.finite || fy == FastClass.infinite)
                return sy ? 1 : -1;
            if (fy == FastClass.zero)
                return 0;
            //return fy == FastClass.signalingNaN ? signalNaNResult : nanResult;
            return float.nan;
        case FastClass.infinite:
            if (fy == FastClass.finite || fy == FastClass.zero)
                return sx ? -1 : 1;
            if (fy == FastClass.infinite)
                return sx == sy ? 0 : (sx ? -1 : 1);
            //return fy == FastClass.signalingNaN ? signalNaNResult : nanResult;
            return float.nan;
        case FastClass.quietNaN:
            //return fy == FastClass.signalingNaN ? signalNaNResult : nanResult;
            return float.nan;
        case FastClass.signalingNaN:
            //return signalNaNResult;
            return float.nan;
    }
}

float decimalCmp(D, T)(auto const ref D x, auto const ref T y) @safe pure nothrow @nogc
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);
    U cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            bool sy;
            const cy = unsign!U(y, sy);
            return coefficientCmp(cx, ex, sx, cy, 0, sy);
        case FastClass.zero:
            static if (isUnsigned!T)
                return y == 0 ? 0 : -1;
            else
                return y == 0 ? 0 : (y < 0 ? 1 : -1);
        case FastClass.infinite:
            return sx ? -1 : 1;
        case FastClass.quietNaN:
            //return nanResult;
            return float.nan;
        case FastClass.signalingNaN:
            //return signalNaNResult;
            return float.nan;
    }
}

float decimalCmp(D, F)(auto const ref D x, auto const ref F y, const(int) yPrecision, const(RoundingMode) yMode, const(int) yMaxFractionalDigits) @safe pure nothrow @nogc
if (isDecimal!D && isFloatingPoint!F)
{
    if (x.isSignalNaN)
        //return signalNaNResult;
        return float.nan;
    if (x.isNaN || y.isNaN)
        //return nanResult;
        return float.nan;

    const sx = cast(bool)signbit(x);
    const sy = cast(bool)signbit(y);

    if (x.isZero)
    {
        if (y == 0.0)
            return 0;
        return sy ? 1 : -1;
    }

    if (y == 0.0)
        return sx ? -1 : 1;

    if (sx != sy)
        return sx ? -1 : 1;

    if (x.isInfinity)
    {
        if (y.isInfinity)
            return 0;
        return sx ? -1 : 1;
    }

    if (y.isInfinity)
        return sx ? 1 : -1;

    Unqual!D v = void;
    const flags = v.packFloatingPoint(y, yPrecision, yMode, yMaxFractionalDigits);
    if (flags & ExceptionFlags.overflow)
    {
        //floating point is too big
        return sx ? 1 : -1;
    }
    else if (flags & ExceptionFlags.underflow)
    {
        //floating point is too small
        return sx ? -1 : 1;
    }

    const result = decimalCmp(x, v);

    version(none)
    if (result == 0 && (flags & ExceptionFlags.inexact))
    {
        //seems equal, but float was truncated toward zero, so it's smaller
        return sx ? -1 : 1;
    }

    return result;
}

int coefficientCmp(T)(const T cx, const(int) ex, const(bool) sx, const(T) cy, const(int) ey, const(bool) sy) @safe pure nothrow @nogc
{
    // Either number is zero
    if (!cx)
        return cy ? (sy ? 1 : -1) : 0;
    else if (!cy)
        return sx ? -1 : 1;

    // Not same sign
    if (sx && !sy)
        return -1;
    else if (!sx && sy)
        return 1;

    return sx ? -coefficientCmp(cx, ex, cy, ey) : coefficientCmp(cx, ex, cy, ey);
}

int coefficientCmp(T)(const T cx, const(int) ex, const(T) cy, const(int) ey) @safe pure nothrow @nogc
{
    // Either number is zero
    if (!cx)
        return cy ? -1 : 0;
    else if (!cy)
        return 1;

    const int px = prec(cx);
    const int py = prec(cy);

    if (px > py)
    {
        const int eyy = ey - (px - py);

        if (ex > eyy)
            return 1;
        else if (ex < eyy)
            return -1;

        Unqual!T cyy = cy;
        mulpow10(cyy, px - py);

        if (cx > cyy)
            return 1;
        else if (cx < cyy)
            return -1;
        else
            return 0;
    }

    if (px < py)
    {
        const int exx = ex - (py - px);

        if (exx > ey)
            return 1;
        else if (exx < ey)
            return -1;

        Unqual!T cxx = cx;
        mulpow10(cxx, py - px);
         if (cxx > cy)
            return 1;
        else if (cxx < cy)
            return -1;
        else
            return 0;
    }

    // Not same exponent
    if (ex > ey)
        return 1;
    else if (ex < ey)
        return -1;

    if (cx > cy)
        return 1;
    else if (cx < cy)
        return -1;
    else
        return 0;
}

float decimalEqu(D1, D2)(auto const ref D1 x, auto const ref D2 y) @safe pure nothrow @nogc
if (isDecimal!(D1, D2))
{
    alias D = CommonDecimal!(D1, D2);
    DataType!(D.sizeof) cx, cy; int ex, ey; bool sx, sy;
    const fx = fastDecode(x, cx, ex, sx);
    const fy = fastDecode(y, cy, ey, sy);

    final switch(fx)
    {
        case FastClass.finite:
            if (fy == FastClass.finite)
                return coefficientEqu(cx, ex, sx, cy, ey, sy);
            if (fy == FastClass.zero || fy == FastClass.infinite)
                return 0;
            //return fy == FastClass.signalingNaN ? signalNaNResult : nanResult;
            return float.nan;
        case FastClass.zero:
            if (fy == FastClass.zero)
                return 1;
            if (fy == FastClass.finite || fy == FastClass.infinite)
                return 0;
            //return fy == FastClass.signalingNaN ? signalNaNResult : nanResult;
            return float.nan;
        case FastClass.infinite:
            if (fy == FastClass.infinite)
                return sx == sy ? 1 : 0;
            if (fy == FastClass.finite || fy == FastClass.zero)
                return 0;
            //return fy == FastClass.signalingNaN ? signalNaNResult : nanResult;
            return float.nan;
        case FastClass.quietNaN:
            //return fy == FastClass.signalingNaN ? signalNaNResult : nanResult;
            return float.nan;
        case FastClass.signalingNaN:
            //return signalNaNResult;
            return float.nan;
    }
}

float decimalEqu(D, T)(auto const ref D x, auto const ref T y) @safe pure nothrow @nogc
if (isDecimal!D && isIntegral!T)
{
    alias U = CommonStorage!(D, T);

    U cx; int ex; bool sx;
    final switch(fastDecode(x, cx, ex, sx))
    {
        case FastClass.finite:
            bool sy;
            const cy = unsign!U(y, sy);
            return coefficientEqu(cx, ex, sx, cy, 0, sy) ? 1 : 0;
        case FastClass.zero:
            return y == 0 ? 1 : 0;
        case FastClass.infinite:
            return 0;
        case FastClass.quietNaN:
            //return nanResult;
            return float.nan;
        case FastClass.signalingNaN:
            //return signalNaNResult;
            return float.nan;
    }
}

float decimalEqu(D, F)(auto const ref D x, auto const ref F y, const(int) yPrecision, const(RoundingMode) yMode, const(int) yMaxFractionalDigits) @safe pure nothrow @nogc
if (isDecimal!D && isFloatingPoint!F)
{
    if (x.isSignalNaN)
        //return signalNaNResult;
        return float.nan;
    if (x.isNaN || y.isNaN)
        //return nanResult;
        return float.nan;
    if (x.isZero)
        return y == 0.0 ? 1 : 0;
    if (y == 0.0)
        return 0;

    const sx = cast(bool)signbit(x);
    const sy = cast(bool)signbit(y);
    if (sx != sy)
        return 0;

    if (x.isInfinity)
        return y.isInfinity ? 1 : 0;
    if (y.isInfinity)
        return 0;

    Unqual!D v = void;
    const flags = v.packFloatingPoint(y, yPrecision, yMode, yMaxFractionalDigits);
    if (flags)
        return 0;
    else
        return decimalEqu(x, v);
}

bool coefficientEqu(T)(const T cx, const(int) ex, const(bool) sx, const(T) cy, const(int) ey, const(bool) sy) @safe pure nothrow @nogc
{
    // Zero?
    if (!cx)
        return cy == 0U;

    // Sign diffference?
    if (sx != sy)
        return false;

    const int px = prec(cx);
    const int py = prec(cy);

    if (px > py)
    {
        int eyy = ey - (px - py);

        if (ex != eyy)
            return false;
        Unqual!T cyy = cy;
        mulpow10(cyy, px - py);

        return cx == cyy;
    }

    if (px < py)
    {
        int exx = ex - (py - px);

        if (exx != ey)
            return false;
        Unqual!T cxx = cx;
        mulpow10(cxx, py - px);
        return cxx == cy;
    }

    return cx == cy && ex == ey;
}

//same as coefficientEqu, but we ignore the last digit if coefficient > 10^max
//this is useful in convergence loops to not become infinite
bool coefficientApproxEqu(T)(const T cx, const(int) ex, const(bool) sx, const(T) cy, const(int) ey, const(bool) sy) @safe pure nothrow @nogc
{
    // Zero?
    if (!cx)
        return cy == 0U;

    // Sign diffference?
    if (sx != sy)
        return false;

    const int px = prec(cx);
    const int py = prec(cy);

    if (px > py)
    {
        const int eyy = ey - (px - py);
        if (ex != eyy)
            return false;
        Unqual!T cyy = cy;
        mulpow10(cyy, px - py);
        if (cx > pow10!T[$ - 2])
            return cx >= cy ? (cx - cy < 10U) : (cy - cx < 10U);
        return cx == cy;
    }

    if (px < py)
    {
        const int exx = ex - (py - px);
        if (exx != ey)
            return false;
        Unqual!T cxx = cx;
        mulpow10(cxx, py - px);
        if (cxx > pow10!T[$ - 2])
            return cxx >= cy ? (cxx - cy < 10U) : (cy - cxx < 10U);
        return cx == cy;
    }

    if (cx > pow10!T[$ - 2])
        return cx >= cy ? (cx - cy < 10U) : (cy - cx < 10U);

    return cx == cy;
}
