/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.db.convert;

import core.time : convert, dur;
import std.conv : to;
import std.exception : assumeWontThrow;
import std.math : abs, pow;
import std.system : Endian;
import std.traits: isIntegral, isUnsigned, Unqual;

version (unittest) import pham.utl.test;
import pham.utl.datetime.tick : Tick;
import pham.db.type;

nothrow @safe:

Duration rangeDuration(Duration value,
    const(int64) minSecond = 0, const(int64) maxSecond = int32.max) pure
{
    const totalSeconds = value.total!"seconds"();
    return totalSeconds >= minSecond && totalSeconds <= maxSecond
        ? value
        : (totalSeconds < minSecond ? dur!"seconds"(minSecond) : dur!"seconds"(maxSecond));
}

int64 removeUnitsFromHNSecs(string units)(int64 hnsecs) pure
if (units == "weeks" || units == "days"
    || units == "hours" || units == "minutes" || units == "seconds"
    || units == "msecs" || units == "usecs" || units == "hnsecs")
{
    const value = convert!("hnsecs", units)(hnsecs);
    return hnsecs - convert!(units, "hnsecs")(value);
}

Duration removeDatePart(scope const(Duration) value) pure
{
    auto hnsecs = removeUnitsFromHNSecs!"days"(value.total!"hnsecs");
    if (hnsecs < 0)
        hnsecs += hnsecsPerDay;
    return dur!"hnsecs"(hnsecs);
}

Duration secondToDuration(const(char)[] validSecondStr) pure
{
    return dur!"seconds"(toInteger!int64(validSecondStr));
}

D toDecimal(D)(const(char)[] validDecimalStr)
if (isDecimal!D)
{
    return assumeWontThrow(D(validDecimalStr));
}

I toInteger(I)(scope const(char)[] validIntegerStr, I emptyIntegerValue = 0) pure
if (is(I == int) || is(I == uint)
    || is(I == long) || is(I == ulong)
    || is(I == short) || is(I == ushort))
{
    return validIntegerStr.length != 0 ? assumeWontThrow(to!I(validIntegerStr)) : emptyIntegerValue;
}

int64 toRangeSecond64(scope const(Duration) value,
    const(int64) minSecond = 0, const(int64) maxSecond = int32.max) pure
{
    const totalSeconds = value.total!"seconds"();
    return totalSeconds >= minSecond && totalSeconds <= maxSecond
        ? totalSeconds
        : (totalSeconds < minSecond ? minSecond : maxSecond);
}

int32 toRangeSecond32(scope const(Duration) value,
    const(int32) minSecond = 0, const(int32) maxSecond = int32.max) pure
{
    const totalSeconds = value.total!"seconds"();
    return totalSeconds >= minSecond && totalSeconds <= maxSecond
        ? cast(int32)totalSeconds
        : (totalSeconds < minSecond ? minSecond : maxSecond);
}

string toString(C)(C c) pure
if (is(C == char) || is(C == wchar) || is(C == dchar))
{
    return assumeWontThrow(to!string(c));
}

string toString(S)(S s) pure
if (is(S == wstring) || is(S == dstring))
{
    return assumeWontThrow(to!string(s));
}

string toString(I)(I i) pure
if (isIntegral!I)
{
    return to!string(i);
}

pragma(inline, true)
T uintDecode(T, Endian EndianKind)(scope const(ubyte)[] v)
if (isUnsigned!T && T.sizeof > 1)
in
{
    assert(v.length == T.sizeof);
}
do
{
    T result = void;

    static if (T.sizeof == 4)
    {
        static if (EndianKind == Endian.littleEndian)
            result = v[0]
                | (cast(T)v[1] << 8)
                | (cast(T)v[2] << 16)
                | (cast(T)v[3] << 24);
        else
            result = (cast(T)v[0] << 24)
                | (cast(T)v[1] << 16)
                | (cast(T)v[2] << 8)
                | v[3];
    }
    else static if (T.sizeof == 8)
    {
        static if (EndianKind == Endian.littleEndian)
            result = v[0]
                | (cast(T)v[1] << 8)
                | (cast(T)v[2] << 16)
                | (cast(T)v[3] << 24)
                | (cast(T)v[4] << 32)
                | (cast(T)v[5] << 40)
                | (cast(T)v[6] << 48)
                | (cast(T)v[7] << 56);
        else
            result = (cast(T)v[0] << 56)
                | (cast(T)v[1] << 48)
                | (cast(T)v[2] << 40)
                | (cast(T)v[3] << 32)
                | (cast(T)v[4] << 24)
                | (cast(T)v[5] << 16)
                | (cast(T)v[6] << 8)
                | v[7];
    }
    else static if (T.sizeof == 2)
    {
        static if (EndianKind == Endian.littleEndian)
            result = v[0]
                | (cast(T)v[1] << 8);
        else
            result = (cast(T)v[0] << 8)
                | v[1];
    }
    else
    {
        static assert(0, "Unsupport " ~ T.stringof);
    }

    version (BigEndian)
    static if (EndianKind == Endian.littleEndian)
        result = swapEndian(result);

    return result;
}

pragma(inline, true)
ubyte[T.sizeof] uintEncode(T, Endian EndianKind)(T v)
if (isUnsigned!T && T.sizeof > 1)
{
    ubyte[T.sizeof] result = void;
    auto uv = cast(Unqual!T)v;

    version (BigEndian)
    static if (EndianKind == Endian.littleEndian)
        uv = swapEndian(uv);

    static if (T.sizeof == 4)
    {
        static if (EndianKind == Endian.littleEndian)
        {
            result[0] = uv & 0xFF;
            result[1] = (uv >> 8) & 0xFF;
            result[2] = (uv >> 16) & 0xFF;
            result[3] = (uv >> 24) & 0xFF;
        }
        else
        {
            result[0] = (uv >> 24) & 0xFF;
            result[1] = (uv >> 16) & 0xFF;
            result[2] = (uv >> 8) & 0xFF;
            result[3] = uv & 0xFF;
        }
    }
    else static if (T.sizeof == 8)
    {
        static if (EndianKind == Endian.littleEndian)
        {
            result[0] = uv & 0xFF;
            result[1] = (uv >> 8) & 0xFF;
            result[2] = (uv >> 16) & 0xFF;
            result[3] = (uv >> 24) & 0xFF;
            result[4] = (uv >> 32) & 0xFF;
            result[5] = (uv >> 40) & 0xFF;
            result[6] = (uv >> 48) & 0xFF;
            result[7] = (uv >> 56) & 0xFF;
        }
        else
        {
            result[0] = (uv >> 56) & 0xFF;
            result[1] = (uv >> 48) & 0xFF;
            result[2] = (uv >> 40) & 0xFF;
            result[3] = (uv >> 32) & 0xFF;
            result[4] = (uv >> 24) & 0xFF;
            result[5] = (uv >> 16) & 0xFF;
            result[6] = (uv >> 8) & 0xFF;
            result[7] = uv & 0xFF;
        }
    }
    else static if (T.sizeof == 2)
    {
        static if (EndianKind == Endian.littleEndian)
        {
            result[0] = uv & 0xFF;
            result[1] = (uv >> 8) & 0xFF;
        }
        else
        {
            result[0] = (uv >> 8) & 0xFF;
            result[1] = uv & 0xFF;
        }
    }
    else
    {
        static assert(0, "Unsupport " ~ T.stringof);
    }

    return result;
}


// Any below codes are private
private:

unittest // toInteger
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.toInteger");

    assert(toInteger!int("") == 0);
    assert(toInteger!int("", int.max) == int.max);
    assert(toInteger!int("1") == 1);
    assert(toInteger!int("98765432") == 98_765_432);
    assert(toInteger!int("-1") == -1);
    assert(toInteger!int("-8765324") == -8_765_324);
}

unittest // toString
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.toString");

    assert(toString('a') == "a");
    assert(toString(wchar('b')) == "b");
    assert(toString(dchar('c')) == "c");

    assert(toString("b"w) == "b");
    assert(toString("c"d) == "c");
}

unittest // uintEncode & uintDecode
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.uintEncode & uintDecode");

    // 16 bits
    auto b16 = uintEncode!(ushort, Endian.littleEndian)(ushort.min);
    auto u16 = uintDecode!(ushort, Endian.littleEndian)(b16);
    assert(u16 == ushort.min);

    b16 = uintEncode!(ushort, Endian.littleEndian)(ushort.max);
    u16 = uintDecode!(ushort, Endian.littleEndian)(b16);
    assert(u16 == ushort.max);

    b16 = uintEncode!(ushort, Endian.littleEndian)(0u);
    u16 = uintDecode!(ushort, Endian.littleEndian)(b16);
    assert(u16 == 0u);

    b16 = uintEncode!(ushort, Endian.littleEndian)(ushort.max / 3);
    u16 = uintDecode!(ushort, Endian.littleEndian)(b16);
    assert(u16 == ushort.max / 3);

    assert(uintEncode!(ushort, Endian.littleEndian)(0u) == uintEncode!(ushort, Endian.bigEndian)(0u));
    assert(uintEncode!(ushort, Endian.littleEndian)(ushort.max) == uintEncode!(ushort, Endian.bigEndian)(ushort.max));

    // 32 bits
    auto b32 = uintEncode!(uint, Endian.littleEndian)(uint.min);
    auto u32 = uintDecode!(uint, Endian.littleEndian)(b32);
    assert(u32 == uint.min);

    b32 = uintEncode!(uint, Endian.littleEndian)(uint.max);
    u32 = uintDecode!(uint, Endian.littleEndian)(b32);
    assert(u32 == uint.max);

    b32 = uintEncode!(uint, Endian.littleEndian)(0u);
    u32 = uintDecode!(uint, Endian.littleEndian)(b32);
    assert(u32 == 0u);

    b32 = uintEncode!(uint, Endian.littleEndian)(uint.max / 3);
    u32 = uintDecode!(uint, Endian.littleEndian)(b32);
    assert(u32 == uint.max / 3);

    assert(uintEncode!(uint, Endian.littleEndian)(0u) == uintEncode!(uint, Endian.bigEndian)(0u));
    assert(uintEncode!(uint, Endian.littleEndian)(uint.max) == uintEncode!(uint, Endian.bigEndian)(uint.max));

    // 64 bits
    auto b64 = uintEncode!(ulong, Endian.littleEndian)(ulong.min);
    auto u64 = uintDecode!(ulong, Endian.littleEndian)(b64);
    assert(u64 == ulong.min);

    b64 = uintEncode!(ulong, Endian.littleEndian)(ulong.max);
    u64 = uintDecode!(ulong, Endian.littleEndian)(b64);
    assert(u64 == ulong.max);

    b64 = uintEncode!(ulong, Endian.littleEndian)(0u);
    u64 = uintDecode!(ulong, Endian.littleEndian)(b64);
    assert(u64 == 0u);

    b64 = uintEncode!(ulong, Endian.littleEndian)(ulong.max / 3);
    u64 = uintDecode!(ulong, Endian.littleEndian)(b64);
    assert(u64 == ulong.max / 3);

    assert(uintEncode!(ulong, Endian.littleEndian)(0u) == uintEncode!(ulong, Endian.bigEndian)(0u));
    assert(uintEncode!(ulong, Endian.littleEndian)(ulong.max) == uintEncode!(ulong, Endian.bigEndian)(ulong.max));
}
