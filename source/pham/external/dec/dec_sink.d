module pham.external.dec.sink;

import std.format : FormatSpec;
import std.traits : isSomeChar, Unqual;

import pham.external.dec.integral : divrem, isAnyUnsigned, prec;

nothrow @safe:

template ToStringSink(C)
{
    alias ToStringSink = void delegate(scope const(C)[]) nothrow @safe;
}

package(pham.external.dec):

//dumps value to buffer right aligned, assumes buffer has enough space
int dumpUnsigned(C, T)(C[] buffer, auto const ref T value) pure
if (isSomeChar!C && isAnyUnsigned!T)
in
{
    assert(buffer.length < int.max);
    assert(buffer.length >  0 && buffer.length >= prec(value));
}
do
{
    auto i = buffer.length;
    Unqual!T v = value;
    do
    {
        auto r = divrem(v, 10U);
        buffer[--i] = cast(C)(r + cast(uint)'0');
    } while (v);
    return cast(int)(buffer.length - i);
}

immutable char[] loHexChars = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];
immutable char[] upHexChars = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'];

//dumps value to buffer right aligned, assumes buffer has enough space
int dumpUnsignedHex(C, T)(C[] buffer, auto const ref T value, const bool uppercase = true) pure
if (isSomeChar!C && isAnyUnsigned!T)
in
{
    assert(buffer.length < int.max);
    assert(buffer.length > 0 && buffer.length >= prec(value));
}
do
{
    const chars = uppercase ? upHexChars : loHexChars;
    auto i = buffer.length;
    Unqual!T v = value;
    do
    {
        const digit = (cast(uint)v & 0xFU);
        buffer[--i] = cast(C)(chars[digit]);
        v >>= 4;
    } while (v);
    return cast(int)(buffer.length - i);
}

//repeats sinking of value count times using a default buffer size of 16
void sinkRepeat(C)(scope ToStringSink!C sink, const C value, int count)
if (isSomeChar!C)
{
    if (count <= 0)
        return;

    enum bufferSize = 16;
    Unqual!C[bufferSize] buffer = value;
    while (count > 0)
    {
        const n = count > bufferSize ? bufferSize : count;
        sink(buffer[0..n]);
        count -= n;
    }
}

//sinks +/-/space
void sinkSign(C)(scope ToStringSink!C sink, auto const ref FormatSpec!C spec, const bool signed)
if (isSomeChar!C)
{
    if (!signed && spec.flPlus)
        sink("+");
    else if (!signed && spec.flSpace)
        sink(" ");
    else if (signed)
        sink("-");
}

//pads left according to spec
void sinkPadLeft(C)(scope ToStringSink!C sink, auto const ref FormatSpec!C spec, ref int pad)
if (isSomeChar!C)
{
    if (pad > 0 && !spec.flDash && !spec.flZero)
    {
        sinkRepeat!C(sink, ' ', pad);
        pad = 0;
    }
}

//zero pads left according to spec
void sinkPadZero(C)(scope ToStringSink!C sink, auto const ref FormatSpec!C spec, ref int pad)
if (isSomeChar!C)
{
    if (pad > 0 && spec.flZero && !spec.flDash)
    {
        sinkRepeat!C(sink, '0', pad);
        pad = 0;
    }
}

//pads right according to spec
void sinkPadRight(C)(scope ToStringSink!C sink, ref int pad)
if (isSomeChar!C)
{
    if (pad > 0)
    {
        sinkRepeat!C(sink, ' ', pad);
        pad = 0;
    }
}

//sinks +/-(s)nan;
void sinkNaN(C, T)(scope ToStringSink!C sink, auto const ref FormatSpec!C spec, const bool signed,
    const bool signaling, T payload, bool hex)
if (isSomeChar!C)
{
    C[250] buffer;
    FormatSpec!C nanspec = spec;
    nanspec.flZero = false;
    nanspec.flHash = false;
    ptrdiff_t digits;
    if (payload)
    {
        if (hex)
            digits = dumpUnsignedHex(buffer, payload, nanspec.spec < 'Z');
        else
            digits = dumpUnsigned(buffer, payload);
    }
    int w = signaling ? 4 : 3;
    if (payload)
    {
        if (hex)
            w += digits + 4;
        else
            w += digits + 2;
    }
    if (nanspec.flPlus || nanspec.flSpace || signed)
        ++w;
    int pad = nanspec.width - w;
    sinkPadLeft!C(sink, nanspec, pad);
    sinkSign!C(sink, nanspec, signed);
    if (signaling)
        sink(nanspec.spec < 'Z' ? "S" : "s");
    sink(nanspec.spec < 'Z' ? "NAN" : "nan");
    if (payload)
    {
        sink("[");
        if (hex)
        {
            sink("0");
            sink(nanspec.spec < 'Z' ? "X" : "x");
        }
        sink(buffer[$ - digits .. $ - 1]);
        sink("]");
    }
    sinkPadRight!C(sink, pad);
}

//sinks +/-(s)inf;
void sinkInfinity(C)(scope ToStringSink!C sink, auto const ref FormatSpec!C spec, const bool signed)
if (isSomeChar!C)
{
    FormatSpec!C infspec = spec;
    infspec.flZero = false;
    infspec.flHash = false;
    const w = infspec.flPlus || infspec.flSpace || signed ? 4 : 3;
    int pad = infspec.width - w;
    sinkPadLeft!C(sink, infspec, pad);
    sinkSign!C(sink, infspec, signed);
    sink(infspec.spec < 'Z' ? "INF" : "inf");
    sinkPadRight!C(sink, pad);
}

//sinks 0
void sinkZero(C)(scope ToStringSink!C sink, auto const ref FormatSpec!C spec, const bool signed,
    const bool skipTrailingZeros = false)
if (isSomeChar!C)
{
    const int requestedDecimals = skipTrailingZeros
        ? 0
        : (spec.precision == spec.UNSPECIFIED || spec.precision < 0 ? 6 : spec.precision);

    int w = requestedDecimals == 0 ? 1 : requestedDecimals + 2;
    if (requestedDecimals == 0 && spec.flHash)
        ++w;
    if (spec.flPlus || spec.flSpace || signed)
        ++w;
    int pad = spec.width - w;
    sinkPadLeft!C(sink, spec, pad);
    sinkSign!C(sink, spec, signed);
    sinkPadZero!C(sink, spec, pad);
    sink("0");
    if (requestedDecimals || spec.flHash)
    {
        sink(".");
        sinkRepeat!C(sink, '0', requestedDecimals);
    }
    sinkPadRight!C(sink, pad);
}
