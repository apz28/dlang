/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2023 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_bit;

import std.bitmanip : bigEndianToNative, littleEndianToNative, nativeToBigEndian, nativeToLittleEndian, swapEndian;
import std.system : Endian;
import std.traits : Unqual, isIntegral, isNumeric, isSomeChar, isUnsigned;

nothrow @safe:

// i=1 ~ a=[1,0] (littleEndian)
union Map16Bit
{
    ushort u; // Make this first to have zero initialized value
    short i;
    ubyte[2] lh;
    ubyte[ushort.sizeof] a;
}
static assert(Map16Bit.sizeof == 2);

// i=1 ~ a=[1,0,0,0] (littleEndian)
union Map32Bit
{
    uint u; // Make this first to have zero initialized value
    int i;
    float f;
    ushort[2] lh;
    ubyte[uint.sizeof] a;
}
static assert(Map32Bit.sizeof == 4);

// i=1 ~ a=[1,0,0,0,0,0,0,0] (littleEndian)
union Map64Bit
{
    ulong u; // Make this first to have zero initialized value
    long i;
    double f;
    uint[2] lh;
    ubyte[ulong.sizeof] a;
}
static assert(Map64Bit.sizeof == 8);

template MapOf(T)
if (isIntegral!T)
{
    static if (T.sizeof == 2)
        alias MapOf = Map16Bit;
    else static if (T.sizeof == 4)
        alias MapOf = Map32Bit;
    else static if (T.sizeof == 8)
        alias MapOf = Map64Bit;
    else
        static assert(0);
}

alias MapSizeBit = MapOf!size_t;

pragma(inline, true)
bool bt(T)(scope const(T)[] p, const(size_t) index) @nogc pure
if (isUnsigned!T && T.sizeof <= 8)
{
    return (p[elementAt!T(index)] >> bitAt!T(index)) & 1u;
}

pragma(inline, true)
bool btc(T)(scope T* p, const(size_t) index) @nogc pure @system
if (isUnsigned!T && T.sizeof <= 8)
{
    const eat = elementAt!T(index);
    const bat = bitAt!T(index);
    const result = (p[eat] >> bat) & 1u;
    if (result)
        p[eat] &= flip!T(cast(T)(T(1u) << bat));
    else
        p[eat] |= cast(T)(T(1u) << bat);
    return result;
}

pragma(inline, true)
bool btr(T)(scope T* p, const(size_t) index) @nogc pure @system
if (isUnsigned!T && T.sizeof <= 8)
{
    const eat = elementAt!T(index);
    const bat = bitAt!T(index);
    const result = (p[eat] >> bat) & 1u;
    p[eat] &= flip!T(cast(T)(T(1u) << bat));
    return result;
}

pragma(inline, true)
bool bts(T)(scope T* p, const(size_t) index) @nogc pure @system
if (isUnsigned!T && T.sizeof <= 8)
{
    const eat = elementAt!T(index);
    const bat = bitAt!T(index);
    const result = (p[eat] >> bat) & 1u;
    p[eat] |= cast(T)(T(1u) << bat);
    return result;
}

pragma(inline, true)
private size_t bitAt(T)(const(size_t) index) @nogc pure
if (isUnsigned!T && T.sizeof <= 8)
{
    return index & (T.sizeof * 8 - 1);
}

/// Returns the minimum number of bits required to represent x; the result is 0 for x == 0.
pragma(inline, true)
uint bitLength(T)(const(T) x) @nogc pure
if (isUnsigned!T && T.sizeof <= 8)
{
    uint n = 0;
    Unqual!T ux = x;

    static if (T.sizeof >= 8)
    if (ux >= 1UL<<32)
    {
	    ux >>= 32;
	    n += 32;
    }

    static if (T.sizeof >= 4)
    if (ux >= 1U<<16)
    {
	    ux >>= 16;
	    n += 16;
    }

    static if (T.sizeof >= 2)
    if (ux >= 1U<<8)
    {
	    ux >>= 8;
	    n += 8;
    }

    assert(ux <= 0xFF);

    return n + len8Table[cast(ubyte)ux];
}

pragma(inline, true)
size_t bitLengthToElement(T)(size_t length) @nogc pure
if (isUnsigned!T)
{
    //return length > 0 ? (((length - 1) / BitsPerElement) + 1) : 0; // Safer for overflow
    static if (T.sizeof == 8)
        return (length + 63) >> 6; // "x >> 6" is "x / 64"
    else static if (T.sizeof == 4)
        return (length + 31) >> 5; // "x >> 5" is "x / 32"
    else static if (T.sizeof == 2)
        return (length + 15) >> 4; // "x >> 4" is "x / 16"
    else static if (T.sizeof == 1)
        return (length + 7) >> 3; // "x >> 3" is "x / 8"
    else
        static assert(0);
}

pragma(inline, true)
T bytesToNative(T)(scope const(ubyte)[] bytes) @nogc pure
if (isIntegral!T)
in
{
    assert(bytes.length >= T.sizeof);
}
do
{
    ubyte[T.sizeof] convertingBytes = bytes[0..T.sizeof];
    version(LittleEndian)
        return littleEndianToNative!T(convertingBytes);
    else
        return bigEndianToNative!T(convertingBytes);
}

pragma(inline, true)
T bytesToNative(T)(scope const(ubyte)[] bytes, const(Endian) fromEndian) @nogc pure
if (isIntegral!T)
in
{
    assert(bytes.length >= T.sizeof);
}
do
{
    ubyte[T.sizeof] convertingBytes = bytes[0..T.sizeof];
    return fromEndian == Endian.littleEndian
        ? littleEndianToNative!T(convertingBytes)
        : bigEndianToNative!T(convertingBytes);
}

pragma(inline, true)
auto nativeToBytes(T)(const(T) value) @nogc pure
if (isIntegral!T)
{
    version(LittleEndian)
        return nativeToLittleEndian!T(value);
    else
        return nativeToBigEndian!T(value);
}

pragma(inline, true)
auto nativeToBytes(T)(const(T) value, const(Endian) toEndian) @nogc pure
if (isIntegral!T)
{
    return toEndian == Endian.littleEndian
        ? nativeToLittleEndian!T(value)
        : nativeToBigEndian!T(value);
}

pragma(inline, true)
T hostToNetworkOrder(T)(const(T) host) @nogc pure
if (isIntegral!T || isSomeChar!T)
{
    version(BigEndian)
        return host;
    else
        return swapEndian!T(host);
}

pragma(inline, true)
T networkToHostOrder(T)(const(T) network) @nogc pure
if (isIntegral!T || isSomeChar!T)
{
    version(BigEndian)
        return network;
    else
        return swapEndian!T(network);
}

pragma(inline, true)
private size_t elementAt(T)(const(size_t) index) @nogc pure
if (isUnsigned!T && T.sizeof <= 8)
{
    return index / (T.sizeof * 8);
}

pragma(inline, true)
T flip(T)(T v) @nogc pure
if (isUnsigned!T)
{
    static if (T.sizeof < size_t.sizeof)
        return cast(T)(~(cast(size_t)v));
    else
        return ~v;
}

pragma(inline, true)
auto fromBytes(T)(scope const(ubyte)[] value) @nogc pure
if (isIntegral!T)
{
    MapOf!T map = { a:value[0..T.sizeof] };
    return map.u;
}

/**
 * Returns the byte of x at byteIndex
 * Params:
 *  x = the value to extract from
 *  byteIndex = which ubyte to extract; ubyte at 0 is highest ubyte
 */
pragma(inline, true)
ubyte getByteAt(T)(const(T) x, size_t byteIndex) @nogc pure
if (isUnsigned!T)
in
{
    assert(byteIndex < T.sizeof);
}
do
{
    return cast(ubyte)(x >> (byteIndex << 3));
}

/// Return the position of the highest set bit in x
pragma(inline, true)
uint highestBit(T)(const(T) x) @nogc pure
if (isUnsigned!T && T.sizeof <= 8)
{
    if (x == 0)
        return 0;
    else
    {
        uint n = 0;
        Unqual!T ux = x;

        static if (T.sizeof >= 8)
        if (ux >= 1UL<<32)
        {
	        ux >>= 32;
	        n += 32;
        }

        static if (T.sizeof >= 4)
        if (ux >= 1U<<16)
        {
	        ux >>= 16;
	        n += 16;
        }

        static if (T.sizeof >= 2)
        if (ux >= 1U<<8)
        {
	        ux >>= 8;
	        n += 8;
        }

        assert(ux <= 0xFF);

        return n + hbt8Table[cast(ubyte)ux];
    }

    version(none)
    {
        if (x != 0)
        {
            enum bits = T.sizeof * 8;
            foreach (i; 0..bits)
            {
                const j = bits - i - 1;
                if ((x >> j) & 0x01)
                    return j + 1;
            }
        }
        return 0;
    }
}

/// Return the position of the lowest set bit in x
pragma(inline, true)
uint lowestBit(T)(const(T) x) @nogc pure
if (isUnsigned!T)
{
    if (x == 0)
        return 0;
    else
    {
        uint n = 0;
        Unqual!T ux = x;

        static if (T.sizeof >= 8)
        if ((ux & 0xFFFF_FFFF) == 0)
        {
	        ux >>= 32;
	        n += 32;
        }

        static if (T.sizeof >= 4)
        if ((ux & 0xFFFF) == 0)
        {
	        ux >>= 16;
	        n += 16;
        }

        static if (T.sizeof >= 2)
        if ((ux & 0xFF) == 0)
        {
	        ux >>= 8;
	        n += 8;
        }

        assert(ux <= 0xFF);

        return n + lbt8Table[cast(ubyte)ux];
    }

    version(none)
    {
        if (x != 0)
        {
            enum bits = T.sizeof * 8;
            foreach (i; 0..bits)
            {
                if ((x >> i) & 0x01)
                    return i + 1;
            }
        }
        return 0;
    }
}

/// Bit cast without any float/interger conversion/promotion
pragma(inline, true)
To numericBitCast(To, From)(const(From) from) @nogc pure @trusted
if (From.sizeof == To.sizeof && isNumeric!From && isNumeric!To)
{
    return *cast(To*)(&from);
}

/// Return the number of significant bytes in x; the result is 0 for x == 0.
uint significantByteLength(T)(const(T) x) @nogc pure
if (isUnsigned!T && T.sizeof <= 8)
{
    static if (T.sizeof >= 8)
    {
        if ((x & 0xFF00_0000_0000_0000) != 0)
            return 8;
        else if ((x & 0x00FF_0000_0000_0000) != 0)
            return 7;
        else if ((x & 0x0000_FF00_0000_0000) != 0)
            return 6;
        else if ((x & 0x0000_00FF_0000_0000) != 0)
            return 5;
    }

    static if (T.sizeof >= 4)
    {
        if ((x & 0xFF00_0000) != 0)
            return 4;
        else if ((x & 0x00FF_0000) != 0)
            return 3;
    }

    static if (T.sizeof >= 2)
    {
        if ((x & 0xFF00) != 0)
            return 2;
    }

    return x != 0 ? 1 : 0;
}

pragma(inline, true)
auto toBytes(T)(const(T) value) @nogc pure
if (isIntegral!T)
{
    MapOf!T map = { u:value };
    return map.a;
}

/// Returns the number of trailing zero bits in x; the result is T.sizeof*8 for x == 0
pragma(inline, true)
uint trailingZeroBits(T)(const(T) x) @nogc pure
if (isUnsigned!T && T.sizeof <= 8)
{
    static if (T.sizeof == 8)
        return x == 0 ? 64 : deBruijn64tab[(x&-x) * deBruijn64>>(64-6)];
    else static if (T.sizeof == 4)
        return x == 0 ? 32 : deBruijn32tab[(x&-x) * deBruijn32>>(32-5)];
    else static if (T.sizeof == 2)
    {
        const uint x2 = x;
        return x2 == 0 ? 16 : deBruijn32tab[(x2&-x2) * deBruijn32>>(32-5)];
    }
    else static if (T.sizeof == 1)
        return ntz8Table[x];
    else
        static assert(0, "Unsupport system for " ~ __FUNCTION__ ~ "." ~ T.stringof);
}


private:

enum deBruijn32 = 0x077CB531;

static immutable ubyte[] deBruijn32tab = [
	0, 1, 28, 2, 29, 14, 24, 3, 30, 22, 20, 15, 25, 17, 4, 8,
	31, 27, 13, 23, 21, 19, 16, 7, 26, 12, 18, 6, 11, 5, 10, 9,
    ];

const deBruijn64 = 0x03f79d71b4ca8b09;

static immutable ubyte[] deBruijn64tab = [
	0, 1, 56, 2, 57, 49, 28, 3, 61, 58, 42, 50, 38, 29, 17, 4,
	62, 47, 59, 36, 45, 43, 51, 22, 53, 39, 33, 30, 24, 18, 12, 5,
	63, 55, 48, 27, 60, 41, 37, 16, 46, 35, 44, 21, 52, 32, 23, 11,
	54, 26, 40, 15, 34, 20, 31, 10, 25, 14, 19, 9, 13, 8, 7, 6,
    ];

static immutable char[] len8Table =
	"\x00\x01\x02\x02\x03\x03\x03\x03\x04\x04\x04\x04\x04\x04\x04\x04" ~  // 16 items per line
	"\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05" ~
	"\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06" ~
	"\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06" ~
	"\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07" ~
	"\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07" ~
	"\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07" ~
	"\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07" ~
	"\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
	"\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
	"\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
	"\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
	"\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
	"\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
	"\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
	"\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08";

static immutable char[] hbt8Table =
    "\x00\x01\x02\x02\x03\x03\x03\x03\x04\x04\x04\x04\x04\x04\x04\x04" ~ // 16 items per line
    "\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05" ~
    "\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06" ~
    "\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06\x06" ~
    "\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07" ~
    "\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07" ~
    "\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07" ~
    "\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07" ~
    "\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
    "\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
    "\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
    "\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
    "\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
    "\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
    "\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08" ~
    "\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08\x08";

static immutable char[] lbt8Table =
    "\x00\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~ // 16 items per line
    "\x05\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x06\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x05\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x07\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x05\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x06\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x05\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x08\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x05\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x06\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x05\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x07\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x05\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x06\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01" ~
    "\x05\x01\x02\x01\x03\x01\x02\x01\x04\x01\x02\x01\x03\x01\x02\x01";

static immutable char[] ntz8Table =
	"\x08\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~ // 16 items per line
	"\x04\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x05\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x04\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x06\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x04\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x05\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x04\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x07\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x04\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x05\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x04\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x06\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x04\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x05\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00" ~
	"\x04\x00\x01\x00\x02\x00\x01\x00\x03\x00\x01\x00\x02\x00\x01\x00";

@safe unittest // bitAt & elementAt
{
    assert(bitAt!ubyte(0) == 0);
    assert(bitAt!ubyte(1) == 1);
    assert(bitAt!ubyte(7) == 7);
    assert(bitAt!ubyte(8) == 0);
    assert(bitAt!ubyte(15) == 7);
    assert(elementAt!ubyte(0) == 0);
    assert(elementAt!ubyte(1) == 0);
    assert(elementAt!ubyte(7) == 0);
    assert(elementAt!ubyte(8) == 1);
    assert(elementAt!ubyte(15) == 1);

    assert(bitAt!uint(0) == 0);
    assert(bitAt!uint(1) == 1);
    assert(bitAt!uint(31) == 31);
    assert(bitAt!uint(32) == 0);
    assert(bitAt!uint(63) == 31);
    assert(elementAt!uint(0) == 0);
    assert(elementAt!uint(1) == 0);
    assert(elementAt!uint(31) == 0);
    assert(elementAt!uint(32) == 1);
    assert(elementAt!uint(63) == 1);

    assert(bitAt!ulong(0) == 0);
    assert(bitAt!ulong(1) == 1);
    assert(bitAt!ulong(63) == 63);
    assert(bitAt!ulong(64) == 0);
    assert(bitAt!ulong(127) == 63);
    assert(elementAt!ulong(0) == 0);
    assert(elementAt!ulong(1) == 0);
    assert(elementAt!ulong(63) == 0);
    assert(elementAt!ulong(64) == 1);
    assert(elementAt!ulong(127) == 1);
}

nothrow @safe unittest // bitLength
{
    assert(bitLength(cast(ubyte)0) == 0);
    assert(bitLength(cast(ushort)0) == 0);
    assert(bitLength(cast(uint)0) == 0);
    assert(bitLength(cast(ulong)0) == 0);

    assert(bitLength(cast(ubyte)8) == 4);
    assert(bitLength(cast(ushort)8) == 4);
    assert(bitLength(cast(uint)8) == 4);
    assert(bitLength(cast(ulong)8) == 4);

    assert(bitLength(ubyte.max) == 8);
    assert(bitLength(ushort.max) == 16);
    assert(bitLength(uint.max) == 32);
    assert(bitLength(ulong.max) == 64);

    assert(bitLength(cast(ubyte)0x80) == 8);
    assert(bitLength(cast(ushort)0x8000) == 16);
    assert(bitLength(cast(uint)0x80000000) == 32);
    assert(bitLength(cast(ulong)0x8000000000000000) == 64);
}

@safe unittest // flip
{
    assert(flip!ubyte(0) == ubyte.max);
    assert(flip!ubyte(ubyte.max) == 0);
    assert(flip!ubyte(1) == 0xFE);

    assert(flip!ushort(0) == ushort.max);
    assert(flip!ushort(ushort.max) == 0);
    assert(flip!ushort(1) == 0xFFFE);

    assert(flip!uint(0) == uint.max);
    assert(flip!uint(uint.max) == 0);
    assert(flip!uint(1) == 0xFFFF_FFFE);

    assert(flip!ulong(0) == ulong.max);
    assert(flip!ulong(ulong.max) == 0);
    assert(flip!ulong(1) == 0xFFFFFFFF_FFFFFFFE);
}

nothrow @safe unittest // getByteAt
{
    assert(getByteAt(cast(ubyte)0x0, 0) == 0x0);
    assert(getByteAt(cast(ubyte)0x01, 0) == 0x01);
    assert(getByteAt(cast(ushort)0x23FF, 0) == 0xFF);
    assert(getByteAt(cast(ushort)0x23FF, 1) == 0x23);
    assert(getByteAt(cast(uint)0x23AB_1234, 2) == 0xAB);
    assert(getByteAt(cast(uint)0x23AB_1234, 3) == 0x23);
    assert(getByteAt(cast(ulong)0x23AB_1234_5678_1234, 6) == 0xAB);
    assert(getByteAt(cast(ulong)0x23AB_1234_5678_1234, 7) == 0x23);
}

@system unittest // bt
{
    {
        size_t[2] array;
        array[0] = 0x2;
        array[1] = 0x0100;

        assert(bt(array, 1));
        assert(array[0] == 0x2);
        assert(array[1] == 0x0100);
    }
}

@system unittest // btc
{
    {
        size_t[2] array;
        array[0] = 0x2;
        array[1] = 0x0100;

        assert(btc(array.ptr, 35) == 0);
        if (size_t.sizeof == 8)
        {
            assert(array[0] == 0x0008_0000_0002);
            assert(array[1] == 0x0100);
        }
        else
        {
            assert(array[0] == 0x2);
            assert(array[1] == 0x0108);
        }

        assert(btc(array.ptr, 35));
        assert(array[0] == 0x2);
        assert(array[1] == 0x0100);
    }
}

@system unittest // btr
{
    {
        size_t[2] array;
        array[0] = 0x2;
        array[1] = 0x0100;

        assert(bts(array.ptr, 35) == 0);
        if (size_t.sizeof == 8)
        {
            assert(array[0] == 0x0008_0000_0002);
            assert(array[1] == 0x0100);
        }
        else
        {
            assert(array[0] == 2);
            assert(array[1] == 0x0108);
        }

        assert(btr(array.ptr, 35));
        assert(array[0] == 2);
        assert(array[1] == 0x0100);
    }
}

nothrow @safe unittest // highestBit
{
    assert(highestBit(cast(ubyte)0) == 0);
    assert(highestBit(cast(ushort)0) == 0);
    assert(highestBit(cast(uint)0) == 0);
    assert(highestBit(cast(ulong)0) == 0);

    assert(highestBit(cast(ubyte)1) == 1);
    assert(highestBit(cast(ushort)1) == 1);
    assert(highestBit(cast(uint)1) == 1);
    assert(highestBit(cast(ulong)1) == 1);

    assert(highestBit(cast(ubyte)0x40) == 7);
    assert(highestBit(cast(ushort)0x4000) == 15);
    assert(highestBit(cast(uint)0x4000_0000) == 31);
    assert(highestBit(cast(ulong)0x4000_0000_0000_0000) == 63);

    assert(highestBit(cast(ubyte)0x80) == 8);
    assert(highestBit(cast(ushort)0x8000) == 16);
    assert(highestBit(cast(uint)0x8000_0000) == 32);
    assert(highestBit(cast(ulong)0x8000_0000_0000_0000) == 64);
}

nothrow @safe unittest // lowestBit
{
    assert(lowestBit(cast(ubyte)0) == 0);
    assert(lowestBit(cast(ushort)0) == 0);
    assert(lowestBit(cast(uint)0) == 0);
    assert(lowestBit(cast(ulong)0) == 0);

    assert(lowestBit(cast(ubyte)1) == 1);
    assert(lowestBit(cast(ushort)1) == 1);
    assert(lowestBit(cast(uint)1) == 1);
    assert(lowestBit(cast(ulong)1) == 1);

    assert(lowestBit(cast(ubyte)0x2) == 2);
    assert(lowestBit(cast(ushort)0x2) == 2);
    assert(lowestBit(cast(uint)0x2) == 2);
    assert(lowestBit(cast(ulong)0x2) == 2);

    assert(lowestBit(cast(ubyte)0x80) == 8);
    assert(lowestBit(cast(ushort)0x8000) == 16);
    assert(lowestBit(cast(uint)0x8000_0000) == 32);
    assert(lowestBit(cast(ulong)0x8000_0000_0000_0000) == 64);
}

unittest // numericBitCast
{
    float f;
    int i;
    uint u;

    i = -1;
    u = numericBitCast!uint(i);
    assert(numericBitCast!int(u) == i);

    u = 2_147_483_648U;
    i = numericBitCast!int(u);
    assert(numericBitCast!uint(i) == u);

    f = 23_820.654;
    u = numericBitCast!uint(f);
    assert(numericBitCast!float(u) == f);
}

nothrow @safe unittest // significantByteLength
{
    assert(significantByteLength(cast(ubyte)0x0) == 0);
    assert(significantByteLength(cast(ushort)0x0) == 0);
    assert(significantByteLength(cast(uint)0x0) == 0);
    assert(significantByteLength(cast(ulong)0x0) == 0);

    assert(significantByteLength(cast(ubyte)0x1) == 1);
    assert(significantByteLength(cast(ushort)0x1) == 1);
    assert(significantByteLength(cast(uint)0x1) == 1);
    assert(significantByteLength(cast(ulong)0x1) == 1);

    assert(significantByteLength(cast(ushort)0x0100) == 2);
    assert(significantByteLength(cast(uint)0x0100_0000) == 4);
    assert(significantByteLength(cast(ulong)0x0100_0000_0000) == 6);
}

nothrow @safe unittest // trailingZeroBits
{
    assert(trailingZeroBits(cast(ubyte)0) == 8);
    assert(trailingZeroBits(cast(ushort)0) == 16);
    assert(trailingZeroBits(cast(uint)0) == 32);
    assert(trailingZeroBits(cast(ulong)0) == 64);

    assert(trailingZeroBits(cast(ubyte)1) == 0);
    assert(trailingZeroBits(cast(ushort)1) == 0);
    assert(trailingZeroBits(cast(uint)1) == 0);
    assert(trailingZeroBits(cast(ulong)1) == 0);

    assert(trailingZeroBits(cast(ubyte)ubyte.max) == 0);
    assert(trailingZeroBits(cast(ushort)ushort.max) == 0);
    assert(trailingZeroBits(cast(uint)uint.max) == 0);
    assert(trailingZeroBits(cast(ulong)ulong.max) == 0);

    assert(trailingZeroBits(cast(ubyte)120) == 3);
    assert(trailingZeroBits(cast(ushort)7600) == 4);
    assert(trailingZeroBits(cast(uint)8_7625_4900) == 2);
    assert(trailingZeroBits(cast(ulong)9_2751_8464_8599_8600) == 3);
}
